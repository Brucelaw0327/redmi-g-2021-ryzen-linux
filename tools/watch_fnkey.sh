#!/bin/bash
# 监听性能模式档位变化 —— 按 Fn+K 时看这里有没有反应（不需要 root，不需要 dmesg）
# 用法: ./watch_fnkey.sh [轮询间隔秒，默认 0.5]

PP=/sys/firmware/acpi/platform_profile
TEMP=/sys/class/hwmon/hwmon5/temp1_input
INTERVAL=${1:-0.5}

command -v bc >/dev/null 2>&1 || true

if [ ! -r "$PP" ]; then
  echo "读不到 $PP —— 该机型可能没有 redmi_wmi / platform_profile 支持"
  exit 1
fi

last=$(cat "$PP")
changes=0
ticks=0

echo "当前档位: $last"
echo "现在按 Fn+K 切换模式，观察下面是否出现「档位 A -> B」"
echo "----------------------------------------------------------"

trap 'echo; echo "结束：共捕获 $changes 次切换"; exit 0' INT TERM

while :; do
  cur=$(cat "$PP" 2>/dev/null)
  if [ "$cur" != "$last" ]; then
    ts=$(date +%H:%M:%S)
    tc=$(awk '{printf "%.0f", $1/1000}' "$TEMP" 2>/dev/null)
    f0=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null)
    gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)
    printf '[%s] 档位 %s -> %s   CPU %s°C  cpu0 %sMHz  governor=%s\n' \
      "$ts" "$last" "$cur" "${tc:-?}" "$(( ${f0:-0} / 1000 ))" "${gov:-?}"
    last=$cur
    changes=$((changes + 1))
  fi

  # 每 20 个周期点一个点，表示还在监听
  ticks=$((ticks + 1))
  if [ $((ticks % 20)) -eq 0 ]; then printf '.'; fi

  sleep "$INTERVAL"
done
