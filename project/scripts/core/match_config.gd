class_name MatchConfig
extends Resource
## Everything a match needs to start — ONE typed entry for skirmish,
## campaign, continue and the MP lobby. Previously each screen hand-
## rolled the chain (Campaign.active, GameState.reset_for_new_map,
## next_map, player_team, pending_load) and the paths had already
## diverged (an MP match leaked player_team into the next skirmish).
## GameState.prepare_match(cfg) applies it; match.gd consumes as before.
## In multiplayer the SAME config travels over the wire (Net.started).


@export var source := "skirmish"  # skirmish | campaign | continue | multiplayer
@export var map_path := ""
@export var player_team := 1
@export var save_data: Dictionary = {}  # non-empty = restore after spawn


static func make(src: String, map_path_value: String,
		player_team_value := 1, save := {}) -> MatchConfig:
	var cfg := MatchConfig.new()
	cfg.source = src
	cfg.map_path = map_path_value
	cfg.player_team = player_team_value
	cfg.save_data = save
	return cfg
