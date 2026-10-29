#!/bin/bash
# uninstall.sh —— 撤销 KDE 档位桥接，恢复 ppd
#
# 用法：sudo ./uninstall.sh
set -eu

[ "$(id -u)" -eq 0 ] || exec sudo -E "$0" "$@"

BIN=/usr/local/bin/redmi-profile-bridge
UNIT=/etc/systemd/system/redmi-profile-bridge.service
DBUS_SVC=/usr/share/dbus-1/system-services/org.freedesktop.UPower.PowerProfiles.service
BACKUP=/usr/local/share/redmi-profile-bridge

echo "== 1/4 停用并移除服务 =="
systemctl disable --now redmi-profile-bridge 2>/dev/null || true
rm -f "$UNIT" "$BIN"
systemctl daemon-reload
echo "   已移除"

echo "== 2/4 恢复 D-Bus 激活入口 =="
if [ -f "$BACKUP/original-dbus-service" ]; then
  cp -a "$BACKUP/original-dbus-service" "$DBUS_SVC"
  echo "   已恢复原文件"
else
  rm -f "$DBUS_SVC"
  echo "   无备份，已删除（ppd 重新安装会自带）"
fi

echo "== 3/4 解除 ppd 的 mask =="
systemctl unmask power-profiles-daemon 2>/dev/null || true

echo "== 4/4 按需恢复 ppd =="
echo -n "   是否现在启动 power-profiles-daemon？[y/N] "
read -r ans || ans=n
case "$ans" in
  [yY]*) systemctl start power-profiles-daemon && echo "   已启动" ;;
  *) echo "   保持停止（KDE 的档位控件会消失，直到 ppd 启动）" ;;
esac
echo "完成。硬件三档仍可用：./perfmode.sh quiet|balanced|turbo"
