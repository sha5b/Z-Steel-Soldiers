class_name TestRig
extends RefCounted
## Per-test assertion rig for the headless harness. A test block starts
## one, checks conditions as it goes, and finishes with a one-line
## verdict. Failed checks print `CHECK FAILED:` lines — the sweep treats
## those exactly like SCRIPT ERROR lines, so a printed-but-unasserted
## regression can no longer pass silently (see README).

var test_name: String
var problems: Array[String] = []
## Set by any failed check; a block can query it to skip stages that
## only make sense after earlier checks held.
var failed := false


static func start(test_name: String) -> TestRig:
	var rig := TestRig.new()
	rig.test_name = test_name
	return rig


func check(cond: bool, message: String) -> void:
	if cond:
		return
	problems.append(message)
	failed = true
	print("CHECK FAILED: %s: %s" % [test_name, message])


func finish(details: String = "") -> void:
	var suffix := ""
	if details != "":
		suffix = " " + details
	if problems.is_empty():
		print("%s: ok%s" % [test_name, suffix])
	else:
		print("%s: FAIL - %d problem(s)%s" % [test_name, problems.size(), suffix])
