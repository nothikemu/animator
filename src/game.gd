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
var _target: Interactable
var _busy := false                       ## transitions in progress
var _talking_npc: Npc
var marker: Node3D                      ## floating objective marker
var breath := 1.0                        ## 1 = full lungs; drains in bad air
var _day_log := {}                       ## what today held, for the card at bedtime


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
	if DevOverlay.allowed():
		add_child(DevOverlay.new())
	actions = WorldActions.new(self)
	marker = ObjectiveMarker.new()
	add_child(marker)
	load_area(GameState.current_area, true)
	rig.target = player
	rig.snap()
	Clock.running = true
	Clock.minute_tick.connect(_on_minute)
	Clock.exhausted.connect(_on_exhausted)
	Clock.phase_changed.connect(func(_p: String) -> void: _update_music())
	Clock.hour_changed.connect(func(_h: int) -> void: _update_music())
	Events.world_event.connect(func(_id: StringName, _d: Dictionary) -> void: _update_music())
	Events.dialogue_ended.connect(_on_dialogue_ended)
	_reset_day_log()
	Clock.day_started.connect(func(_d: int) -> void: _reset_day_log())
	Events.harvest.connect(func(_c: StringName, n: int) -> void: _day_log["harvested"] = int(_day_log.harvested) + n)
	Events.dialogue_started.connect(func(who: StringName) -> void:
		if Content.npcs.has(String(who)) and not (_day_log.people as Array).has(String(who)):
			(_day_log.people as Array).append(String(who)))
	Events.discovered.connect(func(kind: StringName, _id: StringName) -> void:
		if kind == &"places" or kind == &"lore":
			_day_log["found"] = int(_day_log.found) + 1)
	Events.flag_changed.connect(_chapter_banner)
	Events.thread_updated.connect(func(tid: StringName, _s: int) -> void:
		# A finished thread gets a little fist in the air (only when the salvager is free).
		if Threads.is_done(String(tid)) and not player.frozen and player.busy <= 0.0 and not _busy:
			player.react("celebrate"))
	Events.grid_cells_changed.connect(func(_c: Array) -> void: pass)
	if Dev.has_arg("scenario"):
		Scenarios.run(self, Dev.arg("scenario"))
	elif not GameState.has_flag("intro_done"):
		opening()
	_update_music()


func _dev_new_game() -> void:
	GameFlow.new_game(int(Dev.arg("seed", "1234")), "Salvager")


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
	elif Content.maps.has(id):
		area = AreaMap.from_ascii(Content.maps[id])
		_resolve_authored_exits(area)
		_apply_area_deltas(id)
	else:
		var node := ReachGen.node_by_id(GameState.reach_graph, id)
		if node.has("unmapped"):
			GameState.set_flag("deepest", maxi(int(GameState.flag("deepest") if GameState.flag("deepest") else 0), int(node.unmapped)))
			ReachGen.ensure_unmapped(GameState.reach_graph, int(node.unmapped))
			Almanac.record_depth(int(node.unmapped))
		area = ReachGen.generate_cavern(GameState.seed_value, GameState.reach_graph, id)
		_apply_area_deltas(id)
	GameState.current_area = id
	area_view = AreaView.new()
	add_child(area_view)
	area_view.build(area)
	Fx.ambient(area_view, area.biome, area.w, area.d)
	var critters := Critters.new()
	area_view.add_child(critters)
	critters.setup(area, player)
	interact_root = Node3D.new()
	interact_root.name = "Interactables"
	area_view.add_child(interact_root)
	actions.build_for(area, interact_root)
	if id == "wick":
		farm = FarmView.new()
		area_view.add_child(farm)
		farm.setup(area)
		_spawn_surface_machines()
	else:
		farm = null
		_spawn_resources()
		GameState.discover("places", id)
	_spawn_npcs()
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
	var astar: AStarGrid2D = null
	for id in Content.npcs:
		if Npc.area_of(id) != area.id:
			continue
		if astar == null:
			astar = area.build_astar()
		var n := Npc.new()
		n.setup(id, area, astar)
		n.watch(player)
		actors.add_child(n)
		n.place_at_schedule()
		npcs[id] = n


func _spawn_surface_machines() -> void:
	if ResourceLoader.exists("res://src/engineering/surface_machines.gd"):
		var sm: Node3D = load("res://src/engineering/surface_machines.gd").new()
		sm.name = "SurfaceMachines"
		area_view.add_child(sm)


