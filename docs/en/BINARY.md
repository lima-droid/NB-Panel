# Binary Deployment (NB-Panel)

This guide deploys NB-Panel as a native binary on a server (recommended for VPS / systemd environments).

## Requirements

- Linux x86_64 / arm64 (other platforms may be available in Releases)
- A working directory to persist `db/` and `logs/`

## Option A: Install Script (Recommended)

NB-Panel provides an installation script in this repo: `scripts/install.sh`.

```bash
curl -fsSL https://raw.githubusercontent.com/lima-droid/NB-Panel/main/scripts/install.sh | bash
```

If you prefer to inspect it first:

```bash
wget https://raw.githubusercontent.com/lima-droid/NB-Panel/main/scripts/install.sh
chmod +x install.sh
./install.sh
```

## Option B: Manual Install (Releases)

1) Download the archive from GitHub Releases and extract it.
2) Put the `nb-panel` binary in a directory, for example: `/opt/nb-panel/bin/nb-panel`.
3) Run from the working directory so `db/` and `logs/` are created next to it:

```bash
cd /opt/nb-panel
./bin/nb-panel --port 3000
```

## Systemd Example

Create `/etc/systemd/system/nb-panel.service`:

```ini
[Unit]
Description=NB-Panel
After=network.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/nb-panel
ExecStart=/opt/nb-panel/bin/nb-panel --port 3000
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now nb-panel
sudo systemctl status nb-panel --no-pager
```

## First Login / Reset Password

- First start prints initial admin credentials in logs (`journalctl -u nb-panel -n 200`).
- Reset admin password:

```bash
/opt/nb-panel/bin/nb-panel --resetpwd
sudo systemctl restart nb-panel
```

## HTTPS (TLS)

Provide cert and key:

```bash
/opt/nb-panel/bin/nb-panel --port 443 --cert /path/to/cert.pem --key /path/to/key.pem
```

In production, you can also keep NB-Panel on an internal port and place it behind Nginx/Caddy.

## Upgrade

- If installed via script, re-run the script update command if available in your installation.
- If installed manually, replace the binary with the new release, then restart the service.

## Uninstall

If installed via script, use the uninstall option:

```bash
./install.sh uninstall
```

