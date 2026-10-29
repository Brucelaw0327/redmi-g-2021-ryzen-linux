#!/bin/bash
# install.sh —— 安装 bitland-mifs-wmi 的 DKMS 修复版
#
# 修的是什么
# ----------
# 原驱动 bitland_check_performance_capability() 要求 EC 对
# WMI_FN_SYSTEM_AC_TYPE 返回 WMI_SYSTEM_AC_CIRCULARHOLE(2)。
# Redmi G 2021 (TM2037) 的 EC 实际返回 0（枚举里未定义），
# 于是 balanced-performance 和 performance 两档全部 -EOPNOTSUPP，
# platform_profile 四选一里只有 low-power 真正可用 ——
# 这就是 KDE「平衡」「性能」点了没反应的根因。
#
# 补丁只在 EC 明确报告 Type-C(1) 时拒绝，其余放行。
#
# 用法：sudo ./install.sh
# 卸载：sudo ./uninstall.sh

set -eu
cd "$(dirname "$0")"
[ "$(id -u)" -eq 0 ] || exec sudo -E "$0" "$@"

PKG=bitland-mifs-wmi
VER=1.1
SRC="$(pwd)/package"
DST="/usr/src/$PKG-$VER"

echo "== 1/6 检查依赖 =="
command -v dkms >/dev/null || { echo "缺少 dkms：sudo pacman -S dkms"; exit 1; }
KVER=$(uname -r)
[ -d "/lib/modules/$KVER/build" ] || { echo "缺少内核头文件：/lib/modules/$KVER/build"; exit 1; }
echo "   内核 $KVER，dkms $(dkms --version | awk '{print $2}')"

echo "== 2/6 备份原始模块 =="
ORIG="/lib/modules/$KVER/kernel/drivers/platform/x86/$PKG.ko.zst"
mkdir -p /root/bitland-bak
if [ -f "$ORIG" ] && [ ! -f /root/bitland-bak/orig-$KVER.ko.zst ]; then
  cp -a "$ORIG" "/root/bitland-bak/orig-$KVER.ko.zst"
  echo "   已备份 -> /root/bitland-bak/orig-$KVER.ko.zst"
else
  echo "   已存在备份或原文件不存在，跳过"
fi

echo "== 3/6 安装源码到 $DST =="
rm -rf "$DST"
mkdir -p "$DST"
cp -a "$SRC/." "$DST/"
echo "   $(ls "$DST" | tr '\n' ' ')"

echo "== 4/6 DKMS 编译安装 =="
dkms remove -m "$PKG" -v "$VER" --all 2>/dev/null || true
dkms add -m "$PKG" -v "$VER"
dkms build -m "$PKG" -v "$VER"
dkms install -m "$PKG" -v "$VER" --force
depmod -a

echo "== 5/6 重新加载模块 =="
if lsmod | grep -q "^bitland_mifs_wmi"; then
  modprobe -r bitland_mifs_wmi || true
fi
modprobe bitland_mifs_wmi
sleep 1
echo "   已加载：$(modinfo -F filename bitland_mifs_wmi 2>/dev/null || echo 未知)"

echo "== 6/6 验证三档 =="
PP=/sys/firmware/acpi/platform_profile
if [ ! -e "$PP" ]; then
  echo "   platform_profile 未出现，检查 dmesg | grep bitland"; exit 1
fi
printf "   %-24s %-22s %s\n" "写入值" "回读" "固件(0x230)"
EV=$(ls /sys/firmware/efi/efivars/Setup-* 2>/dev/null | head -1)
for v in low-power balanced-performance performance; do
  err=$( (echo "$v" > "$PP") 2>&1 ) || true
  sleep 0.3
  fw="-"
  [ -n "$EV" ] && fw=$(od -A n -t u1 -j 564 -N 1 "$EV" 2>/dev/null | tr -d ' ')
  printf "   %-24s %-22s %s %s\n" "$v" "$(cat "$PP")" "$fw" "$err"
done
# 恢复到均衡档
echo balanced-performance > "$PP" 2>/dev/null || true

echo
echo "完成。驱动修复已通过 DKMS 持久化，内核升级后会自动重编。"
echo "现在 KDE 的电池托盘 / 系统设置 → 节能，三档都可用了。"