## Authored maps name their ways out "up" and "down"; the graph says where those go.
func _resolve_authored_exits(a: AreaMap) -> void:
	var node := ReachGen.node_by_id(GameState.reach_graph, a.id)
	var tier := int(node.get("tier", 0))
	var ups: Array = []
	var downs: Array = []
	for e: Dictionary in GameState.reach_graph.get("edges", []):
		if String(e.a) != a.id and String(e.b) != a.id:
			continue
		var other := String(e.b) if String(e.a) == a.id else String(e.a)
		var ot := 0 if other == "wick" else int(ReachGen.node_by_id(GameState.reach_graph, other).get("tier", 0))
		(ups if ot < tier else downs).append({"to": other, "kind": String(e.kind)})
	var used := {"up": 0, "down": 0}
	var keep: Array = []
	for ex: Dictionary in a.exits:
		var slot := String(ex.get("to", ""))
		if slot in ["up", "down"]:
			var pool: Array = ups if slot == "up" else downs
			var k := int(used[slot])
			used[slot] = k + 1
			if k >= pool.size():
				continue
			ex["to"] = String(pool[k].to)
			ex["kind"] = String(pool[k].kind)
		keep.append(ex)
		a.points["from_" + String(ex.to)] = Vector2i(int(ex.arrive[0]), int(ex.arrive[1]))
	a.exits = keep
	if not a.points.has("arrival") and a.points.has("hub"):
		a.points["arrival"] = a.points.hub


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
		if tex_name == "story_cache":
			# The one thing in the Reach that matters most is lit like it knows it.
			var glint := OmniLight3D.new()
			glint.light_color = Color("56e0d4")
			glint.light_energy = 1.4
			glint.omni_range = 3.5
			glint.position = Vector3(0, 0.8, 0.6)
			s.add_child(glint)


func travel(to: String) -> void:
	if _busy:
		return
	_busy = true
	player.frozen = true
	var from := GameState.current_area
	var label := "Wick" if to == "wick" else String(ReachGen.node_by_id(GameState.reach_graph, to).get("name", to))
	var lift := (from == "wick" and to == "d1_0") or (to == "wick" and from == "d1_0")
	Audio.play("lift" if lift and ResourceLoader.exists("res://assets/audio/sfx/lift.ogg") else "travel", -6.0)
	if lift:
		Events.caption.emit("[the lift cage shudders, and the cable takes the weight]", 2.5)
	await fade.fade_out(0.5, label)
	load_area(to)
	# Arrive at the exit that leads back where we came from.
	var key := "from_" + from
	var from_node := ReachGen.node_by_id(GameState.reach_graph, from)
	if to == "wick" and bool(from_node.get("deep", false)):
		# Up the Primary Lift: out into the pump hall's doorway.
		var p3: Vector2i = area.points.get("pumphall_door", Vector2i(41, 11))
		player.place(Vector2(p3.x + 0.5, p3.y + 1.5), area)
		player.facing = Vector2(0, 1)
	elif area.points.has(key):
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
	elif event.is_action_pressed("minimap"):
		hud.cycle_minimap()
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
		player.air_bad = env.pollution > 0.3 or _hazard() in ["sour", "stale"]
		player.cold = area.biome in ["sump", "drowned", "salt"]
		_breathe(delta)
		_update_target()
		_check_reveal()
		for n: Npc in npcs.values():
			n.try_bark(player.global_position)


## The air hazard where the salvager stands ("" when the air is fine).
func _hazard() -> String:
	if area == null:
		return ""
	if area.id == "wick":
		return "sour" if env.pollution > 0.6 else ""
	return String(Content.biomes.get(area.biome, {}).get("hazard", ""))


## Bad air empties the lungs; a respirator makes it last five times as long. Run out and you
## black out, and someone carries you home.
func _breathe(delta: float) -> void:
	var hz := _hazard()
	var drain := {"sour": 1.0 / 210.0, "stale": 1.0 / 150.0, "damp": 1.0 / 300.0}.get(hz, 0.0) as float
	if GameState.has_gear("respirator"):
		drain *= 0.2
	if player.frozen or _busy or Dialogue.active or (panels and panels.has_method("is_open") and panels.is_open()):
		drain = 0.0
	if drain > 0.0:
		breath = maxf(0.0, breath - drain * delta)
	else:
		breath = minf(1.0, breath + delta / (6.0 if hz == "" else 40.0))
	hud.set_breath(breath, hz != "" and drain > 0.0 or breath < 0.999)
	if breath <= 0.0 and not _busy:
		breath = 0.35
		_blackout()


