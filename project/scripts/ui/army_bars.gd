class_name ArmyBars
extends Control
## The bottom bar's army gauges — the original's `unit_amount_bar` art,
## which shipped in the pack and had no consumer (docs/RESEARCH.md 2d
## listed it as missing).
##
## One gauge per team in the match: a count in the number window and a bar
## whose LENGTH is that team's share of all units on the field. The
## screenshots show exactly two, red and blue, reading "04" and "06" —
## each side's standing army, which is the number that matters in a game
## with no resources to count.
##
## Rebuilt when the team list changes, resized on a unit being built or
## dying (UnitRegistry's roster signal) — never per frame.

const HUD_DIR := "res://assets/z/ui/hud"
const BAR_ART := Vector2(62.0, 16.0)
const GAUGE_GAP := 6.0
const COUNT_W := 30.0
## The black count window the left cap draws, and the metal strip between
## it and the start of the grey track.
const WINDOW_W := 66.0
const METAL_W := 10.0

var _region := Rect2()
var _gauges := {}   # team -> {label: Label, bar: TextureRect}
var _pending_rebuild := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# a build or a death changes the count; a capture can change who is
	# even on the board
	# _rebuild inside a signal handler would free nodes mid-emit
	UnitRegistry.current.unit_spawned.connect(func(_u): _refresh())
	UnitRegistry.current.unit_died.connect(func(_u): _refresh())
	MatchState.current.zone_captured.connect(func(_team): _refresh())
	_rebuild()


## The bar's own window, handed down by the frame (it owns the geometry).
func lay_out(region: Rect2) -> void:
	_region = region
	_place()
	_refresh()   # also the seam that first builds the gauges once a map is up


func _rebuild() -> void:
	_pending_rebuild = false
	for c in get_children():
		c.queue_free()
	_gauges.clear()
	for team in _teams():
		var count := Label.new()
		count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		HudFrame._apply_hud_font(count, 16)
		add_child(count)
		var bar := TextureRect.new()
		bar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		# KEEP, not stretch: the bar shows strength by LENGTH, and a
		# stretched 62px plate would just squash its bevel
		bar.stretch_mode = TextureRect.STRETCH_KEEP
		bar.clip_contents = true
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var path := "%s/unit_amount_bar_%s.png" % [HUD_DIR,
				AnimLibrary.team_name(team)]
		if ResourceLoader.exists(path):
			bar.texture = load(path)
		add_child(bar)
		_gauges[team] = {"label": count, "bar": bar}
	_place()
	_refresh()


## Rebuild on the next idle frame: _refresh can run from a signal, and
## freeing the gauge nodes while that signal is still being emitted is
## how you get "attempt to call on a previously freed instance".
func _rebuild_deferred() -> void:
	if _pending_rebuild:
		return
	_pending_rebuild = true
	_rebuild.call_deferred()


## Every team with a fort on this map, player first — the gauges read
## left to right in the order the bottom bar's windows do.
func _teams() -> Array[int]:
	var found: Array[int] = []
	var mine: int = MatchState.current.player_team
	for b in Engine.get_main_loop().root.get_tree().get_nodes_in_group(
			Groups.BUILDINGS):
		if b is FortBuilding and b.team != 0 and not found.has(b.team):
			found.append(b.team)
	found.sort()
	if found.has(mine):
		found.erase(mine)
		found.push_front(mine)
	return found


## The first gauge's count goes in the frame's own black window; the bars
## run along the grey TRACK, which starts where the left cap ends. Laying
## every gauge out by an even split put bar art on the solid metal strip
## between the two.
func _place() -> void:
	if _region.size.x <= 0.0 or _gauges.is_empty():
		return
	var track_x: float = _region.position.x + WINDOW_W + METAL_W
	var track_w: float = maxf(_region.end.x - track_x, 1.0)
	var n: float = float(_gauges.size())
	var slot: float = (track_w - GAUGE_GAP * (n - 1.0)) / n
	var i := 0
	for team in _gauges:
		var g: Dictionary = _gauges[team]
		var label: Label = g["label"]
		var bar: TextureRect = g["bar"]
		var slot_x: float = track_x + float(i) * (slot + GAUGE_GAP)
		# gauge 1 reads out of the black window the art draws for it;
		# the rest label themselves at the head of their own bar
		label.position = Vector2(_region.position.x if i == 0 else slot_x,
				_region.position.y)
		label.size = Vector2(WINDOW_W if i == 0 else COUNT_W, _region.size.y)
		var bar_x: float = slot_x + (0.0 if i == 0 else COUNT_W + 2.0)
		bar.position = Vector2(bar_x,
				_region.position.y + (_region.size.y - BAR_ART.y) * 0.5)
		bar.size = Vector2(maxf(slot_x + slot - bar_x, 1.0), BAR_ART.y)
		bar.set_meta("full_width", bar.size.x)
		i += 1
	_refresh()


func _refresh() -> void:
	# The map loads AFTER the HUD is built, so at _ready there are no
	# forts and no gauges. Bailing out on an empty set meant the gauges
	# could never appear at all — the team check has to run first.
	var live := _teams()
	if live.size() != _gauges.size() or live.any(func(t): return not _gauges.has(t)):
		_rebuild_deferred()
		return
	var counts := {}
	var total := 0
	for team in _gauges:
		# COUNT, not pop cost: the original's gauge reads "how many
		# robots do I have", and a tank is one unit on it like a grunt
		var n: int = UnitRegistry.current.alive_of_team(team).size()
		counts[team] = n
		total += n
	for team in _gauges:
		var g: Dictionary = _gauges[team]
		(g["label"] as Label).text = "%02d" % int(counts[team])
		var bar: TextureRect = g["bar"]
		var full: float = float(bar.get_meta("full_width", bar.size.x))
		var share: float = float(counts[team]) / float(maxi(total, 1))
		bar.size.x = maxf(roundf(full * share), 1.0)
