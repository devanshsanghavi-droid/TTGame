extends Node
## Entry point. Chooses what to run from the command line:
##   (nothing)            main menu
##   -- --era=cambrian    jump straight into an era
##   -- --autoplay        watch the AutoPilot play (add --era=... to pick one)
##   -- --capture=<era>   scripted flythrough + gameplay snippet (use with --write-movie)
##   -- --perf=<era|all>  measure frame time and draw calls


func _ready() -> void:
	var args: Dictionary = Game.user_args
	if args.has("capture"):
		Game.mode = "capture"
		Game.bot_enabled = true
		_start_runner("res://scripts/systems/capture_runner.gd")
	elif args.has("perf"):
		Game.mode = "perf"
		Game.bot_enabled = true
		_start_runner("res://scripts/systems/perf_runner.gd")
	elif args.has("era"):
		Game.bot_enabled = args.has("autoplay")
		Game.goto_era.call_deferred(args.era)
	elif args.has("autoplay"):
		Game.bot_enabled = true
		Game.goto_era.call_deferred(Game.ERAS[0].id)
	else:
		var menu: Node = load("res://scripts/ui/main_menu.gd").new()
		add_child(menu)


## Tool modes must never sit idle with a window open if their script is broken.
func _start_runner(path: String) -> void:
	var script := load(path) as GDScript
	if script == null or not script.can_instantiate():
		push_error("cannot start %s (script error); quitting" % path)
		get_tree().quit(1)
		return
	add_child(script.new())
