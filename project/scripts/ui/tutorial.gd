class_name TutorialScreen
extends Control
## HOW TO PLAY — the release's own tutorial pages (7 x 512px, from the
## GOG PNG set via tools/gog/convert_assets.py). They shipped in the
## release with nothing referencing them, so the remake had no
## instructions at all.
##
## Page art only: no text is rewritten, the original pages ARE the
## instructions.

const DIR := "res://assets/z/ui/tutorial"

var page := 0
var _pages: Array[Texture2D] = []

@onready var art: TextureRect = %Art
@onready var label: Label = %PageLabel
@onready var prev_btn: Button = %Prev
@onready var next_btn: Button = %Next


func _ready() -> void:
	UiTheme.apply(self)
	MusicPlayer.play_menu()
	_pages = load_pages()
	_show_page()


## Every converted page, in order. Static so a test can count them
## without building the screen.
static func load_pages() -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	var i := 1
	while true:
		var path := "%s/tutor%d.png" % [DIR, i]
		if not ResourceLoader.exists(path):
			break
		out.append(load(path))
		i += 1
	return out


## Move by `step` pages, clamped (no wrap: the pages are an ordered
## explanation, not a carousel). Returns the page actually shown.
func turn(step: int) -> int:
	if _pages.is_empty():
		return 0
	page = clampi(page + step, 0, _pages.size() - 1)
	_show_page()
	return page


func _show_page() -> void:
	if _pages.is_empty():
		label.text = "NO TUTORIAL PAGES CONVERTED"
		return
	art.texture = _pages[page]
	label.text = "%d / %d" % [page + 1, _pages.size()]
	prev_btn.disabled = page == 0
	next_btn.disabled = page == _pages.size() - 1


func _on_prev_pressed() -> void:
	turn(-1)
	Fx.ui_click()


func _on_next_pressed() -> void:
	turn(1)
	Fx.ui_click()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/title.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				_on_back_pressed()
			KEY_LEFT:
				turn(-1)
			KEY_RIGHT:
				turn(1)
