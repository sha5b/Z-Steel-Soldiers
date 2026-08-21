class_name Order
extends RefCounted
## A unit order — the single intake is Unit2D.issue_order(); Commands
## (player clicks) and CpuAi both build these instead of writing entity
## fields. `run` sprints the order (shift-click); enter-type orders carry
## their target and the intent is explicit instead of overloading one
## variable five ways.

enum Type {
	MOVE,           # plain move; fight only when stopped
	ATTACK,         # chase THIS target until it dies
	MOVE_ATTACK,    # AGRO: halt and engage anything en route
	DEFEND,         # move there, then HOLD the post (returns when pushed off)
	MAN_VEHICLE,    # robot walks up and mans empty hardware
	BOARD_APC,      # robot loads as a passenger
	GARRISON,       # robot garrisons its own fort (missile crew)
	REPAIR_BUILDING,  # damaged vehicle enters the repair shop
	CRANE_REPAIR,   # manned crane rebuilds a damaged building/bridge
	STOP,           # CANCEL: drop whatever is in flight and stand here
					# (new ids go on the END — a multiplayer intent sends
					# int(type) over the wire)
}

var type: Type = Type.MOVE
var position := Vector2.ZERO  # MOVE / MOVE_ATTACK destination
var target: Node2D = null     # everything else
var run := false
## APPEND instead of replace (ctrl+right-click): the unit finishes what
## it is doing and runs this next. A non-queued order wipes the queue,
## which is what every plain click has always done.
var queued := false
## Order-confirmation art shown at the destination (PathIndicator).
## "" = derive from the type; Commands overrides it where the CLICK says
## more than the type does (walking onto a crate is a plain move).
var confirm := ""


## Which neutral cursor set confirms this order. The original ships one
## per order kind; a move is `placed`.
func confirm_marker() -> String:
	if confirm != "":
		return confirm
	match type:
		Type.ATTACK:
			return "attacked"
		Type.MAN_VEHICLE:
			return "cannoned" if target != null and target.get("kind") == "cannon" \
					else "entered"
		Type.BOARD_APC, Type.GARRISON:
			return "entered"
		Type.REPAIR_BUILDING, Type.CRANE_REPAIR:
			return "repaired"
		Type.STOP:
			return ""
		_:
			return "placed"


static func move(world_pos: Vector2, sprint := false) -> Order:
	var order := Order.new()
	order.type = Type.MOVE
	order.position = world_pos
	order.run = sprint
	return order


## Attack a specific enemy: close on it, fire from weapon range, and
## KEEP FOLLOWING it if it moves. Right-clicking an enemy used to fall
## through to a plain move — the unit walked to where the enemy was
## standing at click time and stopped there, which is why an attack
## order looked like it went to a position instead of a target.
static func attack(node: Node2D, sprint := false) -> Order:
	var order := Order.new()
	order.type = Type.ATTACK
	order.target = node
	order.position = node.global_position
	order.run = sprint
	return order


## STOP: forget the current order and the whole queue, hold this ground.
## The one basic command the game did not have — until this existed a
## move could only be replaced, never cancelled, so a squad walking into
## an ambush had to be sent somewhere else to be called off.
static func stop() -> Order:
	var order := Order.new()
	order.type = Type.STOP
	return order


## HOLD POSITION: a DEFEND post on the ground the unit already stands on.
## Unit2D arms it in place instead of pathing to its own feet.
static func hold(world_pos: Vector2) -> Order:
	var order := Order.new()
	order.type = Type.DEFEND
	order.position = world_pos
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
