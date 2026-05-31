#!/usr/bin/env bash
#
# iptorrents-cookie.sh
#
# Extracts the IPTorrents session Cookie and the matching User-Agent from your
# local Firefox profile so you can paste them into Prowlarr's IPTorrents
# indexer (Settings -> Indexers -> IPTorrents: "Cookie" and "User-Agent").
#
# IPTorrents auth is a session cookie tied to the browser User-Agent that
# created it. Both must match, so this prints them together. When the cookie
# eventually expires, log into iptorrents.com in Firefox again and re-run this.
#
# Usage:
#   ./iptorrents-cookie.sh            # auto-detect Firefox profile
#   ./iptorrents-cookie.sh -d DOMAIN  # use a different tracker host
#   ./iptorrents-cookie.sh -p PATH    # point at a specific cookies.sqlite
#
# Requires: python3 (ships with Pop!_OS). No apt install needed.

set -euo pipefail

DOMAIN="iptorrents.com"
COOKIES_DB=""

usage() {
  grep '^#' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}

while getopts ":d:p:h" opt; do
  case "$opt" in
    d) DOMAIN="$OPTARG" ;;
    p) COOKIES_DB="$OPTARG" ;;
    h) usage 0 ;;
    *) echo "Unknown option: -$OPTARG" >&2; usage 1 ;;
  esac
done

err() { echo "ERROR: $*" >&2; exit 1; }

command -v python3 >/dev/null 2>&1 || err "python3 not found (try: sudo apt install python3)"

# --- Locate Firefox profile root across install methods -----------------------
# Pop!_OS ships Firefox as a .deb, but handle Snap and Flatpak too.
FF_ROOTS=(
  "$HOME/.mozilla/firefox"
  "$HOME/snap/firefox/common/.mozilla/firefox"
  "$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox"
)

# --- Find the cookies.sqlite that actually has cookies for $DOMAIN -------------
find_cookies_db() {
  # If the user passed one explicitly, trust it.
  if [[ -n "$COOKIES_DB" ]]; then
    [[ -f "$COOKIES_DB" ]] || err "no such file: $COOKIES_DB"
    echo "$COOKIES_DB"
    return
  fi

  local found=()
  local root db
  for root in "${FF_ROOTS[@]}"; do
    [[ -d "$root" ]] || continue
    while IFS= read -r db; do
      found+=("$db")
    done < <(find "$root" -maxdepth 2 -name cookies.sqlite 2>/dev/null)
  done

  [[ ${#found[@]} -gt 0 ]] || err "no Firefox cookies.sqlite found under: ${FF_ROOTS[*]}"

  # Prefer a DB that contains cookies for the target domain.
  for db in "${found[@]}"; do
    if cookie_count "$db" >/dev/null 2>&1 && [[ "$(cookie_count "$db")" -gt 0 ]]; then
      echo "$db"
      return
    fi
  done

  # None matched -> report so the user knows to log in first.
  err "found ${#found[@]} Firefox profile(s) but none has cookies for '$DOMAIN'. Log into https://$DOMAIN in Firefox, then re-run."
}

# Count cookies for $DOMAIN in a given DB (reads a copy to dodge the lock Firefox
# holds while running).
cookie_count() {
  local db="$1"
  python3 - "$db" "$DOMAIN" <<'PY'
import sqlite3, sys, tempfile, shutil, os
db, domain = sys.argv[1], sys.argv[2]
tmp = tempfile.NamedTemporaryFile(suffix=".sqlite", delete=False).name
try:
    shutil.copy2(db, tmp)
    con = sqlite3.connect(f"file:{tmp}?immutable=1", uri=True)
    n = con.execute(
        "SELECT COUNT(*) FROM moz_cookies WHERE host LIKE ? OR host LIKE ?",
        (f"%{domain}", f"%.{domain}"),
    ).fetchone()[0]
    print(n)
finally:
    os.unlink(tmp)
PY
}

# Build the "name=value; name=value" Cookie header for $DOMAIN.
cookie_header() {
  local db="$1"
  python3 - "$db" "$DOMAIN" <<'PY'
import sqlite3, sys, tempfile, shutil, os
db, domain = sys.argv[1], sys.argv[2]
tmp = tempfile.NamedTemporaryFile(suffix=".sqlite", delete=False).name
try:
    shutil.copy2(db, tmp)
    con = sqlite3.connect(f"file:{tmp}?immutable=1", uri=True)
    rows = con.execute(
        "SELECT name, value FROM moz_cookies WHERE host LIKE ? OR host LIKE ? ORDER BY name",
        (f"%{domain}", f"%.{domain}"),
    ).fetchall()
    print("; ".join(f"{n}={v}" for n, v in rows))
finally:
    os.unlink(tmp)
PY
}

# --- Derive the Firefox User-Agent --------------------------------------------
# 1) Honor general.useragent.override if the user set one (prefs.js / user.js).
# 2) Otherwise reconstruct the default desktop UA from the installed version.
#    Firefox reports rv: and Firefox/ as <major>.0 regardless of point release.
user_agent() {
  local profile_dir="$1"
  local override
  override="$(
    grep -hoP 'user_pref\("general\.useragent\.override",\s*"\K[^"]+' \
      "$profile_dir/prefs.js" "$profile_dir/user.js" 2>/dev/null | tail -n1
  )"
  if [[ -n "$override" ]]; then
    echo "$override"
    return
  fi

  local ver=""
  if command -v firefox >/dev/null 2>&1; then
    ver="$(firefox --version 2>/dev/null | grep -oP '[0-9]+(\.[0-9]+)+' | head -n1 || true)"
  fi
  if [[ -z "$ver" && -f "$profile_dir/compatibility.ini" ]]; then
    ver="$(grep -oP '^LastVersion=\K[0-9]+(\.[0-9]+)+' "$profile_dir/compatibility.ini" | head -n1 || true)"
  fi
  [[ -n "$ver" ]] || err "could not determine Firefox version for the User-Agent"

  local major="${ver%%.*}"
  echo "Mozilla/5.0 (X11; Linux x86_64; rv:${major}.0) Gecko/20100101 Firefox/${major}.0"
}

# --- Run ----------------------------------------------------------------------
DB="$(find_cookies_db)"
PROFILE_DIR="$(dirname "$DB")"

COOKIE="$(cookie_header "$DB")"
[[ -n "$COOKIE" ]] || err "no cookies for '$DOMAIN' in $DB (log in via Firefox first)"
UA="$(user_agent "$PROFILE_DIR")"

echo "Firefox profile : $PROFILE_DIR"
echo "Tracker domain  : $DOMAIN"
echo
echo "Paste these into Prowlarr -> IPTorrents indexer:"
echo
echo "Cookie:"
echo "  $COOKIE"
echo
echo "User-Agent:"
echo "  $UA"