func _blackout() -> void:
	_busy = true
	player.frozen = true
	player.perform("collapse")
	Audio.play("thud" if ResourceLoader.exists("res://assets/audio/sfx/thud.ogg") else "travel", -6.0)
	await get_tree().create_timer(0.9).timeout
	await fade.fade_out(1.4, "The air goes thin, then goes out.")
	var deep := bool(ReachGen.node_by_id(GameState.reach_graph, area.id).get("deep", false))
	var rescuer := "pell" if deep and GameState.has_flag("met_pell") else "barnaby"
	load_area("wick")
	var bed: Vector2i = area.points.get("lease_inside", Vector2i(6, 12))
	player.place(Vector2(bed.x + 0.5, bed.y + 0.5), area)
	rig.snap()
	Clock.advance(240.0)
	Society.remember(rescuer, "carried_home", 4.0, 0.2, true)
	Society.change(rescuer, "shared", 4.0)
	GameState.set_flag("blackouts", int(GameState.flag("blackouts") if GameState.flag("blackouts") else 0) + 1)
	breath = 1.0
	await fade.fade_in(1.0)
	player.frozen = false
	_busy = false
	if rescuer == "pell":
		monologue("You wake in the Lease. There's a chalk mark on the door: 3·2·3. Pell carried you all the way to the lift.")
	else:
		monologue("You wake in the Lease with a headache and a blanket you don't own. Barnaby's handwriting on a note: 'Respirator. Bench. Hesper knows how.'")


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
	var summary := day_summary()
	Clock.sleep_until_morning()
	Saves.save(0)
	if area.id == "wick":
		for n: Npc in npcs.values():
			n.place_at_schedule()
		if farm:
			farm.refresh_all()
	if summary != "":
		await fade.card([summary], 2.4, UiTheme.DIM)
	fade.title.text = "Day %d" % Clock.day
	var tw := create_tween()
	tw.tween_property(fade.title, "modulate:a", 1.0, 0.4)
	await get_tree().create_timer(1.2).timeout
	await fade.fade_in(1.0)
	player.frozen = false
	_busy = false
	_update_music()


func _reset_day_log() -> void:
	_day_log = {"money": GameState.money(), "harvested": 0, "people": [], "found": 0}


## One quiet line about the day just gone: what grew, who you talked to, what you earned.
func day_summary() -> String:
	var bits := PackedStringArray()
	if int(_day_log.harvested) > 0:
		bits.append("%d harvested" % int(_day_log.harvested))
	var earned := GameState.money() - int(_day_log.money)
	if earned > 0:
		bits.append("%d glim earned" % earned)
	var people: Array = _day_log.people
	if not people.is_empty():
		var names := PackedStringArray()
		for who: String in people:
			names.append(Society.display_name(who))
		bits.append("talked with " + (", ".join(names.slice(0, names.size() - 1)) + " and " + names[names.size() - 1] if names.size() > 1 else names[0]))
	if int(_day_log.found) > 0:
		bits.append("%d new thing%s found" % [int(_day_log.found), "" if int(_day_log.found) == 1 else "s"])
	if bits.is_empty():
		return ""
	var line := " · ".join(bits)
	return line.substr(0, 1).to_upper() + line.substr(1) + "."


