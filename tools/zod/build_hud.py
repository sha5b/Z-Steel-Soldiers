#!/usr/bin/env python3
"""Build the original in-game HUD art set from the zod pack.

Two jobs, both of which `copy_art.py` cannot do because they need real
conversion rather than a copy:

1. **The main HUD chrome pieces.** The frame itself (`main_hud_side_*`,
   `main_hud_bottom*`) was already in the tree, but everything that goes
   INSIDE it was not: the lettered buttons (A on the sidebar, T/D/Z under
   the weapon panel, R/V/B/G and Menu on the bottom bar), the 74px health
   bar strips, the grenade plate, the 88x63 equipment art, and the two
   filler tiles the frame uses when the window is taller/wider than the
   original 648x484.

2. **The animated head portraits** (`SHEADBI{0-4}`, 24 folders of 40
   pieces). The original does not ship whole faces — it ships one base
   head plus cut-out EYE and MOUTH pieces that the engine composites at
   fixed offsets. The offsets live in the engine, not in the pack, so we
   recover them here by brute force (the same trick that cracked the
   rock stamps in docs/RESEARCH.md 6.6b): slide each piece over the base
   head and keep the position with the lowest mean error over pixels both
   images draw. Every piece in a size group agrees on one offset, which
   is what makes the result trustworthy — see the score line this prints.

   Whole frames are then BAKED, so the runtime just plays a flipbook and
   never has to know a piece offset:

       ui/portraits/<type>_<team>/base.png       neutral face
                                 hurt.png        the second head (low HP)
                                 blink_nNN.png   eye cycle,   11 frames
                                 talk_nNN.png    mouth cycle, 16 frames

Not converted: the 64x64 and 48x64 gesture pieces (5+2 per folder). They
are BIGGER than the base head, so the match above has nothing to lock
onto and their placement stays unknown.

    python3 tools/zod/build_hud.py [--dry-run] [--force]

Source and destination are both gitignored per-contributor trees; the
script reports anything missing instead of failing.
"""

from __future__ import annotations

import argparse
import collections
import glob
import sys
from pathlib import Path

try:
    import numpy as np
    from PIL import Image
except ImportError:  # pragma: no cover - operator feedback only
    print("needs Pillow and numpy:  pip install pillow numpy")
    raise SystemExit(2)

ROOT = Path(__file__).resolve().parents[2]
HUD = ROOT / "assets_original" / "zod" / "other" / "hud"
DEST = ROOT / "project" / "assets" / "z" / "ui"

# Lettered button plates, 24x20 each (Menu is 56x20). The sidebar carries
# A / T / D / Z, the bottom bar R / V / B / G / Menu.
BUTTONS = ["a", "t", "d", "z", "r", "v", "b", "g", "menu"]
BUTTON_STATES = ["active", "inactive", "pressed"]

# Straight conversions into ui/hud/. BMP has no alpha and every one of
# these is an opaque plate, so there is nothing to key out.
PLATES = [
    ("side_filler.bmp", "side_filler.png"),
    ("bottom_filler.bmp", "bottom_filler.png"),
    ("grenade.bmp", "grenade.png"),
    ("health_full.png", "health_full.png"),
    ("health_empty.png", "health_empty.png"),
    ("health_lost.png", "health_lost.png"),
]

# The 88x63 equipment art the sidebar shows under the name plate: a
# grunt's rifle, a tough's missile tube, the hull of each vehicle. Named
# `weapon_*` in the tree because `icon_<type>_<team>` is already taken by
# the small production icons.
WEAPON_TYPES = [
    "grunt", "psycho", "sniper", "tough", "pyro", "laser",
    "jeep", "light", "medium", "heavy", "apc", "crane", "firetruck",
    "missile_launcher", "gatling", "gun", "howitzer", "missile_cannon",
]

# Portrait piece groups, by piece SIZE. Every one of the 24 folders has
# the same signature: 3 base heads, 16 mouths, 11 eye bands.
MOUTH_SIZE = (32, 32)
EYES_SIZE = (48, 16)
BASE_MIN_AREA = 4000  # the 80x6x heads; everything else is a cut-out

# A pixel this dark in a cut-out is the key colour, not art.
KEY_LEVEL = 6


def load_rgb(path: Path) -> Image.Image:
    return Image.open(path).convert("RGB")


def opaque_mask(im: Image.Image) -> "np.ndarray":
    a = np.asarray(im).astype(int)
    return a.sum(axis=2) > KEY_LEVEL * 3


