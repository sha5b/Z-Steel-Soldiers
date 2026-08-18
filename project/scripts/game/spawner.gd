class_name Spawner
extends Object
## The single spawn path for every unit in the game (map loading,
## factory production, sniper ejections, save restore). Scenes resolve
## through ContentDB.scene_for: the per-type scene when one exists
## (convention: scenes/<kind-plural>/<name>.tscn), else the base scene.

static func spawn(parent: Node, kind: String, unit_name: String, team: int,
		world_pos: Vector2, manned := false) -> Node2D:
	var scene := ContentDB.scene_for(kind, unit_name)
	if scene == null:
		return null
	var node: Node2D = scene.instantiate()
	if node is Vehicle2D:
		# setup_vehicle(owner_team): non-zero = spawns manned for that team
		(node as Vehicle2D).setup_vehicle(kind, unit_name, team if manned else 0)
	else:
		node.set("unit_name", unit_name)
		node.set("team", team)
	node.position = world_pos
	parent.add_child(node)
	return node
