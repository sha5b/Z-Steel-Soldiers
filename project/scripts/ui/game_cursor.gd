class_name GameCursor
extends AnimatedSprite2D
## The in-game mouse cursor, the ORIGINAL way (zod ZCursor +
## ZPlayer::DetermineCursor): an ANIMATED (4 frames x 0.2s) team-coloured
## cursor that swaps per context — attack over enemies, grab over item
## drops, enter over mannable hardware, repair for crane/repair-shop
## work, nono for unattackable, place for move orders, cannon when only
## cannons are selected. Drawn INSIDE the stretched canvas (not the OS
## cursor) so it scales with the window exactly like the original's
## 16px cursor did at 640x480 — the OS cursor is hidden for the match.
##
## Hotspots (zod ZCursor::Render): the plain pointer anchors at its tip,
## every contextual cursor is CENTRED on the mouse.

const FRAME_SECONDS := 0.2
const TIP_OFFSET := Vector2(6, 3)  # plain cursor: the arrow tip in art px
const CURSOR_DIR := "res://assets/z/ui/cursor"

var _team := ""
var _type := ""
var _frames := {}  # cursor type -> SpriteFrames


static func install(hud: CanvasLayer) -> GameCursor:
	var cursor := GameCursor.new()
	cursor.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	cursor.z_index = 100  # above pause/game-over overlays added later
	cursor.process_mode = Node.PROCESS_MODE_ALWAYS  # animates while paused
	hud.add_child(cursor)
	return cursor


func _process(_delta: float) -> void:
	position = get_viewport().get_mouse_position()
	_show(_determine(position))


## zod DetermineCursor, mapped onto this remake's systems.
func _determine(mouse: Vector2 = get_viewport().get_mouse_position()) -> String:
	if SelectionManager.current.is_dragging or SelectionManager.current.selected.is_empty():
		return "cursor"
	var sel: Array = SelectionManager.current.selected.filter(
		func(u): return is_instance_valid(u) and u is Unit2D and u.alive)
	if sel.is_empty():
		return "cursor"
	var world: Vector2 = SelectionManager.current.screen_to_world(mouse)
	var can_attack := false
	var can_move := false
	var has_crane := false
	var damaged_vehicle := false
	for u in sel:
		var unit := u as Unit2D
		if unit.unit_name != "crane":
			can_attack = true
		if unit.kind != "cannon":
			can_move = true
		if unit.unit_name == "crane":
			has_crane = true
		if unit.kind == "vehicle" and unit.hp < unit.max_hp:
			damaged_vehicle = true
	var hover := _hover_object(world)
	if hover == null:
		return "place" if can_move else "cannon"
	# repair work: crane over damaged hardware, damaged vehicle over a
	# repair shop (zod can_repair / can_be_repaired)
	if has_crane and hover is Unit2D and hover.kind == "vehicle" \
			and hover.team == MatchState.current.player_team and hover.hp < hover.max_hp:
		return "repair"
	if damaged_vehicle and hover is Building2D and hover.is_repair_shop() \
			and hover.owner_team == MatchState.current.player_team:
		return "repair"
	# item drops
	if hover is Pickup:
		return "grab"
	if hover.team != MatchState.current.player_team:
		# mannable hardware (neutral vehicles/cannons)
		if hover is Vehicle2D and hover.team == 0:
			return "enter"
		return "attack" if can_attack else "nono"
	return "place"  # friendly target: move/follow/garrison order


## What the mouse points at: units first (closest), then pickups, then
## building art rects — same priority the click handlers use.
func _hover_object(world: Vector2) -> Node2D:
	var best: Node2D = null
	for u in get_tree().get_nodes_in_group("units"):
		if u is Unit2D and u.alive and not u.carried \
				and (world - u.global_position).length() < 8.0:
			if best == null or (world - u.global_position).length() \
					< (world - best.global_position).length():
				best = u
	if best:
		return best
	for p in get_tree().get_nodes_in_group("pickups"):
		if p is Node2D and (world - p.global_position).length() < 8.0:
			return p
	for b in get_tree().get_nodes_in_group("all_buildings"):
		if b is Building2D and b.alive and b.art_world_rect().has_point(world):
			return b
	return null


func _show(type: String) -> void:
	var team := AnimLibrary.team_name(MatchState.current.player_team)
	if team != _team:
		_team = team
		_frames.clear()
		_type = ""
	if type == _type:
		return
	_type = type
	if not _frames.has(type):
		_frames[type] = _build(type)
	sprite_frames = _frames[type]
	# centered sprite: top-left = position + offset - art/2. The plain
	# pointer puts its TIP (art px 6,3) on the mouse; contextual cursors
	# centre themselves (offset 0).
	offset = (Vector2(8, 8) - TIP_OFFSET) if type == "cursor" else Vector2.ZERO
	if sprite_frames and sprite_frames.has_animation("a"):
		play("a")


func _build(type: String) -> SpriteFrames:
	# contextual cursors are per-team art; PLACED (the neutral ring set)
	# only exists as the neutral frames
	var art := "%s_%s_n%%02d.png" % [type, _team]  # %%: frame digit passes to the next format
	if type == "placed":
		art = "placed_n%02d.png"
	var frames := SpriteFrames.new()
	frames.add_animation("a")
	frames.set_animation_speed("a", 1.0 / FRAME_SECONDS)
	frames.set_animation_loop("a", true)
	var n := 0
	while true:
		var path := "%s/%s" % [CURSOR_DIR, art % n]
		if not ResourceLoader.exists(path):
			break
		frames.add_frame("a", load(path))
		n += 1
	return frames
