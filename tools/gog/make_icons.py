#!/usr/bin/env python3
"""Cut the game's icon set out of the retail splash art.

The icon is the release's own Z LOGO — the riveted metal Z on its yellow
plate in the top-left corner of `PNG/IPSplash.png` (1024x1024, the iOS
splash; `Splash.png` is the same image at 512 and loses rivet detail).
Nothing in the release ships an icon file, so this crops one.

Output goes under `project/assets/icon/`, which is GITIGNORED like every
other file derived from the original art (see .gitignore and
docs/RESEARCH.md licensing) — the icons are Bitmap Brothers pixels, so
each contributor regenerates them locally:

    python3 tools/gog/make_icons.py

Writes:
  icon.png        256x256   Godot `config/icon` and the in-game window icon
  icon_512.png    512x512   macOS export (Godot bakes its own .icns from it)
  icon.ico        multi-size Windows .ico (16..256) — only embedded into the
                  .exe when rcedit is available, which needs wine; the
                  window icon comes from icon.png either way
  hicolor/<n>x<n>/z-remake.png   Linux desktop icon tree for a .desktop install
"""

import pathlib
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit("Pillow is required: pip install --user pillow")

ROOT = pathlib.Path(__file__).resolve().parents[2]
SPLASH = ROOT / "assets_original/gog/PNG/IPSplash.png"
OUT = ROOT / "project/assets/icon"

# The Z sits at roughly (20,30)-(330,335) in the 1024px splash. This square
# centres it with an even margin and stops short of the red robot's shoulder
# that leans into the bottom-right corner.
CROP = (0, 8, 344, 352)

ICO_SIZES = [16, 24, 32, 48, 64, 128, 256]
HICOLOR_SIZES = [16, 32, 48, 64, 128, 256, 512]


def main() -> int:
    if not SPLASH.exists():
        sys.exit(f"missing {SPLASH} — copy the GOG release into assets_original/")
    OUT.mkdir(parents=True, exist_ok=True)
    logo = Image.open(SPLASH).convert("RGBA").crop(CROP)

    logo.resize((256, 256), Image.LANCZOS).save(OUT / "icon.png")
    logo.resize((512, 512), Image.LANCZOS).save(OUT / "icon_512.png")
    # Pillow builds every listed size into one .ico
    logo.resize((256, 256), Image.LANCZOS).save(
        OUT / "icon.ico", sizes=[(n, n) for n in ICO_SIZES])

    for n in HICOLOR_SIZES:
        d = OUT / "hicolor" / f"{n}x{n}"
        d.mkdir(parents=True, exist_ok=True)
        logo.resize((n, n), Image.LANCZOS).save(d / "z-remake.png")

    print(f"icons written to {OUT.relative_to(ROOT)} "
          f"(crop {CROP} of {SPLASH.name})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
