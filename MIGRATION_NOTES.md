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

### Must fix before `docker compose up`

| # | Issue | Fix |
|---|---|---|
| 1 | `media` group (GID=1001) missing | Ansible: `group` task + add donald |
| 2 | Docker not installed | Ansible: Docker CE install |
| 3 | Ubuntu 26.04 Docker apt repo | Verify `resolute` codename is in Docker's repo; fall back to `noble` packages if not |
| 4 | `/mnt/media` doesn't exist | Ansible: create dir + fstab entry (UUID `3b3a4cb8`) |
| 5 | systemd-resolved stub on port 53 | Ansible: disable `DNSStubListener` before Pi-hole starts |

### Config changes needed

| # | Issue | Fix |
|---|---|---|
| 6 | `/data` volume doesn't exist on new server | ✅ Done — removed from `docker-compose.yml` and `homepage/widgets.yaml` |
| 7 | `HOMEPAGE_ALLOWED_HOSTS` has hardcoded IP `192.168.1.181` | Move to `.env` as `HOMEPAGE_ALLOWED_HOSTS`; Ansible sets it per-host |
| 8 | `encoding.xml` has `/dev/dri/renderD128` VA-API path | Same path exists on new server — no change needed |

### Nice to have

| # | Issue | Notes |
|---|---|---|
| 9 | New server IP is DHCP | ✅ Done — both IPs are reserved in router (home=192.168.1.181, media=192.168.1.182) |
| 10 | Ansible not installed | `pip install --user ansible` on this machine before running playbook |

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

## Future Work

### One-time migration script (`migrate.sh`)
A script to run on the home server before migration. Should:
- Trigger a fresh backup via each service's API (`POST /api/v3/command {"name":"Backup"}`) for Radarr, Sonarr, and Prowlarr
- Wait for backups to complete, then collect the latest zip from each `*/Backups/scheduled/` directory
- Bundle them into a tarball for manual `scp` to the new server
- User places the zips in the right dirs on new server (after first `docker compose up`), then restores via each service's UI

### Ongoing stack backup/restore (`backup.sh` / `restore.sh`)
Scripts for routine backup and disaster recovery of the entire stack. Design TBD.

---

## Ansible Playbook: Outstanding Tasks

All tasks complete. ✅

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
