extends VBoxContainer
## Right-edge quick bar listing every production facility the player owns
## (fort, robot/vehicle factories) — captured factories appear live.
## Click an entry to select that building, which opens the production
## panel. Entries show the original factory labels, a fill bar for
## whatever is currently building, and SMALL ICONS of the queued items
## along the bottom edge. Ownership changes (captures) refresh
## immediately; a slow fallback sweep covers producer deaths.

const FALLBACK_SWEEP_SECONDS := 2.0
const PROGRESS_REFRESH := 0.25
## Entry chrome: tall enough for the label, the "queued/cap" counter and
## a row of MAX_ITEMS queue thumbnails without them overlapping.
const ENTRY_SIZE := Vector2(118, 30)
const ICON_SIZE := Vector2(18, 10)  # landscape, like the icon art

var _sweep_accum := 0.0
var _progress_accum := 0.0
var _entries := {}  # building node -> button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	custom_minimum_size = Vector2(ENTRY_SIZE.x, 0)
	add_theme_constant_override("separation", 3)
	MatchState.current.zone_captured.connect(func(_team): _sync())
	_sync()


func _process(delta: float) -> void:
	_progress_accum += delta
	if _progress_accum >= PROGRESS_REFRESH:
		_progress_accum = 0.0
		for node in _entries:
			var bar: TextureProgressBar = _entries[node].get_node_or_null("ProgressBar")
			if bar and is_instance_valid(node):
				bar.value = node.progress() * 100.0
			if is_instance_valid(node):
				_update_strip(_entries[node], node)
	# deaths and anything a capture didn't cover
	_sweep_accum += delta
	if _sweep_accum >= FALLBACK_SWEEP_SECONDS:
		_sweep_accum = 0.0
		_sync()


func _sync() -> void:
	var alive := {}
	for c in get_tree().get_nodes_in_group(Groups.FACILITIES):
		if c is Node2D and is_instance_valid(c) and c.alive \
				and c.owner_team == MatchState.current.player_team:
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
	btn.custom_minimum_size = ENTRY_SIZE
	btn.tooltip_text = "Select building (right-click map with it selected to set the rally point)"
	var icon_path: String = FactoryLabels.LABELS.get(node.kind_key(), "")
	if icon_path != "" and ResourceLoader.exists(icon_path):
		btn.icon = load(icon_path)
		btn.expand_icon = false
	btn.pressed.connect(func():
		SelectionManager.current.clear_selection()
		SelectionManager.current.toggle_select(node, false))
	add_child(btn)
	return btn


## Mini queue preview: HOW MANY items this facility has queued, plus
## what they are as small icons along the entry's bottom edge. Diffed
## against a cache so the 4 Hz refresh pass costs nothing when idle.
## Icons come from ProductionPanel.icon_for — the shared, cropped and
## cached texture (the raw HUD art is a 96px canvas around a small
## sprite, which renders as a smear at strip size).
func _update_strip(btn: Button, node: Node) -> void:
	var q: Array = node.queue_items()
	var key := ",".join(q)
	if String(btn.get_meta("queue_key", "")) == key:
		return
	btn.set_meta("queue_key", key)

	var count: Label = btn.get_node_or_null("QueueCount")
	if count == null:
		count = Label.new()
		count.name = "QueueCount"
		count.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		count.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		count.offset_left = -ENTRY_SIZE.x
		count.offset_right = -3
		count.offset_top = 1
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count.add_theme_font_size_override("font_size", 12)
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(count)
	# "3/5" — queued out of the queue cap, so a full queue reads as full
	count.text = "" if q.is_empty() else "%d/%d" % [q.size(), ProductionQueue.MAX_ITEMS]
	count.modulate = Color(1.0, 0.55, 0.4) if q.size() >= ProductionQueue.MAX_ITEMS \
		else Color(1.0, 0.92, 0.7)

	var strip: HBoxContainer = btn.get_node_or_null("QueueIcons")
	if strip == null:
		strip = HBoxContainer.new()
		strip.name = "QueueIcons"
		strip.add_theme_constant_override("separation", 1)
		strip.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		strip.offset_left = 4
		strip.offset_top = -(ICON_SIZE.y + 6.0)
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(strip)
	for c in strip.get_children():
		c.queue_free()
	for item in q:
		var parts: PackedStringArray = String(item).split(":")
		if parts.size() != 2:
			continue
		var tex_res := ProductionPanel.icon_for(parts[0], parts[1],
			MatchState.current.player_team)
		if tex_res == null:
			continue
		var tex := TextureRect.new()
		tex.texture = tex_res
		tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tex.custom_minimum_size = ICON_SIZE
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		strip.add_child(tex)


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
