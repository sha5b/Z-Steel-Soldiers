#!/usr/bin/env python3
"""Shared parser for Z: Steel Soldiers binary token files (.zrb, .z2, ...).

Grammar (token stream after the 4-byte "ZRB\\0" magic):

    00 <u8>     small unsigned integer atom
    01 <u16>    unsigned integer atom
    03 <f32>    float atom
    04 <cstr>   string atom
    05          list open  '('
    06          list close ')'
    07          "file" head (root symbol)
    XX          symbol atom; name = symbol_table[XX - 7]
    ff XX       escaped symbol atom (runtime enum id; only partly mapped)

The symbol table comes from the demo's Symbols/zrc_symbols.h (zrSymbol v22)
offset by 7 -- the runtime enum grew 7 leading entries versus the shipped
script-symbol version. FF-escaped ids diverge further; known ones:
82 = TRIANGLE (three vertex indices).
"""
import re
import struct
from pathlib import Path

KNOWN_FF = {82: "TRIANGLE"}

T_OPEN, T_CLOSE = 5, 6


def load_symbols(symbols_dir: Path) -> dict[int, str]:
    src = (symbols_dir / "zrc_symbols.h").read_text(encoding="latin-1")
    ids = re.findall(r"zrID_([A-Z_0-9]+)\s*(?:=\s*(\d+))?\s*(?://[^\n]*)?,", src)
    table: dict[int, str] = {}
    v = 0
    for name, val in ids:
        v = int(val) if val else v
        table[v + 7] = name
        v += 1
    return table


class Token:
    __slots__ = ("kind", "value")

    def __init__(self, kind: str, value):
        self.kind, self.value = kind, value

    def __repr__(self) -> str:  # pragma: no cover - debugging aid
        return f"{self.kind}:{self.value!r}"


def tokenize(data: bytes, symbols: dict[int, str]) -> list[Token]:
    if data[:4] != b"ZRB\x00":
        raise ValueError("not a ZRB file")
    out: list[Token] = []
    i, n = 4, len(data)
    while i < n:
        b = data[i]
        i += 1
        if b == 0:
            out.append(Token("u", data[i])); i += 1
        elif b == 1:
            out.append(Token("u", int.from_bytes(data[i:i + 2], "little"))); i += 2
        elif b == 3:
            out.append(Token("f", struct.unpack("<f", data[i:i + 4])[0])); i += 4
        elif b == 4:
            j = data.find(b"\x00", i)
            out.append(Token("s", data[i:j].decode("latin-1"))); i = j + 1
        elif b == T_OPEN:
            out.append(Token("(", None))
        elif b == T_CLOSE:
            out.append(Token(")", None))
        elif b == 7:
            out.append(Token("w", "FILE"))
        elif b == 0xFF:
            out.append(Token("w", KNOWN_FF.get(data[i], f"FF{data[i]}"))); i += 1
        else:
            out.append(Token("w", symbols.get(b, f"?{b}")))
    return out


class Node(list):
    """S-expression list; node[0] is the head Token when parsed from (head ...)."""


def build_forest(tokens: list[Token]) -> list[Node]:
    """A ZRB stores top-level sibling lists (one per node), linked by
    PARENT(name) attributes rather than nesting."""
    roots: list[Node] = []
    stack: list[Node] = []
    for t in tokens:
        if t.kind == "(":
            new = Node()
            if stack:
                stack[-1].append(new)
            stack.append(new)
        elif t.kind == ")":
            fin = stack.pop()
            if not stack:
                roots.append(fin)
        else:
            if not stack:  # leading FILE token before the first list
                continue
            stack[-1].append(t)
    if stack:
        raise ValueError(f"unbalanced tree ({len(stack)} open)")
    return roots


def parse_file(path: Path, symbols: dict[int, str]) -> list[Node]:
    return build_forest(tokenize(path.read_bytes(), symbols))


def head(node: Node) -> str:
    """Symbol name of a list's head, '' for non-symbol heads."""
    if node and isinstance(node[0], Token) and node[0].kind == "w":
        return node[0].value
    return ""


def atoms(node: Node) -> list:
    return [t.value for t in node if isinstance(t, Token)]


def find_all(node: Node, name: str) -> list[Node]:
    out = []
    for child in node:
        if isinstance(child, Node):
            if head(child) == name:
                out.append(child)
            out.extend(find_all(child, name))
    return out


def find_first(node: Node, name: str):
    found = find_all(node, name)
    return found[0] if found else None


def pairs(node: Node):
    """Yield (symbol, values) for the recursive SYM ( vals ) pair grammar.

    Every container list stores alternating Token(symbol) / Node(values)
    children, exactly like the text form ``worldtype("Desert")``.
    """
    i = 0
    while i + 1 < len(node):
        sym, val = node[i], node[i + 1]
        if isinstance(sym, Token) and sym.kind == "w" and isinstance(val, Node):
            yield sym.value, [t.value for t in val if isinstance(t, Token)]
        i += 2


def attr_values(node: Node, name: str) -> list:
    """Values of the first SYM ( vals ) pair named ``name`` inside node."""
    for sym, vals in pairs(node):
        if sym == name:
            return vals
    return []
