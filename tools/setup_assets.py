#!/usr/bin/env python3
"""One command to turn your copy of Z into a playable project.

    python3 tools/setup_assets.py

That is the whole thing, once the two source sets are in place. It finds
what you have, extracts the retail data if it is still packed, runs every
converter in dependency order, and verifies the result. Run it again any
time — each step is idempotent.

WHAT IT NEEDS

  assets_original/gog/   the retail game data: BUILD01.DAT, LEVEL01.MAP,
                         ARCTIC.PAL, audio/, PNG/, Maps/ ...
  assets_original/zod/   the Zod Engine asset pack: units/, buildings/,
                         planets/, teams/, sounds/, fonts/ ...

Neither ships here. They are The Bitmap Brothers' work, they are
gitignored, and every contributor supplies their own copy. `--where`
prints exactly what is missing and where it comes from.

If you have the GOG installer instead of an extracted directory, drop it
in the repository root as `setup_z*.exe` and this script unpacks it for
you (it uses innoextract when available, otherwise 7z).

WHAT IT DOES NOT DO

It never downloads game art. You point it at files you already own.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GOG = ROOT / "assets_original" / "gog"
ZOD = ROOT / "assets_original" / "zod"
OUT = ROOT / "project" / "assets"

# A few files that prove a source set is really there, rather than an
# empty directory somebody created by hand.
GOG_MARKERS = ["LEVEL01.MAP", "BUILD01.DAT", "PNG", "audio"]
ZOD_MARKERS = ["units", "buildings", "planets", "teams", "sounds"]

WHERE = """
  assets_original/gog/   The RETAIL game data. Buy Z on GOG, install it,
                         and copy the game directory's contents here. Or
                         drop the installer in the repository root as
                         setup_z*.exe and run this script again.
                         Expected inside: LEVEL01.MAP, BUILD01.DAT,
                         ARCTIC.PAL, audio/, PNG/, Maps/

  assets_original/zod/   The ZOD ENGINE asset pack, which carries the
                         unit and map sprites the retail release keeps
                         engine-packed. Get it from the Zod Engine
                         project (zod.sourceforge.net, or the
                         capehill/zodengine mirror) and copy its data
                         directory here.
                         Expected inside: units/, buildings/, planets/,
                         teams/, sounds/, fonts/
"""


# ---------------------------------------------------------------- steps

# (label, script, argv, what it produces, which source set it needs)
STEPS = [
    ("terrain tables", "tools/zod/tileinfo_to_json.py", [],
     "assets/tilesets/tileinfo_<planet>.json", "zod"),
    ("unit and map art", "tools/zod/copy_art.py", [],
     "assets/z/<units, buildings, effects, ...>", "zod"),
    ("HUD frame and portraits", "tools/zod/build_hud.py", [],
     "assets/z/ui/hud/", "zod"),
    ("fonts", "tools/zod/pack_fonts.py", [],
     "assets/z/ui/font/", "zod"),
    ("sound, music and menu art", "tools/gog/convert_assets.py", [],
     "assets/z/{sounds,music,ui}/", "gog"),
    # argv[3] is the directory holding the RAW `<planet>.tileinfo`
    # binaries, not the JSON the step above wrote. Point it at the JSON
    # and every level converts with `passable` and `water` set to null,
    # which `--retail-test` then trips over.
    ("the retail 20-level campaign", "tools/gog/level_to_json.py",
     ["ASSETS_GOG", "OUT_MAPS", "ZOD_PLANETS"],
     "assets/maps/zc01..zc20 + zs26..zs31", "gog"),
    ("planet tags", "tools/zod/verify_map_planets.py", ["--fix"],
     "repairs the planet field on every map", "zod"),
    ("asset map", "tools/build_asset_map.py", [],
     "project/assets_map.json", None),
    ("window and desktop icons", "tools/gog/make_icons.py", [],
     "assets/icon/", "gog"),
]

# Godot rebuilds the editable map scenes from the JSON. Last, because it
# reads everything the steps above wrote.
GODOT_STEP = ("map scenes", "res://tools/build_map_resources.tscn",
              "assets/maps_scenes/*.tscn")


def have(source_dir: Path, markers: list[str]) -> bool:
    return source_dir.is_dir() and any((source_dir / m).exists() for m in markers)


PLACEHOLDERS = {
    "ASSETS_GOG": lambda: str(GOG),
    "ASSETS_ZOD": lambda: str(ZOD),
    "OUT_MAPS": lambda: str(OUT / "maps"),
    "OUT_TILESETS": lambda: str(OUT / "tilesets"),
    "ZOD_PLANETS": lambda: str(ZOD / "planets"),
}


def resolve(argv: list[str]) -> list[str]:
    """Turn the step table's path placeholders into real paths."""
    return [PLACEHOLDERS[a]() if a in PLACEHOLDERS else a for a in argv]


