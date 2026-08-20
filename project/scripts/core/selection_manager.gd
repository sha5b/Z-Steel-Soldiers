class_name SelectionManager
extends Node
## Owns unit selection, drag-rectangle state, the order-stance (player
## intent) and order dispatch (2D). A CHILD OF THE MATCH SCENE (not an
## autoload) — see NavWorld for the locator pattern.

## The active match's selection state (set on _ready, cleared on exit).
static var current: SelectionManager


func _ready() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null


signal selection_changed(units: Array)
signal order_issued(world_position: Vector2)
signal stance_changed
signal drag_started
signal drag_moved
signal drag_ended

## What a right-click order DOES (set by the Q/E/R hotkeys and the
## stance bar next to the minimap): MOVE ignores enemies en route,
## ATTACK_MOVE halts and engages, DEFEND walks there and holds the
## post. Player UI intent lives with selection, not with the economy.
enum OrderStance { MOVE, ATTACK_MOVE, DEFEND }
var order_stance: OrderStance = OrderStance.MOVE


## Single write path — hotkeys and the stance bar both go through it so
## `stance_changed` always fires (the bar used to poll to stay honest).
func set_stance(s: OrderStance) -> void:
	if order_stance == s:
		return
	order_stance = s
	stance_changed.emit()

var selected: Array[Node] = []

## CONTROL GROUPS (Ctrl+digit assigns, digit recalls; 1-9 then 0 = ten
## slots). Groups hold unit references, so a member that dies or is
## freed simply drops out on the next recall — no bookkeeping on death.
const GROUP_COUNT := 10
var _groups := {}  # slot 0..9 -> Array[Node]

var drag_start := Vector2.ZERO
var drag_current := Vector2.ZERO
var is_dragging := false


func toggle_select(unit: Node, additive: bool) -> void:
	if additive:
		if unit in selected:
			selected.erase(unit)
		else:
			selected.append(unit)
	elif unit not in selected:
		clear_selection()
		selected.append(unit)
	_cleanup()
	selection_changed.emit(selected)


## Publish a selection built up by pushing onto `selected` directly (the
## R/V select-all filters do that). Prunes dead entries, marks the
## survivors selected and fires the one signal the HUD listens to.
func commit() -> void:
	_cleanup()
	selection_changed.emit(selected)


func clear_selection() -> void:
	for u in selected:
		if is_instance_valid(u):
			u.set_selected(false)
	selected.clear()
	selection_changed.emit(selected)


func drop_from_selection(unit: Node) -> void:
	if unit in selected:
		selected.erase(unit)
		selection_changed.emit(selected)


## One click, one unit — the old clear-then-add dance in one place.
func select_single(unit: Node) -> void:
	clear_selection()
	if unit is Unit2D and unit.alive:
		selected.append(unit)
	_cleanup()
	selection_changed.emit(selected)


## Units report their own deaths now; the selection follows.
func listen(unit: Unit2D) -> void:
	if not unit.died.is_connected(_on_unit_died):
		unit.died.connect(_on_unit_died)


func _on_unit_died(unit: Node) -> void:
	drop_from_selection(unit)


func select_area(world_rect: Rect2) -> void:
	if not Input.is_key_pressed(KEY_SHIFT):
		clear_selection()
	for unit in get_tree().get_nodes_in_group(Groups.SELECTABLE):
		# own units only — enemy hardware is never selectable/orderable
		if not (unit is Unit2D) or not unit.alive or unit.carried \
				or unit.team != MatchState.current.player_team:
			continue
		if world_rect.has_point(unit.global_position) and unit not in selected:
			selected.append(unit)
	_cleanup()
	selection_changed.emit(selected)


## Store the live selection in a slot; returns how many units went in.
## Assigning an empty selection CLEARS the slot (same as every RTS).
func assign_group(slot: int) -> int:
	if slot < 0 or slot >= GROUP_COUNT:
		return 0
	_cleanup()
	_groups[slot] = selected.duplicate()
	return selected.size()


## Recall a slot as the whole selection. Dead and freed members are
## dropped here (and written back), so a wiped group recalls as nothing
## instead of resurrecting stale references.
func select_group(slot: int) -> int:
	var members := group_members(slot)
	clear_selection()
	for u in members:
		selected.append(u)
	_cleanup()
	selection_changed.emit(selected)
	return selected.size()


## The slot's surviving members (also prunes the stored list).
func group_members(slot: int) -> Array[Node]:
	var out: Array[Node] = []
	for u in _groups.get(slot, []):
		if is_instance_valid(u) and u is Unit2D and u.alive and not u.carried:
			out.append(u)
	if _groups.has(slot):
		_groups[slot] = out
	return out


## Where a group stands, for the camera jump on a second recall press.
## Vector2.INF when the slot is empty.
func group_center(slot: int) -> Vector2:
	var members := group_members(slot)
	if members.is_empty():
		return Vector2.INF
	var sum := Vector2.ZERO
	for u in members:
		sum += u.global_position
	return sum / float(members.size())


func issue_order(world_position: Vector2) -> void:
	order_issued.emit(world_position)


## Drag state flows through here so the rectangle view can follow the
## signals instead of polling every frame.
func begin_drag(screen_pos: Vector2) -> void:
	drag_start = screen_pos
	drag_current = screen_pos
	is_dragging = true
	drag_started.emit()


func move_drag(screen_pos: Vector2) -> void:
	drag_current = screen_pos
	drag_moved.emit()


func end_drag() -> void:
	is_dragging = false
	drag_ended.emit()


func get_drag_rect() -> Rect2:
	return Rect2(drag_start, drag_current - drag_start).abs()


func screen_to_world(screen_pos: Vector2) -> Vector2:
	var canvas: Transform2D = Engine.get_main_loop().root.get_canvas_transform()
	return canvas.affine_inverse() * screen_pos


func screen_to_world_rect(screen_rect: Rect2) -> Rect2:
	var canvas: Transform2D = Engine.get_main_loop().root.get_canvas_transform()
	var inv: Transform2D = canvas.affine_inverse()
	var a := inv * screen_rect.position
	var b := inv * (screen_rect.position + screen_rect.size)
	return Rect2(a, b - a).abs()


func _cleanup() -> void:
	selected = selected.filter(func(u): return is_instance_valid(u))
	for u in selected:
		u.set_selected(true)
