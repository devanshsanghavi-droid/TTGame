extends Node
## Sfx autoload. Procedural ambience through an AudioStreamGenerator and
## synthesised one-shot effects. Silent (no-op) in headless runs.
##
##   Sfx.play("step", position)             one-shot (3D if a position is given)
##   Sfx.set_ambience({"wind": 0.6, "surf": 0.8})   per-era ambient bed
##
## Ambience layers: wind, surf, rain, fire, insects, crowd, drums, birds, rumble, drip

const MIX_RATE := 16000.0
const LAYERS := ["wind", "surf", "rain", "fire", "insects", "crowd", "drums", "birds", "rumble", "drip"]

var enabled := true
var played := {}

var _amb_player: AudioStreamPlayer
var _amb_playback: AudioStreamGeneratorPlayback
var _target := {}
var _gain := {}
var _phase := 0.0
var _lp := {}
var _rng := RandomNumberGenerator.new()
var _streams := {}
var _pool: Array[AudioStreamPlayer3D] = []
var _pool2d: Array[AudioStreamPlayer] = []
var _t := 0.0
var _crackle := 0.0
var _chirp_t := 0.0
var _chirp_f := 0.0
var _bird_t := 0.0
var _bird_f := 0.0
var _drip_t := 0.0
var _drip_env := 0.0
var _drum_env := 0.0
var _syll := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	enabled = DisplayServer.get_name() != "headless"
	for l in LAYERS:
		_target[l] = 0.0
		_gain[l] = 0.0
		_lp[l] = 0.0
	if not enabled:
		return
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.2
	_amb_player = AudioStreamPlayer.new()
	_amb_player.stream = gen
	_amb_player.volume_db = -9.0
	add_child(_amb_player)
	for i in 10:
		var p := AudioStreamPlayer3D.new()
		p.max_distance = 90.0
		p.unit_size = 6.0
		add_child(p)
		_pool.append(p)
	for i in 4:
		var p2 := AudioStreamPlayer.new()
		add_child(p2)
		_pool2d.append(p2)


func set_ambience(mix: Dictionary) -> void:
	for l in LAYERS:
		_target[l] = float(mix.get(l, 0.0))
	if enabled and _amb_player and not _amb_player.playing:
		_amb_player.play()
		_amb_playback = _amb_player.get_stream_playback()


func set_layer(layer: String, value: float) -> void:
	if _target.has(layer):
		_target[layer] = value


func stop_ambience() -> void:
	for l in LAYERS:
		_target[l] = 0.0


func play(sound: String, pos: Variant = null, volume_db := 0.0, pitch := 1.0) -> void:
	played[sound] = int(played.get(sound, 0)) + 1
	if not enabled:
		return
	var st := _stream(sound)
	if st == null:
		return
	if pos is Vector3:
		for p in _pool:
			if not p.playing:
				p.stream = st
				p.global_position = pos
				p.volume_db = volume_db
				p.pitch_scale = pitch * _rng.randf_range(0.94, 1.06)
				p.play()
				return
	else:
		for p in _pool2d:
			if not p.playing:
				p.stream = st
				p.volume_db = volume_db - 6.0
				p.pitch_scale = pitch
				p.play()
				return


## Register an era-specific one-shot under a name, then Sfx.play(name, pos).
func register(sound: String, stream: AudioStream) -> void:
	_streams[sound] = stream


