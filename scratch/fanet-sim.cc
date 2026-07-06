/* -*- Mode:C++; c-file-style:"gnu"; indent-tabs-mode:nil; -*- */
/**
 * FANET simulation for routing protocol comparison.
 * Compatible với cả ns-3.40 và ns-3.42.
 *
 * Protocols: AODV, DSDV, DSR, PMAODV (custom), AOMDV (custom)
 * Mobility:  GAUSS (3D, default) hoặc RWP (2D, paper-style)
 * Energy:    BasicEnergySource + WifiRadioEnergyModel (optional)
 * Metrics:   delivery, delay, throughput, routing-overhead, energy
 */

#include "ns3/core-module.h"
#include "ns3/network-module.h"
#include "ns3/internet-module.h"
#include "ns3/wifi-module.h"
#include "ns3/mobility-module.h"
#include "ns3/applications-module.h"
#include "ns3/flow-monitor-module.h"
#include "ns3/energy-module.h"
#include "ns3/aodv-module.h"
#include "ns3/dsdv-module.h"
#include "ns3/dsr-module.h"
#include "ns3/pmaodv-module.h"
#include "ns3/aomdv-module.h"
#include "ns3/qmaodv-module.h"
#include "ns3/saqmaodv-module.h"
#include "ns3/eaqmaodv-module.h"

#include <iostream>
#include <fstream>
#include <iomanip>
#include <set>
#include <vector>
#include <sys/stat.h>

using namespace ns3;
// NS-3.40: EnergySourceContainer/DeviceEnergyModelContainer nằm trong ns3:: trực tiếp
// (ns3::energy namespace chỉ có từ NS-3.42 trở đi)

NS_LOG_COMPONENT_DEFINE("FanetSim");

struct OverheadCounter
{
  uint64_t ipTxPackets = 0;
  void OnIpTx(Ptr<const Packet>, Ptr<Ipv4>, uint32_t)
  {
    ++ipTxPackets;
  }
};


