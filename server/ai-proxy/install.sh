#!/bin/bash
# 上传本目录后：sudo bash install.sh
# 必需文件只有这一份脚本 + proxy.py
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR=/opt/knowell-ai-proxy
DATA_DIR=/var/lib/knowell-ai-proxy
ENV_FILE=/etc/knowell-ai-proxy.env
UNIT_FILE=/etc/systemd/system/knowell-ai-proxy.service

if [[ "$(id -u)" -ne 0 ]]; then
  echo "请用 root 运行：sudo bash install.sh" >&2
  exit 1
fi

if [[ ! -f "$SRC/proxy.py" ]]; then
  echo "同目录缺少 proxy.py" >&2
  exit 1
fi

PYTHON=""
for cand in python3.11 python3.12 python3.9 python3; do
  if command -v "$cand" >/dev/null 2>&1; then
    PYTHON="$(command -v "$cand")"
    break
  fi
done
if [[ -z "$PYTHON" ]]; then
  echo "安装 python3 ..."
  if command -v yum >/dev/null 2>&1; then
    yum install -y python3.11 || yum install -y python39 || yum install -y python3
  else
    apt-get update && apt-get install -y python3
  fi
  for cand in python3.11 python3.12 python3.9 python3; do
    if command -v "$cand" >/dev/null 2>&1; then
      PYTHON="$(command -v "$cand")"
      break
    fi
  done
fi
if [[ -z "$PYTHON" ]]; then
  echo "找不到 python3" >&2
  exit 1
fi
echo "使用 $PYTHON"

RUN_USER=caddy
if ! id -u "$RUN_USER" >/dev/null 2>&1; then
  if id -u nginx >/dev/null 2>&1; then
    RUN_USER=nginx
  else
    RUN_USER=nobody
  fi
fi

mkdir -p "$BIN_DIR" "$DATA_DIR"
cp "$SRC/proxy.py" "$BIN_DIR/proxy.py"
chmod 755 "$BIN_DIR/proxy.py"

if [[ ! -f "$ENV_FILE" ]]; then
  TOKEN="$(openssl rand -hex 24 2>/dev/null || "$PYTHON" -c 'import secrets; print(secrets.token_hex(24))')"
  cat > "$ENV_FILE" <<EOF
APP_TOKEN=${TOKEN}
UPSTREAM_API_KEY=
UPSTREAM_BASE=https://api.deepseek.com/v1
UPSTREAM_MODEL=deepseek-chat
DAILY_LIMIT=20
LISTEN_HOST=127.0.0.1
LISTEN_PORT=8787
DATA_DIR=${DATA_DIR}
EOF
  chmod 600 "$ENV_FILE"
  echo "已生成 $ENV_FILE"
  echo "APP_TOKEN=${TOKEN}"
else
  echo "保留已有 $ENV_FILE"
  TOKEN="$(grep '^APP_TOKEN=' "$ENV_FILE" | cut -d= -f2-)"
fi

cat > "$UNIT_FILE" <<EOF
[Unit]
Description=KnoWell AI proxy
After=network.target

[Service]
Type=simple
EnvironmentFile=${ENV_FILE}
ExecStart=${PYTHON} ${BIN_DIR}/proxy.py
Restart=on-failure
RestartSec=3
User=${RUN_USER}
Group=${RUN_USER}
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=${DATA_DIR}
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

chown -R "$RUN_USER:$RUN_USER" "$DATA_DIR"
systemctl daemon-reload
systemctl enable --now knowell-ai-proxy
sleep 1
systemctl --no-pager --full status knowell-ai-proxy || true

echo
echo "本机探测：curl -sS http://127.0.0.1:8787/health"
curl -sS http://127.0.0.1:8787/health || true
echo
echo "Caddy 增加（把域名换成你的，然后 reload caddy）："
echo
echo "api.你的域名.com {"
echo "    reverse_proxy 127.0.0.1:8787"
echo "}"
echo
echo "APP_TOKEN=${TOKEN}"
echo "还要填写：sudo nano ${ENV_FILE} 里的 UPSTREAM_API_KEY"
