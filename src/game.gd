extends Node3D
## The game scene: owns the current area view, the player, NPCs, the camera rig, the
## environment, the Undercroft cross-section and the UI layers. Areas stream one at a time.

var env: EnvCtl
var rig: CameraRig
var area: AreaMap
var area_view: AreaView
var player: Player
var actors: Node3D
var npcs: Dictionary = {}                ## id -> Npc
var hud: Hud
var dialogue_box: DialogueBox
var fade: ScreenFade
var actions: WorldActions
var farm: FarmView
var interact_root: Node3D
var resources_root: Node3D
var engineering: Node                    ## EngineeringView (cut mode), created on demand
var panels: Node                         ## UI panel host (inventory, craft, journal...)
var _capture_frames := -1
var _target: Interactable
var _busy := false                       ## transitions in progress
var _talking_npc: Npc


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
	hud = Hud.new()
	add_child(hud)
	dialogue_box = DialogueBox.new()
	add_child(dialogue_box)
	fade = ScreenFade.new()
	add_child(fade)
	if ResourceLoader.exists("res://src/ui/panels.gd"):
		panels = load("res://src/ui/panels.gd").new()
		panels.name = "Panels"
		add_child(panels)
	actions = WorldActions.new(self)
	load_area(GameState.current_area, true)
	rig.target = player
	rig.snap()
	Clock.running = true
	Clock.minute_tick.connect(_on_minute)
	Clock.exhausted.connect(_on_exhausted)
	Events.dialogue_ended.connect(_on_dialogue_ended)
	Events.grid_cells_changed.connect(func(_c: Array) -> void: pass)
	if Dev.has_arg("scenario"):
		Scenarios.run(self, Dev.arg("scenario"))
	if Dev.has_arg("capture"):
		_capture_frames = int(Dev.arg("frames", "45"))
	_update_music()


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


# --- Areas ------------------------------------------------------------------------------------

func load_area(id: String, initial := false) -> void:
	if area_view:
		area_view.queue_free()
		area_view = null
	for n in npcs.values():
		n.queue_free()
	npcs.clear()
	if id == "wick":
		area = AreaMap.from_ascii(Content.wick_map)
	else:
		area = ReachGen.generate_cavern(GameState.seed_value, GameState.reach_graph, id)
		_apply_area_deltas(id)
	GameState.current_area = id
	area_view = AreaView.new()
	add_child(area_view)
	area_view.build(area)
	Fx.ambient(area_view, area.biome, area.w, area.d)
	interact_root = Node3D.new()
	interact_root.name = "Interactables"
	area_view.add_child(interact_root)
	actions.build_for(area, interact_root)
	if id == "wick":
		farm = FarmView.new()
		area_view.add_child(farm)
		farm.setup(area)
		_spawn_npcs()
		_spawn_surface_machines()
	else:
		farm = null
		_spawn_resources()
		GameState.discover("places", id)
	env.set_biome(area.biome)
	rig.bounds = Rect2(0, 0, area.w, area.d)
	var pos: Array = GameState.player.get("pos", [4.5, 5.5])
	if not initial or GameState.player.get("area", "wick") != id:
		var pt: Vector2i = area.points.get("arrival", area.points.get("hub", Vector2i(area.w / 2, area.d / 2)))
		pos = [pt.x + 0.5, pt.y + 0.5]
	player.place(Vector2(float(pos[0]), float(pos[1])), area)
	GameState.player["area"] = id
	Events.area_changed.emit(StringName(id))
	Audio.ambience(String(Content.biomes.get(area.biome, {}).get("ambience", "grove")))
	_update_music()


func _spawn_npcs() -> void:
	var astar := area.build_astar()
	for id in Content.npcs:
		var n := Npc.new()
		n.setup(id, area, astar)
		actors.add_child(n)
		n.place_at_schedule()
		npcs[id] = n


