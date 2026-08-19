class_name Teams
extends Object
## Single source of truth for team identity: display name and the
## UI/minimap/zone colours. Team colour on SPRITES needs nothing from
## here — the original engine shipped its own recoloured art for every
## team (`<anim>_<team>_r<deg>.png`, verified pure colour swaps of the
## red set), and AnimLibrary loads those files directly per team.
## Add a team by adding an entry here plus the `_<team>` art variants.

## team id -> {name, minimap blip/zone tint}
const TEAMS := {
	1: {"name": "red", "mini": Color(1.0, 0.30, 0.25)},
	2: {"name": "blue", "mini": Color(0.35, 0.55, 1.0)},
	3: {"name": "green", "mini": Color(0.35, 0.85, 0.35)},
	4: {"name": "yellow", "mini": Color(1.0, 0.9, 0.3)},
}


static func exists(team: int) -> bool:
	return TEAMS.has(team)


## The original shipped five palettes (null + red/blue/green/yellow);
## 8-team maps cycle their extra slots through them — team 5 fights in
## red art, 6 in blue, and so on. Every art token, flag, marker and UI
## colour goes through here, so manned units of teams 5-8 get a REAL
## team look instead of falling to neutral art (the grey-hull +
## floating-turret bug on the QuickStart map).
static func palette(team: int) -> int:
	if team <= 0:
		return 0
	return ((team - 1) % 4) + 1


static func display_name(team: int) -> String:
	var info: Dictionary = TEAMS.get(palette(team), {})
	return String(info.get("name", "null"))


static func minimap_color(team: int) -> Color:
	var info: Dictionary = TEAMS.get(palette(team), {})
	return info.get("mini", Color(0.6, 0.6, 0.6)) as Color
