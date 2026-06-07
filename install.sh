#!/usr/bin/env bash
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

[[ $EUID -ne 0 ]] && error "请以 root 身份运行"

ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64)  BIN_ARCH="x86_64" ;;
  aarch64|arm64) BIN_ARCH="arm64"  ;;
  *) error "不支持的架构: $ARCH" ;;
esac

command -v curl &>/dev/null || { command -v wget &>/dev/null || error "请安装 curl 或 wget"; }

INSTALL_DIR="/opt/lobster-panel"
mkdir -p "$INSTALL_DIR"

# 下载龙虾面板
info "下载龙虾面板 (nodepassdash) ${BIN_ARCH}..."
if command -v curl &>/dev/null; then
  curl -sL "https://github.com/lima-droid/NB-Panel/releases/latest/download/NB-Panel_Linux_${BIN_ARCH}.tar.gz" -o /tmp/nbpanel.tar.gz
else
  wget -q "https://github.com/lima-droid/NB-Panel/releases/latest/download/NB-Panel_Linux_${BIN_ARCH}.tar.gz" -O /tmp/nbpanel.tar.gz
fi

tar xzf /tmp/nbpanel.tar.gz -C "$INSTALL_DIR"
chmod +x "$INSTALL_DIR/nodepassdash"
rm -f /tmp/nbpanel.tar.gz

# 龙虾核心
info "下载龙虾核心 (np-master) ${BIN_ARCH}..."
if command -v curl &>/dev/null; then
  curl -sL "https://raw.githubusercontent.com/lima-droid/NB-Panel/main/releases/NP-linux-${BIN_ARCH}" -o /tmp/np-master
else
  wget -q "https://raw.githubusercontent.com/lima-droid/NB-Panel/main/releases/NP-linux-${BIN_ARCH}" -O /tmp/np-master
fi
chmod +x /tmp/np-master
mv /tmp/np-master "$INSTALL_DIR/np-master"

# systemd 服务
if command -v systemctl &>/dev/null; then
  cat > /etc/systemd/system/lobster-panel.service << 'SERVICE'
[Unit]
Description=Lobster Panel
After=network.target

[Service]
Type=simple
ExecStart=/opt/lobster-panel/nodepassdash
WorkingDirectory=/opt/lobster-panel
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
SERVICE
  systemctl daemon-reload
fi

echo ""
info "✅ 龙虾面板安装完成！"
info "   面板: $INSTALL_DIR/nodepassdash"
info "   核心: $INSTALL_DIR/np-master"
echo ""
info "🚀 启动面板: systemctl start lobster-panel"
info "🌐 访问面板: http://$(curl -s icanhazip.com):4000"
info "   默认账号: nbpanel / Np123456"
echo ""
info "📋 龙虾核心独立安装命令："
info "   bash <(wget -qO1 https://raw.githubusercontent.com/lima-droid/NP-Master/main/scripts/np.sh) -i"
