class_name AnnouncePlaque
extends Control
## The commander's PRINTED announcements — the original's comp_messages
## plaques (`FORT UNDER ATTACK`, `ROBOT MANUFACTURED`, ...). The voice
## lines for these events were already wired; the matching art shipped
## in the pack with nothing referencing it, so a player with the sound
## off got no message at all.
##
## Driven by one signal (Fx.announced), so an event that gains a plaque
## needs no code here: drop `<event>.png` into assets/z/ui/comp/.

const DIR := "res://assets/z/ui/comp"
const HOLD_SECONDS := 1.8
const FADE_SECONDS := 0.7
const SCALE := 2.0  # the plaques are 128x14 originals; the HUD is 2x

var _icon: TextureRect


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon = TextureRect.new()
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.modulate.a = 0.0
	add_child(_icon)
	Fx.announced.connect(_on_announced)


## Only events that ship a plaque show one; the rest stay voice-only.
static func plaque_path(event: String) -> String:
	var path := "%s/%s.png" % [DIR, event]
	return path if ResourceLoader.exists(path) else ""


func _on_announced(event: String) -> void:
	show_event(event)


## Public so a headless test can drive it without the audio path.
func show_event(event: String) -> bool:
	var path := plaque_path(event)
	if path == "" or _icon == null:
		return false
	var tex: Texture2D = load(path)
	_icon.texture = tex
	_icon.size = tex.get_size() * SCALE
	_icon.position = Vector2(-_icon.size.x * 0.5, 0.0)  # centred on the anchor
	_icon.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(HOLD_SECONDS)
	tween.tween_property(_icon, "modulate:a", 0.0, FADE_SECONDS)
	return true
