class_name EffectDefs
extends RefCounted
## Visual effects (explosions, impacts, muzzle flashes). Each name maps to
## a sprite folder `assets/z/effects/<art>/` (art defaults to the def name)
## containing frames named `<name>_n00.png`, `<name>_n01.png`, ... — any
## folder dropped there is auto-registered by ContentDB and becomes
## playable via `Fx.play(name)`. When a name has no sprite folder, Fx
## falls back to a native CPUParticles2D burst so gameplay effects never
## go missing.
##
## Fields: fps, scale (RELATIVE to the 2x unit baseline — units render at
## 2x, so scale 1.0 shows the art at its authored proportion), sound
## ("explosion" picks a random explosion wav, "" = silent), grounded
## (bottom-anchor the effect at the spawn point — explosions rise from
## the ground), art (folder override), color (particle fallback tint).

const BY_NAME := {
	"explosion": {"fps": 10.0, "scale": 1.0, "sound": "explosion", "grounded": true,
		"color": Color(1.0, 0.75, 0.3)},
	"explosion_big": {"fps": 8.0, "scale": 1.25, "sound": "explosion", "grounded": true,
		"color": Color(1.0, 0.65, 0.25)},
	"impact": {"fps": 12.0, "scale": 0.55, "sound": "", "art": "spark",
		"color": Color(1.0, 0.9, 0.5)},
	"muzzle": {"fps": 15.0, "scale": 0.9, "sound": "",
		"color": Color(1.0, 0.95, 0.6)},
	"debris": {"fps": 12.0, "scale": 1.0, "sound": "", "grounded": true,
		"color": Color(0.6, 0.5, 0.4)},
	"fire0": {"fps": 8.0, "scale": 1.0, "sound": "", "art": "fire",
		"color": Color(1.0, 0.6, 0.2)},
	"fire1": {"fps": 8.0, "scale": 1.0, "sound": "", "art": "fire",
		"color": Color(1.0, 0.6, 0.2)},
}

const FALLBACK := {"fps": 10.0, "scale": 1.0, "sound": "", "color": Color(1.0, 0.8, 0.4)}
