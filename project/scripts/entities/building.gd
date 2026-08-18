@tool
class_name Building2D
extends Node2D
signal died
## Original-sprite building (forts, factories, radar, repair). Loads the
## per-planet texture, shows an ownership flag, and computes a ground
## footprint (sprite is 2x tile scale -> footprint = texture/2) for
## clicks, zone ownership and targeting. Team colour on the flag is the
## Teams palette swap over the master flag art.

@export var building_id := 2
@export var team := 0
@export var planet := "desert"
@export var level := 0  # 0..5: unlocks the build list roster, speeds builds
var is_fort := false
var selected := false

var hp := 500
var max_hp := 500
var alive := true
var owner_team := 0  # factories: follows zone owner
var rally_point := Vector2.INF  # produced units gather here when set
var queue := ProductionQueue.new()  # production queue ("kind:name" items)

var _sprite: Sprite2D
var _rally_flag: Sprite2D
var _flag: AnimatedSprite2D
var _flag_team := -1  # team the flag currently shows
var _hp_bar: ColorRect
var _hp_bar_max_w := 64.0
var _sort_lift := Vector2.ZERO  # node lifted to the footprint bottom (y-sort line)


func setup(id: int, owner_team_value: int, planet_name: String, building_level := 0) -> void:
	building_id = id
	team = owner_team_value
	owner_team = owner_team_value
	planet = planet_name
	level = clampi(building_level, 0, 5)
	is_fort = id == 0 or id == 1
	if id == 6 or id == 7:
		max_hp = BRIDGE_HP
		hp = BRIDGE_HP


# ----------------------- shared production -----------------------
# Every producer (fort, robot factory, vehicle factory) builds from
# its BuildingDef's build_lists[level] — items are "kind:name". Robots
# spawn crewed; vehicles and cannons spawn empty beside the building for
# a robot to man (Z-style).

func producer_key() -> String:
	return ""  # not a producer


func produce_seconds() -> float:
	return 8.0 * build_time_mult()


func build_time_mult() -> float:
	return maxf(1.0 - 0.08 * level, 0.6)


func build_options() -> Array:
	var def := ContentDB.producer_def(producer_key())
	if def == null:
		return []
	return def.build_lists.get(level, [])


func queue_items() -> Array[String]:
	return queue.items


func progress() -> float:
	if owner_team == 0 or queue.items.is_empty():
		return 0.0
	return queue.progress(produce_seconds())


func queue_unit(item: String, silent := false) -> bool:
	var parts := item.split(":")
	if parts.size() != 2:
		return false
	var kind := parts[0]
	var type_name := parts[1]
	if not ContentDB.has_unit(kind, type_name):
		return false
	if kind != "robot" and not ContentDB.has_sprites(kind, type_name):
		return false
	var stats := ContentDB.def_for(kind, type_name)
	if not _pop_allows(kind, stats, silent):
		return false
	if not GameState.spend(owner_team, stats.cost):
		return false
	if not queue.enqueue(item):
		GameState.money[owner_team] += stats.cost  # queue full: refund
		GameState.money_changed.emit(owner_team, GameState.money[owner_team])
		return false
	return true


func cancel_at(index: int) -> void:
	var item := queue.cancel_at(index)
	if item == "" or owner_team == 0:
		return
	var stats := ContentDB.def_for(item.split(":")[0], item.split(":")[1])
	GameState.money[owner_team] += stats.cost
	GameState.money_changed.emit(owner_team, GameState.money[owner_team])


## Cap gate: alive + queued + this unit must fit under the team cap.
## `silent` suppresses the denial beep for CPU-initiated production.
func _pop_allows(kind: String, stats: UnitDef, silent := false) -> bool:
	var team_id := team if team != 0 else owner_team
	var queued := 0
	for item in queue.items:
		var parts: PackedStringArray = item.split(":")
		queued += ContentDB.def_for(parts[0], parts[1]).pop
	var cost := stats.pop
	if GameState.unit_pop(team_id) + queued + cost > GameState.unit_cap(team_id):
		if not silent:
			Fx.cap_denied()
		return false
	return true


func tick_production(delta: float) -> void:
	if owner_team == 0:
		return
	var done := queue.tick(delta, produce_seconds())
	if done != "":
		spawn_produced(done)


