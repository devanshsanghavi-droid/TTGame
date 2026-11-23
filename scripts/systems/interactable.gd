class_name Interactable extends Node3D
## Something the player can press Interact on. Lives in group "interactable".

signal used(player: Player)

var prompt := "Interact"
var radius := 2.3
var enabled := true
var one_shot := false
var callback: Callable


func _ready() -> void:
	add_to_group("interactable")


func interact(player: Player) -> void:
	if not enabled:
		return
	if one_shot:
		enabled = false
	used.emit(player)
	if callback.is_valid():
		callback.call(player)


static func make(parent: Node, pos: Vector3, prompt_text: String, on_use: Callable, reach := 2.3, once := false) -> Interactable:
	var it := Interactable.new()
	it.prompt = prompt_text
	it.callback = on_use
	it.radius = reach
	it.one_shot = once
	it.position = pos
	parent.add_child(it)
	return it
