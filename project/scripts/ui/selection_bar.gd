extends HBoxContainer
## One portrait per selected unit, in the ORIGINAL HUD's art: the
## team-coloured `unit_label_<type>_<team>` strip (robots; hardware
## keeps its sprite portrait) over the real `health_empty/full` bar.
## Rebuilds on selection_changed and updates health from each unit's
## damaged signal — no polling.

const MAX_PORTRAITS := 12

var _slots: Array[Control] = []
var _wired: Array = []  # [unit, callable] — disconnected on every rebuild


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	SelectionManager.current.selection_changed.connect(_sync)


func _sync(units: Array) -> void:
	# drop every damaged-signal hook first: freed slots or REUSED slots
	# left hooked would either crash the emit (bound slot already freed)
	# or update the wrong unit's bar
	_unwire()
	var desired: int = mini(units.size(), MAX_PORTRAITS)
	if _slots.size() != desired:
		for c in get_children():
			c.queue_free()
		_slots.clear()
		for i in desired:
			var slot := _make_slot()
			add_child(slot)
			_slots.append(slot)
	for i in _slots.size():
		var slot: Control = _slots[i]
		# untyped on purpose: a freed unit in the list must not raise on
		# assignment — the validity check below skips it
		var u = units[i] if i < units.size() else null
		var icon: TextureRect = slot.get_meta("icon")
		icon.texture = null
		slot.set_meta("unit", null)
		if u != null and is_instance_valid(u) and u.has_method("portrait_path"):
			slot.set_meta("unit", u)
			var path := _label_strip(u)
			if path == "":
				path = u.portrait_path()
			if path != "" and ResourceLoader.exists(path):
				icon.texture = load(path)
			_update_hp(slot, u)
			if u.has_signal("damaged"):
				var cb := _on_unit_damaged.bind(slot)
				u.damaged.connect(cb)
				_wired.append([u, cb])


func _unwire() -> void:
	for pair in _wired:
		var u = pair[0]
		var cb: Callable = pair[1]
		if is_instance_valid(u) and cb.is_valid() \
				and u.damaged.is_connected(cb):
			u.damaged.disconnect(cb)
	_wired.clear()


func _on_unit_damaged(_amount: int, slot: Control) -> void:
	if not is_instance_valid(slot):
		return
	var u = slot.get_meta("unit")
	if u != null and is_instance_valid(u):
		_update_hp(slot, u)


func _update_hp(slot: Control, u: Node) -> void:
	var hp: TextureProgressBar = slot.get_meta("hp_bar")
	if u.get("max_hp") != null and u.get("hp") != null:
		hp.value = clampf(float(u.hp) / float(u.max_hp), 0.0, 1.0) * 100.0


## The original's team-coloured name+portrait strip (robots only —
## hardware keeps its sprite portrait).
static func _label_strip(u: Node) -> String:
	if u.get("kind") != "robot":
		return ""
	var team := int(u.get("team", 1))
	if team <= 0:
		team = 1  # no team-0 label art — borrow team 1's set
	var path := "res://assets/z/ui/hud/unit_label_%s_%s.png" % [
		u.get("unit_name", ""), AnimLibrary.team_name(team)]
	return path if ResourceLoader.exists(path) else ""


func _make_slot() -> PanelContainer:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(32, 40)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 1)
	slot.add_child(box)
	var icon := TextureRect.new()
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.custom_minimum_size = Vector2(30, 28)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	box.add_child(icon)
	slot.set_meta("icon", icon)
	# the ORIGINAL health bar: empty trough + full fill (nine-slice so
	# one 74px art set serves every slot width)
	var hp := TextureProgressBar.new()
	var empty := "res://assets/z/ui/hud/health_empty.png"
	var full := "res://assets/z/ui/hud/health_full.png"
	if ResourceLoader.exists(empty) and ResourceLoader.exists(full):
		hp.texture_under = load(empty)
		hp.texture_progress = load(full)
		hp.nine_patch_stretch = true
		hp.stretch_margin_left = 2
		hp.stretch_margin_right = 2
		hp.stretch_margin_top = 2
		hp.stretch_margin_bottom = 2
		hp.custom_minimum_size = Vector2(28, 7)
	else:
		hp.custom_minimum_size = Vector2(28, 3)
	box.add_child(hp)
	slot.set_meta("hp_bar", hp)
	return slot