func _on_exhausted() -> void:
	if _busy:
		return
	_busy = true
	player.frozen = true
	player.perform("collapse")
	await get_tree().create_timer(0.9).timeout
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
				GameState.discover("lore", String(r.lore))
				Events.ui_open.emit(&"lore", {"id": String(r.lore)})
				Audio.play("pickup", -6.0)
				mined[id] = 0
			elif left > 0 and String(r.item) != "":
				var take := mini(left, 2 if not r.get("story", false) else 1)
				GameState.give(String(r.item), take)
				Fx.item_pop(area_view, cell_pos(c), player, String(r.item), take)
				if r.get("story", false) and String(r.item) == "governor_coil":
					monologue("The crate's seal parts like it was waiting to. Inside, packed in wax paper and labelled in a neat hand: one governor coil. NEVER THE LAST ONE UP-LINE. Somebody already broke that rule once.")
				left -= take
				mined[id] = left
				var glint := String(r.type) == "glowglass_node"
				player.perform("hammer", func() -> void:
					fx_burst(c, "rock" if not glint else "glint")
					fx_burst(c, "spark")
					Audio.play_at("mine", cell_pos(c), -3.0)
					Events.camera_impulse.emit(0.08))
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
	var crisis_air := float(Sim.fact("pollution")) if Sim.grid != null else 0.0
	var crisis := GameState.has_flag("tremor_done") and not bool(Sim.fact("fissure_sealed"))
	if GameState.has_flag("finale_playing") or (GameState.has_flag("knock_heard") and GameState.view_mode == "cut"):
		cue = "station"
	elif GameState.view_mode == "cut":
		cue = "cut"
	elif area and area.id != "wick":
		cue = String(Content.biomes.get(area.biome, {}).get("music", "reach"))
	elif Clock.phase() in ["hush", "night"]:
		cue = "hush"
	var stems := {"pad": 1.0, "melody": 0.8, "counter": 0.55 if Clock.phase() == "bloom" else 0.0,
		"pulse": 0.6 if Clock.phase() in ["wake", "bloom"] else 0.25, "glass": 0.7, "drone": 1.0,
		"bass": 1.0, "ostinato": 0.85, "perc": 0.7, "alarm": 0.9 if crisis or int(Sim.fact("leaks") if Sim.grid != null else 0) >= 4 else 0.0,
		"brass": 0.9, "knock": 1.0 if GameState.has_flag("knock_heard") else 0.0,
		"breath": 1.0, "pluck": 0.8}
	if cue == "heart":
		stems.brass = 1.0 if GameState.has_flag("heart_running") else 0.0
	elif cue == "sallow":
		stems.melody = 0.85 if not GameState.has_flag("wren_died") else 0.4
	elif cue == "deep":
		stems.knock = 0.8
	if area and area.id != "wick":
		stems.pulse = 0.7 if area.biome in ["sump", "ember"] else 0.35
	if rig and rig.mode == "dialogue":
		stems.melody = 0.35
		stems.counter = 0.0
	if GameState.has_flag("quietlight_active"):
		stems = {"pad": 0.6, "glass": 1.0, "melody": 0.4}
	Audio.music(cue, stems)
	# Bad air and an open crisis close the music down, as if heard through a mask.
	Audio.crisis(clampf(crisis_air * 2.5, 0.0, 0.7) if area and area.id == "wick" else 0.0)


# --- Story sequences --------------------------------------------------------------------------

## Beat 1–2: black, a winch, a snapped cable, a long fall; then the grove's edge and one
## direction with any light in it.
func opening() -> void:
	_busy = true
	player.frozen = true
	fade.black()
	Clock.pause("opening")
	await get_tree().create_timer(0.8).timeout
	Audio.play("winch", -6.0)
	await _black_caption("[a winch creaks, very far above]", 2.4)
	Audio.play("cable_snap", -2.0)
	Events.camera_impulse.emit(0.4)
	await _black_caption("[a cable snaps]", 1.6)
	Audio.play("fall", -4.0)
	await _black_caption("[a long fall — then moss, softer than it has any right to be]", 3.0)
	Clock.resume("opening")
	player.facing = Vector2(0, 1)
	player.perform("getup")          # sprawled in the moss, then up onto unsteady feet
	await fade.fade_in(2.2)
	GameState.set_flag("intro_done")
	player.frozen = false
	_busy = false
	monologue("Your headlamp flickers. Only one direction has any light in it.")


## A sound caption on the black opening card (the HUD caption line sits under the fade).
func _black_caption(text: String, seconds: float) -> void:
	fade.title.add_theme_color_override("font_color", UiTheme.DIM)
	fade.title.text = text   # story text, shown whether or not sound captions are on
	var tw := create_tween()
	tw.tween_property(fade.title, "modulate:a", 1.0, 0.3)
	await get_tree().create_timer(seconds).timeout
	var tw2 := create_tween()
	tw2.tween_property(fade.title, "modulate:a", 0.0, 0.3)
	await tw2.finished
	fade.title.remove_theme_color_override("font_color")


