<div align="center">
  <img src="docs/nb-panel-logo.png" alt="NB-Panel" height="100">
  <h1>NB-Panel</h1>
  <p><strong>轻量级隧道管理面板 · 单二进制 · 开箱即用</strong></p>
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
    <img src="https://img.shields.io/badge/Build-passing-ff69b4?style=flat-square" alt="Build">
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

NB面板 是一个轻量级隧道管理面板，**Go 后端 + React 前端 + SQLite 存储**，单二进制文件部署，开箱即用。

## ✨ 功能一览

| 功能 | 说明 |
|------|------|
| 🎯 **端点管理** | 统一管理所有 NP主控端，支持批量操作、排序、搜索 |
| 🌉 **隧道管理** | 可视化创建和编辑隧道，支持多种协议和场景模板 |
| 📊 **实时监控** | SSE/WebSocket 推送隧道状态、流量、日志 |
| 📈 **流量图表** | 小时/日/周多维度流量趋势 |
| 🔐 **OAuth2 登录** | 支持 Cloudflare OAuth2，可关闭密码登录 |
| 🌍 **多语言** | 内置中英文界面 |
| 📱 **移动端友好** | 响应式布局，支持二维码导入移动端 App |
| 🛠️ **运维工具** | 日志查看器、网络调试、系统状态图表 |

> [完整更新日志 →](https://github.com/lima-droid/NB-Panel/releases)

---

## 🚀 快速开始

### Linux 一键安装

```bash
bash <(wget -qO- https://raw.githubusercontent.com/lima-droid/NB-Panel/main/scripts/install.sh)
```

### Docker

```bash
docker run -d --name nbpanel -p 4000:4000 ghcr.io/lima-droid/nb-panel:latest
```

### 手动安装

`scripts/install.sh` 同时支持二进制（systemd）和 Docker 部署。

---

## ⚙️ CLI 参数

| 参数 | 说明 |
|------|------|
| `--help` | ❓ 帮助 |
| `--version` | ℹ️ 版本 |
| `--port 8080` | 🔌 端口（默认 4000） |
| `--log-level INFO` | 📝 日志级别 |
| `--cert / --key` | 🔒 TLS 证书 |
| `--disable-login` | 🚫 关闭登录 |
| `--sse-debug-log` | 🐛 SSE 调试日志 |
| `--resetpwd` | 🔑 重置密码 |

---

## 🔑 默认登录

| | |
|---|---|
| **用户名** | `nbpanel` |
| **密码** | `Np123456` |

> 密码可通过环境变量 `NB_PANEL_ADMIN_PASSWORD` 覆盖。

---

## 📋 系统要求

- 🐧 **Linux / macOS**
- 🐳 **Docker**（可选）

---

## 📝 许可

BSD-3-Clause · 详见 [LICENSE](LICENSE)

## ⚠️ 免责声明

本项目按"现状"提供，不含任何明示或暗示的担保。使用者须遵守当地法律法规并仅用于合法目的。作者不对任何直接、间接、偶发或后果性损害承担责任。

---

## ⭐ Stargazers

[![Stargazers](https://img.shields.io/github/stars/lima-droid/NB-Panel?style=for-the-badge&logo=github&color=gold)](https://github.com/lima-droid/NB-Panel)

