extends TestCase
## Boots the real game scene headless and pokes every interactive path a player can reach.
## Any engine error raised along the way fails the test (the runner counts them).

var game: Node3D


func before_each() -> void:
	GameFlow.new_game(31337, "Smoke")
	GameState.set_flag("intro_done")


func _boot() -> Node3D:
	var tree := Engine.get_main_loop() as SceneTree
	var g: Node3D = load("res://scenes/game.tscn").instantiate()
	tree.root.add_child(g)
	tree.current_scene = g
	return g


func _shutdown(g: Node3D) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	Dialogue.cancel()
	if g.panels and g.panels.is_open():
		g.panels.close()
	Clock.clear_pauses()
	tree.current_scene = null
	g.free()


func test_wick_interactables_and_tools() -> void:
	var g := _boot()
	check(g.area != null and g.area.id == "wick", "Wick loaded")
	var here := 0
	for id: String in Content.npcs:
		if Npc.area_of(id) == "wick":
			here += 1
	check(g.npcs.size() == here, "every resident who lives in Wick spawned (%d of %d)" % [g.npcs.size(), here])
	check(here >= 5, "Wick's five residents live in Wick at the start")
	# Every prompt in town evaluates.
	for node in g.get_tree().get_nodes_in_group("interactable"):
		var it := node as Interactable
		if it:
			it.prompt()
	# The Lease kit, then every tool on the farm.
	g.actions._seed_tin()
	Dialogue.cancel()
	g.actions._old_tools()
	for t in ["glass", "hammer", "wrench"]:
		GameState.add_tool(t)
	for tool: String in GameState.player.tools:
		GameState.select_tool(tool)
		for c in [Vector2i(8, 16), Vector2i(9, 16), Vector2i(12, 18)]:
			g.actions.use_tool(c)
			Dialogue.cancel()
	g.actions.cycle_seed()
	# NPC routing for a whole day of schedule changes.
	for m in range(0, 24 * 60, 30):
		Clock.minute = float(m)
		for n: Npc in g.npcs.values():
			n.think()
	_shutdown(g)


func test_every_reach_cavern_loads() -> void:
	var g := _boot()
	GameState.set_flag("tremor_done")   # opens the Trunk passage so every node is reachable
	var ids: Array = []
	for node: Dictionary in GameState.reach_graph.nodes:
		ids.append(String(node.id))       # a snapshot: visiting the Unmapped grows the graph
	for id: String in ids:
		g.load_area(id)
		eq(g.area.id, id, "loaded %s" % id)
		for it in g.get_tree().get_nodes_in_group("interactable"):
			(it as Interactable).prompt()
		for r: Dictionary in g.area.resources:
			check(ResourceLoader.exists("res://assets/textures/props/%s.png" % String(r.type)), "resource %s in %s has a sprite" % [r.type, id])
		# Mine whatever is there (lore pages open a panel; close it).
		GameState.add_tool("hammer")
		for r: Dictionary in g.area.resources.duplicate():
			g.mine_at(Vector2i(int(r.x), int(r.z)))
			if g.panels.is_open():
				g.panels.close()
	g.load_area("wick")
	eq(g.area.id, "wick", "back to Wick")
	_shutdown(g)


func test_every_conversation_both_ways() -> void:
	for npc: String in Content.dialogue:
		for cid: String in Content.dialogue[npc].get("convos", {}):
			for pick in [0, 9]:
				check(Dialogue.start_convo(npc, cid), "%s/%s starts" % [npc, cid])
				var guard := 0
				while Dialogue.active and guard < 120:
					guard += 1
					if Dialogue.has_choices():
						Dialogue.choose(mini(pick, Dialogue._choices.size() - 1))
					else:
						Dialogue.advance()
				check(not Dialogue.active, "%s/%s finishes" % [npc, cid])
	for npc: String in Content.dialogue:
		Dialogue.pick_bark(npc)


func test_cut_view_inspects_everything() -> void:
	var g := _boot()
	var e := EngineeringView.new()
	g.add_child(e)
	e.view.rebuild()
	e.active = true
	for o in EngineeringView.OVERLAYS:
		e.set_overlay(o)
	GameState.add_tool("glass")
	for m: String in Content.machines:
		var u := String(Content.machine(m).get("unlock", ""))
		if u != "" and u != "start":
			GameState.set_flag(u)
	for t: Array in EngUi.TOOLS:
		e.set_tool(String(t[0]))
		for c in [Vector2i(24, 13), Vector2i(36, 13), Vector2i(5, 20), Vector2i(38, 21)]:
			e.cursor = c
			e._update_cursor()
			e._hover_key = ""
			e._update_hover()
	e.build_def = "burner"
	e.set_tool("build")
	e._update_cursor()
	for m: MachineState in Sim.machines.machines.values():
		e._show_machine(m)
	for r: Dictionary in Content.undercroft.get("relics", []):
		e._show_cell(Vector2i(int(r.x), int(r.y)))
	for c in [Vector2i(24, 13), Vector2i(10, 15), Vector2i(36, 19)]:
		e._show_cell(c)
	e.ui.show_build_menu()
	e.active = false
	_shutdown(g)


func test_save_and_load_mid_game() -> void:
	var g := _boot()
	GameState.give("glowbeet", 7, true)
	GameState.give("brass_scrap", 4, true)
	GameState.give("wire_coil", 2, true)
	eq(Sim.build("crank", Vector2i(21, 13)), "", "crank built before saving")
	Society.change("mags", "affection", 9.0)
	Threads.check()
	check(Saves.save(3), "saved")
	GameState.take("glowbeet", 7)
	eq(Saves.load_slot(3), "", "loaded")
	eq(GameState.inventory.count("glowbeet"), 7, "beets came back")
	check(Sim.find_machine("crank") != null, "crank came back")
	Saves.delete_slot(3)
	_shutdown(g)
