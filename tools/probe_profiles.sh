#!/bin/bash
# probe_profiles.sh —— 逐个试探 ACPI platform_profile 的四个值，实测它们是否真的不同
#
# 目的：本机 EC 只暴露三个档位（静谧/均衡/极速），但 ACPI 声明了四个值。
#       balanced 到底被 EC 接受还是被忽略？实测一次比猜可靠。
#
# 做法：对每个档位，统一设成 governor=powersave + EPP=balance_power（排除策略干扰），
#       然后施加单核负载 6 秒，采集：回读值、频率上限、负载中的最高/平均频率、末温。
#
# 用法：sudo ./probe_profiles.sh
#       FORCE=1 sudo ./probe_profiles.sh   # 无视 ppd 冲突
set -u
cd "$(dirname "$0")" || exit 1

PP=/sys/firmware/acpi/platform_profile
HW=/sys/class/hwmon/hwmon5/temp1_input
POL=/sys/devices/system/cpu/cpufreq/policy0
FLOPS=./flops

[ "$(id -u)" -eq 0 ] || exec sudo -E "$0" "$@"
[ -x "$FLOPS" ] || { echo "缺少 $FLOPS，先执行 gcc -O2 -mavx2 -mfma -o flops flops.c"; exit 1; }

if systemctl is-active --quiet power-profiles-daemon 2>/dev/null && [ "${FORCE:-0}" != "1" ]; then
  echo "power-profiles-daemon 正在运行，它会改写档位，测不出真实结果。" >&2
  echo "先 sudo systemctl stop power-profiles-daemon，或用 FORCE=1 强制执行。" >&2
  exit 1
fi

ORIG_PP=$(cat "$PP")
ORIG_GOV=$(cat "$POL/scaling_governor")
ORIG_EPP=$(cat "$POL/energy_performance_preference")

restore() {
  echo "$ORIG_PP" > "$PP" 2>/dev/null
  for c in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    echo "$ORIG_GOV" > "$c" 2>/dev/null
  done
  for c in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
    echo "$ORIG_EPP" > "$c" 2>/dev/null
  done
  echo
  echo "已恢复原状态：$ORIG_PP（governor=$ORIG_GOV, epp=$ORIG_EPP）"
}
trap restore EXIT INT TERM

printf '%-22s %-22s %10s %10s %10s %8s %s\n' "写入档位" "回读档位" "频率上限" "负载峰值" "负载均值" "末温" "固件0x230"
echo "-----------------------------------------------------------------------------------------------------"

for prof in low-power balanced balanced-performance performance; do
  wr="ok"
  echo "$prof" > "$PP" 2>/dev/null || wr="写入被拒"

  # 统一策略，排除 governor/EPP 差异带来的干扰
  for c in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    echo powersave > "$c" 2>/dev/null
  done
  for c in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
    echo balance_power > "$c" 2>/dev/null
  done

  sleep 2   # 等 EC 完成切换

  readback=$(cat "$PP" 2>/dev/null)
  [ "$wr" = "ok" ] || readback="$readback ($wr)"
  cap=$(( $(cat "$POL/cpuinfo_max_freq" 2>/dev/null) / 1000 ))
  fw=$(od -A n -t u1 -j 564 -N 1 "$(ls /sys/firmware/efi/efivars/Setup-* 2>/dev/null | head -1)" 2>/dev/null | tr -d ' \n')

  # 单核负载 + 频率采样
  $FLOPS burn >/dev/null 2>&1 &
  PID=$!
  maxf=0; sum=0; n=0
  for i in $(seq 1 30); do
    f=$(( $(cat "$POL/scaling_cur_freq" 2>/dev/null) / 1000 ))
    sum=$((sum + f)); n=$((n + 1))
    [ "$f" -gt "$maxf" ] && maxf=$f
    sleep 0.2
  done
  kill $PID 2>/dev/null; wait $PID 2>/dev/null
  sleep 1

  temp=$(awk '{printf "%.0f°C", $1/1000}' "$HW" 2>/dev/null)
  avg=$(( sum / n ))
  printf '%-22s %-22s %8s MHz %8s MHz %8s MHz %8s %s\n' "$prof" "$readback" "$cap" "$maxf" "$avg" "$temp" "${fw:-?}"
done

echo "-----------------------------------------------------------------------------------------------------"
echo "判读方法："
echo "  · 写入被拒 / 回读不一致 -> 该值在本机无效（balanced 就是这种，驱动直接返回 -EOPNOTSUPP）"
echo "  · 频率上限不同          -> 该档位对最高频率做了硬件级封顶"
echo "  · 上限相同但负载均值不同 -> 差别在功耗/温度墙，不在频率上限"
echo "  · 固件 0x230            -> 0=Turbo 1=Balance 2=Silence；与平台档位对得上说明 EC 双向同步"
