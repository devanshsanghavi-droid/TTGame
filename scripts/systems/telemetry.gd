extends Node
## JSON-lines telemetry. One file per session in user://telemetry/.
## Every line: {"t": seconds, "kind": "...", ...payload}

const DIR := "user://telemetry"

var enabled := true
var snapshot_interval := 0.5
var path := ""

var _file: FileAccess
var _acc := 0.0
var _t := 0.0
var _era: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(DIR)
	open("session_%d" % int(Time.get_unix_time_from_system()))


## Start a new log file (tests open one per era).
func open(log_name: String) -> void:
	if _file:
		_file.close()
	path = "%s/%s.jsonl" % [DIR, log_name]
	_file = FileAccess.open(path, FileAccess.WRITE)
	_t = 0.0
	_acc = 0.0


func set_era(era: Node) -> void:
	_era = era


func log_event(kind: String, data: Dictionary = {}) -> void:
	if not enabled or _file == null:
		return
	var line := {"t": snappedf(_t, 0.01), "kind": kind}
	line.merge(_clean(data))
	_file.store_line(JSON.stringify(line))


func flush() -> void:
	if _file:
		_file.flush()


func global_path() -> String:
	return ProjectSettings.globalize_path(path)


func _physics_process(delta: float) -> void:
	_t += delta
	_acc += delta
	if _acc < snapshot_interval:
		return
	_acc = 0.0
	if _era and is_instance_valid(_era) and _era.has_method("telemetry_snapshot"):
		var snap: Dictionary = _era.telemetry_snapshot()
		snap["fps"] = Engine.get_frames_per_second()
		snap["draw_calls"] = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		log_event("snap", snap)


func _clean(v: Variant) -> Variant:
	match typeof(v):
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				d[str(k)] = _clean(v[k])
			return d
		TYPE_ARRAY:
			var a := []
			for x in v:
				a.append(_clean(x))
			return a
		TYPE_VECTOR3:
			return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]
		TYPE_VECTOR2:
			return [snappedf(v.x, 0.01), snappedf(v.y, 0.01)]
		TYPE_FLOAT:
			return snappedf(v, 0.001)
		TYPE_INT, TYPE_BOOL, TYPE_STRING:
			return v
		TYPE_NIL:
			return null
	return str(v)