func spawn_produced(item: String) -> void:
	var parts := item.split(":")
	var kind := parts[0]
	var type_name := parts[1]
	if owner_team == GameState.player_team:
		Fx.announce("robot_manufactured" if kind == "robot"
			else "vehicle_manufactured" if kind == "vehicle"
			else "gun_manufactured")
	var spawn_pos := global_position + Vector2(48, 40)
	if kind == "robot":
		var unit: Unit2D = Spawner.spawn(get_parent(), kind, type_name,
			owner_team, spawn_pos) as Unit2D
		if unit and rally_point != Vector2.INF:
			unit.move_to(rally_point)
	elif ContentDB.has_sprites(kind, type_name):
		# vehicles and cannons spawn UNMANNED beside the building for a
		# robot to man (Z-style)
		var vehicle := Spawner.spawn(get_parent(), kind, type_name, 0, spawn_pos)
		if vehicle and rally_point != Vector2.INF:
			vehicle.move_to(rally_point)



func _ready() -> void:
	# works with setup() (JSON loader) or straight @export values (map scenes)
	if not is_fort:
		is_fort = building_id == 0 or building_id == 1
	if owner_team == 0 and team != 0:
		owner_team = team
	_build_sprite()
	if Engine.is_editor_hint():
		return
	if is_fort:
		add_to_group("buildings")
	# producers register for the facility quick bar
	var bdef := ContentDB.building_def(building_id)
	if (bdef != null and bdef.produces) or is_fort:
		add_to_group("facilities")


func _build_sprite() -> void:
	_sprite = Sprite2D.new()
	_sprite.texture = load(_texture_path(false))
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# bottom-center the sprite over the footprint
	var ts: Vector2 = _sprite.texture.get_size()
	_sprite.centered = false
	_sprite.position = Vector2(-ts.x * 0.25, -ts.y * 0.5)  # origin = footprint center
	if building_id == 7:  # horizontal bridge: rotate the vertical strip
		_sprite.rotation_degrees = 90
		_sprite.position = Vector2(-ts.y * 0.25, ts.x * 0.5) - Vector2(0, ts.x)
	add_child(_sprite)
	# Godot 4.7 y-sorts by the NODE's y, so the node moves down to the
	# footprint's bottom edge (the wall line) and every visual shifts up
	# to compensate: units below the line draw in front of the building,
	# units on/above it behind. Bridges stay centred (flat ground art).
	# Runtime only — map scenes keep baking footprint centres.
	if not is_bridge() and not Engine.is_editor_hint():
		_sort_lift = Vector2(0, ts.y * 0.25)
		position += _sort_lift
		_sprite.position -= _sort_lift

	_flag = AnimatedSprite2D.new()
	if building_id == 6 or building_id == 7:
		_flag.visible = false  # bridges carry no flag
	_flag.position = Vector2(0, -ts.y * 0.5 - 4) - _sort_lift
	_flag.scale = Vector2(2, 2)
	add_child(_flag)
	set_flag_team(team)

	_build_overlays()

	if is_fort:
		_hp_bar = ColorRect.new()
		_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hp_bar.color = Color(0.2, 1.0, 0.2)
		var bar_w := ts.x * 0.5  # match the building footprint width
		_hp_bar_max_w = bar_w
		_hp_bar.size = Vector2(bar_w, 5)
		_hp_bar.position = Vector2(-bar_w * 0.5, -ts.y * 0.5 - 12) - _sort_lift
		add_child(_hp_bar)


## Ownership flag: master (red) art + the team's palette-swap material —
## neutral team 0 shows the grey flag set. Swapping teams is a material
## change, no disk rescan.
func set_flag_team(for_team: int) -> void:
	if _flag == null or for_team == _flag_team:
		return
	_flag_team = for_team
	_flag.sprite_frames = AnimLibrary.flag_frames(for_team == 0)
	Teams.apply(_flag, for_team)
	if _flag.sprite_frames and _flag.sprite_frames.has_animation("wave"):
		_flag.play("wave")


