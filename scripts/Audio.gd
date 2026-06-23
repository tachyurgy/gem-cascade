extends Node
## Procedural sound bank. Every SFX is SYNTHESIZED in code at boot and baked into
## an AudioStreamWAV buffer — there are no audio asset files, matching the game's
## all-shader, asset-free ethos. Sounds play through a small voice pool so they
## overlap cleanly during fast cascades. Registered as the `Audio` autoload.

const RATE := 22050
const POOL := 14

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _bank := {}
var muted := false


func _ready() -> void:
	# Keep mixing even if the tree is paused (e.g. during the record harness).
	process_mode = Node.PROCESS_MODE_ALWAYS
	for _i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	_build_bank()


## Fire a named sound. `pitch` shifts it (used to climb the combo ladder);
## `vol_db` trims level for the softer, more frequent cues.
func play(sound: String, pitch: float = 1.0, vol_db: float = 0.0) -> void:
	if muted or not _bank.has(sound):
		return
	var p := _players[_next]
	_next = (_next + 1) % POOL
	p.stream = _bank[sound]
	p.pitch_scale = pitch
	p.volume_db = vol_db
	p.play()


func set_muted(m: bool) -> void:
	muted = m


# ----------------------------------------------------------------- synthesis ---
## Append an oscillator voice (with optional pitch glide + envelope) onto a
## working buffer and return it. PackedArrays are copy-on-write, so we thread the
## buffer through the return value rather than mutating in place.
func _osc(buf: PackedFloat32Array, f0: float, f1: float, dur: float,
		wave: String, amp: float, atk: float, dec: float,
		t_off: float = 0.0) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var start := int(t_off * RATE)
	if buf.size() < start + n:
		buf.resize(start + n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var prog := float(i) / maxf(n - 1, 1)
		var f := lerpf(f0, f1, prog)
		phase += TAU * f / RATE
		var s := 0.0
		match wave:
			"sine": s = sin(phase)
			"square": s = signf(sin(phase))
			"saw": s = fmod(phase / TAU, 1.0) * 2.0 - 1.0
			"tri": s = asin(clampf(sin(phase), -1.0, 1.0)) * (2.0 / PI)
			"noise": s = randf() * 2.0 - 1.0
		var env := t / atk if t < atk else exp(-(t - atk) * dec)
		buf[start + i] += s * amp * env
	return buf


func _wav(buf: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w


func _build_bank() -> void:
	var b: PackedFloat32Array

	# select — a small, bright confirmation blip.
	b = PackedFloat32Array()
	b = _osc(b, 1320.0, 1320.0, 0.07, "sine", 0.32, 0.004, 60.0)
	_bank["select"] = _wav(b)

	# swap — a quick airy up-whoosh: filtered noise + a rising sine.
	b = PackedFloat32Array()
	b = _osc(b, 320.0, 720.0, 0.13, "sine", 0.22, 0.01, 26.0)
	b = _osc(b, 0.0, 0.0, 0.13, "noise", 0.05, 0.005, 40.0)
	_bank["swap"] = _wav(b)

	# invalid — a low, dull double buzz (the "nope").
	b = PackedFloat32Array()
	b = _osc(b, 150.0, 110.0, 0.10, "square", 0.20, 0.005, 28.0)
	b = _osc(b, 150.0, 110.0, 0.10, "square", 0.18, 0.005, 28.0, 0.11)
	_bank["invalid"] = _wav(b)

	# match — a plucky bell. Pitched up per combo step at play() time.
	b = PackedFloat32Array()
	b = _osc(b, 660.0, 660.0, 0.22, "tri", 0.30, 0.004, 22.0)
	b = _osc(b, 1320.0, 1320.0, 0.18, "sine", 0.14, 0.004, 30.0)   # octave shimmer
	b = _osc(b, 990.0, 990.0, 0.16, "sine", 0.08, 0.004, 34.0)     # fifth
	_bank["match"] = _wav(b)

	# special — a sparkly three-note rising arpeggio when a piece is forged.
	b = PackedFloat32Array()
	b = _osc(b, 784.0, 784.0, 0.10, "sine", 0.26, 0.004, 38.0, 0.00)
	b = _osc(b, 988.0, 988.0, 0.10, "sine", 0.26, 0.004, 38.0, 0.06)
	b = _osc(b, 1319.0, 1319.0, 0.16, "sine", 0.28, 0.004, 30.0, 0.12)
	_bank["special"] = _wav(b)

	# blast — a punchy boom: noise crack over a deep falling sine thump.
	b = PackedFloat32Array()
	b = _osc(b, 0.0, 0.0, 0.22, "noise", 0.30, 0.002, 24.0)
	b = _osc(b, 220.0, 60.0, 0.30, "sine", 0.45, 0.004, 13.0)
	b = _osc(b, 110.0, 40.0, 0.30, "tri", 0.22, 0.004, 12.0)
	_bank["blast"] = _wav(b)

	# land — a soft, short low thud as gems settle.
	b = PackedFloat32Array()
	b = _osc(b, 240.0, 150.0, 0.09, "sine", 0.30, 0.003, 48.0)
	_bank["land"] = _wav(b)

	# shuffle — a descending then ascending sweep (the board re-rolls).
	b = PackedFloat32Array()
	b = _osc(b, 700.0, 240.0, 0.22, "saw", 0.18, 0.01, 14.0)
	b = _osc(b, 240.0, 760.0, 0.26, "saw", 0.20, 0.01, 11.0, 0.20)
	_bank["shuffle"] = _wav(b)
