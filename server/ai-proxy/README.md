# KnoWell AI 转发（Linux + Caddy）

手机不持有 AI Key。Caddy 对外 HTTPS，本服务只监听本机 `127.0.0.1:8787`。

## 1. 域名

给服务器加一个子域名，例如 `api.你的域名.com`，DNS A 记录指向这台机器。

## 2. 安装

```bash
sudo mkdir -p /opt/knowell-ai-proxy /var/lib/knowell-ai-proxy
sudo cp proxy.py /opt/knowell-ai-proxy/proxy.py
sudo chmod 755 /opt/knowell-ai-proxy/proxy.py

sudo cp env.example /etc/knowell-ai-proxy.env
sudo nano /etc/knowell-ai-proxy.env   # 填 APP_TOKEN 和 UPSTREAM_API_KEY

sudo chown -R www-data:www-data /var/lib/knowell-ai-proxy
sudo cp knowell-ai-proxy.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now knowell-ai-proxy
sudo systemctl status knowell-ai-proxy
```

## 3. Caddy

把 `Caddyfile.snippet` 里的站点块加进现有 Caddyfile，域名改成你的，然后：

```bash
sudo systemctl reload caddy
curl -sS https://api.你的域名.com/health
# 应返回 {"ok":true}
```

## 4. 自测转发

```bash
curl -sS https://api.你的域名.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "X-KnoWell-Token: 你的APP_TOKEN" \
  -H "X-Device-Id: test-device" \
  -d '{"model":"deepseek-chat","messages":[{"role":"user","content":"回复一个字：好"}]}'
```

401 = Token 不对；429 = 这台设备今日次数用完。

## 5. 再改 App

把域名和 `APP_TOKEN` 发给我，我会把 KnoWell 默认地址改成这个接口，用户不用填 Key。
