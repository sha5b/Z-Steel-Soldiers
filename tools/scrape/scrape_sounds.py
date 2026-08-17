#!/usr/bin/env python3
"""Scrape the Sounds Resource listing for Z: Steel Soldiers.

Builds tools/scrape/data/sounds_manifest.json mapping every sound pack to its
category, asset page URL and direct zip URL. Downloading is a separate step
(download_assets.py) so the manifest can be built once and reused.
"""
import html
import json
import re
import sys
import time
import urllib.request
from pathlib import Path

LISTING_URL = "https://sounds.spriters-resource.com/pc_computer/zsteelsoldiers/"
UA = "Mozilla/5.0 (X11; Linux x86_64; Firefox/128.0)"
OUT = Path(__file__).parent / "data" / "sounds_manifest.json"


def fetch(url: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8", "replace")


def clean(txt: str) -> str:
    txt = re.sub(r"<[^>]+>", " ", txt)
    return html.unescape(re.sub(r"\s+", " ", txt)).strip()


def parse_listing(page: str) -> list[dict]:
    """Walk the listing DOM in order, tracking the current section header."""
    token = re.compile(
        r'<div class="section[^"]*"[^>]*>(.*?)</div>|'
        r'<a href="(/pc_computer/zsteelsoldiers/asset/(\d+)/)"[^>]*>(.*?)</a>',
        re.S,
    )
    packs, section = [], ""
    for m in token.finditer(page):
        if m.group(1) is not None:  # section header
            name = clean(m.group(1))
            name = re.sub(r"^\u25be\s*", "", name)
            name = re.sub(r"\[\d+\]\s*", "", name).strip()
            if name:
                section = name
        else:
            packs.append({
                "id": int(m.group(3)),
                "name": clean(m.group(4)).replace(" volume_up", ""),
                "category": section,
                "page": "https://sounds.spriters-resource.com" + m.group(2),
            })
    return packs


def parse_asset_page(page: str) -> dict:
    title = re.search(r"<title>(.*?)</title>", page, re.S)
    zip_m = re.search(r'(?:href|src)="(/media/assets/[^"]+\.zip[^"]*)"', page)
    return {
        "title": clean(title.group(1)) if title else "",
        "zip": "https://sounds.spriters-resource.com" + zip_m.group(1) if zip_m else "",
    }


def main() -> None:
    listing = fetch(LISTING_URL)
    packs = parse_listing(listing)
    print(f"{len(packs)} packs found", file=sys.stderr)
    for p in packs:
        info = parse_asset_page(fetch(p["page"]))
        p.update(info)
        print(f'  [{p["id"]}] {p["category"]} / {p["name"]}', file=sys.stderr)
        time.sleep(0.4)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(packs, indent=1))
    print(f"wrote {OUT}", file=sys.stderr)


if __name__ == "__main__":
    main()
