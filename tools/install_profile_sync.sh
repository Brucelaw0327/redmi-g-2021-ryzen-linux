#!/bin/bash
# 把 profile_sync.sh 装成开机自启的 systemd 服务
# 用法：sudo ./install_profile_sync.sh          # 安装并启动
#       sudo ./install_profile_sync.sh remove   # 卸载
set -eu

DIR=$(cd "$(dirname "$0")" && pwd)
UNIT=/etc/systemd/system/redmi-profile-sync.service
NAME=redmi-profile-sync

[ "$(id -u)" -eq 0 ] || { echo "请用 sudo 运行"; exit 1; }

if [ "${1:-}" = "remove" ]; then
  systemctl disable --now "$NAME" 2>/dev/null || true
  rm -f "$UNIT"
  systemctl daemon-reload
  echo "已卸载 $NAME"
  exit 0
fi

chmod +x "$DIR/profile_sync.sh"

cat > "$UNIT" <<EOF
[Unit]
Description=Sync ACPI platform_profile (Fn+K) to cpufreq governor/EPP
After=multi-user.target

[Service]
Type=simple
ExecStart=$DIR/profile_sync.sh
Restart=always
RestartSec=2
Nice=-5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now "$NAME"
sleep 1
systemctl --no-pager --lines=6 status "$NAME" || true
echo
echo "完成。查看实时日志： journalctl -u $NAME -f"
echo "按 Fn+K 切换档位，日志里应出现「已同步 ... -> governor=... epp=...」"
