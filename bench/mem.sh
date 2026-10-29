#!/bin/bash
cd "$(dirname "$0")"
echo "=== 8 个进程并发（各 128MB，总 1GB）==="
for i in $(seq 1 8); do ./stream_mt 128 6 > "mt_$i.txt" 2>&1 & done
wait
cat mt_*.txt | grep size
echo
TRI=$(cat mt_*.txt | grep -o 'triad=[0-9.]*' | cut -d= -f2 | awk '{s+=$1} END{printf "%.1f", s}')
echo "并发 triad 合计 ≈ $TRI GB/s"
echo
echo "=== THP ==="; cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null
echo "=== 内存通道/速率 ==="; lshw -short -C memory 2>/dev/null | head -8
