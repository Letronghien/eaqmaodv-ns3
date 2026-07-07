#!/usr/bin/env bash
# =============================================================================
# run_full_paper_eaqmaodv.sh — EA-QMAODV Paper Parallel Runner
# (Cấu trúc phỏng theo run_full_paper.sh của dự án PM-AOMDV bạn gửi)
#
# Families (theo progress notes EA-QMAODV, mục 6):
#   E     — Density sweep : N=10/20/30/40/50, GAUSS, seed 1-36, 5 protocol  = 900 runs
#   ELONG — Elongated area : areaX=3000/areaY=200, N=50, seed 1-30, 5 proto = 150 runs
#   STAT  — Static (vel=0) : N=50, seed 1-50, 5 protocol                    = 250 runs
#   W     — Ablation EA-QMAODV only : N=20, 6 config, seed 1-20             = 120 runs
#   Tổng: 1420 runs
#
# *** ĐÃ CHỐT (sau khi validate qua multiseed test trong quá trình debug) ***
#   1) SIMTIME=100s — dùng đúng giá trị đã kiểm chứng nhiều lần trong session
#      debug (cho kết quả ổn định, phân biệt rõ giữa các protocol, và đủ số
#      chu kỳ PeriodicAdaptInterval=10s để Q-learning hội tụ ~10 lần/run).
#      KHÔNG dùng 30s (quá ngắn, chỉ ~3 chu kỳ adapt) hay 200s (không thêm lợi
#      ích rõ rệt, tăng gấp đôi thời gian chạy 1420 job).
#   2) pktInterval SCALE THEO N: mặc định 0.25s chỉ hợp với N=20 (baseline đã
#      validate). Với numFlows=0 (N-1 nguồn dồn về 1 sink), tổng tải tăng theo
#      N — nếu giữ nguyên 0.25s, N=50 sẽ nghẽn hoàn toàn cho MỌI protocol
#      (đã đo được PDR tụt còn 5-9%, không phân biệt được protocol nào cả).
#      Công thức: pktInterval(N) = 0.25 * N/20 (neo tại N=20 đã validate).
#      → N=10:0.125s N=20:0.25s N=30:0.375s N=40:0.50s N=50:0.625s
#   3) 6 cấu hình ablation W1-W6 — GIỮ NGUYÊN như đề xuất ban đầu vì đây là
#      cấu hình do REVIEWER đề xuất, cần giữ đúng để đáp ứng yêu cầu phản biện.
#
# 5 protocol: AODV, AOMDV, PMAODV, QMAODV, EAQMAODV
# 7 workers song song trong tmux (VM 8 vCPU, chừa 1 core cho OS/monitor)
# Queue lưu trên đĩa (pending.txt/done.txt) — resume được nếu VM tắt giữa chừng
# Mỗi worker ghi CSV riêng (worker_N.csv) để tránh ghi đè lẫn nhau khi chạy song song
#
# Sử dụng:
#   bash run_full_paper_eaqmaodv.sh --test      # vài job test nhanh
#   bash run_full_paper_eaqmaodv.sh             # full 1420 jobs (nhiều giờ/ngày)
#   bash run_full_paper_eaqmaodv.sh --resume    # tiếp tục nếu bị ngắt giữa chừng
# =============================================================================

set -euo pipefail

HOME_DIR="$HOME"
PROJECT_DIR="$HOME_DIR/eaqmaodv"
NS3_ROOT="$PROJECT_DIR/ns-allinone-3.40/ns-3.40"
RESULTS_DIR="$PROJECT_DIR/results/paper_full"
QUEUE_DIR="$PROJECT_DIR/queue_paper"
LOGS_DIR="$PROJECT_DIR/logs/paper_workers"

N_WORKERS=7
SESSION="eaqmaodv-paper"
TEST_MODE=false
RESUME=false
SIMTIME=100   # đã validate qua multiseed test trong session debug (xem ghi chú trên)

