# SAQMAODV-NS3 — Self-Adaptive Q-Learning Multipath Routing Evaluation in FANET

[![NS-3](https://img.shields.io/badge/NS--3-3.40-blue)](https://www.nsnam.org/) [![Status](https://img.shields.io/badge/status-active-yellow)]()

NS-3.40 implementation and comprehensive evaluation of **SA-QMAODV** (Self-Adaptive Q-Learning Multipath AODV) against four baseline routing protocols (AODV, AOMDV-3, PMAODV-3, QMAODV-3) in FANET environments.

**Companion project to [qmaodv-ns3](https://github.com/Letronghien/qmaodv-ns3)** — extends the QMAODV evaluation by adding SA-QMAODV with adaptive mechanisms (event-driven ε, dynamic α, context-aware reward weights).

---

## Project Status

| Item | Status |
|------|--------|
| Code (5 protocols) | ✅ Implemented (NS-3.40 modules + patches) |
| Setup script | ✅ `scripts/setup/setup-from-scratch.sh` |
| Family H tuning script | ✅ `scripts/run/tune-saqmaodv-family-h.sh` |
| Heterogeneous battery scenario | ✅ `scripts/run/run-hetero-battery.sh` |
| Long-sim scenario | ✅ `scripts/run/run-long-sim.sh` |
| 5-family parametric sweep | ✅ `scripts/run/run-paper-experiments.sh` |
| Paper-exact reproduction | ✅ `scripts/run/run-paper-exact.sh` |
| Experimental data | ⏳ Pending runs |
| Figures | ⏳ Pending |
| Paper draft | ⏳ Pending |

---

## Experimental Scope

This evaluation runs 4 distinct experimental tracks:

### 1. Family H — SA-QMAODV Hyperparameter Tuning
Sweep adaptive-specific params to identify optimal config:
- λ (Eq.1 sensitivity) ∈ {0.01, 0.05, 0.1, 0.2, 0.5}
- adaptPeriod ∈ {0.5, 1.0, 2.0} s
- w₃ (energy weight in Normal mode) ∈ {0.0, 0.1, 0.2}
- lowEThresh ∈ {0.2, 0.5}
- Total: ~270 configs × 3 seeds @ N=15

### 2. Five Operating Families (N, L, S, P, F)
Cross-protocol comparison across:
- **N**: density 5–30 UAVs
- **L**: traffic load 1–20 pps
- **S**: mobility 5–70 m/s
- **P**: packet size 64–1500 B
- **F**: concurrent flows 1–7

### 3. Heterogeneous Battery (paper's intended use case)
Verify SA-QMAODV's low-energy mode (w₃=0.8) activates correctly:
- initialEnergy ∈ {10, 20, 30, 50} J
- Sim time 300s to allow battery drain
- Compare all 5 protocols

### 4. Long Simulation (adaptive convergence)
Confirm SA's adaptive mechanisms have time to learn:
- simTime ∈ {200, 600, 900, 1200} s
- Tests whether longer convergence improves SA performance

### 5. Paper-Exact (SA-QMAODV Final paper reproduction)
Reproduces the original SA-QMAODV paper §5 scenario:
- 500 × 500 m² area
- 150 kbps/source CBR
- N ∈ {10, 15, 20, 25, 30}
- 30 seeds per configuration

---

## Repository Structure

```
.
├── README.md                          # This file
├── LICENSE                            # MIT
├── .gitignore
├── files/                             # Custom .h/.cc dropped into ns-3 modules
│   ├── aomdv-multipath-table.{h,cc}
│   ├── pmaodv-multipath-table.{h,cc}
│   ├── qmaodv-qtable.{h,cc}
│   └── saqmaodv-qtable.{h,cc}         # SA-QMAODV Q-table with adaptive controller
├── src/
│   └── fanet-sim.cc                   # Main driver with SA-specific CLI flags
├── scripts/
│   ├── setup/setup-from-scratch.sh    # 10-step installer (incl SAQMAODV)
│   ├── run/
│   │   ├── run-paper-experiments.sh   # 5-family sweep (default 5 protocols)
│   │   ├── run-paper-exact.sh         # Paper SA-QMAODV §5 reproduction
│   │   ├── run-hetero-battery.sh      # Heterogeneous battery scenario
│   │   ├── run-long-sim.sh            # Long-sim convergence test
│   │   ├── tune-saqmaodv-family-h.sh  # NEW: Family H for SA-QMAODV
│   │   ├── tune-saqmaodv-stage1.sh    # Initial sweep
│   │   ├── tune-saqmaodv-stage2.sh    # Refinement
│   │   └── tune-saqmaodv-stage3.sh    # Cross-N validation
│   ├── plot/
│   │   ├── plot-experiments-5proto.py # 5-protocol plotter
│   │   ├── analyze-family-H.py        # QMAODV Family H analyzer (re-usable)
│   │   └── aggregate-for-paper.py
│   └── patches/                       # 22 patches: AOMDV+PMAODV+QMAODV+SAQMAODV
├── data/                              # Experimental data (initially empty)
├── figures/                           # Plots (initially empty)
├── paper/                             # Paper drafts (initially empty)
└── reference/
    ├── QMAODV-Paper-v3.docx           # QMAODV Extended paper (Vietnamese, our prior work)
    └── SA-QMAODV-Final.pdf            # Original SA-QMAODV paper for reference
```

---

## Quick Start

### Prerequisites
- NS-3.40 at `$HOME/ns-allinone-3.40/ns-3.40`
- Python 3.8+ with `matplotlib`, `pandas`
- GCC ≥ 9, CMake ≥ 3.20

### Build (10 minutes)
```bash
git clone https://github.com/Letronghien/saqmaodv-ns3.git
cd saqmaodv-ns3
bash scripts/setup/setup-from-scratch.sh
```

### Recommended workflow

**Step 1**: Tune SA-QMAODV first (find optimal config for your setup):
```bash
bash scripts/run/tune-saqmaodv-family-h.sh
# ~30 minutes, gives top-15 configs
```

**Step 2**: After identifying optimal SA hyperparams, update defaults in run scripts, then:
```bash
# Full 5-family evaluation (~3 hours)
PROTOCOLS="AODV AOMDV PMAODV QMAODV SAQMAODV" SEEDS=15 \
    FAMILIES="N L S P F" \
    bash scripts/run/run-paper-experiments.sh
```

**Step 3**: Heterogeneous battery test (~20 min):
```bash
bash scripts/run/run-hetero-battery.sh
```

**Step 4**: Long-sim convergence test (~1-2 hours):
```bash
bash scripts/run/run-long-sim.sh
```

**Step 5**: Generate figures:
```bash
RDIR=$(ls -dt ~/results-paper-* | head -1)
for f in N L S P F; do
    case $f in
        N) csv=family_N_nodes.csv ;;
        L) csv=family_L_load.csv ;;
        S) csv=family_S_speed.csv ;;
        P) csv=family_P_pktsize.csv ;;
        F) csv=family_F_flows.csv ;;
    esac
    python3 scripts/plot/plot-experiments-5proto.py \
            $RDIR/$csv figures/$f/
done
```

---

## Default Hyperparameters

### QMAODV (Strategy B, validated in [qmaodv-ns3](https://github.com/Letronghien/qmaodv-ns3))
| Param | Value |
|-------|-------|
| α | 0.7 |
| γ | 0.6 |
| ε₀ | 0.3 |
| decay | 0.1/s |

### SA-QMAODV (Tentative — will be refined by Family H)
| Param | Default | Note |
|-------|---------|------|
| λ (Eq.1) | 0.01 | From prior stage tuning |
| seqNoWindow | 10 s | Paper "short window" |
| adaptPeriod | 1.0 s | PeriodicAdaptiveTick |
| α₀ | 0.5 | Will adapt |
| γ | 0.9 | Paper-fixed |
| ε₀ | 0.3 | Paper-spec [0.1, 0.5] |
| ε bump (RERR) | +0.2 | Paper §4.2 |
| ε decay (periodic) | −0.02 | Paper §4.2 |
| w₁ (Normal) | 0.5 | Paper Table 1 |
| w₂ (Normal) | 0.4 | Paper Table 1 |
| w₃ (Normal) | 0.1 | Paper Table 1 |
| w (Low-E mode) | (0.1, 0.1, 0.8) | Paper Table 1 |
| lowEThresh | 0.20 | Paper §4.4 |

---

## Related Work
- **QMAODV** [ICIT 2025]: Q-learning multipath baseline
- **PMAODV** [IAAA 2025]: Probabilistic multipath baseline
- **SA-QMAODV** [Original paper]: Self-Adaptive Q-learning extension

See `reference/` for primary documents.

---

## License

MIT — see [LICENSE](LICENSE).

---

## Contact

Le Trong-Hien — `letronghien@iuh.edu.vn`
Industrial University of Ho Chi Minh City, Vietnam.
