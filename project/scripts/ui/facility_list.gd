extends VBoxContainer
## Right-edge quick bar listing every production facility the player owns
## (fort, robot/vehicle factories) — captured factories appear live.
## Click an entry to select that building, which opens the production
## panel. Entries show the original factory labels and a fill bar for
## whatever is currently building. Ownership changes (captures) refresh
## immediately; a slow fallback sweep covers producer deaths.

const FALLBACK_SWEEP_SECONDS := 2.0
const PROGRESS_REFRESH := 0.25
const LABELS := {
	"fort": "res://assets/z/ui/production/fort_factory_label.png",
	"fort_factory": "res://assets/z/ui/production/fort_factory_label.png",
	"robot_factory": "res://assets/z/ui/production/fort_factory_label.png",
	"vehicle_factory": "res://assets/z/ui/production/building_label.png",
}

var _sweep_accum := 0.0
var _progress_accum := 0.0
var _entries := {}  # building node -> button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	custom_minimum_size = Vector2(118, 0)
	add_theme_constant_override("separation", 3)
	MatchState.zone_captured.connect(func(_team): _sync())
	_sync()


func _process(delta: float) -> void:
	_progress_accum += delta
	if _progress_accum >= PROGRESS_REFRESH:
		_progress_accum = 0.0
		for node in _entries:
			var bar: TextureProgressBar = _entries[node].get_node_or_null("ProgressBar")
			if bar and is_instance_valid(node):
				bar.value = node.progress() * 100.0
	# deaths and anything a capture didn't cover
	_sweep_accum += delta
	if _sweep_accum >= FALLBACK_SWEEP_SECONDS:
		_sweep_accum = 0.0
		_sync()


func _sync() -> void:
	var alive := {}
	for c in get_tree().get_nodes_in_group("facilities"):
		if c is Node2D and is_instance_valid(c) and c.alive \
				and c.owner_team == MatchState.player_team:
			alive[c] = true
	for node in _entries.keys():
		if not alive.has(node):
			if is_instance_valid(_entries[node]):
				_entries[node].queue_free()
			_entries.erase(node)
	for node in alive:
		if not _entries.has(node):
			_entries[node] = _make_entry(node)
		if is_instance_valid(_entries[node]):
			_update_entry(_entries[node], node)
	# keep list order stable (top to bottom = map order)
	var keys := _entries.keys()
	keys.sort_custom(func(a, b): return a.get_instance_id() < b.get_instance_id())
	for i in keys.size():
		move_child(_entries[keys[i]], i)


func _make_entry(node: Node) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(118, 24)
	btn.tooltip_text = "Select building (right-click map with it selected to set the rally point)"
	var icon_path: String = LABELS.get(node.kind_key(), "")
	if icon_path != "" and ResourceLoader.exists(icon_path):
		btn.icon = load(icon_path)
		btn.expand_icon = false
	btn.pressed.connect(func():
		SelectionManager.current.clear_selection()
		SelectionManager.current.toggle_select(node, false))
	add_child(btn)
	return btn


func _update_entry(btn: Button, node: Node) -> void:
	btn.modulate = Color(1.3, 1.3, 1.0) if SelectionManager.current.selected.has(node) else Color.WHITE
	if btn.get_node_or_null("ProgressBar") != null:
		return
	var bar := TextureProgressBar.new()
	bar.name = "ProgressBar"
	var fill := "res://assets/z/ui/production/entry_bar_green.png"
	var bg := "res://assets/z/ui/production/entry_bar_grey.png"
	if ResourceLoader.exists(fill) and ResourceLoader.exists(bg):
		bar.texture_under = load(bg)
		bar.texture_progress = load(fill)
		bar.nine_patch_stretch = true
		bar.stretch_margin_left = 4
		bar.stretch_margin_right = 4
		bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		bar.offset_top = -5
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(bar)
