class_name HudPortrait
extends Control
## The sidebar's head window (86x74 at (8,44) in the frame art).
##
## A ROBOT shows its animated cartoon head — the original's SHEADBI face
## set, composited into whole frames by tools/zod/build_hud.py and played
## here as a flipbook:
##
##   base.png       resting face
##   hurt.png       the second head the pack ships, used below HURT_AT hp
##   blink_nNN.png  eye cycle   (11 frames)
##   talk_nNN.png   mouth cycle (16 frames)
##
## HARDWARE has no head in the original: an empty hull sits on the garage
## plate instead, a robot-driven one on its planet backdrop. That is the
## SelectedObject art, which this window keeps using for anything that is
## not a robot.
##
## Nothing polls: the window follows selection_changed, its subject's
## `damaged` signal, and Fx barks (a robot that speaks moves its mouth).

const PORTRAIT_DIR := "res://assets/z/ui/portraits/%s_%s"
const WINDOW := Vector2(86.0, 74.0)
## Below this fraction of max HP the face swaps to the battered head.
const HURT_AT := 0.45
## Eye cycle: a short burst, then a long wait. Robots that blink on a
## fixed beat read as a screensaver.
const BLINK_FPS := 14.0
const BLINK_GAP_MIN := 2.4
const BLINK_GAP_MAX := 6.0
## Mouth cycle while the unit talks — the bark length decides how long.
const TALK_FPS := 12.0

var _art: TextureRect
var _unit: Unit2D = null
var _base: Texture2D = null
var _hurt: Texture2D = null
var _blink: Array[Texture2D] = []
var _talk: Array[Texture2D] = []
var _blink_in := 0.0
var _cycle := -1.0      # seconds into the active cycle, <0 = resting
var _cycling: Array[Texture2D] = []
var _cycle_fps := BLINK_FPS
var _damaged_wire: Callable = Callable()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = WINDOW
	_art = TextureRect.new()
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_art)
	_blink_in = randf_range(BLINK_GAP_MIN, BLINK_GAP_MAX)
	SelectionManager.current.selection_changed.connect(_on_selection)
	# a bark IS the mouth moving — one wire covers order acks, distress
	# calls and idle chatter instead of each caller remembering to
	# animate the face
	Fx.barked.connect(_on_barked)
	_on_selection(SelectionManager.current.selected)


## The window shows ONE subject, like the original's selected-object
## panel: a single selection, else the first unit of a squad.
func _on_selection(units: Array) -> void:
	var subject: Unit2D = null
	for u in units:
		if is_instance_valid(u) and u is Unit2D and u.alive:
			subject = u
			break
	_bind(subject)


func _bind(unit: Unit2D) -> void:
	if unit == _unit:
		return
	if _unit != null and is_instance_valid(_unit) and _damaged_wire.is_valid() \
			and _unit.damaged.is_connected(_damaged_wire):
		_unit.damaged.disconnect(_damaged_wire)
	_unit = unit
	_base = null
	_hurt = null
	_blink.clear()
	_talk.clear()
	_cycle = -1.0
	visible = unit != null
	if unit == null:
		_art.texture = null
		return
	if unit.kind == "robot":
		_load_face(unit)
	if _base == null:
		# hardware, or a robot whose face set was never converted: the
		# hull on its plate, exactly as the selected-object panel drew it
		_base = _load(SelectedObject.backdrop_path(unit))
		var hull := _load(unit.portrait_path())
		_art.texture = _base
		if hull != null:
			_overlay_hull(hull)
			return
	_damaged_wire = func(_amount: int): _refresh_face()
	unit.damaged.connect(_damaged_wire)
	_refresh_face()


func _load_face(unit: Unit2D) -> void:
	var dir: String = PORTRAIT_DIR % [unit.unit_name,
			AnimLibrary.team_name(unit.team if unit.team > 0 else 1)]
	_base = _load("%s/base.png" % dir)
	_hurt = _load("%s/hurt.png" % dir)
	for i in 64:
		var blink := _load("%s/blink_n%02d.png" % [dir, i])
		if blink == null:
			break
		_blink.append(blink)
	for i in 64:
		var talk := _load("%s/talk_n%02d.png" % [dir, i])
		if talk == null:
			break
		_talk.append(talk)


## The hull sits ON the backdrop, so it needs a second layer rather than
## replacing the plate.
func _overlay_hull(hull: Texture2D) -> void:
	var top := TextureRect.new()
	top.texture = hull
	top.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	top.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.set_anchors_preset(Control.PRESET_FULL_RECT)
	_art.add_child(top)


func _refresh_face() -> void:
	if _unit == null or not is_instance_valid(_unit):
		return
	for c in _art.get_children():
		c.queue_free()   # hull layer from a previous hardware subject
	_art.texture = _resting()


## The battered head once the robot is hurt (the original ships two faces
## per robot and this is the only use we have for the second).
func _resting() -> Texture2D:
	if _hurt != null and _unit != null and is_instance_valid(_unit) \
			and float(_unit.hp) / float(maxi(_unit.max_hp, 1)) < HURT_AT:
		return _hurt
	return _base


func _on_barked(seconds: float) -> void:
	if _unit == null or _talk.is_empty():
		return
	_cycling = _talk
	_cycle_fps = TALK_FPS
	_cycle = 0.0
	# a long line loops the mouth cycle; a short one plays part of it
	set_meta("cycle_until", maxf(seconds, 0.3))


func _process(delta: float) -> void:
	if _unit == null or not is_instance_valid(_unit) or _base == null:
		return
	if _cycle >= 0.0:
		_cycle += delta
		if _cycle >= float(get_meta("cycle_until", 0.6)):
			_cycle = -1.0
			_art.texture = _resting()
		else:
			var i := int(_cycle * _cycle_fps) % _cycling.size()
			_art.texture = _cycling[i]
		return
	if _blink.is_empty():
		return
	_blink_in -= delta
	if _blink_in <= 0.0:
		_blink_in = randf_range(BLINK_GAP_MIN, BLINK_GAP_MAX)
		_cycling = _blink
		_cycle_fps = BLINK_FPS
		_cycle = 0.0
		set_meta("cycle_until", float(_blink.size()) / BLINK_FPS)


static func _load(path: String) -> Texture2D:
	return load(path) if path != "" and ResourceLoader.exists(path) else null
