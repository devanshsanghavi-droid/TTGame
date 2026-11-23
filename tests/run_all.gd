extends SceneTree
## Headless test entry point:
##   godot --headless --path . -s tests/run_all.gd
##   godot --headless --path . -s tests/run_all.gd -- --only=cambrian,egypt --speed=10
## Exit code 0 only if every era passes.


func _initialize() -> void:
	var runner: Node = load("res://tests/test_runner.gd").new()
	root.add_child.call_deferred(runner)
