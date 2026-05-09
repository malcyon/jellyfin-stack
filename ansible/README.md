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

Store your vault password in a local file so you don't have to enter it on every run:

```bash
mkdir -p ~/.ansible
echo 'your-vault-password' > ~/.ansible/vault_pass
chmod 600 ~/.ansible/vault_pass
```

`ansible.cfg` in the repo root already points Ansible to this file automatically.

Then run the playbook from the repo root:

```bash
ansible-playbook -i ansible/inventory.yml ansible/playbook.yml
```

The playbook will:
1. Set up Docker and system dependencies
2. Clone the repo to the server
3. Deploy all service configs from vault
4. Start the full stack

> **Note:** After the playbook completes, log out and back in (or run `newgrp docker`) on the server before using `docker` commands directly — the group membership change requires a new session.

---

## Step 6 — Migrate data from an existing installation (optional)

If you are migrating from an existing machine rather than starting fresh, run the migration script **after** the playbook completes. It copies databases and metadata for Jellyfin, Radarr, Sonarr, Prowlarr, and Seerr — including all user accounts, passwords, watch history, libraries, quality profiles, and request history.

From the repo root on the **source** machine:

```bash
./scripts/migrate-data.sh
```

The script will:
1. Stop the relevant services on the source machine
2. Archive their data directories (excluding Ansible-managed config files)
3. Upload the archives to the media server
4. Stop, extract, and restart services on the media server

Then re-run the Ansible playbook to re-apply API keys and managed configs on top of the restored data:

```bash
ansible-playbook -i ansible/inventory.yml ansible/playbook.yml
```

**After migration — suppress the Jellyfin setup wizard:**

The migrated database has your existing users, but Jellyfin may still show the setup wizard because `system.xml` was reset. Fix it directly on the media server:

```bash
ssh media "sed -i 's/<IsStartupWizardCompleted>false<\/IsStartupWizardCompleted>/<IsStartupWizardCompleted>true<\/IsStartupWizardCompleted>/' ~/src/jellyfin-stack/jellyfin/system.xml && docker restart jellyfin"
```

**If `git pull` on the media server complains about `system.xml`:**

This happens once after the first migration because `system.xml` was previously tracked in git. Discard the tracked version and pull:

```bash
git checkout -- jellyfin/system.xml && git pull
```

If you ran the migration script, skip the Jellyfin wizard, Radarr/Sonarr/Prowlarr restore, and Seerr setup steps below — your data is already there.

---

## Step 7 — Post-deploy manual steps

These must be done through each service's web UI after the first boot.

### Pi-hole

**Cutover order matters — follow these steps in sequence.**

1. Verify Pi-hole is up by opening `http://192.168.1.182:8888/admin` — you should see the admin UI. No DNS is required for this step since you're using the IP directly.
2. In Pi-hole, enable DHCP: **Settings → DHCP** — set your router's IP as the gateway.
3. Add DNS records: `morton.lan → 192.168.1.182`, plus individual records for each subdomain (or a wildcard `*.morton.lan`).
4. Disable DHCP on the AT&T router.
5. On your laptop, disconnect and reconnect to WiFi — it should pick up a new lease from Pi-hole.
6. Validate: run `nslookup google.com` in a terminal — if the response shows `Server: 192.168.1.182`, Pi-hole is handling your DNS. The admin dashboard query counter will also start climbing as devices make requests.

> **Safety net:** If anything goes wrong, re-enable DHCP on the AT&T router and you're immediately back to normal. Disabling DHCP on the router doesn't break existing devices right away — they keep their current leases until they expire or reconnect, so you won't lose internet the moment you flip the switch.

### nginx-proxy-manager
1. Open npm at `http://192.168.1.182:81` (default login: `admin@example.com` / `changeme`)
2. Create a proxy host for each service pointing to its container name and port:

