extends HBoxContainer
## One portrait per selected unit. Rebuilds on selection_changed and
## updates health bars from each unit's damaged signal — no polling.

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
			var path: String = u.portrait_path()
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
	var hp: ColorRect = slot.get_meta("hp")
	if u.get("max_hp") != null and u.get("hp") != null:
		hp.size.x = 24.0 * clampf(float(u.hp) / float(u.max_hp), 0.0, 1.0)


func _make_slot() -> PanelContainer:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(28, 34)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	slot.add_child(box)
	var icon := TextureRect.new()
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.custom_minimum_size = Vector2(24, 24)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	box.add_child(icon)
	slot.set_meta("icon", icon)
	var hp_bg := ColorRect.new()
	hp_bg.color = Color(0, 0, 0, 0.6)
	hp_bg.custom_minimum_size = Vector2(24, 3)
	box.add_child(hp_bg)
	var hp := ColorRect.new()
	hp.color = Color(0.2, 1.0, 0.2)
	hp.custom_minimum_size = Vector2(24, 3)
	hp_bg.add_child(hp)
	slot.set_meta("hp", hp)
	return slot