while [[ $# -gt 0 ]]; do
  case $1 in
    --test)   TEST_MODE=true; shift ;;
    --resume) RESUME=true;    shift ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

G='\033[0;32m'; B='\033[0;34m'; C='\033[0;36m'
Y='\033[1;33m'; R='\033[0;31m'; N='\033[0m'; BOLD='\033[1m'

# =============================================================================
# Tạo job queue — lưu vào đĩa
# Job format: PROTOCOL SEED TAG --extra_args...
# =============================================================================
generate_jobs() {
  local JOBS_FILE="$QUEUE_DIR/pending.txt"
  local DONE_FILE="$QUEUE_DIR/done.txt"
  local PROTOS=("AODV" "AOMDV" "PMAODV" "QMAODV" "EAQMAODV")

  mkdir -p "$QUEUE_DIR" "$RESULTS_DIR" "$LOGS_DIR"
  touch "$QUEUE_DIR/queue.lock"
  local CLAIMED_FILE="$QUEUE_DIR/claimed.txt"

  if [[ "$RESUME" == true && -f "$JOBS_FILE" ]]; then
    touch "$CLAIMED_FILE" "$DONE_FILE"
    # FIX-Resume: job da bi "claim" (worker lay ra khoi pending.txt de chay)
    # nhung KHONG co trong done.txt VA KHONG co san trong pending.txt (tuc
    # dang chay do thi VM/worker chet giua chung, khong ai "so huu" nua) ->
    # dua tro lai pending.txt. Neu job da fail binh thuong (khong phai VM
    # chet) thi no da tu re-queue vao pending.txt roi -> khong bi trung lap.
    local RECOVERED=0
    if [[ -s "$CLAIMED_FILE" ]]; then
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if ! grep -qF -- "$line" "$DONE_FILE" 2>/dev/null && \
           ! grep -qF -- "$line" "$JOBS_FILE" 2>/dev/null; then
          echo "$line" >> "$JOBS_FILE"
          RECOVERED=$((RECOVERED+1))
        fi
      done < "$CLAIMED_FILE"
    fi
    > "$CLAIMED_FILE"
    local P=$(wc -l < "$JOBS_FILE")
    local D=$(wc -l < "$DONE_FILE" 2>/dev/null || echo 0)
    echo -e "${Y}[RESUME]${N} Khôi phục ${RECOVERED} job bị bỏ dở (VM chết giữa chừng). Còn ${P} jobs pending, đã xong ${D}"
    return
  fi

  > "$JOBS_FILE"
  > "$DONE_FILE"
  > "$CLAIMED_FILE"

  if [[ "$TEST_MODE" == true ]]; then
    for PROTO in AODV EAQMAODV; do
      for RUN in 1 2 3; do
        echo "$PROTO $RUN test --numNodes=20 --mobility=GAUSS --scenario=test --simTime=$SIMTIME" >> "$JOBS_FILE"
      done
    done
    echo -e "${Y}[TEST]${N} 6 jobs tạo xong"
    return
  fi

  local COUNT=0

  # ── E: Density sweep (N=10..50) ──────────────────────────────────────────
  # pktInterval scale theo N (neo tai N=20=0.25s da validate) de tranh nghen
  # mang toan bo o N lon (numFlows=0 => N-1 luong don ve 1 sink).
  for NN in 10 20 30 40 50; do
    TAG="E_n${NN}"
    PKTIV=$(awk -v n="$NN" 'BEGIN{printf "%.3f", 0.25*n/20}')
    for PROTO in "${PROTOS[@]}"; do
      for RUN in $(seq 1 36); do
        echo "$PROTO $RUN $TAG --numNodes=$NN --mobility=GAUSS --scenario=default --simTime=$SIMTIME --pktInterval=$PKTIV" >> "$JOBS_FILE"
        COUNT=$((COUNT+1))
      done
    done
  done

  # ── ELONG: Elongated topology, N=50 (pktInterval=0.625, dong bo voi E_n50) ─
  for PROTO in "${PROTOS[@]}"; do
    for RUN in $(seq 1 30); do
      echo "$PROTO $RUN ELONG --numNodes=50 --mobility=GAUSS --scenario=elong --areaX=3000 --areaY=200 --simTime=$SIMTIME --pktInterval=0.625" >> "$JOBS_FILE"
      COUNT=$((COUNT+1))
    done
  done

  # ── STAT: Static nodes vel=0, N=50 (pktInterval=0.625, dong bo voi E_n50) ──
  for PROTO in "${PROTOS[@]}"; do
    for RUN in $(seq 1 50); do
      echo "$PROTO $RUN STAT --numNodes=50 --mobility=GAUSS --scenario=stat --meanVelMin=0 --meanVelMax=0 --simTime=$SIMTIME --pktInterval=0.625" >> "$JOBS_FILE"
      COUNT=$((COUNT+1))
    done
  done

  # ── W: Ablation EA-QMAODV only, N=20 ── cấu hình do reviewer đề xuất ─────
  #   ablw1: baseline (mặc định, không đổi gì)
  #   ablw2: tắt adaptive-alpha (kappa lớn -> alpha gần cố định thấp ~0.1)
  #   ablw3: tắt energy^2 penalty (w3=0)
  #   ablw4: tắt queue-reward (w4=0)
  #   ablw5: tăng nặng queue-reward (w4=0.5, gấp đôi mặc định)
  #   ablw6: alpha nhạy hơn (kappa nhỏ = 0.1 thay vì 0.5 mặc định)
  declare -A ABLW
  ABLW[ablw1]=""
  ABLW[ablw2]="--eaKappa=50.0"
  ABLW[ablw3]="--eaW3=0.0"
  ABLW[ablw4]="--eaW4=0.0"
  ABLW[ablw5]="--eaW4=0.5"
  ABLW[ablw6]="--eaKappa=0.1"

  for TAG in ablw1 ablw2 ablw3 ablw4 ablw5 ablw6; do
    for RUN in $(seq 1 20); do
      echo "EAQMAODV $RUN $TAG --numNodes=20 --mobility=GAUSS --scenario=$TAG ${ABLW[$TAG]} --simTime=$SIMTIME --pktInterval=0.25" >> "$JOBS_FILE"
      COUNT=$((COUNT+1))
    done
  done

  echo -e "${G}[QUEUE]${N} $COUNT jobs → $JOBS_FILE"
  echo -e "  E     (density) : 900 jobs  [N=10..50 x 5 protocol x 36 seed]"
  echo -e "  ELONG (dài)     : 150 jobs  [N=50, area 3000x200 x 5 protocol x 30 seed]"
  echo -e "  STAT  (tĩnh)    : 250 jobs  [N=50, vel=0 x 5 protocol x 50 seed]"
  echo -e "  W     (ablation): 120 jobs  [EAQMAODV only x 6 config x 20 seed]"
  echo -e "  Total: ${Y}$COUNT jobs${N} | $N_WORKERS workers | simTime=${SIMTIME}s"
}

