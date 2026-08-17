class_name Unit
extends CharacterBody3D
## Controllable robot/vehicle base. Placeholder capsule until original
## glTF models are wired in via the asset sync script.

const SPEED := 12.0
const TURN_SPEED := 8.0

@export var unit_name := "Psycho"
@export var team := 1

var selected := false

@onready var agent: NavigationAgent3D = $NavigationAgent3D
@onready var ring: MeshInstance3D = $SelectionRing
@onready var body_mesh: MeshInstance3D = $Body


func _ready() -> void:
	add_to_group("selectable")
	agent.navigation_finished.connect(func(): set_physics_process(false))
	set_selected(false)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = team_color(team)
	body_mesh.material_override = mat


func _physics_process(delta: float) -> void:
	if agent.is_navigation_finished():
		return
	var target := agent.get_next_path_position()
	var to_target := (target - global_position)
	to_target.y = 0.0
	var desired_dir := to_target.normalized()
	velocity = desired_dir * SPEED
	# face movement direction smoothly
	if desired_dir.length_squared() > 0.01:
		var look := Basis.looking_at(desired_dir, Vector3.UP)
		global_basis = global_basis.slerp(look, delta * TURN_SPEED)
	move_and_slide()


func move_to(world_pos: Vector3) -> void:
	agent.target_position = world_pos
	set_physics_process(true)


func set_selected(value: bool) -> void:
	selected = value
	ring.visible = value


static func team_color(team: int) -> Color:
	match team:
		1: return Color(0.2, 0.5, 1.0)
		2: return Color(1.0, 0.3, 0.2)
		3: return Color(0.3, 0.9, 0.3)
		_: return Color(0.9, 0.9, 0.2)
