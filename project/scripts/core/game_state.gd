extends Node
## Autoload (GameState): match FLOW — which map is loaded/next, the
## pending save, win/lose detection, the reset ritual. The economy lives
## in MatchState, pathing in NavWorld, saves in SaveSystem.

signal game_over(winning_team: int)

var over := false
var next_map := ""
var current_map := ""
var pending_load: Dictionary = {}  # applied by the map after spawning


func reset_for_new_map() -> void:
	over = false
	MatchState.reset()
	NavWorld.reset()
	pending_load = {}
	SelectionManager.clear_selection()  # drop freed units from the old map


## Save IO lives in the SaveSystem autoload; GameState keeps the match
## flow (pending_load applied by the map after spawning).
func save_game() -> bool:
	return SaveSystem.save_game()


func has_save() -> bool:
	return SaveSystem.has_save()


func read_save() -> Dictionary:
	return SaveSystem.read_save()


## Win condition: the player only wins when EVERY enemy fort is gone —
## not when the first one falls (multiplayer maps carry up to 8 forts).
func report_fort_destroyed(losing_team: int) -> void:
	if over:
		return
	if losing_team == MatchState.player_team:
		over = true
		var winner := 2
		for t in MatchState.money:
			if t != losing_team:
				winner = t
				break
		game_over.emit(winner)
		return
	var enemy_forts := 0
	for b in Engine.get_main_loop().root.get_tree().get_nodes_in_group("buildings"):
		if b is Building2D and b.alive and b.is_fort 				and b.team != 0 and b.team != MatchState.player_team:
			enemy_forts += 1
	if enemy_forts == 0:
		over = true
		game_over.emit(MatchState.player_team)