# =============================================================================
# Worker script — viết ra đĩa, chạy độc lập, mỗi worker 1 CSV riêng
# =============================================================================
write_worker() {
  local WID=$1
  cat > "$QUEUE_DIR/worker_${WID}.sh" << WEOF
#!/usr/bin/env bash
WID=$WID
NS3_ROOT="$NS3_ROOT"
RESULTS_DIR="$RESULTS_DIR"
QUEUE_DIR="$QUEUE_DIR"
LOGS_DIR="$LOGS_DIR"
JOBS_FILE="\$QUEUE_DIR/pending.txt"
DONE_FILE="\$QUEUE_DIR/done.txt"
LOCK="\$QUEUE_DIR/queue.lock"
WORKER_CSV="\$RESULTS_DIR/worker_${WID}.csv"

G='\033[0;32m'; R='\033[0;31m'; Y='\033[1;33m'; C='\033[0;36m'; N='\033[0m'

echo -e "\${C}[W${WID}]\${N} Start @ \$(date '+%H:%M:%S')"
cd "\$NS3_ROOT"

# FIX-Parallel-Race: goi thang binary da build san, KHONG dung "./ns3 run"
# (./ns3 run tu kiem tra/rebuild qua CMake moi lan goi -> 7 worker goi dong
# thoi tren cung 1 thu muc build gay race condition, bao exit=245 gia du
# simulation khong co van de gi that. Da xac nhan RAM/CPU du dai, khong
# phai do thieu tai nguyen).
BIN="\$NS3_ROOT/build/scratch/ns3.40-fanet-sim-optimized"
if [[ ! -x "\$BIN" ]]; then
  echo -e "\${R}[W${WID}] Khong tim thay binary: \$BIN — chay './ns3 build' truoc khi launch worker!\${N}"
  exit 1
fi

DONE_LOCAL=0
FAIL_LOCAL=0

while true; do
  JOB=\$(
    flock -x "\$LOCK" bash -c '
      LINE=\$(head -1 "'\$JOBS_FILE'" 2>/dev/null)
      if [[ -n "\$LINE" ]]; then
        sed -i "1d" "'\$JOBS_FILE'"
        echo "\$LINE" >> "'\$QUEUE_DIR'/claimed.txt"
        echo "\$LINE"
      fi
    '
  )
  [[ -z "\$JOB" ]] && break

  PROTO=\$(echo "\$JOB" | awk '{print \$1}')
  RUN=\$(  echo "\$JOB" | awk '{print \$2}')
  TAG=\$(  echo "\$JOB" | awk '{print \$3}')
  EXTRA=\$(echo "\$JOB" | cut -d' ' -f4-)

  REMAINING=\$(wc -l < "\$JOBS_FILE" 2>/dev/null || echo 0)
  DONE_TOTAL=\$(wc -l < "\$DONE_FILE" 2>/dev/null || echo 0)

  echo -e "\${C}[W${WID}]\${N} \${Y}\${PROTO}\${N} \${TAG} seed=\${RUN}  (q=\${REMAINING} done=\${DONE_TOTAL})"

  LOG="\$LOGS_DIR/w${WID}_\${PROTO}_\${TAG}_s\${RUN}.log"
  mkdir -p "\$LOGS_DIR"
  T0=\$(date +%s)

  "\$BIN" --protocol=\$PROTO --seed=\$RUN \$EXTRA --csvFile=\$WORKER_CSV \
    > "\$LOG" 2>&1
  STATUS=\$?

  ELAPSED=\$(( \$(date +%s) - T0 ))

  # exit 0 = OK. exit 134/139/245 = SIGABRT/SIGSEGV luc destructor
  # EnergySourceContainer (bug da biet, CSV da ghi xong TRUOC khi crash ->
  # van tinh la thanh cong). Ma nay tung xuat hien trong test tuan tu
  # (multiseed-check.sh) VA duoc xac nhan CSV van ghi du du lieu.
  if [[ \$STATUS -eq 0 || \$STATUS -eq 134 || \$STATUS -eq 139 || \$STATUS -eq 245 ]]; then
    flock -x "\$LOCK" bash -c "echo '\$JOB \$(date +%s)' >> '\$DONE_FILE'"
    DONE_LOCAL=\$((DONE_LOCAL+1))
    echo -e "\${G}[W${WID}] ✓\${N} \${PROTO} \${TAG} s\${RUN} (\${ELAPSED}s, exit=\${STATUS})"
  else
    FAIL_LOCAL=\$((FAIL_LOCAL+1))
    echo -e "\${R}[W${WID}] ✗\${N} \${PROTO} \${TAG} s\${RUN} FAIL (exit=\${STATUS}) → re-queue"
    flock -x "\$LOCK" bash -c "echo '\$JOB' >> '\$JOBS_FILE'"
  fi
done

echo -e "\${G}[W${WID}]\${N} Done: \${DONE_LOCAL} OK / \${FAIL_LOCAL} fail @ \$(date '+%H:%M:%S')"
WEOF
  chmod +x "$QUEUE_DIR/worker_${WID}.sh"
}

