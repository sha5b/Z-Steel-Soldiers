class_name Teams
extends Object
## Single source of truth for team identity: display name and the
## UI/minimap/zone colours. Team colour on SPRITES needs nothing from
## here — the original engine shipped its own recoloured art for every
## team (`<anim>_<team>_r<deg>.png`, verified pure colour swaps of the
## red set), and AnimLibrary loads those files directly per team.
## Add a team by adding an entry here plus the `_<team>` art variants.

## team id -> {name, ui accent, minimap blip/zone tint}
const TEAMS := {
	1: {"name": "red", "ui": Color(1.0, 0.25, 0.2), "mini": Color(1.0, 0.30, 0.25)},
	2: {"name": "blue", "ui": Color(0.25, 0.5, 1.0), "mini": Color(0.35, 0.55, 1.0)},
	3: {"name": "green", "ui": Color(0.3, 0.9, 0.3), "mini": Color(0.35, 0.85, 0.35)},
	4: {"name": "yellow", "ui": Color(1.0, 0.9, 0.2), "mini": Color(1.0, 0.9, 0.3)},
}

const NEUTRAL_ZONE_COLOR := Color(0.85, 0.85, 0.85, 0.9)


static func exists(team: int) -> bool:
	return TEAMS.has(team)


static func display_name(team: int) -> String:
	var info: Dictionary = TEAMS.get(team, {})
	return String(info.get("name", "null"))


static func ui_color(team: int) -> Color:
	var info: Dictionary = TEAMS.get(team, {})
	return info.get("ui", Color(0.8, 0.8, 0.8)) as Color


static func minimap_color(team: int) -> Color:
	var info: Dictionary = TEAMS.get(team, {})
	return info.get("mini", Color(0.6, 0.6, 0.6)) as Color


static func zone_color(team: int) -> Color:
	return minimap_color(team) if team != 0 else NEUTRAL_ZONE_COLOR