func _spawn_surface_machines() -> void:
	if ResourceLoader.exists("res://src/engineering/surface_machines.gd"):
		var sm: Node3D = load("res://src/engineering/surface_machines.gd").new()
		sm.name = "SurfaceMachines"
		area_view.add_child(sm)


func _apply_area_deltas(id: String) -> void:
	var d: Dictionary = GameState.areas.get(id, {})
	var mined: Dictionary = d.get("mined", {})
	area.resources = area.resources.filter(func(r: Dictionary) -> bool:
		if mined.has(String(r.id)) and int(mined[String(r.id)]) <= 0:
			area.blocked[int(r.z) * area.w + int(r.x)] = 0
			return false
		return true)


func _spawn_resources() -> void:
	resources_root = Node3D.new()
	resources_root.name = "Resources"
	area_view.add_child(resources_root)
	for r in area.resources:
		var tex_name := String(r.type)
		var path := "res://assets/textures/props/%s.png" % tex_name
		if not ResourceLoader.exists(path):
			continue
		var t := PixelSprite3D.load_tex(path)
		var s := PixelSprite3D.new()
		var tex: Texture2D = t[0]
		s.setup(tex, t[1], Vector2i(tex.get_width(), tex.get_height()), Vector2i(1, 1), {"rim_strength": 0.3})
		s.position = Vector3(float(r.x) + 0.5, area.world_y(int(r.x), int(r.z)), float(r.z) + 0.5)
		s.name = String(r.id)
		resources_root.add_child(s)


func travel(to: String) -> void:
	if _busy:
		return
	_busy = true
	player.frozen = true
	var from := GameState.current_area
	var label := "Wick" if to == "wick" else String(ReachGen.node_by_id(GameState.reach_graph, to).get("name", to))
	Audio.play("travel", -6.0)
	await fade.fade_out(0.5, label)
	load_area(to)
	# Arrive at the exit that leads back where we came from.
	var key := "from_" + from
	if area.points.has(key):
		var p: Vector2i = area.points[key]
		player.place(Vector2(p.x + 0.5, p.y + 0.5), area)
	elif to == "wick":
		var p2: Vector2i = area.points.get("reach_gate", Vector2i(44, 15))
		player.place(Vector2(p2.x + 0.5, p2.y + 0.5), area)
	rig.snap()
	await fade.fade_in(0.7)
	player.frozen = false
	_busy = false


# --- Input --------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	if engineering and engineering.has_method("is_active") and engineering.is_active():
		return
	if Dialogue.active:
		if event.is_action_pressed("interact") or event.is_action_pressed("confirm") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
			dialogue_box.advance()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("cancel") and not Dialogue.has_choices():
			Dialogue.cancel()
			get_viewport().set_input_as_handled()
		return
	if panels and panels.has_method("is_open") and panels.is_open():
		return
	if event.is_action_pressed("interact"):
		if _target:
			_target.act()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("context") or event.is_action_pressed("primary"):
		if actions.use_tool(player.facing_cell()):
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("secondary"):
		var s := actions.cycle_seed()
		if s != "":
			Events.toast.emit("Seed: %s" % Content.item_name(s), &"info")
		return
	if event.is_action_pressed("tool_next"):
		GameState.cycle_tool(1)
		Audio.ui("ui_tick", -10.0)
	elif event.is_action_pressed("tool_prev"):
		GameState.cycle_tool(-1)
		Audio.ui("ui_tick", -10.0)
	elif event.is_action_pressed("cut_view"):
		toggle_cut_view()
	elif event.is_action_pressed("inventory"):
		Events.ui_open.emit(&"inventory", {})
	elif event.is_action_pressed("journal"):
		Events.ui_open.emit(&"journal", {})
	elif event.is_action_pressed("map"):
		Events.ui_open.emit(&"map", {})
	elif event.is_action_pressed("menu"):
		Events.ui_open.emit(&"pause", {})


