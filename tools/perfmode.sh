#!/bin/bash
# Redmi G 2021 性能模式切换 —— Linux 下替代 Windows「小米游戏盒子 GamingBox」
#
# 本机固件只有三个档位，对应 BIOS Setup 变量 offset 0x230：
#   0 = Turbo Mode（极速）  1 = Balance Mode（均衡）  2 = Silence Mode（静谧）
#
# 三档映射（已通过逐档写测 + efivarfs 交叉核对确认）：
#
#   静谧 quiet    -> low-power            -> 0x230 = 2 = Silence
#   均衡 balanced -> balanced-performance -> 0x230 = 1 = Balance
#   极速 turbo    -> performance          -> 0x230 = 0 = Turbo
#
# 两个坑，别踩：
#   1. balanced 是幽灵值。ACPI 的 choices 里有它，驱动也照收，但固件不认识，
#      写完回读还是旧值（假成功）。均衡档必须写 balanced-performance。
#   2. 驱动的 WMI 值序和固件 Setup 值序不一样（驱动 0=均衡/1=极速/2=静谧）。
#      判断真实状态必须读 efivarfs，不能只看 platform_profile。
#
# 依赖：内核 bitland_mifs_wmi（提供 platform_profile）+ ACPI
set -u

PP=/sys/firmware/acpi/platform_profile
CH=/sys/firmware/acpi/platform_profile_choices
LED=/sys/class/leds/bitland-mifs-wmi::kbd_backlight

usage() {
  cat <<'EOF'
用法: ./perfmode.sh <档位>

  quiet|静谧     低功耗优先，风扇最安静   -> low-power
  balanced|均衡  日常办公 / 游戏         -> balanced-performance
  turbo|极速     满血释放，风扇最吵       -> performance

  acpi <值>      直接写 ACPI 档位（balanced 会被驱动拒绝，返回 -EOPNOTSUPP）
  kbd N          键盘背光亮度 0-3
  show           查看当前状态（含固件侧真实档位）
EOF
  exit "${1:-0}"
}

need_root() {
  [ "$(id -u)" -eq 0 ] && return
  command -v sudo >/dev/null || { echo "需要 root 权限"; exit 1; }
  exec sudo -E "$0" "$@"
}

# ppd 或 KDE 桥接服务都会同时管理 platform_profile 与 governor/EPP，与本脚本互相覆盖。
check_conflict() {
  local active=0 name=""
  if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet power-profiles-daemon 2>/dev/null; then
    active=1; name="power-profiles-daemon"
  elif pgrep -x power-profiles-daemon >/dev/null 2>&1; then
    active=1; name="power-profiles-daemon"
  elif command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet redmi-profile-bridge 2>/dev/null; then
    active=1; name="redmi-profile-bridge"
  fi
  [ "$active" = "1" ] || return 0
  [ "${FORCE:-0}" = "1" ] && { echo "FORCE=1：无视 $name 冲突继续" >&2; return 0; }
  cat >&2 <<EOF
检测到 $name 正在运行。
它会同时写入 platform_profile 和 governor/EPP，与本脚本互相覆盖，切档会「弹回去」。

  想交给 KDE 统一管理：  cd ../kde-bridge && sudo ./install.sh
  坚持用本脚本：         sudo systemctl disable --now $name
                        然后 FORCE=1 ./perfmode.sh ...
EOF
  exit 1
}

