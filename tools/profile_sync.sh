#!/bin/bash
# profile_sync.sh —— 把 Fn+K 的 EC 档位变化同步到 cpufreq（governor + EPP）
#
# 背景：这台机器的 Fn+K 只会改 ACPI platform_profile（EC 固件层），
#       不会动 kernel 的 scaling_governor / energy_performance_preference。
#       结果是：EC 在「静谧」档，系统仍用 performance 策略钉死高频，
#       温度降不下来，两边状态还不一致。
#
# 本守护进程轮询 platform_profile，一旦变化就立刻写入配套的 governor + EPP，
# 让 Fn+K 真正做到「一键换档」。
#
# 用法：
#   sudo ./profile_sync.sh              # 前台运行，Ctrl+C 退出
#   安装为开机自启：sudo ./install_profile_sync.sh
#
# 环境变量（调试用）：
#   PP_FILE=/path/to/file   替换 platform_profile 路径（便于本地测试）
#   INTERVAL=0.5            轮询间隔秒
#   DRY_RUN=1               只打印不写入
set -u

PP=${PP_FILE:-/sys/firmware/acpi/platform_profile}
INTERVAL=${INTERVAL:-0.5}
DRY_RUN=${DRY_RUN:-0}
NO_INIT=${NO_INIT:-0}

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

# 档位 -> (governor, epp)  与 perfmode.sh 保持完全一致
map_profile() {
  case "$1" in
    low-power)            echo "powersave power" ;;
    balanced)             echo "powersave balance_power" ;;
    balanced-performance) echo "powersave balance_performance" ;;
    performance)          echo "performance performance" ;;
    *)                    echo "" ;;
  esac
}

# 注意顺序：amd-pstate-epp 在 governor=performance 时会把 EPP 锁成 performance，
# 所以必须先改 governor 放开 EPP，再写 EPP。反过来会静默失败。
apply_profile() {
  local prof=$1 gov epp p
  read -r gov epp <<<"$(map_profile "$prof")"
  if [ -z "$gov" ]; then
    log "未知档位「$prof」，跳过"
    return 1
  fi

  if [ "$DRY_RUN" = "1" ]; then
    log "DRY_RUN: $prof -> governor=$gov epp=$epp"
    return 0
  fi

  local pols
  pols=$(ls -d /sys/devices/system/cpu/cpufreq/policy* 2>/dev/null)
  [ -z "$pols" ] && pols=$(ls -d /sys/devices/system/cpu/cpu[0-9]* 2>/dev/null)

  local ok=0 fail=0
  for p in $pols; do
    [ -w "$p/cpufreq/scaling_governor" ] || continue
    if echo "$gov" > "$p/cpufreq/scaling_governor" 2>/dev/null; then
      echo "$epp" > "$p/cpufreq/energy_performance_preference" 2>/dev/null && ok=$((ok+1)) || ok=$((ok+1))
    else
      fail=$((fail+1))
    fi
  done

  if [ "$fail" -gt 0 ] && [ "$ok" -eq 0 ]; then
    log "写入失败（需要 root 权限？）"
    return 1
  fi
  log "已同步 $prof -> governor=$gov epp=$epp（$ok 个核）"
}

[ -r "$PP" ] || { echo "读不到 $PP，本机可能不支持 platform_profile"; exit 1; }
if [ "$(id -u)" -ne 0 ] && [ "$DRY_RUN" != "1" ]; then
  echo "需要 root：sudo $0" >&2
  exit 1
fi

log "启动，监听 $PP（间隔 ${INTERVAL}s）"
log "可选档位: $(cat /sys/firmware/acpi/platform_profile_choices 2>/dev/null)"

cur=$(cat "$PP" 2>/dev/null)
log "当前: $cur -> governor=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_governor 2>/dev/null) epp=$(cat /sys/devices/system/cpu/cpufreq/policy0/energy_performance_preference 2>/dev/null)"

# 启动时按当前档位对齐一次（如需保留现状可设 NO_INIT=1）
if [ "$NO_INIT" != "1" ]; then
  apply_profile "$cur"
fi

trap 'log "退出"; exit 0' INT TERM

while true; do
  sleep "$INTERVAL"
  new=$(cat "$PP" 2>/dev/null)
  [ -z "$new" ] && continue
  if [ "$new" != "$cur" ]; then
    # EC 连续拨档时会有中间态，稍微等一下再读，取稳定值
    sleep 0.3
    stable=$(cat "$PP" 2>/dev/null)
    [ -n "$stable" ] && new=$stable
    # 稳定后又回到原档位，说明只是路过，不用动
    [ "$new" = "$cur" ] && continue
    log "档位 $cur -> $new"
    apply_profile "$new"
    cur=$new
  fi
done
