class_name EffectDef
extends Resource
## One visual effect — .tres files under content/effects/ plus one entry
## per sprite folder auto-discovered under assets/z/effects/. Scale is
## relative to the native art size; `grounded` effects bottom-anchor at
## the spawn point; art_name overrides the art folder (frames are named
## after the folder, not the def).

@export var id := "explosion"
@export var art_name := ""  # "" = same as id
@export var fps := 10.0
@export var scale := 1.0
@export var sound_set := ""  # Fx sound-set key ("" = silent)
@export var grounded := false
@export var fallback_color := Color(1.0, 0.8, 0.4)  # particle burst tint
