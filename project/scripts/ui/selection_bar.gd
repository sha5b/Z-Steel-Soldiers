class_name SelectionBar
extends HBoxContainer
## Bottom-center selection display: one portrait tile per selected unit
## (original stand sprite + HP bar); click a portrait to select only that
## unit. Shows "+N" when overflowing.

const MAX_PORTRAITS := 14


func _process(_delta: float) -> void:
	var units := SelectionManager.selected
	if not visible and units.is_empty():
		return
	_sync(units)


func _sync(units: Array) -> void:
	var desired: int = mini(units.size(), MAX_PORTRAITS)
	if get_child_count() != desired:
		for c in get_children():
			c.queue_free()
		for i in desired:
			add_child(_make_slot())
	var children := get_children()
	for i in children.size():
		# untyped on purpose: a freed unit in the list must not raise on
		# assignment — the validity check below skips it
		var u = units[i] if i < units.size() else null
		var icon: TextureRect = children[i].get_meta("icon")
		var hp: ColorRect = children[i].get_meta("hp")
		icon.texture = null
		if u != null and is_instance_valid(u) and u.has_method("portrait_path"):
			var path: String = u.portrait_path()
			if path != "" and ResourceLoader.exists(path):
				icon.texture = load(path)
			if u.get("max_hp") != null and u.get("hp") != null:
				hp.size.x = 28.0 * clampf(float(u.hp) / float(u.max_hp), 0.0, 1.0)


func _make_slot() -> PanelContainer:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(34, 40)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	slot.add_child(box)
	var icon := TextureRect.new()
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.custom_minimum_size = Vector2(30, 30)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	box.add_child(icon)
	var hp_bg := ColorRect.new()
	hp_bg.color = Color(0, 0, 0, 0.6)
	hp_bg.custom_minimum_size = Vector2(28, 3)
	box.add_child(hp_bg)
	var hp := ColorRect.new()
	hp.color = Color(0.2, 1.0, 0.2)
	hp.custom_minimum_size = Vector2(28, 3)
	hp.position = Vector2(0, 0)
	box.add_child(hp)
	slot.set_meta("icon", icon)
	slot.set_meta("hp", hp)
	slot.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_pick(slot))
	return slot


func _pick(slot: PanelContainer) -> void:
	var idx := slot.get_index()
	if idx < SelectionManager.selected.size():
		var u = SelectionManager.selected[idx]
		if u == null or not is_instance_valid(u):
			return
		SelectionManager.clear_selection()
		SelectionManager.toggle_select(u, false)
