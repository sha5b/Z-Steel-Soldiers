# Research Notes — Z: Steel Soldiers

Compiled 2026-08-17. Everything below was verified hands-on unless marked
otherwise.

## 1. Is there source code or an existing remake?

**No.** Checked:

- Wikipedia: [List of game engine recreations] — not listed
- Wikipedia: [List of commercial games with later released source code] —
  The Bitmap Brothers never released the source
- [awesome-game-remakes] — not listed
- GitHub searches for remakes/reimplementations — nothing active

The 2014 Steam "remaster" (app 275510) is the same game re-packaged with
updated art; it is not open source.

Caveat: the **official UK demo** accidentally ships real engine headers
(`Symbols/z2strings.h` — plain C source with Bitmap Brothers CVS headers).
The remaining `Symbols/*_sym.h` files are enciphered (see §4).

## 2. Game overview (what we must recreate)

From Wikipedia/PCGamingWiki/manual coverage:

- RTS, 2001, Windows. Sequel to *Z* (1996). 30 missions, 5 worlds
  (Desert, Arctic, Jungle, Volcanic, Temperate/Urban...).
- **Economy:** no harvesting. Capturing **sectors** (map territory flags)
  generates money proportional to sector value; power comes from the
  territory's power grid. This is *the* defining mechanic.
- **Units:** robot infantry (Grunt, Psycho, Tough, Sniper, Pyro, Technician,
  Explosives...), vehicles (light/medium/heavy: Jeeps, Tanks, APCs, helis,
  jets, jump-jets, barges...). Robots pilot empty vehicles — infantry +empty
  vehicle = crewed vehicle.
- **Buildings:** per-sector (Command Centre, Radar, Factory variants: robot
  factory, vehicle factory, airfield...). Production via factory queue.
- 6 heroes per side with portraits and taunt voice lines; mission dialogue
  between heroes drives the campaign.
- 3D on 2D-ish gameplay: fixed isometric-style camera, deformable-ish
  terrain, bridges, water, radar/minimap HUD.
- Up to 8 players in skirmish/MP, teams, human/CPU slots.

## 3. Demo extraction (done)

- Source: [Archive.org — Z Steel Soldiers (UK) Demo]
  (`z_-_steel_soldiers_uk_demo`, 92 MB zip, bin/cue CD image).
- The CD is a **MODE2/2352** InstallShield installer disc:
  1. Carve 2048-byte user data per sector → ISO (`isoinfo` then lists files)
  2. `unshield x data1.cab` (built from source into `~/.local`, no sudo)
  3. Result: `Z_Files/` = **1360 files** — the actual demo game tree
- A second demo item (`SteelSoldiersDemo`) also exists on Archive.org; not
  needed.

Extracted tree (`assets_original/demo/`):

| Folder              | Contents                                                    |
|---------------------|-------------------------------------------------------------|
| `Demo/`             | `demo.exe`, engine DLLs (`zrcore`, `zrgeom`, `zrdx8`, `z2net`, `routefinder`, `EventSys`, `EventEd`) |
| `GfxData/`          | 630 files: models (`.zrb`), textures (`.tga`), GUI images, fonts, Fx |
| `WorldData/demo/`   | the Desert demo level: `Demo1.zlv` (plaintext level!), `.zrc/.zrh` scripts, `.dbs`, minimap, scape/wav ambience, world models+textures |
| `sfx/`              | 589 WAVs (environment, generic, menu, win/lose stingers)    |
| `Symbols/`          | `z2strings.h` (plain C!), enciphered `*_sym.h`, `.zrs`, grammar, options script |

## 4. Asset encipherment (cracked)

The engine stores media files enciphered with a **size-keyed byte stream**.
Algorithm reversed by Luigi Auriemma
([ZenHAX thread], script `z_steel_soldiers.bms`):

```
BL = (1 if size > 0x10 else 0) ^ (size >> 8) ^ 0x18
plain[i] = ((i + BL) ^ enc[i]) - i     (byte-wise)
```

