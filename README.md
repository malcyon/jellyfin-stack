# jellyfin-stack

Infrastructure configuration for my personal home media server.

The stack is deployed with Docker Compose and provisioned via Ansible. See [ansible/README.md](ansible/README.md) for setup instructions.

## Services

| Service | Purpose |
|---|---|
| [Jellyfin](https://github.com/jellyfin/jellyfin) | Media server |
| [Radarr](https://github.com/Radarr/Radarr) | Movie collection manager |
| [Sonarr](https://github.com/Sonarr/Sonarr) | TV series collection manager |
| [Prowlarr](https://github.com/Prowlarr/Prowlarr) | Indexer manager |
| [Seerr](https://github.com/seerr-team/seerr) | Media request management |
| [SABnzbd](https://github.com/sabnzbd/sabnzbd) | Usenet downloader |
| [qBittorrent](https://github.com/qbittorrent/qBittorrent) | Torrent downloader |
| [Gluetun](https://github.com/qdm12/gluetun) | VPN client (WireGuard) |
| [Pi-hole](https://github.com/pi-hole/pi-hole) | DNS and DHCP server |
| [nginx-proxy-manager](https://github.com/NginxProxyManager/nginx-proxy-manager) | Reverse proxy |
| [Homepage](https://github.com/gethomepage/homepage) | Dashboard |
| [Glance](https://github.com/glanceapp/glance) | Self-hosted start page |
| [FreshRSS](https://github.com/FreshRSS/FreshRSS) | Self-hosted RSS Reader |
| [RomM](https://github.com/rommapp/romm) | Self-hosted ROM Manager |
| [Kiwix](https://github.com/kiwix/kiwix-tools) | Offline ZIM archive server (Wikipedia, etc.) |
| [Tailscale](https://tailscale.com/) | WireGuard-based VPN for remote LAN access |
| [Navidrome](https://github.com/navidrome/navidrome) | Subsonic-compatible music streaming server |
| [Tdarr](https://github.com/HaveAGitGat/Tdarr) | Automated media transcoding (e.g. add AAC audio tracks) |

## Future plans

### Services to add
| Service | Purpose | Notes |
|---|---|---|
| **Restic + Restic REST Server** | Automated backups | Back up Jellyfin db, *arr databases, config dirs |

### Infrastructure
- **UPS** — protect the media server and router from power loss; prevents database corruption on unclean shutdown
- **Secondary Pi-hole** — run a second Pi-hole instance on another device (e.g. a Raspberry Pi) and configure it as the backup DNS server in Pi-hole's DHCP settings; prevents full network DNS outage if the media server goes down
