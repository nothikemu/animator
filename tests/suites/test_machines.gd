extends TestCase
## Resource networks and the generic machine evaluator.

const DEFS := {
	"gen": {"name": "G", "desc": "", "size": [1, 1], "cost": {}, "placement": "any", "power": {"produce": 40}},
	"fuelgen": {"name": "F", "desc": "", "size": [1, 1], "cost": {}, "placement": "any", "power": {"produce": 40},
		"fuel": {"items": {"glowbeet": 60}, "capacity": 5}, "emit_gas": {"sour": 0.05}, "heat": 5.0, "dirty": true},
	"load": {"name": "L", "desc": "", "size": [1, 1], "cost": {}, "placement": "any", "power": {"consume": 25}},
	"bigload": {"name": "B", "desc": "", "size": [1, 1], "cost": {}, "placement": "any", "power": {"consume": 50}},
	"batt": {"name": "C", "desc": "", "size": [1, 1], "cost": {}, "placement": "any", "battery": {"capacity": 100, "rate": 30}},
	"pump": {"name": "P", "desc": "", "size": [1, 1], "cost": {}, "placement": "any", "pump": {"rate": 0.5}},
	"intake": {"name": "I", "desc": "", "size": [1, 1], "cost": {}, "placement": "any", "intake": {"rate": 1.0}},
	"outlet": {"name": "O", "desc": "", "size": [1, 1], "cost": {}, "placement": "any", "outlet": {"rate": 1.0}},
	"well": {"name": "W", "desc": "", "size": [1, 1], "cost": {}, "placement": "any", "pump": {"rate": 0.5, "manual": true}, "well": {"capacity": 3.0}},
	"scrub": {"name": "S", "desc": "", "size": [1, 1], "cost": {}, "placement": "any", "scrub": {"sour": 0.1, "radius": 1}},
	"floorbox": {"name": "FB", "desc": "", "size": [2, 1], "cost": {}, "placement": "floor"},
}


func _open_grid(w := 20, h := 10) -> UcGrid:
	var g := UcGrid.new(w, h, h - 1)
	for y in h:
		for x in w:
			g.mat[g.idx(x, y)] = UcGrid.Mat.ROCK if y == h - 1 else UcGrid.Mat.AIR
	g.fill_open_with_ambient()
	return g


func _wire(mw: MachineWorld, from_x: int, to_x: int, y: int) -> void:
	for x in range(from_x, to_x + 1):
		mw.set_conduit("wire", Vector2i(x, y))


func test_generator_powers_a_connected_load() -> void:
	var g := _open_grid()
	var mw := MachineWorld.new(DEFS)
	var gen := mw.add_machine("gen", Vector2i(1, 2))
	var ld := mw.add_machine("load", Vector2i(6, 2))
	_wire(mw, 1, 6, 2)
	mw.tick(g, 1.0)
	near(ld.power_sat, 1.0, 0.001, "load fully powered")
	eq(ld.status, &"ok", "load status")
	near(gen.power_out, 25.0, 0.01, "generator only supplies what is used")


func test_unconnected_load_reports_not_connected() -> void:
	var g := _open_grid()
	var mw := MachineWorld.new(DEFS)
	mw.add_machine("gen", Vector2i(1, 2))
	var ld := mw.add_machine("load", Vector2i(6, 2))
	mw.tick(g, 1.0)
	eq(ld.status, &"not_connected", "load without wire")


func test_deficit_gives_partial_power() -> void:
	var g := _open_grid()
	var mw := MachineWorld.new(DEFS)
	mw.add_machine("gen", Vector2i(1, 2))
	var a := mw.add_machine("load", Vector2i(3, 2))
	var b := mw.add_machine("load", Vector2i(4, 2))
	_wire(mw, 1, 4, 2)
	mw.tick(g, 1.0)
	near(a.power_sat, 0.8, 0.001, "40 supply / 50 demand")
	near(b.power_sat, 0.8, 0.001, "shared fairly")


func test_battery_charges_on_surplus_and_covers_deficit() -> void:
	var g := _open_grid()
	var mw := MachineWorld.new(DEFS)
	var gen := mw.add_machine("gen", Vector2i(1, 2))
	var bat := mw.add_machine("batt", Vector2i(2, 2))
	_wire(mw, 1, 2, 2)
	for i in 3:
		mw.tick(g, 1.0)
	check(bat.stored > 50.0, "battery should charge from surplus (got %.1f)" % bat.stored)
	gen.enabled = false
	var ld := mw.add_machine("load", Vector2i(3, 2))
	mw.set_conduit("wire", Vector2i(3, 2))
	mw.tick(g, 1.0)
	near(ld.power_sat, 1.0, 0.001, "battery covers the load")


func test_overload_burns_a_wire_and_splits_the_network() -> void:
	var g := _open_grid()
	var mw := MachineWorld.new(DEFS, 7)
	mw.add_machine("gen", Vector2i(1, 2))
	mw.add_machine("gen", Vector2i(2, 2))
	mw.add_machine("bigload", Vector2i(5, 2))
	mw.add_machine("load", Vector2i(6, 2))
	_wire(mw, 1, 6, 2)
	var burnt := false
	for i in 20:
		for e in mw.tick(g, 1.0):
			if e.type == "wire_burnt":
				burnt = true
	check(burnt, "75 pw through a 60 pw wire should eventually burn out")


