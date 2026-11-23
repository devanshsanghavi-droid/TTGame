class_name ChronoDevice extends Node
## CHRONO: the wrist AI. Scanner pulse, 5-second rewind, and the MALFUNCTION
## system (timed + contextual glitches with real gameplay effects).

signal glitch_started(kind: String)
signal glitch_ended(kind: String)
signal scanned
signal rewound(seconds: float)
signal said(text: String)

const SCAN_COOLDOWN := 5.0
const REWIND_COOLDOWN := 18.0
const REWIND_SECONDS := 5.0

## Built-in glitches: kind -> duration in seconds.
const BUILTIN := {
	"gravity_flicker": 5.0,
	"era_flash": 5.0,
	"translation_failure": 22.0,
	"time_stutter": 4.0,
	"yell": 1.5,
}

const DEFAULT_LINES := {
	"gravity_flicker": [
		"Gravity is currently a suggestion. I have filed a complaint with myself.",
		"Local gravity reduced by seventy-eight percent. You are welcome. I am sorry.",
	],
	"era_flash": [
		"Small temporal bleed. Try not to touch anything from the wrong millennium.",
		"We are briefly somewhen else. Same spot. Different problems.",
	],
	"translation_failure": [
		"Translation module offline. Everyone now sounds like a kettle.",
		"I have lost the local language. Smile and point. It works for tourists.",
	],
	"time_stutter": [
		"Time is buffering. Everything else, I mean. You are fine.",
		"The universe has dropped some frames.",
	],
	"yell": [
		"ATTENTION. BATTERY AT FORTY PERCENT. THIS HAS BEEN A LOUD ANNOUNCEMENT.",
		"REMINDER. YOU ARE TRYING TO BE QUIET. END OF REMINDER.",
	],
}

var era: Node
var player: Player
var hud: Node
var charge := 1.0
var scan_enabled := true
var rewind_enabled := true
var glitches_enabled := true
var glitch_pool: Array = []
var glitch_interval := Vector2(38.0, 70.0)
var glitch_lines := {}
var active_glitches := {}
var translation_broken := false
var scan_cooldown := 0.0
var rewind_cooldown := 0.0
var stats := {"scans": 0, "rewinds": 0, "glitches": {}, "lines": 0}

var _custom := {}
var _history: Array = []
var _hist_acc := 0.0
var _next_glitch := 30.0
var _said_once := {}
var _rng := RandomNumberGenerator.new()


func setup(p_era: Node, p_player: Player, p_hud: Node, rng_seed: int) -> void:
	era = p_era
	player = p_player
	hud = p_hud
	_rng.seed = rng_seed
	_next_glitch = _rng.randf_range(glitch_interval.x * 0.6, glitch_interval.y * 0.8)


## Era-specific glitch. `start` and `finish` take no arguments.
func register_glitch(kind: String, duration: float, start: Callable, finish := Callable(), lines: Array = []) -> void:
	_custom[kind] = {"duration": duration, "start": start, "finish": finish}
	if lines.size() > 0:
		glitch_lines[kind] = lines
	if not glitch_pool.has(kind):
		glitch_pool.append(kind)


func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	scan_cooldown = maxf(0.0, scan_cooldown - delta)
	rewind_cooldown = maxf(0.0, rewind_cooldown - delta)
	# rewind history
	_hist_acc += delta
	if _hist_acc >= 0.1 and player.alive:
		_hist_acc = 0.0
		var snap := player.snapshot()
		if era and era.has_method("rewind_capture"):
			snap["era"] = era.rewind_capture()
		_history.append(snap)
		if _history.size() > int(REWIND_SECONDS * 10.0) + 1:
			_history.pop_front()
	if not player.control_locked or player.input.bot:
		if player.input.scan:
			scan()
		if player.input.rewind:
			rewind()
	# active glitches
	for kind in active_glitches.keys():
		active_glitches[kind] -= delta
		if active_glitches[kind] <= 0.0:
			_end_glitch(kind)
	# scheduler
	if glitches_enabled and glitch_pool.size() > 0 and player.alive:
		_next_glitch -= delta
		if _next_glitch <= 0.0:
			_next_glitch = _rng.randf_range(glitch_interval.x, glitch_interval.y)
			var options: Array = []
			for k in glitch_pool:
				if not active_glitches.has(k):
					options.append(k)
			if options.size() > 0:
				trigger_glitch(options[_rng.randi() % options.size()])


