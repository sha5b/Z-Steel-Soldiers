class_name EffectDefs
extends RefCounted
## Visual effects (explosions, impacts, muzzle flashes). Each name maps to
## a sprite folder `assets/z/effects/<name>/` containing frames named
## `<name>_n00.png`, `<name>_n01.png`, ... — any folder dropped there is
## auto-registered by ContentDB and becomes playable via `Fx.play(name)`.
## When a name has no sprite folder, Fx falls back to a native
## CPUParticles2D burst so gameplay effects never go missing.
##
## Fields: fps, scale, sound ("explosion" picks a random explosion wav,
## "" = silent), color (particle fallback tint).

const BY_NAME := {
	"explosion": {"fps": 10.0, "scale": 1.4, "sound": "explosion", "color": Color(1.0, 0.75, 0.3)},
	"explosion_big": {"fps": 8.0, "scale": 2.6, "sound": "explosion", "color": Color(1.0, 0.65, 0.25)},
	"impact": {"fps": 12.0, "scale": 0.7, "sound": "", "color": Color(1.0, 0.9, 0.5)},
	"muzzle": {"fps": 15.0, "scale": 0.8, "sound": "", "color": Color(1.0, 0.95, 0.6)},
}

const FALLBACK := {"fps": 10.0, "scale": 1.0, "sound": "", "color": Color(1.0, 0.8, 0.4)}
