# Music Stack Plan

Navidrome + Beets workflow for the media server.

---

## Navidrome — already deployed

Code changes are committed (see `d8c7ab3`). After running the playbook, the container is up. **Remaining manual steps:**

1. **Pi-hole** → Local DNS Records → add `navidrome.morton.lan` → `192.168.1.182`
2. **NPM** → add proxy host `navidrome.morton.lan` → `navidrome:4533`
3. **Visit** `http://navidrome.morton.lan` → create the admin account on first load
4. **Populate** `/mnt/media/music/` with music files (or wait until Beets is set up to do this properly)
5. **Trigger a scan** in Navidrome UI: Settings → Scan Library
6. **(Optional)** Generate an API token in Navidrome and add it to the homepage widget in `homepage/services.yaml`:
   ```yaml
   widget:
     type: navidrome
     url: http://navidrome:4533
     user: <your-admin-username>
     token: <token from Navidrome admin>
   ```

---

## Beets — planned

Beets handles tagging, organizing, and renaming music before it lands in Navidrome's library. It runs as a long-running idle container; you trigger imports via `docker exec`, or via a cron job in unattended mode.

### Directory layout
- `/mnt/media/music-staging/` — drop new music here (downloads, CD rips, etc.)
- `/mnt/media/music/` — Beets moves cleaned-up music here (this is what Navidrome reads)
- `./beets/` — Beets config and SQLite library database

### Files to change

#### 1. `docker-compose.yml` — add service
```yaml
beets:
  image: lscr.io/linuxserver/beets:latest
  container_name: beets
  environment:
    - PUID=${PUID}
    - PGID=${PGID}
    - TZ=${TZ}
  volumes:
    - ./beets:/config
    - /mnt/media/music:/music
    - /mnt/media/music-staging:/downloads
  restart: unless-stopped
  networks:
    - media
```

No port mapping needed — the web plugin is optional and we'd skip it.

#### 2. `ansible/roles/media-server/tasks/media.yml` — add tasks
- Create `/mnt/media/music-staging` directory (owner `donald:media`)
- Create `{{ stack_path }}/beets` config directory (owner `donald:media`)
- Deploy initial `config.yaml` with `force: false` so user edits stick

#### 3. `ansible/templates/beets-config.yaml.j2` — new file
Initial Beets config — covers the common useful settings:
```yaml
directory: /music
library: /config/library.db

import:
  copy: no
  move: yes
  write: yes
  resume: yes
  incremental: yes      # remember imported folders, skip them next run
  quiet_fallback: skip  # in -q mode, skip ambiguous matches instead of importing wrong

paths:
  default: $albumartist/$album%aunique{} ($year)/$track - $title
  singleton: Non-Album/$artist/$title
  comp: Compilations/$album%aunique{} ($year)/$track - $title

plugins:
  - fetchart       # download cover art
  - embedart       # embed cover into ID3 tags
  - lyrics         # fetch lyrics
  - replaygain     # ReplayGain normalization
  - lastgenre      # genre tagging via Last.fm
  - chroma         # acoustic fingerprinting (Chromaprint)
  - missing        # detect missing tracks
  - duplicates     # detect duplicates

replaygain:
  backend: ffmpeg
  auto: yes

embedart:
  auto: yes
```

#### 4. `homepage/services.yaml` — no entry needed
Beets has no useful UI to link to.

#### 5. `README.md` — add to active services table

### Manual post-deploy steps

1. **First import** (interactive) to confirm everything works:
   ```bash
   docker exec -it beets beet import /downloads/<some-album>
   ```
2. **(Optional)** Set up a cron job on the media server for unattended imports of high-confidence matches:
   ```cron
   0 * * * * docker exec beets beet import -q /downloads/ >> /var/log/beets-cron.log 2>&1
   ```
   Stuff that imports cleanly disappears from `/downloads/`; ambiguous matches stay there for you to review interactively later.

### Workflow once running

1. Download or rip a new album → drop the folder into `/mnt/media/music-staging/`
2. If you set up cron: well-tagged music gets auto-imported within an hour
3. Otherwise: `docker exec -it beets beet import /downloads/MyNewAlbum`
4. Navidrome picks up the new music on its next hourly scan (or trigger manually)

### Useful commands

| Command | Purpose |
|---|---|
| `beet import /downloads/Rush` | Interactive import (prompts for ambiguous matches) |
| `beet import -q /downloads/` | Quiet mode — skip anything not high-confidence |
| `beet list "artist:Rush"` | Search library |
| `beet stats` | Library statistics |
| `beet missing` | Find tracks missing from albums |
| `beet duplicates` | Find duplicate songs |
| `beet update` | Re-scan for moved/changed files |

Prefix each with `docker exec -it beets ` to run inside the container.

---

## Notes / decisions

- **Why not Lidarr:** known metadata-matching issues and frequent breakage with non-mainstream music. Beets gives manual control where it matters and full automation where it doesn't.
- **Why staging dir on `/mnt/media`:** keeps it on the same filesystem as `/mnt/media/music/` so Beets' `move: yes` is an instant rename, not a slow cross-filesystem copy.
- **Why no web UI:** Beets' web plugin is read-only library browsing — Navidrome already does that better.
