#!/usr/bin/env bash

SCRIPT_VERSION='2.4.0'
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# NB面板 配置
GITHUB_REPO="lima-droid/NB-Panel"
NPD_DOWNLOAD_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main/releases/NB-Panel_Linux_x86_64.tar.gz"
NPD_LOCAL_DIR="/root/npmb"
NPD_LOCAL_TARGZ="${NPD_LOCAL_DIR}/NB-Panel_Linux_x86_64.tar.gz"
NPD_BINARY_NAME="nodepassdash"
NPD_INSTALL_DIR="/opt/nodepassdash"
NPD_USER_NAME="nodepass"
NPD_SERVICE_NAME="nodepassdash"
NPD_DEFAULT_PORT="4000"

# 通用函数
info() { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*" && exit 1; }
hint() { echo -e "${CYAN} →${NC} $*"; }
title() { echo -e "\n${BOLD}${BLUE}━ $* ━${NC}\n"; }
step() { echo -e "${CYAN} ▸${NC} $*"; }
reading() { echo -n "$(echo -e "${GREEN} ▸${NC} $1")"; read "$2"; }

check_root() { [[ $(id -u) -ne 0 ]] && error "必须以 root 运行"; }

# ========== 下载 ==========
download_nodepassdash() {
  mkdir -p "$NPD_LOCAL_DIR"

  if [[ -f "$NPD_LOCAL_TARGZ" ]]; then
    warn "本地已存在: $NPD_LOCAL_TARGZ"
    read -p " 重新下载？[y/N]: " redownload
    [[ ! "$redownload" =~ ^[Yy]$ ]] && { info "使用本地文件"; return 0; }
  fi

  step "下载 NB面板..."
  echo " ${CYAN}${NPD_DOWNLOAD_URL}${NC}"

  if command -v curl &>/dev/null; then
    curl -#L -o "$NPD_LOCAL_TARGZ" "$NPD_DOWNLOAD_URL"
  elif command -v wget &>/dev/null; then
    wget --show-progress -qO "$NPD_LOCAL_TARGZ" "$NPD_DOWNLOAD_URL"
  else
    error "未找到 curl 或 wget"
  fi

  if [[ -f "$NPD_LOCAL_TARGZ" ]]; then
    local size=$(stat -c%s "$NPD_LOCAL_TARGZ" 2>/dev/null || echo 0)
    [[ "$size" -gt 0 ]] && { info "下载完成 ($(numfmt --to=iec $size 2>/dev/null || echo "${size}B"))"; } || error "文件为空"
  else
    error "下载失败，请检查网络"
  fi
}

# ========== 安装 ==========
check_npd_install() {
  systemctl is-active --quiet $NPD_SERVICE_NAME 2>/dev/null && return 0
  [[ -f "$NPD_INSTALL_DIR/bin/$NPD_BINARY_NAME" ]] && return 1
  return 2
}

install_nodepassdash() {
  check_npd_install
  [[ $? -ne 2 ]] && { warn "NB面板 已安装，请先卸载"; return; }

  download_nodepassdash
  [[ ! -f "$NPD_LOCAL_TARGZ" ]] && error "未找到安装包"

  echo
  title "NB面板 安装配置"

  read -p " 监听端口 (默认 $NPD_DEFAULT_PORT): " USER_PORT
  USER_PORT="${USER_PORT:-$NPD_DEFAULT_PORT}"
  [[ ! "$USER_PORT" =~ ^[0-9]+$ || "$USER_PORT" -lt 1 || "$USER_PORT" -gt 65535 ]] && error "端口无效"

  read -p " 域名或 IP (回车自动检测): " DASH_IP
  [[ -z "$DASH_IP" ]] && DASH_IP=$(curl -s --max-time 5 ipv4.ip.sb 2>/dev/null || echo "localhost")

  read -p " 启用 HTTPS? [y/N]: " https
  if [[ "$https" =~ ^[Yy]$ ]]; then
    ENABLE_HTTPS="true"
    read -p " TLS 证书路径 (.crt/.pem): " CERT_PATH
    read -p " TLS 私钥路径 (.key): " KEY_PATH
    [[ ! -f "$CERT_PATH" ]] && error "证书不存在: $CERT_PATH"
    [[ ! -f "$KEY_PATH" ]] && error "私钥不存在: $KEY_PATH"
  else
    ENABLE_HTTPS="false"
    CERT_PATH=""
    KEY_PATH=""
  fi

  echo
  read -p " 确认安装？[Y/n]: " ok
  [[ "$ok" =~ ^[Nn]$ ]] && { echo "已取消"; return; }

  echo
  title "正在安装"

  # 解压
  local tmp="/tmp/npdash_tmp"
  rm -rf "$tmp" && mkdir "$tmp"
  step "解压安装包..."
  tar -xzf "$NPD_LOCAL_TARGZ" -C "$tmp" >/dev/null 2>&1 || error "解压失败"

  local binary=$(find "$tmp" -name "$NPD_BINARY_NAME" -type f | head -1)
  [[ -z "$binary" ]] && error "未找到二进制文件"

  # 目录和用户
  step "创建安装目录..."
  mkdir -p "$NPD_INSTALL_DIR"/{bin,db,logs,certs}
  id "$NPD_USER_NAME" &>/dev/null || useradd --system --home "$NPD_INSTALL_DIR" --shell /bin/false "$NPD_USER_NAME" >/dev/null 2>&1

  # 复制二进制
  step "安装二进制文件..."
  cp "$binary" "$NPD_INSTALL_DIR/bin/$NPD_BINARY_NAME"
  chmod 755 "$NPD_INSTALL_DIR/bin/$NPD_BINARY_NAME"
  chown root:root "$NPD_INSTALL_DIR/bin/$NPD_BINARY_NAME"
  ln -sf "$NPD_INSTALL_DIR/bin/$NPD_BINARY_NAME" /usr/local/bin/$NPD_BINARY_NAME

  # 权限
  chown -R "$NPD_USER_NAME:$NPD_USER_NAME" "$NPD_INSTALL_DIR"/{db,logs,certs} 2>/dev/null
  chown "$NPD_USER_NAME:$NPD_USER_NAME" "$NPD_INSTALL_DIR" 2>/dev/null

  # 配置文件
  step "写入配置..."
  cat > "$NPD_INSTALL_DIR/config.env" << EOF
PORT=$USER_PORT
ENABLE_HTTPS=$ENABLE_HTTPS
DB_PATH=$NPD_INSTALL_DIR/db/database.db
EOF

  # TLS 证书
  local tls_args=""
  if [[ "$ENABLE_HTTPS" == "true" ]]; then
    cp "$CERT_PATH" "$NPD_INSTALL_DIR/certs/server.crt"
    cp "$KEY_PATH" "$NPD_INSTALL_DIR/certs/server.key"
    chown "$NPD_USER_NAME:$NPD_USER_NAME" "$NPD_INSTALL_DIR/certs/"*
    chmod 600 "$NPD_INSTALL_DIR/certs/server.key"
    chmod 644 "$NPD_INSTALL_DIR/certs/server.crt"
    cat >> "$NPD_INSTALL_DIR/config.env" << EOF
CERT_PATH=$NPD_INSTALL_DIR/certs/server.crt
KEY_PATH=$NPD_INSTALL_DIR/certs/server.key
EOF
    tls_args=" --cert $NPD_INSTALL_DIR/certs/server.crt --key $NPD_INSTALL_DIR/certs/server.key"
  fi

  # systemd 服务
  step "注册 systemd 服务..."
  cat > /etc/systemd/system/$NPD_SERVICE_NAME.service << EOF
[Unit]
Description=NB面板 - NodePass 隧道管理面板
After=network.target

[Service]
User=$NPD_USER_NAME
Group=$NPD_USER_NAME
WorkingDirectory=$NPD_INSTALL_DIR
ExecStart=$NPD_INSTALL_DIR/bin/$NPD_BINARY_NAME --port $USER_PORT$tls_args
Restart=always
RestartSec=5
EnvironmentFile=-$NPD_INSTALL_DIR/config.env

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable $NPD_SERVICE_NAME >/dev/null 2>&1
  systemctl start $NPD_SERVICE_NAME

  # 清理
  rm -rf "$tmp" "$NPD_LOCAL_DIR"

  # 结果
  sleep 2
  local proto="http"
  [[ "$ENABLE_HTTPS" == "true" ]] && proto="https"

  echo
  echo -e "${BOLD}${GREEN}+────────────────────────────+${NC}"
  echo -e "${BOLD}${GREEN}| NB面板 安装完成！         |${NC}"
  echo -e "${BOLD}${GREEN}+────────────────────────────+${NC}"
  echo
  echo -e " 访问地址: ${CYAN}${proto}://${DASH_IP}:${USER_PORT}${NC}"
  echo -e " 本地访问: ${CYAN}${proto}://localhost:${USER_PORT}${NC}"
  echo
  echo -e " ${YELLOW}默认账号: nbpanel / Np123456${NC}"
  echo -e " ${YELLOW}首次登录后请立即修改密码${NC}"
  echo -e " ${CYAN}项目仓库: https://github.com/${GITHUB_REPO}${NC}"
  echo

  if systemctl is-active --quiet $NPD_SERVICE_NAME; then
    info "服务已启动"
  else
    warn "服务可能未启动: journalctl -u $NPD_SERVICE_NAME -n 20"
  fi
}

# ========== 查看 ==========
show_npd_info() {
  check_npd_install
  local status
  case $? in
    0) status="${GREEN}● 运行中${NC}" ;;
    1) status="${YELLOW}○ 已安装 (未运行)${NC}" ;;
    2) warn "NB面板 未安装"; return ;;
  esac

  local port="$NPD_DEFAULT_PORT"
  [[ -f "$NPD_INSTALL_DIR/config.env" ]] && source "$NPD_INSTALL_DIR/config.env" 2>/dev/null

  echo
  echo -e " ${CYAN}NB面板${NC} $status"
  echo -e " 安装目录 : ${NPD_INSTALL_DIR}"
  echo -e " 监听端口 : ${PORT:-$port}"
  echo -e " 项目仓库 : https://github.com/${GITHUB_REPO}"
  echo
}

