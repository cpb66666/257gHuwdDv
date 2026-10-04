#!/usr/bin/env bash
set -e

# ================= 1. 基础配置与参数解析 =================
# 面板地址（可通过外部环境变量 API_HOST 动态覆盖，否则使用默认）
API_HOST="${API_HOST:-http://vtwo.subscription.men}"

# 参数顺序：
# $1: 节点 ID
# $2: 解析域名
# $3: 协议编号/名称 (默认 8: AnyTLS)
# $4: 通信密钥 API Key (可选，更推荐通过环境变量 API_KEY 传入)
NODE_ID="$1"
CERT_DOMAIN="$2"
RAW_TYPE="${3:-8}"

# 通信密钥优先级：环境变量 API_KEY > 第 4 个参数 > 终端交互提示
API_KEY="${API_KEY:-$4}"

# 如果均未获取到 API_KEY，则进行交互式输入（密码模式不回显）
if [ -z "$API_KEY" ]; then
    read -s -rp "请输入面板通信密钥 (API Key): " API_KEY
    echo ""
fi

if [ -z "$API_KEY" ]; then
    echo "❌ 错误: 未检测到 API Key，安装终止！"
    exit 1
fi

# 检查节点 ID
if [ -z "$NODE_ID" ]; then
    read -rp "请输入节点 ID (数字): " NODE_ID
fi

# 检查域名
if [ -z "$CERT_DOMAIN" ]; then
    read -rp "请输入节点解析域名 (例如 ula3.server1.men): " CERT_DOMAIN
fi

# 检查协议
if [ -z "$3" ]; then
    echo "----------------------------------------"
    echo "请选择节点传输协议："
    echo "  1. Shadowsocks    2. Vless       3. Vmess       4. Hysteria"
    echo "  5. Hysteria2      6. Trojan      7. Tuic        8. AnyTLS"
    read -rp "请输入选项编号 [常用: 5 / 7 / 8] (默认 8): " input_type
    RAW_TYPE="${input_type:-8}"
fi

# 协议映射转换
case "$RAW_TYPE" in
    1|shadowsocks|Shadowsocks|ss) NODE_TYPE="Shadowsocks" ;;
    2|vless|Vless|VLESS)         NODE_TYPE="Vless" ;;
    3|vmess|Vmess|VMess)         NODE_TYPE="Vmess" ;;
    4|hysteria|Hysteria|hy)       NODE_TYPE="Hysteria" ;;
    5|hysteria2|Hysteria2|hy2)    NODE_TYPE="Hysteria2" ;;
    6|trojan|Trojan)              NODE_TYPE="Trojan" ;;
    7|tuic|Tuic)                  NODE_TYPE="Tuic" ;;
    8|anytls|AnyTLS)              NODE_TYPE="anytls" ;;
    *)                            NODE_TYPE="$RAW_TYPE" ;;
esac

echo "=========================================="
echo "准备部署 V2bX："
echo "面板地址 : ${API_HOST}"
echo "节点 ID   : ${NODE_ID}"
echo "解析域名 : ${CERT_DOMAIN}"
echo "节点协议 : ${NODE_TYPE} (编号: ${RAW_TYPE})"
echo "核心类型 : sing (选项 2)"
echo "通信密钥 : ${API_KEY:0:2}******${API_KEY: -2} (已脱敏显示)"
echo "=========================================="

# ================= 2. 静默安装 V2bX =================
echo ">>> [1/3] 正在拉取官方安装包进行静默安装..."
printf "n\n" | bash <(curl -Ls https://raw.githubusercontent.com/wyx2685/V2bX-script/master/install.sh)

# ================= 3. 下发核心文件与配置 =================
echo ">>> [2/3] 写入 Sing-box 基础配置与主配置文件..."
mkdir -p /etc/V2bX

# 修复 sing_origin.json 缺失报错问题
cat <<'ORIGIN' > /etc/V2bX/sing_origin.json
{
  "log": {
    "disabled": false,
    "level": "warn",
    "timestamp": true
  },
  "dns": {},
  "inbounds": [],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ],
  "route": {
    "rules": []
  }
}
ORIGIN

# 写入主配置文件
cat <<CONFIG > /etc/V2bX/config.json
{
    "Log": {
        "Level": "error",
        "Output": ""
    },
    "Cores": [
    {
        "Type": "sing",
        "Log": {
            "Level": "error",
            "Timestamp": true
        },
        "NTP": {
            "Enable": false,
            "Server": "time.apple.com",
            "ServerPort": 0
        },
        "OriginalPath": "/etc/V2bX/sing_origin.json"
    }],
    "Nodes": [{
            "Core": "sing",
            "ApiHost": "${API_HOST}",
            "ApiKey": "${API_KEY}",
            "NodeID": ${NODE_ID},
            "NodeType": "${NODE_TYPE}",
            "Timeout": 30,
            "ListenIP": "::",
            "SendIP": "0.0.0.0",
            "DeviceOnlineMinTraffic": 200,
            "MinReportTraffic": 0,
            "TCPFastOpen": false,
            "SniffEnabled": true,
            "CertConfig": {
                "CertMode": "http",
                "RejectUnknownSni": false,
                "CertDomain": "${CERT_DOMAIN}",
                "CertFile": "/etc/V2bX/fullchain.cer",
                "KeyFile": "/etc/V2bX/cert.key",
                "Email": "v2bx@github.com",
                "Provider": "cloudflare",
                "DNSEnv": {
                    "EnvName": "env1"
                }
            }
        }]
}
CONFIG

# ================= 4. 重启与服务校验 =================
echo ">>> [3/3] 重载 systemd 并启动 V2bX 服务..."
systemctl daemon-reload
systemctl enable V2bX
systemctl restart V2bX

sleep 2
if systemctl is-active --quiet V2bX; then
    echo "=========================================="
    echo "  🎉 V2bX 节点 [${NODE_ID}] 部署成功并已正常运行！"
    echo "=========================================="
else
    echo "❌ V2bX 启动失败，最近 20 行运行日志如下："
    journalctl -u V2bX -n 20 --no-pager
    exit 1
fi
