#!/bin/bash
# 全核浮点吞吐：启动 8 个 FMA 进程（对应 8 个物理核），汇总 GFLOPS
# 用法: ./allcore.sh <iters> <标签> [采样秒数]
cd "$(dirname "$0")"
IT=${1:-30000000}
TAG=${2:-run}
MON=${3:-0}
if [ "$MON" -gt 0 ]; then ./monitor.sh "$MON" 2 > "mon_$TAG.csv" & MONPID=$!; fi
rm -f "out_$TAG.txt"
for i in $(seq 1 8); do ./flops "$IT" >> "out_$TAG.txt" & done
wait
[ -n "$MONPID" ] && wait $MONPID 2>/dev/null
TOTAL=$(awk -F'|' '{s+=$1} END{printf "%.1f", s}' "out_$TAG.txt")
PER=$(awk -F'|' '{s+=$1;n++} END{printf "%.2f", s/n}' "out_$TAG.txt")
echo "[$TAG] 8核合计 = $TOTAL GFLOPS   单核均值 = $PER GFLOPS"
echo "隐含全核频率 ≈ $(awk -v t="$TOTAL" 'BEGIN{printf "%.2f", t*1000/(8*32)}') MHz (理论峰值 32 FLOP/cycle/核)"
echo "单核离散度: $(awk -F'|' '{printf "%.1f ", $1}' "out_$TAG.txt")"
