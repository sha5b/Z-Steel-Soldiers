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

Plaintext s-expression language after decryption. Observed grammar
(from `WorldData/demo/Campain/Demo1.zlv`, 2162 lines):

```
(
leveldata (
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
            objectextraname("Blue-CC",off)
            objectteam(2)  setobjectlevel(4)
            setobjectrotation(0,-360,0)
            shedslotentry ( completeobject(...) ... )   # garrisoned units
        )
        ...
    )
    ...
)
```

Coordinates are world-space floats (X, Y, 0?). Object names match editor/
catalogue names — the game must resolve them through an object database
(probably `.dbs` or `GfxData` conventions).

Same s-expression language appears compiled into binary tokens in `.zrb`.

## `.zrb` — model/scene file 🔶

Magic `ZRB\0`, then a token stream. Tokens seen (byte values):

| Byte | Meaning (inferred)                                  |
|------|-----------------------------------------------------|
| `07` | file header/version marker (version 07 follows?)    |
| `04` | inline null-terminated string follows              |
| `03` | 4-byte float follows                                |
| `05` | end of list/node                                    |
| `06` | node start; next byte = node type id               |
| `08` | attribute/name definition?                          |

Node type ids observed: `0x58 scene`, `0xe0/0xe1/e2` (transform: position /
rotation / scale — 3 floats each follow), `0xca`, …

Strings inside unit models reference: node names (`backpack`), texture files
(`robotext3.tga`), material names (`robotext3`). Large tail of floats =
vertex/normal/UV buffers. This is the **main conversion target** for getting
original models into glTF. 418 files across `GfxData` + `WorldData`.

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

## `.zrs` / `Symbols/*_sym.h` ❓

Enciphered with something *stronger* than §1 (single-byte XOR ruled out by
brute force). Likely scrambled C headers symbol tables the engine loads for
scripting. The one plaintext header (`z2strings.h`) proves the pattern.

## WAV / TGA ✅

Standard formats post-decryption: PCM 22050 Hz 16-bit mono/stereo; TGA
uncompressed 24/32-bit (e.g. 128×128 tiles).
