#!/bin/bash
# ================================================================
# run-paper-full.sh — Full paper comparison ~1420 runs
# Protocols: AODV, AOMDV, PMAODV, QMAODV, EAQMAODV(=EA-QMAODV)
# Scenarios: E(default) | ELONG(elong) | STAT(stat) | W(ablw1-6)
# ================================================================
NS3_DIR="$HOME/ns-allinone-3.40/ns-3.40"
BIN="$NS3_DIR/build/scratch/ns3.40-fanet-sim-optimized"
CSV="$NS3_DIR/results.csv"
LOG_DIR="$HOME/eaqmaodv-ns3/results/logs"
mkdir -p "$LOG_DIR"

SIM_TIME=300; PARALLEL_JOBS=7
QS_MU=0.10; QS_KAPPA=0.50

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
RED='\033[0;31m'; BOLD='\033[1m'; NC='\033[0m'

echo -e "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  FANET Paper Comparison (~1420 runs)                    ║"
echo "║  AODV | AOMDV | PMAODV | QMAODV | EA-QMAODV            ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

run_sim() {
    # $1=proto $2=nodes $3=seed $4=scenario $5=mobility $6+=extra_args
    local PROTO=$1 NODES=$2 SEED=$3 SCEN=$4 MOB=$5
    shift 5; local EXTRA="$*"
    local TAG="${SCEN}_${PROTO}_N${NODES}_s${SEED}"

    # Skip nếu đã có trong CSV
    awk -F',' -v sc="$SCEN" -v p="$PROTO" -v n="$NODES" -v s="$SEED" \
        '$1==sc && $2==p && $5==n && $11==s {found=1;exit} END{exit !found}' "$CSV" 2>/dev/null \
        && { echo "SKIP $TAG"; return 0; }

    "$BIN" \
        --protocol="$PROTO" --numNodes="$NODES" --seed="$SEED" \
        --simTime="$SIM_TIME" --mobility="$MOB" --scenario="$SCEN" \
        --qsMu="$QS_MU" --qsKappa="$QS_KAPPA" \
        --qsW1=0.4 --qsW2=0.3 --qsW3=0.2 --qsW4=0.1 \
        $EXTRA --csvFile="/home/tronghien1011/ns-allinone-3.40/ns-3.40/results.csv" > "$LOG_DIR/${TAG}.log" 2>&1
    local EC=$?
    [[ $EC -eq 0||$EC -eq 134||$EC -eq 139 ]] \
        && echo -e "${GREEN}✓${NC} $TAG" \
        || echo -e "${RED}✗${NC} $TAG (exit=$EC)"
}
export -f run_sim
export BIN LOG_DIR SIM_TIME QS_MU QS_KAPPA CSV

run_sim_w() {
    local PROTO=$1 NODES=$2 SEED=$3 SCEN=$4 MOB=$5 W1=$6 W2=$7 W3=$8 W4=$9
    local TAG="${SCEN}_${PROTO}_N${NODES}_s${SEED}"
    awk -F',' -v sc="$SCEN" -v p="$PROTO" -v n="$NODES" -v s="$SEED" \
        '$1==sc && $2==p && $5==n && $11==s {found=1;exit} END{exit !found}' "$CSV" 2>/dev/null \
        && { echo "SKIP $TAG"; return 0; }
    "$BIN" \
        --protocol="$PROTO" --numNodes="$NODES" --seed="$SEED" \
        --simTime="$SIM_TIME" --mobility="$MOB" --scenario="$SCEN" \
        --qsMu="$QS_MU" --qsKappa="$QS_KAPPA" \
        --qsW1="$W1" --qsW2="$W2" --qsW3="$W3" --qsW4="$W4" \
        --csvFile="/home/tronghien1011/ns-allinone-3.40/ns-3.40/results.csv" > "$LOG_DIR/${TAG}.log" 2>&1
    local EC=$?
    [[ $EC -eq 0||$EC -eq 134||$EC -eq 139 ]] \
        && echo -e "${GREEN}✓${NC} $TAG" \
        || echo -e "${RED}✗${NC} $TAG (exit=$EC)"
}
export -f run_sim_w

PROTOS="AODV AOMDV PMAODV QMAODV EAQMAODV"

# ── E: scenario=default, N=10..50, seeds 1-36, 5 protos = 900 ─────────
echo -e "\n${YELLOW}[E] default, N=10..50, seeds 1-36, 5 protos = 900 runs${NC}"
> /tmp/paper_E.txt
for P in $PROTOS; do for N in 10 20 30 40 50; do
  for S in $(seq 1 36); do echo "$P $N $S default GAUSS"; done
done; done >> /tmp/paper_E.txt
parallel --jobs "$PARALLEL_JOBS" --colsep ' ' \
    run_sim {1} {2} {3} {4} {5} :::: /tmp/paper_E.txt

# ── ELONG: scenario=elong, areaX=3000 areaY=200, N=20, 30 seeds × 5 = 150 ─
echo -e "\n${YELLOW}[ELONG] elong, N=20, seeds 1-30, 5 protos = 150${NC}"
> /tmp/paper_ELONG.txt
for P in $PROTOS; do
  for S in $(seq 1 30); do
    echo "$P 20 $S elong GAUSS --areaX=3000 --areaY=200"
  done
done >> /tmp/paper_ELONG.txt
parallel --jobs "$PARALLEL_JOBS" --colsep ' ' \
    run_sim {1} {2} {3} {4} {5} {6} :::: /tmp/paper_ELONG.txt

# ── STAT: scenario=stat, vel=0, N=20, 50 seeds × 5 = 250 ─────────────
echo -e "\n${YELLOW}[STAT] stat, N=20, seeds 1-50, 5 protos = 250${NC}"
> /tmp/paper_STAT.txt
for P in $PROTOS; do
  for S in $(seq 1 50); do
    echo "$P 20 $S stat GAUSS --meanVelMin=0 --meanVelMax=0"
  done
done >> /tmp/paper_STAT.txt
parallel --jobs "$PARALLEL_JOBS" --colsep ' ' \
    run_sim {1} {2} {3} {4} {5} {6} :::: /tmp/paper_STAT.txt

# ── W: EA-QMAODV weight ablation, scenario=ablw1..ablw6, 120 runs ─────
echo -e "\n${YELLOW}[W] Weight ablation EA-QMAODV, 6×20=120 runs${NC}"
> /tmp/paper_W.txt
declare -A WMAP=(
  ["ablw1"]="0.5 0.2 0.2 0.1"
  ["ablw2"]="0.3 0.3 0.3 0.1"
  ["ablw3"]="0.4 0.3 0.2 0.1"
  ["ablw4"]="0.4 0.2 0.1 0.3"
  ["ablw5"]="0.5 0.1 0.1 0.3"
  ["ablw6"]="0.3 0.2 0.4 0.1"
)
for TAG in ablw1 ablw2 ablw3 ablw4 ablw5 ablw6; do
  W="${WMAP[$TAG]}"
  for S in $(seq 1 20); do
    echo "EAQMAODV 20 $S $TAG GAUSS $W"
  done
done >> /tmp/paper_W.txt
parallel --jobs "$PARALLEL_JOBS" --colsep ' ' \
    run_sim_w {1} {2} {3} {4} {5} {6} {7} {8} {9} :::: /tmp/paper_W.txt

echo -e "\n${CYAN}${BOLD}✅ Hoàn tất!${NC}"
echo "Rows trong CSV: $(wc -l < $CSV)"
