# Z (1996) — Godot Remake

A fan remake of the original **Z** (The Bitmap Brothers, 1996) — the 2D
robot RTS — in Godot 4, as faithful to the original as possible using the
assets and format knowledge from the open-source
[Zod Engine](https://github.com/a-sf-mirror/zod_engine) project.

> **Status:** single-player feature-complete — all 57 original maps,
> full unit roster, territory economy, production, campaign, save/load,
> AI with difficulty, and a 17-check headless test suite. Multiplayer
> intentionally out of scope. See `docs/ROADMAP.md`.

## Environment

- Godot **4.7.1 stable** (Flatpak: `org.godotengine.Godot`)
  ```bash
  flatpak run org.godotengine.Godot   # open project/project.godot, press F5
  ```
- Controls: WASD/arrows/edge pan, wheel zoom, drag = box select,
  right-click = move order.

## Repository layout

| Path                | Purpose                                             |
|---------------------|-----------------------------------------------------|
| `docs/`             | Research notes, roadmap                             |
| `project/`          | Godot project (2D)                                  |
| `assets_original/`  | Full Zod Engine asset set (gitignored, 84 MB)       |
| `project/assets/z/` | Working subset of Z sprites (gitignored)            |

## Asset licensing

The original Z graphics/sounds are © The Bitmap Brothers. They are
extracted via the Zod Engine asset pack, kept **gitignored** in
`assets_original/` and `project/assets/` — every contributor copies them
locally. Do not redistribute. The code in this repo is original.
