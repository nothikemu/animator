class_name GameFlow
extends RefCounted
## Starting, continuing and leaving a game. The main menu, dev scenarios and tests all go
## through here so every system is reset the same way.

const GAME_SCENE := "res://scenes/game.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"


static func new_game(seed_value: int, player_name: String) -> void:
	GameState.new_game(seed_value, player_name)
	Clock.clear_pauses()
	Clock.start(1, 7 * 60)
	Sim.new_world(seed_value)
	Society.reset()
	Economy.reset()
	Threads.reset()
	Director.reset(seed_value)
	Dialogue.reset()


static func random_seed() -> int:
	return randi_range(100000, 999999)


static func start(tree: SceneTree) -> void:
	tree.change_scene_to_file.call_deferred(GAME_SCENE)


## Loads a slot and enters the game. Returns "" or a plain-language error.
static func continue_from(tree: SceneTree, slot: int) -> String:
	Clock.clear_pauses()
	var err := Saves.load_slot(slot)
	if err != "":
		return err
	tree.change_scene_to_file.call_deferred(GAME_SCENE)
	return ""


static func quit_to_menu(tree: SceneTree) -> void:
	Clock.running = false
	Clock.clear_pauses()
	Dialogue.cancel()
	GameState.started = false
	RenderingServer.global_shader_parameter_set("cut_amount", 0.0)
	tree.change_scene_to_file.call_deferred(MENU_SCENE)
