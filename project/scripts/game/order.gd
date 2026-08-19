class_name Order
extends RefCounted
## A unit order — the single intake is Unit2D.issue_order(); Commands
## (player clicks) and CpuAi both build these instead of writing entity
## fields. `run` sprints the order (shift-click); enter-type orders carry
## their target and the intent is explicit instead of overloading one
## variable five ways.

enum Type {
	MOVE,           # plain move; fight only when stopped
	MOVE_ATTACK,    # AGRO: halt and engage anything en route
	DEFEND,         # move there, then HOLD the post (returns when pushed off)
	MAN_VEHICLE,    # robot walks up and mans empty hardware
	BOARD_APC,      # robot loads as a passenger
	GARRISON,       # robot garrisons its own fort (missile crew)
	REPAIR_BUILDING,  # damaged vehicle enters the repair shop
	CRANE_REPAIR,   # manned crane rebuilds a damaged building/bridge
}

var type: Type = Type.MOVE
var position := Vector2.ZERO  # MOVE / MOVE_ATTACK destination
var target: Node2D = null     # everything else
var run := false


static func move(world_pos: Vector2, sprint := false) -> Order:
	var order := Order.new()
	order.type = Type.MOVE
	order.position = world_pos
	order.run = sprint
	return order


static func move_attack(world_pos: Vector2, sprint := false) -> Order:
	var order := Order.new()
	order.type = Type.MOVE_ATTACK
	order.position = world_pos
	order.run = sprint
	return order


static func move_defend(world_pos: Vector2, sprint := false) -> Order:
	var order := Order.new()
	order.type = Type.DEFEND
	order.position = world_pos
	order.run = sprint
	return order


## Resolve an enter-type order from whatever was clicked: the intent
## follows the target's type (fort -> garrison, APC -> board, empty
## hardware -> man, repair shop -> repair, other building -> crane work).
static func for_target(node: Node2D, sprint := false) -> Order:
	var order := Order.new()
	order.target = node
	order.run = sprint
	if node is FortBuilding:
		order.type = Type.GARRISON
	elif node is Vehicle2D and (node as Vehicle2D).is_apc():
		order.type = Type.BOARD_APC
	elif node is Vehicle2D:
		order.type = Type.MAN_VEHICLE
	elif node is Building2D and (node as Building2D).is_repair_shop():
		order.type = Type.REPAIR_BUILDING
	else:
		order.type = Type.CRANE_REPAIR
	return order
