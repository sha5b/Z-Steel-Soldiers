class_name TopBar
extends HBoxContainer
## Top bar: player money, zone ownership counts per team, match clock.

var elapsed := 0.0
var _money: Label
var _zones: Label
var _clock: Label


func _ready() -> void:
	add_theme_constant_override("separation", 24)
	_money = _label("$ 200")
	_zones = _label("zones -")
	_clock = _label("0:00")


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


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	add_child(l)
	return l