# =============================================================================
# Monitor script — hiển thị tiến độ real-time
# =============================================================================
write_monitor() {
  cat > "$QUEUE_DIR/monitor.sh" << MEOF
#!/usr/bin/env bash
QUEUE_DIR="$QUEUE_DIR"
RESULTS_DIR="$RESULTS_DIR"

G='\033[0;32m'; B='\033[0;34m'; C='\033[0;36m'
Y='\033[1;33m'; R='\033[0;31m'; N='\033[0m'; BOLD='\033[1m'

START_TIME=\$(date +%s)
clear

while true; do
  PENDING=\$(wc -l < "\$QUEUE_DIR/pending.txt" 2>/dev/null || echo 0)
  DONE=\$(   wc -l < "\$QUEUE_DIR/done.txt"    2>/dev/null || echo 0)
  TOTAL=\$((PENDING + DONE))
  [[ \$TOTAL -eq 0 ]] && TOTAL=1
  PCT=\$((DONE * 100 / TOTAL))
  FILLED=\$((PCT * 36 / 100))
  BAR=\$(  printf '%*s' "\$FILLED"        '' | tr ' ' '█')
  EMPTY=\$(printf '%*s' "\$((36-FILLED))" '' | tr ' ' '░')

  NOW=\$(date +%s)
  ELAPSED_S=\$((NOW - START_TIME))

  tput cup 0 0
  printf "\${BOLD}\${C}══════  EA-QMAODV Paper Runner | %s  ══════\${N}\n" "\$(date '+%H:%M:%S')"
  printf "  Progress : [\${G}%s\${N}%s] \${Y}%d%%\${N}  (%d/%d jobs)\n" \
         "\$BAR" "\$EMPTY" "\$PCT" "\$DONE" "\$TOTAL"

  printf "  Elapsed  : %dh %dm\n" "\$((ELAPSED_S/3600))" "\$(( (ELAPSED_S%3600)/60 ))"
  if [[ \$DONE -gt 5 ]]; then
    ETA_S=\$(( PENDING * ELAPSED_S / DONE ))
    printf "  ETA      : ~%dh %dm remaining\n" "\$((ETA_S/3600))" "\$(( (ETA_S%3600)/60 ))"
  else
    printf "  ETA      : calculating...\n"
  fi
  echo ""

  printf "\${BOLD}  %-10s %8s %10s %10s %6s\${N}\n" "Protocol" "PDR%" "Delay(ms)" "Thr(Mbps)" "Runs"
  echo "  ──────────────────────────────────────────────────────────"
  for PROTO in AODV AOMDV PMAODV QMAODV EAQMAODV; do
    STATS=\$(cat "\$RESULTS_DIR"/worker_*.csv 2>/dev/null | awk -F',' -v p="\$PROTO" '
      \$2==p { pdr+=\$12; delay+=\$13; thr+=\$14; c++ }
      END { if(c>0) printf "%.2f %.2f %.4f %d", pdr/c, delay/c, thr/c, c }')
    if [[ -n "\$STATS" ]]; then
      read PDR DELAY THR RUNS <<< "\$STATS"
      printf "  %-10s %7.2f%% %10.2f %10.4f %6d\n" "\$PROTO" "\$PDR" "\$DELAY" "\$THR" "\$RUNS"
    fi
  done

  echo ""
  echo -e "  \${B}Queue : \$QUEUE_DIR/pending.txt | done.txt\${N}"
  echo -e "  \${B}Data  : \$RESULTS_DIR/worker_*.csv (gộp lại lúc cuối)\${N}"
  echo -e "  \${Y}Ctrl+B D\${N} detach  |  \${Y}tmux attach -t eaqmaodv-paper\${N} resume"

  [[ \$PENDING -eq 0 && \$DONE -gt 0 ]] && {
    echo -e "\n  \${G}\${BOLD}✓ TẤT CẢ \$DONE JOBS HOÀN TẤT!\${N}"
    echo -e "  Chạy gộp kết quả: bash \$QUEUE_DIR/merge_results.sh"
    break
  }

  sleep 15
done
MEOF
  chmod +x "$QUEUE_DIR/monitor.sh"
}

# =============================================================================
# Merge script — gộp toàn bộ worker_*.csv thành 1 file kết quả cuối cùng
# =============================================================================
write_merge_script() {
  cat > "$QUEUE_DIR/merge_results.sh" << MEOF
#!/usr/bin/env bash
RESULTS_DIR="$RESULTS_DIR"
OUT="\$RESULTS_DIR/results-final-\$(date +%Y%m%d).csv"
first=1
> "\$OUT"
for f in "\$RESULTS_DIR"/worker_*.csv; do
  [[ -f "\$f" ]] || continue
  if [[ \$first -eq 1 ]]; then
    cat "\$f" >> "\$OUT"
    first=0
  else
    tail -n +2 "\$f" >> "\$OUT"
  fi
done
echo "Đã gộp -> \$OUT (\$(wc -l < "\$OUT") dòng, gồm cả header)"
MEOF
  chmod +x "$QUEUE_DIR/merge_results.sh"
}

# =============================================================================
# Launch tmux session
# =============================================================================
launch_tmux() {
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  sleep 1

  tmux new-session -d -s "$SESSION" -x 240 -y 60 \
    "bash $QUEUE_DIR/monitor.sh; echo 'Monitor done'; read"

  tmux rename-window -t "$SESSION:0" "eaqmaodv-paper"

  tmux split-window -t "$SESSION:0" -v -p 65 \
    "bash $QUEUE_DIR/worker_1.sh; echo '[W1 DONE]'; read"

  for W in 2 3 4 5 6 7; do
    tmux split-window -t "$SESSION:0" -h \
      "bash $QUEUE_DIR/worker_${W}.sh; echo '[W${W} DONE]'; read"
    tmux select-layout -t "$SESSION:0" tiled
  done

  tmux select-pane -t "$SESSION:0.0"
  echo -e "${G}[TMUX]${N} Session '${SESSION}' sẵn sàng ($((N_WORKERS+1)) panes)"
}

# =============================================================================
# Main
# =============================================================================
main() {
  local MODE=$([[ "$TEST_MODE" == true ]] && echo "TEST (6 jobs)" || echo "FULL (1420 jobs)")
  echo -e "\n${C}════════════════════════════════════════════════════${N}"
  echo -e "${C}  EA-QMAODV Paper Runner — $MODE${N}"
  echo -e "${C}  E(density)+ELONG(dài)+STAT(tĩnh)+W(ablation)${N}"
  echo -e "${C}  $N_WORKERS workers | simTime=${SIMTIME}s | disk-persistent${N}"
  echo -e "${C}════════════════════════════════════════════════════${N}\n"

  command -v tmux &>/dev/null || sudo apt-get install -y tmux

  echo -e "${B}[BUILD]${N} Dam bao binary da build moi nhat truoc khi chay song song..."
  (cd "$NS3_ROOT" && ./ns3 build)

  generate_jobs

  echo -e "${B}[SETUP]${N} Viết worker scripts..."
  for W in $(seq 1 $N_WORKERS); do write_worker "$W"; done
  write_monitor
  write_merge_script

  launch_tmux

  echo ""
  echo -e "  ${Y}Attach :${N} tmux attach -t $SESSION"
  echo -e "  ${Y}Detach :${N} Ctrl+B  D"
  echo -e "  ${Y}Resume :${N} bash run_full_paper_eaqmaodv.sh --resume"
  echo -e "  ${Y}Monitor:${N} tail -f $QUEUE_DIR/done.txt | wc -l"
  echo -e "  ${Y}Gộp CSV:${N} bash $QUEUE_DIR/merge_results.sh"
  echo ""
  sleep 2
  tmux attach -t "$SESSION"
}

main "$@"
