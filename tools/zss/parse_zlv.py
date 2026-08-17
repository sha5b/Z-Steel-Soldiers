#!/usr/bin/env python3
"""Parse a decrypted Z: Steel Soldiers .zlv level file into JSON.

The .zlv format is plaintext s-expressions using a head(values) pair
grammar — the text form of the same language as binary .zrb files:

    ( leveldata (
        worldtype("Desert") mapsize(256,256) waterlevel(49)
        objectlist (
            completeobject (
                objectentry("Command Centre",147.5,0.0,162.5)
                objectteam(2) setobjectlevel(4)
                shedslotentry( completeobject(...) )
            )
        )
    ) )

Output JSON: {"settings": {..}, "objects": [..]} where settings flattens
scalar pairs and objects mirrors the completeobject hierarchy (garrisoned
units nested under "slots").

Usage: parse_zlv.py LEVEL.zlv [OUT.json]
"""
import json
import re
import sys
from pathlib import Path

TOKEN = re.compile(r'\(|\)|"(?:[^"\\]|\\.)*"|[^\s()",]+')
NESTED_KEYS = {"objectlist", "shedslotentry", "completeobject", "incompleteobject"}


def lex(text: str) -> list[str]:
    return [t for t in TOKEN.findall(text) if t != ","]


def parse(tokens: list[str], pos: int = 0):
    if pos >= len(tokens):
        raise ValueError("unexpected EOF")
    tok = tokens[pos]
    if tok == "(":
        out, pos = [], pos + 1
        while tokens[pos] != ")":
            val, pos = parse(tokens, pos)
            out.append(val)
        return out, pos + 1
    if tok.startswith('"'):
        return tok[1:-1].replace('\\"', '"'), pos + 1
    for conv in (int, float):
        try:
            return conv(tok), pos + 1
        except ValueError:
            pass
    return tok, pos + 1


def pairs_to_dict(items: list, out: dict) -> None:
    """Convert alternating head/value items into a dict; repeated heads
    accumulate into lists; nested containers recurse."""
    i = 0
    while i < len(items):
        head = items[i]
        val = items[i + 1] if i + 1 < len(items) else None
        if not isinstance(head, str) or val is None:
            i += 1
            continue
        if isinstance(val, list):
            if head in NESTED_KEYS:
                sub: dict = {}
                pairs_to_dict(val, sub)
                val = sub
            elif any(isinstance(v, list) and v and isinstance(v[0], str) and v[0] in NESTED_KEYS
                     for v in val):
                # bare container contents (e.g. objectlist's list)
                sub = {}
                pairs_to_dict(val, sub)
                val = sub
        if head in out:
            if not isinstance(out[head], list) or not isinstance(out[head][0], dict) and isinstance(val, dict):
                out[head] = [out[head]]
            out[head].append(val)
        else:
            out[head] = val
        i += 2


def extract_objects(d: dict, out: list) -> None:
    for key, val in d.items():
        if key == "completeobject":
            entries = val if isinstance(val, list) else [val]
            for obj in entries:
                if not isinstance(obj, dict):
                    continue
                entry = dict(obj)
                slots: list = []
                extract_objects(obj, slots)
                if slots:
                    entry["slots"] = slots
                out.append(entry)
        elif isinstance(val, dict):
            extract_objects(val, out)
        elif isinstance(val, list) and val and isinstance(val[0], dict):
            for item in val:
                extract_objects(item, out)


def convert(path: Path) -> dict:
    tree, _ = parse(lex(path.read_text(encoding="latin-1")))
    # tree = ['leveldata', [pairs...]]
    root: dict = {}
    for item in tree if isinstance(tree, list) else [tree]:
        if isinstance(item, list):
            pairs_to_dict(item, root)
    settings = {k: v for k, v in root.items() if k != "objectlist"}
    objects: list = []
    extract_objects(root.get("objectlist", {}), objects)
    return {"source": path.name, "settings": settings, "objects": objects}


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    src = Path(sys.argv[1])
    dst = Path(sys.argv[2]) if len(sys.argv) > 2 else src.with_suffix(".json")
    data = convert(src)
    dst.write_text(json.dumps(data, indent=1))
    print(f"{src.name}: {len(data['objects'])} objects, "
          f"{len(data['settings'])} settings -> {dst}")


if __name__ == "__main__":
    main()
