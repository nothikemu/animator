extends Node3D
## The game scene: owns the current area view, the player, the camera rig, environment,
## the Undercroft cross-section and the UI layers. Areas stream one at a time.

var env: EnvCtl
var rig: CameraRig
var area: AreaMap
var area_view: AreaView
var player: Player
var actors: Node3D
var ui: CanvasLayer
var _capture_frames := -1


func _ready() -> void:
	if not GameState.started:
		_dev_new_game()
	env = EnvCtl.new()
	add_child(env)
	rig = CameraRig.new()
	add_child(rig)
	actors = Node3D.new()
	actors.name = "Actors"
	add_child(actors)
	player = Player.new()
	player.name = "Player"
	actors.add_child(player)
	load_area(GameState.current_area, true)
	rig.target = player
	rig.snap()
	Clock.running = true
	if Dev.has_arg("scenario"):
		Scenarios.run(self, Dev.arg("scenario"))
	if Dev.has_arg("capture"):
		_capture_frames = int(Dev.arg("frames", "45"))


func _dev_new_game() -> void:
	var seed_v := int(Dev.arg("seed", "1234"))
	GameState.new_game(seed_v, "Salvager")
	Clock.start(1, 7 * 60)
	Sim.new_world(seed_v)
	Society.reset()
	Economy.reset()
	Threads.reset()
	Director.reset(seed_v)
	Dialogue.reset()


func load_area(id: String, initial := false) -> void:
	if area_view:
		area_view.queue_free()
	if id == "wick":
		area = AreaMap.from_ascii(Content.wick_map)
	else:
		area = ReachGen.generate_cavern(GameState.seed_value, GameState.reach_graph, id)
	GameState.current_area = id
	area_view = AreaView.new()
	add_child(area_view)
	area_view.build(area)
	env.set_biome(area.biome)
	rig.bounds = Rect2(0, 0, area.w, area.d)
	var pos: Array = GameState.player.get("pos", [4.5, 5.5])
	if not initial or GameState.player.get("area", "wick") != id:
		var pt: Vector2i = area.points.get("arrival", area.points.get("hub", Vector2i(area.w / 2, area.d / 2)))
		pos = [pt.x + 0.5, pt.y + 0.5]
	player.place(Vector2(float(pos[0]), float(pos[1])), area)
	Events.area_changed.emit(StringName(id))


func _process(delta: float) -> void:
	if area_view and player:
		area_view.update_fades(player.global_position, delta)
		area_view.update_lights(delta, Clock.glow_level(), Clock.darkness(), 1.0 if Settings.graphics.get("shadows", true) else 0.0)
		GameState.player["pos"] = [player.position.x, player.position.z]
		GameState.player["area"] = GameState.current_area
		if area.id == "wick" and Sim.grid != null:
			var x := clampi(int(player.position.x), 0, Sim.grid.w - 1)
			env.pollution = clampf(float(Sim.grid.surface_air(x).sour) * 4.0, 0.0, 1.0)
	if _capture_frames >= 0:
		_capture_frames -= 1
		if _capture_frames == 0:
			_capture()


func _capture() -> void:
	var path := Dev.arg("capture")
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	Log.info("capture", "saved %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	if not Dev.has_arg("keep"):
		get_tree().quit()
