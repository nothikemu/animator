class_name Interactable
extends Node3D
## Something the player can act on with the interact action. The prompt and action are
## callables so availability can depend on live state ("Crank the well" only if broken...).

var radius := 1.4
var prompt_fn: Callable                  ## () -> String ("" = not available now)
var action_fn: Callable                  ## () -> void
var priority := 0


static func make(pos: Vector3, prompt: Callable, action: Callable, r := 1.4, prio := 0) -> Interactable:
	var i := Interactable.new()
	i.position = pos
	i.prompt_fn = prompt
	i.action_fn = action
	i.radius = r
	i.priority = prio
	i.add_to_group("interactable")
	return i


func prompt() -> String:
	return String(prompt_fn.call()) if prompt_fn.is_valid() else ""


func act() -> void:
	if action_fn.is_valid():
		action_fn.call()
