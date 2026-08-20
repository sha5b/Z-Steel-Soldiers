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
    # The rest of the build-menu chrome. The panel had the title plates
    # and the object buttons but none of the WINDOW the original draws
    # them in, nor its Ok/Cancel pair or its status plates — so the
    # factory popup was our own panel wearing two original stickers.
    ("other/production_gui/base_image.png", "ui/production/"),
    ("other/production_gui/object_back.png", "ui/production/"),
    ("other/production_gui/object_name_button.png", "ui/production/"),
    ("other/production_gui/object_name_button_pressed.png", "ui/production/"),
    ("other/production_gui/ok_button.png", "ui/production/"),
    ("other/production_gui/ok_button_pressed.png", "ui/production/"),
    ("other/production_gui/cancel_button.png", "ui/production/"),
    ("other/production_gui/cancel_button_pressed.png", "ui/production/"),
    ("other/production_gui/paused_label.png", "ui/production/"),
    ("other/production_gui/buildingless_label.png", "ui/production/"),
    ("other/production_gui/down_button.png", "ui/production/"),
    ("other/production_gui/down_button_pressed.png", "ui/production/"),
    # Per-planet battle themes. The GOG release ships arctic/city/jungle
    # (AA16/aC16/aJ16); desert and volcanic only exist in the zod pack.
    ("sounds/music_desert.ogg", "music/"),
    ("sounds/music_volcanic.ogg", "music/"),
    ("sounds/music_jungle.ogg", "music/"),
]

PLANETS = ["desert", "volcanic", "arctic", "city", "jungle"]

# Numbered frame SERIES: a source glob, the destination folder and the
# destination stem. Effect folders follow the EffectPlayer contract —
# folder <name>/ holding <name>_nNN.png — so a copied series registers
# itself as an effect id with no def to write.
#
# (source glob, destination dir, destination stem or "" to keep the name)
SERIES: list[tuple[str, str, str]] = []

# Rock destruction debris, per planet and per rubble size. All five
# planets used to share ONE generic effects/debris folder while the pack
# shipped 256 planet-specific frames.
# Which rubble sizes each planet ships (desert and city have no
# `large1` — the sets are not uniform).
ROCK_DEBRIS_SIZES = {
    "desert": ["large0", "mid0", "mid1", "small"],
    "city": ["large0", "mid0", "mid1", "small"],
    "arctic": ["large0", "large1", "mid0", "mid1", "small"],
    "jungle": ["large0", "large1", "mid0", "mid1", "small"],
    "volcanic": ["large0", "large1", "mid0", "mid1", "small"],
}
for _planet in PLANETS:
    for _size in ROCK_DEBRIS_SIZES[_planet]:
        SERIES.append((
            f"planets/rock_effects/debri_{_size}_{_planet}_n*.png",
            f"effects/rock_debris_{_planet}_{_size}/",
            f"rock_debris_{_planet}_{_size}",
        ))
    # Bridge rubble is its own set (one size per planet).
    SERIES.append((
        f"planets/bridge_effects/debri_large_{_planet}_n*.png",
        f"effects/bridge_debris_{_planet}/",
        f"bridge_debris_{_planet}",
    ))

# Order-confirmation cursors: the NEUTRAL "*ed" frame sets the original
# flashes at the click point, one per order kind. Only placed_* had been
# copied (PathIndicator draws it on a move order's last waypoint).
for _order in ["attacked", "cannoned", "entered", "exited", "grabbed",
               "grenaded", "repaired"]:
    SERIES.append((f"cursors/{_order}_n*.png", "ui/cursor/", ""))

# Ambient birds: 5 frames x 2 headings x 5 planets, plus the bird CALL
# wavs that were already converted and unreferenced.
SERIES.append(("other/birds/bird_*.png", "entities/birds/", ""))

# The commander's announcement plaques (the same events the comp_*
# voices already announce).
SERIES.append(("other/comp_messages/*.png", "ui/comp/", ""))

# Unit name plates for the selected-object panel: the NEUTRAL weapon
# plate for every type (the team-coloured unit_label_* set only covers
# the six robots).
SERIES.append(("other/hud/label_*.png", "ui/hud/", ""))

# Building LEVEL digits (6x7 glyphs, levels 1-6): levels 0-5 are fully
# implemented and the player could not read them anywhere.
SERIES.append(("buildings/level_*.bmp", "ui/hud/", ""))

# Robot voice bank. ROB01-22 are already in as selected_*/acknowledge_*
# (verified by content hash); the remaining 53 lines are unlabelled, so
# they are copied as an ambient CHATTER pool and never used as a
# semantic cue — see Fx.chatter().
for _n in range(23, 76):
    SERIES.append((f"sounds/ROB{_n:02d}.wav", "sounds/", f"bark_{_n:02d}"))


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

    def take(src: Path, dst: Path) -> None:
        nonlocal copied, skipped
        if dst.is_file() and dst.stat().st_size == src.stat().st_size:
            skipped += 1
            return
        print(f"{'would copy' if args.dry_run else 'copy'}  "
              f"{src.relative_to(ZOD)} -> {dst.relative_to(ROOT)}")
        if not args.dry_run:
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
        copied += 1

    for rel_src, rel_dst in COPIES:
        src = ZOD / rel_src
        dst = DEST / rel_dst
        if rel_dst.endswith("/"):
            dst = dst / src.name
        if not src.is_file():
            print(f"MISSING SOURCE  {rel_src}")
            missing += 1
            continue
        take(src, dst)

    for glob_src, rel_dst, stem in SERIES:
        matches = sorted(ZOD.glob(glob_src))
        if not matches:
            print(f"MISSING SOURCE  {glob_src}")
            missing += 1
            continue
        for i, src in enumerate(matches):
            name = src.name
            if stem:
                # keep a trailing _nNN frame index, else number in order
                tail = src.stem.split("_n")[-1]
                if tail.isdigit() and len(matches) > 1:
                    name = f"{stem}_n{int(tail):02d}{src.suffix}"
                elif len(matches) > 1:
                    name = f"{stem}_n{i:02d}{src.suffix}"
                else:
                    name = f"{stem}{src.suffix}"
            take(src, DEST / rel_dst / name)

    print(f"copied={copied} already-current={skipped} missing-source={missing}")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
