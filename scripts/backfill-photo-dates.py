#!/usr/bin/env python3
"""Backfill DateTimeOriginal on photos that lack it, deriving the date from the
folder structure (year/decade/dated-subfolder). Intended for a library that is
organised by date in folders but whose files have no embedded date-taken — so
Immich (and anything else that sorts by EXIF) places them on the right part of
the timeline instead of by meaningless file modification time.

Usage:
    backfill-photo-dates.py <library-dir>            # dry run: report only
    backfill-photo-dates.py <library-dir> --apply    # write the dates

Behaviour:
  * Files that already have DateTimeOriginal are left untouched.
  * Date is taken from the most specific thing in the path:
        YYYY-MM-DD subfolder  -> that exact day
        YYYY folder           -> YYYY-01-01
        1970s / ..._earlier   -> mid-decade (1975) / 1950-01-01
  * SKIP_TOP folders (no year in their name) are skipped.
  * Only real, writable image formats are touched (WRITABLE); BMP and
    unidentifiable/text-misidentified files are skipped and reported.
  * --apply runs exiftool with -overwrite_original. Always take a backup first
    (a snapshot outside any sync path, or rely on cloud version history).

Requires: exiftool on PATH.
"""
import json, re, subprocess, sys, csv, collections, os, tempfile

# Top-level folders with no derivable year — left dateless on purpose.
SKIP_TOP = {"Dad's Pics", "Morton Farm"}
# Formats exiftool can safely write a date into.
WRITABLE = {"JPEG", "PNG", "TIFF", "HEIC", "HEIF"}
# Path segment that marks the boundary above which folder names are irrelevant
# for date derivation (so we don't match a year in some parent path).
ANCHOR = "Family Pics/"

re_ymd  = re.compile(r"(19|20)\d\d-\d\d-\d\d")
re_dec  = re.compile(r"(19[5-9]0|20[0-2]0)s")
re_year = re.compile(r"(?<!\d)(19[5-9]\d|20[0-2]\d)(?!\d)")


def derive(rel):
    m = re_ymd.search(rel)
    if m:
        return "exact", m.group(0).replace("-", ":")
    m = re_dec.search(rel)
    if m:
        return "decade", str(int(m.group(1)) + 5) + ":01:01"
    m = re_year.search(rel)
    if m:
        return "year", m.group(0) + ":01:01"
    if "earlier" in rel.lower():
        return "decade", "1950:01:01"
    return "none", None


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    base = sys.argv[1]
    apply = "--apply" in sys.argv[2:]

    out = subprocess.run(
        ["exiftool", "-r", "-j", "-q", "-DateTimeOriginal", "-SourceFile", "-FileType",
         "-ext", "jpg", "-ext", "jpeg", "-ext", "png", "-ext", "heic",
         "-ext", "bmp", "-ext", "tif", "-ext", "tiff", base],
        capture_output=True, text=True)
    data = json.loads(out.stdout) if out.stdout.strip() else []

    cats, types, skipped = collections.Counter(), collections.Counter(), collections.Counter()
    rows = []
    for it in data:
        if it.get("DateTimeOriginal"):
            continue
        src = it["SourceFile"]
        rel = src.split(ANCHOR, 1)[-1]
        top = rel.split("/")[0]
        cat, date = derive(rel)
        if cat == "none" or top in SKIP_TOP:
            skipped["undated folder / underivable"] += 1
            continue
        ftype = it.get("FileType") or "unidentified"
        if ftype not in WRITABLE:
            skipped[f"non-writable type: {ftype}"] += 1
            continue
        stamp = f"{date} 00:00:00"
        rows.append({"SourceFile": src, "DateTimeOriginal": stamp, "CreateDate": stamp})
        cats[cat] += 1
        types[ftype] += 1

    print(f"date-derivable, dateless, writable images: {len(rows)}")
    print("  by category:", dict(cats))
    print("  by file type:", dict(types))
    print("  skipped:", dict(skipped))

    if not rows:
        return
    fd, csv_path = tempfile.mkstemp(prefix="photo-dates-", suffix=".csv")
    with os.fdopen(fd, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["SourceFile", "DateTimeOriginal", "CreateDate"])
        w.writeheader()
        w.writerows(rows)

    if not apply:
        print(f"\nDRY RUN — nothing written. CSV of intended dates: {csv_path}")
        print("Re-run with --apply to write them (take a backup first).")
        return

    print(f"\nAPPLYING dates to {len(rows)} files via exiftool ...")
    r = subprocess.run(
        ["exiftool", "-overwrite_original", "-r", f"-csv={csv_path}", base],
        capture_output=True, text=True)
    print(r.stderr.strip().splitlines()[-1] if r.stderr.strip() else r.stdout.strip())
    os.unlink(csv_path)


if __name__ == "__main__":
    main()
