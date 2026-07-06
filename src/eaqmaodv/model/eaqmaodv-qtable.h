/* -*- Mode:C++; c-file-style:"gnu"; indent-tabs-mode:nil; -*- */
/**
 * EA-QMAODV: Queue-State Self-Adaptive Q-Table.
 *
 * Extends SA-QMAODV QTable with:
 *
 * 1. FOUR-TERM REWARD:
 *      r = w1·ACK + w2·1/(delay+1) + w3·EnergyFrac + w4·1/(queueRatio+1)
 *
 * 2. HIGH-LOAD ADAPTIVE MODE (analogous to Low-Energy Mode):
 *      mean queue occupancy > m_qHighThresh  →  HIGH_LOAD weights (amplify w4)
 *      mean queue occupancy < m_qLowThresh   →  NORMAL weights
 *
 * All SA adaptive mechanisms (ε decay, α recompute, Low-Energy mode) run
 * unchanged in the background.
 *
 * Queue occupancy per next-hop is fed into UpdateQValue() as a new parameter
 * `queueRatio` ∈ [0.0, 1.0] (0 = empty, 1 = full).
 *
 * Paper: "EA-QMAODV: Queue-State Aware Self-Adaptive Q-Learning Routing
 *         for Congestion-Resilient FANETs"
 * Inspired by: QL-AODV (Future Internet 2025) — buffer-state reward
 */

#ifndef QEAQMAODV_QTABLE_H
#define QEAQMAODV_QTABLE_H

#include "eaqmaodv-rtable.h"

#include "ns3/ipv4-address.h"
#include "ns3/nstime.h"
#include "ns3/random-variable-stream.h"

#include <map>
#include <vector>
#include <deque>

namespace ns3
{
namespace eaqmaodv
{

/// Operating mode for reward weight adaptation.
enum LoadMode
{
    LOAD_NORMAL   = 0,  ///< Default weights
    LOAD_HIGH     = 1,  ///< Queue congestion detected — amplify w4
    LOAD_LOWENERGY = 2, ///< Battery critical — amplify w3 (from SA-QMAODV)
    LOAD_COMBINED = 3,  ///< Both high-load AND low-energy active
};

/// One Q-learning record per (destination, next-hop) pair.
struct QRecord
{
    RoutingTableEntry rt;
    double            qValue;
    uint32_t          txCount;
    uint32_t          ackCount;
    Time              lastUpd;
    double            lastQueue;  ///< Last observed queue ratio for this next-hop

    QRecord() : qValue(0.0), txCount(0), ackCount(0),
                lastUpd(Seconds(0)), lastQueue(0.0) {}
    QRecord(const RoutingTableEntry& e, double q)
        : rt(e), qValue(q), txCount(0), ackCount(0),
          lastUpd(Seconds(0)), lastQueue(0.0) {}
};

/**
 * \brief EA-QMAODV Queue-State Self-Adaptive Q-Table.
 *
 * Drop-in replacement for saqmaodv::QTable with 4-term reward and
 * High-Load adaptive mode.
 */
class QTable
{
  public:
    QTable(uint32_t maxPaths = 3);

    void SetMaxPaths(uint32_t mp);
    uint32_t GetMaxPaths() const;

    // -------- Inherited SA hyper-parameter setters --------------------------
    void SetLearningParameters(double alpha0, double gamma, double epsilon0);
    void SetRewardWeights(double w1, double w2, double w3, double w4 = 0.2);
    void SetLowEnergyThreshold(double frac);
    void SetTdErrorParams(double mu, double kappa);
    void SetSeqNoWindow(Time window);

    // -------- NEW: Queue-State thresholds -----------------------------------
    /**
     * \brief Set queue occupancy thresholds for High-Load mode.
     * \param qHigh  Mean queue ratio above which HIGH_LOAD activates (default 0.7).
     * \param qLow   Mean queue ratio below which NORMAL resumes (default 0.3).
     */
    void SetQueueThresholds(double qHigh, double qLow);
    double GetQueueHigh() const { return m_qHighThresh; }
    double GetQueueLow()  const { return m_qLowThresh; }

    // -------- NEW: w4 reward weight (queue term) ----------------------------
    double GetW4() const { return m_w4; }

    // -------- SA adaptive controller ----------------------------------------
    void OnRouteError();
    void PeriodicEpsilonDecay();
    void RecordSeqNoUpdate();
    void UpdateTdErrorEma(double tdError);
  void RecomputeAdaptiveAlpha();
    void RecomputeAdaptiveRewardWeights(double energyFraction);
    /**
     * \brief NEW: Update adaptive weights based on current queue state.
     * \param meanQueueRatio   Mean queue occupancy across recent next-hops [0,1].
     */
    void RecomputeAdaptiveRewardWeightsWithQueue(double energyFraction,
                                                 double meanQueueRatio);

