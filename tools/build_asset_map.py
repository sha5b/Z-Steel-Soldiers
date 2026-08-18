#!/usr/bin/env python3
"""Build the canonical asset map: every original asset category, where it
lives in each source (zod pack / GOG release), what the game uses, and
its wiring status. Emits docs/ASSET_MAP.md (human) and
project/assets_map.json (machine) — the reference for transforming or
re-sourcing any asset (e.g. a future GOG sprites.rsc extraction).

Run: python3 tools/build_asset_map.py
"""
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ZOD = ROOT / "assets_original" / "zod"
GOG = ROOT / "assets_original" / "gog"
WORK = ROOT / "project" / "assets" / "z"

TEAM = r"_(red|blue|green|yellow|null)"


def files_under(path: Path, exts=(".png",)) -> list:
    if not path.exists():
        return []
    return sorted(f for f in os.listdir(path)
                  if f.lower().endswith(exts) and "thumbs" not in f.lower())


def count_by_prefix(folder: Path) -> dict:
    import re
    out = {}
    for f in files_under(folder):
        stem = re.sub(TEAM + r".*", "", f[:-4])
        stem = re.sub(r"(_n\d+)?\.png$", "", stem)
        out[stem] = out.get(stem, 0) + 1
    return out


def gog_status(kind: str) -> str:
    if kind in ("sounds", "music", "ui", "hud-art", "backdrops"):
        return "GOG files in use (convert_assets.py)"
    return "packed in sprites.rsc (7211 entries, codec TBD)"


# category -> (zod folder, our usage, wiring status, notes)
MAP = [
    # --- robots (the "people") ------------------------------------------
    ("robots/stand+walk", "units/robots", "Unit2D idle/move anims", "WIRED",
     "8 directions x 4 teams; the original's only robot locomotion set"),
    ("robots/fire per type", "units/robots/<type>", "Unit2D shooting anims", "WIRED",
     "per-type weapon fire; infantry shooting IS original art"),
    ("robots/die1-5", "units/robots", "random death variant per unit", "WIRED",
     "the flying/tumbling deaths — 'people fly up' lives here (die5 is the long one)"),
    ("robots/melt", "units/robots", "extra death variant", "WIRED",
     "energy-weapon death"),
    ("robots/idle flavors", "units/robots", "idle humor (beer, cigarette, pope, ...)", "WIRED 9/12",
     "available not wired: dodge, jump-*, escape_tank, tank_fire, throw, fullAreaScan relatives"),
    ("robots/gestures", "units/robots", "point (orders), pickup-* (crates), enter_apc (manning)", "WIRED 3/6",
     "wired: point, pickup-up/down, enter_apc; available: throw, dodge"),
    ("robots/celebrate", "units/robots", "victory celebration", "WIRED", ""),
    # --- vehicles ---------------------------------------------------------
    ("vehicles/<type> empty/base/fire/wasted", "units/vehicles", "Vehicle2D anims", "WIRED",
     "incl. base_damaged below half HP; tanks fire through turret layer"),
    ("vehicles/top_* turrets", "units/vehicles", "turret layer, independent aim", "WIRED",
     "per-type turret_offset from canvas geometry; topf_* firing variant"),
    ("vehicles/top_pop", "units/vehicles", "turret blows off on death", "WIRED", ""),
    ("vehicles/under_* jeep wheels", "units/vehicles/jeep", "jeep wheel layer", "WIRED",
     "shared art, no team prefix"),
    ("vehicles/bullet.png", "units/vehicles", "tank shell projectile sprite", "WIRED", ""),
    ("vehicles death_effects", "units/vehicles/death_effects", "wreck smoke/fire overlay", "WIRED",
     "big_smoke/fire/little_fire loops on wrecks"),
    ("vehicles track marks", "units/vehicles/track_effects", "-", "NOT WIRED",
     "per-planet track decals (jeep_track_desert_...); gameplay effect"),
    ("vehicles tank_dirt/oil/sparks", "units/vehicles", "-", "NOT WIRED",
     "movement/damage ground effects"),
    # --- cannons ----------------------------------------------------------
    ("cannons/<type>", "units/cannons", "Vehicle2D (stationary)", "WIRED",
     "idle chain base->equiped->place(gunner)->fire; missiles spawn since art added"),
    # --- buildings --------------------------------------------------------
    ("buildings/<kind> base+destroyed", "buildings", "Building2D textures", "WIRED",
     "destroyed naming: base_destroyed_<planet>.png"),
    ("buildings overlays", "buildings", "radar dish, factory spinners, repair smoke", "WIRED",
     "def-driven `anims`; hidden when destroyed"),
    ("buildings fort", "buildings/fort", "fort per planet + destroyed", "WIRED", ""),
    # --- planets ----------------------------------------------------------
    ("planets tilesets+tileinfo", "planets", "terrain + navigation + water", "WIRED",
     "also drives scene-map passability"),
    ("planets rocks/bridges", "planets", "rock sprites, bridge art", "WIRED", ""),
    # --- effects ----------------------------------------------------------
    ("other/explosions", "other/explosions", "Fx explosion sprite anims", "WIRED",
     "side_explosion; tank_missile_explosion for the big one"),
    ("other/fire", "other/fire", "burning fire loops", "WIRED",
     "wreck fires"),
    ("other/particles, birds, hut_animals", "other", "-", "NOT WIRED",
     "ambient life; maps carry no animal objects in our conversion"),
    # --- HUD --------------------------------------------------------------
    ("hud unit icons", "other/hud", "selection bar portraits", "WIRED",
     "icon_<type>_<team>.png (converted from bmp)"),
    ("hud unit labels", "other/hud", "-", "COPIED, NOT WIRED",
     "unit_label_<type>_<team> name plates"),
    ("hud amount bar", "other/hud", "HP bars (selection ring)", "WIRED",
     "unit_amount_bar_<team>.png, cropped to remaining health"),
    ("hud grenade icon", "other/hud", "upgrade indicator (top bar)", "WIRED", ""),
    ("hud backdrop", "other/hud", "minimap radar frame per planet", "WIRED", ""),
    ("hud main_hud_side", "other/hud", "-", "COPIED, NOT WIRED",
     "the original's full side HUD chrome"),
    ("hud a/b/d/g buttons", "other/hud", "-", "COPIED, NOT WIRED",
     "original in-game action buttons"),
    # --- menus / production GUI -------------------------------------------
    ("menus+main_menu_gui buttons", "other/menus, other/main_menu_gui", "UiTheme button chrome", "WIRED",
     "nine-piece composed styleboxes"),
    ("production_gui", "other/production_gui", "production panel (object buttons, labels, entry bars)", "WIRED", ""),
    ("cursors", "cursors", "default in-game pointer", "PARTLY WIRED",
     "animated contextual set (attack/grenade/enter/...) available"),
    # --- audio ------------------------------------------------------------
    ("sfx", "GOG audio/*.RAW", "all weapon/explosion/UI sounds", "WIRED (GOG)",
     "115 sounds, RAW->wav 11025Hz u8"),
    ("music", "GOG *.ogg", "menu/battle loops, win/lose stingers", "WIRED (GOG)", ""),
    ("voices", "zod sounds + GOG lproj RAWs", "acknowledge + selected voices", "WIRED",
     "75 ROB barks + COMP computer voice available, not wired"),
    # --- GOG packed -------------------------------------------------------
    ("GOG sprites.rsc", "gog/en.lproj/sprites.rsc", "-", "PACKED, NOT EXTRACTED",
     "7211 sprites + offset table + per-planet PAL; codec/SHEADBI TBD; "
     "zod PNGs are the same art pre-extracted (see RESEARCH.md 2b)"),
]


