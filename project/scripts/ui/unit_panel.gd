class_name UnitPanel
extends Control
## Everything the sidebar says about the selected unit, under its
## portrait: the team name plate, the equipment art, the grenade tally and
## the health bar over the weapon plate.
##
## The pieces are the original's:
##   unit_label_<type>_<team>.png   red name plate ("GRUNT")
##   weapon_<type>.png              88x63 equipment art (a grunt's rifle,
##                                  a tough's missile tube, a tank hull)
##   label_<type>.png               weapon plate ("RIFLE", "MISSILE")
##   grenade.png                    grenade plate, with the count beside it
##   health_{full,lost,empty}.png   74px bar, in thirds like the original:
##                                  green for current, yellow for lost
##
## The bar is 74px because the original's HP scale IS 74 (see the stat
## table in docs/RESEARCH.md 2d) — one pixel per hit point.
##
## Signal-driven: selection changes rebind it, the subject's `damaged`
## signal moves the bar, and MatchState's upgrade signal moves the
## grenade tally. Nothing here polls.

const HUD_DIR := "res://assets/z/ui/hud"

var _name_plate: TextureRect
var _equipment: TextureRect
var _weapon_plate: TextureRect
var _grenade: TextureRect
var _grenade_count: Label
var _health_lost: TextureRect
var _health_full: TextureRect
var _unit: Unit2D = null
var _damaged_wire: Callable = Callable()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_plate = _rect(HudFrame.NAME_PLATE)
	_equipment = _rect(HudFrame.EQUIPMENT)
	_grenade = _rect(HudFrame.GRENADE)
	_grenade.texture = _tex("grenade")
	_weapon_plate = _rect(HudFrame.WEAPON_PLATE)
	# health: empty track, the lost (yellow) span over it, the current
	# (green) span on top — all left-aligned and CLIPPED to width, never
	# stretched, so one pixel stays one hit point
	var track := _rect(HudFrame.HEALTH)
	track.texture = _tex("health_empty")
	_health_lost = _rect(HudFrame.HEALTH)
	_health_lost.texture = _tex("health_lost")
	_health_full = _rect(HudFrame.HEALTH)
	_health_full.texture = _tex("health_full")
	for bar in [track, _health_lost, _health_full]:
		bar.stretch_mode = TextureRect.STRETCH_KEEP
		bar.clip_contents = true
	_grenade_count = Label.new()
	_grenade_count.position = HudFrame.GRENADE_COUNT.position
	_grenade_count.size = HudFrame.GRENADE_COUNT.size
	_grenade_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_grenade_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	HudFrame._apply_hud_font(_grenade_count, 16)
	add_child(_grenade_count)
	SelectionManager.current.selection_changed.connect(_on_selection)
	MatchState.current.upgrade_gained.connect(func(_team, _which): _sync_grenades())
	_on_selection(SelectionManager.current.selected)


func _rect(at: Rect2) -> TextureRect:
	var r := TextureRect.new()
	r.position = at.position
	r.size = at.size
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r


func _on_selection(units: Array) -> void:
	var subject: Unit2D = null
	for u in units:
		if is_instance_valid(u) and u is Unit2D and u.alive:
			subject = u
			break
	if _unit != null and is_instance_valid(_unit) and _damaged_wire.is_valid() \
			and _unit.damaged.is_connected(_damaged_wire):
		_unit.damaged.disconnect(_damaged_wire)
	_unit = subject
	var shown := subject != null
	for node in [_name_plate, _equipment, _weapon_plate, _grenade,
			_grenade_count, _health_full, _health_lost]:
		node.visible = shown
	if not shown:
		return
	_name_plate.texture = _load(SelectedObject.plate_path(subject.unit_name,
			subject.team))
	_equipment.texture = _tex("weapon_%s" % subject.unit_name)
	_weapon_plate.texture = _load("%s/label_%s.png" % [HUD_DIR, subject.unit_name])
	_damaged_wire = func(_amount: int): _sync_health()
	subject.damaged.connect(_damaged_wire)
	_sync_health()
	_sync_grenades()


## Green = current HP, yellow = what it has lost, both in bar pixels.
func _sync_health() -> void:
	if _unit == null or not is_instance_valid(_unit):
		return
	var frac := clampf(float(_unit.hp) / float(maxi(_unit.max_hp, 1)), 0.0, 1.0)
	var full_w := HudFrame.HEALTH.size.x
	_health_full.size.x = roundf(full_w * frac)
	_health_lost.size.x = full_w


## The original's grenade tally: the crate upgrade grants throwables, so
## the count only means anything for a robot that can throw them.
func _sync_grenades() -> void:
	if _unit == null or not is_instance_valid(_unit):
		return
	var carried: int = int(_unit.grenades) if _unit.get("grenades") != null else 0
	var show := _unit.kind == "robot" and carried > 0
	_grenade.visible = show
	_grenade_count.visible = show
	_grenade_count.text = "%d" % carried


static func _tex(name: String) -> Texture2D:
	return _load("%s/%s.png" % [HUD_DIR, name])


static func _load(path: String) -> Texture2D:
	return load(path) if path != "" and ResourceLoader.exists(path) else null
