#!/bin/bash
# 采样 CPU 温度 / 频率 / 负载，输出 CSV
DUR=${1:-60}
STEP=${2:-2}
TEMP=/sys/class/hwmon/hwmon5/temp1_input
echo "t,sec,tctl_c,avg_mhz,max_mhz,min_mhz,load"
T0=$(date +%s.%N)
i=0
while true; do
  NOW=$(date +%s.%N)
  EL=$(awk -v a="$T0" -v b="$NOW" 'BEGIN{printf "%.1f", b-a}')
  [ $(awk -v e="$EL" -v d="$DUR" 'BEGIN{print (e>=d)?1:0}') -eq 1 ] && break
  T=$(awk '{printf "%.1f", $1/1000}' $TEMP)
  F=$(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq)
  read AVG MAX MIN <<< $(echo "$F" | awk '{s+=$1; if($1>m||NR==1)m=$1; if($1<n||NR==1)n=$1} END{printf "%.0f %.0f %.0f", s/NR/1000, m/1000, n/1000}')
  L=$(awk '{print $1}' /proc/loadavg)
  echo "$i,$EL,$T,$AVG,$MAX,$MIN,$L"
  i=$((i+1))
  sleep $STEP
done
