extends TestCase
## The whole chapter, played through the real systems from the cistern crisis to the knock.
## If this passes, the vertical slice can be finished.


func before_each() -> void:
	GameFlow.new_game(2024, "Tester")
	for f in ["intro_done", "lease_tools", "lease_seed_tin", "got_glass", "learned_pipes"]:
		GameState.set_flag(f)
	GameState.discover("places", "undercroft")
	for i in 6:
		Threads.check()


func _ticks(minutes: int) -> void:
	for i in minutes:
		Sim._tick_machines(1.0)
		for k in 3:
			Sim._field_step()


func _give(items: Dictionary) -> void:
	for it: String in items:
		GameState.give(it, int(items[it]), true)


func test_cistern_pump_on_a_crank() -> void:
	GameState.set_flag("b_thanked_well")
	Threads.check()
	eq(Threads.stage("power"), 1, "power thread running")
	_give({"brass_scrap": 10, "wire_coil": 16, "blackstone": 4, "pipe_section": 20})
	eq(Sim.build("pump", Vector2i(37, 20)), "", "electric pump stands in the Sink")
	check(Sim.build("crank", Vector2i(35, 21)) == "" , "a crank can stand in the Sink...")
	Sim.machines.mark_dirty()
	_ticks(1)
	eq(String(Sim.find_machine("crank").status), "flooded", "...but it floods, and says so")
	Sim.deconstruct(Vector2i(35, 21))
	eq(Sim.build("crank", Vector2i(40, 15)), "", "crank on the dry pump-hall floor")
	var line: Array = [Vector2i(37, 19), Vector2i(37, 18), Vector2i(37, 17)]
	for x in range(36, 30, -1):
		line.append(Vector2i(x, 17))
	for y in [16, 15, 14, 13]:
		line.append(Vector2i(31, y))
	line.push_front(Vector2i(37, 20))
	check(Sim.lay_conduit("pipe", line) >= 12, "pipe from the pump to the cistern wall")
	# The old station line shares the outlet; its cracks would bleed everything away.
	for c in [Vector2i(33, 12), Vector2i(34, 12)]:
		eq(Sim.repair("pipe", c), "", "mended %s" % c)
	Threads.check()
	eq(Threads.stage("power"), 2, "pump placed")
	var w: Array = [Vector2i(40, 15), Vector2i(40, 16), Vector2i(40, 17), Vector2i(39, 17), Vector2i(38, 17), Vector2i(37, 17), Vector2i(37, 18), Vector2i(37, 19), Vector2i(37, 20)]
	eq(Sim.lay_conduit("wire", w), w.size(), "wire from the crank down to the pump")
	var crank := Sim.find_machine("crank")
	for i in 4:
		Sim.crank(crank.id)
	var before := Sim.cistern_level()
	_ticks(20)
	var pump := Sim.find_machine("pump")
	eq(String(pump.status), "ok", "pump runs (%s)" % pump.status)
	check(pump.water_moved > 0.0, "pump moves water")
	check(Sim.cistern_level() >= before - 0.001, "cistern holds or climbs (%.3f -> %.3f)" % [before, Sim.cistern_level()])
	Threads.check()
	check(Threads.is_done("power"), "cistern thread done")


func test_tremor_station_and_the_knock() -> void:
	GameState.set_flag("reach_open")
	GameState.set_flag("b_station_asked")
	Threads.check()
	eq(Threads.stage("station7"), 1, "station thread starts")
	GameState.set_flag("seen_station_pump")
	Threads.check()
	eq(Threads.stage("station7"), 2, "needs a coil")
	Director.trigger("tremor")
	Threads.check()
	eq(Threads.stage("station7"), 3, "the Trunk chamber is open")
	check(ReachGen.passable({"kind": "sealed"}, GameState.flags), "sealed passage now passable")
	# The coil is in the trunk node's ruin.
	var found := false
	for n: Dictionary in GameState.reach_graph.nodes:
		if bool(n.get("trunk", false)):
			var a := ReachGen.generate_cavern(GameState.seed_value, GameState.reach_graph, String(n.id))
			for r: Dictionary in a.resources:
				if String(r.get("item", "")) == "governor_coil":
					found = true
	check(found, "a governor coil exists in the Trunk chamber")
	_give({"governor_coil": 1, "seal_gum": 4, "brass_scrap": 12, "wire_coil": 20})
	Threads.check()
	eq(Threads.stage("station7"), 4, "fit the coil")
	var sp := Sim.find_machine("station_pump")
	eq(Sim.load_item(sp.id, "governor_coil", 1), 1, "coil fitted")
	eq(Sim.load_item(sp.id, "seal_gum", 4), 4, "seals fitted")
	for x in [35, 40, 43]:
		eq(Sim.build("crank", Vector2i(x, 15)), "", "crank at %d,15" % x)
	var wire: Array = []
	for x in range(35, 45):
		wire.append(Vector2i(x, 15))
	check(Sim.lay_conduit("wire", wire) >= 9, "wire along the pump hall floor")
	for m: MachineState in Sim.machines.machines.values():
		if m.def_id == "crank":
			for i in 4:
				Sim.crank(m.id)
	for c in [Vector2i(33, 12), Vector2i(34, 12), Vector2i(41, 17), Vector2i(41, 19)]:
		Sim.repair("pipe", c)
	_ticks(10)
	eq(String(sp.status), "ok", "Station 7 runs (%s, power %.2f)" % [sp.status, sp.power_sat])
	check(bool(Sim.fact("running.station_pump")), "fact agrees")
	Threads.check()
	eq(Threads.stage("station7"), 5, "talk to Barnaby")
	eq(String(Dialogue.pick_line("barnaby").get("id", "")), "b_valve", "Barnaby's valve conversation is up")
	Dialogue.start_with("barnaby")
	var guard := 0
	while Dialogue.active and guard < 60:
		guard += 1
		if Dialogue.has_choices():
			Dialogue.choose(0)
		else:
			Dialogue.advance()
	eq(String(GameState.flag("valve_choice")), "open", "chose to open")
	Threads.check()
	eq(Threads.stage("station7"), 6, "meet at the valve")
	check(Dialogue.start_convo("barnaby", "finale_open"), "finale runs")
	guard = 0
	while Dialogue.active and guard < 60:
		guard += 1
		Dialogue.advance()
	check(GameState.has_flag("knock_heard"), "the knock")
	check(GameState.has_flag("valve_open"), "valve open")
	Threads.check()
	check(Threads.is_done("station7"), "chapter thread complete")
