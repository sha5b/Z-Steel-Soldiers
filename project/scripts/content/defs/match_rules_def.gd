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
## Crate upgrades. A team that collects a grenade crate hits harder with
## ROBOTS, a rocket crate with HARDWARE (vehicles + cannons). These were
## documented behaviour with no implementation anywhere: `upgrade_key`
## was unset on both crates, so grant_upgrade never fired, has_upgrade
## was permanently false and no damage multiplier existed in combat.
@export var grenade_damage_bonus := 0.4   # +40% robot damage
@export var rocket_damage_bonus := 0.6    # +60% vehicle/cannon damage
## VETERANCY. A unit that survives fights gets better at them: every
## rank adds damage and accuracy. The kill counts are the rank steps
## (3 ranks by default), and the two bonuses are PER RANK.
## Remake values — the original ships no table for this in the asset
## pack, so they are deliberately small and tunable here rather than
## guessed at in code.
## Robots handed to a fort team that starts a map with NO units at all.
## The retail levels name their starting armies in `preset1.wal` /
## `preset2.wal` and NEITHER FILE SHIPS in the release (Z.exe only holds
## the string), so a converted campaign map arrives with forts,
## factories and derelict hardware but no crew. Without this a mission
## can be lost the moment your first robot dies (the original
## no-units rule), which is not a game. Zod maps come with their own
## rosters and never trigger it.
@export var starting_squad := 3
@export var veteran_kill_steps: Array[int] = [2, 5, 9]
@export var veteran_damage_bonus := 0.12   # +12% damage per rank
@export var veteran_hit_bonus := 0.04      # +4 percentage points to hit
