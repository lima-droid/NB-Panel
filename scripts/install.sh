#!/usr/bin/env bash
#
# NB-Panel Installer
# https://github.com/lima-droid/NB-Panel
#
set -Eeuo pipefail
umask 022

# 二进制安装跟随上游 NodePassDash 官方发布
REPO="NodePassProject/NodePassDash"
ASSET_PREFIX="NodePassDash"
# 运行时从 GitHub 获取最新版本，不在脚本中写死
VERSION=""

INSTALL_DIR="/opt/nodepassdash"
BINARY_NAME="nodepassdash"
SERVICE_NAME="nodepassdash"
DOCKER_IMAGE="ghcr.io/lima-droid/nb-panel:latest"
CONTAINER_NAME="nbpanel"
# 兼容旧版本安装脚本创建的容器名
LEGACY_CONTAINER_NAME="nodepassdash"
CONTAINER=""
DEFAULT_PORT=4000
DEFAULT_DATA_DIR="/opt/nbpanel-data"

# 临时目录，退出时清理
WORKDIR=""
cleanup() {
  if [[ -n "$WORKDIR" && -d "$WORKDIR" ]]; then
    rm -rf "$WORKDIR"
  fi
  return 0
}
trap cleanup EXIT

# ---------- Colors ----------
ESC=$(printf '\033')
R="${ESC}[31m"
G="${ESC}[32m"
Y="${ESC}[33m"
C="${ESC}[36m"
B="${ESC}[1m"
N="${ESC}[0m"

trap 'echo -e " ${R}XX${N} 安装中断 (第 $LINENO 行)" >&2' ERR

msg()   { echo -e " ${B}${C}>>${N}${B} $*${N}"; }
ok()    { echo -e " ${G}OK${N} $*"; }
warn()  { echo -e " ${Y}!!${N} $*"; }
err()   { echo -e " ${R}XX${N} $*" >&2; exit 1; }
sep()   { echo -e " ${C}------------------------------------------------${N}"; }
readp() {
  local prompt="$1" var="$2"
  read -rp "$(echo -e " ${prompt}")" "$var" || { echo; exit 1; }
}

have() { command -v "$1" >/dev/null 2>&1; }

check_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || err "请使用 root 账户运行"
}

# ---------- 通用工具 ----------
download_file() {
  local url="$1" out="$2"
  if have curl; then
    curl -fL --retry 3 --connect-timeout 15 --max-time 300 -o "$out" "$url"
  elif have wget; then
    wget -q --tries=3 --timeout=30 -O "$out" "$url"
  else
    err "缺少下载工具，请先安装 curl 或 wget"
  fi
}

get_ip() {
  local ip=""
  if have curl; then
    ip=$(curl -fsS --max-time 5 https://ipv4.ip.sb 2>/dev/null || true)
    if [[ -z "$ip" ]]; then
      ip=$(curl -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)
    fi
  elif have wget; then
    ip=$(wget -qO- --timeout=5 https://ipv4.ip.sb 2>/dev/null || true)
    if [[ -z "$ip" ]]; then
      ip=$(wget -qO- --timeout=5 https://api.ipify.org 2>/dev/null || true)
    fi
  fi
  printf '%s' "${ip:-localhost}"
}

validate_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 ))
}

