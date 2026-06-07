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

# Colors - 只使用简单颜色，不添加任何符号
ESC=$(printf '\033')
R="${ESC}[31m"
G="${ESC}[32m"
Y="${ESC}[33m"
C="${ESC}[36m"
B="${ESC}[1m"
N="${ESC}[0m"

# 纯文本消息函数 - 没有任何符号
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

download_binary() {
  local url="https://github.com/lima-droid/NB-Panel/releases/latest/download/NB-Panel_$(detect_arch).tar.gz"
  dest="/tmp/nbpanel.tar.gz"
  msg "下载 NB-Panel..."

  if command -v curl &>/dev/null; then
    curl -#L -o "$dest" "$url" || err "下载失败"
  else
    wget --show-progress -qO "$dest" "$url" || err "下载失败"
  fi
}

install_binary() {
  local dest_port ip_addr cert_path key_path tls_args
  dest="/tmp/nbpanel.tar.gz"

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
    tls_args=" --cert $cert_path --key $key_path"
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
    mkdir -p "$INSTALL_DIR/certs"
    cp "$cert_path" "$INSTALL_DIR/certs/server.crt"
    cp "$key_path" "$INSTALL_DIR/certs/server.key"
    chmod 600 "$INSTALL_DIR/certs/server.key"
    printf "CERT_PATH=%s/certs/server.crt\n" "$INSTALL_DIR" >> "$INSTALL_DIR/config.env"
    printf "KEY_PATH=%s/certs/server.key\n" "$INSTALL_DIR" >> "$INSTALL_DIR/config.env"
  fi

  chown -R nodepass:nodepass "$INSTALL_DIR/db" "$INSTALL_DIR/logs" "$INSTALL_DIR/certs" 2>/dev/null 

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
EOF

  systemctl daemon-reload
  systemctl enable --quiet $SERVICE_NAME
  systemctl start $SERVICE_NAME

  rm -rf /tmp/nbpanel_install /tmp/nbpanel.tar.gz

  local proto="http"
  [[ "$https" =~ ^[Yy]$ ]] && proto="https"

  echo
  sep
  echo -e " ${G}安装完成${N}"
  sep 
  echo -e "   账号:    nbpanel / Np123456"
  echo -e "   路径:    $INSTALL_DIR/bin/$BINARY_NAME"
  echo -e "   配置:    $INSTALL_DIR/config.env"
  echo -e "   URL:     ${C}${proto}://${ip_addr}:${dest_port}${N}"
  sep
  echo
}

