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
		var c: Node = load("res://scripts/systems/capture_runner.gd").new()
		add_child(c)
	elif args.has("perf"):
		Game.mode = "perf"
		Game.bot_enabled = true
		var p: Node = load("res://scripts/systems/perf_runner.gd").new()
		add_child(p)
	elif args.has("era"):
		Game.bot_enabled = args.has("autoplay")
		Game.goto_era.call_deferred(args.era)
	elif args.has("autoplay"):
		Game.bot_enabled = true
		Game.goto_era.call_deferred(Game.ERAS[0].id)
	else:
		var menu: Node = load("res://scripts/ui/main_menu.gd").new()
		add_child(menu)
