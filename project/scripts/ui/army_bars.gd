class_name ArmyBars
extends Control
## The original bottom-left UNIT AMOUNT gauge. Zod's HUD draws exactly one
## 62x16 team-coloured strip at (132,460), crops it by unit_amount/max_units,
## then prints the current amount over it. The long centre trough is chat
## space, not one territory gauge per army.

const HUD_DIR := "res://assets/z/ui/hud"
const BAR_ART := Vector2(62.0, 16.0)

var _bar: TextureRect
var _label: Label
var _last_pop := -1
var _last_cap := -1
var _last_team := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar = TextureRect.new()
	_bar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_bar.stretch_mode = TextureRect.STRETCH_KEEP
	_bar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bar.clip_contents = true
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar)
	_label = Label.new()
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	HudFrame._apply_hud_font(_label, 10)
	add_child(_label)
	MatchState.current.zone_captured.connect(func(_team): _refresh(true))
	UnitRegistry.current.unit_spawned.connect(func(_unit): _refresh(true))
	UnitRegistry.current.unit_died.connect(func(_unit): _refresh(true))
	_refresh(true)


## The 66x24 black window in the left HUD cap. The original inset is 2px
## from its left and 4px from its top, yielding the native 62x16 bar.
func lay_out(region: Rect2) -> void:
	var at := region.position + Vector2(2.0, 4.0)
	_bar.position = at
	_bar.size = BAR_ART
	_label.position = at + Vector2(3.0, 0.0)
	_label.size = BAR_ART - Vector2(3.0, 0.0)
	_refresh(true)


func _process(_delta: float) -> void:
	# Manning/ejecting changes teams without spawning or killing hardware.
	# The integer guard keeps this effectively event-driven while covering that
	# transition and save-restore removals too.
	_refresh()


func _refresh(force := false) -> void:
	if MatchState.current == null or UnitRegistry.current == null \
			or _bar == null or _label == null:
		return
	var team := MatchState.current.player_team
	var used := MatchState.current.unit_pop(team)
	var cap := MatchState.current.unit_cap(team)
	if not force and used == _last_pop and cap == _last_cap and team == _last_team:
		return
	_last_pop = used
	_last_cap = cap
	_last_team = team
	var path := "%s/unit_amount_bar_%s.png" % [HUD_DIR,
		AnimLibrary.team_name(team)]
	_bar.texture = load(path) if ResourceLoader.exists(path) else null
	var share := clampf(float(used) / float(maxi(cap, 1)), 0.0, 1.0)
	_bar.size.x = roundf(BAR_ART.x * share)
	_label.text = str(used)
