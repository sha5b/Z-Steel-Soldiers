extends Node
## Autoload (GameState): match FLOW — which map is loaded/next, the
## pending save, win/lose detection, the reset ritual. The economy lives
## in MatchState, pathing in NavWorld, saves in SaveSystem.

signal game_over(winning_team: int)

var over := false
var next_map := ""
var current_map := ""
var pending_load: Dictionary = {}  # applied by the map after spawning
var _eliminated: Array[int] = []


func reset_for_new_map() -> void:
	over = false
	_eliminated.clear()
	MatchState.reset()
	# match-scoped subsystems are per-instance now — a fresh scene starts
	# clean; only an old instance (mid scene change) needs resetting
	if NavWorld.current:
		NavWorld.current.reset()
	if SelectionManager.current:
		SelectionManager.current.clear_selection()  # drop freed units
	pending_load = {}


## THE way into a match: apply a typed MatchConfig (skirmish, campaign,
## continue, multiplayer) and let the caller change the scene. Replaces
## four hand-rolled per-screen chains; MP sends the same config shape
## over the wire.
func prepare_match(cfg: MatchConfig) -> void:
	if cfg.source == "campaign":
		Campaign.active = true
	elif cfg.source != "continue":
		Campaign.active = false
	reset_for_new_map()
	next_map = cfg.map_path
	pending_load = cfg.save_data
	MatchState.player_team = cfg.player_team


## Save IO lives in the SaveSystem autoload; GameState keeps the match
## flow (pending_load applied by the map after spawning).
func save_game() -> bool:
	return SaveSystem.save_game()


func has_save() -> bool:
	return SaveSystem.has_save()


func read_save() -> Dictionary:
	return SaveSystem.read_save()


## Elimination (original CheckDestroyedFort): the moment ANY fort half
## of a team falls, the WHOLE team goes — every other object it owns is
## destroyed and all its zones turn neutral. Symmetric for the player
## and every AI team: one fallen half eliminates the owner, killing one
## enemy half is enough to defeat them.
func report_fort_destroyed(losing_team: int) -> void:
	if over or losing_team == 0 or losing_team in _eliminated:
		return
	_eliminated.append(losing_team)
	# registry entries can dangle (units freed without die(), e.g. the
	# save-restore roster swap) — validity comes FIRST, `is` on a freed
	# instance is a hard error
	for u in UnitRegistry.current.all_units().duplicate():
		if is_instance_valid(u) and u is Unit2D and u.team == losing_team and u.alive:
			u.die()
	for b in Engine.get_main_loop().root.get_tree() \
			.get_nodes_in_group("all_buildings").duplicate():
		if is_instance_valid(b) and b is Building2D \
				and b.owner_team == losing_team and b.alive:
			b.kill()
	for z in MatchState.zones.duplicate():
		if z.owner_team == losing_team:
			z.set_owner_team(0)
	_settle_outcome(losing_team)


## Original CheckNoUnitsDestroyFort: a team that has no alive robot,
## vehicle or cannon left loses every fort it still holds (and with
## them, the match). Polled from UnitRegistry.current.untrack.
func check_no_units(team: int) -> void:
	if over or team == 0 or team in _eliminated:
		return
	var has_fort := false
	for b in Engine.get_main_loop().root.get_tree() \
			.get_nodes_in_group("all_buildings"):
		if is_instance_valid(b) and b is Building2D and b.alive and b.is_fort \
				and b.team == team:
			has_fort = true
			break
	# carried units (garrisoned / riding an APC) exist too — a fort with
	# defenders inside must not self-destruct out from under them
	if has_fort and UnitRegistry.current.alive_of_team(team).is_empty():
		report_fort_destroyed(team)


func _settle_outcome(losing_team: int) -> void:
	if over:
		return
	if losing_team == MatchState.player_team:
		over = true
		var winner := 2
		for t in MatchState.money:
			if t != losing_team and not t in _eliminated:
				winner = t
				break
		game_over.emit(winner)
		return
	# the player wins when every OTHER team has been eliminated
	for b in Engine.get_main_loop().root.get_tree() \
			.get_nodes_in_group("all_buildings"):
		if is_instance_valid(b) and b is Building2D and b.alive and b.is_fort \
				and b.team != 0 and b.team != MatchState.player_team:
			return  # another team still fights on
	over = true
	game_over.emit(MatchState.player_team)
