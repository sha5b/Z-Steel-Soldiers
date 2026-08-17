#!/usr/bin/env python3
"""Convert decrypted Z: Steel Soldiers .zrb models to glTF 2.0 (.glb).

A ZRB is a tokenized scene graph:
    FILE ( NODE ( NAME("x") TRANSLATION(x,y,z) ROTATION(deg) SCALE(x,y,z)
                  GEOMETRY ( SOLID TEXTURE("t.tga") VERTEX(...8 floats...)
                             TRIANGLE(i,j,k) ... )
                  NODE(...) ) )

Vertices carry 8 floats: position xyz, uv, normal xyz. Rotations are euler
degrees (order XYZ as written; the game is gone, so if orientation looks
off in Godot this is the knob). Meshes become triangle soups (indices are
per-geometry and sequential in the file).

Usage: zrb_to_gltf.py SRC_DIR OUT_DIR --symbols SYMBOLS_DIR [--texture-dir DIR]
Writes <name>.glb next to converted textures (PNG).
"""
import argparse
import json
import math
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from zss_lib import Node, Token, attr_values, find_all, find_first, head, load_symbols, parse_file  # noqa: E402

try:
    from PIL import Image
except ImportError:
    Image = None


def euler_xyz_deg_to_quat(rx: float, ry: float, rz: float) -> tuple[float, float, float, float]:
    ax, ay, az = map(math.radians, (rx, ry, rz))
    cx, sx = math.cos(ax / 2), math.sin(ax / 2)
    cy, sy = math.cos(ay / 2), math.sin(ay / 2)
    cz, sz = math.cos(az / 2), math.sin(az / 2)
    # R = Rz(az) Ry(ay) Rx(ax)  (glTF convention)
    return (
        sx * cy * cz + cx * sy * sz,
        cx * sy * cz - sx * cy * sz,
        cx * cy * sz + sx * sy * cz,
        cx * cy * cz - sx * sy * sz,
    )


def tga_to_png(tga_path: Path, png_path: Path) -> None:
    if Image is None:
        raise RuntimeError("Pillow required for texture conversion")
    img = Image.open(tga_path)
    img.save(png_path)