def group_offset(base: Image.Image, pieces: list[Path]) -> tuple[int, int, float]:
    """The ONE offset a whole size group is drawn at, and how sharply it
    wins.

    Scored jointly rather than by per-piece vote: a single cut-out can be
    mostly key colour (a wide-open mouth barely overlaps the closed mouth
    the base head draws), so its own best position is noisy. Summing the
    error of every member of the group over the SAME candidate offset
    puts all the evidence behind one decision.

    Returns (x, y, margin) where margin is runner-up / winner error — how
    much worse the next distinct position is. Anything near 1.0 means the
    lock is not real.
    """
    b = np.asarray(base).astype(int)
    b_drawn = b.sum(axis=2) > KEY_LEVEL * 3
    loaded = [(np.asarray(load_rgb(p)).astype(int), opaque_mask(load_rgb(p)))
              for p in pieces]
    ph, pw = loaded[0][0].shape[0], loaded[0][0].shape[1]
    totals: dict[tuple[int, int], float] = {}
    for y in range(0, b.shape[0] - ph + 1):
        for x in range(0, b.shape[1] - pw + 1):
            win = b[y:y + ph, x:x + pw]
            drawn = b_drawn[y:y + ph, x:x + pw]
            total = 0.0
            ok = True
            for p, pm in loaded:
                both = pm & drawn
                if both.sum() < pm.sum() * 0.3:
                    ok = False
                    break
                total += float(np.abs(win - p).sum(axis=2)[both].mean())
            if ok:
                totals[(x, y)] = total
    if not totals:
        return 0, 0, 1.0
    ranked = sorted(totals.items(), key=lambda kv: kv[1])
    (x, y), best = ranked[0]
    runner_up = next((v for k, v in ranked[1:]
                      if abs(k[0] - x) > 1 or abs(k[1] - y) > 1), best)
    return x, y, (runner_up / best if best > 0 else 1.0)


def composite(base: Image.Image, overlays: list[tuple[Image.Image, tuple[int, int]]]) -> Image.Image:
    out = base.copy()
    for piece, (x, y) in overlays:
        mask = piece.convert("L").point(lambda v: 255 if v > KEY_LEVEL else 0)
        out.paste(piece, (x, y), mask)
    return out


def neutral_index(base: Image.Image, pieces: list[Path], at: tuple[int, int]) -> int:
    """Which member of a group is the RESTING one: the piece that differs
    least from what the base head already draws there (the base is drawn
    mouth-closed, eyes-open)."""
    b = np.asarray(base).astype(int)
    best = (float("inf"), 0)
    for i, path in enumerate(pieces):
        p = np.asarray(load_rgb(path)).astype(int)
        x, y = at
        win = b[y:y + p.shape[0], x:x + p.shape[1]]
        m = opaque_mask(load_rgb(path)) & (win.sum(axis=2) > KEY_LEVEL * 3)
        if m.sum() == 0:
            continue
        score = float(np.abs(win - p).sum(axis=2)[m].mean())
        if score < best[0]:
            best = (score, i)
    return best[1]


def portrait_pieces(folder: Path) -> tuple[list[Path], list[Path], list[Path]]:
    """(head candidates, mouth cut-outs, eye cut-outs) for one folder."""
    by_size: dict[tuple[int, int], list[Path]] = collections.defaultdict(list)
    for f in sorted(folder.glob("*.png")):
        with Image.open(f) as im:
            by_size[im.size].append(f)
    heads = [f for size, fs in by_size.items()
             if size[0] * size[1] >= BASE_MIN_AREA and size[0] >= 80
             for f in fs]
    return sorted(heads), sorted(by_size.get(MOUTH_SIZE, [])), \
        sorted(by_size.get(EYES_SIZE, []))


