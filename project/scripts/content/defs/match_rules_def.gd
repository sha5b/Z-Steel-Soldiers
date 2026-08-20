class_name MatchRulesDef
extends Resource
## Economy and match rule values — content/match/default.tres, the
## same payload a multiplayer match agrees on. Values mirror the
## original zsettings; tuning happens in the Inspector, not in code.

@export var income_per_zone := 1.0      # money per owned zone per tick
@export var level_seconds := 150.0      # tech ladder: ~2.5 min per level
@export var starting_money := 200
@export var capture_seconds := 2.0      # zone flip presence time
@export var apc_capacity := 3           # robots per transport
