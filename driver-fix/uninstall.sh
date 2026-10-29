#!/bin/bash
# uninstall.sh —— 卸载 DKMS 修复版，恢复系统自带驱动
#
# 用法：sudo ./uninstall.sh

set -eu
cd "$(dirname "$0")"
[ "$(id -u)" -eq 0 ] || exec sudo -E "$0" "$@"

PKG=bitland-mifs-wmi
VER=1.1
KVER=$(uname -r)

echo "== 1/4 移除 DKMS 模块 =="
dkms remove -m "$PKG" -v "$VER" --all 2>/dev/null && echo "   已移除" || echo "   未安装，跳过"
rm -rf "/usr/src/$PKG-$VER"
depmod -a

echo "== 2/4 重新加载系统模块 =="
modprobe -r bitland_mifs_wmi 2>/dev/null || true
modprobe bitland_mifs_wmi
sleep 1
echo "   当前：$(modinfo -F filename bitland_mifs_wmi 2>/dev/null || echo 未知)"

echo "== 3/4 确认档位接口 =="
cat /sys/firmware/acpi/platform_profile 2>/dev/null || echo "   platform_profile 不存在"

echo "== 4/4 备份文件 =="
ls -l /root/bitland-bak/ 2>/dev/null || echo "   无备份"

echo
echo "已恢复系统自带驱动。此时 performance / balanced-performance 会重新变成不可写。"
echo "如需连 KDE 桥接一起撤掉：sudo ../kde-bridge/uninstall.sh"
