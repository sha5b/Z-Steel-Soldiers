extends Node
## Autoload: match state — team money, zone income ticking, player team.

signal money_changed(team: int, amount: int)

const INCOME_PER_ZONE := 5.0   # money per owned zone per tick
const TICK_SECONDS := 1.0

var player_team := 1
var money := {1: 200, 2: 200, 3: 200, 4: 200}
var zones: Array[Node] = []
var _accum := 0.0


func _process(delta: float) -> void:
	_accum += delta
	while _accum >= TICK_SECONDS:
		_accum -= TICK_SECONDS
		for team in money:
			var income := 0
			for z in zones:
				if z.owner_team == team:
					income += INCOME_PER_ZONE
			money[team] += income
			money_changed.emit(team, money[team])


func register_zone(zone: Node) -> void:
	zones.append(zone)


func player_money() -> int:
	return money.get(player_team, 0)
