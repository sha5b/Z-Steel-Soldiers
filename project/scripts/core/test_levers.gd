class_name TestLevers
extends Object
## Headless-harness levers, out of MatchState (state purity): statics
## shared without autoload state, per the engine's own guidance for
## helper libraries since 4.1. Production code READS them; only the
## test harness writes them.


## 2-second builds regardless of defs (real build times are 72-373s).
static var fast_build := false

## Bypass move_and_slide — tight hand-stepped loops get no physics
## ticks, and move_and_slide does nothing until one. The physics-ON
## rig (--placement-test) flips this back off for its block.
static var direct_step := false