Verified against the demo: WAVs decode to clean RIFF/PCM (22050 Hz, 16-bit),
TGAs decode to valid images. Implemented in `tools/zss/decrypt_assets.py`;
878 files decrypted successfully. The same algorithm should cover `.zrc`,
`.zrh` and "few others" per Auriemma — but note `.zrh` decodes to binary VM
bytecode, not text.

## 5. File formats observed

See `docs/FORMATS.md` for details. Summary:

| Ext        | Nature                                                        |
|------------|---------------------------------------------------------------|
| `.zlv`     | **Plaintext** s-expression level definition (after decrypt)    |
| `.zrb`     | Binary tokenized scene-graph model ("ZRB\0" magic, v7)         |
| `.tga`     | Standard TGA after decryption                                 |
| `.wav`     | Standard PCM WAV after decryption                             |
| `.zrc/.zrh`| Mission logic: compiled VM bytecode (+ `.zlv`-ish text parts?) |
| `.dbs`     | Level database (binary)                                       |
| `.z2`      | GUI image collections                                         |
| `.dsf`     | "DIMEDSF" sound archive (codec unknown per Auriemma)          |
| `.zrs`     | Enciphered symbol/resource tables                             |
| `.movie`   | Mission intro "movie" script (enciphered)                     |

## 6. Web asset inventory

- [The Sounds Resource — Z: Steel Soldiers]:
  **210 packs** — hero/unit/mission-dialogue voice for 5 languages + 5 SFX
  categories. Full manifest with direct URLs committed at
  `tools/scrape/data/sounds_manifest.json`; downloader in
  `tools/scrape/download_sounds.py`. (Scraped politely, 0.4–1 s delays.)
- The Models / Textures / Sprites Resource have game pages but **0 assets**
  uploaded for this game (checked 2026-08-17).
- No other legal asset sources found. Demo extraction (§3) is therefore the
  primary source for 3D models/textures.

## 7. Engine facts from the demo binaries

- Engine name: **Z2** (headers: "Z2. Copyright 1997-1999 The Bitmap
  Brothers Ltd."). Renderer DLL `zrdx8` (DirectX 8). Pathfinding lives in
  `routefinder.dll`; mission scripting in `EventSys/EventEd` DLLs.
- `Symbols/z2strings.h` enumerates hundreds of game string IDs (menu,
  units, orders...) — useful as a checklist of game vocabulary.
- Level text format (`.zlv`) references objects by editor name
  ("Command Centre", "Psycho", "Anti Air Gun", "Weapons Factory"...),
  teams, weather ("Stormy"), lighting ("Midnight"), map 256×256,
  water level, robot/vehicle angles. This is a direct spec source for map
  loading.

## 8. Godot environment

- Installed: Godot **4.7.1 stable** via Flatpak (`org.godotengine.Godot`).
  Latest upstream stable is 4.8 (June 2026); 4.7.1 is a supported
  maintenance-branch release — fine to target. CLI:
  `flatpak run org.godotengine.Godot --headless --path project --import`
  for CI-style imports/exports.

## 9. Licensing

- Demo binaries/assets: © The Bitmap Brothers (defunct; IP passed to
  Summitsoft/Richelieu?). Free demo was officially distributed — using it
  locally as reference/extraction source is standard fan-remake practice.
- Sounds Resource rips: same copyright; gitignored in this repo.
- Anything we ship publicly must be original/CC0 placeholder art with a
  local-only "original assets" switch.

[List of game engine recreations]: https://en.wikipedia.org/wiki/List_of_game_engine_recreations
[List of commercial games with later released source code]: https://en.wikipedia.org/wiki/List_of_commercial_video_games_with_later_released_source_code
[awesome-game-remakes]: https://github.com/radek-sprta/awesome-game-remakes
[Archive.org — Z Steel Soldiers (UK) Demo]: https://archive.org/details/z_-_steel_soldiers_uk_demo
[ZenHAX thread]: http://aluigi.zenhax.com/viewtopic.php?t=4198
[The Sounds Resource — Z: Steel Soldiers]: https://sounds.spriters-resource.com/pc_computer/zsteelsoldiers/
