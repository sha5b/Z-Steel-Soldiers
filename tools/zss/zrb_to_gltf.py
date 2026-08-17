#!/usr/bin/env python3
"""Convert decrypted Z: Steel Soldiers .zrb models to glTF 2.0 (.glb).

A ZRB is a tokenized scene graph using one uniform grammar everywhere:

    SYM ( values ) SYM ( values ) ...

Nodes are top-level lists: NODE ( <attr manifest> ) NAME ( "x" ) PARENT ( "y" )
TRANSLATION ( x y z ) ROTATION ( deg ) SCALE ( x y z ) MESH ( ... ) ...
Meshes contain NAME/FLAG/SIZE pairs plus VERTEX (8 floats: pos xyz, uv,
normal xyz) and TRIANGLE (3 indices) pairs. Rotations are euler degrees.
"""
import argparse
import json
import math
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from zss_lib import Node, Token, attr_values, head, load_symbols, pairs, parse_file  # noqa: E402

try:
    from PIL import Image
except ImportError:
    Image = None


def euler_xyz_deg_to_quat(rx: float, ry: float, rz: float) -> tuple[float, float, float, float]:
    ax, ay, az = map(math.radians, (rx, ry, rz))
    cx, sx = math.cos(ax / 2), math.sin(ax / 2)
    cy, sy = math.cos(ay / 2), math.sin(ay / 2)
    cz, sz = math.cos(az / 2), math.sin(az / 2)
    return (  # R = Rz * Ry * Rx (glTF order)
        sx * cy * cz + cx * sy * sz,
        cx * sy * cz - sx * cy * sz,
        cx * cy * sz + sx * sy * cz,
        cx * cy * cz - sx * sy * sz,
    )


def find_texture_file(znode: Node, texture_dirs: list[Path]) -> tuple[Path, str] | None:
    """TEXTURE ( NAME(...) FILE("x") ) pairs may sit at node level."""
    for sym, vals in pairs(znode):
        if sym != "TEXTURE" or not isinstance(vals, list):
            continue
    for child in znode:
        if isinstance(child, Node) and head(child) != "":
            pass
    # texture pairs: Token(TEXTURE) followed by Node holding NAME/FILE pairs
    for i in range(len(znode) - 1):
        sym, val = znode[i], znode[i + 1]
        if isinstance(sym, Token) and sym.kind == "w" and sym.value == "TEXTURE" and isinstance(val, Node):
            fname = attr_values(val, "FILE")
            if fname and isinstance(fname[0], str):
                name = fname[0]
                for d in texture_dirs:
                    hit = next(d.rglob(name), None)
                    if hit is not None:
                        return hit, name
    return None


class GltfBuilder:
    def __init__(self, name: str):
        self.json = {
            "asset": {"version": "2.0", "generator": "zss zrb_to_gltf"},
            "scenes": [{"nodes": [0]}], "scene": 0,
            "nodes": [], "meshes": [], "accessors": [], "bufferViews": [],
            "materials": [], "textures": [], "images": [],
            "samplers": [{"magFilter": 9729, "minFilter": 9987,
                          "wrapS": 10497, "wrapT": 10497}],
        }
        self.bin = bytearray()
        self.material_cache: dict[str, int] = {}

    def _view(self, data: bytes, target: int) -> int:
        pad = (4 - len(self.bin) % 4) % 4
        self.bin += b"\x00" * pad
        off = len(self.bin)
        self.bin += data
        self.json["bufferViews"].append(
            {"buffer": 0, "byteOffset": off, "byteLength": len(data), "target": target})
        return len(self.json["bufferViews"]) - 1

    def add_material(self, tex_path: Path, out_dir: Path) -> int:
        key = tex_path.name
        if key in self.material_cache:
            return self.material_cache[key]
        png = out_dir / (tex_path.stem + ".png")
        if Image is not None:
            Image.open(tex_path).save(png)
        img_idx = len(self.json["images"])
        self.json["images"].append({"uri": png.name})
        self.json["textures"].append({"sampler": 0, "source": img_idx})
        mat_idx = len(self.json["materials"])
        self.json["materials"].append({
            "name": tex_path.stem,
            "pbrMetallicRoughness": {
                "baseColorTexture": {"index": len(self.json["textures"]) - 1},
                "metallicFactor": 0.0, "roughnessFactor": 1.0},
            "doubleSided": True})
        self.material_cache[key] = mat_idx
        return mat_idx

    def add_mesh(self, mesh_list: Node, tex_path: Path | None, out_dir: Path) -> int | None:
        verts: list[list[float]] = []
        faces: list[list[int]] = []
        for sym, vals in pairs(mesh_list):
            if sym == "VERTEX" and len(vals) >= 8 and all(isinstance(v, float) for v in vals[:8]):
                verts.append(vals[:8])
            elif sym == "TRIANGLE" and len(vals) >= 3:
                faces.append(vals[:3])
        if not verts or not faces:
            return None
        if max(i for f in faces for i in f) >= len(verts):
            return None

        pos = [v for vert in verts for v in vert[0:3]]
        uv = [v for vert in verts for v in (vert[3], 1.0 - vert[4])]
        nrm = [v for vert in verts for v in vert[5:8]]
        idx = [i for f in faces for i in f]
        n = len(verts)

        pv = self._view(struct.pack(f"<{n*3}f", *pos), 34962)
        self.json["accessors"].append({"bufferView": pv, "componentType": 5126,
                                       "count": n, "type": "VEC3"})
        pacc = len(self.json["accessors"]) - 1
        uvv = self._view(struct.pack(f"<{n*2}f", *uv), 34962)
        self.json["accessors"].append({"bufferView": uvv, "componentType": 5126,
                                       "count": n, "type": "VEC2"})
        uacc = len(self.json["accessors"]) - 1
        nv = self._view(struct.pack(f"<{n*3}f", *nrm), 34962)
        self.json["accessors"].append({"bufferView": nv, "componentType": 5126,
                                       "count": n, "type": "VEC3"})
        nacc = len(self.json["accessors"]) - 1
        iv = self._view(struct.pack(f"<{len(idx)}H", *idx), 34963)
        self.json["accessors"].append({"bufferView": iv, "componentType": 5123,
                                       "count": len(idx), "type": "SCALAR"})
        iacc = len(self.json["accessors"]) - 1

        mat = self.add_material(tex_path, out_dir) if tex_path else 0
        self.json["meshes"].append({"primitives": [{
            "attributes": {"POSITION": pacc, "NORMAL": nacc, "TEXCOORD_0": uacc},
            "indices": iacc, "material": mat}]})
        return len(self.json["meshes"]) - 1

    def finish(self, out_path: Path) -> None:
        if not self.json["meshes"]:
            raise ValueError("no meshes")
        js = json.dumps(self.json, separators=(",", ":")).encode()
        js += b" " * ((4 - len(js) % 4) % 4)
        self.bin += b"\x00" * ((4 - len(self.bin) % 4) % 4)
        total = 12 + 8 + len(js) + 8 + len(self.bin)
        out = struct.pack("<III", 0x46546C67, 2, total)
        out += struct.pack("<II", len(js), 0x4E4F534A) + js       # "JSON"
        out += struct.pack("<II", len(self.bin), 0x004E4942) + self.bin  # "BIN\0"
        out_path.write_bytes(out)


