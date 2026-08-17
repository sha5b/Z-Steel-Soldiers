# Z: Steel Soldiers — Godot Remake

A fan remake of *Z: Steel Soldiers* (The Bitmap Brothers, 2001) in Godot 4,
built as faithfully as possible to the original using assets extracted from
the official free demo and community-ripped sound packs.

> **Status:** research & asset pipeline phase. See `docs/RESEARCH.md` and
> `docs/ROADMAP.md`.

## Environment

- Godot **4.7.1 stable** (Flatpak: `org.godotengine.Godot`)
  ```bash
  flatpak run org.godotengine.Godot
  ```
- Python 3 (asset tooling in `tools/`)

## Repository layout

| Path                | Purpose                                              |
|---------------------|------------------------------------------------------|
| `docs/`             | Research notes, format documentation, roadmap        |
| `tools/scrape/`     | Web scrapers for community asset sites               |
| `tools/zss/`        | Original-format tools (decryptor, converters)         |
| `assets_original/`  | Extracted demo assets + downloaded sounds (gitignored)|
| `project/`          | The Godot project (to be created)                    |

## Asset pipeline

```bash
# 1. one-time: scrape the Sounds Resource manifest (already committed)
python3 tools/scrape/scrape_sounds.py

# 2. download English voice + SFX packs into assets_original/sounds/
python3 tools/scrape/download_sounds.py          # or: ... all

# 3. decrypt demo assets (from an extracted demo install, see docs)
python3 tools/zss/decrypt_assets.py <src> assets_original/demo
```

## Licensing

The Godot code in this repository is original. All game assets from the demo
and rip sites remain © The Bitmap Brothers / their current holders; they live
in `assets_original/` which is **gitignored** — every contributor extracts
their own copy locally. Do not redistribute them.
