extends Node
## Captures every engine error and warning so tests can assert a clean run.
## Autoloaded first so nothing slips past it.

class WatchLogger extends Logger:
	var mutex := Mutex.new()
	var entries: Array = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array) -> void:
		var kind := "error"
		match error_type:
			Logger.ERROR_TYPE_WARNING: kind = "warning"
			Logger.ERROR_TYPE_SCRIPT: kind = "script"
			Logger.ERROR_TYPE_SHADER: kind = "shader"
		mutex.lock()
		entries.append({
			"kind": kind,
			"msg": rationale if rationale != "" else code,
			"where": "%s:%d (%s)" % [file, line, function],
		})
		mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass


## Substrings of messages that are known engine noise and never a game fault.
const IGNORE := [
	"ObjectDB instances leaked",
	"resources still in use at exit",
	# Jolt's thread pool reports this when the machine is heavily loaded (many
	# Godot instances at once). It waits and carries on; simulation is unaffected.
	"Jolt Physics job system exceeded the maximum number of jobs",
]

var _logger := WatchLogger.new()


func _enter_tree() -> void:
	OS.add_logger(_logger)


## Returns and clears everything captured since the last call.
func take() -> Array:
	_logger.mutex.lock()
	var out: Array = _logger.entries.duplicate()
	_logger.entries.clear()
	_logger.mutex.unlock()
	var kept: Array = []
	for e in out:
		var skip := false
		for s in IGNORE:
			if String(e.msg).contains(s):
				skip = true
				break
		if not skip:
			kept.append(e)
	return kept


func peek_count() -> int:
	_logger.mutex.lock()
	var n: int = _logger.entries.size()
	_logger.mutex.unlock()
	return n
