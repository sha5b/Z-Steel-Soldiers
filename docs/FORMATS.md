# Z: Steel Soldiers file formats

Reverse-engineering notes from the UK demo (`assets_original/demo/`).
Status column: ✅ understood · 🔶 partially · ❓ unknown.

## Encipherment (applies to `.tga .wav .zrc .zrh .zlv` …)

```
BL = (1 if size > 0x10 else 0) ^ (size >> 8) ^ 0x18
plain[i] = ((i + BL) ^ enc[i]) - i
```

`tools/zss/decrypt_assets.py` implements it. Reference: Luigi Auriemma's
`z_steel_soldiers.bms`.

## `.zlv` — level definition ✅

Plaintext s-expressions after decryption, using the same `head(values)`
pair grammar as ZRB. Observed grammar
(from `WorldData/demo/Campain/Demo1.zlv`, 2162 lines):

```
( leveldata (
    worldtype("Desert")
    players(1)  mapnumber(1)  startresource(5000)
    setweather("Stormy")  setlighting("Midnight")
    maxtech(1)  robotangle(46)  vehicleangle(46)
    mapsize(256,256)  maxheight(325)  stepused(65)  waterlevel(49)
    teamsused(2)
    teamname(0,"Team 1") ... teamallocation(1,"Team 1",humanonly,"(1) Reed")
    objectlist (
        completeobject (
            objectentry("Command Centre", 147.5, 0.0, 162.5)
            objectextraname("Blue-CC", off)
            objectteam(2)  setobjectlevel(4)  setobjectrotation(0,-360,0)
            shedslotentry ( completeobject(...) ... )   # garrisoned units
        )
        ... 273 objects total ...
    )
)
```

Demo roster (273 objects): 2 Command Centres, Radars, Robot/Weapons
Factories, bunkers with garrisoned Psychos, Pyros, Construction Robots,
guns (Anti Tank/Anti Air), tanks (Light/Medium/Mortar), Hummers, plus 210
`terrainobjectentry` scenery props referencing `.zrs` resource files
(barrels, etc.) with `setobjectdestroyable`/`landobjectscale` attributes.

Parser: `tools/zss/parse_zlv.py` → JSON (`settings` + `objects`).

## `.zrb` — model/scene file ✅ (decoded 2026-08-17)

Binary token stream after `ZRB\0` magic, fully reversed:

| Token          | Meaning                                    |
|----------------|--------------------------------------------|
| `00 <u8>`      | small unsigned integer atom                |
| `01 <u16>`     | unsigned integer atom                      |
| `03 <f32>`     | float atom                                 |
| `04 <cstr>`    | string atom                                |
| `05` / `06`    | list open `(` / close `)`                  |
| `07`           | file head (appears once, before root list) |
| `08..FE`       | symbol atom: `zrc_symbols.h` enum + 7      |
| `FF XX`        | escaped symbol (runtime enum; partly known)|

Key discovery: the demo's enciphered `Symbols/*_sym.h` files decode with
the same size-keyed cipher (§1) and contain the **complete script-symbol
enums** — `zrc_symbols.h` lists all 363 `zrID_*` names. Plain symbol bytes
map to that enum with a **+7 offset** (runtime enum gained 7 leading
entries). FF-escaped symbols diverge (runtime enum grew mid-list);
confirmed mappings: `FF 82` = TRIANGLE.

File structure — a forest of top-level lists, each `SYM ( values )` pair
(the binary form of the `.zlv` text grammar):

```
NODE ( <attr manifest> ) NAME("scene") TRANSLATION(x y z) ROTATION(deg|quat)
     SCALE(x y z) PARENT("other node") ...
MESH ( NAME(...) SIZE(n) VERTEX(px py pz u v nx ny nz) VERTEX(...)
       TRIANGLE(i j k) TRIANGLE(...) )
FF77 ( ... detail/LOD mesh, same layout ... )
TEXTURE ( NAME("robotext2") FILE("robotext2.tga") )
MATERIAL ( NAME GEOMETRY( TEXTURING(PERSPECTIVE) SHADING(FLAT) ... ) )
```

- Nodes link by `PARENT(name)` references, not nesting.
- Vertices carry 8 floats: position xyz, UV, normal xyz.
- Rotations: euler degrees (3 values) or quaternion (4 values).
- Node names double as attach points (`firestraight`, `fireair`,
  `firecrouch` = muzzle/fire positions).

Converter: `tools/zss/zrb_to_gltf.py` → glTF 2.0 GLB + PNG textures.
302/389 files produce meshes (the rest are non-mesh zrb: sprites, GUI,
camera dummies). Validated by orthographic render — apsycho_b is a
recognizable robot soldier.

## `.zrh` / `.zrc` — mission scripts ❓

`.zrh` decrypts to binary data — probably bytecode for the event/mission VM
(`EventSys.dll`). `.zrc` for the demo decodes to something image-like
(maybe minimap/icon). Needs work; the demo's `EventEd.dll` (event editor)
likely contains the opcode table — strings/disassembly pending.

## `.dbs` — level database ❓

`Demo1.zlv.dbs` — binary. Possibly the sector/heightmap/pathing data grid
for the level. The `.map` and `.tga` next to `Demo1.zlv` are the heightmap
and minimap.

## `.z2` — GUI image collection ❓

`GfxData/Gui/Images/*.z2` — binary containers of UI images. No RE yet.

## `.dsf` — DIMEDSF sound archive ❓

Magic `DIMEDSF`; directory at 0x50 with 0x20-byte entries (name, frequency,
channels, bits, offset, size — offsets/sizes in ALIGN units). Audio codec
unknown (per Auriemma, still unsolved publicly). Not blocking: demo ships
plain WAVs too.

## `.zrs` / `Symbols/*_sym.h` ✅ (decrypted)

**All symbol files decode with the §1 cipher** (they initially looked
stronger because the known-plaintext header differs from `z2strings.h`).
Decrypted copies live in `assets_original/demo/Symbols_dec/`. They are
plain C headers enumerating the script language's symbol ids — the
complete token vocabulary, including `zrc_symbols.h` (363 `zrID_*` names
used to decode ZRB).

## WAV / TGA ✅

Standard formats post-decryption: PCM 22050 Hz 16-bit mono/stereo; TGA
uncompressed 24/32-bit (e.g. 128×128 tiles).
