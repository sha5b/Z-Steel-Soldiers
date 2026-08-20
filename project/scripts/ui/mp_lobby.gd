extends Control
## Multiplayer room: the host picks the map (skirmish-style list), any
## player clicks an OPEN seat to claim that team, the host cycles
## unoccupied slots OPEN/CPU/CLOSED, everyone readies up and the host
## STARTS — launching the SAME match on every peer (until order
## replication lands, remote players fight as local AI stand-ins). Chat
## rides in the room state. Net owns the wire protocol.

@onready var map_list: ItemList = %MapList
@onready var preview: TextureRect = %Preview
@onready var map_name_label: Label = %MapName
@onready var map_info_label: Label = %MapInfo
@onready var status: Label = %Status
@onready var slots_box: VBoxContainer = %Slots
@onready var chat_log: Label = %ChatLog
@onready var chat_input: LineEdit = %ChatInput
@onready var ready_btn: Button = %Ready
@onready var start_btn: Button = %Start

var _launched := false
var _bounced := false


func _ready() -> void:
	UiTheme.apply(self)
	MusicPlayer.play_menu()
	$Background.texture = UiTheme.trimmed("res://assets/z/ui/IPBackground.png")
	if Net.role == Net.Role.OFFLINE:
		# F6'd straight into the room: stage a local host game only for
		# screenshot runs, otherwise there is nothing to show here
		if "--screenshot" in OS.get_cmdline_args() + OS.get_cmdline_user_args():
			Net.host_game("SCREENSHOT GAME", Net.GAME_PORT, false)
		else:
			get_tree().change_scene_to_file("res://scenes/multiplayer.tscn")
			return
	Net.room_changed.connect(_refresh)
	Net.started.connect(_on_started)
	Net.host_lost.connect(_on_host_lost)
	map_list.visible = Net.role == Net.Role.HOST
	if map_list.visible:
		_build_map_list()
	_refresh()
	await SelfTests.maybe_screenshot(self, "screenshot_mp_lobby.png")


func _build_map_list() -> void:
	map_list.allow_reselect = true
	map_list.clear()
	map_list.add_theme_constant_override("icon_maximum_width", 36)
	var current := str(Net.room.get("map", ""))
	for e in MapCatalog.entries():
		if e.sandbox:
			continue
		var map_name := String(e.name)
		var m := MapCatalog.meta(map_name)
		map_list.add_item("%s  %dP" % [MapCatalog.display_title(map_name), m.players])
		map_list.set_item_icon(map_list.item_count - 1, MapPreview.texture(map_name))
		map_list.set_item_metadata(map_list.item_count - 1, String(e.path))
		if String(e.path) == current:
			map_list.select(map_list.item_count - 1)


func _refresh() -> void:
	if _launched or Net.role == Net.Role.OFFLINE or Net.room.is_empty():
		return
	var path := str(Net.room.get("map", ""))
	if path != "":
		var map_name := path.get_file().get_basename()
		var m := MapCatalog.meta(map_name)
		preview.texture = MapPreview.texture(map_name)
		map_name_label.text = MapCatalog.display_title(map_name)
		map_info_label.text = "%s   %dx%d   %d PLAYERS" % [
			m.terrain.to_upper(), m.width, m.height, m.players]
		if map_list.visible:
			for i in map_list.item_count:
				if str(map_list.get_item_metadata(i)) == path:
					if i not in map_list.get_selected_items():
						map_list.select(i)
					break
	_refresh_status()
	_rebuild_slots()
	_refresh_chat()
	_refresh_buttons()


func _refresh_status() -> void:
	if bool(Net.room.get("started", false)) and not _launched:
		status.text = "MATCH ALREADY IN PROGRESS"
		_bounce_soon()
	elif Net.role == Net.Role.HOST:
		var addr := " or ".join(Net.host_addresses) \
				if Net.host_addresses.size() > 0 else "UNKNOWN"
		status.text = "SHARE ADDRESS:  %s :%d" % [addr, Net.GAME_PORT]
	else:
		status.text = "ROOM:  %s" % str(Net.room.get("name", "?"))