# ========== 卸载 ==========
uninstall_nodepassdash() {
  check_npd_install
  [[ $? -eq 2 ]] && { warn "未检测到安装"; return; }

  read -p " 确认卸载 NB面板？[y/N]: " ok
  [[ ! "$ok" =~ ^[Yy]$ ]] && return

  step "停止服务..."
  systemctl stop $NPD_SERVICE_NAME 2>/dev/null
  systemctl disable $NPD_SERVICE_NAME 2>/dev/null
  rm -f /etc/systemd/system/$NPD_SERVICE_NAME.service
  systemctl daemon-reload 2>/dev/null

  step "删除文件..."
  rm -rf "$NPD_INSTALL_DIR"
  rm -f /usr/local/bin/$NPD_BINARY_NAME

  [[ -d "$NPD_LOCAL_DIR" ]] && rm -rf "$NPD_LOCAL_DIR"

  echo
  info "NB面板 已卸载"
}

# ========== 主菜单 ==========
show_header() {
  clear
  echo
  echo -e " ${BOLD}${BLUE}+──────────────────────────────+${NC}"
  echo -e " ${BOLD}${BLUE}|${NC} NB面板 安装管理器 ${BOLD}${BLUE}         |${NC}"
  echo -e " ${BOLD}${BLUE}|${NC} v${SCRIPT_VERSION} · ${CYAN}github.com/lima-droid/NB-Panel${NC} ${BOLD}${BLUE}|${NC}"
  echo -e " ${BOLD}${BLUE}+──────────────────────────────+${NC}"
  echo
}

