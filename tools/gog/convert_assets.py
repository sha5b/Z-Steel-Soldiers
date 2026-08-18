#!/usr/bin/env python3
"""Convert the GOG release of Z into the project's asset layout.

Sources (assets_original/gog/, Runesoft/Mac port of Z, © The Bitmap
Brothers — gitignored, local only):
  audio/*.RAW        8-bit unsigned PCM mono 11025 Hz sound effects
  *.ogg (root)       in-game music loops + win/lose jingles
  en.lproj/*.ogg     planet stingers/cutscene music (unused for now)
  PNG/Box*.png       original HUD panel art (3-slice: caps + centre)
  PNG/Background.png title backdrop, PNG/Splash.png title splash

Outputs into project/assets/z/ following docs/ASSET_CONVENTIONS.md.
Rerunnable; skips already-converted files. Unit sprites are NOT in the
GOG extraction (engine-packed) — those stay sourced from the zod pack.
"""
import shutil
import struct
import sys
import wave
from pathlib import Path

GOG = Path(__file__).resolve().parents[2] / "assets_original" / "gog"
PROJ = GOG.parent.parent / "project" / "assets" / "z"

SAMPLE_RATE = 11025

MUSIC = ["AA16.ogg", "aC16.ogg", "aJ16.ogg", "ipBATTLE16.ogg",
         "ipOPTIONS16.ogg", "ipWIN.ogg", "ipLOSE.ogg"]

UI = ["Background.png", "Splash.png", "BoxLeft.png", "BoxRight.png",
      "BoxCentreWide.png", "BoxCentreNarrow.png", "BoxDivide.png",
      "BoxInfo.png", "BoxInfo2.png", "Buttons.png", "PMHSprites.png"]

# 320x200 world thumbs for the campaign/map screens (pairs: base + alt
# lighting pass). Palette-mode PNGs; Godot imports them as-is.
PLANETS = ["ARTIC", "CITY", "DESERT", "JUNGLE", "VOLCAN"]

# 64x128 Mac-port menu plaques + 64x64 exit button art.
PLAQUES = ["options.png", "audio.png", "credits.png", "Exit.png"]


def raw_to_wav(raw_path: Path, wav_path: Path) -> None:
    data = raw_path.read_bytes()
    with wave.open(str(wav_path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes(b"".join(
            struct.pack("<h", (b - 128) * 256) for b in data))


def main() -> None:
    (PROJ / "sounds").mkdir(parents=True, exist_ok=True)
    (PROJ / "music").mkdir(parents=True, exist_ok=True)
    (PROJ / "ui").mkdir(parents=True, exist_ok=True)

    sfx = sorted(GOG.glob("audio/*.RAW"))
    for raw in sfx:
        wav = PROJ / "sounds" / (raw.stem + ".wav")
        if not wav.exists():
            raw_to_wav(raw, wav)
    print(f"sounds: {len(sfx)} RAW -> wav (11025 Hz u8 mono -> 16-bit)")

    n = 0
    for name in MUSIC:
        src, dst = GOG / name, PROJ / "music" / name
        if src.exists() and not dst.exists():
            shutil.copy2(src, dst)
            n += 1
    print(f"music: {n} ogg tracks copied ({len(MUSIC)} selected of soundtrack)")

    n = 0
    for name in UI:
        src, dst = GOG / "PNG" / name, PROJ / "ui" / name
        if src.exists() and not dst.exists():
            shutil.copy2(src, dst)
            n += 1
    print(f"ui: {n} HUD/background images copied")

    (PROJ / "ui" / "planets").mkdir(parents=True, exist_ok=True)
    n = 0
    for base in PLANETS:
        for variant in ["", "2"]:
            src = GOG / "PNG" / f"{base}{variant}.png"
            dst = PROJ / "ui" / "planets" / f"{base.lower()}{variant}.png"
            if src.exists() and not dst.exists():
                shutil.copy2(src, dst)
                n += 1
    print(f"planets: {n} world thumbnails copied")

    (PROJ / "ui" / "plaques").mkdir(parents=True, exist_ok=True)
    n = 0
    for name in PLAQUES:
        src, dst = GOG / "PNG" / name, PROJ / "ui" / "plaques" / name
        if src.exists() and not dst.exists():
            shutil.copy2(src, dst)
            n += 1
    print(f"plaques: {n} menu plaques copied")

    # zod-sourced explosion wavs are superseded by EXP1/EXP2/OBJDEST3
    removed = 0
    for old in PROJ.glob("sounds/explosion_0*.wav"):
        old.unlink()
        removed += 1
    if (PROJ / "sounds" / "GRENADE.wav").exists():
        (PROJ / "sounds" / "GRENADE.wav").unlink()  # replaced by GRENADE.RAW
        removed += 1
    print(f"superseded zod sfx removed: {removed}")


if __name__ == "__main__":
    sys.exit(main())
