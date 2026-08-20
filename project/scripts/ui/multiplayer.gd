extends Control
## Multiplayer browse: hosts on the LAN announce themselves
## (LanDiscovery — no master server) and appear here while this screen is
## open; HOST opens a room on this machine, JOIN (or double-click)
## connects straight to that host. The DIRECT field covers internet /
## VPN / port-forwarded hosts that broadcasts can't reach.

@onready var list: ItemList = %GameList
@onready var status: Label = %Status
@onready var direct_ip: LineEdit = %DirectIP

var _discovery: LanDiscovery
var _keys: Array[String] = []  # ItemList rows <-> announce keys


func _ready() -> void:
	UiTheme.apply(self)
	MusicPlayer.play_menu()
	$Background.texture = UiTheme.trimmed("res://assets/z/ui/IPBackground.png")
	list.allow_reselect = true
	_discovery = LanDiscovery.new()
	_discovery.game_found.connect(_on_game)
	_discovery.game_updated.connect(_on_game)
	_discovery.game_lost.connect(_on_gone)
	if not _discovery.listen():
		_set_status("DISCOVERY PORT BUSY - USE DIRECT IP")
	elif Net.last_error != "":
		_set_status(Net.last_error)
		Net.last_error = ""
	else:
		_set_status("SEARCHING THE LAN...")
	await SelfTests.maybe_screenshot(self, "screenshot_multiplayer.png")


func _process(_delta: float) -> void:
	_discovery.poll()


func _exit_tree() -> void:
	if _discovery != null:
		_discovery.stop_listen()


func _set_status(text: String) -> void:
	status.text = text


func _on_game(key: String, info: Dictionary) -> void:
	# JSON numbers arrive as floats — cast before formatting
	var row := "%s  -  %s  -  %d/%d" % [str(info.get("name", "?")),
			str(info.get("map", "?")), int(info.get("cur", 0)),
			int(info.get("max", 0))]
	var i := _keys.find(key)
	if i < 0:
		_keys.append(key)
		list.add_item(row)
		list.set_item_metadata(list.item_count - 1, key)
	else:
		list.set_item_text(i, row)
	if list.item_count > 0:
		var word := "GAME" if list.item_count == 1 else "GAMES"
		_set_status("%d %s ON THE LAN" % [list.item_count, word])


func _on_gone(key: String) -> void:
	var i := _keys.find(key)
	if i >= 0:
		_keys.remove_at(i)
		list.remove_item(i)
		if list.item_count == 0:
			_set_status("SEARCHING THE LAN...")


func _on_game_selected(_index: int) -> void:
	pass  # JOIN reads the selection when pressed


func _on_game_activated(_index: int) -> void:
	_on_join_pressed()


func _selected_info() -> Dictionary:
	var sel := list.get_selected_items()
	if sel.is_empty():
		return {}
	return _discovery.game_info(str(list.get_item_metadata(sel[0])))


func _on_join_pressed() -> void:
	var info := _selected_info()
	if info.is_empty():
		return
	if Net.join_game(str(info.get("ip", "")), int(info.get("port", 0))):
		get_tree().change_scene_to_file("res://scenes/mp_lobby.tscn")


func _on_join_direct_pressed() -> void:
	var text := direct_ip.text.strip_edges()
	if text == "":
		return
	var ip := text
	var port := Net.GAME_PORT
	if ":" in text:
		var parts := text.split(":")
		ip = parts[0]
		if parts.size() > 1 and parts[1].is_valid_int():
			port = int(parts[1])
	if Net.join_game(ip, port):
		get_tree().change_scene_to_file("res://scenes/mp_lobby.tscn")


func _on_direct_submitted(_text: String) -> void:
	_on_join_direct_pressed()


func _on_host_pressed() -> void:
	if Net.host_game("%s'S GAME" % GameSettings.player_name):
		get_tree().change_scene_to_file("res://scenes/mp_lobby.tscn")


func _on_back_pressed() -> void:
	Net.leave()
	get_tree().change_scene_to_file("res://scenes/title.tscn")