func _process(delta: float) -> void:
	if area_view and player:
		area_view.update_fades(player.global_position, delta)
		area_view.update_lights(delta, Clock.glow_level(), Clock.darkness(), 1.0 if Settings.graphics.get("shadows", true) else 0.0)
		GameState.player["pos"] = [player.position.x, player.position.z]
		if area.id == "wick" and Sim.grid != null:
			var x := clampi(int(player.position.x), 0, Sim.grid.w - 1)
			env.pollution = clampf(float(Sim.grid.surface_air(x).sour) * 4.0, 0.0, 1.0)
		elif area.biome == "sump":
			env.pollution = 0.15
		else:
			env.pollution = 0.0
		_update_target()
		for n: Npc in npcs.values():
			n.try_bark(player.global_position)
	if _capture_frames >= 0:
		_capture_frames -= 1
		if _capture_frames == 0:
			_capture()


func _update_target() -> void:
	var best: Interactable = null
	var best_score := INF
	if not player.frozen and not Dialogue.active:
		var pp := player.global_position
		for node in get_tree().get_nodes_in_group("interactable"):
			var it := node as Interactable
			if it == null or not it.is_inside_tree():
				continue
			var d := Vector2(it.global_position.x - pp.x, it.global_position.z - pp.z)
			var dist := d.length()
			if dist > it.radius:
				continue
			var facing_bonus := -d.normalized().dot(player.facing) * 0.4 if dist > 0.01 else 0.0
			var score := dist + facing_bonus - it.priority * 0.05
			if score < best_score and it.prompt() != "":
				best_score = score
				best = it
	_target = best
	var text := ""
	if best:
		text = "[%s] %s" % [Settings.binding_label("interact"), best.prompt()]
	if text != String(get_meta("last_prompt", "")):
		set_meta("last_prompt", text)
		Events.prompt_changed.emit(text)


func _on_minute(_m: int) -> void:
	for n: Npc in npcs.values():
		n.think()


# --- Dialogue -------------------------------------------------------------------------------------

func start_dialogue(n: Npc) -> void:
	if Dialogue.active:
		return
	if not Dialogue.start_with(n.id):
		n.bark("...")
		return
	_talking_npc = n
	n.talking = true
	n.face_towards(player.global_position)
	player.frozen = true
	var mid := (player.global_position + n.global_position) * 0.5
	rig.focus_override = mid
	rig.mode = "dialogue"
	_update_music()


func monologue(text: String) -> void:
	if Dialogue.active:
		return
	player.frozen = true
	Dialogue.say_lines("player", [text])


func _on_dialogue_ended(_id: StringName) -> void:
	if _talking_npc:
		_talking_npc.talking = false
		_talking_npc = null
	if engineering and engineering.is_active():
		return   # the cut view owns the camera and keeps the player parked
	player.frozen = false
	rig.focus_override = null
	rig.mode = "explore"
	_update_music()


# --- Time ------------------------------------------------------------------------------------------

func sleep() -> void:
	if _busy:
		return
	_busy = true
	player.frozen = true
	await fade.fade_out(1.0)
	Clock.sleep_until_morning()
	Saves.save(0)
	if area.id == "wick":
		for n: Npc in npcs.values():
			n.place_at_schedule()
		if farm:
			farm.refresh_all()
	fade.title.text = "Day %d" % Clock.day
	var tw := create_tween()
	tw.tween_property(fade.title, "modulate:a", 1.0, 0.4)
	await get_tree().create_timer(1.2).timeout
	await fade.fade_in(1.0)
	player.frozen = false
	_busy = false
	_update_music()


