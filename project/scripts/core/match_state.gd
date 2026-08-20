class_name MatchState
extends Node
## The match economy and its rules — team money and zone income,
## upgrades, population caps, AI difficulty, and the zone registry that
## feeds income. A CHILD OF THE MATCH SCENE (not an autoload): each
## match owns its economy and dies with it — see NavWorld for the
## locator pattern. Launch config (player_team, difficulty) reaches the
## fresh instance through GameState.pending_config (applied by match.gd).

## The active match's economy (set on _ready, cleared on exit).
static var current: MatchState


func _ready() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null

signal money_changed(team: int, amount: int)
signal zone_captured(team: int)
signal tech_level_changed

const INCOME_PER_ZONE := 1.0
const LEVEL_SECONDS := 150.0  # original: forts/factories tech up over match TIME (~2.5 min/level)

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
	_facilities.clear()


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
	for b in _facilities:
		if is_instance_valid(b) and b.alive and b.owner_team != 0 and b.level < 5:
			var new_level: int = clampi(want, b.level, 5)
			if new_level > b.level:
				b.level = new_level
				bumped = true
	if bumped:
		tech_level_changed.emit()


## Facilities register on spawn / unregister on exit — the tech tick
## iterates this array instead of walking the whole scene tree from an
## autoload every second.
var _facilities: Array[Building2D] = []


func register_facility(b: Building2D) -> void:
	if not _facilities.has(b):
		_facilities.append(b)


func unregister_facility(b: Building2D) -> void:
	_facilities.erase(b)


func player_money() -> int:
	return money.get(player_team, 0)


func spend(team: int, amount: int) -> bool:
	if money.get(team, 0) < amount:
		return false
	money[team] -= amount
	money_changed.emit(team, money[team])
	return true


## Single-writer economy API: nothing outside this file writes `money`
## directly (loader ledgers, building refunds, save restore all went
## through here — direct writes from three layers once hid refund bugs).
func deposit(team: int, amount: int) -> void:
	money[team] = money.get(team, 0) + amount
	money_changed.emit(team, money[team])


func set_money(team: int, amount: int) -> void:
	money[team] = amount
	money_changed.emit(team, amount)


func grant_ledger(team: int, start := 200) -> void:
	if not money.has(team):
		set_money(team, start)


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
	for u in UnitRegistry.current.of_team(team):
		used += ContentDB.def_for(u.kind, u.unit_name).pop
	return used


func unit_cap(team: int) -> int:
	# base 25 + one per owned zone (original zsettings)
	var zones_owned := 0
	for z in zones:
		if z.owner_team == team:
			zones_owned += 1
	return 25 + zones_owned