    // -------- Read accessors ------------------------------------------------
    double   GetAlpha()    const { return m_alpha; }
    double   GetGamma()    const { return m_gamma; }
    double   GetEpsilon()  const { return m_epsilon; }
    double   GetW1()       const { return m_w1; }
    double   GetW2()       const { return m_w2; }
    double   GetW3()       const { return m_w3; }
    uint32_t GetDeltaSeq() const;
    LoadMode GetCurrentMode() const { return m_loadMode; }
    double   GetMeanQueueRatio() const;
    /// Counters for paper Fig 6
    uint64_t GetHighLoadCount() const { return m_highLoadCount; }

    // -------- Standard Q-table operations -----------------------------------
    bool     AddRoute(const RoutingTableEntry& rt);
    void     ReinitQValues(Ipv4Address dst);
    uint32_t GetRoutes(Ipv4Address dst,
                       std::vector<RoutingTableEntry>& routes,
                       const RoutingTable* mainTable = nullptr) const;

    bool SelectEpsilonGreedy(const RoutingTableEntry& primary,
                             RoutingTableEntry& out,
                             const RoutingTable* mainTable = nullptr);

    /**
     * \brief Update Q-value with 4-term reward.
     * \param queueRatio  Queue occupancy at next-hop [0.0, 1.0]; 0.0 = empty.
     */
    void UpdateQValue(Ipv4Address dst, Ipv4Address nextHop,
                      double ackSuccess, double delaySec,
                      double energyFraction = 1.0,
                      double queueRatio = 0.0);

    bool EnsureRecord(const RoutingTableEntry& rt);
    void UpdateQValueOrCreate(const RoutingTableEntry& rt,
                              double ackSuccess, double delaySec,
                              double energyFraction = 1.0,
                              double queueRatio = 0.0);

    void     DeleteRoutes(Ipv4Address dst);
    void     DeleteRoute(Ipv4Address dst, Ipv4Address nextHop);
    void     RemoveNextHopGlobally(Ipv4Address nextHop);
    uint32_t Size() const;
    uint32_t CountFor(Ipv4Address dst) const;
    bool     IsFull(Ipv4Address dst) const;
    void     Clear();
    void     Print(std::ostream& os) const;
    double   GetQValue(Ipv4Address dst, Ipv4Address nextHop) const;

    /// Update per-next-hop queue ratio (called from routing protocol queue callback)
    void UpdateNextHopQueue(Ipv4Address nextHop, double queueRatio);

  private:
    std::vector<QRecord>::iterator FindWorst(std::vector<QRecord>& vec);
    std::vector<QRecord> BuildCandidates(const RoutingTableEntry& primary,
                                         const RoutingTable* mainTable) const;
    double ComputeReward(double ackSuccess, double delaySec,
                         double energyFrac, double queueRatio) const;
    void    PurgeSeqNoEvents() const;
    void   ApplyLoadMode();   ///< Set w1-w4 from current load mode presets

    // Q-table storage
    std::map<Ipv4Address, std::vector<QRecord>> m_records;
    uint32_t m_maxPaths;

    // Per-next-hop queue tracking
    std::map<Ipv4Address, double> m_nhQueue;   ///< next-hop → queue ratio

    // SA adaptive state (unchanged from SA-QMAODV)
    double m_alpha, m_gamma, m_epsilon;
    double m_w1, m_w2, m_w3, m_w4;      ///< w4 is new
    bool   m_lowEnergyMode;
    double m_epsilonMin, m_epsilonMax, m_epsilonStep, m_epsilonBump;
    double      m_muTdError;    ///< EMA smoothing factor mu  (default 0.10)
  double      m_kappaTdError;  ///< Saturation constant  kappa (default 0.50)
  double      m_tdErrorEma;   ///< Running EMA of |TD-error|
    Time   m_seqNoWindow;
    double m_lowEnergyThresh;
    mutable std::deque<Time> m_seqEvents;

    // Weight presets (4 modes × 4 weights)
    double m_w1Normal,   m_w2Normal,   m_w3Normal,   m_w4Normal;
    double m_w1LowE,     m_w2LowE,     m_w3LowE,     m_w4LowE;
    double m_w1HighLoad, m_w2HighLoad, m_w3HighLoad, m_w4HighLoad;
    double m_w1Combined, m_w2Combined, m_w3Combined, m_w4Combined;

    // NEW: Queue-State adaptive state
    double   m_qHighThresh;    ///< Queue ratio above which HIGH_LOAD activates (default 0.7)
    double   m_qLowThresh;     ///< Queue ratio below which NORMAL resumes (default 0.3)
    LoadMode m_loadMode;       ///< Current operating mode
    uint64_t m_highLoadCount;  ///< Times HIGH_LOAD was triggered (for paper stats)

    Ptr<UniformRandomVariable> m_uniform;
};

} // namespace eaqmaodv
} // namespace ns3

#endif /* QEAQMAODV_QTABLE_H */
