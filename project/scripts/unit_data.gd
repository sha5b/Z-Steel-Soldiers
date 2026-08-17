class_name UnitData
## Static stats per unit type. Ballparked from Z gameplay; tune later.

const ROBOTS := {
	"grunt":  {"hp": 42, "damage": 4,  "range": 58.0, "cooldown": 0.75, "speed": 60.0, "cost": 40},
	"psycho": {"hp": 46, "damage": 3,  "range": 58.0, "cooldown": 0.40, "speed": 62.0, "cost": 60},
	"sniper": {"hp": 34, "damage": 15, "range": 110.0, "cooldown": 1.80, "speed": 58.0, "cost": 80},
	"tough":  {"hp": 72, "damage": 8,  "range": 50.0, "cooldown": 1.10, "speed": 50.0, "cost": 70},
	"pyro":   {"hp": 52, "damage": 6,  "range": 40.0, "cooldown": 0.60, "speed": 56.0, "cost": 70},
	"laser":  {"hp": 44, "damage": 10, "range": 85.0, "cooldown": 1.30, "speed": 56.0, "cost": 90},
}
const VEHICLES := {
	"jeep":   {"hp": 60,  "damage": 5,  "range": 62.0, "cooldown": 0.55, "speed": 95.0, "cost": 0},
	"light":  {"hp": 90,  "damage": 9,  "range": 78.0, "cooldown": 1.00, "speed": 75.0, "cost": 0},
	"medium": {"hp": 130, "damage": 14, "range": 88.0, "cooldown": 1.40, "speed": 62.0, "cost": 0},
	"heavy":  {"hp": 190, "damage": 22, "range": 96.0, "cooldown": 2.00, "speed": 50.0, "cost": 0},
	"apc":    {"hp": 150, "damage": 0,  "range": 0.0,  "cooldown": 9.9, "speed": 80.0, "cost": 0},
}
const CANNONS := {
	"gatling": {"hp": 55, "damage": 3, "range": 95.0, "cooldown": 0.35, "speed": 0.0, "cost": 0},
}


static func stats_for(kind: String, type_name: String) -> Dictionary:
	match kind:
		"robot": return ROBOTS.get(type_name, ROBOTS.grunt)
		"vehicle": return VEHICLES.get(type_name, VEHICLES.jeep)
		"cannon": return CANNONS.get(type_name, CANNONS.gatling)
	return ROBOTS.grunt