class GltfBuilder:
    def __init__(self, name: str):
        self.name = name
        self.json = {
            "asset": {"version": "2.0", "generator": "zss zrb_to_gltf"},
            "scenes": [{"nodes": [0]}],
            "scene": 0,
            "nodes": [],
            "meshes": [],
            "accessors": [],
            "bufferViews": [],
            "materials": [],
            "textures": [],
            "images": [],
            "samplers": [{"magFilter": 9729, "minFilter": 9987,
                          "wrapS": 10497, "wrapT": 10497}],
        }
        self.bin = bytearray()
        self.image_cache: dict[str, int] = {}
        self.material_cache: dict[str, int] = {}

    def add_buffer_view(self, data: bytes, target: int) -> int:
        align = 4 - (len(self.bin) % 4)
        self.bin += b"\x00" * align
        offset = len(self.bin)
        self.bin += data
        self.json["bufferViews"].append(
            {"buffer": 0, "byteOffset": offset, "byteLength": len(data), "target": target})
        return len(self.json["bufferViews"]) - 1

    def add_accessor(self, data: bytes, count: int, ctype: str, target: int) -> int:
        bv = self.add_buffer_view(data, target)
        self.json["accessors"].append(
            {"bufferView": bv, "componentType": ctype, "count": count,
             "type": "VEC3" if target == 34962 and len(data) // count == 12 else
                     ("VEC2" if target == 34962 else "SCALAR")})
        return len(self.json["accessors"]) - 1

    def add_image(self, texture_name: str, texture_dir: Path, out_dir: Path) -> int:
        if texture_name in self.image_cache:
            return self.image_cache[texture_name]
        tga = None
        for cand in (texture_dir / texture_name,
                     texture_dir / (texture_name + ".tga"),
                     texture_dir / (texture_name.replace(".tga", "") + ".tga")):
            if cand.exists():
                tga = cand
                break
        if tga is None:
            raise FileNotFoundError(f"texture {texture_name} not under {texture_dir}")
        png_rel = tga.with_suffix(".png").name
        if Image is not None:
            tga_to_png(tga, out_dir / png_rel)
        idx = len(self.json["images"])
        self.json["images"].append({"uri": png_rel})
        self.json["textures"].append({"sampler": 0, "source": idx})
        mat_idx = len(self.json["materials"])
        self.json["materials"].append({
            "name": texture_name,
            "pbrMetallicRoughness": {
                "baseColorTexture": {"index": len(self.json["textures"]) - 1},
                "metallicFactor": 0.0, "roughnessFactor": 1.0},
            "doubleSided": True})
        self.image_cache[texture_name] = mat_idx
        return mat_idx

    def add_mesh(self, geometry: Node, texture_dir: Path, out_dir: Path) -> int | None:
        verts = find_all(geometry, "VERTEX")
        tris = find_all(geometry, "TRIANGLE")
        if not verts or not tris:
            return None
        pos, uv, nrm = [], [], []
        for v in verts:
            vals = [t.value for t in v if isinstance(t, Token)][1:]
            if len(vals) < 8:
                return None
            pos += vals[0:3]
            uv += vals[3:5]
            nrm += vals[5:8]
        idx: list[int] = []
        for t in tris:
            vals = [t.value for t in t if isinstance(t, Token)][1:]
            idx += vals[:3]
        n = len(pos) // 3
        if max(idx, default=0) >= n:
            return None

        pacc = self.add_accessor(struct.pack(f"<{n*3}f", *pos), n, 5126, 34962)
        # fix type labels (VEC2/VEC3)
        self.json["accessors"][pacc]["type"] = "VEC3"
        uv_bytes = struct.pack(f"<{n*2}f", *uv)
        uvbv = self.add_buffer_view(uv_bytes, 34962)
        self.json["accessors"].append(
            {"bufferView": uvbv, "componentType": 5126, "count": n, "type": "VEC2"})
        uacc = len(self.json["accessors"]) - 1
        nacc = self.add_accessor(struct.pack(f"<{n*3}f", *nrm), n, 5126, 34962)
        self.json["accessors"][nacc]["type"] = "VEC3"
        ibytes = struct.pack(f"<{len(idx)}H", *idx)
        ibv = self.add_buffer_view(ibytes, 34963)
        self.json["accessors"].append(
            {"bufferView": ibv, "componentType": 5123, "count": len(idx),
             "type": "SCALAR"})

        tex_attr = find_first(geometry, "TEXTURE")
        mat = 0
        if tex_attr is not None:
            vals = [t.value for t in tex_attr if isinstance(t, Token)]
            if len(vals) > 1 and isinstance(vals[1], str):
                try:
                    mat = self.add_image(vals[1], texture_dir, out_dir)
                except FileNotFoundError:
                    pass

        self.json["meshes"].append({"primitives": [{
            "attributes": {"POSITION": pacc, "NORMAL": nacc, "TEXCOORD_0": uacc},
            "indices": len(self.json["accessors"]) - 1,
            "material": mat}]})
        return len(self.json["meshes"]) - 1

    def add_node(self, znode: Node, parent: int, texture_dir: Path, out_dir: Path) -> None:
        gnode: dict = {"name": "", "children": []}
        idx = len(self.json["nodes"])
        self.json["nodes"].append(gnode)
        self.json["nodes"][parent]["children"].append(idx)

        name = attr_values(znode, "NAME")
        gnode["name"] = str(name[0]) if name else f"node{idx}"
        tr = attr_values(znode, "TRANSLATION")
        if len(tr) == 3:
            gnode["translation"] = [round(v, 6) for v in tr]
        rot = attr_values(znode, "ROTATION")
        if len(rot) == 3 and any(v != 0 for v in rot):
            gnode["rotation"] = [round(v, 6) for v in euler_xyz_deg_to_quat(*rot)]
        sc = attr_values(znode, "SCALE")
        if len(sc) == 3 and any(v != 1 for v in sc):
            gnode["scale"] = [round(v, 6) for v in sc]

        for child in znode:
            if not isinstance(child, Node):
                continue
            h = head(child)
            if h == "GEOMETRY":
                mesh = self.add_mesh(child, texture_dir, out_dir)
                if mesh is not None:
                    gnode.setdefault("mesh", mesh)
            elif h == "NODE":
                self.add_node(child, idx, texture_dir, out_dir)

    def finish(self, out_path: Path) -> None:
        if not self.json["meshes"]:
            raise ValueError("no meshes")
        json_bytes = json.dumps(self.json, separators=(",", ":")).encode()
        def pad4(b: bytes) -> tuple[bytes, int]:
            n = (4 - len(b) % 4) % 4
            return b + b" " * n, len(b) + n
        json_pad, json_len = pad4(json_bytes)
        bin_start = 20 + json_len
        n = (4 - (len(self.bin) + (bin_start % 4 if bin_start % 4 else 0)) % 4) % 4
        # pad bin so its length is 4-aligned relative to file start
        while (bin_start + len(self.bin)) % 4:
            self.bin += b"\x00"
        header = struct.pack("<IIII", 0x46546C67, 2, 12 + json_len + len(self.bin), json_len)
        out_path.write_bytes(header + struct.pack("<I", len(self.bin)) + json_pad + self.bin)