| Domain | Forward to | Notes |
|---|---|---|
| `morton.lan` | `homepage:3000` | |
| `jellyfin.morton.lan` | `jellyfin:8096` | Enable Websockets Support |
| `seerr.morton.lan` | `seerr:5055` | |
| `radarr.morton.lan` | `radarr:7878` | |
| `sonarr.morton.lan` | `sonarr:8989` | |
| `prowlarr.morton.lan` | `prowlarr:9696` | |
| `sabnzbd.morton.lan` | `sabnzbd:8080` | |
| `qbit.morton.lan` | `gluetun:8080` | qBittorrent shares gluetun's network — use `gluetun`, not `qbittorrent` |
| `pihole.morton.lan` | `192.168.1.182:8888` | Pi-hole uses host networking — use the host IP, not the container name |
| `npm.morton.lan` | `nginx-proxy-manager:81` | |
| `glance.morton.lan` | `glance:8080` | |

### Jellyfin
- **If you ran the migration script:** skip the wizard — your users, libraries, and watch history are already restored. Just verify the service loads at `jellyfin.morton.lan` and trigger a library scan if needed.
- **Fresh install:** run the setup wizard; add your media library pointing to `/data/movies`, `/data/tv`, etc. and let it scan.
- The USB drive must be plugged in and mounted at `/mnt/media` before scanning.

### Radarr
- Ansible pre-seeds the API key so homepage and Prowlarr connections work immediately
- **If you ran the migration script:** quality profiles, root folders, download client settings, and movie library are already restored — no further action needed.
- **Fresh install:** restore from backup: **Settings → Backup → Restore** — use the latest zip from `radarr/Backups/scheduled/` (copy it to the server first with `scp`)

### Sonarr
- **If you ran the migration script:** skip — data already restored.
- **Fresh install:** same restore process as Radarr — backup zips are in `sonarr/Backups/scheduled/`

### Prowlarr
- **If you ran the migration script:** skip — data already restored. Trigger a manual indexer sync in Radarr and Sonarr: **Settings → Indexers → Sync App Indexers**
- **Fresh install:** same restore process — backup zips are in `prowlarr/Backups/scheduled/`, then sync indexers as above.

### SABnzbd & qBittorrent
- Ansible deploys full configs — no manual setup required
- Verify downloads land in `/data/downloads/` correctly

### Seerr
- **If you ran the migration script:** users and request history are already restored — skip the wizard.
- **Fresh install:** connect to Jellyfin, Radarr, and Sonarr through the setup wizard.

### Bazarr
- Connect to Sonarr and Radarr; configure subtitle providers

### homepage
- Update `href` URLs in `homepage/services.yaml` from `home.local:PORT` to the new `*.morton.lan` subdomains

---

## Step 8 — Verify the stack end-to-end

Test in dependency order so each service is confirmed before testing those that depend on it.

### gluetun / qBittorrent
- Open `qbit.morton.lan` → **Settings → Advanced** → **Network Interface** should show `tun0` (VPN tunnel active)
- **Settings → Downloads** → Default Save Path should be `/data/downloads/completed`

### SABnzbd
- Open `sabnzbd.morton.lan` → **Config → Servers** → click **Test Server** — should return "Connection successful"
- **Config → General** → Completed Download Folder should be `/data/downloads/complete`

### Prowlarr
- Open `prowlarr.morton.lan` → **Indexers** — confirm indexers are present and tested
- **Settings → Apps** — Radarr and Sonarr should show green/synced

### Radarr / Sonarr
- **Settings → Download Clients** — qBittorrent and SABnzbd should be green
- **Settings → Root Folders** — `/data/movies` (Radarr) and `/data/shows` (Sonarr) should show available space
- **Movies / Series** — libraries should be populated from the migration

### Jellyfin
- Open `jellyfin.morton.lan` → **Dashboard → Libraries** — correct item counts
- Play a movie to confirm direct play works

### Seerr
- Open `seerr.morton.lan` → **Settings → Jellyfin** — server connected, libraries visible
- **Settings → Services** — Radarr and Sonarr show green; use the test button to confirm
- Make a test request — confirm it appears in Radarr or Sonarr and a download starts

### Homepage
- Open `morton.lan` — Jellyfin, Radarr, Sonarr, and Seerr widgets should all show live data

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

