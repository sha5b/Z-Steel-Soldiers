#!/usr/bin/env python3
"""Pack the zod per-character font sets into BMFont atlases Godot imports.

Sources (assets_original/zod/fonts/, same original Z art pre-extracted):
  yellow_menu/  8px gold-with-outline menu font — the classic Z menu look
  big_white/    16px white-with-outline display font

Each set ships one tight-cropped PNG per character (char_<ascii>.png) with
no metrics; vertical placement is reconstructed from per-glyph heights:
letters bottom-align on the baseline, 'gjqpy' hang below it, quote marks
pin to the top, commas and periods sit on the baseline. Output is a
single-page BMFont text .fnt + atlas PNG in project/assets/z/ui/font/.

Rerunnable; regenerates deterministically (shelf packing, sorted ids).
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
FONTS = ROOT / "assets_original" / "zod" / "fonts"
OUT = ROOT / "project" / "assets" / "z" / "ui" / "font"

SETS = [
    # dir, out name, atlas width, x spacing, chars to skip
    ("yellow_menu", "z_menu_yellow", 256, 1),
    ("big_white", "z_big_white", 512, 2),
]

TOP_CHARS = "'\"`^"
CENTER_CHARS = "*+-=<>~"


def baseline_of(chars: dict) -> int:
    """Baseline = ink height of plain x-height/cap letters, clamped to [6,18]."""
    heights = [im.height for code, im in chars.items()
               if chr(code) in "acemnorsuvwxz0359bdhkt"]
    return max(6, min(18, max(heights) if heights else 8))


def yoffset(code: int, h: int, base: int) -> int:
    ch = chr(code)
    if ch in "gjpqy":
        return base - h + max(2, h - base)  # hang below the baseline
    if ch in ",.;":
        return base - h  # sit on the baseline
    if ch == "_":
        return base - 1
    if ch in TOP_CHARS:
        return 1
    if ch in CENTER_CHARS:
        return max(1, base // 2 - h // 2)
    return max(0, base - h)  # bottom-aligned on the baseline


def pack(src_dir: Path, name: str, atlas_w: int, spacing: int) -> None:
    chars = {}
    for f in sorted(src_dir.glob("char_*.png")):
        im = Image.open(f).convert("RGBA")
        bbox = im.getbbox()
        if bbox and chr(int(f.stem.split("_")[1])) != " ":
            im = im.crop(bbox)
        chars[int(f.stem.split("_")[1])] = im
    base = baseline_of(chars)
    descent = 2
    line_h = base + descent + 1

    # shelf-pack with 1px padding to stop atlas bleeding
    pad = 1
    x = y = shelf_h = 0
    placed = {}
    for code in sorted(chars):
        im = chars[code]
        if x + im.width + pad * 2 > atlas_w:
            x = 0
            y += shelf_h + pad * 2
            shelf_h = 0
        placed[code] = (x + pad, y + pad, im)
        x += im.width + pad * 2
        shelf_h = max(shelf_h, im.height)
    atlas_h = y + shelf_h + pad * 2

    sheet = Image.new("RGBA", (atlas_w, atlas_h), (0, 0, 0, 0))
    lines = []
    for code, (px, py, im) in placed.items():
        sheet.alpha_composite(im, (px, py))
        adv = 4 if chr(code) == " " else im.width + spacing
        lines.append(
            "char id=%d x=%d y=%d width=%d height=%d xoffset=0 yoffset=%d "
            "xadvance=%d page=0 chnl=15" % (
                code, px, py, im.width, im.height, yoffset(code, im.height, base), adv))
    sheet.save(OUT / f"{name}.png")

    fnt = OUT / f"{name}.fnt"
    fnt.write_text(
        "info face=\"{0}\" size={1} bold=0 italic=0 charset=\"\" unicode=1 "
        "stretchH=100 smooth=0 aa=1 padding=0,0,0,0 spacing=1,1 outline=0\n"
        "common lineHeight={2} base={1} scaleW={3} scaleH={4} pages=1 packed=0 "
        "alphaChnl=0 redChnl=4 greenChnl=4 blueChnl=4\n"
        "page id=0 file=\"{0}.png\"\n"
        "chars count={5}\n{6}\n".format(
            name, base, line_h, atlas_w, atlas_h, len(lines), "\n".join(lines)))
    print(f"{name}: {len(lines)} chars, base={base}, atlas {atlas_w}x{atlas_h}")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for src, name, w, sp in SETS:
        pack(FONTS / src, name, w, sp)


if __name__ == "__main__":
    main()
