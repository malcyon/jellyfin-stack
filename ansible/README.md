# Media Server Ansible Playbook

Automates the setup of a Jellyfin media server.


## Prerequisites

Install Ansible on your local machine:

```bash
sudo apt install ansible
```

`ansible.posix` is included with the Ubuntu ansible package — no separate install needed.

---

## Step 1 — Set up GitHub SSH access on the media server

The repo is private, so the media server needs its own SSH key authorized on GitHub.

SSH into the media server and generate a key:

```bash
ssh media
ssh-keygen -t ed25519 -C "media server"
cat ~/.ssh/id_ed25519.pub
```

Copy the output and add it to your GitHub profile: **Settings → SSH and GPG keys → New SSH key**.

Then accept GitHub's host key (required before Ansible runs, otherwise the git clone task will hang):

```bash
ssh -T git@github.com
```

Type `yes` when prompted. You should see `Hi malcyon! You've successfully authenticated...`

---

## Step 2 — Configure the inventory


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

## Step 3 — Review vars

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

## Step 4 — Create and encrypt the vault

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
| `vault_seerr_client_id` | `clientId` from `seerr/settings.json` |
| `vault_seerr_session_secret` | `sessionSecret` from `seerr/settings.json` |
| `vault_seerr_vapid_private` | `vapidPrivate` from `seerr/settings.json` |
| `vault_seerr_vapid_public` | `vapidPublic` from `seerr/settings.json` |
| `vault_seerr_jellyfin_api_key` | `jellyfin.apiKey` from `seerr/settings.json` (distinct from `vault_jellyfin_api_key`) |
| `vault_pihole_webpassword` | Choose a password for the Pi-hole web UI |

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

## Step 5 — Run the playbook

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

## Step 6 — Post-deploy manual steps

These must be done through each service's web UI after the first boot.

### Pi-hole

**Cutover order matters — follow these steps in sequence.**

1. Verify Pi-hole is up by opening `http://192.168.1.182:8888` — you should see the admin UI. No DNS is required for this step since you're using the IP directly.
2. In Pi-hole, enable DHCP: **Settings → DHCP** — set your router's IP as the gateway.
3. Add DNS records: `morton.lan → 192.168.1.182`, plus individual records for each subdomain (or a wildcard `*.morton.lan`).
4. Disable DHCP on the AT&T router.
5. On your laptop, disconnect and reconnect to WiFi — it should pick up a new lease from Pi-hole.
6. Validate: run `nslookup google.com` in a terminal — if the response shows `Server: 192.168.1.182`, Pi-hole is handling your DNS. The admin dashboard query counter will also start climbing as devices make requests.

> **Safety net:** If anything goes wrong, re-enable DHCP on the AT&T router and you're immediately back to normal. Disabling DHCP on the router doesn't break existing devices right away — they keep their current leases until they expire or reconnect, so you won't lose internet the moment you flip the switch.

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