# 防止误填系统目录导致 mkdir/rm -rf 破坏系统
is_safe_data_dir() {
  local d="$1"
  [[ -n "$d" && "$d" == /* && "$d" != "/" ]] || return 1
  case "$d" in
    /bin|/boot|/dev|/etc|/home|/lib|/lib64|/opt|/proc|/root|/run|/sbin|/srv|/sys|/tmp|/usr|/usr/local|/usr/bin|/usr/share|/var|/var/lib|/var/www)
      return 1
      ;;
  esac
  return 0
}

prompt_port() {
  local p
  while true; do
    readp "监听端口 [${DEFAULT_PORT}]: " p
    p=${p:-$DEFAULT_PORT}
    if validate_port "$p"; then
      SELECTED_PORT="$p"
      return 0
    fi
    warn "端口必须是 1-65535 之间的数字"
  done
}

# ---------- 版本与下载 ----------
detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64)   echo "Linux_x86_64" ;;
    aarch64|arm64)  echo "Linux_arm64" ;;
    armv7l)         echo "Linux_armv7hf" ;;
    armv6l)         echo "Linux_armv6hf" ;;
    *) err "不支持的架构: $(uname -m)" ;;
  esac
}

get_latest_version() {
  local tag=""
  if have curl; then
    tag=$(curl -fsSL --max-time 15 -H 'User-Agent: NB-Panel-Installer' \
      "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null \
      | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1) || true
  elif have wget; then
    tag=$(wget -qO- --timeout=15 --header='User-Agent: NB-Panel-Installer' \
      "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null \
      | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1) || true
  fi

  # API 受限时，退回到 releases/latest 的跳转地址
  if [[ -z "$tag" ]] && have curl; then
    tag=$(curl -fsSL -o /dev/null -w '%{url_effective}' \
      "https://github.com/${REPO}/releases/latest" 2>/dev/null | sed 's#.*/tag/##') || true
  fi

  if [[ -n "$tag" ]]; then
    VERSION="$tag"
    [[ "$VERSION" == v* ]] || VERSION="v${VERSION}"
    msg "目标版本: ${VERSION}"
  else
    VERSION=""
    warn "无法获取上游版本号，将直接从 releases/latest 下载最新版"
  fi
}

verify_sha256() {
  local archive="$1" name="$2"
  local sums="$WORKDIR/checksums.txt"

  if ! have sha256sum; then
    warn "未找到 sha256sum，跳过校验"
    return 0
  fi

  local expected actual
  expected=$(awk -v n="$name" '$2 == n { print $1; exit }' "$sums")
  if [[ -z "$expected" ]]; then
    warn "校验文件中没有 ${name}，跳过校验"
    return 0
  fi

  actual=$(sha256sum "$archive" | awk '{print $1}')
  [[ "$actual" == "$expected" ]] || err "SHA256 校验失败: ${name}"
  ok "SHA256 校验通过"
}

download_binary() {
  local asset_arch base asset sums_name release_path
  asset_arch=$(detect_arch)
  [[ -n "$WORKDIR" ]] || WORKDIR=$(mktemp -d)

  if [[ -n "$VERSION" ]]; then
    release_path="releases/download/${VERSION}"
  else
    # 拿不到版本号时使用 latest/download 别名，始终下载上游最新版
    release_path="releases/latest/download"
  fi
  base="https://github.com/${REPO}/${release_path}"
  asset="${ASSET_PREFIX}_${asset_arch}.tar.gz"
  ARCHIVE="$WORKDIR/nbpanel.tar.gz"

  msg "下载 NodePassDash ${VERSION:-latest} (${asset_arch})..."
  download_file "${base}/${asset}" "$ARCHIVE" || err "下载失败: ${base}/${asset}"
  [[ -s "$ARCHIVE" ]] || err "下载文件为空"

  if [[ -n "$VERSION" ]]; then
    sums_name="${ASSET_PREFIX}_${VERSION#v}_checksums.txt"
    if download_file "${base}/${sums_name}" "$WORKDIR/checksums.txt" 2>/dev/null; then
      verify_sha256 "$ARCHIVE" "$asset"
    else
      warn "未获取到校验文件，跳过 SHA256 校验"
    fi
  else
    warn "未获取到版本号，跳过 SHA256 校验"
  fi

  tar -tzf "$ARCHIVE" >/dev/null 2>&1 || err "安装包损坏或格式不正确"

  EXTRACT_DIR="$WORKDIR/extract"
  rm -rf "$EXTRACT_DIR"
  mkdir -p "$EXTRACT_DIR"
  tar -xzf "$ARCHIVE" -C "$EXTRACT_DIR" || err "解压失败"
  msg "解压完成"
}

extract_binary() {
  local binary
  binary=$(find "$EXTRACT_DIR" -type f -name "$BINARY_NAME" -print -quit)
  [[ -n "$binary" ]] || err "安装包中未找到 ${BINARY_NAME}"

  local rc=0
  "$binary" --version >/dev/null 2>&1 || rc=$?
  if [[ "$rc" -eq 126 || "$rc" -eq 127 ]]; then
    err "二进制无法在当前系统运行（架构不匹配或文件损坏）"
  fi

  printf '%s' "$binary"
}

# ---------- 状态判断 ----------
binary_installed() { [[ -f "${INSTALL_DIR}/bin/${BINARY_NAME}" ]]; }
docker_available() { have docker && docker info >/dev/null 2>&1; }
container_exists() {
  local name
  for name in "$CONTAINER_NAME" "$LEGACY_CONTAINER_NAME"; do
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$name"; then
      CONTAINER="$name"
      return 0
    fi
  done
  return 1
}
container_data_dir() {
  local db_dir
  db_dir=$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/app/db"}}{{.Source}}{{end}}{{end}}' \
    "$CONTAINER" 2>/dev/null || true)
  # 数据目录布局为 <data_dir>/db，取上一级作为数据根目录
  [[ -n "$db_dir" ]] && dirname "$db_dir"
  return 0
}
container_port() {
  docker port "$CONTAINER" 4000/tcp 2>/dev/null | head -n1 | sed 's/.*://' || true
}

# ---------- 二进制安装 ----------
install_binary() {
  if binary_installed; then
    warn "已检测到二进制安装，请使用升级功能"
    return 0
  fi
  have systemctl || err "当前系统没有 systemd，请使用 Docker 安装"

  local dest_port https="" cert_path="" key_path="" tls_args=""
  prompt_port
  dest_port="$SELECTED_PORT"

  readp "启用 HTTPS? [y/N]: " https
  if [[ "$https" =~ ^[Yy]$ ]]; then
    readp "TLS 证书路径: " cert_path
    readp "TLS 私钥路径: " key_path
    [[ -f "$cert_path" ]] || err "证书文件不存在: ${cert_path}"
    [[ -f "$key_path" ]] || err "私钥文件不存在: ${key_path}"
    tls_args=" --cert ${INSTALL_DIR}/certs/server.crt --key ${INSTALL_DIR}/certs/server.key"
  fi

  echo
  readp "确认安装? [Y/n]: " confirm
  if [[ "$confirm" =~ ^[Nn]$ ]]; then
    echo
    warn "安装已取消"
    return 0
  fi

  get_latest_version
  download_binary
  local binary
  binary=$(extract_binary)

  local ip_addr
  ip_addr=$(get_ip)

  msg "创建系统用户..."
  id nodepass >/dev/null 2>&1 || useradd --system --home "$INSTALL_DIR" --shell /bin/false nodepass

  msg "创建目录..."
  mkdir -p "$INSTALL_DIR"/{bin,db,logs,certs}

  msg "安装二进制文件..."
  install -m 755 -o root -g root "$binary" "$INSTALL_DIR/bin/$BINARY_NAME"
  ln -sf "$INSTALL_DIR/bin/$BINARY_NAME" "/usr/local/bin/$BINARY_NAME"

  {
    printf 'PORT=%s\n' "$dest_port"
    printf 'DB_PATH=%s/db/database.db\n' "$INSTALL_DIR"
  } > "$INSTALL_DIR/config.env"

  if [[ "$https" =~ ^[Yy]$ ]]; then
    msg "安装证书..."
    install -m 644 "$cert_path" "$INSTALL_DIR/certs/server.crt"
    install -m 600 "$key_path" "$INSTALL_DIR/certs/server.key"
    chown nodepass:nodepass "$INSTALL_DIR/certs/server.crt" "$INSTALL_DIR/certs/server.key"
    {
      printf 'CERT_PATH=%s/certs/server.crt\n' "$INSTALL_DIR"
      printf 'KEY_PATH=%s/certs/server.key\n' "$INSTALL_DIR"
    } >> "$INSTALL_DIR/config.env"
  fi

  chown -R nodepass:nodepass "$INSTALL_DIR/db" "$INSTALL_DIR/logs" "$INSTALL_DIR/certs"
  chown nodepass:nodepass "$INSTALL_DIR" "$INSTALL_DIR/config.env"

  msg "注册 systemd 服务..."
  cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=NB-Panel
After=network.target

[Service]
User=nodepass
Group=nodepass
WorkingDirectory=${INSTALL_DIR}
EnvironmentFile=-${INSTALL_DIR}/config.env
ExecStart=${INSTALL_DIR}/bin/${BINARY_NAME} --port ${dest_port}${tls_args}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --quiet "$SERVICE_NAME"
  systemctl start "$SERVICE_NAME" || true
  sleep 1
  if ! systemctl is-active --quiet "$SERVICE_NAME"; then
    journalctl -u "$SERVICE_NAME" -n 20 --no-pager 2>/dev/null || true
    err "服务启动失败，请检查上方日志"
  fi

  local proto="http"
  if [[ "$https" =~ ^[Yy]$ ]]; then
    proto="https"
  fi

  echo
  sep
  echo -e " ${G}安装完成${N}"
  sep
  echo -e "   账号:    nbpanel / Np123456"
  echo -e "   路径:    ${INSTALL_DIR}/bin/${BINARY_NAME}"
  echo -e "   配置:    ${INSTALL_DIR}/config.env"
  echo -e "   URL:     ${C}${proto}://${ip_addr}:${dest_port}${N}"
  echo -e "   ${Y}请首次登录后立即修改默认密码${N}"
  sep
  echo
}

# ---------- 二进制升级 / 卸载 ----------
upgrade_binary() {
  binary_installed || { warn "二进制版未安装"; return 0; }

  get_latest_version
  download_binary
  local binary
  binary=$(extract_binary)

  local target="${INSTALL_DIR}/bin/${BINARY_NAME}"
  local backup="${target}.bak"
  msg "备份当前版本..."
  cp -f "$target" "$backup"
  chmod 755 "$backup"

  msg "停止服务并替换二进制..."
  systemctl stop "$SERVICE_NAME" 2>/dev/null || true
  install -m 755 "$binary" "$target"

  if systemctl start "$SERVICE_NAME" && sleep 1 && systemctl is-active --quiet "$SERVICE_NAME"; then
    rm -f "$backup"
    ok "二进制升级完成"
  else
    warn "新版本启动失败，正在回滚..."
    install -m 755 "$backup" "$target"
    systemctl start "$SERVICE_NAME" 2>/dev/null || true
    err "升级失败，已回滚到旧版本"
  fi
}

uninstall_binary() {
  binary_installed || { warn "二进制版未安装"; return 0; }

  readp "确认卸载二进制版? [y/N]: " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || return 0

  systemctl stop "$SERVICE_NAME" 2>/dev/null || true
  systemctl disable "$SERVICE_NAME" 2>/dev/null || true
  rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
  systemctl daemon-reload
  systemctl reset-failed 2>/dev/null || true

  rm -rf "$INSTALL_DIR"
  rm -f "/usr/local/bin/${BINARY_NAME}" "/usr/local/bin/nodepassdash-ctl"

  if id nodepass >/dev/null 2>&1; then
    userdel nodepass 2>/dev/null || true
  fi

  ok "二进制版已卸载（包括用户和所有遗留文件）"
}

# ---------- Docker ----------
install_docker() {
  docker_available || err "Docker 未安装或未运行，请先启动 Docker"
  if container_exists; then
    warn "已检测到 Docker 容器 ${CONTAINER}，请使用升级功能"
    return 0
  fi

  local port_host data_dir ip_addr
  echo
  sep
  echo -e " ${B}Docker 安装${N}"
  sep

  prompt_port
  port_host="$SELECTED_PORT"

  readp "数据目录 [${DEFAULT_DATA_DIR}]: " data_dir
  data_dir=${data_dir:-$DEFAULT_DATA_DIR}
  is_safe_data_dir "$data_dir" || err "数据目录不安全或过于宽泛: ${data_dir}"

  echo
  readp "确认安装? [Y/n]: " confirm
  if [[ "$confirm" =~ ^[Nn]$ ]]; then
    echo
    warn "安装已取消"
    return 0
  fi

  ip_addr=$(get_ip)

  msg "创建数据目录..."
  mkdir -p "$data_dir"/{logs,public,db}
  chmod 755 "$data_dir" "$data_dir/logs" "$data_dir/public"
  chmod 700 "$data_dir/db"

  msg "拉取 Docker 镜像..."
  docker pull "$DOCKER_IMAGE"

  msg "启动容器..."
  docker run -d \
    --name "$CONTAINER_NAME" \
    --restart=always \
    --log-opt max-size=10m \
    --log-opt max-file=3 \
    -p "${port_host}:4000" \
    -e PORT=4000 \
    -v "$data_dir/logs:/app/logs" \
    -v "$data_dir/db:/app/db" \
    -v "$data_dir/public:/app/public" \
    "$DOCKER_IMAGE" || err "容器启动失败"

  if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    docker logs --tail 20 "$CONTAINER_NAME" 2>&1 || true
    err "容器未正常运行，请检查上方日志"
  fi

  echo
  sep
  echo -e " ${G}安装完成${N}"
  sep
  echo -e "   账号:    nbpanel / Np123456"
  echo -e "   数据:    ${data_dir}"
  echo -e "   URL:     ${C}http://${ip_addr}:${port_host}${N}"
  echo -e "   ${Y}请首次登录后立即修改默认密码${N}"
  sep
  echo
}

upgrade_docker() {
  docker_available || err "Docker 未安装或未运行"
  container_exists || { warn "Docker 版未安装"; return 0; }

  local port_host data_dir new_name
  port_host=$(container_port)
  data_dir=$(container_data_dir)
  port_host=${port_host:-$DEFAULT_PORT}

  if [[ -z "$data_dir" ]]; then
    data_dir="$DEFAULT_DATA_DIR"
    [[ -d "$data_dir" ]] || err "无法识别容器数据目录，请手动升级"
  fi
  is_safe_data_dir "$data_dir" || err "数据目录不安全或过于宽泛: ${data_dir}"

  msg "拉取最新镜像..."
  docker pull "$DOCKER_IMAGE"

  msg "重建容器 (端口 ${port_host}, 数据 ${data_dir})..."
  mkdir -p "$data_dir"/{logs,public,db}
  chmod 755 "$data_dir" "$data_dir/logs" "$data_dir/public"
  chmod 700 "$data_dir/db"

  # 先停旧容器并保留，用临时名称启动新容器；失败时自动恢复旧容器
  docker stop "$CONTAINER" >/dev/null 2>&1 || true
  new_name="${CONTAINER}-new"
  docker rm -f "$new_name" >/dev/null 2>&1 || true

  if ! docker run -d \
    --name "$new_name" \
    --restart=always \
    --log-opt max-size=10m \
    --log-opt max-file=3 \
    -p "${port_host}:4000" \
    -e PORT=4000 \
    -v "$data_dir/logs:/app/logs" \
    -v "$data_dir/db:/app/db" \
    -v "$data_dir/public:/app/public" \
    "$DOCKER_IMAGE"; then
    docker rm -f "$new_name" >/dev/null 2>&1 || true
    docker start "$CONTAINER" >/dev/null 2>&1 || true
    err "新容器启动失败，已恢复旧容器"
  fi

  sleep 1
  if ! docker ps --format '{{.Names}}' | grep -qx "$new_name"; then
    docker logs --tail 20 "$new_name" 2>&1 || true
    docker rm -f "$new_name" >/dev/null 2>&1 || true
    docker start "$CONTAINER" >/dev/null 2>&1 || true
    err "新容器未正常运行，已恢复旧容器"
  fi

  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  docker rename "$new_name" "$CONTAINER"
  ok "Docker 升级完成"
}

uninstall_docker() {
  docker_available || { warn "Docker 未安装或未运行"; return 0; }
  container_exists || { warn "Docker 版未安装"; return 0; }

  readp "确认卸载 Docker 版? [y/N]: " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || return 0

  local data_dir
  data_dir=$(container_data_dir)

  docker stop "$CONTAINER" >/dev/null 2>&1 || true
  docker rm "$CONTAINER" >/dev/null 2>&1 || true
  docker rmi "$DOCKER_IMAGE" 2>/dev/null || true

  if [[ -n "$data_dir" ]]; then
    readp "删除数据目录 ${data_dir}? [y/N]: " del
    if [[ "$del" =~ ^[Yy]$ ]]; then
      if is_safe_data_dir "$data_dir"; then
        rm -rf "$data_dir"
        ok "Docker 版和数据目录已删除"
      else
        warn "拒绝删除危险路径: ${data_dir}，请手动处理"
      fi
      return 0
    fi
  fi

  ok "Docker 版已卸载（数据目录保留）"
}

# ---------- 状态 / 日志 / 重启 ----------
show_status() {
  local port="" ver=""
  echo
  echo "  二进制:"
  if binary_installed; then
    port=$(grep '^PORT=' "$INSTALL_DIR/config.env" 2>/dev/null | cut -d= -f2 || true)
    ver=$("$INSTALL_DIR/bin/$BINARY_NAME" --version 2>/dev/null | head -n1 || true)
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
      echo "    状态: 运行中"
      echo "    端口: ${port:-$DEFAULT_PORT}"
    else
      echo "    状态: 已停止"
    fi
    if [[ -n "$ver" ]]; then
      echo "    版本: ${ver}"
    fi
  else
    echo "    未安装"
  fi

  echo
  echo "  Docker:"
  if container_exists; then
    port=$(container_port)
    if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
      echo "    状态: 运行中"
      echo "    端口: ${port:-$DEFAULT_PORT}"
      echo "    数据: $(container_data_dir)"
    else
      echo "    状态: 已停止"
    fi
  else
    echo "    未安装"
  fi
  echo
}

show_logs() {
  if container_exists; then
    docker logs --tail 50 "$CONTAINER"
  elif binary_installed; then
    journalctl -u "$SERVICE_NAME" -n 50 --no-pager
  else
    warn "未检测到已安装的 NB-Panel"
  fi
}

restart_panel() {
  if container_exists; then
    docker restart "$CONTAINER" >/dev/null
    ok "Docker 容器已重启"
  elif binary_installed; then
    systemctl restart "$SERVICE_NAME"
    ok "systemd 服务已重启"
  else
    warn "未检测到已安装的 NB-Panel"
  fi
}

# ---------- 菜单 ----------
install_menu() {
  echo
  sep
  echo -e " ${B}选择安装方式${N}"
  sep
  echo "   1. 二进制 (systemd)"
  echo "   2. Docker"
  sep
  readp "请选择 [1/2]: " method
  echo

  case "$method" in
    2) install_docker ;;
    *) install_binary ;;
  esac
}

