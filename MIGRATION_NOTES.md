# Media Server Migration Notes

## Current Server (source)

- **OS:** Ubuntu (current daily driver / desktop)
- **IP:** 192.168.1.181
- **User:** donald — uid=1000, gid=1000, supplemental `media` group at GID=1001
- **Stack path:** `/home/donald/src/jellyfin-stack`
- **Repo:** https://github.com/malcyon/jellyfin-stack (public)

### Storage (current)
| Mount | UUID | Notes |
|---|---|---|
| `/mnt/media` | `3b3a4cb8-ae88-48b7-8289-b150b57026e1` | USB ext4 drive — all media files |
| `/data` | `b3f05aa1-5d88-4d27-8b38-5bda5cfe469e` | Internal ext4 — OneDrive sync, SteamLibrary |

### GPU (current)
- Intel iGPU with VA-API at `/dev/dri/renderD128`
- Hardware transcoding is **disabled** in Jellyfin (`HardwareAccelerationType=none`)

---

## New Server (target: `media` / 192.168.1.182)

- **OS:** Ubuntu 26.04 LTS "Resolute Raccoon"
- **IP:** 192.168.1.182 (DHCP — should be made static before Pi-hole takes over DHCP)
- **User:** donald — uid=1000, gid=1000 — **no `media` group yet, no `docker` group**
- **Hostname:** `media` (already set correctly)
- **CPU:** 8 cores | **RAM:** 22GB
- **Docker:** not installed
- **Ansible:** not installed (also not on current machine — needs pip install)

### Storage (new server)
| Device | Size | Mount | Notes |
|---|---|---|---|
| sdb | 238.5GB | `/` (LVM, 100GB partition) | Boot/system drive, 81GB free |
| sda | 1.8TB | `/home` | Plenty of room for the stack |
| sdc–sdf | 0B | — | USB ports, nothing connected yet |

- **No `/data` drive** — the OneDrive/SteamLibrary drive is not present and not planned for the new server
- **USB media drive not connected yet** — will be plugged in after physical move

### GPU (new server)
- **NVIDIA GTX 1050 Ti** (GP107/EVGA)
- `/dev/dri/card0` and `/dev/dri/renderD128` are present (kernel DRM layer)
- No proprietary NVIDIA driver installed; nouveau not loaded
- Jellyfin hardware transcoding currently disabled — `/dev/dri` mapping is safe to keep

---

## Differences to Resolve

All differences resolved. ✅

| # | Issue | Fix |
|---|---|---|
| 1 | `media` group (GID=1001) missing | ✅ Ansible: `group` task + add donald |
| 2 | Docker not installed | ✅ Ansible: Docker CE install (pinned to `noble` repo) |
| 3 | Ubuntu 26.04 Docker apt repo | ✅ Hardcoded `noble` codename — `resolute` not yet in Docker's repo |
| 4 | `/mnt/media` doesn't exist | ✅ Ansible: create dir + fstab entry (UUID `3b3a4cb8`) |
| 5 | systemd-resolved stub on port 53 | ✅ Ansible: `DNSStubListener=no` drop-in + handler restart |
| 6 | `/data` volume doesn't exist on new server | ✅ Removed from `docker-compose.yml` and `homepage/widgets.yaml` |
| 7 | `HOMEPAGE_ALLOWED_HOSTS` hardcoded to `192.168.1.181` | ✅ Moved to `.env` / `env.j2`; set per-host in `vars.yml` |
| 8 | `encoding.xml` has `/dev/dri/renderD128` VA-API path | ✅ Same path exists on new server — no change needed |
| 9 | New server IP is DHCP | ✅ Static IP configured via Netplan (`enp3s0`, `192.168.1.182/24`, gw `192.168.1.254`); managed by Ansible template `netplan-static.yaml.j2` |

---

## Planned Architecture: Pi-hole + nginx-proxy-manager

### Goal
Replace unreliable `home.local` mDNS with authoritative local DNS under `morton.lan`.

### DNS flow
```
LAN clients
  → Pi-hole (DHCP + DNS, port 53/67 on host network)
       └─ *.morton.lan → 192.168.1.182
                              └─ nginx-proxy-manager (ports 80/443)
                                   ├─ morton.lan        → homepage :3000
                                   ├─ jellyfin.morton.lan → jellyfin :8096
                                   ├─ seerr.morton.lan  → seerr :5055
                                   ├─ radarr.morton.lan → radarr :7878
                                   ├─ sonarr.morton.lan → sonarr :8989
                                   ├─ prowlarr.morton.lan → prowlarr :9696
                                   ├─ sabnzbd.morton.lan → sabnzbd :8085
                                   ├─ qbit.morton.lan   → qbittorrent :8080
                                   ├─ pihole.morton.lan → pihole :8888
                                   └─ glance.morton.lan → glance :8081
```

