#!/usr/bin/env bash
#
# NB-Panel Installer
# https://github.com/lima-droid/NB-Panel
#
set -eE
trap 'echo "安装中断，行号: $LINENO"; exit 1' ERR

VERSION="3.4.4"
INSTALL_DIR="/opt/nodepassdash"
BINARY_NAME="nodepassdash"
SERVICE_NAME="nodepassdash"
DOCKER_IMAGE="ghcr.io/lima-droid/nb-panel:latest"

# Colors
ESC=$(printf '\033')
R="${ESC}[31m"
G="${ESC}[32m"
Y="${ESC}[33m"
C="${ESC}[36m"
B="${ESC}[1m"
N="${ESC}[0m"

msg()   { echo -e " ${B}${C}>>${N}${B} $*${N}"; }
ok()    { echo -e " ${G}OK${N} $*"; }
warn()  { echo -e " ${Y}!!${N} $*"; }
err()   { echo -e " ${R}XX${N} $*" >&2; exit 1; }
sep()   { echo -e " ${C}------------------------------------------------${N}"; }
readp() { read -p "$(echo -e " $1")" "$2"; }

check_root() {
  [[ $EUID -eq 0 ]] || err "请使用 root 账户运行"
}

# ---------- Binary Install ----------
detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "Linux_x86_64" ;;
    aarch64|arm64) echo "Linux_arm64" ;;
    armv7l) echo "Linux_armv7" ;;
    *) err "不支持的架构: $(uname -m)" ;;
  esac
}

get_latest_version() {
  local api_url="https://api.github.com/repos/NodePassProject/NodePassDash/releases/latest"
  VERSION=$(curl -sL "$api_url" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
  if [[ -z "$VERSION" ]]; then
    err "获取最新版本失败，请检查网络或 GitHub API 限制"
  fi
  msg "获取到最新版本: ${VERSION}"
}

download_binary() {
  local arch
  arch="$(detect_arch)"
  dest="/tmp/nbpanel.tar.gz"
  msg "下载 NB-Panel (${arch})..."

  local url="https://github.com/NodePassProject/NodePassDash/releases/download/${VERSION}/NodePassDash_${arch}.tar.gz"
  if command -v curl &>/dev/null; then
    curl -#L -o "$dest" "$url" || err "下载失败"
  else
    wget --show-progress -qO "$dest" "$url" || err "下载失败"
  fi
  if file "$dest" | grep -q "HTML"; then
    err "下载返回 HTML，请检查版本: ${VERSION}, 架构: ${arch}"
  fi
}

install_binary() {
  local dest_port ip_addr cert_path key_path tls_args
  dest="/tmp/nbpanel.tar.gz"

  get_latest_version
  download_binary

  msg "解压安装包..."
  rm -rf /tmp/nbpanel_install && mkdir /tmp/nbpanel_install
  tar -xzf "$dest" -C /tmp/nbpanel_install || err "解压失败"

  local binary
  binary=$(find /tmp/nbpanel_install -name "$BINARY_NAME" -type f | head -1)
  [[ -n "$binary" ]] || err "未找到二进制文件"

  echo
  sep
  echo -e " ${B}二进制安装${N}"
  sep

  readp "监听端口 [4000]: " dest_port
  dest_port="${dest_port:-4000}"

  readp "启用 HTTPS? [y/N]: " https
  if [[ "$https" =~ ^[Yy]$ ]]; then
    readp "TLS 证书路径: " cert_path
    readp "TLS 私钥路径: " key_path
    [[ -f "$cert_path" ]] || err "证书文件不存在: $cert_path"
    [[ -f "$key_path" ]] || err "私钥文件不存在: $key_path"
    tls_args=" --cert $INSTALL_DIR/certs/server.crt --key $INSTALL_DIR/certs/server.key"
  fi

  echo
  readp "确认安装? [Y/n]: " confirm
  [[ "$confirm" =~ ^[Nn]$ ]] && { echo; warn "安装已取消"; return; }

  ip_addr=$(curl -s --max-time 5 https://ipv4.ip.sb 2>/dev/null || echo "localhost")

  msg "创建系统用户..."
  id nodepass &>/dev/null || useradd --system --home "$INSTALL_DIR" --shell /bin/false nodepass

  msg "创建目录..."
  mkdir -p "$INSTALL_DIR"/{bin,db,logs,certs}

  msg "安装二进制文件..."
  cp "$binary" "$INSTALL_DIR/bin/$BINARY_NAME"
  chmod 755 "$INSTALL_DIR/bin/$BINARY_NAME"
  chown root:root "$INSTALL_DIR/bin/$BINARY_NAME"
  ln -sf "$INSTALL_DIR/bin/$BINARY_NAME" /usr/local/bin/$BINARY_NAME

  printf "PORT=%s\n" "$dest_port" > "$INSTALL_DIR/config.env"
  printf "DB_PATH=%s/db/database.db\n" "$INSTALL_DIR" >> "$INSTALL_DIR/config.env"

  if [[ "$https" =~ ^[Yy]$ ]]; then
    msg "安装证书..."
    cp "$cert_path" "$INSTALL_DIR/certs/server.crt"
    cp "$key_path" "$INSTALL_DIR/certs/server.key"
    chmod 600 "$INSTALL_DIR/certs/server.key"
    chmod 644 "$INSTALL_DIR/certs/server.crt"
    chown nodepass:nodepass "$INSTALL_DIR/certs/server.crt" "$INSTALL_DIR/certs/server.key"
    printf "CERT_PATH=%s/certs/server.crt\n" "$INSTALL_DIR" >> "$INSTALL_DIR/config.env"
    printf "KEY_PATH=%s/certs/server.key\n" "$INSTALL_DIR" >> "$INSTALL_DIR/config.env"
  fi

  chown -R nodepass:nodepass "$INSTALL_DIR/db" "$INSTALL_DIR/logs" "$INSTALL_DIR/certs" 2>/dev/null
  chown nodepass:nodepass "$INSTALL_DIR" "$INSTALL_DIR/config.env" 2>/dev/null

  msg "注册 systemd 服务..."
  cat > /etc/systemd/system/$SERVICE_NAME.service <<EOF
[Unit]
Description=NB-Panel
After=network.target

[Service]
User=nodepass
Group=nodepass
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/bin/$BINARY_NAME --port $dest_port$tls_args
Restart=always
RestartSec=5
EnvironmentFile=-$INSTALL_DIR/config.env

[Install]
WantedBy=multi-user.target