# ---------- Docker Install ----------
install_docker() {
  command -v docker &>/dev/null || err "请先安装 Docker"

  local port_host data_dir ip_addr

  echo
  sep
  echo -e " ${B}Docker 安装${N}"
  sep

  readp "映射端口 [4000]: " port_host
  port_host="${port_host:-4000}"

  readp "数据目录 [$(pwd)/nbpanel-data]: " data_dir
  data_dir="${data_dir:-$(pwd)/nbpanel-data}"

  echo
  readp "确认安装? [Y/n]: " confirm
  [[ "$confirm" =~ ^[Nn]$ ]] && { echo; warn "安装已取消"; return; }

  ip_addr=$(curl -s --max-time 5 https://ipv4.ip.sb 2>/dev/null || hostname -I | awk '{print $1}')
  ip_addr="${ip_addr:-localhost}"

  docker inspect "$SERVICE_NAME" &>/dev/null && {
    msg "删除旧容器..."
    docker rm -f "$SERVICE_NAME" &>/dev/null
  }

  mkdir -p "$data_dir"/{logs,public,db}
  chmod 777 "$data_dir"/{logs,public,db}

  msg "拉取 Docker 镜像..."
  docker pull "$DOCKER_IMAGE"

  msg "启动容器..."
  docker run -d \
    --name "$SERVICE_NAME" \
    --restart=always \
    -p "${port_host}:4000" \
    -e PORT=4000 \
    -v "$data_dir/logs:/app/logs" \
    -v "$data_dir/db:/app/db" \
    -v "$data_dir/public:/app/public" \
    "$DOCKER_IMAGE" || err "容器启动失败"

  echo
  sep
  echo -e " ${G}安装完成${N}"
  sep
  echo -e "   账号:    nbpanel / Np123456"
  echo -e "   数据:    ${data_dir}"
  echo -e "   URL:     ${C}http://${ip_addr}:${port_host}${N}"
  sep
  echo
}

# ---------- Uninstall ----------
uninstall_binary() {
  [[ -f "$INSTALL_DIR/bin/$BINARY_NAME" ]] || { warn "二进制版未安装"; return; }
  readp "确认卸载? [y/N]: " ok
  [[ "$ok" =~ ^[Yy]$ ]] || return
  systemctl stop $SERVICE_NAME 2>/dev/null
  systemctl disable $SERVICE_NAME 2>/dev/null
  rm -f /etc/systemd/system/$SERVICE_NAME.service
  systemctl daemon-reload
  rm -rf "$INSTALL_DIR"
  rm -f /usr/local/bin/$BINARY_NAME
  ok "二进制版已卸载"
}

uninstall_docker() {
  docker ps -a --format '{{.Names}}' | grep -q "^${SERVICE_NAME}$" || { warn "Docker 版未安装"; return; }
  readp "确认卸载? [y/N]: " ok
  [[ "$ok" =~ ^[Yy]$ ]] || return
  docker stop "$SERVICE_NAME" 2>/dev/null || true
  docker rm "$SERVICE_NAME" 2>/dev/null || true
  docker rmi "$DOCKER_IMAGE" 2>/dev/null || true
  readp "删除数据目录? [y/N]: " del
  if [[ "$del" =~ ^[Yy]$ ]]; then
    local data_dir="${DATA_DIR:-$(pwd)/nbpanel-data}"
    rm -rf "$data_dir"
  fi
  ok "Docker 版已卸载"
}


# ---------- Install Menu ----------
install_menu() {
  echo
  sep
  echo -e " ${B}选择安装方式${N}"
  sep
  echo -e "   1. 二进制"
  echo -e "   2. Docker"
  sep
  readp "请选择 [1/2]: " method
  echo

  case "$method" in
    2) install_docker ;;
    *) install_binary ;;
  esac
}

# ---------- Status ----------
show_status() {
  echo
  echo "  二进制:"
  if [[ -f "$INSTALL_DIR/bin/$BINARY_NAME" ]]; then
    if systemctl is-active --quiet $SERVICE_NAME 2>/dev/null; then
      echo "    状态: 运行中"
      local port=$(grep ^PORT= "$INSTALL_DIR/config.env" 2>/dev/null | cut -d= -f2)
      echo "    端口: ${port:-4000}"
    else
      echo "    状态: 已停止"
    fi
  else
    echo "    未安装"
  fi

  echo
  echo "  Docker:"
  if docker ps -a --format '{{.Names}}' | grep -q "^${SERVICE_NAME}$" 2>/dev/null; then
    if docker ps --format '{{.Names}}' | grep -q "^${SERVICE_NAME}$" 2>/dev/null; then
      echo "    状态: 运行中"
      local port=$(docker port "$SERVICE_NAME" 2>/dev/null | head -1 | sed 's/.*://')
      echo "    端口: ${port:-4000}"
    else
      echo "    状态: 已停止"
    fi
  else
    echo "    未安装"
  fi
  echo
}