# ------------------------------------------------------------------ scanner
func scan() -> bool:
	if not scan_enabled or scan_cooldown > 0.0:
		return false
	scan_cooldown = SCAN_COOLDOWN
	stats.scans += 1
	var marks: Array = []
	if era:
		for n in era.get_tree().get_nodes_in_group("poi"):
			var n3 := n as Node3D
			if n3 and n3.is_inside_tree() and n3.is_visible_in_tree():
				marks.append({"node": n3, "label": n3.get_meta("poi_label", "?"), "kind": n3.get_meta("poi_kind", "poi")})
		if era.has_method("on_scan"):
			era.on_scan(marks)
		era.mark("chrono_scan")
	if hud:
		hud.show_scan(marks, 7.0)
	Sfx.play("scan")
	Telemetry.log_event("scan", {"marks": marks.size()})
	scanned.emit()
	return true


# ------------------------------------------------------------------- rewind
func rewind() -> bool:
	if not rewind_enabled or rewind_cooldown > 0.0 or _history.size() < 8 or not player.alive:
		return false
	var snap: Dictionary = _history[0]
	var seconds := _history.size() * 0.1
	_history.clear()
	rewind_cooldown = REWIND_COOLDOWN
	stats.rewinds += 1
	player.restore(snap)
	if era:
		if snap.has("era") and era.has_method("rewind_restore"):
			era.rewind_restore(snap.era)
		era.mark("chrono_rewind")
	if hud:
		hud.glitch_fx(0.9, 0.7)
	Sfx.play("rewind")
	Telemetry.log_event("rewind", {"seconds": seconds, "to": snap.pos})
	rewound.emit(seconds)
	return true


# ------------------------------------------------------------------ glitches
func trigger_glitch(kind: String) -> bool:
	if active_glitches.has(kind) or player == null or not player.alive:
		return false
	var duration: float
	if _custom.has(kind):
		duration = _custom[kind].duration
		_custom[kind].start.call()
	elif BUILTIN.has(kind):
		duration = BUILTIN[kind]
		match kind:
			"gravity_flicker":
				player.gravity_scale = 0.22
			"era_flash":
				if era:
					era.set_era_flash(true)
			"translation_failure":
				translation_broken = true
			"time_stutter":
				if era:
					era.world_time_scale = 0.3
			"yell":
				player.bump_noise(1.0)
				if era:
					era.emit_noise(player.global_position, 45.0, 1.0, "chrono")
	else:
		return false
	active_glitches[kind] = duration
	stats.glitches[kind] = int(stats.glitches.get(kind, 0)) + 1
	if hud:
		hud.glitch_fx(0.75 if kind != "translation_failure" else 0.4, minf(duration, 5.0))
	Sfx.play("glitch")
	var lines: Array = glitch_lines.get(kind, DEFAULT_LINES.get(kind, []))
	if lines.size() > 0:
		say(lines[_rng.randi() % lines.size()], true)
	if era:
		era.mark("glitch")
		era.mark("glitch:" + kind)
	Telemetry.log_event("glitch", {"glitch": kind, "duration": duration})
	glitch_started.emit(kind)
	return true


func _end_glitch(kind: String) -> void:
	active_glitches.erase(kind)
	if _custom.has(kind):
		var fin: Callable = _custom[kind].finish
		if fin.is_valid():
			fin.call()
	else:
		match kind:
			"gravity_flicker":
				player.gravity_scale = 1.0
			"era_flash":
				if era:
					era.set_era_flash(false)
			"translation_failure":
				translation_broken = false
			"time_stutter":
				if era:
					era.world_time_scale = 1.0
	Telemetry.log_event("glitch_end", {"glitch": kind})
	glitch_ended.emit(kind)


func end_all_glitches() -> void:
	for kind in active_glitches.keys():
		_end_glitch(kind)


func is_glitching(kind := "") -> bool:
	return active_glitches.size() > 0 if kind == "" else active_glitches.has(kind)


# -------------------------------------------------------------------- voice
func say(text: String, urgent := false) -> void:
	stats.lines += 1
	if hud:
		hud.subtitle("CHRONO", text, urgent)
	Telemetry.log_event("chrono_say", {"text": text})
	said.emit(text)


func say_once(key: String, text: String) -> void:
	if _said_once.has(key):
		return
	_said_once[key] = true
	say(text)


## Scrambles NPC speech while the translator is down.
func translate(text: String) -> String:
	if not translation_broken:
		return text
	var syl := ["ka", "tu", "mi", "ro", "she", "na", "lo", "ve", "ghi", "ba", "ur", "esh", "do", "pa", "zin"]
	var out := PackedStringArray()
	var h := text.hash()
	for w in text.split(" "):
		h = (h * 1103515245 + 12345) & 0x7fffffff
		var n := clampi(int(ceil(w.length() / 3.0)), 1, 3)
		var word := ""
		for i in n:
			word += syl[(h >> (i * 4)) % syl.size()]
		out.append(word)
	return " ".join(out).capitalize() + "."