int main(int argc, char *argv[])
{
  // ====== Parameters ======
  std::string protocol      = "AODV";
  uint32_t    maxPaths      = 3;
  std::string mobility      = "GAUSS";
  uint32_t    numNodes      = 10;
  double      simTime       = 200.0;
  uint32_t    seed          = 1;
  double      initialEnergyJ = 50.0;
  double      energyStdDev  = 0.0;   ///< 0 = uniform; >0 = heterogeneous energy
  double      txPowerDbm    = 16.0;
  double      areaX         = 1000.0;
  double      areaY         = 1000.0;
  double      areaZ         = 300.0;
  double      alpha         = 0.85;
  double      meanVelMin    = 15.0;
  double      meanVelMax    = 25.0;
  uint32_t    pktSize       = 512;
  double      pktInterval   = 0.25;
  std::string csvFile       = "results.csv";
  bool        enableEnergy  = true;
  // === Stress scenario controls ===
  uint32_t    numFlows      = 0;        // 0 = N-1 sources -> sink 0 (default).
                                        // >0 = numFlows independent (src,dst) pairs.
  std::string scenario      = "default"; // tag for CSV output

  // === QMAODV Q-learning hyper-parameters (paper Table 3) ===
  double      qmAlpha       = 0.5;      // Q-learning learning rate
  double      qmGamma       = 0.9;      // Discount factor
  double      qmEpsilon     = 0.5;      // Initial exploration rate
  double      qmW1          = 0.6;      // Reward weight: ACK_success
  double      qmW2          = 0.4;      // Reward weight: 1/(delay+1)
  double      qmEpsilonDecay = 0.02;    // ε-decay amount per period
  double      qmDecayPeriod = 10.0;     // ε-decay period (s)

  // === SA-QMAODV Self-Adaptive hyper-parameters (paper Table 1) ===
  double      saAlpha0      = 0.5;      // initial α (will adapt)
  double      saGamma       = 0.9;      // discount (fixed in paper)
  double      saEpsilon0    = 0.3;      // initial ε (will adapt)
  double      saW1          = 0.5;      // initial reward weight ACK
  double      saW2          = 0.4;      // initial reward weight 1/(delay+1)
  double      saW3          = 0.1;      // initial reward weight Energy
  double      saLambda      = 0.1;      // λ in α_t formula (§4.3)
  double      saSeqNoWin    = 5.0;      // Δ_Seq window (s)
  double      saLowEThresh  = 0.20;     // low-energy threshold (fraction)
  double      saAdaptPeriod = 10.0;     // periodic adaptive tick (s)

  // === EA-QMAODV Queue-State Self-Adaptive hyper-parameters ===
  double      eaAlpha0          = 0.5;   // initial α (will adapt)
  double      eaGamma           = 0.9;   // discount (fixed)
  double      eaEpsilon0        = 0.3;   // initial ε (will adapt)
  double      eaW1              = 0.40;  // reward weight ACK            (Normal §4.2)
  double      eaW2              = 0.30;  // reward weight 1/(delay+1)
  double      eaW3              = 0.10;  // reward weight Energy
  double      eaW4              = 0.20;  // reward weight 1/(queue+1)    (Normal §4.2)
  double      eaMu              = 0.10;  // μ: EMA smoothing factor for TD-error
  double      eaKappa           = 0.50;  // κ: saturation constant (Eq.2c)
  double      eaSeqNoWin        = 5.0;   // Δ_Seq window (s)
  double      eaLowEThresh      = 0.20;  // low-energy threshold
  double      eaQueueHighThresh = 0.70;  // queue HIGH_LOAD entry threshold (§4.3)
  double      eaQueueLowThresh  = 0.30;  // queue HIGH_LOAD exit  threshold [NEW]
  double      eaAdaptPeriod     = 10.0;  // periodic adaptive tick (s)

  CommandLine cmd(__FILE__);
  cmd.AddValue("protocol",       "Routing protocol (AODV|DSDV|DSR|PMAODV|AOMDV|QMAODV|SAQMAODV|EAQMAODV)", protocol);
  cmd.AddValue("maxPaths",       "PMAODV/AOMDV/QMAODV/SAQMAODV/EAQMAODV max paths per destination", maxPaths);
  cmd.AddValue("mobility",       "Mobility model (GAUSS|RWP)",                   mobility);
  cmd.AddValue("numNodes",       "Number of UAV nodes",                          numNodes);
  cmd.AddValue("simTime",        "Simulation time (s)",                          simTime);
  cmd.AddValue("seed",           "RNG seed (run id)",                            seed);
  cmd.AddValue("initialEnergy",  "Initial energy per node (J)",                  initialEnergyJ);
  cmd.AddValue("energyStdDev",  "StdDev for heterogeneous energy (0=uniform)",   energyStdDev);
  cmd.AddValue("txPowerDbm",     "Tx power (dBm)",                               txPowerDbm);
  cmd.AddValue("alpha",          "GaussMarkov alpha (0..1, lower=more random)",  alpha);
  cmd.AddValue("meanVelMin",     "Min UAV velocity (m/s)",                       meanVelMin);
  cmd.AddValue("meanVelMax",     "Max UAV velocity (m/s)",                       meanVelMax);
  cmd.AddValue("pktSize",        "UDP payload size (bytes)",                     pktSize);
  cmd.AddValue("pktInterval",    "Packet interval per source (s)",               pktInterval);
  cmd.AddValue("numFlows",       "0=all sources->sink0 (default); >0=N pairs",   numFlows);
  cmd.AddValue("scenario",       "Scenario tag for CSV (default|stress-mob|stress-load|multi-flow)", scenario);
  cmd.AddValue("areaX",          "Area X dimension (m)",                         areaX);
  cmd.AddValue("areaY",          "Area Y dimension (m)",                         areaY);
  cmd.AddValue("areaZ",          "Area Z dimension (m, 3D only)",                areaZ);
  cmd.AddValue("enableEnergy",   "Enable energy model (1/0)",                    enableEnergy);
  cmd.AddValue("csvFile",        "Output CSV file",                              csvFile);
  // QMAODV Q-learning controls
  cmd.AddValue("qmAlpha",        "QMAODV Q-learning rate α (0..1)",              qmAlpha);
  cmd.AddValue("qmGamma",        "QMAODV discount factor γ (0..1)",              qmGamma);
  cmd.AddValue("qmEpsilon",      "QMAODV initial ε for ε-greedy",                qmEpsilon);
  cmd.AddValue("qmW1",           "QMAODV reward weight for ACK_success",         qmW1);
  cmd.AddValue("qmW2",           "QMAODV reward weight for 1/(delay+1)",         qmW2);
  cmd.AddValue("qmEpsilonDecay", "QMAODV ε decrement per period",                qmEpsilonDecay);
  cmd.AddValue("qmDecayPeriod",  "QMAODV ε-decay period (s)",                    qmDecayPeriod);
  // SA-QMAODV Self-Adaptive controls
  cmd.AddValue("saAlpha0",       "SA-QMAODV initial α (will adapt)",             saAlpha0);
  cmd.AddValue("saGamma",        "SA-QMAODV discount factor γ (fixed)",          saGamma);
  cmd.AddValue("saEpsilon0",     "SA-QMAODV initial ε (will adapt)",             saEpsilon0);
  cmd.AddValue("saW1",           "SA-QMAODV reward weight ACK",                  saW1);
  cmd.AddValue("saW2",           "SA-QMAODV reward weight 1/(delay+1)",          saW2);
  cmd.AddValue("saW3",           "SA-QMAODV reward weight Energy",               saW3);
  cmd.AddValue("saLambda",       "SA-QMAODV sensitivity λ in α_t formula",       saLambda);
  cmd.AddValue("saSeqNoWin",     "SA-QMAODV Δ_Seq window (s)",                   saSeqNoWin);
  cmd.AddValue("saLowEThresh",   "SA-QMAODV low-energy threshold (fraction)",    saLowEThresh);
  cmd.AddValue("saAdaptPeriod",  "SA-QMAODV periodic adaptive tick (s)",         saAdaptPeriod);
  // EA-QMAODV Queue-State controls
  cmd.AddValue("eaAlpha0",          "EA-QMAODV initial α (will adapt)",              eaAlpha0);
  cmd.AddValue("eaGamma",           "EA-QMAODV discount factor γ (fixed)",           eaGamma);
  cmd.AddValue("eaEpsilon0",        "EA-QMAODV initial ε (will adapt)",              eaEpsilon0);
  cmd.AddValue("eaW1",              "EA-QMAODV reward weight ACK",                   eaW1);
  cmd.AddValue("eaW2",              "EA-QMAODV reward weight 1/(delay+1)",           eaW2);
  cmd.AddValue("eaW3",              "EA-QMAODV reward weight Energy",                eaW3);
  cmd.AddValue("eaW4",              "EA-QMAODV reward weight 1/(queue+1) [NEW]",     eaW4);
  cmd.AddValue ("eaMu", "EAQMAODV TD-error EMA smoothing mu", eaMu);
  cmd.AddValue ("eaKappa", "EAQMAODV TD-error saturation kappa", eaKappa);
  cmd.AddValue("eaSeqNoWin",        "EA-QMAODV Δ_Seq window (s)",                    eaSeqNoWin);
  cmd.AddValue("eaLowEThresh",      "EA-QMAODV low-energy threshold (fraction)",     eaLowEThresh);
  cmd.AddValue("eaQueueHighThresh", "EA-QMAODV queue HIGH_LOAD entry threshold",     eaQueueHighThresh);
  cmd.AddValue("eaQueueLowThresh",  "EA-QMAODV queue HIGH_LOAD exit  threshold",     eaQueueLowThresh);
  cmd.AddValue("eaAdaptPeriod",     "EA-QMAODV periodic adaptive tick (s)",          eaAdaptPeriod);
  cmd.Parse(argc, argv);

  RngSeedManager::SetSeed(1);
  RngSeedManager::SetRun(seed);

  std::cout << "=== FANET sim ===  protocol=" << protocol;
  if (protocol == "PMAODV" || protocol == "AOMDV" || protocol == "QMAODV" ||
      protocol == "SAQMAODV" || protocol == "EAQMAODV")
    std::cout << "(maxPaths=" << maxPaths << ")";
  if (protocol == "QMAODV")
    std::cout << "(α=" << qmAlpha << " γ=" << qmGamma << " ε=" << qmEpsilon << ")";
  if (protocol == "SAQMAODV")
    std::cout << "(α0=" << saAlpha0 << " γ=" << saGamma << " ε0=" << saEpsilon0
              << " w=(" << saW1 << "," << saW2 << "," << saW3 << ")"
              << " λ=" << saLambda << ")";
  if (protocol == "EAQMAODV")
    std::cout << "(α0=" << eaAlpha0 << " γ=" << eaGamma << " ε0=" << eaEpsilon0
              << " w=(" << eaW1 << "," << eaW2 << "," << eaW3 << "," << eaW4 << ")"
              << " mu=" << eaMu << " kappa=" << eaKappa
              << " Qhi=" << eaQueueHighThresh << " Qlo=" << eaQueueLowThresh << ")";
  std::cout << "  mob=" << mobility
            << "  N=" << numNodes
            << "  T=" << simTime << "s"
            << "  seed=" << seed
            << "  E0=" << initialEnergyJ << "J" << std::endl;

  // ====== Nodes ======
  NodeContainer nodes;
  nodes.Create(numNodes);

  // ====== WiFi 802.11b ad-hoc ======
  WifiHelper wifi;
  wifi.SetStandard(WIFI_STANDARD_80211b);
  wifi.SetRemoteStationManager("ns3::ConstantRateWifiManager",
                               "DataMode",    StringValue("DsssRate11Mbps"),
                               "ControlMode", StringValue("DsssRate1Mbps"));

  YansWifiPhyHelper wifiPhy;
  wifiPhy.Set("TxPowerStart", DoubleValue(txPowerDbm));
  wifiPhy.Set("TxPowerEnd",   DoubleValue(txPowerDbm));

  YansWifiChannelHelper wifiChannel;
  wifiChannel.SetPropagationDelay("ns3::ConstantSpeedPropagationDelayModel");
  wifiChannel.AddPropagationLoss("ns3::FriisPropagationLossModel");
  wifiPhy.SetChannel(wifiChannel.Create());

  WifiMacHelper wifiMac;
  wifiMac.SetType("ns3::AdhocWifiMac",
                  "QosSupported", BooleanValue(true));  // enable EDCA/BE_Txop for queue-state sensing
  NetDeviceContainer devices = wifi.Install(wifiPhy, wifiMac, nodes);

  // ====== Mobility ======
  MobilityHelper mob;
  std::ostringstream velStr;
  velStr << "ns3::UniformRandomVariable[Min=" << meanVelMin
         << "|Max=" << meanVelMax << "]";
  std::ostringstream xStr, yStr, zStr;
  xStr << "ns3::UniformRandomVariable[Min=0|Max=" << areaX << "]";
  yStr << "ns3::UniformRandomVariable[Min=0|Max=" << areaY << "]";
  zStr << "ns3::UniformRandomVariable[Min=0|Max=" << areaZ << "]";

  if (mobility == "GAUSS") {
    mob.SetPositionAllocator(
        "ns3::RandomBoxPositionAllocator",
        "X", StringValue(xStr.str()),
        "Y", StringValue(yStr.str()),
        "Z", StringValue(zStr.str()));
    mob.SetMobilityModel(
        "ns3::GaussMarkovMobilityModel",
        "Bounds",          BoxValue(Box(0, areaX, 0, areaY, 0, areaZ)),
        "TimeStep",        TimeValue(Seconds(0.5)),
        "Alpha",           DoubleValue(alpha),
        "MeanVelocity",    StringValue(velStr.str()),
        "MeanDirection",   StringValue("ns3::UniformRandomVariable[Min=0|Max=6.283185307]"),
        "MeanPitch",       StringValue("ns3::UniformRandomVariable[Min=-0.05|Max=0.05]"),
        "NormalVelocity",  StringValue("ns3::NormalRandomVariable[Mean=0.0|Variance=1.0|Bound=2.0]"),
        "NormalDirection", StringValue("ns3::NormalRandomVariable[Mean=0.0|Variance=0.2|Bound=0.4]"),
        "NormalPitch",     StringValue("ns3::NormalRandomVariable[Mean=0.0|Variance=0.02|Bound=0.04]"));
  }
  else if (mobility == "RWP") {
    mob.SetPositionAllocator(
        "ns3::RandomRectanglePositionAllocator",
        "X", StringValue(xStr.str()),
        "Y", StringValue(yStr.str()));
    mob.SetMobilityModel(
        "ns3::RandomWaypointMobilityModel",
        "Speed", StringValue(velStr.str()),
        "Pause", StringValue("ns3::ConstantRandomVariable[Constant=0.0]"),
        "PositionAllocator",
        PointerValue(CreateObjectWithAttributes<RandomRectanglePositionAllocator>(
            "X", StringValue(xStr.str()),
            "Y", StringValue(yStr.str()))));
  }
  else {
    NS_FATAL_ERROR("Unknown mobility: " << mobility << " (GAUSS|RWP)");
  }
  mob.Install(nodes);

  // ====== Internet stack + routing + energy ======
  Ipv4InterfaceContainer interfaces;
  EnergySourceContainer sources;
  DeviceEnergyModelContainer deviceModels;

  auto installEnergy = [&]() {
    if (!enableEnergy) return;
    if (energyStdDev <= 0.0) {
      // Uniform energy — all nodes same initial energy
      BasicEnergySourceHelper esHelper;
      esHelper.Set("BasicEnergySourceInitialEnergyJ", DoubleValue(initialEnergyJ));
      sources = esHelper.Install(nodes);
    } else {
      // Heterogeneous energy — per-node Gaussian draw, clipped to [5, 3*mean]
      Ptr<NormalRandomVariable> rng = CreateObject<NormalRandomVariable>();
      rng->SetAttribute("Mean",     DoubleValue(initialEnergyJ));
      rng->SetAttribute("Variance", DoubleValue(energyStdDev * energyStdDev));
      for (uint32_t i = 0; i < nodes.GetN(); ++i) {
        double e0 = rng->GetValue();
        e0 = std::max(5.0, std::min(e0, 3.0 * initialEnergyJ));
        BasicEnergySourceHelper esHelper;
        esHelper.Set("BasicEnergySourceInitialEnergyJ", DoubleValue(e0));
        sources.Add(esHelper.Install(nodes.Get(i)));
      }
    }
    WifiRadioEnergyModelHelper wifiEnergyHelper;
    deviceModels = wifiEnergyHelper.Install(devices, sources);
  };

  if (protocol == "AODV" || protocol == "DSDV" ||
      protocol == "PMAODV" || protocol == "AOMDV" ||
      protocol == "QMAODV" || protocol == "SAQMAODV" ||
      protocol == "EAQMAODV") {
    InternetStackHelper internet;
    if (protocol == "AODV") {
      AodvHelper aodv;
      internet.SetRoutingHelper(aodv);
    } else if (protocol == "DSDV") {
      DsdvHelper dsdv;
      internet.SetRoutingHelper(dsdv);
    } else if (protocol == "PMAODV") {
      PmaodvHelper pmaodv;
      pmaodv.Set("MaxPaths", UintegerValue(maxPaths));
      internet.SetRoutingHelper(pmaodv);
    } else if (protocol == "AOMDV") {
      AomdvHelper aomdv;
      aomdv.Set("MaxPaths", UintegerValue(maxPaths));
      internet.SetRoutingHelper(aomdv);
    } else if (protocol == "QMAODV") {
      QmaodvHelper qmaodv;
      qmaodv.Set("MaxPaths",           UintegerValue(maxPaths));
      qmaodv.Set("Alpha",              DoubleValue(qmAlpha));
      qmaodv.Set("Gamma",              DoubleValue(qmGamma));
      qmaodv.Set("Epsilon",            DoubleValue(qmEpsilon));
      qmaodv.Set("RewardW1",           DoubleValue(qmW1));
      qmaodv.Set("RewardW2",           DoubleValue(qmW2));
      qmaodv.Set("EpsilonDecay",       DoubleValue(qmEpsilonDecay));
      qmaodv.Set("EpsilonDecayPeriod", TimeValue(Seconds(qmDecayPeriod)));
      internet.SetRoutingHelper(qmaodv);
    } else if (protocol == "SAQMAODV") {
      SaqmaodvHelper saqmaodv;
      saqmaodv.Set("MaxPaths",              UintegerValue(maxPaths));
      saqmaodv.Set("Alpha0",                DoubleValue(saAlpha0));
      saqmaodv.Set("Gamma",                 DoubleValue(saGamma));
      saqmaodv.Set("Epsilon0",              DoubleValue(saEpsilon0));
      saqmaodv.Set("RewardW1",              DoubleValue(saW1));
      saqmaodv.Set("RewardW2",              DoubleValue(saW2));
      saqmaodv.Set("RewardW3",              DoubleValue(saW3));
      saqmaodv.Set("Lambda",                DoubleValue(saLambda));
      saqmaodv.Set("SeqNoWindow",           TimeValue(Seconds(saSeqNoWin)));
      saqmaodv.Set("LowEnergyThreshold",    DoubleValue(saLowEThresh));
      saqmaodv.Set("PeriodicAdaptInterval", TimeValue(Seconds(saAdaptPeriod)));
      internet.SetRoutingHelper(saqmaodv);
    } else if (protocol == "EAQMAODV") {
      EaqmaodvHelper eaqmaodv;
      eaqmaodv.Set("MaxPaths",              UintegerValue(maxPaths));
      eaqmaodv.Set("Alpha0",                DoubleValue(eaAlpha0));
      eaqmaodv.Set("Gamma",                 DoubleValue(eaGamma));
      eaqmaodv.Set("Epsilon0",              DoubleValue(eaEpsilon0));
      eaqmaodv.Set("RewardW1",              DoubleValue(eaW1));
      eaqmaodv.Set("RewardW2",              DoubleValue(eaW2));
      eaqmaodv.Set("RewardW3",              DoubleValue(eaW3));
      eaqmaodv.Set("RewardW4",              DoubleValue(eaW4));
      eaqmaodv.Set("MuTdError",             DoubleValue(eaMu));
      eaqmaodv.Set("KappaTdError",          DoubleValue(eaKappa));
      eaqmaodv.Set("SeqNoWindow",           TimeValue(Seconds(eaSeqNoWin)));
      eaqmaodv.Set("LowEnergyThreshold",    DoubleValue(eaLowEThresh));
      eaqmaodv.Set("QueueHighThreshold",    DoubleValue(eaQueueHighThresh));
      eaqmaodv.Set("QueueLowThreshold",     DoubleValue(eaQueueLowThresh));
      eaqmaodv.Set("PeriodicAdaptInterval", TimeValue(Seconds(eaAdaptPeriod)));
      internet.SetRoutingHelper(eaqmaodv);
    }
    internet.Install(nodes);

    Ipv4AddressHelper addresses;
    addresses.SetBase("10.0.0.0", "255.0.0.0");
    interfaces = addresses.Assign(devices);

    installEnergy();
  }
  else if (protocol == "DSR") {
    InternetStackHelper internet;
    internet.Install(nodes);
    Ipv4AddressHelper addresses;
    addresses.SetBase("10.0.0.0", "255.0.0.0");
    interfaces = addresses.Assign(devices);
    installEnergy();
    DsrMainHelper dsrMain;
    DsrHelper dsr;
    dsrMain.Install(dsr, nodes);
  }
  else {
    NS_FATAL_ERROR("Unknown protocol: " << protocol);
  }

  // ====== Traffic: N-1 sources -> sink (node 0) ======
  uint16_t port = 9;

  // Build flow specs (src->dst pairs).
  //   numFlows == 0  → default: N-1 sources -> sink 0 (paper-like).
  //   numFlows > 0   → independent pairs (i, numNodes-1-i) for i=0..numFlows-1.
  struct FlowSpec { uint32_t src; uint32_t dst; };
  std::vector<FlowSpec> flows;
  if (numFlows == 0) {
    for (uint32_t i = 1; i < numNodes; ++i) {
      flows.push_back({i, 0});
    }
  } else {
    if (numFlows * 2 > numNodes) {
      NS_FATAL_ERROR("numFlows*2 > numNodes (" << numFlows << "*2 vs " << numNodes << ")");
    }
    for (uint32_t i = 0; i < numFlows; ++i) {
      flows.push_back({i, numNodes - 1 - i});
    }
  }

  // Install PacketSink on each unique destination.
  std::set<uint32_t> sinkIdxs;
  for (auto &f : flows) sinkIdxs.insert(f.dst);
  for (uint32_t sinkIdx : sinkIdxs) {
    PacketSinkHelper sinkHelper("ns3::UdpSocketFactory",
        InetSocketAddress(Ipv4Address::GetAny(), port));
    ApplicationContainer serverApp = sinkHelper.Install(nodes.Get(sinkIdx));
    serverApp.Start(Seconds(1.0));
    serverApp.Stop(Seconds(simTime));
  }

  uint64_t dataRateBps = static_cast<uint64_t>(pktSize * 8 / pktInterval);
  std::ostringstream rateStr;
  rateStr << dataRateBps << "bps";

  ApplicationContainer clientApps;
  double startBase = 5.0;
  for (size_t i = 0; i < flows.size(); ++i) {
    OnOffHelper onoff ("ns3::UdpSocketFactory",
        InetSocketAddress (interfaces.GetAddress (flows[i].dst), port));
    onoff.SetAttribute ("DataRate",   StringValue (rateStr.str ()));
    onoff.SetAttribute ("PacketSize", UintegerValue (pktSize));
    onoff.SetAttribute ("OnTime",
        StringValue ("ns3::ConstantRandomVariable[Constant=1.0]"));
    onoff.SetAttribute ("OffTime",
        StringValue ("ns3::ConstantRandomVariable[Constant=0.0]"));
    double startT = startBase + i * (pktInterval * 0.1);
    ApplicationContainer app = onoff.Install (nodes.Get (flows[i].src));
    app.Start (Seconds (startT));
    app.Stop (Seconds (simTime - 1.0));
    clientApps.Add (app);
  }

  // ===== FlowMonitor + overhead counter =====
  FlowMonitorHelper flowMonHelper;
  Ptr<FlowMonitor> monitor = flowMonHelper.InstallAll ();

  OverheadCounter* overhead = new OverheadCounter ();
  Config::ConnectWithoutContext (
      "/NodeList/*/$ns3::Ipv4L3Protocol/Tx",
      MakeCallback (&OverheadCounter::OnIpTx, overhead));

  // ===== Run =====
  Simulator::Stop (Seconds (simTime + 1.0));
  Simulator::Run ();

  // ===== Compute metrics =====
  monitor->CheckForLostPackets ();
  Ptr<Ipv4FlowClassifier> classifier =
      DynamicCast<Ipv4FlowClassifier> (flowMonHelper.GetClassifier ());
  auto stats = monitor->GetFlowStats ();

  uint64_t txPackets = 0, rxPackets = 0, rxBytes = 0;
  double sumDelay = 0.0;
  for (auto &kv : stats)
    {
      Ipv4FlowClassifier::FiveTuple t = classifier->FindFlow (kv.first);
      if (t.destinationPort == port)
        {
          txPackets += kv.second.txPackets;
          rxPackets += kv.second.rxPackets;
          rxBytes   += kv.second.rxBytes;
          sumDelay  += kv.second.delaySum.GetSeconds ();
        }
    }

  double deliveryRatio  = (txPackets > 0) ? (100.0 * rxPackets / txPackets) : 0.0;
  double avgDelayMs     = (rxPackets > 0) ? (1000.0 * sumDelay / rxPackets) : 0.0;
  double throughputMbps = (rxBytes * 8.0 / simTime / 1.0e6);
  uint64_t routingOverhead = (overhead->ipTxPackets > txPackets)
      ? overhead->ipTxPackets - txPackets : 0;

  double totalEnergyJ = 0.0;
  uint32_t nodesDead = 0;
  if (enableEnergy)
    {
      for (uint32_t i = 0; i < sources.GetN (); ++i)
        {
          Ptr<BasicEnergySource> src =
              DynamicCast<BasicEnergySource> (sources.Get (i));
          double rem = src->GetRemainingEnergy ();
          totalEnergyJ += (initialEnergyJ - rem);
          if (rem <= 0.0) ++nodesDead;
        }
    }

  Simulator::Destroy ();

  // ===== Console output =====
  std::cout << std::fixed << std::setprecision (4);
  std::cout << "=== FANET sim === protocol=" << protocol
             << "  mob=" << mobility << "  N=" << numNodes
             << "  T=" << simTime << "s  seed=" << seed
             << "  E0=" << initialEnergyJ << "J\n"
             << "  delivery=" << deliveryRatio << "%"
             << "  delay="    << avgDelayMs    << "ms"
             << "  thr="      << throughputMbps<< "Mbps"
             << "  rOver="    << routingOverhead
             << "  E="        << totalEnergyJ  << "J"
             << "  dead="     << nodesDead << "/" << numNodes
             << std::endl;

  // ===== CSV output =====
  struct stat st;
  bool needHeader = (stat (csvFile.c_str (), &st) != 0) || (st.st_size == 0);

  std::ofstream csv (csvFile.c_str (), std::ios::app);
  if (needHeader)
    {
      csv << "scenario,protocol,mobility,seed,nodes,flows,velMin,velMax,"
          << "pktInterval,simTime,pktSize,pdr,delay,thr,overhead,energy,dead\n";
    }
  csv << scenario << "," << protocol << "," << mobility << "," << seed << ","
      << numNodes << "," << flows.size () << ","
      << meanVelMin << "," << meanVelMax << ","
      << pktInterval << "," << simTime << "," << pktSize << ","
      << std::fixed << std::setprecision (4)
      << deliveryRatio << "," << avgDelayMs << "," << throughputMbps << ","
      << routingOverhead << "," << totalEnergyJ << "," << nodesDead << "\n";
  csv.close ();

  std::cout.flush ();
  return 0;
}
