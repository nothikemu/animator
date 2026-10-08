class_name Scenarios
extends RefCounted
## Developer scenarios for screenshots and testing: put the world into a specific state.
##   godot -- --scenario=wick_day --capture=/tmp/shot.png


static func run(game: Node, name: String) -> void:
	var parts := name.split(":")
	match parts[0]:
		"wick_day":
			Clock.start(1, 10 * 60)
			_place(game, Vector2(12.5, 17.5))
		"wick_night":
			Clock.start(1, 23 * 60)
			_place(game, Vector2(22.5, 14.5))
		"commons":
			Clock.start(1, 19 * 60)
			_place(game, Vector2(23.5, 15.5))
		"arrival":
			Clock.start(1, 7 * 60)
			_place(game, Vector2(4.5, 6.5))
		"lease":
			Clock.start(1, 9 * 60)
			_place(game, Vector2(6.5, 12.5))
		"pumphall":
			Clock.start(1, 14 * 60)
			_place(game, Vector2(40.5, 14.5))
		"lake":
			Clock.start(1, 21 * 60)
			_place(game, Vector2(14.5, 22.5))
		"reach":
			# reach:<area id>[:x:z] — loads any area below Wick, optionally standing somewhere.
			var id: String = parts[1] if parts.size() > 1 else String(GameState.reach_graph.nodes[0].id)
			game.load_area(id)
			if parts.size() > 3:
				_place(game, Vector2(float(parts[2]), float(parts[3])))
		"pos":
			_place(game, Vector2(float(parts[1]), float(parts[2])))
		"cut_demo":
			# A small working circuit in the locker cavity: crank -> wire -> two lamps.
			Clock.start(1, 11 * 60)
			_place(game, Vector2(24.5, 19.5))
			GameState.add_tool("glass")
			_kit()
			for b in [["crank", Vector2i(21, 13)], ["lamp", Vector2i(23, 13)], ["lamp", Vector2i(25, 13)]]:
				var err: String = Sim.build(String(b[0]), b[1])
				if err != "":
					Log.warn("scenario", "build %s: %s" % [b[0], err])
			Sim.lay_conduit("wire", [Vector2i(21, 13), Vector2i(22, 13), Vector2i(23, 13), Vector2i(24, 13), Vector2i(25, 13)])
			var cr := Sim.find_machine("crank")
			if cr:
				for i in 4:
					Sim.crank(cr.id)
			Sim._tick_machines(1.0)
			game.toggle_cut_view.call_deferred()
			if parts.size() > 1:
				game.get_tree().create_timer(0.1).timeout.connect(func() -> void:
					if game.engineering:
						game.engineering.overlay = parts[1])
		"midgame":
			# A plausible day-3 state for UI and dialogue checks.
			Clock.start(3, 13 * 60)
			_place(game, Vector2(30.5, 13.5))
			for f in ["intro_done", "lease_tools", "lease_seed_tin", "got_glass", "learned_pipes", "wick_revealed"]:
				GameState.set_flag(f)
			GameState.discover("places", "undercroft")
			for t in ["tiller", "can", "glass", "hammer"]:
				GameState.add_tool(t)
			for id in Content.npcs:
				Society.mark_met(id)
			Society.change("barnaby", "trust", 12.0)
			Society.change("barnaby", "shared", 6.0)
			Society.change("hesper", "affection", 11.0)
			Society.change("odile", "respect", 8.0)
			Society.change("mags", "affection", 14.0)
			Society.change("grist", "fear", 6.0)
			for item in [["glowbeet", 8], ["moss_fiber", 6], ["brass_scrap", 5], ["glowglass", 2], ["pipe_section", 4], ["ember_resin", 3], ["sulfur", 2], ["bellcap", 1]]:
				GameState.give(String(item[0]), int(item[1]), true)
			GameState.add_money(64)
			for l in ["moss_frames", "first_knock", "tier1", "relic_crew_locker"]:
				GameState.discover("lore", l)
			GameState.add_deed("harvested", 4.0)
			Sim.repair("pipe", Vector2i(24, 13))
			for i in 4:
				Threads.check()
			GameState.set_flag("well_fixed")
			Requests.reset()
			for d in [1, 2, 3]:
				Requests.refresh(d)
		"talk":
			# talk:<npc> — opens that resident's best conversation.
			Clock.start(1, 8 * 60)
			GameState.set_flag("intro_done")
			var who: String = parts[1] if parts.size() > 1 else "barnaby"
			game.get_tree().create_timer(0.3).timeout.connect(func() -> void:
				var n: Npc = game.npcs.get(who)
				if n:
					game.player.place(Vector2(n.position.x - 1.2, n.position.z + 0.6), game.area)
					game.rig.snap()
					game.start_dialogue(n))
		"quietlight":
			Clock.start(5, 22 * 60 + 20)
			_place(game, Vector2(14.5, 21.5))
			GameState.set_flag("intro_done")
			GameState.set_flag("quietlight_announced")
			Director.trigger("quietlight")
		"tremor":
			# The Tremor's aftermath seen through the glass: fissure open, sour gas climbing.
			Clock.start(6, 10 * 60)
			_place(game, Vector2(8.5, 19.5))
			GameState.add_tool("glass")
			Director.trigger("tremor")
			for i in 90:
				Sim._field_step()
			game.toggle_cut_view.call_deferred()
		"harvest":
			# A bed of glowbeets at every stage, then one harvested in slow motion.
			Clock.start(2, 13 * 60)
			_place(game, Vector2(10.5, 17.2))
			GameState.add_tool("tiller")
			var k := 0
			for x in range(7, 15):
				for z in range(15, 19):
					var c := Vector2i(x, z)
					if Sim.till(c) and Sim.plant(c, "glowbeet" if (x + z) % 3 else "cave_moss"):
						Sim.plots[c].growth = clampf(0.15 + 0.12 * float(k % 9), 0.0, 1.0)
						Sim.plots[c].water = 0.8
						k += 1
			if game.farm:
				game.farm.refresh_all()
			game.get_tree().create_timer(1.0).timeout.connect(func() -> void:
				var c := Vector2i(10, 16)
				Sim.plots[c].growth = 1.0
				Sim.plots[c].crop = "glowbeet"
				game.actions._hands(c)
				Engine.time_scale = 0.12)
		"trunk":
			# The Trunk chamber after the Tremor: Wren's camp and the spares crate.
			GameState.set_flag("tremor_done")
			for n: Dictionary in GameState.reach_graph.nodes:
				if bool(n.get("trunk", false)):
					game.load_area(String(n.id))
					var rp: Vector2i = game.area.points.get("ruin", Vector2i(10, 10))
					_place(game, Vector2(rp.x + 0.5, rp.y + 2.5))
		"opening":
			Clock.start(1, 7 * 60)
			game.opening()
		"cut_exit":
			# Enters the cut, then leaves it again: checks the return transition restores the town.
			Clock.start(1, 11 * 60)
			_place(game, Vector2(24.5, 19.5))
			GameState.add_tool("glass")
			game.toggle_cut_view.call_deferred()
			game.get_tree().create_timer(4.0).timeout.connect(func() -> void: game.toggle_cut_view())
		"cut":
			# cut[:overlay[:tool]] — opens the Undercroft view from the well.
			Clock.start(1, 11 * 60)
			_place(game, Vector2(24.5, 19.5))
			GameState.add_tool("glass")
			_kit()
			game.toggle_cut_view.call_deferred()
			if parts.size() > 1:
				game.get_tree().create_timer(0.1).timeout.connect(func() -> void:
					var e: Node = game.engineering
					if e:
						e.overlay = parts[1]
						if parts.size() > 2:
							e.build_def = parts[3] if parts.size() > 3 else ""
							e.tool = parts[2])
	if game.has_method("on_scenario"):
		game.on_scenario(name)


## Materials and schematics for engineering tests.
static func _kit() -> void:
	for item in ["pipe_section", "wire_coil", "brass_scrap", "blackstone", "glowglass", "seal_gum", "glowbeet", "filter_pad", "moss_fiber", "thermal_ore"]:
		GameState.give(item, 12, true)
	for m: String in Content.machines:
		var u := String(Content.machine(m).get("unlock", ""))
		if u != "" and u != "start":
			GameState.set_flag(u)


static func _place(game: Node, p: Vector2) -> void:
	game.player.place(p, game.area)
	game.rig.snap()
