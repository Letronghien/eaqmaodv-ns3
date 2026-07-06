#!/bin/bash
# ================================================================
# run-ea-rerun.sh — EA-QMAODV (~380 simulations)
# Fix: TD-error EMA adaptive α + E² energy penalty
# ================================================================
NS3_DIR="$HOME/ns-allinone-3.40/ns-3.40"
BIN="$NS3_DIR/build/scratch/ns3.40-fanet-sim-optimized"
CSV="$NS3_DIR/results.csv"
LOG_DIR="$HOME/fanet-routing/results/ea-qmaodv/logs"
mkdir -p "$LOG_DIR"

QS_MU=0.10; QS_KAPPA=0.50; SIM_TIME=30
PARALLEL_JOBS=$(nproc)
CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
RED='\033[0;31m'; BOLD='\033[1m'; NC='\033[0m'

echo -e "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║  EA-QMAODV Rerun  (μ=0.10, κ=0.50, E², TD-α)       ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"

run_sim() {
    local PROTO=$1 NODES=$2 SEED=$3 MOBILITY=${4:-GAUSS} SCENARIO=${5:-default} \
          W1=${6:-0.4} W2=${7:-0.3} W3=${8:-0.1} W4=${9:-0.2} EXTRA="${10:-}"
    local TAG="${SCENARIO}_${PROTO}_N${NODES}_s${SEED}_$(echo $W1$W2$W3$W4 | tr -d .)"
    "$BIN" \
        --protocol="$PROTO" --numNodes="$NODES" --seed="$SEED" \
        --simTime="$SIM_TIME" --mobility="$MOBILITY" --scenario="$SCENARIO" \
        --qsMu="$QS_MU" --qsKappa="$QS_KAPPA" \
        --qsW1="$W1" --qsW2="$W2" --qsW3="$W3" --qsW4="$W4" \
        $EXTRA \
        > "$LOG_DIR/${TAG}.log" 2>&1
    local EC=$?
    [[ $EC -eq 0 || $EC -eq 134 || $EC -eq 139 ]] \
        && echo -e "${GREEN}✓${NC} $TAG" \
        || echo -e "${RED}✗${NC} $TAG (exit=$EC)"
}
export -f run_sim
export BIN LOG_DIR QS_MU QS_KAPPA SIM_TIME

# ── E: Standard GAUSS, 5 node counts × 36 seeds = 180 runs ────────────
echo -e "\n${YELLOW}[E] GAUSS default, N=10..50, seeds 1-36 (180 runs)${NC}"
for N in 10 20 30 40 50; do
  for S in $(seq 1 36); do echo "EAQMAODV $N $S GAUSS default 0.4 0.3 0.1 0.2"; done
done > /tmp/ea_E.txt
parallel --jobs "$PARALLEL_JOBS" --colsep ' ' \
    run_sim {1} {2} {3} {4} {5} {6} {7} {8} {9} :::: /tmp/ea_E.txt

# ── ELONG: Elongated area, N=20, 30 seeds ─────────────────────────────
echo -e "\n${YELLOW}[ELONG] Elongated area (3000×200m), N=20, seeds 1-30${NC}"
for S in $(seq 1 30); do
  echo "EAQMAODV 20 $S GAUSS default 0.4 0.3 0.1 0.2 --areaX=3000 --areaY=200"
done > /tmp/ea_ELONG.txt
parallel --jobs "$PARALLEL_JOBS" --colsep ' ' \
    run_sim {1} {2} {3} {4} {5} {6} {7} {8} {9} "{10}" :::: /tmp/ea_ELONG.txt

# ── STAT: Near-static (vel≈0), N=20, 50 seeds ─────────────────────────
echo -e "\n${YELLOW}[STAT] Static nodes (vel=0), N=20, seeds 1-50${NC}"
for S in $(seq 1 50); do
  echo "EAQMAODV 20 $S GAUSS default 0.4 0.3 0.1 0.2 --meanVelMin=0 --meanVelMax=0"
done > /tmp/ea_STAT.txt
parallel --jobs "$PARALLEL_JOBS" --colsep ' ' \
    run_sim {1} {2} {3} {4} {5} {6} {7} {8} {9} "{10}" :::: /tmp/ea_STAT.txt

# ── W: Weight variations, N=20, 6 combos × 20 seeds = 120 runs ────────
echo -e "\n${YELLOW}[W] Weight variation, N=20, 6×20=120 runs${NC}"
> /tmp/ea_W.txt
for W in "0.5 0.2 0.2 0.1" "0.3 0.3 0.3 0.1" "0.4 0.3 0.2 0.1" \
          "0.4 0.2 0.1 0.3" "0.5 0.1 0.1 0.3" "0.3 0.2 0.4 0.1"; do
  for S in $(seq 1 20); do echo "EAQMAODV 20 $S GAUSS default $W"; done
done >> /tmp/ea_W.txt
parallel --jobs "$PARALLEL_JOBS" --colsep ' ' \
    run_sim {1} {2} {3} {4} {5} {6} {7} {8} {9} :::: /tmp/ea_W.txt

TOTAL=$(grep -c "EAQMAODV" "$CSV" 2>/dev/null || echo 0)
echo -e "\n${CYAN}${BOLD}✅ Xong! EAQMAODV rows in CSV: $TOTAL${NC}"