def convert_file(src: Path, out_dir: Path, symbols: dict[int, str], texture_dirs: list[Path]) -> Path | None:
    forest = parse_file(src, symbols)
    znodes = [n for n in forest if head(n) == "NODE"]
    if not znodes:
        return None
    builder = GltfBuilder(src.stem)
    builder.json["nodes"].append({"name": src.stem, "children": []})

    by_name: dict[str, int] = {}
    pending_parent: dict[int, str] = {}
    for z in znodes:
        names = attr_values(z, "NAME")
        nm = str(names[0]) if names else None
        gidx = len(builder.json["nodes"])
        builder.json["nodes"].append({"name": nm or f"node{gidx}", "children": []})
        builder.json["nodes"][0]["children"].append(gidx)
        if nm:
            by_name[nm] = gidx
        tr = attr_values(z, "TRANSLATION")
        if len(tr) == 3:
            builder.json["nodes"][gidx]["translation"] = [round(v, 6) for v in tr]
        rot = attr_values(z, "ROTATION")
        if len(rot) == 3 and any(v != 0 for v in rot):
            builder.json["nodes"][gidx]["rotation"] = [round(v, 6) for v in euler_xyz_deg_to_quat(*rot)]
        sc = attr_values(z, "SCALE")
        if len(sc) == 3 and any(v != 1 for v in sc):
            builder.json["nodes"][gidx]["scale"] = [round(v, 6) for v in sc]
        par = attr_values(z, "PARENT")
        if par:
            pending_parent[gidx] = str(par[0])
        for child in z:
            if isinstance(child, Node) and head(child) == "GEOMETRY":
                mesh = builder.add_mesh(child, texture_dirs[0], out_dir)
                if mesh is not None:
                    builder.json["nodes"][gidx].setdefault("mesh", mesh)

    # re-parent children under their named PARENT
    for gidx, pname in pending_parent.items():
        if pname in by_name and pname != builder.json["nodes"][gidx]["name"]:
            builder.json["nodes"][0]["children"].remove(gidx)
            builder.json["nodes"][by_name[pname]]["children"].append(gidx)

    out = out_dir / f"{src.stem}.glb"
    try:
        builder.finish(out)
    except ValueError:
        return None
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("src", type=Path)
    ap.add_argument("out", type=Path)
    ap.add_argument("--symbols", type=Path, required=True,
                    help="dir containing decrypted zrc_symbols.h")
    ap.add_argument("--texture-dirs", type=Path, nargs="+", required=True)
    args = ap.parse_args()
    symbols = load_symbols(args.symbols)
    args.out.mkdir(parents=True, exist_ok=True)

    files = sorted(args.src.rglob("*.zrb")) if args.src.is_dir() else [args.src]
    ok, fail, skipped = 0, 0, 0
    for f in files:
        try:
            res = convert_file(f, args.out, symbols, args.texture_dirs)
        except Exception as e:  # noqa: BLE001
            print(f"FAIL {f.name}: {e}")
            fail += 1
            continue
        if res is None:
            skipped += 1
        else:
            ok += 1
    print(f"converted {ok}, skipped {skipped}, failed {fail} -> {args.out}")


if __name__ == "__main__":
    main()
