#!/usr/bin/env python3
"""Generates the per-type unit scenes (Phase 4).

Base scenes (scenes/unit.tscn, scenes/vehicle.tscn) stay hand-maintained;
this writes the inherited per-type scenes under scenes/{units,vehicles,
cannons}/ that carry identity (kind + unit_name) and the zod DoRender
turret tables (exported arrays on the root). Re-run after adding a unit
type that needs turret offsets; plain unit scenes can also be created by
hand — the convention is scenes/<kind-plural>/<name>.tscn.
"""
import os

ROOT = os.path.join(os.path.dirname(__file__), "..", "project")

TURRET = {
    "light": {"hull": [(2,0),(0,0),(-2,0),(0,0),(2,0),(0,0),(-2,0),(0,0)],
              "aim": [(0,-2),(0,-2),(0,-1),(-1,0),(0,0),(0,0),(0,1),(1,-2)],
              "scans": True},
    "medium": {"hull": [(0,0),(0,6),(-1,0),(-2,6),(0,0),(0,6),(-1,0),(-2,6)],
               "aim": [(4,-5),(5,-3),(7,-4),(5,-5),(2,-5),(6,-5),(7,-5),(5,-5)],
               "scans": True},
    "heavy": {"hull": [(4,0),(2,-3),(-1,-5),(-3,-4),(4,0),(2,-3),(-1,-5),(-3,-4)],
              "aim": [(4,0),(0,-2),(0,-2),(0,-2),(-4,0),(0,0),(0,0),(0,0)],
              "scans": True},
    "apc": {"hull": [(1,5),(5,8),(9,5),(13,8),(15,5),(11,3),(8,3),(5,4)],
            "aim": [], "scans": True},
    "missile_launcher": {"hull": [(0,0),(2,3),(3,0),(8,4),(9,0),(7,-2),(2,-3),(0,-3)],
                         "aim": [(2,0),(0,0),(0,0),(0,-2),(0,-2),(-2,0),(0,2),(0,-2)],
                         "scans": True},
    "jeep": {"hull": [(0,2),(6,7),(12,4),(20,8),(25,2),(20,-4),(15,-3),(5,-4)],
             "aim": [(0,0),(-2,0),(-5,0),(-8,0),(-10,0),(-8,5),(-5,6),(-2,5)],
             "scans": False},
}


def pva(points):
    flat = []
    for x, y in points:
        flat += [float(x), float(y)]
    return "PackedVector2Array(" + ", ".join(f"{v:.1f}" for v in flat) + ")"


def scene(root_name, base_path, props):
    lines = [
        "[gd_scene load_steps=2 format=3]\n",
        f'[ext_resource type="PackedScene" path="{base_path}" id="1_base"]\n',
        f'\n[node name="{root_name}" instance=ExtResource("1_base")]\n',
    ]
    for key, value in props:
        lines.append(f"{key} = {value}\n")
    return "".join(lines)


def write(path, content):
    full = os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w") as f:
        f.write(content)
    print("wrote", path)


ROBOTS = ["grunt", "psycho", "sniper", "tough", "pyro", "laser"]
VEHICLES = ["jeep", "light", "medium", "heavy", "apc", "missile_launcher", "crane"]
CANNONS = ["gatling", "gun", "howitzer", "missile_cannon"]

for name in ROBOTS:
    write(f"scenes/units/{name}.tscn",
          scene(name.capitalize(), "res://scenes/unit.tscn",
                [("unit_name", f'"{name}"')]))

for name in VEHICLES:
    props = [("unit_name", f'"{name}"'), ("kind", '"vehicle"')]
    table = TURRET.get(name)
    if table:
        props += [
            ("turret_hull_off", pva(table["hull"])),
            ("turret_aim_off", pva(table["aim"])),
            ("turret_scans", "true" if table["scans"] else "false"),
        ]
    write(f"scenes/vehicles/{name}.tscn",
          scene(name.capitalize(), "res://scenes/vehicle.tscn", props))

for name in CANNONS:
    write(f"scenes/cannons/{name}.tscn",
          scene(name.capitalize(), "res://scenes/vehicle.tscn",
                [("unit_name", f'"{name}"'), ("kind", '"cannon"')]))
