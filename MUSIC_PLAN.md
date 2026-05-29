# Music Stack Plan

Lidarr + Beets + Navidrome workflow for the media server.

---

## Architecture

```
indexers → Lidarr → /mnt/media/music → Beets (hourly tag pass) → Navidrome
```

- **Lidarr** owns discovery, downloads, file organization, and renaming. Root folder is `/data/music` (= `/mnt/media/music`). "Rename Tracks" stays ON.
- **Beets** runs as a post-processor on Lidarr's already-organized library. It does **not** move or rename files. It only enhances tags: downloads lyrics (LRCLib), embeds cover art, scrubs junk ID3 frames.
- **Navidrome** serves the result. Auto-scans hourly (`ND_SCANSCHEDULE=1h`).

The "no moves" rule is critical — if Beets moved or renamed files, Lidarr would lose track of its imports and start re-downloading them.

---

## Navidrome — deployed

See commit `d8c7ab3`. Remaining manual steps:

1. **Pi-hole** → Local DNS Records → add `navidrome.morton.lan` → `192.168.1.182`
2. **NPM** → add proxy host `navidrome.morton.lan` → `navidrome:4533`
3. **Visit** `http://navidrome.morton.lan` → create the admin account on first load
4. **(Optional)** Generate an API token in Navidrome and wire up the Homepage widget in `homepage/services.yaml`

---

## Lidarr — deployed

See the commit adding Lidarr. UI setup notes:

- **Root folder**: `/data/music`
- **Quality profile**: low-bitrate preferred (MP3-128 through 320, cutoff at MP3-160)
- **Download clients**: SABnzbd + qBittorrent, both with category `music`
- **Indexers**: synced from Prowlarr
- **Settings → Media Management → Rename Tracks**: **ON** (do not disable — Beets is post-only)

---

## Beets — deployed

Runs as a long-running idle container; the hourly cron entry triggers `beet import -A -q /music/`. With `incremental: yes` it skips already-processed albums, so cron passes are cheap once the library is settled.

### Config (`beets/config.yaml`)

Tracked in git. Lives at `./beets/config.yaml` on the host (mounted as `/config/config.yaml` in the container).

Key settings:
- `import.copy: no`, `import.move: no`, `import.write: yes` — never touch the file tree; only rewrite tags in place
- `import.incremental: yes` — skip already-imported directories
- `import.quiet_fallback: skip` — don't auto-import ambiguous matches
- Plugins: `lyrics`, `fetchart`, `embedart`, `scrub`
- `lyrics.sources: [lrclib]` — free, no API key, synced .lrc preferred

### Cron

Ansible installs an hourly cron entry under user `donald`:
```
30 * * * * docker exec beets beet import -A -q /music/ >> /home/donald/beets-cron.log 2>&1
```

### Useful commands

Prefix with `docker exec -it beets`:

| Command | Purpose |
|---|---|
| `beet import /music/<Artist>` | Interactive (prompts for ambiguous matches) |
| `beet import -A -q /music/` | Quiet — what the cron runs |
| `beet list "artist:Rush"` | Search library |
| `beet stats` | Library stats |
| `beet update` | Re-scan for moved/changed files |
| `beet missing` | Find tracks missing from albums |
| `beet duplicates` | Find duplicates |

### Adding plugins later

To enable plugins that need API credentials (e.g. `lastgenre` needs a Last.fm API key, `acousticbrainz` etc.), edit `beets/config.yaml` and run the playbook — the `Restart beets` handler will pick up the change.

---

## Notes / decisions

- **Why hybrid Lidarr + Beets:** Lidarr's library tracking, search, and quality monitoring are useful. Beets' tag matching and lyrics support are better than Lidarr's. Running Beets as a tag-only post-processor gets both without the apps fighting over the file tree.
- **Why no `paths:` block in Beets config:** we don't want Beets reorganizing files — Lidarr already does that and we'd break Lidarr's tracking.
- **Why no `replaygain`, `chroma`, `lastgenre` for now:** they add CPU cost or need API keys. Can be added later by editing the config.
- **Why no `music-staging` directory:** original plan had Beets owning the entire pipeline from a staging dir. With Lidarr now in the loop, staging is unnecessary — Lidarr writes directly to `/mnt/media/music`.
