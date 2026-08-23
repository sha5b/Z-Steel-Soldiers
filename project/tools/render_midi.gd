extends Node
## Pure-Godot MIDI renderer: the zod soundtrack's .MID files to playable
## WAVs with NOTHING external — no fluidsynth, no soundfont, no ffmpeg.
## Run headless from project/:
##   flatpak run org.godotengine.Godot --headless --path . \
##       res://tools/render_midi.tscn
##
## It parses Standard MIDI File format 1 (varlen deltas, tempo events)
## and synthesizes a compact General-MIDI approximation in GDScript —
## oscillator families per program group, key-classified percussion,
## attack/release envelopes — then writes 22 kHz 16-bit mono WAVs to
## assets/z/music/. It is the FALLBACK for players without the GOG
## recording set; the GOG .ogg tracks remain the real soundtrack.
## Approximation: tempo changes apply from the moment they parse (no
## retroactive re-time) — fine for these files, noted for honesty.

const SRC_DIR := "res://../assets_original/zod/sounds"
const DST_DIR := "res://assets/z/music"
const RATE := 16000
const NORMALIZE := 0.89


func _ready() -> void:
	# res://.. collapses oddly in some loaders — the OS path is the
	# reliable one for reading OUTSIDE the project
	var dir := DirAccess.open(ProjectSettings.globalize_path("res://")
			+ "/../assets_original/zod/sounds")
	if dir == null:
		dir = DirAccess.open(SRC_DIR)
	if dir == null:
		push_error("no zod sounds dir (copy the zod pack first)")
		get_tree().quit(1)
		return
	var all := dir.get_files()
	print("midi source: %d files" % all.size())
	for i in mini(all.size(), 6):
		print("  file: ", all[i])
	var rendered := 0
	for f in dir.get_files():
		var lower := f.to_lower()
		if not lower.ends_with(".mid"):
			continue
		var out := "%s/zod_%s.wav" % [DST_DIR, lower.get_basename()]
		if FileAccess.file_exists(out):
			print("skip ", f)
			continue
		var src_path := ProjectSettings.globalize_path("res://") \
				+ "/../assets_original/zod/sounds/" + f
		var parsed := _parse_midi(src_path)
		if parsed.is_empty():
			push_error("no notes in %s" % f)
			continue
		var wav := _synthesize(parsed["notes"])
		var err := wav.save_to_wav(out)
		if err != OK:
			push_error("write %s: %s" % [out, err])
			continue
		print("render ", f, " -> ", out, " (%.1fs, %d notes)"
			% [float(wav.data.size()) / 2.0 / RATE, parsed["notes"].size()])
		rendered += 1
	print("done: %d tracks" % rendered)
	get_tree().quit()


# ----------------------------- SMF parsing ------------------------------

func _parse_midi(path: String) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes == null or bytes.size() < 14 or bytes.slice(0, 4) != "MThd".to_ascii_buffer():
		return {}
	var division := bytes.decode_u16(12)
	if division & 0x8000:
		push_error("SMPTE timing not supported")
		return {}
	var usec_per_tick := 500000.0 / float(division)  # 120 bpm default
	var notes := []
	var open := {}  # (ch<<8)|key -> Array of note dicts
	var pos := 14
	while pos + 8 <= bytes.size():
		var chunk := bytes.slice(pos, pos + 4).get_string_from_ascii()
		var len := bytes.decode_u32(pos + 4)
		var body := pos + 8
		var end := body + len
		var p := body
		if chunk == "MTrk":
			var tick := 0
			var run := 0
			var channel_prog := {}
			while p < end:
				var dv := _varlen(bytes, p)
				tick += dv[0]
				p = dv[1]
				var status := bytes[p]
				if status < 0x80:
					status = run
				else:
					p += 1
					if status < 0xF0:
						run = status
				if status == 0xFF:
					var mtype := bytes[p]
					p += 1
					var ml := _varlen(bytes, p)
					p = ml[1]
					if mtype == 0x51 and ml[0] == 3:
						var tempo: int = (bytes[p] << 16) | (bytes[p + 1] << 8) | bytes[p + 2]
						usec_per_tick = float(tempo) / float(division)
					p += ml[0]
				elif status == 0xF0 or status == 0xF7:
					var sl := _varlen(bytes, p)
					p = sl[1] + sl[0]
				else:
					var ch := status & 0x0F
					match status & 0xF0:
						0x90, 0x80:
							var key := bytes[p]
							var vel := bytes[p + 1]
							p += 2
							var id := (ch << 8) | key
							if status & 0xF0 == 0x90 and vel > 0:
								var n := {
									"ch": ch, "key": key, "vel": vel / 127.0,
									"prog": int(channel_prog.get(ch, 0)),
									"on": tick * usec_per_tick / 1000000.0,
								}
								notes.append(n)
								if not open.has(id):
									open[id] = []
								open[id].append(n)
							elif open.has(id) and not open[id].is_empty():
								(open[id].pop_back())["off"] = tick * usec_per_tick / 1000000.0
						0xC0:
							channel_prog[ch] = bytes[p]
							p += 1
						0xB0, 0xA0, 0xE0:
							p += 2
						0xD0:
							p += 1
						_:
							p += 1
		pos = end
	for n in notes:
		if not n.has("off"):
			n["off"] = n["on"] + (0.12 if n["ch"] == 9 else 0.35)
	return {"notes": notes}