apply() {
  local prof=$1 gov=$2 epp=$3
  echo "$prof" > "$PP" || { echo "写入 $PP 失败"; exit 1; }
  local c
  # 顺序很重要：amd-pstate-epp 在 governor=performance 时会把 EPP 锁成 performance，
  # 必须先改 governor 放开 EPP，再写 EPP；反过来写会静默失败。
  for c in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    echo "$gov" > "$c" 2>/dev/null
  done
  for c in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
    echo "$epp" > "$c" 2>/dev/null
  done

  local rp rg re cap
  rp=$(cat "$PP" 2>/dev/null)
  rg=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)
  re=$(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null)
  cap=$(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null)
  echo "已切换 -> $rp（governor=$rg, epp=$re, 频率上限 $((cap / 1000)) MHz）"
  [ "$rp" = "$prof" ] || echo "  ⚠ 回读不一致：写入 $prof，实际 $rp（EC 可能不接受该档位）" >&2
  [ "$rg" = "$gov"  ] || echo "  ⚠ governor 未生效，期望 $gov" >&2
  [ "$re" = "$epp"  ] || echo "  ⚠ epp 未生效，期望 $epp" >&2
}

# 从 BIOS 的 Setup UEFI 变量读固件侧真实档位：
# offset 0x230，0=Turbo Mode / 1=Balance Mode / 2=Silence Mode。
# 文件前 4 字节是 efivarfs 属性头，所以实际偏移是 4+0x230=564。
bios_mode() {
  local f b
  f=$(ls /sys/firmware/efi/efivars/Setup-* 2>/dev/null | head -1)
  [ -n "$f" ] || { echo "读不到 Setup 变量"; return 1; }
  b=$(od -A n -t u1 -j 564 -N 1 "$f" 2>/dev/null | tr -d ' \n')
  case "$b" in
    0) echo "极速 Turbo Mode   (0x230=0)" ;;
    1) echo "均衡 Balance Mode (0x230=1)" ;;
    2) echo "静谧 Silence Mode (0x230=2)" ;;
    *) echo "未知值 0x230=$b" ;;
  esac
}

show() {
  local cap
  cap=$(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null)
  echo "平台档位 : $(cat "$PP" 2>/dev/null)"
  echo "固件档位 : $(bios_mode 2>/dev/null)"
  echo "可选档位 : $(cat "$CH" 2>/dev/null)"
  echo "governor : $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)"
  echo "EPP      : $(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null)"
  echo "频率上限 : $((cap / 1000)) MHz"
  echo "CPU 温度 : $(awk '{printf "%.0f°C", $1/1000}' /sys/class/hwmon/hwmon5/temp1_input 2>/dev/null)"
  echo "键盘背光 : $(cat "$LED/brightness" 2>/dev/null)/$(cat "$LED/max_brightness" 2>/dev/null)"
  if command -v nvidia-smi >/dev/null 2>&1; then
    local g
    g=$(nvidia-smi --query-gpu=temperature.gpu,power.draw,power.limit \
        --format=csv,noheader 2>/dev/null | head -1)
    case "$g" in
      ""|*failed*|*NVIDIA-SMI*) : ;;
      *) echo "独显     : $g" ;;
    esac
  fi
}

case "${1:-show}" in
  quiet|silent|静谧)  need_root "$@"; check_conflict; apply low-power            powersave power ;;
  balanced|均衡)      need_root "$@"; check_conflict; apply balanced-performance powersave balance_performance ;;
  turbo|极速|perf)    need_root "$@"; check_conflict; apply performance          performance performance ;;
  acpi)
    need_root "$@"
    [ -n "${2:-}" ] || { echo "用法: ./perfmode.sh acpi <low-power|balanced|balanced-performance|performance>"; exit 1; }
    if [ "$2" = "balanced" ]; then
      echo "注意：balanced 在本机不受支持（bitland-mifs-wmi 的 set() 直接返回 -EOPNOTSUPP）。" >&2
      echo "      均衡档请用 ./perfmode.sh balanced（写入 balanced-performance）。" >&2
    fi
    check_conflict
    apply "$2" powersave balance_power
    ;;
  kbd)
    need_root "$@"
    v=${2:-0}
    [ "$v" -ge 0 ] && [ "$v" -le 3 ] || { echo "亮度只能是 0-3"; exit 1; }
    echo "$v" > "$LED/brightness" && echo "键盘背光 -> $v"
    ;;
  show)  show ;;
  -h|--help|help) usage 0 ;;
  *) usage 1 ;;
esac