main_menu() {
  local choice
  while true; do
    echo
    echo -e " ${B}${C}----------------------------------------${N}"
    echo -e " ${B}${C}     NB-Panel 管理脚本${N}"
    echo -e " ${B}${C}  github.com/lima-droid/NB-Panel${N}"
    echo -e " ${B}${C}----------------------------------------${N}"
    echo
    echo "    1. 安装"
    echo "    2. 卸载"
    echo "    3. 升级"
    echo "    4. 状态"
    echo "    5. 日志"
    echo "    6. 重启"
    echo "    0. 退出"
    echo
    readp "请选择 [0-6]: " choice

    case "$choice" in
      1) install_menu ;;
      2)
        echo
        local has_bin=0 has_dkr=0
        if binary_installed; then has_bin=1; fi
        if container_exists; then has_dkr=1; fi
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
        if container_exists; then
          upgrade_docker
        elif binary_installed; then
          upgrade_binary
        else
          warn "未检测到已安装的 NB-Panel"
        fi
        ;;
      4) show_status ;;
      5) show_logs ;;
      6) restart_panel ;;
      0) exit 0 ;;
      *) warn "无效选项" ;;
    esac

    echo
    readp "按回车键返回... " _ || true
  done
}

# ---------- 主入口 ----------
usage() {
  cat <<EOF
用法: bash install.sh [选项]

  -b, --binary          二进制安装 (systemd)
  -d, --docker          Docker 安装
  -u, --upgrade         升级已安装的版本
  -r, --remove          卸载二进制版
  -R, --remove-docker   卸载 Docker 版
  -s, --status          查看状态
  -l, --logs            查看日志
  -h, --help            显示帮助

  (无参数)              进入交互菜单
EOF
}

main() {
  case "${1:-}" in
    -h|--help)            usage; exit 0 ;;
  esac

  check_root

  case "${1:-}" in
    -b|--binary)          install_binary ;;
    -d|--docker)          install_docker ;;
    -u|--upgrade)
                          if container_exists; then
                            upgrade_docker
                          else
                            upgrade_binary
                          fi
                          ;;
    -r|--remove)          uninstall_binary ;;
    -R|--remove-docker)   uninstall_docker ;;
    -s|--status)          show_status ;;
    -l|--logs)            show_logs ;;
    "")                   main_menu ;;
    *)                    usage; exit 1 ;;
  esac
}

main "$@"