func test_pump_moves_water_through_pipes() -> void:
	var g := _open_grid()
	for x in range(1, 4):
		g.water[g.idx(x, 8)] = 1.0
	var mw := MachineWorld.new(DEFS)
	mw.add_machine("intake", Vector2i(1, 8))
	mw.add_machine("pump", Vector2i(2, 5))
	var out := mw.add_machine("outlet", Vector2i(12, 8))
	for y in range(5, 9):
		mw.set_conduit("pipe", Vector2i(1, y))
	for x in range(1, 13):
		mw.set_conduit("pipe", Vector2i(x, 5))
	for y in range(5, 9):
		mw.set_conduit("pipe", Vector2i(12, y))
	var before := g.total_water()
	mw.tick(g, 1.0)
	check(out.water_moved > 0.0, "outlet reports flow")
	for i in 3:
		mw.tick(g, 1.0)
	check(g.water[g.idx(12, 8)] > 0.5, "outlet cell should receive water (got %.3f)" % g.water[g.idx(12, 8)])
	near(g.total_water(), before, 0.0001, "pumping conserves water")


func test_pipes_connect_through_a_machine() -> void:
	var g := _open_grid()
	g.water[g.idx(1, 8)] = 1.0
	var mw := MachineWorld.new(DEFS)
	mw.add_machine("intake", Vector2i(1, 8))
	mw.add_machine("pump", Vector2i(5, 5))
	mw.add_machine("outlet", Vector2i(10, 8))
	# Two separate pipe runs that only meet inside the pump's cell.
	for y in range(5, 9):
		mw.set_conduit("pipe", Vector2i(1, y))
	for x in range(1, 6):
		mw.set_conduit("pipe", Vector2i(x, 5))
	for x in range(5, 11):
		mw.set_conduit("pipe", Vector2i(x, 4))
	mw.set_conduit("pipe", Vector2i(5, 4))
	for y in range(4, 9):
		mw.set_conduit("pipe", Vector2i(10, y))
	mw.rebuild()
	eq(mw.water_nets.size(), 1, "runs merge through the pump")


func test_burst_pipe_leaks_instead_of_delivering() -> void:
	var g := _open_grid()
	g.water[g.idx(1, 8)] = 1.0
	g.water[g.idx(2, 8)] = 1.0
	var mw := MachineWorld.new(DEFS)
	mw.add_machine("intake", Vector2i(1, 8))
	var w := mw.add_machine("well", Vector2i(8, 2))
	for y in range(2, 9):
		mw.set_conduit("pipe", Vector2i(1, y))
	for x in range(1, 9):
		mw.set_conduit("pipe", Vector2i(x, 2), 0.0 if x == 4 else 1.0)
	w.manual_timer = 5.0
	mw.tick(g, 1.0)
	near(w.basin, 0.0, 0.0001, "nothing reaches the well past a burst segment")
	check(mw.last.leaked > 0.0, "water leaks at the burst")
	check(g.water[g.idx(4, 2)] > 0.0, "leaked water appears at the burst cell")
	mw.repair_conduit("pipe", Vector2i(4, 2))
	w.manual_timer = 5.0
	mw.tick(g, 1.0)
	check(w.basin > 0.3, "after repair the well fills (got %.3f)" % w.basin)


func test_fuel_generator_burns_fuel_and_pollutes() -> void:
	var g := _open_grid()
	var mw := MachineWorld.new(DEFS)
	var f := mw.add_machine("fuelgen", Vector2i(3, 4))
	mw.add_machine("load", Vector2i(4, 4))
	_wire(mw, 3, 4, 4)
	mw.tick(g, 1.0)
	eq(f.status, &"no_fuel", "empty burner")
	f.fuel_items["glowbeet"] = 2
	var sour_before := g.total_species(UcGrid.SOUR)
	var t_before := g.temp[g.idx(3, 4)]
	for i in 10:
		mw.tick(g, 1.0)
	eq(f.status, &"ok", "fuelled burner runs")
	check(g.total_species(UcGrid.SOUR) > sour_before, "burner emits sour gas")
	check(g.temp[g.idx(3, 4)] > t_before, "burner heats its cell")
	check(f.fuel_minutes < 60.0, "fuel is consumed")


func test_scrubber_cleans_sour_air() -> void:
	var g := _open_grid()
	g.add_gas(5, 4, UcGrid.SOUR, 0.5)
	var mw := MachineWorld.new(DEFS)
	mw.add_machine("scrub", Vector2i(5, 4))
	var before := g.total_species(UcGrid.SOUR)
	for i in 5:
		mw.tick(g, 1.0)
	check(g.total_species(UcGrid.SOUR) < before, "scrubber removes sour gas")


func test_placement_rules() -> void:
	var g := _open_grid()
	var mw := MachineWorld.new(DEFS)
	eq(mw.placement_error("floorbox", Vector2i(3, 2), g), "needs_floor", "floating floor machine")
	eq(mw.placement_error("floorbox", Vector2i(3, 8), g), "", "machine on the floor")
	eq(mw.placement_error("floorbox", Vector2i(3, 9), g), "blocked", "inside rock")
	mw.add_machine("floorbox", Vector2i(3, 8))
	eq(mw.placement_error("floorbox", Vector2i(4, 8), g), "occupied", "overlap")


func test_machine_world_round_trip() -> void:
	var g := _open_grid()
	var mw := MachineWorld.new(DEFS)
	var f := mw.add_machine("fuelgen", Vector2i(3, 4))
	f.fuel_items["glowbeet"] = 3
	_wire(mw, 3, 6, 4)
	mw.set_conduit("pipe", Vector2i(2, 2), 0.4)
	var mw2 := MachineWorld.new(DEFS)
	mw2.load_dict(mw.to_dict())
	eq(mw2.machines.size(), 1, "machine count")
	eq(int(mw2.machines.values()[0].fuel_items.get("glowbeet", 0)), 3, "hopper contents")
	near(float(mw2.pipes[Vector2i(2, 2)]), 0.4, 0.0001, "pipe health")
	eq(mw2.wires.size(), 4, "wires")
	mw2.tick(g, 1.0)
