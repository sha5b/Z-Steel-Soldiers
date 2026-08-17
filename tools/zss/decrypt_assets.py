#!/usr/bin/env python3
"""Deobfuscate Z: Steel Soldiers media files.

The engine stores tga/wav/zrc/zrh (and a few other) files enciphered with a
size-keyed byte stream, reversed by Luigi Auriemma in z_steel_soldiers.bms:

    BL = (1 if size > 0x10 else 0) ^ (size >> 8) ^ 0x18
    plain[i] = ((i + BL) ^ enc[i]) - i        (mod 256 per byte)

Usage: decrypt_assets.py SRC DST [ext ...]
Defaults to the extensions known to be enciphered. Unknown/binary engine
formats (.zrb, .dll, ...) are copied verbatim.
"""
import shutil
import sys
from pathlib import Path

DEFAULT_EXTS = {"tga", "wav", "zrc", "zrh", "zlv"}


def decrypt(data: bytes) -> bytes:
    size = len(data)
    bl = (1 if size > 0x10 else 0) ^ (size >> 8) ^ 0x18
    return bytes((((i + bl) ^ b) - i) & 0xFF for i, b in enumerate(data))


def main() -> None:
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    src, dst = Path(sys.argv[1]), Path(sys.argv[2])
    exts = {e.lower().lstrip(".") for e in sys.argv[3:]} or DEFAULT_EXTS
    n_dec = n_copy = 0
    for f in sorted(src.rglob("*")):
        if not f.is_file():
            continue
        rel = f.relative_to(src)
        out = dst / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        if f.suffix.lower().lstrip(".") in exts:
            out.write_bytes(decrypt(f.read_bytes()))
            n_dec += 1
        else:
            shutil.copy2(f, out)
            n_copy += 1
    print(f"decrypted {n_dec}, copied {n_copy} -> {dst}")


if __name__ == "__main__":
    main()
