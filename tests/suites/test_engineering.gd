extends TestCase
## The Undercroft toolkit against the real Wick data: building, wiring and the cut-view helpers.


func before_each() -> void:
	GameState.new_game(77, "Test")
	Clock.start(1, 11 * 60)
	Sim.new_world(77)
	for item in ["pipe_section", "wire_coil", "brass_scrap", "blackstone", "glowglass"]:
		GameState.give(item, 20, true)
	for m: String in Content.machines:
		var u := String(Content.machine(m).get("unlock", ""))
		if u != "" and u != "start":
			GameState.set_flag(u)


func test_crank_powers_lamps_in_locker_cavity() -> void:
	eq(Sim.build("crank", Vector2i(21, 13)), "", "crank fits on the cavity floor")
	eq(Sim.build("lamp", Vector2i(23, 13)), "", "lamp fits")
	var laid := Sim.lay_conduit("wire", [Vector2i(21, 13), Vector2i(22, 13), Vector2i(23, 13)])
	eq(laid, 3, "three wire cells laid")
	var crank := Sim.find_machine("crank")
	var lamp := Sim.find_machine("lamp")
	Sim.crank(crank.id)
	Sim._tick_machines(1.0)
	eq(String(lamp.status), "ok", "lamp runs off the crank (status %s, sat %.2f, crank out %.1f)" % [lamp.status, lamp.power_sat, crank.power_out])
	check(lamp.light > 0.0, "lamp makes light")


func test_lamp_without_power_says_why() -> void:
	Sim.build("lamp", Vector2i(23, 13))
	Sim._tick_machines(1.0)
	var lamp := Sim.find_machine("lamp")
	check(lamp.status in [&"not_connected", &"no_power"], "unpowered lamp explains itself (%s)" % lamp.status)
	check(Inspect.machine_lines(lamp, Content.machine("lamp")).size() > 0, "plain-language lines exist")


func test_placement_reasons_are_plain() -> void:
	eq(Sim.build("lamp", Vector2i(5, 16)), "blocked", "can't build inside rock")
	check(Inspect.place_reason("blocked").length() > 5, "reason has words")
	eq(Sim.build("crank", Vector2i(22, 12)), "needs_floor", "crank needs footing")


func test_cell_text_describes_air() -> void:
	var t := Inspect.cell_text(Sim.grid, Vector2i(5, 20))
	check(t.contains("sour") or t.contains("foul"), "sour pocket reads as foul: %s" % t)
	var r := Inspect.cell_text(Sim.grid, Vector2i(5, 16))
	check(r.begins_with("Rock"), "rock described: %s" % r)


func test_undercroft_view_coordinates_round_trip() -> void:
	var v := UndercroftView.new()
	v.grid = Sim.grid
	for c in [Vector2i(0, 10), Vector2i(24, 13), Vector2i(47, 23), Vector2i(10, 4)]:
		eq(v.world_to_cell(v.cell_center(c)), c, "cell %s round trip" % c)
	v.free()


func test_drag_path_is_an_l() -> void:
	var e := EngineeringView.new()
	e.drag_from = Vector2i(2, 12)
	e.cursor = Vector2i(8, 15)
	var cells := e._drag_cells()
	eq(cells.size(), 10, "6 across + 3 down + start")
	eq(cells[0], Vector2i(2, 12), "starts at the press")
	eq(cells[cells.size() - 1], Vector2i(8, 15), "ends at the cursor")
	for i in range(1, cells.size()):
		var d: Vector2i = cells[i] - cells[i - 1]
		check(absi(d.x) + absi(d.y) == 1, "contiguous at %d" % i)
	e.free()
