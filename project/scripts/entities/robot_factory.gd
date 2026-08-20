class_name RobotFactory
extends Building2D
## Robot factory: belongs to the team owning its zone. Builds from the
## robot-factory build list for its level (robots AND the smaller
## cannons, like the original) — production is queue-driven for the
## player and the CPU opponent alike, money- and cap-gated.


func kind_key() -> String:
	return "robot_factory"


func producer_key() -> String:
	return "robot_factory"
