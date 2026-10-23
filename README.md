<div align="center">
  <img src="docs/nb-panel-logo.png" alt="NB-Panel" height="100">
  <h1>NB-Panel</h1>
  <p><strong>Lightweight tunnel management panel · single binary · ready to use</strong></p>
  <p>
    <a href="https://github.com/lima-droid/NB-Panel/releases">
      <img src="https://img.shields.io/github/v/release/lima-droid/NB-Panel?style=flat-square&label=Version&color=2496ed" alt="Release">
    </a>
    <a href="https://github.com/lima-droid/NB-Panel">
      <img src="https://img.shields.io/github/stars/lima-droid/NB-Panel?style=flat-square&label=Stars&color=ffc107" alt="Stars">
    </a>
    <a href="https://github.com/lima-droid/NB-Panel/blob/main/LICENSE">
      <img src="https://img.shields.io/github/license/lima-droid/NB-Panel?style=flat-square&label=License&color=success" alt="License">
    </a>
    <a href="https://github.com/lima-droid/NB-Panel">
      <img src="https://img.shields.io/github/last-commit/lima-droid/NB-Panel?style=flat-square&label=Updated&color=blueviolet" alt="Last Commit">
    </a>
    <a href="https://t.me/NBPanel">
      <img src="https://img.shields.io/badge/Telegram-NBPanel-26A5E4?style=flat-square&logo=telegram" alt="Telegram">
    </a>
  </p>
  <p>
    <b>English</b> · <a href="docs/zh-CN/README.md">简体中文</a>
  </p>
</div>

---

NB-Panel is a lightweight tunnel management panel built with a **Go backend, React frontend, and SQLite storage**. It ships as a single binary and works out of the box.

## ✨ Features

| Feature | Description |
|---------|-------------|
| 🎯 **Endpoint management** | Manage all NP masters in one place, with batch actions, sorting, and search |
| 🌉 **Tunnel management** | Create and edit tunnels visually, with protocol and scenario templates |
| 📊 **Live monitoring** | Tunnel status, traffic, and logs pushed over SSE/WebSocket |
| 📈 **Traffic charts** | Hourly, daily, and weekly traffic trends |
| 🔐 **OAuth2 login** | Cloudflare OAuth2 support; password login can be disabled |
| 🌍 **Multi-language** | Built-in English and Simplified Chinese UI |
| 📱 **Mobile friendly** | Responsive layout, QR-code import for the mobile app |
| 🛠️ **Ops toolbox** | Log viewer, network debugging, and system status charts |

> [Full changelog →](https://github.com/lima-droid/NB-Panel/releases)

---

## 🚀 Quick start

### Linux one-liner

```bash
bash <(wget -qO- https://raw.githubusercontent.com/lima-droid/NB-Panel/main/scripts/install.sh)
# or, if only curl is available:
bash <(curl -fsSL https://raw.githubusercontent.com/lima-droid/NB-Panel/main/scripts/install.sh)
```

The systemd binary installation resolves and pulls the **latest** official upstream
**NodePassDash** release at runtime (statically linked, matching your architecture);
Docker uses this repository's image. Downloaded archives are verified against the
release SHA256 checksums.

### Docker

```bash
docker run -d --name nbpanel -p 4000:4000 ghcr.io/lima-droid/nb-panel:latest
```

Persist data by mounting `/app/db`, `/app/logs`, and `/app/public`, for example:

```bash
docker run -d --name nbpanel --restart=always -p 4000:4000 \
  -v /opt/nbpanel-data/db:/app/db \
  -v /opt/nbpanel-data/logs:/app/logs \
  -v /opt/nbpanel-data/public:/app/public \
  ghcr.io/lima-droid/nb-panel:latest
```

### Installer options

| Option | Description |
|--------|-------------|
| `-b, --binary` | Install as a systemd service |
| `-d, --docker` | Install with Docker |
| `-u, --upgrade` | Upgrade the detected installation |
| `-r, --remove` | Uninstall the binary installation |
| `-R, --remove-docker` | Uninstall the Docker installation |
| `-s, --status` | Show installation status |
| `-l, --logs` | Show recent logs |
| `-h, --help` | Show help |

Run the installer without arguments for the interactive menu.

---

## ⚙️ CLI arguments

| Argument | Description |
|----------|-------------|
| `--help` | ❓ Help |
| `--version` | ℹ️ Version |
| `--port 8080` | 🔌 Listen port (default `4000`) |
| `--log-level INFO` | 📝 Log level |
| `--cert / --key` | 🔒 TLS certificate and key |
| `--disable-login` | 🚫 Disable login |
| `--sse-debug-log` | 🐛 SSE debug logging |
| `--resetpwd` | 🔑 Reset the admin password |

---

## 🔑 Default login

| | |
|---|---|
| **Username** | `nbpanel` |
| **Password** | `Np123456` |

> ⚠️ Change the default password immediately after the first login.
> The installer creates a systemd service named `nodepassdash`, or a Docker container named `nbpanel`.

---

## 📋 Requirements

### Binary installation

- 🐧 **Linux** with `systemd` (Debian / Ubuntu / CentOS and derivatives)
- 🖥️ **x86_64**, **arm64**, **armv7**, or **armv6**
- 👑 **root** for installation
- 📡 **curl** or **wget**

The upstream binary is statically linked. Alpine and other non-systemd systems should
use the Docker installation.

### Docker installation

- 🐳 **Docker** with the daemon running (multi-arch image)

---

## 📝 License

BSD-3-Clause · See [LICENSE](LICENSE)

## ⚠️ Disclaimer

This project is provided "as is", without warranty of any kind, express or implied.
Users are responsible for complying with local laws and using it only for lawful purposes.
The author is not liable for any direct, indirect, incidental, or consequential damages.

---

## ⭐ Stargazers

[![Stargazers](https://img.shields.io/github/stars/lima-droid/NB-Panel?style=for-the-badge&logo=github&color=gold)](https://github.com/lima-droid/NB-Panel)
