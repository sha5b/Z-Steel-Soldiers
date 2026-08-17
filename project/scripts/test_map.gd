extends Node3D
## Test map: 256x256 ground (demo map size), demo unit squad, orders via
## right click. Placeholder visuals until original models are synced in.

const UNIT := preload("res://scenes/unit.tscn")

@onready var camera_rig: Node3D = $RtsCamera
@onready var ground: StaticBody3D = $Ground


func _ready() -> void:
	SelectionManager.order_issued.connect(_on_order)
	_build_ground()
	_build_navmesh()
	for i in 6:
		var u := UNIT.instantiate()
		u.unit_name = ["Psycho", "Pyro", "Grunt"][i % 3]
		u.team = 1
		u.position = Vector3(60.0 + (i % 3) * 4.0, 1.0, 60.0 + (i / 3) * 4.0)
		add_child(u)


func _build_ground() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(256, 256)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.76, 0.66, 0.45)
	$Ground/GroundMesh.mesh = mesh
	$Ground/GroundMesh.material_override = mat


func _build_navmesh() -> void:
	var nm := NavigationMesh.new()
	var h := 128.0
	nm.vertices = PackedVector3Array([
		Vector3(-h, 0.0, -h), Vector3(h, 0.0, -h), Vector3(h, 0.0, h), Vector3(-h, 0.0, h)])
	nm.add_polygon(PackedInt32Array([0, 3, 2, 1]))
	$NavigationRegion3D.navigation_mesh = nm


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				SelectionManager.drag_start = event.position
				SelectionManager.drag_current = event.position
				SelectionManager.is_dragging = true
			else:
				SelectionManager.is_dragging = false
				var rect := SelectionManager.get_drag_rect()
				if rect.size.length() < 6.0:
					_pick_select(event.position)
				else:
					SelectionManager.select_area(rect)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var pos = _raycast_ground(event.position)
			if pos:
				SelectionManager.issue_order(pos)
	elif event is InputEventMouseMotion and SelectionManager.is_dragging:
		SelectionManager.drag_current = event.position


func _pick_select(screen_pos: Vector2) -> void:
	var cam: Camera3D = camera_rig.camera
	var from: Vector3 = cam.project_ray_origin(screen_pos)
	var dir: Vector3 = cam.project_ray_normal(screen_pos)
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 1000.0)
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit and hit.collider.owner is Unit:
		SelectionManager.toggle_select(hit.collider.owner, Input.is_key_pressed(KEY_SHIFT))
	else:
		SelectionManager.clear_selection()


func _raycast_ground(screen_pos: Vector2) -> Variant:
	var cam: Camera3D = camera_rig.camera
	var from: Vector3 = cam.project_ray_origin(screen_pos)
	var dir: Vector3 = cam.project_ray_normal(screen_pos)
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 2000.0, 0xFFFFFFFF)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position if hit else null


func _on_order(world_position: Vector3) -> void:
	for u in SelectionManager.selected:
		u.move_to(world_position)
