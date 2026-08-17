#!/usr/bin/env python3
"""Download sound packs listed in data/sounds_manifest.json.

Files land in assets_original/sounds/<category>/<pack>.zip and are unzipped
next to the zip. Default filter: English packs + Sound Effects (the in-game
usable set); pass "all" to grab every language.
"""
import json
import sys
import time
import urllib.request
import zipfile
from pathlib import Path

UA = "Mozilla/5.0 (X11; Linux x86_64; Firefox/128.0)"
MANIFEST = Path(__file__).parent / "data" / "sounds_manifest.json"
OUT = Path(__file__).resolve().parents[2] / "assets_original" / "sounds"


def slug(s: str) -> str:
    return "".join(c if c.isalnum() else "_" for c in s.lower()).strip("_")


def fetch(url: str, tries: int = 3) -> bytes:
    for t in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=60) as r:
                return r.read()
        except Exception as e:  # noqa: BLE001
            if t == tries - 1:
                raise
            print(f"  retry ({e})", file=sys.stderr)
            time.sleep(5 * (t + 1))


def main() -> None:
    want_all = len(sys.argv) > 1 and sys.argv[1] == "all"
    packs = json.loads(MANIFEST.read_text())
    if not want_all:
        packs = [p for p in packs if "English" in p["category"] or p["category"] == "Sound Effects"]
    print(f"downloading {len(packs)} packs", file=sys.stderr)
    for p in packs:
        dest_dir = OUT / slug(p["category"])
        dest_dir.mkdir(parents=True, exist_ok=True)
        zpath = dest_dir / f"{p['id']}_{slug(p['name'])}.zip"
        if not zpath.exists():
            zpath.write_bytes(fetch(p["zip"]))
            time.sleep(1.0)
        extract_dir = dest_dir / zpath.stem
        if not extract_dir.exists():
            extract_dir.mkdir()
            with zipfile.ZipFile(zpath) as z:
                # flatten: pack zips contain a single top-level dir
                for member in z.namelist():
                    if member.endswith("/"):
                        continue
                    target = extract_dir / "/".join(member.split("/")[1:]) or member
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(z.read(member))
        print(f"  [{p['id']}] {p['category']} / {p['name']}", file=sys.stderr)
    print("done", file=sys.stderr)


if __name__ == "__main__":
    main()
