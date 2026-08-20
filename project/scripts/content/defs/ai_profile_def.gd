class_name AiProfileDef
extends Resource
## One CPU difficulty profile — content/ai/{easy,normal,hard}.tres.
## Indexed by MatchState.ai_difficulty (0/1/2).

@export var think_seconds := 4.0        # OODA cadence
@export var attack_units := 10          # army size before the push
@export var bank_before_vehicle := 200  # savings floor before hardware
@export var man_radius := 320.0         # how far a robot walks to man
@export var max_claims := 6             # simultaneous zone captures
@export var man_priority := {           # hardware manning (firepower first)
	"heavy": 0, "missile_launcher": 1, "missile_cannon": 2, "medium": 3,
	"howitzer": 4, "light": 5, "gun": 6, "gatling": 7, "jeep": 8, "apc": 9,
	"crane": 10,
}
