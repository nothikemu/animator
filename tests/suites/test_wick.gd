extends TestCase
## Integration: the authored Wick undercroft behaves the way the opening story needs.


func before_each() -> void:
	GameState.new_game(99, "Tester")
	Clock.start(1, 6 * 60)
	Sim.new_world(99)
	Society.reset()
	Economy.reset()
	Threads.reset()
	Director.reset(99)


func _crank_and_run(minutes: int) -> void:
	var w := Sim.well()
	for i in minutes:
		Sim.crank(w.id)
		Sim._tick_machines(1.0)
		for s in 3:
			Sim._field_step()


func test_the_well_starts_dry_because_the_feed_line_is_burst() -> void:
	var w := Sim.well()
	check(w != null, "well exists")
	_crank_and_run(6)
	check(w.basin < 0.01, "cranking yields nothing (basin %.3f)" % w.basin)
	check(Sim.machines.last.leaked > 0.0 or Sim.grid.water[Sim.grid.idx(24, 13)] > 0.0, "the burst sprays into the crawlspace")


func test_repairing_the_burst_brings_water_back() -> void:
	GameState.give("pipe_section", 2, true)
	eq(Sim.repair("pipe", Vector2i(24, 13)), "", "repair succeeds")
	_crank_and_run(4)
	check(Sim.well().basin > 0.5, "the well fills after the repair (basin %.3f)" % Sim.well().basin)


func test_town_mains_draw_down_the_cistern() -> void:
	var start := Sim.cistern_level()
	check(start > 0.3, "cistern starts with water (%.2f)" % start)
	Sim.fast_forward(1440.0)
	check(Sim.cistern_level() < start - 0.1, "a day of town use lowers the cistern (%.2f -> %.2f)" % [start, Sim.cistern_level()])


func test_the_sink_holds_a_stable_level() -> void:
	var lvl := func() -> float:
		var s := 0.0
		for y in range(17, 22):
			for x in range(34, 44):
				s += Sim.grid.water[Sim.grid.idx(x, y)]
		return s
	var before: float = lvl.call()
	Sim.fast_forward(1440.0 * 2)
	var after: float = lvl.call()
	check(absf(after - before) < before * 0.35, "spring and drain balance (%.1f -> %.1f)" % [before, after])


func test_spring_waterfall_drives_a_turbine() -> void:
	GameState.set_flag("schematic_turbine", true)
	GameState.give("brass_scrap", 5, true)
	GameState.give("glowglass", 3, true)
	GameState.give("wire_coil", 3, true)
	eq(Sim.build("turbine", Vector2i(46, 14)), "", "turbine fits in the waterfall shaft")
	for i in 60:
		Sim._field_step()
	Sim._tick_machines(1.0)
	var t := Sim.find_machine("turbine")
	check(t.power_out > 0.0 or t.status != &"dry", "turbine finds falling water (status %s)" % t.status)


func test_tremor_lets_sour_gas_reach_the_farm() -> void:
	var before := Sim.column_avg_sour(5, 10)
	Director._hook_tremor({})
	for i in 360:
		Sim._field_step()
	var after := Sim.column_avg_sour(5, 10)
	check(after > before + 0.01, "sour rises through the fissure to the Lease (%.4f -> %.4f)" % [before, after])
	check(GameState.has_flag("tremor_done"), "tremor flag set")


func test_burner_pollution_reaches_settlement_air() -> void:
	GameState.set_flag("schematic_burner", true)
	GameState.give("brass_scrap", 6, true)
	GameState.give("blackstone", 4, true)
	GameState.give("wire_coil", 6, true)
	eq(Sim.build("burner", Vector2i(12, 8)), "", "burner on the surface")
	GameState.give("glowbeet", 5, true)
	var b := Sim.find_machine("burner")
	Sim.load_item(b.id, "glowbeet", 5)
	eq(Sim.build("lamp", Vector2i(16, 9)), "not_known", "lamp needs its schematic")
	GameState.set_flag("schematic_lamp", true)
	GameState.give("glowglass", 1, true)
	eq(Sim.build("lamp", Vector2i(16, 9)), "", "lamp on the surface")
	Sim.lay_conduit("wire", [Vector2i(13, 9), Vector2i(14, 9), Vector2i(15, 9), Vector2i(16, 9)])
	var before := Sim.column_avg_sour(8, 16)
	for i in 120:
		Sim._tick_machines(1.0)
		for s in 3:
			Sim._field_step()
	check(Sim.find_machine("lamp").status == &"ok", "lamp powered (%s)" % Sim.find_machine("lamp").status)
	check(Sim.column_avg_sour(8, 16) > before, "burner exhaust fouls the farm air")
	check(Sim.light_at(Vector2(16.5, 19.5)) > 0.2, "a powered lamp lights the farm edge")


func test_farm_cycle_till_plant_water_harvest() -> void:
	var cell := Vector2i(9, 17)
	check(Sim.is_farm_soil(cell), "Lease farm soil")
	check(Sim.till(cell), "till")
	check(Sim.plant(cell, "cave_moss"), "plant moss")
	for d in 3:
		Sim.water_plot(cell)
		Sim._tick_crops(1440.0)
	var p := Sim.plot_at(cell)
	check(CropLogic.is_mature(p), "moss mature after watering for its days (growth %.2f, health %.2f)" % [p.growth, p.health])
	var got := Sim.harvest(cell)
	check(int(got.get("moss_fiber", 0)) >= 2, "harvest gives fiber: %s" % [got])


func test_wick_map_is_coherent() -> void:
	var a := AreaMap.from_ascii(Content.wick_map)
	eq(a.w, 48, "width")
	eq(a.d, 32, "depth")
	var astar := a.build_astar()
	var pts: Dictionary = a.points
	for name in pts:
		var p: Vector2i = pts[name]
		check(a.is_walkable(p.x, p.y), "point '%s' is walkable" % name)
	for name in ["lease_door", "well", "commons", "exchange_door", "annex_door", "moss_beds", "reach_gate", "dock"]:
		var path := astar.get_id_path(pts.arrival, pts[name])
		check(path.size() > 0, "arrival connects to %s" % name)
