extends Node

const SAMPLE_RATE := 22050

var _players: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}


func _ready() -> void:
	for i in 12:
		var p := AudioStreamPlayer.new()
		p.volume_db = -4.0
		add_child(p)
		_players.append(p)

	_streams["slash"] = _make_whoosh(0.16, 260.0, 1250.0, 0.72)
	_streams["heavy_slash"] = _make_whoosh(0.22, 180.0, 1600.0, 0.90)
	_streams["thrust"] = _make_whoosh(0.14, 700.0, 2200.0, 0.78)
	_streams["windup"] = _make_tone(0.16, 340.0, 620.0)
	_streams["parry"] = _make_clang(0.36, 980.0, 1560.0)
	_streams["perfect_parry"] = _make_clang(0.55, 1180.0, 2090.0)
	_streams["block"] = _make_impact(0.14, 240.0)
	_streams["hit"] = _make_impact(0.18, 155.0)
	_streams["guard_break"] = _make_shatter(0.32)
	_streams["dash"] = _make_whoosh(0.12, 480.0, 240.0, 0.45)
	_streams["splash"] = _make_whoosh(0.45, 760.0, 160.0, 0.80)
	_streams["bell"] = _make_bell(0.42, 740.0, 1110.0)
	_streams["charge"] = _make_tone(0.24, 520.0, 1046.5)
	_streams["win"] = _make_fanfare()


func play_windup() -> void:
	play("windup", randf_range(0.95, 1.08), -7.5)


func play_slash_by_power(power: float, is_thrust: bool = false) -> void:
	if is_thrust:
		play("thrust", clampf(0.92 + power * 0.16, 0.85, 1.32), clampf(-7.5 + power * 2.2, -9.0, -2.5))
		return
	var s_name := "heavy_slash" if power >= 1.15 else "slash"
	var pitch := clampf(0.84 + power * 0.24 + randf_range(-0.04, 0.04), 0.78, 1.38)
	var vol := clampf(-8.0 + power * 2.6, -9.5, -1.5)
	play(s_name, pitch, vol)


func play(sound_name: String, pitch_scale: float = 1.0, volume_db: float = -4.0) -> void:
	if not _streams.has(sound_name):
		return
	for p in _players:
		if not p.playing:
			p.stream = _streams[sound_name]
			p.pitch_scale = pitch_scale
			p.volume_db = volume_db
			p.play()
			return
	_players[0].stream = _streams[sound_name]
	_players[0].pitch_scale = pitch_scale
	_players[0].volume_db = volume_db
	_players[0].play()


func _build_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		var v := clampi(int(samples[i] * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = data
	return wav


func _make_whoosh(duration: float, f_start: float, f_end: float, gain: float = 0.65) -> AudioStreamWAV:
	var count := int(duration * SAMPLE_RATE)
	var buf := PackedFloat32Array()
	buf.resize(count)
	var lp := 0.0
	for i in count:
		var t := float(i) / float(count)
		var env := sin(t * PI) * (1.0 - t * 0.28)
		var cutoff := lerpf(f_start, f_end, t) / float(SAMPLE_RATE) * 4.5
		var noise := randf_range(-1.0, 1.0)
		lp = lerpf(lp, noise, clampf(cutoff, 0.02, 0.92))
		buf[i] = clampf(lp * env * gain, -1.0, 1.0)
	return _build_wav(buf)


func _make_clang(duration: float, f1: float, f2: float) -> AudioStreamWAV:
	var count := int(duration * SAMPLE_RATE)
	var buf := PackedFloat32Array()
	buf.resize(count)
	for i in count:
		var t := float(i) / float(SAMPLE_RATE)
		var env := exp(-t * 9.5)
		var transient := exp(-t * 90.0) * randf_range(-0.35, 0.35)
		var s := sin(TAU * f1 * t) * 0.45 + sin(TAU * f2 * t) * 0.35 + sin(TAU * (f2 * 1.49) * t) * 0.22
		buf[i] = clampf((s * env + transient) * 0.78, -1.0, 1.0)
	return _build_wav(buf)


func _make_impact(duration: float, base_freq: float) -> AudioStreamWAV:
	var count := int(duration * SAMPLE_RATE)
	var buf := PackedFloat32Array()
	buf.resize(count)
	var phase := 0.0
	for i in count:
		var t := float(i) / float(SAMPLE_RATE)
		var progress := float(i) / float(count)
		var env := exp(-t * 17.0)
		var freq := lerpf(base_freq * 2.1, base_freq * 0.42, progress)
		phase += TAU * freq / float(SAMPLE_RATE)
		var thud := sin(phase) * 0.72 + randf_range(-0.35, 0.35) * exp(-t * 34.0)
		buf[i] = clampf(thud * env * 0.85, -1.0, 1.0)
	return _build_wav(buf)


func _make_shatter(duration: float) -> AudioStreamWAV:
	var count := int(duration * SAMPLE_RATE)
	var buf := PackedFloat32Array()
	buf.resize(count)
	var phase := 0.0
	for i in count:
		var t := float(i) / float(SAMPLE_RATE)
		var env := exp(-t * 10.5)
		phase += TAU * lerpf(580.0, 110.0, clampf(t / duration, 0.0, 1.0)) / float(SAMPLE_RATE)
		var crack := sin(phase) * 0.45 + sin(TAU * 1340.0 * t) * exp(-t * 22.0) * 0.3 + randf_range(-0.5, 0.5) * exp(-t * 18.0)
		buf[i] = clampf(crack * env * 0.85, -1.0, 1.0)
	return _build_wav(buf)


func _make_tone(duration: float, f1: float, f2: float) -> AudioStreamWAV:
	var count := int(duration * SAMPLE_RATE)
	var buf := PackedFloat32Array()
	buf.resize(count)
	var phase := 0.0
	for i in count:
		var t := float(i) / float(SAMPLE_RATE)
		var progress := clampf(t / duration, 0.0, 1.0)
		var freq := lerpf(f1, f2, progress)
		phase += TAU * freq / float(SAMPLE_RATE)
		var env := sin(progress * PI) * (1.0 - progress * 0.25)
		buf[i] = sin(phase) * env * 0.42
	return _build_wav(buf)


func _make_bell(duration: float, f1: float, f2: float) -> AudioStreamWAV:
	var count := int(duration * SAMPLE_RATE)
	var buf := PackedFloat32Array()
	buf.resize(count)
	for i in count:
		var t := float(i) / float(SAMPLE_RATE)
		var env := exp(-t * 6.5) * clampf(t * 120.0, 0.0, 1.0)
		var s := sin(TAU * f1 * t) * 0.6 + sin(TAU * f2 * t) * 0.35 + sin(TAU * (f1 * 2.0) * t) * 0.15
		buf[i] = clampf(s * env * 0.52, -1.0, 1.0)
	return _build_wav(buf)


func _make_fanfare() -> AudioStreamWAV:
	var notes := [523.25, 659.25, 783.99, 1046.5]
	var note_dur := 0.13
	var total := int(notes.size() * note_dur * SAMPLE_RATE)
	var buf := PackedFloat32Array()
	buf.resize(total)
	var phase := 0.0
	for i in total:
		var t := float(i) / float(SAMPLE_RATE)
		var idx := mini(int(t / note_dur), notes.size() - 1)
		var local_t := t - float(idx) * note_dur
		phase += TAU * notes[idx] / float(SAMPLE_RATE)
		var attack := clampf(local_t * 110.0, 0.0, 1.0)
		var env := exp(-local_t * 6.5) * attack
		buf[i] = sin(phase) * env * 0.48
	return _build_wav(buf)
