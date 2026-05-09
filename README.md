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
| [Bazarr](https://github.com/morpheus65535/bazarr) | Subtitle management |
| [Pi-hole](https://github.com/pi-hole/pi-hole) | DNS and DHCP server |
| [nginx-proxy-manager](https://github.com/NginxProxyManager/nginx-proxy-manager) | Reverse proxy |
| [Homepage](https://github.com/gethomepage/homepage) | Dashboard |
| [Glance](https://github.com/glanceapp/glance) | Self-hosted start page |
