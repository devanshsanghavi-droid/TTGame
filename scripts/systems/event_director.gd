class_name EventDirector extends Node
## Scripted "shenanigan" events. Each has a globally unique `type`, a trigger
## (place, time, predicate or manual) and randomized variants so replays differ.
##
##   director.add("tide_surge", "tidal_surge", {"at": pos, "radius": 12.0},
##       [["fast", func(): ...], ["slow", func(): ...]])

signal event_fired(id: String, variant: String)

var era: Node
var events: Array[Dictionary] = []
var fired := {}
var enabled := true

var _by_id := {}


## trigger: {"at": Vector3, "radius": float} | {"time": float} | {"when": Callable} | {"manual": true}
## variants: Array of [name, Callable]. One is picked at random with the era RNG.
## opts: {"after": id} only arms once another event has fired; {"delay": s} after trigger.
func add(id: String, type: String, trigger: Dictionary, variants: Array, opts: Dictionary = {}) -> void:
	var ev := {"id": id, "type": type, "trigger": trigger, "variants": variants, "opts": opts, "done": false, "pending": -1.0}
	events.append(ev)
	_by_id[id] = ev


func types() -> Array:
	var out := []
	for e in events:
		out.append(e.type)
	return out


func has_fired(id: String) -> bool:
	return fired.has(id)


func fire(id: String, variant := -1) -> bool:
	var ev: Dictionary = _by_id.get(id, {})
	if ev.is_empty() or ev.done:
		return false
	ev.done = true
	var vs: Array = ev.variants
	var idx := variant
	if idx < 0 or idx >= vs.size():
		idx = (era.rng.randi() % vs.size()) if era and vs.size() > 0 else 0
	var vname := "default"
	if vs.size() > 0:
		vname = String(vs[idx][0])
		var fn: Callable = vs[idx][1]
		if fn.is_valid():
			fn.call()
	fired[id] = vname
	if era:
		era.mark("event")
	Telemetry.log_event("event", {"id": id, "type": ev.type, "variant": vname})
	event_fired.emit(id, vname)
	return true


func _physics_process(delta: float) -> void:
	if not enabled or era == null or era.player == null:
		return
	var ppos: Vector3 = era.player.global_position
	for ev in events:
		if ev.done:
			continue
		if ev.pending >= 0.0:
			ev.pending -= delta
			if ev.pending <= 0.0:
				fire(ev.id)
			continue
		var opts: Dictionary = ev.opts
		if opts.has("after") and not fired.has(opts.after):
			continue
		var trig: Dictionary = ev.trigger
		var hit := false
		if trig.has("at"):
			var at: Vector3 = trig.at
			var r: float = trig.get("radius", 8.0)
			var d := Vector2(ppos.x - at.x, ppos.z - at.z).length()
			hit = d < r and absf(ppos.y - at.y) < trig.get("height", 12.0)
		elif trig.has("time"):
			hit = era.elapsed >= float(trig.time)
		elif trig.has("when"):
			hit = bool((trig.when as Callable).call())
		if hit:
			var delay: float = opts.get("delay", 0.0)
			if delay > 0.0:
				ev.pending = delay
			else:
				fire(ev.id)
