class_name UnitDefs
extends RefCounted
## Unit content tables. To add a unit type: drop its sprite folder under
## `assets/z/` following the naming conventions (see
## docs/ASSET_CONVENTIONS.md) and add an entry here. Entries are plain
## dictionaries so generated content (tools, AI asset gen) can extend them.
##
## Fields: hp, damage, range, cooldown, speed, cost, dir (sprite folder),
## projectile (optional: {speed, sprite, impact} — damage lands on impact
## instead of instantly).

const ROBOTS := {
	"grunt":  {"hp": 42, "damage": 4,  "range": 58.0,  "cooldown": 0.75, "speed": 60.0, "cost": 40,
		"dir": "res://assets/z/robots_grunt", "sound": "RIFLE3", "pop": 1},
	"psycho": {"hp": 46, "damage": 3,  "range": 58.0,  "cooldown": 0.40, "speed": 62.0, "cost": 60,
		"dir": "res://assets/z/robots_psycho", "sound": "MACHGUN2", "pop": 1},
	"sniper": {"hp": 34, "damage": 15, "range": 110.0, "cooldown": 1.80, "speed": 58.0, "cost": 80,
		"dir": "res://assets/z/robots_sniper", "sound": "RIFLE3", "pop": 1},
	"tough":  {"hp": 72, "damage": 8,  "range": 50.0,  "cooldown": 1.10, "speed": 50.0, "cost": 70,
		"dir": "res://assets/z/robots_tough", "sound": "GRENLOBX", "pop": 1},
	"pyro":   {"hp": 52, "damage": 6,  "range": 40.0,  "cooldown": 0.60, "speed": 56.0, "cost": 70,
		"dir": "res://assets/z/robots_pyro", "sound": "FLAMER", "pop": 1},
	"laser":  {"hp": 44, "damage": 10, "range": 85.0,  "cooldown": 1.30, "speed": 56.0, "cost": 90,
		"dir": "res://assets/z/robots_laser", "sound": "LASERGUN", "pop": 1},
}

const VEHICLES := {
	"jeep":   {"hp": 60,  "damage": 5,  "range": 62.0, "cooldown": 0.55, "speed": 95.0, "cost": 60,
		"dir": "res://assets/z/vehicles_jeep", "sound": "JEEPMGUN", "pop": 2},
	"light":  {"hp": 90,  "damage": 9,  "range": 78.0, "cooldown": 1.00, "speed": 75.0, "cost": 100,
		"dir": "res://assets/z/vehicles_light", "sound": "LTANKGUN", "pop": 2,
		"projectile": {"speed": 300.0, "impact": "impact", "texture": "res://assets/z/vehicles_light/bullet.png"}},
	"medium": {"hp": 130, "damage": 14, "range": 88.0, "cooldown": 1.40, "speed": 62.0, "cost": 150,
		"dir": "res://assets/z/vehicles_medium", "sound": "MTANKGUN", "pop": 3,
		"projectile": {"speed": 280.0, "impact": "impact", "texture": "res://assets/z/vehicles_light/bullet.png"}},
	"heavy":  {"hp": 190, "damage": 22, "range": 96.0, "cooldown": 2.00, "speed": 50.0, "cost": 220,
		"dir": "res://assets/z/vehicles_heavy", "sound": "HTANKGUN", "pop": 4,
		"projectile": {"speed": 240.0, "impact": "impact", "texture": "res://assets/z/vehicles_light/bullet.png"}},
	"apc":    {"hp": 150, "damage": 0,  "range": 0.0,  "cooldown": 9.9,  "speed": 80.0, "cost": 120,
		"dir": "res://assets/z/vehicles_apc", "sound": "", "pop": 3},
	"missile_launcher": {"hp": 110, "damage": 20, "range": 180.0, "cooldown": 3.00, "speed": 55.0, "cost": 200,
		"dir": "res://assets/z/vehicles_missile_launcher", "sound": "MOBIMIS2", "pop": 3,
		"projectile": {"speed": 190.0, "impact": "explosion",
			"texture": "res://assets/z/vehicles_missile_launcher/bullet.png"}},
}

const CANNONS := {
	"gatling":  {"hp": 55, "damage": 3,  "range": 95.0,  "cooldown": 0.35, "speed": 0.0, "cost": 0,
		"dir": "res://assets/z/cannons_gatling", "sound": "GATTGUN", "pop": 2},
	"gun":      {"hp": 75, "damage": 8,  "range": 110.0, "cooldown": 0.90, "speed": 0.0, "cost": 0,
		"dir": "res://assets/z/cannons_gun", "sound": "LTGUN", "pop": 2,
		"projectile": {"speed": 320.0, "sprite": "shell", "impact": "impact"}},
	"howitzer": {"hp": 80, "damage": 18, "range": 170.0, "cooldown": 2.60, "speed": 0.0, "cost": 0,
		"dir": "res://assets/z/cannons_howitzer", "sound": "GRENLOBX", "pop": 3,
		"projectile": {"speed": 200.0, "sprite": "shell", "impact": "impact"}},
	"missile_cannon": {"hp": 70, "damage": 26, "range": 200.0, "cooldown": 3.40, "speed": 0.0, "cost": 0,
		"dir": "res://assets/z/cannons_missile", "sound": "MOBIMISS", "pop": 3,
		"projectile": {"speed": 170.0, "impact": "explosion",
			"texture": "res://assets/z/cannons_missile/bullet.png"}},
}

## Defaults used when ContentDB auto-registers a sprite folder that has no
## entry above (drop a folder in, get a playable unit, tune stats later).
const ROBOT_DEFAULTS := {"hp": 42, "damage": 4, "range": 58.0, "cooldown": 0.75, "speed": 60.0, "cost": 40}
const VEHICLE_DEFAULTS := {"hp": 90, "damage": 8, "range": 78.0, "cooldown": 1.00, "speed": 70.0, "cost": 100}
const CANNON_DEFAULTS := {"hp": 70, "damage": 8, "range": 110.0, "cooldown": 1.00, "speed": 0.0, "cost": 0}

## Zod map object id -> type name (tools/zod/map_to_json.py header).
const MAP_ROBOT_IDS := ["grunt", "psycho", "sniper", "tough", "pyro", "laser"]
const MAP_VEHICLE_IDS := ["jeep", "light", "medium", "heavy", "apc", "missile_launcher", "crane"]
const MAP_CANNON_IDS := ["gatling", "gun", "howitzer", "missile_cannon"]

## Table + defaults per kind ("robot" | "vehicle" | "cannon").
static func table_for(kind: String) -> Dictionary:
	match kind:
		"robot": return ROBOTS
		"vehicle": return VEHICLES
		"cannon": return CANNONS
	return ROBOTS


static func defaults_for(kind: String) -> Dictionary:
	match kind:
		"robot": return ROBOT_DEFAULTS
		"vehicle": return VEHICLE_DEFAULTS
		"cannon": return CANNON_DEFAULTS
	return ROBOT_DEFAULTS
