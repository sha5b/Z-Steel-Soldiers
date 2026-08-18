class_name ProjectileDef
extends Resource
## Travelling projectile for a weapon — damage lands on impact (Z-style,
## dodgeable) and the impact effect plays at the landing point.

@export var speed := 240.0
@export var impact := "impact"  # effect def name played at the landing
@export var texture: Texture2D = null  # flying sprite (null = tracer line)
