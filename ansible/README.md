# Media Server Ansible Playbook

Automates the setup of a Jellyfin media server.


## Step 1 — Configure the inventory

Edit `ansible/inventory.yml` and set the server's IP address:

```yaml
media-server:
  ansible_host: 192.168.1.182   # ← update this
  ansible_user: donald
```

Verify you can reach the server:

```bash
ssh media
```

---

## Step 2 — Review vars

Open `ansible/group_vars/media_servers/vars.yml`. The defaults match this stack's setup but review:

| Variable | Description |
|---|---|
| `stack_user` | Linux user on the target server |
| `stack_path` | Where the repo will be cloned |
| `repo_url` | Git remote (do not change) |
| `puid` / `pgid` | Must match `donald`'s UID and the `media` group GID on the server |
| `tz` | Timezone |
| `sabnzbd_host_whitelist` | Comma-separated hosts/IPs/subnets SABnzbd will accept requests from |

---

## Step 3 — Create and encrypt the vault

The vault holds all secrets. **Never commit the plaintext vault file.**

```bash
cp ansible/group_vars/media_servers/vault.yml.example \
   ansible/group_vars/media_servers/vault.yml
```

Edit `vault.yml` and fill in every `REPLACE_ME` value:

| Variable | Where to find it |
|---|---|
| `vault_wireguard_private_key` | Surfshark VPN dashboard → WireGuard config |
| `vault_wireguard_addresses` | Same WireGuard config file |
| `vault_firewall_outbound_subnets` | Your LAN subnet, e.g. `192.168.1.0/24` |
| `vault_jellyfin_api_key` | Jellyfin → Dashboard → API Keys |
| `vault_seerr_api_key` | Seerr → Settings → General → API Key |
| `vault_radarr_api_key` | Radarr → Settings → General → API Key |
| `vault_sonarr_api_key` | Sonarr → Settings → General → API Key |
| `vault_prowlarr_api_key` | Prowlarr → Settings → General → API Key |
| `vault_sabnzbd_api_key` | SABnzbd → Config → General → API Key |
| `vault_sabnzbd_nzb_key` | SABnzbd → Config → General → NZB Key |
| `vault_sabnzbd_server_username` | Your newsgroup provider username |
| `vault_sabnzbd_server_password` | Your newsgroup provider password |
| `vault_qbittorrent_password_hash` | Value of `WebUI\Password_PBKDF2` in `qbittorrent/qBittorrent/qBittorrent.conf` (without surrounding quotes) |

Once all values are filled in, encrypt the file:

```bash
ansible-vault encrypt ansible/group_vars/media_servers/vault.yml
```

You will be prompted to set a vault password. Store it somewhere safe (password manager recommended). The encrypted file is safe to leave on disk — it is already in `.gitignore`.

To edit the vault later:

```bash
ansible-vault edit ansible/group_vars/media_servers/vault.yml
```

---

## Step 4 — Run the playbook

From the repo root:

```bash
ansible-playbook -i ansible/inventory.yml ansible/playbook.yml --ask-vault-pass
```

Enter your vault password when prompted. The playbook will:
1. Set up Docker and system dependencies
2. Clone the repo to the server
3. Deploy all service configs from vault
4. Start the full stack

> **Note:** After the playbook completes, log out and back in (or run `newgrp docker`) on the server before using `docker` commands directly — the group membership change requires a new session.

---

## Step 5 — Post-deploy manual steps

These must be done through each service's web UI after the first boot.

### Pi-hole
1. Open Pi-hole admin at `http://192.168.1.182:8888`
2. Add a DNS record: `morton.lan → 192.168.1.182`
3. Add individual records or a wildcard for each subdomain
4. Go to your router and **disable its built-in DHCP server**
5. Enable DHCP in Pi-hole (Settings → DHCP)

### nginx-proxy-manager
1. Open npm at `http://192.168.1.182:81` (default login: `admin@example.com` / `changeme`)
2. Create a proxy host for each service pointing to its container name and port:

| Domain | Forward to |
|---|---|
| `morton.lan` | `homepage:3000` |
| `jellyfin.morton.lan` | `jellyfin:8096` |
| `seerr.morton.lan` | `seerr:5055` |
| `radarr.morton.lan` | `radarr:7878` |
| `sonarr.morton.lan` | `sonarr:8989` |
| `prowlarr.morton.lan` | `prowlarr:9696` |
| `sabnzbd.morton.lan` | `sabnzbd:8080` |
| `qbit.morton.lan` | `qbittorrent:8080` |
| `pihole.morton.lan` | `localhost:8888` |
| `glance.morton.lan` | `glance:8080` |

### Jellyfin
- Run the setup wizard; add your media library pointing to `/data/movies`, `/data/tv`, etc.
- Let it scan (the USB drive must be plugged in and mounted at `/mnt/media`)

### Radarr
- Ansible pre-seeds the API key so homepage and Prowlarr connections work immediately
- Restore full config: **Settings → Backup → Restore** — use the latest zip from `radarr/Backups/scheduled/` (copy it to the server first with `scp`)
- This restores quality profiles, root folders, download client settings, and movie library

### Sonarr
- Same restore process as Radarr — backup zips are in `sonarr/Backups/scheduled/`

### Prowlarr
- Same restore process — backup zips are in `prowlarr/Backups/scheduled/`
- After restore, trigger a manual indexer sync in Radarr and Sonarr: **Settings → Indexers → Sync App Indexers**

### SABnzbd & qBittorrent
- Ansible deploys full configs — no manual setup required
- Verify downloads land in `/data/downloads/` correctly

### Seerr
- Connect to Jellyfin, Radarr, and Sonarr through the setup wizard

### Bazarr
- Connect to Sonarr and Radarr; configure subtitle providers

### homepage
- Update `href` URLs in `homepage/services.yaml` from `home.local:PORT` to the new `*.morton.lan` subdomains

---

## Vault reference

All secrets are stored in `ansible/group_vars/media_servers/vault.yml` (encrypted).
The example file with placeholder values is at `vault.yml.example`.

| File | Purpose |
|---|---|
| `templates/env.j2` | Generates `.env` for docker-compose |
| `templates/radarr-config.xml.j2` | Seeds Radarr API key |
| `templates/sonarr-config.xml.j2` | Seeds Sonarr API key |
| `templates/prowlarr-config.xml.j2` | Seeds Prowlarr API key |
| `templates/sabnzbd.ini.j2` | Full SABnzbd config with newsgroup credentials |
| `templates/qbittorrent.conf.j2` | qBittorrent config with WebUI password hash |
