#!/bin/bash
# multiseed-check.sh — Kiem tra EAQMAODV vs baseline qua NHIEU seed (khong chi 1)
# truoc khi quyet dinh co can sua tiep loi #1 (reward gia) hay khong.
set -e
cd ~/eaqmaodv/ns-allinone-3.40/ns-3.40
CSV=~/multiseed-results.csv
rm -f "$CSV"

echo "Chay 10 seed x 5 protocol x 2 quy mo (N=20, N=30) = 100 runs..."
for N in 20 30; do
  for P in AODV AOMDV PMAODV QMAODV EAQMAODV; do
    for SEED in 1 2 3 4 5 6 7 8 9 10; do
      ./ns3 run "scratch/fanet-sim --protocol=$P --numNodes=$N --numFlows=0 --simTime=100 --seed=$SEED --scenario=multiseed-n${N} --csvFile=$CSV" > /dev/null 2>&1
    done
    echo "  $P @ N=$N xong"
  done
done

echo ""
echo "=== Trung binh + do lech chuan qua 10 seed, theo protocol va N ==="
python3 - << 'PYEOF'
import csv, os, statistics
from collections import defaultdict

rows = defaultdict(list)
path = os.path.expanduser("~/multiseed-results.csv")
with open(path) as f:
    reader = csv.DictReader(f)
    for r in reader:
        key = (r["scenario"], r["protocol"])
        rows[key].append({
            "pdr": float(r["pdr"]),
            "delay": float(r["delay"]),
            "thr": float(r["thr"]),
            "overhead": float(r["overhead"]),
        })

print(f"{'Scenario':<18}{'Protocol':<10}{'PDR avg':>9}{'PDR std':>9}{'Delay avg':>12}{'Thr avg':>10}{'Overhead avg':>14}")
for (scenario, proto), vals in sorted(rows.items()):
    pdrs = [v["pdr"] for v in vals]
    delays = [v["delay"] for v in vals]
    thrs = [v["thr"] for v in vals]
    ovhs = [v["overhead"] for v in vals]
    print(f"{scenario:<18}{proto:<10}{statistics.mean(pdrs):>8.2f}%{statistics.stdev(pdrs):>9.2f}{statistics.mean(delays):>11.2f}ms{statistics.mean(thrs):>10.4f}{statistics.mean(ovhs):>14.0f}")
PYEOF
