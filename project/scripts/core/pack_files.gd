class_name PackFiles
extends Object
## Directory listings that survive an EXPORT.
##
## Godot rewrites the files it packs. A text resource is converted to
## binary (`foo.tres` -> `foo.res`, `foo.tscn` -> `foo.scn`) and an
## imported image becomes a compressed texture (`bar.png` -> `bar.ctex`
## under `.godot/imported/`); each one stays reachable through its
## ORIGINAL path because the pack also carries a `<original>.remap`
## pointer. `load("res://…/foo.tres")` therefore keeps working in a
## build — but `DirAccess.get_files()` returns the REWRITTEN names.
##
## Every scan in this project filtered on the source extension
## (`entry.ends_with(".tres")`, `f.get_extension() == "png"`). In the
## editor those matched; in an exported build they matched NOTHING, so
## the packaged game came up with no building defs, no unit folders and
## no effect art while every test passed in the editor. `list()` folds
## the export's names back to the source names so one scan works in
## both.

## Export rewrite -> source extension.
const REWRITTEN := {
	"res": "tres",
	"scn": "tscn",
	"ctex": "png",
	"ctexarray": "png",
	"oggvorbisstr": "ogg",
	"sample": "wav",
}


## Files in `path`, named as they are in the PROJECT (never as the pack
## stores them). The `.import` / `.remap` sidecar an export ships for a
## converted file is folded back into the name it stands for, and
## duplicates are collapsed — in the editor the same list comes back
## unchanged.
##
## What a build actually contains, measured (`--teams-test` printed it):
## an imported image appears in its source directory ONLY as
## `foo.png.import`, with the real texture living in `.godot/imported/`
## under a hashed `.ctex` name. So a scan must strip that suffix; nothing
## in the art folders is named `.png` at all.
static func list(path: String) -> PackedStringArray:
	var dir := DirAccess.open(path)
	if dir == null:
		return PackedStringArray()
	var seen := {}
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir():
			seen[_to_source(entry)] = true
		entry = dir.get_next()
	dir.list_dir_end()
	var out := PackedStringArray()
	for name in seen:
		out.append(String(name))
	out.sort()
	return out


## Subdirectories of `path`. Directory names are not rewritten by the
## export, but an empty directory is not packed at all — so a folder that
## only ever held imported images still shows up (its `.remap` entries
## keep it alive) while a genuinely empty one does not.
static func dirs(path: String) -> PackedStringArray:
	var dir := DirAccess.open(path)
	if dir == null:
		return PackedStringArray()
	var out := PackedStringArray()
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir() and not entry.begins_with("."):
			out.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


## Files in `path` whose SOURCE extension is `ext` ("png", "tres", ...).
static func with_ext(path: String, ext: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in list(path):
		if f.get_extension() == ext:
			out.append(f)
	return out


static func has_ext(path: String, ext: String) -> bool:
	for f in list(path):
		if f.get_extension() == ext:
			return true
	return false


## One packed name -> the project name it stands for.
static func _to_source(entry: String) -> String:
	var name := entry
	# both sidecars are already named after the ORIGINAL file
	for sidecar in [".import", ".remap"]:
		if name.ends_with(sidecar):
			return name.trim_suffix(sidecar)
	var ext := name.get_extension()
	if REWRITTEN.has(ext):
		return "%s.%s" % [name.get_basename(), REWRITTEN[ext]]
	return name
