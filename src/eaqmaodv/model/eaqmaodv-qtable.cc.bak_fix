/* -*- Mode:C++; c-file-style:"gnu"; indent-tabs-mode:nil; -*- */
/**
 * QS-QMAODV: Queue-State Self-Adaptive Q-Table — Implementation.
 *
 * Key extension over saqmaodv::QTable:
 *   1. 4-term reward: r = w1·ACK + w2·1/(delay+1) + w3·Energy + w4·1/(queue+1)
 *   2. HIGH_LOAD mode: when mean queue > m_qHighThresh, amplify w4
 *   3. COMBINED mode: both LOW_ENERGY and HIGH_LOAD simultaneously
 */

#include "qsaqmaodv-qtable.h"

#include "ns3/log.h"
#include "ns3/simulator.h"

#include <algorithm>
#include <cmath>
#include <numeric>
#include <sstream>

namespace ns3
{
NS_LOG_COMPONENT_DEFINE("QsaqmaodvQTable");

namespace qsaqmaodv
{

// ────────────────────────────────────────────────────────────────────────────
// Construction
// ────────────────────────────────────────────────────────────────────────────

QTable::QTable(uint32_t maxPaths)
    : m_maxPaths(maxPaths),
      // SA state
      m_alpha(0.5), m_gamma(0.9), m_epsilon(0.3),
      m_w1(0.4),    m_w2(0.3),    m_w3(0.1),   m_w4(0.2),
      m_lowEnergyMode(false),
      m_epsilonMin(0.05), m_epsilonMax(1.0),
      m_epsilonStep(0.02), m_epsilonBump(0.2),
      m_muTdError(0.10),
      m_kappaTdError(0.50),
      m_tdErrorEma(0.0),
      m_seqNoWindow(Seconds(10.0)),
      m_lowEnergyThresh(0.2),
      // Weight presets — Normal
      m_w1Normal(0.4),    m_w2Normal(0.3),    m_w3Normal(0.1),   m_w4Normal(0.2),
      // Weight presets — Low Energy
      m_w1LowE(0.2),      m_w2LowE(0.1),      m_w3LowE(0.5),     m_w4LowE(0.2),
      // Weight presets — High Load
      m_w1HighLoad(0.3),  m_w2HighLoad(0.2),  m_w3HighLoad(0.1), m_w4HighLoad(0.4),
      // Weight presets — Combined (Low Energy + High Load)
      m_w1Combined(0.2),  m_w2Combined(0.1),  m_w3Combined(0.35), m_w4Combined(0.35),
      // Queue-State thresholds
      m_qHighThresh(0.7), m_qLowThresh(0.3),
      m_loadMode(LOAD_NORMAL),
      m_highLoadCount(0)
{
    m_uniform = CreateObject<UniformRandomVariable>();
}

// ────────────────────────────────────────────────────────────────────────────
// Setters
// ────────────────────────────────────────────────────────────────────────────

void QTable::SetMaxPaths(uint32_t mp)      { m_maxPaths = mp; }
uint32_t QTable::GetMaxPaths() const       { return m_maxPaths; }

void QTable::SetLearningParameters(double alpha0, double gamma, double epsilon0)
{
    m_alpha   = alpha0;
    m_gamma   = gamma;
    m_epsilon = epsilon0;
}

void QTable::SetRewardWeights(double w1, double w2, double w3, double w4)
{
    m_w1Normal = m_w1 = w1;
    m_w2Normal = m_w2 = w2;
    m_w3Normal = m_w3 = w3;
    m_w4Normal = m_w4 = w4;
}

void QTable::SetLowEnergyThreshold(double frac) { m_lowEnergyThresh = frac; }
void QTable::SetTdErrorParams(double mu, double kappa)
{
    m_muTdError    = mu;
    m_kappaTdError = kappa;
}
void QTable::SetSeqNoWindow(Time window)         { m_seqNoWindow = window; }

void QTable::SetQueueThresholds(double qHigh, double qLow)
{
    NS_ASSERT_MSG(qLow < qHigh, "QueueLow must be < QueueHigh");
    m_qHighThresh = qHigh;
    m_qLowThresh  = qLow;
}

// ────────────────────────────────────────────────────────────────────────────
// SA Adaptive Controller (unchanged from SA-QMAODV)
// ────────────────────────────────────────────────────────────────────────────

void QTable::OnRouteError()
{
    m_epsilon = std::min(m_epsilon + m_epsilonBump, m_epsilonMax);
    NS_LOG_INFO("QS-QTable: RERR bump ε → " << m_epsilon);
}

void QTable::PeriodicEpsilonDecay()
{
    m_epsilon = std::max(m_epsilon - m_epsilonStep, m_epsilonMin);
}

void QTable::RecordSeqNoUpdate()
{
    m_seqEvents.push_back(Simulator::Now());
}

// EA-QMAODV Fix 1 (Sec.4.4): EMA of |TD-error|.
void QTable::UpdateTdErrorEma(double tdError)
{
    double absErr = std::fabs(tdError);
    m_tdErrorEma  = (1.0 - m_muTdError) * m_tdErrorEma + m_muTdError * absErr;
}
// EA-QMAODV Fix 1 (Sec.4.4): rational alpha from TD-error EMA.
void QTable::RecomputeAdaptiveAlpha()
{
    double newAlpha = 0.1 + 0.8 * m_tdErrorEma / (m_tdErrorEma + m_kappaTdError);
    m_alpha = newAlpha;
    NS_LOG_DEBUG("QS-QTable EA: alpha(TD-EMA)=" << m_alpha);
}
void QTable::RecomputeAdaptiveRewardWeights(double energyFraction)
{
    bool wasLowE __attribute__((unused)) = m_lowEnergyMode;
    m_lowEnergyMode = (energyFraction < m_lowEnergyThresh);

    if (m_lowEnergyMode != wasLowE)
    {
        NS_LOG_INFO("QS-QTable: LowEnergy=" << m_lowEnergyMode);
    }
    ApplyLoadMode();
}

void QTable::RecomputeAdaptiveRewardWeightsWithQueue(double energyFraction,
                                                     double meanQueueRatio)
{
    // Update energy state
    m_lowEnergyMode = (energyFraction < m_lowEnergyThresh);

    // Update high-load state (hysteresis)
    bool wasHighLoad = (m_loadMode == LOAD_HIGH || m_loadMode == LOAD_COMBINED);
    bool highLoad    = wasHighLoad
                       ? (meanQueueRatio > m_qLowThresh)   // recovery hysteresis
                       : (meanQueueRatio > m_qHighThresh);  // trigger

    if (highLoad && !wasHighLoad)
    {
        ++m_highLoadCount;
        NS_LOG_INFO("QS-QTable: HIGH_LOAD triggered q=" << meanQueueRatio);
    }

    // Determine combined mode
    if (m_lowEnergyMode && highLoad)
        m_loadMode = LOAD_COMBINED;
    else if (highLoad)
        m_loadMode = LOAD_HIGH;
    else if (m_lowEnergyMode)
        m_loadMode = LOAD_LOWENERGY;
    else
        m_loadMode = LOAD_NORMAL;

    ApplyLoadMode();
}

void QTable::ApplyLoadMode()
{
    switch (m_loadMode)
    {
    case LOAD_NORMAL:
        m_w1 = m_w1Normal; m_w2 = m_w2Normal;
        m_w3 = m_w3Normal; m_w4 = m_w4Normal;
        break;
    case LOAD_LOWENERGY:
        m_w1 = m_w1LowE;   m_w2 = m_w2LowE;
        m_w3 = m_w3LowE;   m_w4 = m_w4LowE;
        break;
    case LOAD_HIGH:
        m_w1 = m_w1HighLoad; m_w2 = m_w2HighLoad;
        m_w3 = m_w3HighLoad; m_w4 = m_w4HighLoad;
        break;
    case LOAD_COMBINED:
        m_w1 = m_w1Combined; m_w2 = m_w2Combined;
        m_w3 = m_w3Combined; m_w4 = m_w4Combined;
        break;
    }
}

// ────────────────────────────────────────────────────────────────────────────
// ΔSeq (topology volatility, inherited from SA-QMAODV)
// ────────────────────────────────────────────────────────────────────────────

void QTable::PurgeSeqNoEvents() const
{
    Time cutoff = Simulator::Now() - m_seqNoWindow;
    while (!m_seqEvents.empty() && m_seqEvents.front() < cutoff)
        m_seqEvents.pop_front();
}

uint32_t QTable::GetDeltaSeq() const
{
    PurgeSeqNoEvents();
    return static_cast<uint32_t>(m_seqEvents.size());
}

// ────────────────────────────────────────────────────────────────────────────
// Queue tracking
// ────────────────────────────────────────────────────────────────────────────

void QTable::UpdateNextHopQueue(Ipv4Address nextHop, double queueRatio)
{
    m_nhQueue[nextHop] = std::max(0.0, std::min(1.0, queueRatio));
}

double QTable::GetMeanQueueRatio() const
{
    if (m_nhQueue.empty()) return 0.0;
    double sum = 0.0;
    for (auto& kv : m_nhQueue) sum += kv.second;
    return sum / static_cast<double>(m_nhQueue.size());
}

// ────────────────────────────────────────────────────────────────────────────
// Reward computation (4-term)
// ────────────────────────────────────────────────────────────────────────────

double QTable::ComputeReward(double ackSuccess, double delaySec,
                             double energyFrac, double queueRatio) const
{
    double r1 = m_w1 * ackSuccess;
    double r2 = m_w2 * (1.0 / (delaySec + 1.0));
    double r3 = m_w3 * energyFrac * energyFrac;  // EA-Fix2: E^2
    double r4 = m_w4 * (1.0 / (queueRatio + 1.0));   // NEW: queue term
    return r1 + r2 + r3 + r4;
}

// ────────────────────────────────────────────────────────────────────────────
// Q-table CRUD
// ────────────────────────────────────────────────────────────────────────────

bool QTable::AddRoute(const RoutingTableEntry& rt)
{
    auto& vec = m_records[rt.GetDestination()];
    for (auto& rec : vec)
        if (rec.rt.GetNextHop() == rt.GetNextHop()) { rec.rt = rt; return false; }

    if (vec.size() >= m_maxPaths)
    {
        auto worst = FindWorst(vec);
        *worst = QRecord(rt, 0.0);
    }
    else
    {
        vec.emplace_back(rt, 0.0);
    }
    return true;
}

void QTable::ReinitQValues(Ipv4Address dst)
{
    auto it = m_records.find(dst);
    if (it != m_records.end())
        for (auto& r : it->second) r.qValue = 0.0;
}

uint32_t QTable::GetRoutes(Ipv4Address dst,
                            std::vector<RoutingTableEntry>& routes,
                            const RoutingTable* mainTable) const
{
    auto it = m_records.find(dst);
    if (it == m_records.end()) return 0;
    for (auto& r : it->second) routes.push_back(r.rt);
    return static_cast<uint32_t>(routes.size());
}

std::vector<QRecord>::iterator QTable::FindWorst(std::vector<QRecord>& vec)
{
    return std::min_element(vec.begin(), vec.end(),
        [](const QRecord& a, const QRecord& b){ return a.qValue < b.qValue; });
}

std::vector<QRecord> QTable::BuildCandidates(const RoutingTableEntry& primary,
                                              const RoutingTable* mainTable) const
{
    std::vector<QRecord> cands;
    auto it = m_records.find(primary.GetDestination());
    if (it != m_records.end())
        cands = it->second;

    // Ensure primary route is present
    bool found = false;
    for (auto& c : cands)
        if (c.rt.GetNextHop() == primary.GetNextHop()) { found = true; break; }
    if (!found)
        cands.emplace_back(primary, 0.0);

    return cands;
}

// ────────────────────────────────────────────────────────────────────────────
// Route Selection (ε-greedy, same as SA-QMAODV — no mode switching here)
// ────────────────────────────────────────────────────────────────────────────

bool QTable::SelectEpsilonGreedy(const RoutingTableEntry& primary,
                                  RoutingTableEntry& out,
                                  const RoutingTable* mainTable)
{
    auto cands = BuildCandidates(primary, mainTable);
    if (cands.empty()) { out = primary; return true; }

    if (m_uniform->GetValue() < m_epsilon)
    {
        // Explore: random candidate
        uint32_t idx = m_uniform->GetInteger(0, static_cast<uint32_t>(cands.size()) - 1);
        out = cands[idx].rt;
    }
    else
    {
        // Exploit: highest Q-value
        auto best = std::max_element(cands.begin(), cands.end(),
            [](const QRecord& a, const QRecord& b){ return a.qValue < b.qValue; });
        out = best->rt;
    }
    return true;
}

// ────────────────────────────────────────────────────────────────────────────
// Q-value Update (4-term reward)
// ────────────────────────────────────────────────────────────────────────────

void QTable::UpdateQValue(Ipv4Address dst, Ipv4Address nextHop,
                          double ackSuccess, double delaySec,
                          double energyFraction, double queueRatio)
{
    // Update stored queue ratio for this next-hop
    UpdateNextHopQueue(nextHop, queueRatio);

    auto it = m_records.find(dst);
    if (it == m_records.end()) return;

    // Find max Q for the destination (for Bellman update)
    double maxNextQ = 0.0;
    for (auto& r : it->second)
        if (r.qValue > maxNextQ) maxNextQ = r.qValue;

    // 4-term reward
    double reward = ComputeReward(ackSuccess, delaySec, energyFraction, queueRatio);

    // Update matching record
    for (auto& rec : it->second)
    {
        if (rec.rt.GetNextHop() != nextHop) continue;
        double oldQ   = rec.qValue;
        double target = reward + m_gamma * maxNextQ;
        rec.qValue    = (1.0 - m_alpha) * oldQ + m_alpha * target;
        // EA-QMAODV Fix 1: TD-error drives adaptive alpha
        double tdError = reward + m_gamma * maxNextQ - oldQ;
        UpdateTdErrorEma(tdError);
        RecomputeAdaptiveAlpha();
        rec.lastUpd   = Simulator::Now();
        ++rec.txCount;
        if (ackSuccess > 0.5) ++rec.ackCount;
        rec.lastQueue = queueRatio;

        NS_LOG_DEBUG("QS-QTable: Q[" << dst << "/" << nextHop << "] → "
                     << rec.qValue << " (r=" << reward
                     << " ack=" << ackSuccess
                     << " q=" << queueRatio << ")");
        break;
    }
}

bool QTable::EnsureRecord(const RoutingTableEntry& rt)
{
    return AddRoute(rt);
}

void QTable::UpdateQValueOrCreate(const RoutingTableEntry& rt,
                                  double ackSuccess, double delaySec,
                                  double energyFraction, double queueRatio)
{
    EnsureRecord(rt);
    UpdateQValue(rt.GetDestination(), rt.GetNextHop(),
                 ackSuccess, delaySec, energyFraction, queueRatio);
}

// ────────────────────────────────────────────────────────────────────────────
// Deletion and Utilities
// ────────────────────────────────────────────────────────────────────────────

void QTable::DeleteRoutes(Ipv4Address dst)
{
    m_records.erase(dst);
}

void QTable::DeleteRoute(Ipv4Address dst, Ipv4Address nextHop)
{
    auto it = m_records.find(dst);
    if (it == m_records.end()) return;
    auto& vec = it->second;
    vec.erase(std::remove_if(vec.begin(), vec.end(),
        [&](const QRecord& r){ return r.rt.GetNextHop() == nextHop; }), vec.end());
    if (vec.empty()) m_records.erase(it);
}

void QTable::RemoveNextHopGlobally(Ipv4Address nextHop)
{
    for (auto& kv : m_records)
    {
        auto& vec = kv.second;
        vec.erase(std::remove_if(vec.begin(), vec.end(),
            [&](const QRecord& r){ return r.rt.GetNextHop() == nextHop; }), vec.end());
    }
    m_nhQueue.erase(nextHop);
}

uint32_t QTable::Size() const
{
    uint32_t n = 0;
    for (auto& kv : m_records) n += static_cast<uint32_t>(kv.second.size());
    return n;
}

uint32_t QTable::CountFor(Ipv4Address dst) const
{
    auto it = m_records.find(dst);
    return it == m_records.end() ? 0 : static_cast<uint32_t>(it->second.size());
}

bool QTable::IsFull(Ipv4Address dst) const
{
    return CountFor(dst) >= m_maxPaths;
}

void QTable::Clear()
{
    m_records.clear();
    m_nhQueue.clear();
}

double QTable::GetQValue(Ipv4Address dst, Ipv4Address nextHop) const
{
    auto it = m_records.find(dst);
    if (it == m_records.end()) return 0.0;
    for (auto& r : it->second)
        if (r.rt.GetNextHop() == nextHop) return r.qValue;
    return 0.0;
}

void QTable::Print(std::ostream& os) const
{
    os << "QS-QMAODV QTable: " << m_records.size() << " destinations\n";
    os << "  ε=" << m_epsilon << " α=" << m_alpha << " γ=" << m_gamma << "\n";
    os << "  w=(" << m_w1 << "," << m_w2 << "," << m_w3 << "," << m_w4 << ")\n";
    os << "  mode=" << (int)m_loadMode << " ΔSeq=" << GetDeltaSeq() << "\n";
    os << "  mean_queue=" << GetMeanQueueRatio() << "\n";
    for (auto& kv : m_records)
    {
        os << "  dst=" << kv.first << "\n";
        for (auto& r : kv.second)
        {
            os << "    nh=" << r.rt.GetNextHop()
               << " Q=" << r.qValue
               << " q=" << r.lastQueue
               << " tx=" << r.txCount
               << " ack=" << r.ackCount << "\n";
        }
    }
}

} // namespace qsaqmaodv
} // namespace ns3