main_menu() {
  show_header

  check_npd_install; local s=$?
  [[ $s -ne 2 ]] && show_npd_info

  echo -e " ${BOLD}操作菜单${NC}"
  echo -e " ${BLUE}──────────${NC}"
  if [[ $s -eq 2 ]]; then
    echo -e " ${GREEN}1${NC}. 安装 "
  else
    echo -e " ${GREEN}1${NC}. 查看状态"
    echo -e " ${GREEN}2${NC}. 重启服务"
    echo -e " ${GREEN}3${NC}. 停止服务"
    echo -e " ${RED}4${NC}. 卸载"
  fi
  echo -e " ${CYAN}0${NC}. 退出"
  echo

  reading "请选择: " ch
  case "$ch" in
    1) [[ $s -eq 2 ]] && install_nodepassdash || show_npd_info ;;
    2) [[ $s -ne 2 ]] && { systemctl restart $NPD_SERVICE_NAME && info "已重启"; } ;;
    3) [[ $s -ne 2 ]] && { systemctl stop $NPD_SERVICE_NAME && info "已停止"; } ;;
    4) [[ $s -ne 2 ]] && uninstall_nodepassdash ;;
    0) echo; exit 0 ;;
    *) main_menu ;;
  esac

  echo
  read -p " 按回车键继续..."
  main_menu
}

# ========== 入口 ==========
main() {
  check_root

  case "$1" in
    -i|--install) install_nodepassdash ;;
    -u|--uninstall) uninstall_nodepassdash ;;
    -s|--status) show_npd_info ;;
    -d|--download) download_nodepassdash ;;
    -h|--help)
      echo
      echo -e "${BOLD}NB面板 安装管理器 v${SCRIPT_VERSION}${NC}"
      echo -e " ${CYAN}https://github.com/lima-droid/NB-Panel${NC}"
      echo
      echo " bash $0       交互式菜单"
      echo " bash $0 -i    直接安装"
      echo " bash $0 -u    卸载"
      echo " bash $0 -s    查看状态"
      echo " bash $0 -d    仅下载安装包"
      echo
      ;;
    *) main_menu ;;
  esac
}

main "$@"