### Pi-hole Docker requirements
- `network_mode: host` (required for DHCP broadcast)
- Web UI on port **8888** (avoids conflict with npm's port 80)
- `PIHOLE_WEBPASSWORD` → add to `.env` / Ansible vault
- `cap_add: NET_ADMIN`
- Config volumes: `./pihole/etc-pihole` and `./pihole/etc-dnsmasq.d`

### systemd-resolved fix (Ansible task)
Disable the stub listener so Pi-hole can bind port 53:
```ini
# /etc/systemd/resolved.conf.d/no-stub.conf
[Resolve]
DNSStubListener=no
```
Then: `systemctl restart systemd-resolved`

### Router changes (manual, after Pi-hole is running)
1. Reserve IP 192.168.1.182 for the server's MAC address
2. Disable DHCP on the router
3. Verify clients pick up new DNS from Pi-hole

---

## Services: Config Backup Status

| Service | Config in git? | Secrets present? | Notes |
|---|---|---|---|
| **homepage** | ✅ Yes | Fixed — `{{HOMEPAGE_VAR_*}}` via `.env` | `services.yaml`, `widgets.yaml`, etc. now tracked |
| **jellyfin** | ✅ Partial | None found | XML/JSON tracked; DB intentionally excluded — will rescan media |
| **glance** | ✅ Git (direct) | None | `glance.yml` and `home.yml` tracked; `.bak` excluded |
| **gluetun** | ✅ Complete | WireGuard key in `.env` ✅ | `servers.json` is auto-generated runtime data; no config files needed |
| **qbittorrent** | ✅ Ansible template + git | WebUI password hash in vault; `categories.json` tracked in git | No backup/restore needed |
| **prowlarr** | ✅ Ansible template | API key in vault | `prowlarr-config.xml.j2` seeds config; restore indexers + credentials via built-in backup |
| **radarr** | ✅ Ansible template | API key in vault | `radarr-config.xml.j2` seeds config on new server; restore DB via built-in backup |
| **sonarr** | ✅ Ansible template | API key in vault | `sonarr-config.xml.j2` seeds config on new server; restore DB via built-in backup |
| **seerr** | ✅ Ansible template | Session secret, VAPID keys, all API keys in vault | Jellyfin serverId/library IDs will be stale — re-run Jellyfin setup in Seerr UI after deploy |
| **sabnzbd** | ✅ Ansible template | Newsgroup credentials, API key, NZB key in vault | Full `sabnzbd.ini.j2` template; no backup/restore needed |
| **bazarr** | ✅ Ansible template | Subtitle provider credentials, Radarr/Sonarr keys, Flask secret in vault | Full config templated; no manual setup needed |
| **nginx-proxy-manager** | ❌ Gitignored (intentional) | `keys.json` has RSA private key | Config lives in `database.sqlite`; NPM generates fresh keys and DB on new install; full manual setup post-deploy |

---

## Services Added Post-Migration

### Grafana Alloy (monitoring agent)
Native systemd service (not Docker), installed via Grafana apt repo. Ships metrics and logs to Grafana Cloud.

| Component | What it collects |
|---|---|
| `prometheus.exporter.unix` | Host/node metrics (CPU, memory, disk, network). Job: `integrations/unix` |
| `prometheus.exporter.cadvisor` | Docker container resource metrics. Job: `integrations/cadvisor` |
| `loki.source.docker` | Docker container stdout/stderr logs |
| `loki.source.journal` | systemd journal logs |

**Key implementation notes:**
- `containerd_host` must be the raw socket path `/run/containerd/containerd.sock` — using the `unix:///` URI prefix causes Go to treat it as a relative path and fail with "no such file or directory"
- containerd socket must be `root:docker 0660` — Ansible task sets this immediately; a systemd drop-in (`/etc/systemd/system/containerd.service.d/docker-group-socket.conf`) persists the permission on containerd restarts
- Do not set `containerd_namespace = "moby"` — this causes the containerd factory to claim Docker containers before the Docker factory can, resulting in container IDs instead of human-readable names as the `name` metric label

### Pi-hole Exporter
Docker container (`ekofr/pihole-exporter:latest`) running with `network_mode: host` so it can reach Pi-hole's API on `localhost:8888`. Alloy scrapes it at `localhost:9617` with `job="pihole"`.

- Uses `PIHOLE_PASSWORD` env var (Pi-hole v6 authentication)
- Dashboard imported from grafana.com: search "Pi-hole Exporter" by eko

---

## Home PC Configuration

### Static IP on media server

The media server (`192.168.1.182`) is configured with a static IP via Netplan, bypassing DHCP entirely. This prevents boot failures caused by Pi-hole DHCP not yet being ready when the server starts.

Managed by Ansible template `ansible/templates/netplan-static.yaml.j2`, deployed to `/etc/netplan/00-installer-config.yaml` on the media server. Variables in `ansible/group_vars/media_servers/vars.yml`:
- Interface: `enp3s0` (MAC `34:17:eb:ca:54:71`)
- IP: `192.168.1.182/24`, gateway `192.168.1.254`
- DNS: `1.1.1.1`, `8.8.8.8` (public — Pi-hole handles LAN DNS for clients, not the server itself)

### SSHFS mount for `/mnt/media`
The home PC (`home` / 192.168.1.181) mounts the media server's `/mnt/media` locally at `/mnt/media` via SSHFS, allowing the file manager to browse and reorganize media files directly.

Managed by a systemd mount unit at `/etc/systemd/system/mnt-media.mount`. Mounts automatically after network is up on boot.

**Prerequisites on home PC:**
- `sshfs` installed (`sudo apt install sshfs`)
- `user_allow_other` uncommented in `/etc/fuse.conf`
- Server's host key in `/root/.ssh/known_hosts` (`sudo ssh-keyscan 192.168.1.182 | sudo tee -a /root/.ssh/known_hosts`)

**Unit file:** `/etc/systemd/system/mnt-media.mount`
```ini
[Unit]
Description=Media server SSHFS mount
After=network-online.target
Wants=network-online.target

[Mount]
What=donald@192.168.1.182:/mnt/media
Where=/mnt/media
Type=fuse.sshfs
Options=_netdev,idmap=user,uid=1000,gid=1000,IdentityFile=/home/donald/.ssh/id_ed25519,allow_other,reconnect,ServerAliveInterval=15,ServerAliveCountMax=3

[Install]
WantedBy=multi-user.target
```

---

## Future Work

### Ongoing stack backup/restore (`backup.sh` / `restore.sh`)
Scripts for routine backup and disaster recovery of the entire stack. Design TBD.

### Video transcoding — Tdarr / FileFlows / Unmanic
Automated transcoding pipeline to convert video files to AAC audio for better compatibility with mobile clients (Jellyfin on iOS/Android often can't direct play non-AAC audio). Options:
- **Tdarr** — most mature, plugin-based, has a worker model
- **FileFlows** — newer, flow-based UI, active development
- **Unmanic** — simpler, lightweight
All three can watch a folder and transcode in place or to a target directory.

### Shared notes — Obsidian Sync alternative
Self-hosted sync backend for Obsidian or a standalone notes app. Options:
- **Obsidian LiveSync** (self-hosted CouchDB backend) — keeps using Obsidian clients
- **Silverbullet** — self-hosted wiki/notes with Markdown
- **Joplin Server** — pairs with Joplin clients, supports end-to-end encryption

### Remote access — Tailscale or Cloudflare Tunnel
Secure access to the stack from outside the LAN without port forwarding:
- **Tailscale** — WireGuard mesh VPN, zero-config, free tier covers personal use; access everything via LAN IPs over the tunnel
- **Cloudflare Tunnel** — exposes specific services via Cloudflare's edge with no open ports; better for sharing individual services publicly

---

## Service Reconfiguration Checklist (post-deploy, manual)

These must be done through each service's web UI after first boot:

- [ ] **Pi-hole** — Add DNS records: `morton.lan → 192.168.1.182`, wildcard or individual `*.morton.lan` records; then disable DHCP on the router and verify clients pick up DNS from Pi-hole
- [ ] **nginx-proxy-manager** — Create proxy hosts for each `*.morton.lan` subdomain; issue SSL certs if desired
- [ ] **Jellyfin** — Run initial setup wizard; add media library pointing to `/mnt/media/movies`, `/mnt/media/tv`, etc.; let it scan
- [ ] **Radarr** — Copy the latest backup zip from `radarr/Backups/scheduled/` to the new server, then restore: `Settings → Backup → Restore`. Restores quality profiles, root folders, download client config, and movie library.
- [ ] **Sonarr** — Same as Radarr. Backup zips are in `sonarr/Backups/scheduled/`.
- [ ] **Prowlarr** — Copy the latest backup zip from `prowlarr/Backups/scheduled/` to the new server, then restore: `Settings → Backup → Restore`. After restore, trigger a manual sync in Radarr and Sonarr (`Settings → Indexers → Sync App Indexers`).
- [ ] **Seerr** — `jellyfin.serverId` and library IDs will be stale since Jellyfin rebuilt its database. Go to **Settings → Jellyfin** and re-run the server sync to update the server ID and re-discover libraries.
- [ ] **homepage** — Update `href` URLs in `services.yaml` from `home.local:PORT` to `service.morton.lan`
- [ ] **FreshRSS** — Visit `http://freshrss.morton.lan` and run the setup wizard; create admin account; add RSS feeds
- [ ] **RomM** — Add vault secrets (`vault_romm_db_password`, `vault_romm_db_root_password`, `vault_romm_auth_secret_key`) then run Ansible; ROMs go in `/mnt/media/roms`; optionally register a Twitch/IGDB app for metadata
- [ ] **nginx-proxy-manager** — Add proxy hosts for `freshrss.morton.lan` → `:8082` and `romm.morton.lan` → `:8083`
