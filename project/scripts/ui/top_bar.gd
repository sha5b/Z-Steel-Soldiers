class_name TopBar
extends HBoxContainer
## Top bar: player money, zone ownership counts per team, match clock.

var elapsed := 0.0
var _money: Label
var _zones: Label
var _clock: Label
var _upgrades: HBoxContainer


func _ready() -> void:
	add_theme_constant_override("separation", 24)
	_money = _label("$ 200")
	_zones = _label("zones -")
	_clock = _label("0:00")
	_upgrades = HBoxContainer.new()
	_upgrades.add_theme_constant_override("separation", 4)
	add_child(_upgrades)


func _process(delta: float) -> void:
	elapsed += delta
	_money.text = "$ %d" % GameState.player_money()
	var counts := {}
	for z in GameState.zones:
		if z.owner_team != 0:
			counts[z.owner_team] = counts.get(z.owner_team, 0) + 1
	var mine: int = counts.get(GameState.player_team, 0)
	var total: int = GameState.zones.size()
	var theirs: int = counts.get(2, 0) if GameState.player_team != 2 else counts.get(1, 0)
	_zones.text = "zones %d/%d (them %d)" % [mine, total, theirs]
	_clock.text = "%d:%02d" % [int(elapsed) / 60, int(elapsed) % 60]
	_sync_upgrades()


## Original grenade/rocket crate icons while the upgrade is held.
func _sync_upgrades() -> void:
	var wanted := ""
	if GameState.has_upgrade(GameState.player_team, "grenades"):
		wanted += "g"
	if GameState.has_upgrade(GameState.player_team, "rockets"):
		wanted += "r"
	if _upgrades.get_meta("shown", "") == wanted:
		return
	_upgrades.set_meta("shown", wanted)
	for c in _upgrades.get_children():
		c.queue_free()
	for kind in wanted:
		var icon_path := "res://assets/z/ui/hud/icon_grenade_%s.png" % [
			AnimLibrary.team_name(GameState.player_team)]
		if ResourceLoader.exists(icon_path):
			var tex := TextureRect.new()
			tex.texture = load(icon_path)
			tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			tex.custom_minimum_size = Vector2(26, 26)
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			_upgrades.add_child(tex)


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	add_child(l)
	return l
