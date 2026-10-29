#!/bin/bash
# test.sh —— 在私有会话总线上端到端验证 redmi-profile-bridge
# 不碰系统总线、不写 sysfs（DRY_RUN=1），可在任何环境安全运行。
# 用法：./test.sh        （会自动用 dbus-run-session 包一层私有总线）
set -u
cd "$(dirname "$0")"

# 必须跑在干净的私有总线上：真实系统服务已占着 org.freedesktop.UPower.PowerProfiles，
# 在用户会话总线上跑会直接撞名失败，也可能干扰正在用的桥接服务。
if [ "${BRIDGE_TEST_REEXEC:-0}" != "1" ]; then
  command -v dbus-run-session >/dev/null 2>&1 || {
    echo "缺少 dbus-run-session（dbus 包）"; exit 1; }
  export BRIDGE_TEST_REEXEC=1
  exec dbus-run-session -- bash "$0" "$@"
fi

[ -f ./pp_test ] || printf 'low-power\n' > ./pp_test

BUS_TYPE=session DRY_RUN=1 PP_PATH=./pp_test /usr/bin/python3 ./redmi-profile-bridge &
PID=$!
sleep 1.5

B="busctl --address=$DBUS_SESSION_BUS_ADDRESS"
DEST=org.freedesktop.UPower.PowerProfiles
PATH_=/org/freedesktop/UPower/PowerProfiles
IFACE=org.freedesktop.UPower.PowerProfiles

echo "===== 1. 接口是否完整 ====="
$B introspect "$DEST" "$PATH_" "$IFACE" 2>&1 | sed -n '1,40p'

echo
echo "===== 2. 初始 ActiveProfile ====="
$B get-property "$DEST" "$PATH_" "$IFACE" ActiveProfile 2>&1

echo
echo "===== 3. Profiles（KDE 靠这个渲染档位列表）====="
$B get-property "$DEST" "$PATH_" "$IFACE" Profiles 2>&1

echo
echo "===== 4. 设为 balanced ====="
$B set-property "$DEST" "$PATH_" "$IFACE" ActiveProfile s balanced 2>&1
$B get-property "$DEST" "$PATH_" "$IFACE" ActiveProfile 2>&1

echo
echo "===== 5. 设为 performance ====="
$B set-property "$DEST" "$PATH_" "$IFACE" ActiveProfile s performance 2>&1
$B get-property "$DEST" "$PATH_" "$IFACE" ActiveProfile 2>&1

echo
echo "===== 6. 非法档位应被拒绝 ====="
$B set-property "$DEST" "$PATH_" "$IFACE" ActiveProfile s bogus 2>&1 | head -2

echo
echo "===== 7. HoldProfile / ReleaseProfile ====="
COOKIE=$($B call "$DEST" "$PATH_" "$IFACE" HoldProfile sss performance "video playback" org.kde.test 2>&1)
echo "HoldProfile -> $COOKIE"
$B get-property "$DEST" "$PATH_" "$IFACE" ActiveProfileHolds 2>&1 | cut -c1-160
N=$(echo "$COOKIE" | tr -dc '0-9')
$B call "$DEST" "$PATH_" "$IFACE" ReleaseProfile u "$N" 2>&1
$B get-property "$DEST" "$PATH_" "$IFACE" ActiveProfileHolds 2>&1

echo
echo "===== 8. 外部改动 platform_profile 后是否自动同步 ====="
printf 'balanced-performance\n' > ./pp_test
sleep 1.5
echo -n "回读 ActiveProfile: "; $B get-property "$DEST" "$PATH_" "$IFACE" ActiveProfile 2>&1

kill "$PID" 2>/dev/null
wait "$PID" 2>/dev/null
printf 'low-power\n' > ./pp_test
echo
echo "测试结束"
