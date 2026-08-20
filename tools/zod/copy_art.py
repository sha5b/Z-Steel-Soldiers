#!/usr/bin/env python3
"""Copy the zod-pack art and audio the game references into project/assets/z/.

Why this exists: every other converter in tools/ is reproducible, but the
5,600-odd PNGs under project/assets/z/ that came from the zod pack were
produced by an unversioned manual step. So when a NEW file is needed the
gap is invisible — the code just takes a silent `ResourceLoader.exists()`
false branch and a feature quietly does nothing. Three real bugs came
from exactly that:

  * robot_factory_label.png / vehicle_factory_label.png were never
    copied, so FactoryLabels fell back to the FORT's plate on the robot
    factory and a generic plate on the vehicle factory.
  * music_desert.ogg / music_volcanic.ogg were never copied, so two of
    the five planets had no battle theme at all.

This script is declarative and idempotent: add a row, re-run, done. It
only copies (no format conversion), so it stays cheap to audit.

    python3 tools/zod/copy_art.py [--dry-run]

Source and destination are both gitignored per-contributor trees; the
script reports anything missing on either side instead of failing.
"""

from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ZOD = ROOT / "assets_original" / "zod"
DEST = ROOT / "project" / "assets" / "z"

# (source relative to assets_original/zod, destination relative to
#  project/assets/z) — a destination ending in "/" keeps the source name.
COPIES: list[tuple[str, str]] = [
    # Producer title plates. The panel keys these by producer name, and
    # the two factory plates were the missing pieces.
    ("other/production_gui/robot_factory_label.png", "ui/production/"),
    ("other/production_gui/vehicle_factory_label.png", "ui/production/"),
    # Per-planet battle themes. The GOG release ships arctic/city/jungle
    # (AA16/aC16/aJ16); desert and volcanic only exist in the zod pack.
    ("sounds/music_desert.ogg", "music/"),
    ("sounds/music_volcanic.ogg", "music/"),
    ("sounds/music_jungle.ogg", "music/"),
]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dry-run", action="store_true",
                    help="report what would be copied and exit")
    args = ap.parse_args()

    if not ZOD.is_dir():
        print(f"zod pack not found at {ZOD} — nothing to do "
              "(it is a gitignored per-contributor copy)")
        return 0

    copied = skipped = missing = 0
    for rel_src, rel_dst in COPIES:
        src = ZOD / rel_src
        dst = DEST / rel_dst
        if rel_dst.endswith("/"):
            dst = dst / src.name
        if not src.is_file():
            print(f"MISSING SOURCE  {rel_src}")
            missing += 1
            continue
        if dst.is_file() and dst.stat().st_size == src.stat().st_size:
            skipped += 1
            continue
        print(f"{'would copy' if args.dry_run else 'copy'}  "
              f"{rel_src} -> {dst.relative_to(ROOT)}")
        if not args.dry_run:
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
        copied += 1

    print(f"copied={copied} already-current={skipped} missing-source={missing}")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