## Texture location comes from the building def's `tex` key — new building
## types only add art + a content/buildings entry.
func _texture_path(destroyed: bool) -> String:
	if ContentDB.building_def(building_id) == null:
		return ""
	match ContentDB.building_def(building_id).tex:
		"fort_front":
			return "res://assets/z/buildings/fort/fort_%s_front%s.png" % [
				planet, "_destroyed" if destroyed else ""]
		"fort_back":
			return "res://assets/z/buildings/fort/fort_%s_back%s.png" % [
				planet, "_destroyed" if destroyed else ""]
		"bridge":
			return "res://assets/z/planets/bridge_%s.png" % planet
		var kind:
			if destroyed:
				return "res://assets/z/buildings/%s/base_destroyed_%s.png" % [kind, planet]
			return "res://assets/z/buildings/%s/base_%s.png" % [kind, planet]


## Animated overlay layers from the def's `anims` (radar dish, factory
## spinner, repair smoke stack...): numbered frames `<prefix>_<i>.png`
## played as a loop over the base sprite.
func _build_overlays() -> void:
	var bdef := ContentDB.building_def(building_id)
	if bdef == null:
		return
	for anim in bdef.anims:
		var frames := SpriteFrames.new()
		frames.add_animation("loop")
		frames.set_animation_speed("loop", anim.fps)
		frames.set_animation_loop("loop", true)
		var frame := 0
		while true:
			var path := "res://assets/z/buildings/%s/%s_%d.png" % [
				bdef.tex, anim.prefix, frame]
			if not ResourceLoader.exists(path):
				break
			frames.add_frame("loop", load(path))
			frame += 1
		if frame == 0:
			continue
		var overlay := AnimatedSprite2D.new()
		overlay.name = "Overlay_%s" % anim.prefix
		overlay.sprite_frames = frames
		overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		overlay.centered = false
		overlay.position = anim.offset - Vector2(8, 8) - _sort_lift  # small overlay sprites anchor near their centre
		add_child(overlay)
		overlay.play("loop")


func world_footprint() -> Rect2:
	# ground area under the sprite (world px); the node may be lifted to
	# the footprint's bottom edge for y-sorting — undo that here
	var ts: Vector2 = _sprite.texture.get_size() if _sprite else Vector2(64, 64)
	if building_id == 7:
		ts = Vector2(ts.y, ts.x)  # rotated horizontal bridge
	var half := ts * 0.25
	return Rect2(global_position - _sort_lift - half, half * 2.0)


func visual_center() -> Vector2:
	var ts: Vector2 = _sprite.texture.get_size() if _sprite else Vector2(64, 64)
	return global_position - _sort_lift - Vector2(0, ts.y * 0.25)


func set_rally(world_position: Vector2) -> void:
	rally_point = world_position
	if _rally_flag == null:
		_rally_flag = Sprite2D.new()
		_rally_flag.texture = load("res://assets/z/flags/flag_red_n00.png")
		_rally_flag.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_rally_flag.scale = Vector2(2, 2)
		add_child(_rally_flag)
	Teams.apply(_rally_flag, team if team != 0 else owner_team)
	_rally_flag.position = rally_point - global_position
	_rally_flag.visible = selected


func set_selected(value: bool) -> void:
	selected = value
	if _rally_flag:
		_rally_flag.visible = value and rally_point != Vector2.INF
	if _sprite:
		_sprite.modulate = Color(1.3, 1.3, 0.9) if value else Color.WHITE


func update_flag(for_team: int) -> void:
	set_flag_team(for_team)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if is_fort:
		return
	# non-fort buildings (radar, repair) follow their zone's owner so the
	# flag recolors on capture; factories override with their own loop
	var center := world_footprint().get_center()
	for z in GameState.zones:
		if z.world_rect().has_point(center):
			if z.owner_team != owner_team:
				owner_team = z.owner_team
				team = owner_team
				update_flag(owner_team)
			break
	_repair_tick(delta)


func is_bridge() -> bool:
	return building_id == 6 or building_id == 7


func is_repair_shop() -> bool:
	return building_id == 3


# ----------------------- repair shop -----------------------
# One damaged vehicle at a time drives in, heals under the smoke stack
# and rolls out again (original: UnitEnterRepairBuilding + repair anim).

var repair_unit: Node2D = null
var _repair_time := 0.0
const REPAIR_SECONDS := 4.0


