#!/bin/bash
# install.sh —— 让 KDE 的三档直接驱动本机 EC 三档
#
# 做什么：
#   1. 停用并 mask power-profiles-daemon（否则两边抢同一个 D-Bus 名字）
#   2. 装 /usr/local/bin/redmi-profile-bridge 与 systemd 单元
#   3. 把 D-Bus 激活文件指向本服务（原来是 ppd）
#   4. 启动并做一次端到端验证
#
# 用法：sudo ./install.sh
# 卸载：sudo ./uninstall.sh
set -eu

cd "$(dirname "$0")"
[ "$(id -u)" -eq 0 ] || exec sudo -E "$0" "$@"

BIN=/usr/local/bin/redmi-profile-bridge
UNIT=/etc/systemd/system/redmi-profile-bridge.service
DBUS_SVC=/usr/share/dbus-1/system-services/org.freedesktop.UPower.PowerProfiles.service
BACKUP=/usr/local/share/redmi-profile-bridge

echo "== 1/5 停用 power-profiles-daemon =="
if systemctl list-unit-files power-profiles-daemon.service >/dev/null 2>&1; then
  systemctl disable --now power-profiles-daemon 2>/dev/null || true
  systemctl mask power-profiles-daemon 2>/dev/null || true
  echo "   已 mask（Masked 后 D-Bus 也无法把它激活起来）"
else
  echo "   未安装，跳过"
fi

echo "== 2/5 安装服务程序 =="
install -Dm755 redmi-profile-bridge "$BIN"
echo "   $BIN"

echo "== 3/5 安装 systemd 单元 =="
install -Dm644 redmi-profile-bridge.service "$UNIT"
systemctl daemon-reload
echo "   $UNIT"

echo "== 4/5 接管 D-Bus 激活入口 =="
mkdir -p "$BACKUP"
if [ -f "$DBUS_SVC" ] && [ ! -f "$BACKUP/original-dbus-service" ]; then
  cp -a "$DBUS_SVC" "$BACKUP/original-dbus-service"
fi
cat > "$DBUS_SVC" <<'EOF'
[D-BUS Service]
Name=org.freedesktop.UPower.PowerProfiles
Exec=/bin/false
User=root
SystemdService=redmi-profile-bridge.service
EOF
echo "   激活入口 -> redmi-profile-bridge.service（原件已备份到 $BACKUP）"

echo "== 5/5 启动并验证 =="
systemctl enable --now redmi-profile-bridge
sleep 1
systemctl --no-pager --lines=0 status redmi-profile-bridge || true
echo
echo "--- 总线上的属性 ---"
busctl get-property org.freedesktop.UPower.PowerProfiles \
    /org/freedesktop/UPower/PowerProfiles \
    org.freedesktop.UPower.PowerProfiles ActiveProfile 2>&1 || true
busctl get-property org.freedesktop.UPower.PowerProfiles \
    /org/freedesktop/UPower/PowerProfiles \
    org.freedesktop.UPower.PowerProfiles Profiles 2>&1 || true
echo
echo "--- 当前硬件状态 ---"
../perfmode.sh show 2>/dev/null || cat /sys/firmware/acpi/platform_profile
echo
echo "完成。KDE 的电池托盘 / 系统设置 → 节能，现在三档都可用。"
echo "切档后可看：journalctl -u redmi-profile-bridge -f"