def convert_file(src: Path, out_dir: Path, symbols, texture_dirs: list[Path]) -> Path | None:
    forest = parse_file(src, symbols)
    znodes = [n for n in forest if head(n) == "NODE"]
    if not znodes:
        return None
    b = GltfBuilder(src.stem)
    b.json["nodes"].append({"name": src.stem, "children": []})

    tex = find_texture_file(znodes[0], texture_dirs)
    by_name: dict[str, int] = {}
    reparent: dict[int, str] = {}
    mesh_containers = ("MESH", "FF77")
    for z in znodes:
        names = attr_values(z, "NAME")
        nm = str(names[0]) if names and isinstance(names[0], str) else None
        g = len(b.json["nodes"])
        entry: dict = {"name": nm or f"node{g}", "children": []}
        b.json["nodes"].append(entry)
        b.json["nodes"][0]["children"].append(g)
        if nm:
            by_name[nm] = g
        tr = attr_values(z, "TRANSLATION")
        if len(tr) == 3:
            entry["translation"] = [round(float(v), 6) for v in tr]
        rot = attr_values(z, "ROTATION")
        if len(rot) == 4:  # quaternion (x y z w)
            entry["rotation"] = [round(float(v), 6) for v in rot]
        elif len(rot) == 3 and any(float(v) != 0 for v in rot):
            entry["rotation"] = [round(v, 6) for v in euler_xyz_deg_to_quat(*map(float, rot))]
        sc = attr_values(z, "SCALE")
        if len(sc) == 3 and any(float(v) != 1 for v in sc):
            entry["scale"] = [round(float(v), 6) for v in sc]
        par = attr_values(z, "PARENT")
        if par and isinstance(par[0], str):
            reparent[g] = par[0]
        node_tex = find_texture_file(z, texture_dirs) or tex
        for i in range(len(z) - 1):
            sym, val = z[i], z[i + 1]
            if (isinstance(sym, Token) and sym.kind == "w"
                    and sym.value in mesh_containers and isinstance(val, Node)):
                m = b.add_mesh(val, node_tex[0] if node_tex else None, out_dir)
                if m is not None:
                    entry.setdefault("mesh", m)

    for g, pname in reparent.items():
        if pname in by_name and pname != b.json["nodes"][g]["name"]:
            if g in b.json["nodes"][0]["children"]:
                b.json["nodes"][0]["children"].remove(g)
            b.json["nodes"][by_name[pname]]["children"].append(g)

    out = out_dir / f"{src.stem}.glb"
    try:
        b.finish(out)
    except ValueError:
        return None
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("src", type=Path)
    ap.add_argument("out", type=Path)
    ap.add_argument("--symbols", type=Path, required=True)
    ap.add_argument("--texture-dirs", type=Path, nargs="+", required=True)
    args = ap.parse_args()
    symbols = load_symbols(args.symbols)
    args.out.mkdir(parents=True, exist_ok=True)
    files = sorted(args.src.rglob("*.zrb")) if args.src.is_dir() else [args.src]
    ok = skip = fail = 0
    for f in files:
        try:
            res = convert_file(f, args.out, symbols, args.texture_dirs)
        except Exception as e:  # noqa: BLE001
            print(f"FAIL {f.name}: {e}")
            fail += 1
            continue
        ok += res is not None
        skip += res is None
    print(f"converted {ok}, skipped {skip}, failed {fail} -> {args.out}")


if __name__ == "__main__":
    main()
