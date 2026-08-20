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
	var world: Vector2 = SelectionManager.current.screen_to_world(mouse)
	var sel: Array = SelectionManager.current.selected.filter(
		func(u): return is_instance_valid(u) and u is Unit2D and u.alive)
	if sel.is_empty():
		# a selected BUILDING is not a Unit2D, so this used to fall
		# straight to the plain pointer — the fort's own eject
		# affordance included
		var hovered := _hover_object(world)
		return "exit" if hovered != null and _can_eject(hovered) else "cursor"
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
	# EXIT: hovering something in the selection that is HOLDING bodies
	# (a garrisoned fort, a crewed hull, a loaded APC) — X or the panel's
	# EXIT button hands them back. This is what the shipped exit_* cursor
	# art is for; nothing referenced it before, and there was no dismount
	# action at all, so a unit that entered anything was gone for good.
	if _can_eject(hover):
		return "exit"
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


## Is `hover` a selected thing that Commands.eject() would empty? Same
## predicate the action uses, so the cursor cannot promise an eject that
## does nothing.
func _can_eject(hover: Node2D) -> bool:
	if not SelectionManager.current.selected.has(hover):
		return false
	if hover is FortBuilding and hover.team == MatchState.current.player_team:
		for member in (hover as FortBuilding).garrison:
			if is_instance_valid(member) and member.alive:
				return true
		return false
	if hover is Vehicle2D and hover.team == MatchState.current.player_team:
		return (hover as Vehicle2D).manned or not (hover as Vehicle2D).cargo.is_empty()
	return false


## What the mouse points at — the shared Pick priority (one definition
## for cursor, clicks and targeting).
func _hover_object(world: Vector2) -> Node2D:
	return Pick.at(world)


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
	# every cursor _determine can return is per-team art. (The neutral
	# `placed_n*` ring set is NOT a cursor: PathIndicator draws it at the
	# order destination, and the special case that used to sit here was
	# unreachable because _determine never returns "placed".)
	var art := "%s_%s_n%%02d.png" % [type, _team]  # %%: frame digit passes to the next format
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
