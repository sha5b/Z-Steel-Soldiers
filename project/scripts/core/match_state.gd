extends Node
## Autoload (MatchState): the match economy and its rules — team money
## and zone income, upgrades with their damage multipliers, population
## caps, AI difficulty, and the zone registry that feeds income.

signal money_changed(team: int, amount: int)
signal zone_captured(team: int)
signal tech_level_changed

const INCOME_PER_ZONE := 1.0
const LEVEL_SECONDS := 150.0  # original: forts/factories tech up over match TIME (~2.5 min/level)
var fast_build := false  # self-test lever: 2s builds regardless of defs
var direct_step := false  # self-test lever: bypass move_and_slide (no physics ticks in tight loops)

## What a right-click order DOES (set by the Q/E/R hotkeys and the
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
var match_time := 0.0


func reset() -> void:
	zones.clear()
	over_reset()
	_accum = 0.0
	match_time = 0.0
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
		_tech_tick()


## ORIGINAL tech ladder (the game zod never implemented): every producer
## gains a build level as the match clock runs — the roster grows for
## EVERYONE over time, while zone ownership keeps its faithful role of
## speeding production (BuildTimeModified). Levels only rise, so a
## captured factory never loses tech.
func _tech_tick() -> void:
	match_time += TICK_SECONDS
	var want := int(match_time / LEVEL_SECONDS)
	if want <= 0:
		return
	var bumped := false
	for b in Engine.get_main_loop().root.get_tree().get_nodes_in_group("facilities"):
		if b is Building2D and b.alive and b.owner_team != 0 and b.level < 5:
			var new_level: int = clampi(want, b.level, 5)
			if new_level > b.level:
				b.level = new_level
				bumped = true
	if bumped:
		tech_level_changed.emit()


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