def run(cmd: list[str], label: str, cwd: Path = ROOT) -> bool:
    started = time.monotonic()
    print(f"  {label} ... ", end="", flush=True)
    done = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    took = time.monotonic() - started
    if done.returncode != 0:
        print(f"FAILED ({took:.0f}s)")
        tail = (done.stderr or done.stdout or "").strip().splitlines()[-12:]
        for line in tail:
            print(f"      {line}")
        return False
    print(f"ok ({took:.0f}s)")
    return True


def unpack_installer() -> bool:
    """Unpack a GOG installer sitting in the repository root."""
    found = sorted(ROOT.glob("setup_z*.exe")) + sorted(ROOT.glob("setup_Z*.exe"))
    if not found:
        return False
    installer = found[0]
    GOG.mkdir(parents=True, exist_ok=True)
    print(f"\nUnpacking {installer.name}")
    if shutil.which("innoextract"):
        cmd = ["innoextract", "-e", "-s", "-d", str(GOG), str(installer)]
    elif shutil.which("7z"):
        cmd = ["7z", "x", "-y", f"-o{GOG}", str(installer)]
    else:
        print("  no innoextract and no 7z — install one, or extract by hand")
        return False
    if not run(cmd, installer.name):
        return False
    # installers bury the data a level or two down; lift it up
    for name in GOG_MARKERS:
        if (GOG / name).exists():
            return True
    for candidate in sorted(GOG.rglob("LEVEL01.MAP")):
        src = candidate.parent
        print(f"  lifting game data out of {src.relative_to(GOG)}")
        for item in src.iterdir():
            target = GOG / item.name
            if not target.exists():
                shutil.move(str(item), str(target))
        return True
    return False


def godot_binary() -> list[str] | None:
    for exe in ("godot4", "godot"):
        if shutil.which(exe):
            return [exe]
    if shutil.which("flatpak"):
        probe = subprocess.run(
            ["flatpak", "info", "org.godotengine.Godot"],
            capture_output=True, text=True)
        if probe.returncode == 0:
            return ["flatpak", "run", "org.godotengine.Godot"]
    return None


# ----------------------------------------------------------------- main

def main() -> int:
    ap = argparse.ArgumentParser(
        description="Convert your copy of Z into a playable Godot project.")
    ap.add_argument("--where", action="store_true",
                    help="say what is missing and where it comes from, then stop")
    ap.add_argument("--skip-scenes", action="store_true",
                    help="skip the Godot pass that rebuilds the map scenes")
    ap.add_argument("--only", metavar="TEXT",
                    help="run only the steps whose label contains TEXT")
    args = ap.parse_args()

    if not have(GOG, GOG_MARKERS):
        unpack_installer()

    got_gog = have(GOG, GOG_MARKERS)
    got_zod = have(ZOD, ZOD_MARKERS)

    print("Sources")
    print(f"  assets_original/gog   {'found' if got_gog else 'MISSING'}")
    print(f"  assets_original/zod   {'found' if got_zod else 'MISSING'}")

    if args.where or not (got_gog and got_zod):
        print(WHERE)
        if not (got_gog and got_zod):
            print("Nothing was converted. Supply the missing set and run again.")
            return 1
        return 0

    steps = [s for s in STEPS
             if s[4] is None
             or (s[4] == "gog" and got_gog)
             or (s[4] == "zod" and got_zod)]
    if args.only:
        steps = [s for s in steps if args.only.lower() in s[0].lower()]

    print(f"\nConverting ({len(steps)} steps)")
    failed = []
    for label, script, extra, _produces, _needs in steps:
        if not run([sys.executable, script, *resolve(extra)], label):
            failed.append(label)

    # The zod .map converter takes ONE file at a time, and the asset pack
    # ships no .map sources (the 57 zod maps in the repository were
    # converted once, from a separate map set). Loop it only for somebody
    # who does have them.
    zod_maps = sorted(ZOD.rglob("*.map"))
    if zod_maps and not args.only:
        print(f"  zod maps ({len(zod_maps)} found)")
        for src in zod_maps:
            dst = OUT / "maps" / (src.stem + ".json")
            if not run([sys.executable, "tools/zod/map_to_json.py", str(src),
                        str(dst), str(OUT / "tilesets")], f"    {src.name}"):
                failed.append(f"zod map {src.name}")

    if not args.skip_scenes and not failed:
        label, scene, _produces = GODOT_STEP
        godot = godot_binary()
        if godot is None:
            print(f"  {label} ... skipped (no Godot on PATH and no flatpak)")
        else:
            run([*godot, "--headless", "--path", "project", scene], label)

    print()
    if failed:
        print(f"{len(failed)} step(s) failed: {', '.join(failed)}")
        return 1

    maps = len(list((OUT / "maps").glob("*.json"))) if (OUT / "maps").is_dir() else 0
    art = sum(1 for _ in (OUT / "z").rglob("*.png")) if (OUT / "z").is_dir() else 0
    print(f"Ready. {art} art files, {maps} maps.")
    print("Play it:  flatpak run org.godotengine.Godot   (open project/, press F5)")
    print("Check it: godot --headless --path project"
          " res://scenes/main.tscn --art-test --quit-after 6000")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
