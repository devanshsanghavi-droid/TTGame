extends Node
## Placeholder; replaced by the full menu in the menus pass.


func _ready() -> void:
	Game.goto_era.call_deferred(Game.ERAS[0].id)