def bake_portraits(dry_run: bool, force: bool) -> tuple[int, int]:
    written = folders = 0
    src_root = HUD / "portraits"
    if not src_root.is_dir():
        print(f"MISSING SOURCE  {src_root}")
        return 0, 1
    # Team folders of one unit type hold the SAME head recoloured, so the
    # base-frame decision belongs to the type, not the folder. Deciding
    # per folder let two teams of one robot pick different crops of the
    # same face (the pack ships it twice, 16px apart, which scores almost
    # equally) and their portraits then sat at different offsets in the
    # window.
    by_type: dict[str, list[Path]] = collections.defaultdict(list)
    for folder in sorted(p for p in src_root.iterdir() if p.is_dir()):
        by_type[folder.name.rsplit("_", 1)[0]].append(folder)

    for type_name, team_folders in by_type.items():
        # score every head candidate across ALL of the type's teams
        scores: dict[str, float] = collections.defaultdict(float)
        for folder in team_folders:
            heads, mouths, eyes = portrait_pieces(folder)
            if not heads or not mouths or not eyes:
                continue
            for cand in heads:
                image = load_rgb(cand)
                _, _, m_margin = group_offset(image, mouths)
                _, _, e_margin = group_offset(image, eyes)
                scores[cand.name] += m_margin * e_margin
        if not scores:
            print(f"SKIP {type_name}: unexpected piece set")
            continue
        order = sorted(scores.items(), key=lambda kv: -kv[1])
        base_name, alt_name = order[0][0], (order[1][0] if len(order) > 1 else "")
        print(f"{type_name:8s} base={base_name} alt={alt_name or '-'} "
              f"(margins {', '.join(f'{n}:{v:.2f}' for n, v in order)})")

        for folder in team_folders:
            heads, mouths, eyes = portrait_pieces(folder)
            head_path = next((h for h in heads if h.name == base_name), None)
            if head_path is None or not mouths or not eyes:
                print(f"SKIP {folder.name}: no {base_name}")
                continue
            base = load_rgb(head_path)
            alt_path = next((h for h in heads if h.name == alt_name), None)
            alt = load_rgb(alt_path) if alt_path else None
            mx, my, m_margin = group_offset(base, mouths)
            ex, ey, e_margin = group_offset(base, eyes)
            n_mouth = neutral_index(base, mouths, (mx, my))
            n_eyes = neutral_index(base, eyes, (ex, ey))
            print(f"  {folder.name:14s} mouth@({mx},{my}) x{m_margin:.2f}  "
                  f"eyes@({ex},{ey}) x{e_margin:.2f}  "
                  f"rest=mouth{n_mouth}/eyes{n_eyes}")
            rest_mouth = (load_rgb(mouths[n_mouth]), (mx, my))
            rest_eyes = (load_rgb(eyes[n_eyes]), (ex, ey))
            out_dir = DEST / "portraits" / folder.name
            jobs: list[tuple[str, Image.Image]] = [
                ("base.png", composite(base, [rest_mouth, rest_eyes])),
            ]
            if alt is not None:
                # the alternate head is often the SAME face on a canvas
                # shifted 16px, so it needs its own piece offsets —
                # reusing the base's dropped the eyes and mouth in the
                # wrong place and streaked the frame
                amx, amy, _ = group_offset(alt, mouths)
                aex, aey, _ = group_offset(alt, eyes)
                jobs.append(("hurt.png", composite(alt, [
                    (load_rgb(mouths[neutral_index(alt, mouths, (amx, amy))]), (amx, amy)),
                    (load_rgb(eyes[neutral_index(alt, eyes, (aex, aey))]), (aex, aey)),
                ])))
            for i, path in enumerate(eyes):
                jobs.append((f"blink_n{i:02d}.png",
                             composite(base, [rest_mouth, (load_rgb(path), (ex, ey))])))
            for i, path in enumerate(mouths):
                jobs.append((f"talk_n{i:02d}.png",
                             composite(base, [(load_rgb(path), (mx, my)), rest_eyes])))
            for name, image in jobs:
                dst = out_dir / name
                if dst.is_file() and not force:
                    continue
                if not dry_run:
                    out_dir.mkdir(parents=True, exist_ok=True)
                    image.save(dst)
                written += 1
            folders += 1
    return written, 0 if folders else 1


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--force", action="store_true",
                    help="rewrite files that already exist")
    args = ap.parse_args()

    if not HUD.is_dir():
        print(f"zod hud art not found at {HUD} — nothing to do "
              "(it is a gitignored per-contributor copy)")
        return 0

    written = missing = 0
    hud_out = DEST / "hud"

    def emit(src: Path, dst: Path) -> None:
        nonlocal written
        if dst.is_file() and not args.force:
            return
        print(f"{'would write' if args.dry_run else 'write'}  "
              f"{dst.relative_to(ROOT)}")
        if not args.dry_run:
            dst.parent.mkdir(parents=True, exist_ok=True)
            Image.open(src).save(dst)
        written += 1

    for name, out_name in PLATES:
        src = HUD / name
        if not src.is_file():
            print(f"MISSING SOURCE  {name}")
            missing += 1
            continue
        emit(src, hud_out / out_name)

    for letter in BUTTONS:
        for state in BUTTON_STATES:
            src = HUD / f"{letter}_button_{state}.bmp"
            if not src.is_file():
                print(f"MISSING SOURCE  {src.name}")
                missing += 1
                continue
            emit(src, hud_out / f"btn_{letter}_{state}.png")

    for type_name in WEAPON_TYPES:
        src = HUD / f"{type_name}_icon.png"
        if not src.is_file():
            print(f"MISSING SOURCE  {src.name}")
            missing += 1
            continue
        emit(src, hud_out / f"weapon_{type_name}.png")

    baked, portrait_missing = bake_portraits(args.dry_run, args.force)
    missing += portrait_missing

    print(f"hud-pieces={written} portrait-frames={baked} "
          f"missing-source={missing}")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
