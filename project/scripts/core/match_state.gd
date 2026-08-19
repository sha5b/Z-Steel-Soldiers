extends Node
## Autoload (MatchState): the match economy and its rules — team money
## and zone income, upgrades with their damage multipliers, population
## caps, AI difficulty, and the zone registry that feeds income.

signal money_changed(team: int, amount: int)
signal zone_captured(team: int)

const INCOME_PER_ZONE := 1.0
var fast_build := false  # self-test lever: 2s builds regardless of defs

## What a right-click order DOES (set by the A/D/W hotkeys and the
## stance bar next to the minimap): MOVE ignores enemies en route,
## ATTACK_MOVE halts and engages, DEFEND walks there and holds the post.
enum OrderStance { MOVE, ATTACK_MOVE, DEFEND }
var order_stance: OrderStance = OrderStance.MOVE
## Smart idle (grab-hand toggle): idle robots auto-man nearby empty
## hardware and auto-walk to capturable flags (original auto_grab radii).
var auto_idle := true   # money per owned zone per tick
const TICK_SECONDS := 1.0

var map_root: Node2D = null  # where units and decals live (set at load)
var planet := "desert"
var player_team := 1
var ai_difficulty := 1  # 0 easy, 1 normal, 2 hard
var money := {1: 200, 2: 200, 3: 200, 4: 200}
var zones: Array[Node] = []
var upgrades := {}  # team -> {grenades: bool, rockets: bool}
var _accum := 0.0


func reset() -> void:
	zones.clear()
	over_reset()
	_accum = 0.0
	upgrades = {}


func over_reset() -> void:
	money = {1: 200, 2: 200, 3: 200, 4: 200}


func _process(delta: float) -> void:
	_accum += delta
	while _accum >= TICK_SECONDS:
		_accum -= TICK_SECONDS
		for team in money:
			var income := 0.0
			for z in zones:
				if z.owner_team == team:
					income += INCOME_PER_ZONE
			money[team] += int(income)
			money_changed.emit(team, money[team])


func player_money() -> int:
	return money.get(player_team, 0)


func spend(team: int, amount: int) -> bool:
	if money.get(team, 0) < amount:
		return false
	money[team] -= amount
	money_changed.emit(team, money[team])
	return true


func register_zone(zone: Node) -> void:
	zones.append(zone)


func notify_zone_captured(team: int) -> void:
	zone_captured.emit(team)


# ------------------------- upgrades -------------------------

func grant_upgrade(team: int, key: String) -> void:
	if not upgrades.has(team):
		upgrades[team] = {}
	upgrades[team][key] = true


func has_upgrade(team: int, key: String) -> bool:
	return upgrades.get(team, {}).get(key, false)


func robot_damage_mult(team: int) -> float:
	return 1.4 if has_upgrade(team, "grenades") else 1.0


func vehicle_damage_mult(team: int) -> float:
	return 1.4 if has_upgrade(team, "rockets") else 1.0


# ------------------------- population -------------------------

func unit_pop(team: int) -> int:
	var used := 0
	for u in UnitRegistry.of_team(team):
		used += ContentDB.def_for(u.kind, u.unit_name).pop
	return used


func unit_cap(team: int) -> int:
	# base 25 + one per owned zone (original zsettings)
	var zones_owned := 0
	for z in zones:
		if z.owner_team == team:
			zones_owned += 1
	return 25 + zones_owned