func _varlen(bytes: PackedByteArray, p: int) -> Array:
	var v := 0
	while true:
		var b: int = bytes[p]
		p += 1
		v = (v << 7) | (b & 0x7F)
		if b < 0x80:
			break
	return [v, p]


# ---------------------------- synthesis ---------------------------------

func _synthesize(notes: Array) -> AudioStreamWAV:
	var total := 0.0
	for n in notes:
		total = maxf(total, n["off"])
	var count := int((total + 1.0) * RATE)
	var buf := PackedFloat32Array()
	buf.resize(count)

	for n in notes:
		var freq := 440.0 * pow(2.0, (n["key"] - 69) / 12.0)
		var start := int(n["on"] * RATE)
		var dur: float = minf(n["off"] - n["on"] + 0.05, 4.0)
		var frames := int(dur * RATE)
		var gain: float = n["vel"] * (0.5 if n["ch"] == 9 else 0.3)
		for i in frames:
			var idx := start + i
			if idx >= count:
				break
			var t := float(i) / RATE
			var s := _sample(n, freq, t)
			var env := clampf(t / 0.01, 0.0, 1.0) * clampf((dur - t) / 0.04, 0.0, 1.0)
			buf[idx] += s * gain * env

	var pcm := PackedByteArray()
	pcm.resize(count * 2)
	for i in count:
		pcm.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * NORMALIZE * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = pcm
	return wav


## One sample of a note: oscillator family by program group, drums by
## KEY (the GM percussion map's region, not the channel's program).
func _sample(n: Dictionary, freq: float, t: float) -> float:
	if n["ch"] == 9:
		var key: int = n["key"]
		if key <= 41:  # bass drum region
			return sin(TAU * (58.0 + 340.0 * maxf(0.0, 0.05 - t) * 8.0) * t) \
				* maxf(0.0, 1.0 - t / 0.16)
		if key == 42 or key == 44 or key == 46:  # closed/edge hats
			return (randf() * 2.0 - 1.0) * maxf(0.0, 1.0 - t / 0.045) * 0.7
		if key >= 39 or key == 37:  # snare side/rim region
			return (randf() * 2.0 - 1.0) * maxf(0.0, 1.0 - t / 0.11)
		return sin(TAU * freq * t * 0.5)  # toms: pitched sine
	var prog: int = n["prog"]
	if prog >= 24 and prog < 32 or prog >= 48 and prog < 56 or prog >= 80 and prog < 88:
		return fmod(freq * t, 1.0) * 2.0 - 1.0  # guitars/strings/lead: saw
	if prog >= 32 and prog < 48 or prog >= 56 and prog < 64 or prog >= 88 and prog < 96:
		return 1.0 if fmod(freq * t, 1.0) < 0.5 else -1.0  # bass/brass: square
	return sin(TAU * freq * t)  # keys, organ, flutes, pads: sine
