class_name UnitDef
extends Resource
## One unit type (robot, vehicle or cannon) — the .tres files under
## content/{units,vehicles,cannons}/ are the editable source of truth.
## To add a unit: copy a .tres next to its siblings, point asset_dir at a
## sprite folder following docs/ASSET_CONVENTIONS.md, tune the stats.

@export var id := "grunt"  # unit name used everywhere (build lists, maps)
@export var kind := "robot"  # robot | vehicle | cannon
@export var asset_dir := ""  # sprite folder (AnimLibrary conventions)
@export var sound := ""  # GOG wav name for the weapon report

@export_group("Stats")
@export var hp := 42
@export var damage := 4
@export var range_px := 58.0
@export var cooldown := 0.75
@export var speed := 60.0
@export var cost := 40
@export var build_time := 60.0  # seconds (zsettings.cpp SetDefaults)
@export var pop := 1  # population cap cost
@export var hit_chance := 1.0  # per-shot chance (original zsettings)
@export var snipe_chance := 0.0  # driver kill while the target's lid is open
@export var splash_radius := 0.0  # explosive splash; 0 = none

## Weapon behaviour: "hitscan" (tracer), "laser" (beam), "shell"
## (travelling projectile + splash). Empty = auto: projectile def means
## shell, otherwise hitscan.
@export var weapon := ""
@export var projectile: ProjectileDef = null  # null = hitscan
@export var scene: PackedScene = null  # per-type scene (Phase 4); null = base
