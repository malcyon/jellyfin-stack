#!/usr/bin/env bash
# Migrate service data from this machine to the media server.
# Run from the repo root on the source machine.
#
# Usage: ./scripts/migrate-data.sh [dest_user@host] [dest_stack_path]
#
# Defaults to the production media server. Services are stopped on both ends
# during transfer to ensure a consistent snapshot.
#
# Ansible-managed files (config.xml, settings.json, Jellyfin XML configs) are
# excluded — run the Ansible playbook after migration to re-apply them.

set -euo pipefail

STACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${1:-donald@192.168.1.182}"
DEST_STACK="${2:-/home/donald/src/jellyfin-stack}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Source : $STACK_ROOT"
echo "Dest   : $DEST:$DEST_STACK"
echo

cd "$STACK_ROOT"

# ---------------------------------------------------------------------------
# Stop source services for a consistent snapshot
# ---------------------------------------------------------------------------
echo "==> Stopping source services..."
docker compose stop jellyfin radarr sonarr prowlarr seerr

# ---------------------------------------------------------------------------
# Create archives
# ---------------------------------------------------------------------------
echo "==> Creating archives..."

# Jellyfin: data/ subdir only (db + metadata + plugins).
# Top-level XML configs are in git and managed by Ansible — excluded.
tar -czf "$WORK/jellyfin.tar.gz" \
  -C "$STACK_ROOT/jellyfin" \
  data

# *arr apps: full config dir minus config.xml (Ansible deploys API keys there).
for svc in radarr sonarr prowlarr; do
  tar -czf "$WORK/${svc}.tar.gz" \
    --exclude="${svc}/config.xml" \
    -C "$STACK_ROOT" \
    "$svc"
done

# Seerr: full config dir minus settings.json (Ansible-managed).
tar -czf "$WORK/seerr.tar.gz" \
  --exclude="seerr/settings.json" \
  -C "$STACK_ROOT" \
  seerr

# ---------------------------------------------------------------------------
# Restart source services
# ---------------------------------------------------------------------------
echo "==> Restarting source services..."
docker compose start jellyfin radarr sonarr prowlarr seerr

# ---------------------------------------------------------------------------
# Upload
# ---------------------------------------------------------------------------
echo "==> Uploading archives to $DEST..."
scp "$WORK"/*.tar.gz "$DEST:/tmp/"

# ---------------------------------------------------------------------------
# Extract on media server
# ---------------------------------------------------------------------------
echo "==> Extracting on media server..."
# shellcheck disable=SC2087
ssh "$DEST" bash -s << REMOTE
set -euo pipefail

echo "Stopping destination services..."
docker compose -f $DEST_STACK/docker-compose.yml stop jellyfin radarr sonarr prowlarr seerr

echo "Extracting archives..."
# Jellyfin: restore into jellyfin/ so data/ lands at jellyfin/data/
tar -xzf /tmp/jellyfin.tar.gz  -C $DEST_STACK/jellyfin

# *arr + seerr: restore into stack root so directory names are preserved
for svc in radarr sonarr prowlarr seerr; do
  tar -xzf /tmp/\${svc}.tar.gz -C $DEST_STACK
done

rm -f /tmp/{jellyfin,radarr,sonarr,prowlarr,seerr}.tar.gz

echo "Starting destination services..."
docker compose -f $DEST_STACK/docker-compose.yml start jellyfin radarr sonarr prowlarr seerr
REMOTE

echo
echo "==> Migration complete."
echo "    Run the Ansible playbook to re-apply managed configs (API keys etc.):"
echo "    ansible-playbook -i ansible/inventory.yml ansible/playbook.yml"