func _rebuild_slots() -> void:
	for c in slots_box.get_children():
		c.queue_free()
	var my_id := Net.my_id()
	for slot in Net.room.get("slots", []):
		var team := int(slot.get("team", 0))
		var controller = slot.get("controller", "closed")
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.color = Teams.minimap_color(team)
		row.add_child(swatch)
		var seat := Button.new()
		seat.custom_minimum_size = Vector2(0, 26)
		seat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if controller is int:
			seat.text = _occupied_label(team, int(controller), my_id)
			seat.disabled = true
		else:
			var state := str(controller)
			seat.text = "%s : %s" % [_head(team),
					"TAKE SEAT" if state == "open" else state.to_upper()]
			seat.disabled = state != "open"
			if not seat.disabled:
				seat.pressed.connect(_sit.bind(team))
		row.add_child(seat)
		if Net.role == Net.Role.HOST and not (controller is int):
			var cycle := Button.new()
			cycle.custom_minimum_size = Vector2(74, 26)
			cycle.text = str(controller).to_upper()
			cycle.pressed.connect(Net.host_toggle_slot.bind(team))
			row.add_child(cycle)
		slots_box.add_child(row)


func _head(team: int) -> String:
	return "TEAM %d %s" % [team, Teams.display_name(team).to_upper()]


func _occupied_label(team: int, peer: int, my_id: int) -> String:
	var who := Net.player_name(peer)
	if peer == 1:
		who += " [HOST]"
	if peer == my_id:
		who += " - YOU"
	if bool(Net.room.players.get(peer, {}).get("ready", false)):
		who += " (READY)"
	return "%s : %s" % [_head(team), who]


func _refresh_chat() -> void:
	var lines: Array = Net.room.get("chat", [])
	var shown: PackedStringArray = []
	for i in range(maxi(0, lines.size() - 6), lines.size()):
		var e: Dictionary = lines[i]
		var who := str(e.get("name", ""))
		var text := str(e.get("text", ""))
		shown.append(who + ": " + text if who != "" else "* " + text + " *")
	chat_log.text = "\n".join(shown)


func _refresh_buttons() -> void:
	var i_am_host := Net.role == Net.Role.HOST
	start_btn.visible = i_am_host
	ready_btn.visible = not i_am_host
	if not i_am_host:
		var me: Dictionary = Net.room.players.get(Net.my_id(), {})
		ready_btn.set_pressed_no_signal(bool(me.get("ready", false)))


func _sit(team: int) -> void:
	if Net.role == Net.Role.HOST:
		Net.host_take_seat(team)
	else:
		Net.request_seat(team)


## A joiner that arrived after the match began sees the started room —
## show why and drift back to the browse screen.
func _bounce_soon() -> void:
	if _bounced:
		return
	_bounced = true
	await get_tree().create_timer(2.0).timeout
	if not _launched:
		Net.leave()
		get_tree().change_scene_to_file("res://scenes/multiplayer.tscn")


func _on_map_selected(index: int) -> void:
	Net.host_set_map(str(map_list.get_item_metadata(index)))


func _on_ready_toggled(on: bool) -> void:
	Net.set_ready(on)


func _on_start_pressed() -> void:
	if not Net.host_start():
		status.text = "START BLOCKED:  %s" % Net.start_blocker()


func _on_leave_pressed() -> void:
	Net.leave()
	get_tree().change_scene_to_file("res://scenes/multiplayer.tscn")


func _on_send_pressed() -> void:
	Net.send_chat(chat_input.text)
	chat_input.clear()


func _on_chat_submitted(_text: String) -> void:
	_on_send_pressed()


func _on_host_lost(reason: String) -> void:
	Net.last_error = reason
	Net.leave()
	get_tree().change_scene_to_file("res://scenes/multiplayer.tscn")


## The shared kickoff: exactly the skirmish launch chain, with every
## peer playing their own lobby team.
func _on_started(config: Dictionary) -> void:
	if _launched:
		return
	_launched = true
	GameState.prepare_match(MatchConfig.make("multiplayer",
			str(config.get("map", "")),
			Net.match_team if Net.match_team > 0 else 1))
	get_tree().change_scene_to_file("res://scenes/main.tscn")