## Build a mono one-shot from a function: fn(t_seconds, u_0_to_1, white_noise) -> sample in -1..1.
func make_wav(duration: float, fn: Callable, rate := 22050) -> AudioStreamWAV:
	var n := int(rate * duration)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in n:
		var v := clampf(float(fn.call(float(i) / rate, float(i) / n, rng.randf() * 2.0 - 1.0)), -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav


func _process(delta: float) -> void:
	if not enabled or _amb_playback == null:
		return
	for l in LAYERS:
		_gain[l] = move_toward(_gain[l], _target[l], delta * 0.5)
	var frames := _amb_playback.get_frames_available()
	if frames <= 0:
		return
	frames = mini(frames, 1600)
	var buf := PackedVector2Array()
	buf.resize(frames)
	var dt := 1.0 / MIX_RATE
	var g_wind: float = _gain.wind
	var g_surf: float = _gain.surf
	var g_rain: float = _gain.rain
	var g_fire: float = _gain.fire
	var g_ins: float = _gain.insects
	var g_crowd: float = _gain.crowd
	var g_drum: float = _gain.drums
	var g_bird: float = _gain.birds
	var g_rum: float = _gain.rumble
	var g_drip: float = _gain.drip
	var lp_w: float = _lp.wind
	var lp_s: float = _lp.surf
	var lp_c: float = _lp.crowd
	var lp_r: float = _lp.rumble
	var lp_f: float = _lp.fire
	for i in frames:
		_t += dt
		var n := _rng.randf() * 2.0 - 1.0
		var s := 0.0
		if g_wind > 0.001:
			lp_w += (n - lp_w) * (0.02 + 0.015 * sin(_t * 0.31))
			s += lp_w * g_wind * (0.9 + 0.5 * sin(_t * 0.17) * sin(_t * 0.41)) * 2.2
		if g_surf > 0.001:
			lp_s += (n - lp_s) * 0.09
			var swell := pow(0.5 + 0.5 * sin(_t * 0.62 + sin(_t * 0.11) * 1.5), 2.5)
			s += lp_s * g_surf * (0.15 + swell) * 1.3
		if g_rain > 0.001:
			s += n * g_rain * 0.16
		if g_fire > 0.001:
			lp_f += (n - lp_f) * 0.03
			if _rng.randf() < 0.0016 * (0.5 + g_fire):
				_crackle = 1.0
			_crackle *= 0.9965
			s += (lp_f * 1.4 + n * _crackle * 0.5) * g_fire
		if g_ins > 0.001:
			_chirp_t -= dt
			if _chirp_t <= 0.0:
				_chirp_t = _rng.randf_range(0.05, 0.5)
				_chirp_f = _rng.randf_range(2600.0, 4200.0)
			s += sin(_t * TAU * _chirp_f) * g_ins * 0.035 * (0.5 + 0.5 * sin(_t * TAU * 22.0))
		if g_bird > 0.001:
			_bird_t -= dt
			if _bird_t <= 0.0:
				_bird_t = _rng.randf_range(0.6, 3.5)
				_bird_f = _rng.randf_range(900.0, 2100.0)
			var be := clampf(_bird_t * 3.0, 0.0, 1.0) * clampf(1.0 - absf(fmod(_bird_t, 0.3) - 0.15) * 8.0, 0.0, 1.0)
			s += sin(_t * TAU * (_bird_f + 400.0 * sin(_t * 30.0))) * g_bird * 0.05 * be
		if g_crowd > 0.001:
			lp_c += (n - lp_c) * 0.06
			_syll += dt * (3.0 + 2.0 * sin(_t * 0.7))
			s += lp_c * g_crowd * (0.45 + 0.55 * absf(sin(_syll * 3.1) * sin(_syll * 1.7))) * 1.6
		if g_drum > 0.001:
			var beat := fmod(_t * 2.1, 1.0)
			if beat < dt * 2.1:
				_drum_env = 1.0
			_drum_env *= 0.9992
			s += sin(_t * TAU * (62.0 + 40.0 * _drum_env)) * _drum_env * g_drum * 0.7
		if g_rum > 0.001:
			lp_r += (n - lp_r) * 0.004
			s += lp_r * g_rum * 9.0
		if g_drip > 0.001:
			_drip_t -= dt
			if _drip_t <= 0.0:
				_drip_t = _rng.randf_range(0.3, 1.8)
				_drip_env = 1.0
			_drip_env *= 0.998
			s += sin(_t * TAU * (1400.0 + 900.0 * _drip_env)) * _drip_env * g_drip * 0.05
		s = clampf(s, -1.0, 1.0)
		buf[i] = Vector2(s, s)
	_lp.wind = lp_w
	_lp.surf = lp_s
	_lp.crowd = lp_c
	_lp.rumble = lp_r
	_lp.fire = lp_f
	_amb_playback.push_buffer(buf)


# ---------------------------------------------------------------- one-shots
func _stream(sound: String) -> AudioStream:
	if _streams.has(sound):
		return _streams[sound]
	var st: AudioStream = _kenney(sound)
	if st == null:
		st = _synth(sound)
	_streams[sound] = st
	return st


## If the Kenney packs were unzipped by hand into assets/audio/kenney/, prefer them.
func _kenney(sound: String) -> AudioStream:
	var map := {
		"step": "impact-sounds/footstep_concrete_000.ogg",
		"thud": "impact-sounds/impactSoft_heavy_000.ogg",
		"pickup": "rpg-audio/handleSmallLeather.ogg",
		"ui": "interface-sounds/click_001.ogg",
	}
	if not map.has(sound):
		return null
	var p := "res://assets/audio/kenney/" + String(map[sound])
	return load(p) if ResourceLoader.exists(p) else null


func _synth(sound: String) -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.2
	var kind := sound
	match sound:
		"step": dur = 0.09
		"step_wet": dur = 0.16
		"scan": dur = 0.7
		"rewind": dur = 0.6
		"glitch": dur = 0.35
		"portal": dur = 1.4
		"objective": dur = 0.5
		"pickup": dur = 0.08
		"thud": dur = 0.25
		"splash": dur = 0.5
		"ui": dur = 0.05
		"roar": dur = 1.6
		"call": dur = 1.1
		"horn": dur = 1.2
		"bell": dur = 1.4
		"hit": dur = 0.18
		"fire_whoosh": dur = 0.8
		"crack": dur = 0.3
		_:
			kind = "ui"
			dur = 0.05
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = sound.hash()
	var lp := 0.0
	for i in n:
		var t := float(i) / rate
		var u := float(i) / n
		var noise := rng.randf() * 2.0 - 1.0
		var s := 0.0
		match kind:
			"step":
				lp += (noise - lp) * 0.25
				s = lp * exp(-u * 7.0) * 0.9
			"step_wet":
				lp += (noise - lp) * 0.5
				s = lp * exp(-u * 4.0) * 0.6 + sin(t * TAU * (300.0 - 200.0 * u)) * exp(-u * 6.0) * 0.2
			"scan":
				s = sin(t * TAU * (520.0 + 900.0 * u * u)) * (1.0 - u) * 0.25 + sin(t * TAU * 131.0) * (1.0 - u) * 0.15
			"rewind":
				s = sin(t * TAU * (900.0 - 760.0 * u)) * 0.25 * (1.0 - u * 0.5) + noise * 0.08 * (1.0 - u)
			"glitch":
				var gate := 1.0 if fmod(t * 37.0, 1.0) < 0.5 else 0.0
				s = (noise * 0.25 + sin(t * TAU * 73.0) * 0.3) * gate * (1.0 - u)
			"portal":
				s = sin(t * TAU * (55.0 + 30.0 * sin(t * 9.0))) * 0.4 * sin(u * PI) + noise * 0.06 * sin(u * PI)
			"objective":
				s = (sin(t * TAU * 392.0) + sin(t * TAU * 587.0) * (1.0 if u >= 0.3 else 0.0)) * 0.14 * exp(-u * 2.5)
			"pickup":
				lp += (noise - lp) * 0.4
				s = lp * exp(-u * 5.0) * 0.5
			"thud", "hit":
				s = sin(t * TAU * (95.0 - 50.0 * u)) * exp(-u * 5.0) * 0.8 + noise * exp(-u * 20.0) * 0.3
			"splash":
				lp += (noise - lp) * 0.35
				s = lp * exp(-u * 3.5) * 0.8
			"ui":
				s = sin(t * TAU * 660.0) * exp(-u * 6.0) * 0.2
			"roar":
				lp += (noise - lp) * 0.06
				s = (lp * 2.5 + sin(t * TAU * (58.0 + 12.0 * sin(t * 23.0))) * 0.5) * sin(u * PI) * 0.8
			"call":
				s = sin(t * TAU * (420.0 + 260.0 * sin(u * PI) + 35.0 * sin(t * 60.0))) * sin(u * PI) * 0.4
			"horn":
				s = (sin(t * TAU * 174.0) + 0.5 * sin(t * TAU * 348.0) + 0.25 * sin(t * TAU * 522.0)) * sin(u * PI) * 0.3
			"bell":
				s = (sin(t * TAU * 440.0) + 0.6 * sin(t * TAU * 1108.0) + 0.3 * sin(t * TAU * 1870.0)) * exp(-u * 4.0) * 0.25
			"fire_whoosh":
				lp += (noise - lp) * (0.05 + 0.2 * u)
				s = lp * sin(u * PI) * 1.2
			"crack":
				s = noise * exp(-u * 14.0) * 0.9
		var v := int(clampf(s, -1.0, 1.0) * 32000.0)
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav
