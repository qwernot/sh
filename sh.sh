#!/usr/bin/env bash

# 脚本配置
FRP_VERSION="${FRP_VERSION:-0.69.0}"
FRP_TOKEN="${FRP_TOKEN:-ai123456}"
DASHBOARD_USER="${DASHBOARD_USER:-admin}"
DASHBOARD_PASSWORD="${DASHBOARD_PASSWORD:-ai123456}"

# 1. 检查是否为 root 用户
[[ "$(id -u)" == "0" ]] || { echo "请使用 root 运行此脚本" >&2; exit 1; }

# 2. 检查 CPU 架构
case "$(uname -m)" in
  x86_64|amd64) FRP_ARCH="amd64" ;;
  aarch64|arm64) FRP_ARCH="arm64" ;;
  armv7l) FRP_ARCH="arm" ;;
  *) echo "不支持的 CPU 架构：$(uname -m)" >&2; exit 1 ;;
esac

# 3. 检查并安装依赖
command -v curl >/dev/null 2>&1 || {
  echo "缺少 curl，正在尝试安装..."
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update && apt-get install -y curl
  elif command -v yum >/dev/null 2>&1; then
    yum install -y curl
  else
    echo "无法安装 curl，请手动安装后重试。" >&2
    exit 1
  fi
}

# 4. 下载并解压 FRP
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_${FRP_ARCH}.tar.gz"
echo "下载 frp：$URL"
curl -fL --retry 3 "$URL" -o "$TMP_DIR/frp.tgz"

# 创建安装目录
mkdir -p /opt/frp /etc/frp

# 解压文件
tar -xzf "$TMP_DIR/frp.tgz" -C "$TMP_DIR" --strip-components=1
install -m 0755 "$TMP_DIR/frps" /opt/frp/frps

# 5. 生成配置文件
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

chmod 0600 /etc/frp/frps.toml

# 6. 启动 FRP 服务 (使用 nohup 替代 systemctl)
echo "正在启动 frps 服务..."
nohup /opt/frp/frps -c /etc/frp/frps.toml > /var/log/frps.log 2>&1 &

# 简单等待一下，让进程有时间启动
sleep 2

# 检查进程是否成功启动
if pgrep -f "/opt/frp/frps" > /dev/null; then
  echo "frps 部署并启动成功！"
  echo "----------------------------------------"
  echo "客户端连接端口：7000"
  echo "Dashboard 地址：http://$(hostname -I | awk '{print $1}'):7500"
  echo "Dashboard 账号：$DASHBOARD_USER"
  echo "Dashboard 密码：$DASHBOARD_PASSWORD"
  echo "frp Token：$FRP_TOKEN"
  echo "----------------------------------------"
  echo "请在云服务商的安全组中放行 TCP 7000 和 TCP 7500 端口。"
else
  echo "frps 启动失败，请检查日志：cat /var/log/frps.log" >&2
  exit 1
fi
