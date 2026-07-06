#!/bin/bash
# ============================================================================
# pretest-eaqmaodv.sh
# Bộ kịch bản test nhỏ để kiểm tra 5 protocol (AODV, AOMDV, PMAODV, QMAODV,
# EAQMAODV) chạy đúng/hợp lý TRƯỚC KHI chạy full sweep ~1420 runs cho paper.
#
# Chạy trên VM, trong môi trường cô lập đã build:
#   bash pretest-eaqmaodv.sh
#
# Kết quả ghi vào ~/pretest-results.csv (KHÔNG lẫn với results.csv chính).
# Toàn bộ nên chạy xong trong vài phút (simTime ngắn, numNodes nhỏ).
# ============================================================================
set -e
cd ~/eaqmaodv/ns-allinone-3.40/ns-3.40

CSV=~/pretest-results.csv
rm -f "$CSV"

run() {
  echo ">>> $*"
  ./ns3 run "scratch/fanet-sim $* --csvFile=$CSV" 2>&1 | grep -E "delivery=|died with|NS_FATAL|terminate"
}

echo "########################################################"
echo "# TEST 1 — Sanity check: 5 protocol tại N=10/20/30      #"
echo "# Kỳ vọng: không crash (ngoại trừ SIGSEGV lúc thoát đã  #"
echo "# biết), delivery/delay/thr là số hợp lý (không 0%/NaN) #"
echo "########################################################"
for N in 10 20 30; do
  for P in AODV AOMDV PMAODV QMAODV EAQMAODV; do
    run --protocol=$P --numNodes=$N --simTime=50 --seed=1 --scenario=t1-sanity
  done
done

echo "########################################################"
echo "# TEST 2 — AODV vs AOMDV/PMAODV có thực sự phân biệt   #"
echo "# nhau không (N lớn hơn để multipath có cơ hội phát huy)#"
echo "# Kỳ vọng: 3 protocol cho số liệu KHÁC NHAU rõ rệt ở    #"
echo "# từng seed — nếu giống hệt nhau -> nghi ngờ multipath  #"
echo "# không hoạt động đúng                                  #"
echo "########################################################"
for seed in 1 2 3; do
  for P in AODV AOMDV PMAODV; do
    run --protocol=$P --numNodes=30 --maxPaths=3 --simTime=100 --seed=$seed --scenario=t2-multipath
  done
done

echo "########################################################"
echo "# TEST 3 — Seed có thực sự đổi kết quả không (RNG)?     #"
echo "# Kỳ vọng: 5 seed cho 5 kết quả khác nhau               #"
echo "# (nếu giống hệt -> seed/RNG run chưa được set đúng)    #"
echo "########################################################"
for seed in 1 2 3 4 5; do
  run --protocol=EAQMAODV --numNodes=20 --simTime=100 --seed=$seed --scenario=t3-seedvar
done

echo "########################################################"
echo "# TEST 4 — Multi-flow (numFlows) có chạy đúng không?    #"
echo "# Kỳ vọng: không crash với flows=0/5/10, cột 'flows'    #"
echo "# trong CSV phải khớp đúng số flow thực tế              #"
echo "########################################################"
run --protocol=EAQMAODV --numNodes=20 --numFlows=0  --simTime=100 --seed=1 --scenario=t4-flow0
run --protocol=EAQMAODV --numNodes=20 --numFlows=5  --simTime=100 --seed=1 --scenario=t4-flow5
run --protocol=EAQMAODV --numNodes=20 --numFlows=10 --simTime=100 --seed=1 --scenario=t4-flow10

echo "########################################################"
echo "# TEST 5 — Energy: node có 'chết' khi initialEnergy thấp?#"
echo "# Kỳ vọng: nodesDead TĂNG khi initialEnergy GIẢM         #"
echo "# (E0=5J nên có dead>0, E0=50J nên dead=0)               #"
echo "########################################################"
for E0 in 5 10 20 50; do
  run --protocol=EAQMAODV --numNodes=20 --initialEnergy=$E0 --simTime=150 --seed=1 --scenario=t5-energy
done

echo "########################################################"
echo "# TEST 6 — Hyperparameter EA-QMAODV có ảnh hưởng thật   #"
echo "# tới kết quả không (kiểm tra CLI có nối đúng vào thuật  #"
echo "# toán, không phải bị bỏ qua)                            #"
echo "# Kỳ vọng: các cấu hình khác nhau -> số liệu khác nhau   #"
echo "########################################################"
run --protocol=EAQMAODV --numNodes=20 --simTime=100 --seed=1 --eaMu=0.05 --eaKappa=0.3 --scenario=t6-hp-lowmu
run --protocol=EAQMAODV --numNodes=20 --simTime=100 --seed=1 --eaMu=0.5  --eaKappa=0.8 --scenario=t6-hp-highmu
run --protocol=EAQMAODV --numNodes=20 --simTime=100 --seed=1 --eaW4=0.0  --scenario=t6-hp-noqueue
run --protocol=EAQMAODV --numNodes=20 --simTime=100 --seed=1 --eaW4=0.5  --scenario=t6-hp-heavyqueue

echo "########################################################"
echo "# TEST 7 — Chạy gần đúng quy mô paper thật (N=50,T=200s) #"
echo "# để bắt lỗi timing/memory trước khi chạy full 1420 runs #"
echo "# Kỳ vọng: không crash giữa chừng, ước lượng được thời   #"
echo "# gian chạy trung bình / 1 run                            #"
echo "########################################################"
for P in AODV AOMDV PMAODV QMAODV EAQMAODV; do
  T0=$(date +%s)
  run --protocol=$P --numNodes=50 --simTime=200 --seed=1 --scenario=t7-paperscale
  T1=$(date +%s)
  echo "    -> thời gian chạy: $((T1-T0))s"
done

echo ""
echo "============================================================"
echo "XONG. Kết quả đầy đủ tại: $CSV"
echo "Xem nhanh:"
echo "  column -s, -t $CSV | less -S"
echo "============================================================"
