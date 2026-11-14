extends Node

const SAMPLE_RATE := 22050

var _players: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}


func _ready() -> void:
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.volume_db = -4.0
		add_child(p)
		_players.append(p)

	_streams["slash"] = _make_whoosh(0.18, 320.0, 900.0)
	_streams["windup"] = _make_tone(0.16, 340.0, 620.0)
	_streams["parry"] = _make_clang(0.32, 920.0, 1480.0)
	_streams["hit"] = _make_impact(0.16, 155.0)
	_streams["guard_break"] = _make_impact(0.24, 95.0)
	_streams["splash"] = _make_whoosh(0.45, 700.0, 180.0)
	_streams["bell"] = _make_tone(0.38, 660.0, 990.0)
	_streams["win"] = _make_fanfare()


func play_windup() -> void:
	play("windup", randf_range(0.95, 1.08), -7.0)


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


func _make_whoosh(duration: float, f_start: float, f_end: float) -> AudioStreamWAV:
	var count := int(duration * SAMPLE_RATE)
	var buf := PackedFloat32Array()
	buf.resize(count)
	var lp := 0.0
	for i in count:
		var t := float(i) / float(count)
		var env := sin(t * PI) * (1.0 - t * 0.35)
		var cutoff := lerpf(f_start, f_end, t) / float(SAMPLE_RATE) * 4.0
		var noise := randf_range(-1.0, 1.0)
		lp = lerpf(lp, noise, clampf(cutoff, 0.02, 0.9))
		buf[i] = lp * env * 0.65
	return _build_wav(buf)


func _make_clang(duration: float, f1: float, f2: float) -> AudioStreamWAV:
	var count := int(duration * SAMPLE_RATE)
	var buf := PackedFloat32Array()
	buf.resize(count)
	for i in count:
		var t := float(i) / float(SAMPLE_RATE)
		var env := exp(-t * 11.0)
		var s := sin(TAU * f1 * t) * 0.5 + sin(TAU * f2 * t) * 0.35 + sin(TAU * (f2 * 1.43) * t) * 0.2
		buf[i] = clampf(s * env * 0.75, -1.0, 1.0)
	return _build_wav(buf)


func _make_impact(duration: float, base_freq: float) -> AudioStreamWAV:
	var count := int(duration * SAMPLE_RATE)
	var buf := PackedFloat32Array()
	buf.resize(count)
	var phase := 0.0
	for i in count:
		var t := float(i) / float(SAMPLE_RATE)
		var progress := float(i) / float(count)
		var env := exp(-t * 18.0)
		var freq := lerpf(base_freq * 1.9, base_freq * 0.45, progress)
		phase += TAU * freq / float(SAMPLE_RATE)
		var thud := sin(phase) * 0.7 + randf_range(-0.3, 0.3) * exp(-t * 32.0)
		buf[i] = clampf(thud * env * 0.85, -1.0, 1.0)
	return _build_wav(buf)


func _make_tone(duration: float, f1: float, f2: float) -> AudioStreamWAV:
	var count := int(duration * SAMPLE_RATE)
	var buf := PackedFloat32Array()
	buf.resize(count)
	for i in count:
		var t := float(i) / float(SAMPLE_RATE)
		var freq := f1 if t < duration * 0.45 else f2
		var env := exp(-fmod(t, duration * 0.45) * 8.0)
		buf[i] = sin(TAU * freq * t) * env * 0.45
	return _build_wav(buf)


func _make_fanfare() -> AudioStreamWAV:
	var notes := [523.25, 659.25, 783.99, 1046.5]
	var note_dur := 0.13
	var total := int(notes.size() * note_dur * SAMPLE_RATE)
	var buf := PackedFloat32Array()
	buf.resize(total)
	for i in total:
		var t := float(i) / float(SAMPLE_RATE)
		var idx := mini(int(t / note_dur), notes.size() - 1)
		var local_t := t - float(idx) * note_dur
		var env := exp(-local_t * 6.0)
		buf[i] = sin(TAU * notes[idx] * t) * env * 0.5
	return _build_wav(buf)