# ---------- Main Menu ----------
main_menu() {
  echo
  echo -e " ${B}${C}----------------------------------------${N}"
  echo -e " ${B}${C}     NB-Panel 管理脚本 v${VERSION}${N}"
  echo -e " ${B}${C}  github.com/lima-droid/NB-Panel${N}"
  echo -e " ${B}${C}----------------------------------------${N}"
  echo
  echo "    1. 安装"
  echo "    2. 卸载"
  echo "    3. 升级"
  echo "    4. 状态"
  echo "    5. 日志"
  echo "    0. 退出"
  echo
  readp "请选择 [0-5]: " choice

  case "$choice" in
    1) install_menu ;;
    2)
      echo
      local has_bin=0 has_dkr=0
      [[ -f "$INSTALL_DIR/bin/$BINARY_NAME" ]] && has_bin=1
      docker ps -a --format '{{.Names}}' | grep -q "^${SERVICE_NAME}$" 2>/dev/null && has_dkr=1
      if [[ $has_bin -eq 1 && $has_dkr -eq 1 ]]; then
        echo "  检测到两种安装方式:"
        echo "    1) 二进制"
        echo "    2) Docker"
        echo "    3) 全部"
        readp "请选择 [1/2/3]: " u
        case "$u" in
          2) uninstall_docker ;;
          3) uninstall_binary; uninstall_docker ;;
          *) uninstall_binary ;;
        esac
      elif [[ $has_dkr -eq 1 ]]; then
        uninstall_docker
      elif [[ $has_bin -eq 1 ]]; then
        uninstall_binary
      else
        warn "未检测到已安装的 NB-Panel"
      fi
      ;;
    3)
      echo
      if docker ps -a --format '{{.Names}}' | grep -q "^${SERVICE_NAME}$" 2>/dev/null; then
        msg "Docker 升级中..."
        local pd dd
        pd=$(docker port "$SERVICE_NAME" 2>/dev/null | head -1 | sed 's/.*://')
        dd=$(docker inspect "$SERVICE_NAME" 2>/dev/null | grep '"Source"' | sed 's/.*"Source": "//;s/".*//' | grep nbpanel-data | head -1)
        pd="${pd:-4000}"; dd="${dd:-$(pwd)/nbpanel-data}"
        docker stop "$SERVICE_NAME" 2>/dev/null; docker rm "$SERVICE_NAME" 2>/dev/null
        docker pull "$DOCKER_IMAGE"
        mkdir -p "$dd"/{logs,public,db} && chmod 777 "$dd"/{logs,public,db}
        docker run -d --name "$SERVICE_NAME" --restart=always -p "${pd}:4000" -e PORT=4000 -v "$dd/logs:/app/logs" -v "$dd/db:/app/db" -v "$dd/public:/app/public" "$DOCKER_IMAGE" && ok "Docker 升级完成"
      elif [[ -f "$INSTALL_DIR/bin/$BINARY_NAME" ]]; then
        msg "二进制升级中..."
        systemctl stop $SERVICE_NAME 2>/dev/null
        download_binary
        rm -rf /tmp/nbpanel_install && mkdir /tmp/nbpanel_install
        tar -xzf "$dest" -C /tmp/nbpanel_install || err "解压失败"
        local binary=$(find /tmp/nbpanel_install -name "$BINARY_NAME" -type f | head -1)
        cp "$binary" "$INSTALL_DIR/bin/$BINARY_NAME" && chmod 755 "$INSTALL_DIR/bin/$BINARY_NAME"
        systemctl start $SERVICE_NAME && ok "二进制升级完成"
        rm -rf /tmp/nbpanel_install
      else
        warn "未检测到已安装的 NB-Panel"
      fi
      ;;
    4) show_status ;;
    5)
      if docker ps --format '{{.Names}}' | grep -q "^${SERVICE_NAME}$" 2>/dev/null; then
        docker logs --tail 50 "$SERVICE_NAME"
      elif systemctl is-active --quiet $SERVICE_NAME 2>/dev/null; then
        journalctl -u $SERVICE_NAME -n 50 --no-pager
      else
        echo "无运行实例"
      fi
      ;;
    0) exit 0 ;;
    *) main_menu ;;
  esac

  echo
  readp "按回车键返回... " dummy
  main_menu
}

# ---------- Main Entry ----------
main() {
  check_root

  case "${1:-}" in
    -b|--binary) install_binary ;;
    -d|--docker) install_docker ;;
    -r|--remove) uninstall_binary ;;
    -R|--remove-docker) uninstall_docker ;;
    -s|--status) show_status ;;
    -h|--help)
      echo "用法: bash install.sh [选项]"
      echo "  -b, --binary          二进制安装"
      echo "  -d, --docker          Docker 安装"
      echo "  -r, --remove          卸载二进制"
      echo "  -R, --remove-docker   卸载 Docker"
      echo "  -s, --status          查看状态"
      echo "  (无参数)              交互菜单"
      exit 0
      ;;
    *) main_menu ;;
  esac
}

main "$@"