func _on_exhausted() -> void:
	if _busy:
		return
	_busy = true
	player.frozen = true
	await fade.fade_out(1.6, "You don't remember lying down.")
	var outside := area.id != "wick" or not Rect2(3, 10, 6, 5).has_point(Vector2(player.position.x, player.position.z))
	if area.id != "wick":
		load_area("wick")
	var bed: Vector2i = area.points.get("lease_inside", Vector2i(6, 12))
	player.place(Vector2(bed.x + 0.5, bed.y + 0.5), area)
	rig.snap()
	Clock.sleep_until_morning()
	if outside:
		Society.remember("barnaby", "carried_home", 4.0, 0.2, true)
		Society.change("barnaby", "shared", 6.0)
		GameState.set_flag("carried_home", int(GameState.flag("carried_home") if GameState.flag("carried_home") else 0) + 1)
	Saves.save(0)
	await fade.fade_in(1.0)
	player.frozen = false
	_busy = false
	if outside:
		monologue("Somebody brought you home. There's a cup of moss tea on the stove, still warm.")


# --- Feedback helpers -----------------------------------------------------------------------------

func cell_pos(c: Vector2i) -> Vector3:
	return Vector3(c.x + 0.5, area.world_y(c.x, c.y) + 0.1, c.y + 0.5)


func fx_burst(c: Vector2i, kind: String) -> void:
	Fx.burst(area_view, cell_pos(c), kind)


## Hammer on a resource node in the Reach.
func mine_at(c: Vector2i) -> bool:
	if area.id == "wick":
		return false
	for r in area.resources:
		if int(r.x) == c.x and int(r.z) == c.y:
			var id := String(r.id)
			if not GameState.areas.has(area.id):
				GameState.areas[area.id] = {"mined": {}}
			var mined: Dictionary = GameState.areas[area.id].get("mined", {})
			GameState.areas[area.id]["mined"] = mined
			var left := int(mined.get(id, int(r.n)))
			if r.has("lore"):
				Events.ui_open.emit(&"lore", {"id": String(r.lore)})
				mined[id] = 0
			elif left > 0 and String(r.item) != "":
				var take := mini(left, 2 if not r.get("story", false) else 1)
				GameState.give(String(r.item), take)
				left -= take
				mined[id] = left
				player.use_tool_anim(0.45)
				fx_burst(c, "rock" if String(r.type) != "glowglass_node" else "glint")
				Audio.play_at("mine", cell_pos(c), -3.0)
				Events.camera_impulse.emit(0.08)
				GameState.add_deed("mined", float(take))
			if int(mined.get(id, 1)) <= 0:
				var node := resources_root.get_node_or_null(id)
				if node:
					node.queue_free()
				area.blocked[c.y * area.w + c.x] = 0
				area.resources.erase(r)
			return true
	return false


func toggle_cut_view() -> void:
	if not GameState.has_tool("glass"):
		if area.id == "wick":
			monologue("Whatever's wrong with the water is under your feet, and you can't see through dirt.")
		return
	if area.id != "wick":
		monologue("The plumb-glass shows only rock here. The surveys it remembers are for Station 7.")
		return
	if engineering == null:
		engineering = load("res://src/engineering/engineering_view.gd").new()
		engineering.name = "Engineering"
		add_child(engineering)
	engineering.toggle()


func _update_music() -> void:
	var cue := "wick"
	if GameState.view_mode == "cut":
		cue = "cut"
	elif area and area.id != "wick":
		cue = "reach"
	elif Clock.phase() in ["hush", "night"]:
		cue = "hush"
	var stems := {"pad": 1.0, "melody": 0.8, "counter": 0.5 if Clock.phase() == "bloom" else 0.0, "pulse": 0.0,
		"glass": 0.6, "drone": 1.0, "bass": 1.0, "ostinato": 0.8, "perc": 0.6, "alarm": 0.0}
	if rig and rig.mode == "dialogue":
		stems.melody = 0.35
		stems.counter = 0.0
	Audio.music(cue, stems)


func _capture() -> void:
	var path := Dev.arg("capture")
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	Log.info("capture", "saved %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	if not Dev.has_arg("keep"):
		get_tree().quit()