## Beat 3: the first time the player steps out of the grotto, the camera eases back to show Wick.
func _check_reveal() -> void:
	if area.id != "wick" or GameState.has_flag("wick_revealed") or not GameState.has_flag("intro_done"):
		return
	if player.position.z < 9.5 or player.position.x > 14.0:
		return
	GameState.set_flag("wick_revealed")
	GameState.discover("places", "wick")
	rig._zoom_target = CameraRig.ZOOM_MAX
	Events.caption.emit("Wick", 3.0)
	Audio.play("reveal", -6.0)
	get_tree().create_timer(5.0).timeout.connect(func() -> void: rig._zoom_target = 24.0)


## The Trunk valve, with Barnaby, from the cut view. open = turn it; otherwise listen.
func finale(open: bool) -> void:
	if Dialogue.active:
		return
	GameState.set_flag("finale_playing", true)
	Dialogue.start_convo("barnaby", "finale_open" if open else "finale_shut")
	_update_music()
	await Events.dialogue_ended
	GameState.set_flag("finale_playing", false)
	await get_tree().create_timer(1.2).timeout
	show_ending()


## The end of the vertical slice. The game continues afterwards.
func show_ending() -> void:
	if _busy:
		return
	_busy = true
	await fade.fade_out(2.4)
	var lines: Array = []
	lines.append("Wick has water. Station 7 is breathing again.")
	if GameState.deed("industrial_power") > GameState.deed("clean_power") + 1.0:
		lines.append("Its pumps run on fire, and the lake remembers the smoke.")
	elif GameState.deed("clean_power") > 0.5:
		lines.append("Its pumps run on falling water, and the lake hardly noticed.")
	if String(GameState.flag("ql_bloom") if GameState.flag("ql_bloom") else "") == "bright":
		lines.append("Hesper's moss bloomed brighter than it had in forty years.")
	if GameState.has_flag("read_wren_note"):
		lines.append("Somewhere below, Wren Askew went looking for whoever keeps the deep pumps running.")
	lines.append("And under the Lower Stations, someone is still running the machine.")
	await fade.card(lines, 2.8)
	await fade.card(["I want to see what is deeper down."], 3.6, UiTheme.LIVING)
	GameState.set_flag("chapter_one_done")
	GameState.discover("lore", "the_knock")
	Saves.save(0)
	await fade.card(["End of Chapter One: The Dry Well"], 2.2, UiTheme.DIM)
	await fade.fade_in(1.6)
	_busy = false


## The real ending, from the Bellows console: title, the world, each person, and you. Then the
## game carries on (the Unmapped opens below the Heart), unless you go topside.
func play_ending() -> void:
	if _busy:
		return
	_busy = true
	player.frozen = true
	var id := Ending.resolve()
	GameState.set_flag("ending_" + id, true)
	GameState.set_flag("ending_seen", true)
	GameState.set_flag("unmapped_open", true)
	Almanac.record_ending(id)
	await get_tree().create_timer(1.5).timeout
	await fade.fade_out(2.4)
	_update_music()
	for c: Dictionary in Ending.cards(id):
		await fade.card(c.lines, float(c.hold), c.color)
	Saves.save(0)
	_busy = false
	# The last question: home, or here.
	if GameState.has_flag("heart_running"):
		Dialogue.start_convo("_bellows", "topside")
		await Events.dialogue_ended
	if GameState.has_flag("went_topside"):
		_busy = true
		Almanac.record_ending("topside")
		await fade.card(["The great lift ran again, and one morning it went up.",
			"%s went home. Wick writes. The letters always start the same way." % String(GameState.player.get("name", "The salvager")),
			"Still here."], 2.8, UiTheme.LIVING)
		Saves.save(0)
		await fade.card(["Thank you for playing Bellows."], 3.0, UiTheme.ACCENT)
		_busy = false
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	await fade.card(["Thank you for playing Bellows.", "Wick carries on. Below the Heart, the stair goes on into the Unmapped."], 2.6, UiTheme.DIM)
	await fade.fade_in(1.6)
	player.frozen = false
	_update_music()


## A banner at the top of the screen as each chapter begins (it doesn't stop play).
func _chapter_banner(flag: StringName, _value: Variant) -> void:
	var titles := {&"learned_codes": ["Chapter Two", "Answering"], &"lift_built": ["Chapter Three", "The Lower Stations"],
		&"ways_open": ["Chapter Four", "The Bellows"]}
	if not titles.has(flag) or GameState.has_flag("banner_" + String(flag)):
		return
	GameState.set_flag("banner_" + String(flag), true)
	hud.banner(String(titles[flag][0]), String(titles[flag][1]))
