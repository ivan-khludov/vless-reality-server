# VLESS Reality Server

One-command setup for a self-hosted **VLESS + Reality** proxy server using Xray. Reality disguises traffic as normal TLS to a chosen destination (e.g. Cloudflare), which helps avoid simple DPI blocking.

## Requirements

- **OS:** Ubuntu (tested on 24.04). May work on other Debian-based systems.
- **Root:** Script must be run as root (or with `sudo`).
- **Port:** Configurable at install (default 443); the chosen port must be free (no other service should listen on it).

## Installation

```bash
sudo bash install.sh
```

On first run the script will prompt for:

- **SNI** (Server Name Indication for Reality), default `www.cloudflare.com` — press Enter to use the default.
- **Listen port** for VLESS, default 443 — press Enter to use the default.
- **Client name** (label for the first client in the link), default `auto-vless-reality` — press Enter to use the default.

Then the script will:

1. Install dependencies: `curl`, `openssl`, `uuid-runtime`, `jq`
2. Install Xray via the [official Xray-install script](https://github.com/XTLS/Xray-install)
3. Generate UUID, X25519 keys, and short id for Reality
4. Write Xray config with VLESS + Reality (TCP, port chosen at install, flow `xtls-rprx-vision`)
5. Enable and start the `xray` systemd service
6. Detect the server’s external IP and build a VLESS client link
7. Save the link to `files/vless-reality-clients.txt` and print it

Use the printed link in a VLESS Reality–compatible client (e.g. v2rayN, Nekoray, Shadowrocket, Hiddify). To add more clients later, use `add-config.sh` (see below).

## Adding another client

After installation, run:

```bash
sudo ./add-config.sh
```

The script adds a new client (new UUID and short id) without removing existing ones, restarts Xray, and appends the new client link to `files/vless-reality-clients.txt`. If the config or public key is missing, it exits with an error asking you to run `install.sh` first.

## Listing clients

To see all clients (numbered by index) and their UUIDs/shortIds:

```bash
sudo ./show-configs.sh
```

Use the numbers shown when removing a client.

## Removing a client

To remove a client by its number (from `show-configs.sh`):

```bash
sudo ./remove-config.sh 2
```

This removes the client from the Xray config, restarts Xray, and **overwrites** `files/vless-reality-clients.txt` so it only lists links for the remaining clients. The generated txt file always reflects the current config after a removal.

## Updating port or SNI

To change the **listen port** for VLESS (config, Xray restart, and clients file updated):

```bash
sudo ./update-port.sh
```

To change the **SNI** and the associated Reality dest (config, Xray restart, and clients file updated):

```bash
sudo ./update-sni.sh
```

Each script prompts for the new value with the current one as default; press Enter to keep it.

## Important paths

| Path                              | Description                                                                                |
| --------------------------------- | ------------------------------------------------------------------------------------------ |
| `/usr/local/etc/xray/config.json` | Xray config                                                                                |
| `files/vless-reality-clients.txt` | Client VLESS links (in repo root; `files/` is gitignored)                                  |
| `files/.vless-reality-public-key` | Server Reality public key, used when adding clients (in repo root; `files/` is gitignored) |
| `files/server-ip`                 | Cached server IP for links; set at first run, no network calls afterward. Edit and re-run a script that rewrites links to update. |

## Service

- **Start:** `sudo systemctl start xray`
- **Stop:** `sudo systemctl stop xray`
- **Status:** `sudo systemctl status xray`
- **Logs:** `journalctl -u xray -f`
