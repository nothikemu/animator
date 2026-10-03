extends Node
## Owns Wick's simulation: the Undercroft grid, machines + conduits, and farm plots.
## Fields step at a fixed rate driven by game time; machines tick once per game minute;
## crops every ten game minutes. Everything keeps running while the player is away.

const STEPS_PER_MINUTE := 3.0
const MAX_STEPS_PER_FRAME := 3        ## catch-up limit; keeps a slow frame from snowballing
const STEP_DT := 0.25
const CROP_INTERVAL := 10
const FARM_COLUMNS := Vector2i(6, 15)
const VILLAGE_COLUMNS := Vector2i(2, 45)

signal stepped()                         ## a field step happened (visuals may refresh)
signal ticked()                          ## machines ticked

var grid: UcGrid
var machines: MachineWorld
var plots: Dictionary = {}               ## Vector2i(x, z) on the Wick map -> plot dict
var drains: Array = []
var static_lights: Array = []            ## [{pos: Vector2, energy, range, kind}]
var slice_z := 20
var active := false
var field_steps := 0
var last_tick_ms := 0.0
var last_step_ms := 0.0
var town_water := 1.0                    ## smoothed share of the town's water demand served
var cistern_capacity := 16.0

var _step_acc := 0.0
var _sour_acc := 0.0
var _dirty_acc := 0.0
var _clean_acc := 0.0
var _leak_acc := 0.0
var _last_status: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	Clock.advanced.connect(_on_advanced)
	Clock.minute_tick.connect(_on_minute)
	Clock.time_skipped.connect(fast_forward)


func new_world(seed_value: int) -> void:
	var def := Content.undercroft
	grid = WickBuilder.build_grid(def)
	machines = WickBuilder.build_machines(def, Content.machines, seed_value)
	drains = def.get("drains", [])
	slice_z = int(def.get("slice_z", 20))
	plots.clear()
	_rng.seed = hash([seed_value, "sim"])
	_build_static_lights()
	active = true
	# Let the initial state settle so the first look at the Undercroft is calm.
	for i in 40:
		_field_step()
	machines.rebuild()


func _build_static_lights() -> void:
	static_lights.clear()
	for p in Content.wick_map.get("props", []):
		var t := String(p.get("type", ""))
		var pos := Vector2(float(p.x) + 0.5, float(p.z) + 0.5)
		var s := float(p.get("scale", 1.0))
		match t:
			"glowroot":
				static_lights.append({"pos": pos, "energy": 0.62 * s, "range": 5.0 * s, "kind": "glow"})
			"glowroot_small":
				static_lights.append({"pos": pos, "energy": 0.3, "range": 2.4, "kind": "glow"})
			"town_lamp", "porch_lamp":
				static_lights.append({"pos": pos, "energy": 0.5, "range": 4.2, "kind": "lamp"})


# --- Ticking ---------------------------------------------------------------------------

func _on_advanced(minutes: float) -> void:
	if not active:
		return
	_step_acc += minutes * STEPS_PER_MINUTE
	var n := mini(int(_step_acc), MAX_STEPS_PER_FRAME)
	for i in n:
		_field_step()
	_step_acc = minf(_step_acc - n, 12.0)


func _field_step() -> void:
	var t0 := Time.get_ticks_usec()
	match Clock.breath():
		"exhale": grid.vent_scale = 2.5
		"inhale": grid.vent_scale = 0.3
		_: grid.vent_scale = 1.0
	grid.step(STEP_DT)
	WickBuilder.apply_drains(grid, drains, 1.0)
	field_steps += 1
	last_step_ms = (Time.get_ticks_usec() - t0) / 1000.0
	stepped.emit()


func _on_minute(m: int) -> void:
	if not active:
		return
	_tick_machines(1.0)
	if m % CROP_INTERVAL == 0:
		_tick_crops(float(CROP_INTERVAL))
	if m % 60 == 0:
		_report_deeds()


