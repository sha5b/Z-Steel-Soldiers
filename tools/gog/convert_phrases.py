#!/usr/bin/env python3
"""Decode the GOG PHRASES.BIN face-animation table to JSON.

Format (reverse engineered 2026-08-21, see docs/RESEARCH.md):
  u32 zero, u32 44 (data offset of the first stream)
  then 64 records of 552 bytes:
    [ 0..31]  phrase name, NUL-terminated, space padded
    [32..551] 256 little-endian u16 pairs:
                low  byte (col-A) — secondary channel, semantics unknown
                high byte (col-B) — FACE FRAME << 4 (alphabet 0..15;
                                    0 = rest; blink uses 15, wink adds 5,
                                    surprise adds 4; speech uses 1..8)

Output: project/assets/z/phrases.json
  {"phrases": [{"name": ..., "frames": [256 ints], "aux": [256 ints]}, ...]}

Run from the repo root:  python3 tools/gog/convert_phrases.py
"""
import json
import struct
import sys
from pathlib import Path

SRC = Path("assets_original/gog/PHRASES.BIN")
DST = Path("project/assets/z/phrases.json")
RECORD = 552
NAMES = 64


def main() -> int:
    if not SRC.exists():
        print(f"missing {SRC} — copy the GOG dump first (see README)")
        return 1
    data = SRC.read_bytes()
    phrases = []
    for r in range(NAMES):
        off = 8 + r * RECORD
        if off + RECORD > len(data):
            break
        name = data[off:off + 32].split(b"\0")[0].decode("ascii").rstrip()
        frames, aux = [], []
        for i in range(256):
            a, b = struct.unpack_from("<BB", data, off + 32 + i * 2)
            aux.append(a)
            frames.append(b >> 4)
        phrases.append({"name": name, "frames": frames, "aux": aux})
    DST.write_text(json.dumps({"phrases": phrases}))
    print(f"{len(phrases)} phrases -> {DST}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
