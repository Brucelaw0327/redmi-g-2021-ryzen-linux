#!/bin/bash
# 独显满载监测：先运行本脚本，再开任意 3D 负载，结束后分析 CSV
# 用法: ./gpu_watch.sh [采样秒数]
# 输出: gpu_load.csv + gpu_info.txt

cd "$(dirname "$0")" || exit 1
DUR=${1:-300}
OUT=gpu_load.csv
INFO=gpu_info.txt

if ! command -v nvidia-smi >/dev/null; then
  echo "未找到 nvidia-smi"; exit 1
fi

# ---- 1. 静态信息：功耗墙 + 降频原因规格 ----
{
  echo "### 时间: $(date)"
  echo
  echo "### 功耗墙"
  nvidia-smi -q -d POWER | grep -E "Power Draw|Current Power Limit|Default Power Limit|Min Power Limit|Max Power Limit|Power Limit|Enforced"
  echo
  echo "### 时钟"
  nvidia-smi -q -d CLOCK | grep -E "Graphics|SM  |Memory|Video|Max Clocks" | head -20
  echo
  echo "### 温度阈值 / 当前"
  nvidia-smi -q -d TEMPERATURE | grep -E "GPU Current|Shutdown|Slowdown|Max Operating|Target"
  echo
  echo "### 降频原因（当前）"
  nvidia-smi -q -d PERFORMANCE | sed -n '/Clocks Event Reasons/,/^$/p' | head -20
  echo
  echo "### 支持的图形时钟"
  nvidia-smi --query-gpu=clocks.max.graphics,clocks.max.sm,clocks.max.mem,power.max_limit,power.default_limit --format=csv
} > "$INFO" 2>&1

cat "$INFO"
echo
echo "--------------------------------------------------------"
echo "开始采样 ${DUR}s，现在请打开 3D 负载（游戏 / gpu-burn / 3DMark 均可）"
echo "--------------------------------------------------------"

# ---- 2. 动态采样 ----
echo "sec,temp,power_w,cap_w,sm_mhz,mem_mhz,util,mem_used_mib,pstate,throttle" > "$OUT"
T0=$(date +%s)
while :; do
  NOW=$(date +%s); EL=$((NOW - T0))
  [ "$EL" -ge "$DUR" ] && break
  R=$(nvidia-smi --query-gpu=temperature.gpu,power.draw,power.limit,clocks.sm,clocks.mem,utilization.gpu,memory.used,pstate,clocks_throttle_reasons.active --format=csv,noheader,nounits 2>/dev/null)
  echo "$EL,$R" | tr -d ' ' >> "$OUT"
  sleep 2
done

echo "采样结束 -> $OUT"
echo
echo "=== 汇总 ==="
awk -F, 'NR>1 {
  n++; t+=$2; p+=$3; c+=$4; s+=$5;
  if ($2>mt) mt=$2; if ($3>mp) mp=$3;
  if (smin==""||$5<smin) smin=$5; if ($5>smax) smax=$5;
  if ($7>umax) umax=$7;
} END {
  printf "样本 %d 个 | 均温 %.1f°C（峰 %.0f） | 平均功耗 %.1fW（峰 %.0f） | 功耗墙档位 %.0fW\n", n, t/n, mt, p/n, mp, c/n;
  printf "SM 频率 %.0f~%.0f MHz（均 %.0f） | GPU 占用峰值 %.0f%%\n", smin, smax, s/n, umax;
}' "$OUT"

echo
echo "提示：把 $OUT 和 $INFO 贴回来，我可以判断是否存在功耗墙 / 温度墙"
