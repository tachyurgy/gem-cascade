extends Node
## Synthesized, seamlessly-looping background soundtrack. Built entirely in code at
## boot (bass + arpeggio + soft pad + kick/hat groove) and baked into one looping
## AudioStreamWAV — no audio files, matching the game's synth ethos. Registered as
## the `Music` autoload. Ducks briefly when a big blast goes off.

const RATE := 44100
const BPM := 124.0

var _player: AudioStreamPlayer
var _base_db := -10.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.bus = "Master"
	_player.volume_db = _base_db
	add_child(_player)
	_player.stream = _build_loop()
	_player.play()


func set_muted(m: bool) -> void:
	_player.volume_db = -80.0 if m else _base_db


## Briefly dip the music so a blast/finisher cuts through, then swell back.
func duck(amount_db: float = 9.0, hold: float = 0.18) -> void:
	if Audio.muted:
		return
	var t := create_tween()
	t.tween_property(_player, "volume_db", _base_db - amount_db, 0.04)
	t.tween_interval(hold)
	t.tween_property(_player, "volume_db", _base_db, 0.5)


# ------------------------------------------------------------- synthesis ---
func _note(buf: PackedFloat32Array, freq: float, start: float, dur: float,
		wave: String, amp: float, dec: float) -> void:
	var n := int(dur * RATE)
	var s0 := int(start * RATE)
	var atk := 0.006
	var phase := 0.0
	for i in n:
		var idx := s0 + i
		if idx < 0 or idx >= buf.size():
			continue
		var t := float(i) / RATE
		phase += TAU * freq / RATE
		var v := 0.0
		match wave:
			"sine": v = sin(phase)
			"tri": v = asin(clampf(sin(phase), -1.0, 1.0)) * (2.0 / PI)
			"saw": v = fmod(phase / TAU, 1.0) * 2.0 - 1.0
			"square": v = signf(sin(phase))
			"noise": v = randf() * 2.0 - 1.0
		var env := (t / atk) if t < atk else exp(-(t - atk) * dec)
		buf[idx] += v * amp * env


# Note frequencies (Hz).
const NOTE := {
	"A2": 110.00, "C3": 130.81, "E3": 164.81, "F3": 174.61, "G3": 196.00,
	"A3": 220.00, "C4": 261.63, "D4": 293.66, "E4": 329.63, "F4": 349.23,
	"G4": 392.00, "A4": 440.00, "C5": 523.25, "E5": 659.25, "G5": 783.99,
}


func _build_loop() -> AudioStreamWAV:
	var beat := 60.0 / BPM
	var bars := 4
	var beats_per_bar := 4
	var total_beats := bars * beats_per_bar
	var loop_len := total_beats * beat
	var buf := PackedFloat32Array()
	buf.resize(int(loop_len * RATE) + 4)

	# Chord progression: Am - F - C - G  (vi IV I V in C major), one bar each.
	var roots := ["A2", "F3", "C3", "G3"]
	var chords := [
		["A3", "C4", "E4"],   # Am
		["F3", "A3", "C4"],   # F
		["C4", "E4", "G4"],   # C
		["G3", "D4", "G4"],   # G
	]
	# A bright arpeggio pattern (which chord-tone to ping per 16th note).
	var arp_seq := [0, 1, 2, 1, 0, 2, 1, 2]

	for bar in bars:
		var bar_t := bar * beats_per_bar * beat
		var root: float = NOTE[roots[bar]]
		var chord: Array = chords[bar]

		# Bass: root on every beat, with a little octave bounce on the off-beats.
		for b in beats_per_bar:
			var bt := bar_t + b * beat
			_note(buf, root, bt, beat * 0.9, "tri", 0.34, 6.0)
			_note(buf, root * 2.0, bt + beat * 0.5, beat * 0.4, "square", 0.05, 12.0)

		# Soft sustained pad — gentle chord bed (decays before the bar ends → no
		# click at the loop boundary).
		for nm in chord:
			_note(buf, NOTE[nm], bar_t, beat * 3.6, "sine", 0.07, 1.1)

		# Sparkly arpeggio — two 8th-note runs per bar.
		for step in 8:
			var at := bar_t + step * (beat * 0.5)
			var tone: float = NOTE[chord[arp_seq[step] % chord.size()]] * 2.0
			_note(buf, tone, at, beat * 0.45, "tri", 0.12, 9.0)
			_note(buf, tone * 1.5, at, beat * 0.30, "sine", 0.04, 14.0)  # fifth shimmer

		# Groove: kick on 1 & 3, hat on every off-beat.
		for b in beats_per_bar:
			var bt := bar_t + b * beat
			if b % 2 == 0:
				_kick(buf, bt)
			_hat(buf, bt + beat * 0.5)

	# Soft master limiter so the layers never clip.
	for i in buf.size():
		buf[i] = clampf(buf[i] * 0.85, -0.98, 0.98)

	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		bytes.encode_s16(i * 2, int(buf[i] * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = int(loop_len * RATE)
	return w


func _kick(buf: PackedFloat32Array, at: float) -> void:
	# Pitch-dropping sine = punchy kick.
	var n := int(0.16 * RATE)
	var s0 := int(at * RATE)
	var phase := 0.0
	for i in n:
		var idx := s0 + i
		if idx < 0 or idx >= buf.size():
			continue
		var t := float(i) / RATE
		var f := lerpf(150.0, 48.0, clampf(t / 0.10, 0.0, 1.0))
		phase += TAU * f / RATE
		var env: float = exp(-t * 22.0)
		buf[idx] += sin(phase) * 0.5 * env


func _hat(buf: PackedFloat32Array, at: float) -> void:
	var n := int(0.04 * RATE)
	var s0 := int(at * RATE)
	for i in n:
		var idx := s0 + i
		if idx < 0 or idx >= buf.size():
			continue
		var t := float(i) / RATE
		buf[idx] += (randf() * 2.0 - 1.0) * 0.07 * exp(-t * 90.0)