func try_start_repair(unit: Node2D) -> bool:
	if not is_repair_shop() or owner_team == 0 or repair_unit != null:
		return false
	if unit.team != owner_team or not (unit is Vehicle2D) or unit.kind != "vehicle":
		return false
	if unit.hp >= unit.max_hp:
		return false
	repair_unit = unit
	_repair_time = 0.0
	unit.visible = false
	unit.velocity = Vector2.ZERO
	unit.move_target = Vector2.ZERO
	unit.waypoints = PackedVector2Array()
	unit.remove_from_group("selectable")
	unit.remove_from_group("units")
	SelectionManager.drop_from_selection(unit)
	return true


func _repair_tick(delta: float) -> void:
	if repair_unit == null:
		return
	if not is_instance_valid(repair_unit) or not repair_unit.alive:
		repair_unit = null
		return
	_repair_time += delta
	repair_unit.hp = mini(repair_unit.max_hp,
		int(round(repair_unit.hp + repair_unit.max_hp * delta / REPAIR_SECONDS)))
	if _repair_time >= REPAIR_SECONDS or repair_unit.hp >= repair_unit.max_hp:
		var done: Node2D = repair_unit
		repair_unit = null
		done.hp = done.max_hp
		done.visible = true
		done.add_to_group("selectable")
		done.add_to_group("units")
		done.global_position = world_footprint().get_center() + Vector2(0, 44)
		done.move_to(done.global_position + Vector2(0, 34))


func take_damage(amount: int) -> void:
	if not alive:
		return
	if is_bridge():
		_bridge_damage(amount)
		return
	if not is_fort:
		return
	hp -= amount
	if team == GameState.player_team:
		Fx.announce("fort_under_attack")
	if _sprite:
		_sprite.modulate = Color(3, 3, 3)
		var tween := create_tween()
		tween.tween_property(_sprite, "modulate", Color.WHITE, 0.15)
	if _hp_bar:
		_hp_bar.size.x = maxf(4.0, _hp_bar_max_w * clampf(float(hp) / float(max_hp), 0.0, 1.0))
	if hp <= 0:
		alive = false
		died.emit()
		remove_from_group("buildings")
		SelectionManager.drop_from_selection(self)
		if has_method("kill_garrison"):
			call("kill_garrison")
		Fx.destroyed(visual_center())
		_sprite.texture = load(_texture_path(true))
		for child in get_children():
			if child.name.begins_with("Overlay_"):
				child.visible = false
		_hp_bar.visible = false
		_flag.visible = false
		GameState.report_fort_destroyed(team)


# ----------------------- bridges -----------------------
# Bridges can be blown up (they become impassable rubble) and rebuilt
# by a manned crane (original: CheckDestroyedBridge + crane repair).

const BRIDGE_HP := 400
var bridge_cells: Array[Vector2i] = []  # filled by the map loader


func _bridge_damage(amount: int) -> void:
	hp -= amount
	if _sprite:
		_sprite.modulate = Color(3, 3, 3)
		var tween := create_tween()
		tween.tween_property(_sprite, "modulate", Color(0.35, 0.35, 0.35), 0.3)
	if hp > 0:
		return
	hp = 0
	Fx.destroyed(world_footprint().get_center())
	for cell in bridge_cells:
		if GameState.nav_grid:
			GameState.nav_grid.set_point_solid(cell, true)
		if GameState.vehicle_grid:
			GameState.vehicle_grid.set_point_solid(cell, true)
	_sprite.modulate = Color(0.35, 0.35, 0.35)


## Crane repair: restores a destroyed bridge (or patches a damaged one).
func repair_by(amount: int) -> void:
	if not is_bridge():
		hp = mini(hp + amount, max_hp)
		return
	if hp >= BRIDGE_HP:
		return
	hp = mini(hp + amount, BRIDGE_HP)
	if hp >= BRIDGE_HP:
		for cell in bridge_cells:
			if GameState.nav_grid:
				GameState.nav_grid.set_point_solid(cell, false)
			if GameState.vehicle_grid:
				GameState.vehicle_grid.set_point_solid(cell, false)
		_sprite.modulate = Color.WHITE
		Fx.play("spark", world_footprint().get_center())
