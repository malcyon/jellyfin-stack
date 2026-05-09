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

## Future plans

### Services to add
| Service | Purpose | Notes |
|---|---|---|
| **Graylog** | Centralized log aggregation | Requires MongoDB + Elasticsearch/OpenSearch; resource-heavy |
| **FreshRSS** | Self-hosted RSS reader | Lightweight, easy to add |
| **Nextcloud** (or alternative) | Shared filesystem / cloud storage | Heavy; Seafile is a lighter alternative |
| **Tdarr / Fileflows / Unmanic** | Automated media transcoding — add AAC audio tracks | Evaluate which fits workflow best |
| **Restic + Restic REST Server** | Automated backups | Back up Jellyfin db, *arr databases, config dirs |
| **RomM** | ROM manager for game library | Integrates with Jellyfin |
| **Tailscale or Cloudflare Tunnel** | Secure remote access without port forwarding | Tailscale is simpler; Cloudflare Tunnel avoids VPN client requirement |

### Infrastructure
- **UPS** — protect the media server and router from power loss; prevents database corruption on unclean shutdown
- **Secondary Pi-hole** — run a second Pi-hole instance on another device (e.g. a Raspberry Pi) and configure it as the backup DNS server in Pi-hole's DHCP settings; prevents full network DNS outage if the media server goes down
