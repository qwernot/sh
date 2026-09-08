#!/usr/bin/env bash
set -Eeuo pipefail

FRP_VERSION="${FRP_VERSION:-0.69.0}"
FRP_TOKEN="${FRP_TOKEN:-ai123456}"
DASHBOARD_USER="${DASHBOARD_USER:-admin}"
DASHBOARD_PASSWORD="${DASHBOARD_PASSWORD:-ai123456}"

[[ "$(id -u)" == "0" ]] || { echo "请使用 root 运行此脚本" >&2; exit 1; }

case "$(uname -m)" in
  x86_64|amd64) FRP_ARCH="amd64" ;;
  aarch64|arm64) FRP_ARCH="arm64" ;;
  armv7l) FRP_ARCH="arm" ;;
  *) echo "不支持的 CPU 架构：$(uname -m)" >&2; exit 1 ;;
esac

command -v curl >/dev/null 2>&1 || {
  echo "缺少 curl，请先安装：apt-get update && apt-get install -y curl" >&2
  exit 1
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_${FRP_ARCH}.tar.gz"
echo "下载 frp：$URL"
curl -fL --retry 3 "$URL" -o "$TMP_DIR/frp.tgz"

rm -rf "$TMP_DIR/frp"
mkdir -p "$TMP_DIR/frp" /opt/frp /etc/frp
tar -xzf "$TMP_DIR/frp.tgz" -C "$TMP_DIR/frp" --strip-components=1
install -m 0755 "$TMP_DIR/frp/frps" /opt/frp/frps

cat > /etc/frp/frps.toml <<EOF
bindAddr = "0.0.0.0"
bindPort = 7000

auth.method = "token"
auth.token = "$FRP_TOKEN"

webServer.addr = "0.0.0.0"
webServer.port = 7500
webServer.user = "$DASHBOARD_USER"
webServer.password = "$DASHBOARD_PASSWORD"
EOF

cat > /etc/systemd/system/frps.service <<'EOF'
[Unit]
Description=frp server
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/opt/frp/frps -c /etc/frp/frps.toml
Restart=always
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

chmod 0600 /etc/frp/frps.toml
systemctl daemon-reload
systemctl enable --now frps

echo
echo "frps 部署完成"
echo "客户端端口：7000"
echo "Dashboard：http://$(hostname -I | awk '{print $1}'):7500"
echo "Dashboard 账号：$DASHBOARD_USER"
echo "Dashboard 密码：$DASHBOARD_PASSWORD"
echo "frp Token：$FRP_TOKEN"
echo
echo "请在云安全组放行 TCP 7000、TCP 7500，以及需要映射的 TCP/UDP 端口。"
systemctl --no-pager --full status frps | sed -n '1,12p'