def build() -> dict:
    entries = []
    for cat, folder, usage, status, notes in MAP:
        zod_path = ZOD / folder if not folder.startswith(("GOG", "zod sounds")) else None
        counts = count_by_prefix(zod_path) if zod_path and zod_path.exists() else {}
        work_dir = _work_dir_for(folder)
        parity = None
        if zod_path and zod_path.exists() and work_dir:
            parity = len(files_under(zod_path)) - len(files_under(work_dir))
        entries.append({
            "category": cat, "zod_source": folder,
            "file_count": sum(counts.values()),
            "prefixes": counts,
            "game_usage": usage, "status": status, "notes": notes,
            "parity_diff_vs_working_set": parity,
            "gog": gog_status("sounds" if folder.startswith("GOG") else "packed"),
        })
    return {"generated": "tools/build_asset_map.py", "categories": entries}


def _work_dir_for(folder: str):
    m = {
        "units/robots": WORK / "robots",
        "units/vehicles": WORK / "vehicles_jeep",  # representative
        "units/cannons": WORK / "cannons_gatling",
    }
    for k, v in m.items():
        if folder == k:
            return v
    if folder.startswith("units/robots/"):
        return WORK / ("robots_" + folder.split("/")[-1])
    if folder.startswith("units/vehicles/"):
        return WORK / ("vehicles_" + folder.split("/")[-1])
    return None


def write_docs(data: dict) -> None:
    lines = [
        "# Asset map — original sources vs game usage",
        "",
        "Generated by `tools/build_asset_map.py` (rerun after asset work).",
        "The canonical cross-reference for re-sourcing or transforming any",
        "asset — see `project/assets_map.json` for the machine-readable form.",
        "",
        "| Category | Files | Game usage | Status | Notes |",
        "|---|---|---|---|---|",
    ]
    for e in data["categories"]:
        lines.append("| %s | %d | %s | **%s** | %s |" % (
            e["category"], e["file_count"], e["game_usage"], e["status"], e["notes"]))
    (ROOT / "docs" / "ASSET_MAP.md").write_text("\n".join(lines) + "\n")
    (ROOT / "project" / "assets_map.json").write_text(json.dumps(data, indent=1))


if __name__ == "__main__":
    data = build()
    write_docs(data)
    wired = sum(1 for e in data["categories"] if e["status"] == "WIRED")
    print(f"asset map: {len(data['categories'])} categories, {wired} fully wired")
    print("-> docs/ASSET_MAP.md, project/assets_map.json")
