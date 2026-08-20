class_name SelectedObject
extends Control
## The original's SELECTED-OBJECT panel: the unit standing on its
## planet's backdrop (hardware on the garage plate) with its name plate
## underneath.
##
## All three pieces shipped in the pack and nothing referenced them —
## 6 `backdrop_*` scenes and 30 team-coloured `unit_label_*` plates,
## plus the 19 neutral `label_*` weapon plates that cover the hardware
## the coloured set does not.
##
## Shows for a SINGLE selection (that is what "selected object" means in
## the original); a multi-unit selection is what the portrait row is
## for.

const BACKDROP := "res://assets/z/ui/hud/backdrop_%s.png"
const HARDWARE_BACKDROP := "res://assets/z/ui/hud/backdrop_vehicle.png"
const TEAM_PLATE := "res://assets/z/ui/hud/unit_label_%s_%s.png"
const PLATE := "res://assets/z/ui/hud/label_%s.png"
const ART := Vector2(86.0, 74.0)   # backdrop art size
const PLATE_ART := Vector2(96.0, 14.0)

var _backdrop: TextureRect
var _portrait: TextureRect
var _plate: TextureRect


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop = _make_rect()
	_portrait = _make_rect()
	_plate = _make_rect()
	_backdrop.size = ART
	_portrait.size = ART
	_plate.position = Vector2((ART.x - PLATE_ART.x) * 0.5, ART.y)
	_plate.size = PLATE_ART
	visible = false
	SelectionManager.current.selection_changed.connect(_sync)


func _make_rect() -> TextureRect:
	var r := TextureRect.new()
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r


func _sync(units: Array) -> void:
	var unit: Unit2D = null
	if units.size() == 1 and is_instance_valid(units[0]) and units[0] is Unit2D:
		unit = units[0]
	visible = unit != null and unit.alive
	if not visible:
		return
	_backdrop.texture = _load(_backdrop_path(unit))
	_portrait.texture = _load(unit.portrait_path())
	_plate.texture = _load(plate_path(unit.unit_name, unit.team))


## Robots stand on their planet; hardware sits on the garage plate.
static func _backdrop_path(unit: Unit2D) -> String:
	if unit.kind != "robot":
		return HARDWARE_BACKDROP
	var planet: String = MatchState.current.planet if MatchState.current else "desert"
	return BACKDROP % planet


## The team-coloured plate when the type has one (the six robots), else
## the neutral weapon plate that covers all 19 types. "" when neither
## ships — a type with no plate simply shows none.
static func plate_path(type_name: String, team: int) -> String:
	var coloured := TEAM_PLATE % [type_name, AnimLibrary.team_name(team)]
	if ResourceLoader.exists(coloured):
		return coloured
	var neutral := PLATE % type_name
	return neutral if ResourceLoader.exists(neutral) else ""


static func _load(path: String) -> Texture2D:
	return load(path) if path != "" and ResourceLoader.exists(path) else null