func _tick_machines(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	var events := machines.tick(grid, dt)
	last_tick_ms = (Time.get_ticks_usec() - t0) / 1000.0
	_sour_acc += float(machines.last.get("sour", 0.0))
	_dirty_acc += float(machines.last.get("dirty_power", 0.0))
	_clean_acc += float(machines.last.get("clean_power", 0.0))
	_leak_acc += float(machines.last.get("leaked", 0.0))
	town_water = lerpf(town_water, float(machines.last.get("town_served", 1.0)), 0.02 * dt)
	for e in events:
		match String(e.type):
			"wire_burnt":
				Events.toast.emit("A wire burnt out under the load.", &"warn")
				Events.world_event.emit(&"wire_burnt", e)
				Events.camera_impulse.emit(0.25)
				GameState.add_deed("overloaded", 1.0)
			"produced":
				Events.machine_changed.emit(int(e.id))
	if events.size() > 0:
		Events.sim_topology_changed.emit()
	for m: MachineState in machines.machines.values():
		if _last_status.get(m.id, &"") != m.status:
			_last_status[m.id] = m.status
			Events.machine_status_changed.emit(m.id, m.status)
	ticked.emit()


func _report_deeds() -> void:
	if _sour_acc > 0.01:
		GameState.add_deed("pollution", _sour_acc * 10.0, {"where": "wick"})
	if _dirty_acc > 1.0:
		GameState.add_deed("industrial_power", _dirty_acc / 600.0)
	if _clean_acc > 1.0:
		GameState.add_deed("clean_power", _clean_acc / 600.0)
	if _leak_acc > 0.05:
		GameState.add_deed("leaked_water", _leak_acc)
	_sour_acc = 0.0
	_dirty_acc = 0.0
	_clean_acc = 0.0
	_leak_acc = 0.0


## Catch-up after sleep or a blackout: coarse steps that keep the world consistent.
func fast_forward(minutes: float) -> void:
	if not active:
		return
	var chunks := int(minutes / 10.0)
	for i in chunks:
		_tick_machines(10.0)
		for s in 5:
			_field_step()
		_tick_crops(10.0)
	_report_deeds()


# --- Farm ------------------------------------------------------------------------------

func is_farm_soil(cell: Vector2i) -> bool:
	var map: Dictionary = Content.wick_map
	var rows: Array = map.get("mat", [])
	if cell.y < 0 or cell.y >= rows.size():
		return false
	var row := String(rows[cell.y])
	if cell.x < 0 or cell.x >= row.length():
		return false
	return String(map.legend.get(row[cell.x], "")) == "farm_soil"


func plot_at(cell: Vector2i) -> Dictionary:
	return plots.get(cell, {})


func till(cell: Vector2i) -> bool:
	if plots.has(cell) or not is_farm_soil(cell):
		return false
	plots[cell] = {"crop": "", "growth": 0.0, "health": 1.0, "water": 0.0, "dead": false,
		"pollinated": false, "fertile": 0.0, "planted_day": 0, "sour_eaten": 0.0}
	Events.crop_changed.emit(_plot_index(cell))
	return true


func plant(cell: Vector2i, crop_id: String) -> bool:
	var p: Dictionary = plots.get(cell, {})
	if p.is_empty() or String(p.crop) != "" or not Content.crops.has(crop_id):
		return false
	p.crop = crop_id
	p.growth = 0.0
	p.health = 1.0
	p.dead = false
	p.planted_day = Clock.day
	Events.crop_changed.emit(_plot_index(cell))
	return true


func water_plot(cell: Vector2i) -> bool:
	var p: Dictionary = plots.get(cell, {})
	if p.is_empty():
		return false
	p.water = 1.0
	grid.set_surface_moisture(cell.x, grid.surface_moisture(cell.x) + 0.08)
	Events.crop_changed.emit(_plot_index(cell))
	return true


func fertilise(cell: Vector2i) -> bool:
	var p: Dictionary = plots.get(cell, {})
	if p.is_empty():
		return false
	p.fertile = 1.0
	Events.crop_changed.emit(_plot_index(cell))
	return true


## Harvests a mature plot; returns {item: n}. Clears dead husks (returns {}).
func harvest(cell: Vector2i) -> Dictionary:
	var p: Dictionary = plots.get(cell, {})
	if p.is_empty() or String(p.crop) == "":
		return {}
	if p.dead:
		p.crop = ""
		p.dead = false
		p.growth = 0.0
		Events.crop_changed.emit(_plot_index(cell))
		return {}
	if not CropLogic.is_mature(p):
		return {}
	var def: Dictionary = Content.crop(p.crop)
	var out := CropLogic.expected_yield(p, def)
	if def.has("seed_return"):
		var sr: Array = def.seed_return
		var n := _rng.randi_range(int(sr[0]), int(sr[1]))
		if n > 0:
			out[String(def.seed)] = int(out.get(String(def.seed), 0)) + n
	if bool(def.get("sour_bonus", false)) and float(p.get("sour_eaten", 0.0)) > 0.05:
		for item in def.yield:
			out[item] = int(out[item]) + 1
	Events.harvest.emit(StringName(p.crop), 1)
	p.crop = ""
	p.growth = 0.0
	p.health = 1.0
	p.pollinated = false
	p.sour_eaten = 0.0
	Events.crop_changed.emit(_plot_index(cell))
	return out


func plot_env(cell: Vector2i) -> Dictionary:
	var air := grid.surface_air(cell.x)
	var p: Dictionary = plots.get(cell, {})
	var moist := maxf(float(p.get("water", 0.0)), grid.surface_moisture(cell.x))
	var topsoil_t := grid.temp[grid.idx(clampi(cell.x, 0, grid.w - 1), grid.ground_y)]
	return {"light": light_at(Vector2(cell.x + 0.5, cell.y + 0.5)), "moisture": moist,
		"temp": (float(air.temp) + topsoil_t) * 0.5, "sour": float(air.sour), "stale": float(air.stale)}


func _tick_crops(minutes: float) -> void:
	var phase := Clock.phase()
	for cell: Vector2i in plots:
		var p: Dictionary = plots[cell]
		if String(p.crop) == "" or p.dead:
			continue
		var def: Dictionary = Content.crop(p.crop)
		var env := plot_env(cell)
		var mins := minutes
		if def.has("grows_in") and not (def.grows_in as Array).has(phase):
			mins = 0.0
		if float(p.get("fertile", 0.0)) > 0.0:
			mins *= 1.5
			p.fertile = maxf(0.0, float(p.fertile) - minutes / 1440.0)
		var was_mature := CropLogic.is_mature(p)
		var was_stage := CropLogic.stage(p)
		CropLogic.advance(p, def, env, mins)
		# Crops drink from the soil column as well as their own watering.
		if p.water <= 0.0:
			var m := grid.surface_moisture(cell.x)
			grid.set_surface_moisture(cell.x, m - float(def.get("thirst", 0.6)) * minutes / 1440.0 * 0.3)
		# Living filters: moss breathes in stale air, ferns eat sour gas.
		if def.has("scrub"):
			for sp in def.scrub:
				var k := UcGrid.SPECIES.find(sp)
				var amt := float(def.scrub[sp]) * minutes * (0.5 + 0.5 * float(p.growth))
				var eaten := grid.convert_gas(cell.x, grid.ground_y - 1, k, UcGrid.FRESH, amt)
				if sp == "sour":
					p.sour_eaten = float(p.get("sour_eaten", 0.0)) + eaten
		# Lampmoths pollinate lit glowbeets when the air is clean at Hush.
		if p.crop == "glowbeet" and phase == "hush" and float(env.light) > 0.3 and float(env.sour) < 0.05:
			p.pollinated = true
		if CropLogic.stage(p) != was_stage or p.dead or (CropLogic.is_mature(p) and not was_mature):
			Events.crop_changed.emit(_plot_index(cell))
			if p.dead:
				GameState.add_deed("crop_died", 1.0, {"crop": p.crop})


func _plot_index(cell: Vector2i) -> int:
	return cell.y * 1000 + cell.x


## Light reaching a point on the village floor (0..1+). Used by crops; visuals use real lights.
func light_at(pos: Vector2) -> float:
	var total := 0.0
	var glow := Clock.glow_level()
	var dark := Clock.darkness()
	for l in static_lights:
		var d: float = pos.distance_to(l.pos)
		if d >= float(l.range):
			continue
		var f: float = pow(1.0 - d / float(l.range), 2.0)
		var e: float = float(l.energy)
		if l.kind == "glow":
			e *= glow
		elif l.kind == "lamp":
			e *= 0.25 + 0.75 * dark
		total += e * f
	for m: MachineState in machines.machines.values():
		if m.light <= 0.0:
			continue
		var ld: Dictionary = Content.machine(m.def_id).get("light", {})
		var mp := Vector2(m.cell.x + m.size.x * 0.5, slice_z + 0.5)
		var d := pos.distance_to(mp)
		var r := float(ld.get("range", 5.0))
		if d < r:
			total += float(ld.get("grow", 0.4)) * m.light * pow(1.0 - d / r, 2.0)
	for cell: Vector2i in plots:
		var p: Dictionary = plots[cell]
		if p.crop == "glowbeet" and CropLogic.is_mature(p):
			var d := pos.distance_to(Vector2(cell.x + 0.5, cell.y + 0.5))
			if d < 1.8 and d > 0.01:
				total += 0.3 * (1.0 - d / 1.8)
	return clampf(total, 0.0, 1.5)


# --- Building & engineering ------------------------------------------------------------

## Returns "" on success or a reason key.
func build(def_id: String, cell: Vector2i) -> String:
	var def: Dictionary = Content.machine(def_id)
	if def.is_empty():
		return "unknown"
	if not GameState.can_build(def_id):
		return "not_known"
	var err := machines.placement_error(def_id, cell, grid)
	if err != "":
		return err
	var cost: Dictionary = def.get("cost", {})
	if not GameState.inventory.has_all(cost):
		return "no_materials"
	GameState.inventory.remove_all(cost)
	var m := machines.add_machine(def_id, cell)
	GameState.discover("machines", def_id)
	GameState.add_deed("built", 1.0, {"machine": def_id})
	if bool(def.get("dirty", false)):
		GameState.add_deed("built_dirty", 1.0, {"machine": def_id})
	elif def.has("turbine") or def.has("scrub"):
		GameState.add_deed("built_clean", 1.0, {"machine": def_id})
	Events.sim_topology_changed.emit()
	Events.machine_changed.emit(m.id)
	return ""


func deconstruct(cell: Vector2i) -> bool:
	var m := machines.machine_at(cell)
	if m == null or m.fixed:
		return false
	var def: Dictionary = Content.machine(m.def_id)
	machines.remove_machine(m.id)
	for item in def.get("cost", {}):
		var back := int(ceil(int(def.cost[item]) * 0.5))
		if back > 0:
			GameState.give(item, back, true)
	for item in m.fuel_items:
		if int(m.fuel_items[item]) > 0:
			GameState.give(item, int(m.fuel_items[item]), true)
	Events.sim_topology_changed.emit()
	return true


func conduit_item(layer: String) -> String:
	return "pipe_section" if layer == "pipe" else "wire_coil"


## Lays conduit on each cell that doesn't already have it. Returns cells laid.
func lay_conduit(layer: String, cells: Array) -> int:
	var item := conduit_item(layer)
	var laid := 0
	var l := machines.pipes if layer == "pipe" else machines.wires
	for c in cells:
		if l.has(c) or not machines.can_lay_conduit(c, grid):
			continue
		if not GameState.take(item, 1):
			break
		machines.set_conduit(layer, c, 1.0)
		laid += 1
	if laid > 0:
		Events.sim_topology_changed.emit()
	return laid


func remove_conduit(layer: String, cell: Vector2i) -> bool:
	if machines.remove_conduit(layer, cell):
		GameState.give(conduit_item(layer), 1, true)
		Events.sim_topology_changed.emit()
		return true
	return false


## Repairs a damaged conduit. Pipes take seal gum (or a pipe section); wires take a coil.
func repair(layer: String, cell: Vector2i) -> String:
	var l := machines.pipes if layer == "pipe" else machines.wires
	if not l.has(cell) or float(l[cell]) >= 1.0:
		return "not_damaged"
	if layer == "pipe":
		if not GameState.take("seal_gum", 1) and not GameState.take("pipe_section", 1):
			return "no_materials"
	elif not GameState.take("wire_coil", 1):
		return "no_materials"
	machines.repair_conduit(layer, cell)
	GameState.add_deed("repaired", 1.0, {"layer": layer, "x": cell.x, "y": cell.y})
	Events.sim_topology_changed.emit()
	return ""


## Fills an open cell with packed blackstone (seals fissures, blocks gas).
func fill_cell(cell: Vector2i) -> String:
	if not grid.is_open(cell.x, cell.y) or machines.occupancy.has(cell):
		return "blocked"
	if not GameState.take("blackstone", 2):
		return "no_materials"
	grid.set_mat(cell.x, cell.y, UcGrid.Mat.ROCK)
	GameState.add_deed("sealed_cell", 1.0)
	Events.grid_cells_changed.emit([cell])
	return ""


func crank(machine_id: int) -> bool:
	var m: MachineState = machines.machines.get(machine_id)
	if m == null:
		return false
	var def: Dictionary = Content.machine(m.def_id)
	if def.has("crank"):
		m.manual_timer = minf(m.manual_timer + float(def.crank.get("minutes", 30.0)), 120.0)
		return true
	if def.has("pump") and bool(def.pump.get("manual", false)):
		m.manual_timer = minf(m.manual_timer + 4.0, 12.0)
		return true
	return false


func load_item(machine_id: int, item: String, n: int) -> int:
	var m: MachineState = machines.machines.get(machine_id)
	if m == null:
		return 0
	var def: Dictionary = Content.machine(m.def_id)
	var accepted := false
	if def.has("fuel") and (def.fuel.get("items", {}) as Dictionary).has(item):
		accepted = true
	if def.has("filter") and String(def.filter.get("item", "")) == item:
		accepted = true
	if def.has("compost") and String(def.compost.get("input", "")) == item:
		accepted = true
	if def.has("requires") and (def.requires as Dictionary).has(item):
		var need := int(def.requires[item]) - int(m.story.get(item, 0))
		n = mini(n, need)
		if n > 0 and GameState.take(item, n):
			m.story[item] = int(m.story.get(item, 0)) + n
			Events.machine_changed.emit(m.id)
			return n
		return 0
	if not accepted:
		return 0
	var cap := int(def.get("fuel", {}).get("capacity", 10))
	var have := int(m.fuel_items.get(item, 0))
	n = mini(n, maxi(0, cap - have))
	if n <= 0 or not GameState.take(item, n):
		return 0
	m.fuel_items[item] = have + n
	Events.machine_changed.emit(m.id)
	return n


## Empties a machine's output buffer into the inventory (sludge, fertiliser).
func collect_output(machine_id: int) -> Dictionary:
	var m: MachineState = machines.machines.get(machine_id)
	if m == null:
		return {}
	var def: Dictionary = Content.machine(m.def_id)
	var n := int(floor(m.waste))
	if n <= 0:
		return {}
	var item := String(def.get("waste", {}).get("item", def.get("compost", {}).get("output", "")))
	if item.is_empty():
		return {}
	var got := GameState.give(item, n)
	m.waste -= got
	return {item: got}


func take_well_water(amount: float) -> float:
	for m: MachineState in machines.machines.values():
		if m.def_id == "old_well":
			var got := minf(m.basin, amount)
			m.basin -= got
			return got
	return 0.0


func well() -> MachineState:
	for m: MachineState in machines.machines.values():
		if m.def_id == "old_well":
			return m
	return null


func find_machine(def_id: String) -> MachineState:
	for m: MachineState in machines.machines.values():
		if m.def_id == def_id:
			return m
	return null


# --- Facts for the rule language -------------------------------------------------------

func fact(key: String) -> Variant:
	if grid == null:
		return null
	match key:
		"pollution": return village_pollution()
		"pollution_farm": return column_avg_sour(FARM_COLUMNS.x, FARM_COLUMNS.y)
		"cistern": return cistern_level()
		"town_water": return town_water
		"noise_lane": return machines.last.get("noise", 0.0)
		"exhale": return Clock.breath() == "exhale"
		"planted":
			var n := 0
			for c: Vector2i in plots:
				if String(plots[c].get("crop", "")) != "":
					n += 1
			return n
		"well_flowing":
			var w := well()
			return w != null and (w.basin > 0.15 or (w.water_moved > 0.01 and w.on_water_net and machines.water_net_of(w).get("leak", 1.0) < 0.05))
		"fissure_sealed":
			for cell in Content.undercroft.get("fissure", []):
				var c := Vector2i(int(cell[0]), int(cell[1]))
				# Sealed when no open fissure cell reaches the surface: packing any one row closes it.
				if not grid.is_open(c.x, c.y):
					return true
			return false
		"power":
			var total := 0.0
			for net: Dictionary in machines.power_nets:
				total += float(net.get("supply", 0.0))
			return total
		"leaks":
			var n := 0
			for c: Vector2i in machines.pipes:
				if float(machines.pipes[c]) < 1.0:
					n += 1
			return n
	if key.begins_with("air_sour_"):
		var npc := key.substr(9)
		var home := String(Content.npc(npc).get("home", ""))
		var pt: Array = Content.wick_map.get("points", {}).get(home, [24, 20])
		return grid.surface_air(int(pt[0])).sour
	if key.begins_with("machine."):
		var n := 0
		for m: MachineState in machines.machines.values():
			if m.def_id == key.substr(8):
				n += 1
		return n
	if key.begins_with("running."):
		for m: MachineState in machines.machines.values():
			if m.def_id == key.substr(8) and m.status == &"ok":
				return true
		return false
	return null


func column_avg_sour(x0: int, x1: int) -> float:
	var s := 0.0
	for x in range(x0, x1 + 1):
		s += float(grid.surface_air(x).sour)
	return s / float(x1 - x0 + 1)


func village_pollution() -> float:
	return column_avg_sour(VILLAGE_COLUMNS.x, VILLAGE_COLUMNS.y)


func cistern_level() -> float:
	var s := 0.0
	for y in range(13, 17):
		for x in range(27, 31):
			s += minf(grid.water[grid.idx(x, y)], 1.0)
	return clampf(s / cistern_capacity, 0.0, 1.0)


# --- Serialisation -----------------------------------------------------------------------

func to_dict() -> Dictionary:
	var ps := []
	var keys := plots.keys()
	keys.sort()
	for c in keys:
		var p: Dictionary = plots[c].duplicate()
		p.erase("last_factors")
		p["x"] = c.x
		p["z"] = c.y
		ps.append(p)
	return {"grid": grid.to_dict(), "machines": machines.to_dict(), "plots": ps,
		"town_water": town_water}


func load_dict(d: Dictionary, seed_value: int) -> void:
	new_world(seed_value)
	if d.get("grid") is Dictionary:
		var g := UcGrid.from_dict(d.grid)
		if g.w == grid.w and g.h == grid.h:
			grid = g
		else:
			Log.warn("sim", "saved grid size mismatch; keeping fresh grid")
	if d.get("machines") is Dictionary:
		machines.load_dict(d.machines)
	plots.clear()
	for p in d.get("plots", []):
		if not p is Dictionary:
			continue
		var c := Vector2i(int(p.get("x", 0)), int(p.get("z", 0)))
		var crop := String(p.get("crop", ""))
		if crop != "" and not Content.crops.has(crop):
			crop = ""
		plots[c] = {"crop": crop, "growth": clampf(float(p.get("growth", 0.0)), 0.0, 1.0),
			"health": clampf(float(p.get("health", 1.0)), 0.0, 1.0),
			"water": clampf(float(p.get("water", 0.0)), 0.0, 1.0), "dead": bool(p.get("dead", false)),
			"pollinated": bool(p.get("pollinated", false)), "fertile": clampf(float(p.get("fertile", 0.0)), 0.0, 1.0),
			"planted_day": int(p.get("planted_day", 0)), "sour_eaten": float(p.get("sour_eaten", 0.0))}
	town_water = clampf(float(d.get("town_water", 1.0)), 0.0, 1.0)
	machines.rebuild()
