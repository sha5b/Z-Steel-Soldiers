class_name ProductionLine
extends RefCounted
## THE PRODUCTION LINE — one selected unit type, built over and over.
##
## Z HAS NO BUILD QUEUE. This used to be a five-slot FIFO, which was our
## invention and wrong from the first commit: you do not stack up orders
## in Z, you point a factory at ONE unit type and it turns that out
## indefinitely until you point it somewhere else. That difference is not
## cosmetic — a queue makes production a burst you pay for up front and
## then forget, while a line makes it a standing commitment you keep
## re-deciding, which is the whole economic texture of the game.
##
## So: `selected` is the type on the line ("kind:name", or "" for a
## factory that has been stopped), `elapsed` is the clock on the unit
## currently being built, and `paid` records whether that unit has been
## charged for yet. Completing a unit clears `paid` and leaves `selected`
## alone — the next one starts immediately.
##
## SWITCHING KEEPS THE CLOCK. Changing the selection mid-build carries
## the elapsed seconds over to the new type (and refunds the old unit, so
## the money stays straight — see Producer.select). Payment and spawning
## live in Producer; this class only tracks what and how far.

signal changed

## "kind:name" currently on the line; "" = stopped (a factory the player
## cancelled stays stopped — it does NOT quietly refill with a default).
var selected := ""
var elapsed := 0.0
## Has the unit in progress been charged for? Production stalls unpaid
## when the team is broke, at the population cap, or (a fort building
## cannons) out of free tower mounts — a stall must not silently bank
## time, and must not charge twice when it clears.
var paid := false


func is_running() -> bool:
	return selected != ""


## Point the line at a type. The clock CARRIES OVER by design; `paid`
## does not, because the new type costs something different and Producer
## refunds the old unit as it switches.
func select(item: String) -> void:
	if selected == item:
		return
	selected = item
	paid = false
	changed.emit()


## Stop producing entirely: the line goes idle and stays idle. This is
## what the panel's Cancel button does — a factory with nothing on it is
## a deliberate state, not a gap to be filled.
func stop() -> void:
	if selected == "" and elapsed == 0.0:
		return
	selected = ""
	elapsed = 0.0
	paid = false
	changed.emit()


func clear() -> void:
	selected = ""
	elapsed = 0.0
	paid = false


## Advance the clock; returns the finished type name or "". The caller
## must not call this until the unit in progress is `paid` for, so a
## stalled line accumulates nothing.
func tick(delta: float, seconds: float) -> String:
	if selected == "":
		elapsed = 0.0
		return ""
	elapsed += delta
	if elapsed < seconds:
		return ""
	elapsed = 0.0
	paid = false  # the next one on the line pays its own way
	changed.emit()
	return selected  # the line KEEPS its selection: build it again


## 0..1 progress of the unit currently building.
func progress(seconds: float) -> float:
	if selected == "":
		return 0.0
	return clampf(elapsed / seconds, 0.0, 1.0)
