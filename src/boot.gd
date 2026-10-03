extends Node
## Entry point. Chooses the first scene: a dev scenario/scene from the command line,
## otherwise the main menu.


func _ready() -> void:
	var target := "res://scenes/main_menu.tscn"
	if Dev.has_arg("scene"):
		target = Dev.arg("scene")
	elif Dev.has_arg("scenario"):
		target = "res://scenes/game.tscn"
	if not ResourceLoader.exists(target):
		Log.error("boot", "missing scene %s" % target)
		return
	get_tree().change_scene_to_file.call_deferred(target)
