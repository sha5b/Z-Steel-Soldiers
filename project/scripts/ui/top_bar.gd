class_name TopBar
extends HBoxContainer
## Top bar: player money, zone ownership counts per team, match clock.
## Money and zone counts refresh on their signals (no per-frame polling);
## the clock mirrors the SIM clock (MatchState.current.match_time — what drives
## the tech ladder), not a UI-side accumulator that drifts from it.

var _money: Label
var _zones: Label
var _pop: Label
var _clock: Label
var _upgrades: HBoxContainer


func _ready() -> void:
	add_theme_constant_override("separation", 24)
	_money = _label("credits 200")
	_zones = _label("zones -")
	_pop = _label("pop -")
	_clock = _label("0:00")
	_upgrades = HBoxContainer.new()
	_upgrades.add_theme_constant_override("separation", 4)
	add_child(_upgrades)
	MatchState.current.money_changed.connect(func(_team, _amount): _refresh_counts())
	MatchState.current.zone_captured.connect(func(_team): _refresh_counts())
	_refresh_counts()


func _process(_delta: float) -> void:
	var t: int = int(MatchState.current.match_time)
	_clock.text = "%d:%02d" % [t / 60, t % 60]


func _refresh_counts() -> void:
	_money.text = "credits %d" % MatchState.current.player_money()
	var counts := {}
	for z in MatchState.current.zones:
		if z.owner_team != 0:
			counts[z.owner_team] = counts.get(z.owner_team, 0) + 1
	var mine: int = counts.get(MatchState.current.player_team, 0)
	var total: int = MatchState.current.zones.size()
	var theirs := 0
	for t in counts:
		if t != MatchState.current.player_team:
			theirs += counts[t]
	_zones.text = "zones %d of %d - them %d" % [mine, total, theirs]
	_pop.text = "pops %d/%d" % [MatchState.current.unit_pop(
		MatchState.current.player_team), MatchState.current.unit_cap(
		MatchState.current.player_team)]
	_sync_upgrades()


## Original grenade/rocket crate icons while the upgrade is held.
func _sync_upgrades() -> void:
	var wanted := ""
	if MatchState.current.has_upgrade(MatchState.current.player_team, "grenades"):
		wanted += "g"
	if MatchState.current.has_upgrade(MatchState.current.player_team, "rockets"):
		wanted += "r"
	if _upgrades.get_meta("shown", "") == wanted:
		return
	_upgrades.set_meta("shown", wanted)
	for c in _upgrades.get_children():
		c.queue_free()
	for _kind in wanted:
		# only grenade art ships in the original HUD; rockets are the
		# same crate line, shown with its icon
		var icon_path := "res://assets/z/ui/hud/icon_grenade_%s.png" % [
			AnimLibrary.team_name(MatchState.current.player_team)]
		if ResourceLoader.exists(icon_path):
			var tex := TextureRect.new()
			tex.texture = load(icon_path)
			tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			tex.custom_minimum_size = Vector2(26, 26)
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			_upgrades.add_child(tex)


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	add_child(label)
	return label
