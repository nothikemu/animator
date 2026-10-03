class_name MachineWorld
extends RefCounted
## Machines + conduits (pipes, wires) living in the Undercroft grid.
##
## Behaviour is assembled from optional components in each machine definition
## (power/pump/intake/outlet/sprinkle/scrub/fan/fuel/battery/...). One generic evaluator
## handles every machine; adding a machine is a data change.
##
## Tick order (per in-game minute):
##   1. environment checks + producer potentials + consumer demand
##   2. power networks (supply/demand, batteries, wire overload)
##   3. water networks (pumps pull from cells/intakes, deliver to consumers/tanks, leaks)
##   4. apply effects into the grid (gas, heat, moisture, water) and settle statuses

const WIRE_CAPACITY := 60.0        ## power units a basic wire network can carry
const OVERLOAD_MINUTES := 6.0      ## sustained overload before a wire burns out
const PIPE_CAPACITY := 3.0         ## water units per minute a pipe network can carry

const STATUS_PRIORITY := [&"broken", &"off", &"flooded", &"not_connected", &"no_power",
	&"overloaded", &"no_fuel", &"needs_filter", &"output_full", &"no_water", &"dry",
	&"too_hot", &"choking", &"incomplete", &"idle", &"ok"]

var defs: Dictionary = {}
var machines: Dictionary = {}      ## id -> MachineState
var next_id := 1
var pipes: Dictionary = {}         ## Vector2i -> health (0 = burst; still conducts and leaks)
var wires: Dictionary = {}         ## Vector2i -> health (0 = burnt; does not conduct)
var occupancy: Dictionary = {}     ## Vector2i -> machine id
var rng := RandomNumberGenerator.new()

var power_nets: Array = []         ## [{cells, machines, supply, demand, load, overloaded}]
var water_nets: Array = []
var _overload_time: Dictionary = {}  ## anchor cell -> minutes overloaded
var _dirty := true

# Per-tick accounting, read by the Sim autoload for deeds/consequences.
var last := {"sour": 0.0, "stale": 0.0, "dirty_power": 0.0, "clean_power": 0.0,
	"water_pumped": 0.0, "leaked": 0.0, "scrubbed": 0.0, "noise": 0.0, "town_served": 1.0}


func _init(definitions: Dictionary = {}, seed_value: int = 0) -> void:
	defs = definitions
	rng.seed = seed_value


func def_of(m: MachineState) -> Dictionary:
	return defs.get(m.def_id, {})


# --- Building -----------------------------------------------------------------------

## Returns "" when placement is valid, otherwise a reason key ("blocked", "needs_floor", ...).
func placement_error(def_id: String, cell: Vector2i, grid: UcGrid) -> String:
	var d: Dictionary = defs.get(def_id, {})
	if d.is_empty():
		return "unknown"
	var size := _size_of(d)
	var mode := String(d.get("placement", "floor"))
	for dy in size.y:
		for dx in size.x:
			var c := cell + Vector2i(dx, dy)
			if not grid.in_bounds(c.x, c.y):
				return "out_of_bounds"
			if occupancy.has(c):
				return "occupied"
			if not grid.is_open(c.x, c.y):
				return "blocked"
	var bottom := cell.y + size.y - 1
	match mode:
		"floor", "water":
			for dx in size.x:
				if grid.is_open(cell.x + dx, bottom + 1) and not occupancy.has(Vector2i(cell.x + dx, bottom + 1)):
					return "needs_floor"
		"surface":
			if bottom != grid.ground_y - 1:
				return "needs_surface"
			for dx in size.x:
				if grid.is_open(cell.x + dx, bottom + 1):
					return "needs_floor"
		"ceiling":
			for dx in size.x:
				if grid.is_open(cell.x + dx, cell.y - 1):
					return "needs_ceiling"
		"any":
			pass
	return ""


func add_machine(def_id: String, cell: Vector2i, fixed := false) -> MachineState:
	var d: Dictionary = defs.get(def_id, {})
	var m := MachineState.new()
	m.id = next_id
	next_id += 1
	m.def_id = def_id
	m.cell = cell
	m.size = _size_of(d)
	m.fixed = fixed or bool(d.get("fixed", false))
	machines[m.id] = m
	for c in m.cells():
		occupancy[c] = m.id
	_dirty = true
	return m


func remove_machine(id: int) -> MachineState:
	var m: MachineState = machines.get(id)
	if m == null or m.fixed:
		return null
	for c in m.cells():
		occupancy.erase(c)
	machines.erase(id)
	_dirty = true
	return m


func machine_at(c: Vector2i) -> MachineState:
	var id: int = occupancy.get(c, 0)
	return machines.get(id)


func can_lay_conduit(c: Vector2i, grid: UcGrid) -> bool:
	if not grid.in_bounds(c.x, c.y):
		return false
	var m := grid.get_mat(c.x, c.y)
	return m != UcGrid.Mat.BEDROCK and m != UcGrid.Mat.EMBER and m != UcGrid.Mat.SEAL


func set_conduit(layer: String, c: Vector2i, health := 1.0) -> void:
	_layer(layer)[c] = clampf(health, 0.0, 1.0)
	_dirty = true


func remove_conduit(layer: String, c: Vector2i) -> bool:
	var had := _layer(layer).erase(c)
	if had:
		_dirty = true
	return had


func damage_conduit(layer: String, c: Vector2i, amount: float) -> void:
	var l := _layer(layer)
	if l.has(c):
		l[c] = clampf(float(l[c]) - amount, 0.0, 1.0)
		_dirty = true


func repair_conduit(layer: String, c: Vector2i) -> bool:
	var l := _layer(layer)
	if l.has(c) and float(l[c]) < 1.0:
		l[c] = 1.0
		_dirty = true
		return true
	return false


func _layer(layer: String) -> Dictionary:
	return pipes if layer == "pipe" else wires


func mark_dirty() -> void:
	_dirty = true


static func _size_of(d: Dictionary) -> Vector2i:
	var s: Array = d.get("size", [1, 1])
	return Vector2i(maxi(1, int(s[0])), maxi(1, int(s[1])))


# --- Topology ---------------------------------------------------------------------------

func rebuild() -> void:
	power_nets = _components(wires, true)
	water_nets = _components(pipes, false)
	for m: MachineState in machines.values():
		m.on_power_net = false
		m.on_water_net = false
	for net in power_nets:
		for id in net.machines:
			machines[id].on_power_net = true
	for net in water_nets:
		for id in net.machines:
			machines[id].on_water_net = true
	_dirty = false


func _components(layer: Dictionary, skip_broken: bool) -> Array:
	var seen := {}
	var nets: Array = []
	var keys := layer.keys()
	keys.sort()  # deterministic order regardless of build history
	for start in keys:
		if seen.has(start):
			continue
		if skip_broken and float(layer[start]) <= 0.0:
			continue
		var cells: Array[Vector2i] = []
		var mids := {}
		var stack: Array[Vector2i] = [start]
		seen[start] = true
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			cells.append(c)
			if occupancy.has(c):
				mids[occupancy[c]] = true
			for d in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
				var nb: Vector2i = c + d
				if layer.has(nb) and not seen.has(nb):
					if skip_broken and float(layer[nb]) <= 0.0:
						continue
					seen[nb] = true
					stack.append(nb)
		var ids := mids.keys()
		ids.sort()
		nets.append({"cells": cells, "machines": ids})
	# Machines join every conduit run they touch (pipes connect *through* a pump),
	# so merge components that share a machine.
	var merged := true
	while merged:
		merged = false
		for i in nets.size():
			for j in range(i + 1, nets.size()):
				var shared := false
				for id in nets[j].machines:
					if nets[i].machines.has(id):
						shared = true
						break
				if shared:
					nets[i].cells.append_array(nets[j].cells)
					for id in nets[j].machines:
						if not nets[i].machines.has(id):
							nets[i].machines.append(id)
					nets[i].machines.sort()
					nets.remove_at(j)
					merged = true
					break
			if merged:
				break
	for net in nets:
		net.merge({"anchor": _min_cell(net.cells), "supply": 0.0, "demand": 0.0, "load": 0.0,
			"overloaded": false, "leak": 0.0, "flow": 0.0})
	return nets


static func _min_cell(cells: Array[Vector2i]) -> Vector2i:
	var best := cells[0]
	for c in cells:
		if c.y < best.y or (c.y == best.y and c.x < best.x):
			best = c
	return best


func power_net_of(m: MachineState) -> Dictionary:
	for net in power_nets:
		if net.machines.has(m.id):
			return net
	return {}


func water_net_of(m: MachineState) -> Dictionary:
	for net in water_nets:
		if net.machines.has(m.id):
			return net
	return {}


# --- Tick -------------------------------------------------------------------------------

## Advances machines by `dt` in-game minutes. Returns a list of notable events.
func tick(grid: UcGrid, dt: float) -> Array:
	if _dirty:
		rebuild()
	var events: Array = []
	for k in last:
		last[k] = 0.0
	last["town_served"] = 1.0
	var reasons := {}            ## id -> Array of status reasons this tick
	var potential := {}          ## id -> power producible
	var demand := {}             ## id -> power wanted
	var base_eff := {}           ## id -> environment efficiency
	var ids := machines.keys()
	ids.sort()

	# 1. Environment + potentials ---------------------------------------------------
	for id in ids:
		var m: MachineState = machines[id]
		var d := def_of(m)
		var r: Array = []
		reasons[id] = r
		m.power_sat = 0.0
		m.water_sat = 0.0
		m.power_out = 0.0
		m.power_in = 0.0
		m.water_moved = 0.0
		m.light = 0.0
		m.noise = 0.0
		var hard := false
		if m.health <= 0.0:
			r.append(&"broken")
			hard = true
		if not m.enabled:
			r.append(&"off")
			hard = true
		if not bool(d.get("waterproof", false)) and _water_level(grid, m) > 0.55:
			r.append(&"flooded")
			hard = true
		if d.has("requires") and not _story_complete(m, d):
			r.append(&"incomplete")
			hard = true
		var eff := 1.0
		var t := _avg_temp(grid, m)
		var max_t := float(d.get("max_temp", 95.0))
		if t > max_t:
			eff *= clampf(1.0 - (t - max_t) / 25.0, 0.15, 1.0)
			r.append(&"too_hot")
		if bool(d.get("needs_air", false)):
			var fresh := _avg_fresh(grid, m)
			if fresh < 0.55:
				eff *= clampf((fresh - 0.15) / 0.4, 0.0, 1.0)
				r.append(&"choking")
		if hard:
			eff = 0.0
		base_eff[id] = eff
		# Producers
		var pot := 0.0
		if d.has("power") and d.power.has("produce") and eff > 0.0:
			var fuel_ok := true
			if d.has("fuel"):
				if m.fuel_minutes <= 0.0:
					_refuel(m, d)
				fuel_ok = m.fuel_minutes > 0.0
				if not fuel_ok:
					r.append(&"no_fuel")
			if fuel_ok:
				pot = float(d.power.produce) * eff
		if d.has("turbine") and eff > 0.0:
			var tf: Dictionary = d.turbine
			var fl := _avg_flow(grid, m)
			pot = minf(float(tf.get("max", 12.0)), fl * float(tf.get("per_flow", 30.0))) * eff
			if pot < 0.5:
				r.append(&"dry")
		if d.has("crank") and eff > 0.0:
			if m.manual_timer > 0.0:
				pot = float(d.crank.get("power", 20.0)) * eff
			else:
				r.append(&"idle")
		potential[id] = pot
		# Consumers
		var dem := 0.0
		if d.has("power") and d.power.has("consume") and not hard:
			dem = float(d.power.consume)
			if not m.on_power_net:
				r.append(&"not_connected")
		demand[id] = dem

	# 2. Power networks -------------------------------------------------------------
	for net in power_nets:
		var supply := 0.0
		var want := 0.0
		var batteries: Array = []
		for id in net.machines:
			supply += float(potential.get(id, 0.0))
			want += float(demand.get(id, 0.0))
			if def_of(machines[id]).has("battery") and float(base_eff[id]) > 0.0:
				batteries.append(machines[id])
		var discharge := 0.0
		if want > supply:
			var deficit := want - supply
			for b: MachineState in batteries:
				var bd: Dictionary = def_of(b).battery
				var can := minf(float(bd.get("rate", 30.0)), b.stored / maxf(dt, 0.001))
				var give := minf(can, deficit - discharge)
				if give > 0.0:
					b.stored -= give * dt
					b.power_out = give
					discharge += give
		var available := supply + discharge
		var load := minf(available, want)
		var sat := 1.0 if want <= 0.0 else clampf(available / want, 0.0, 1.0)
		var overloaded := load > WIRE_CAPACITY + 0.01
		if overloaded:
			sat *= WIRE_CAPACITY / load
			var anchor: Vector2i = net.anchor
			_overload_time[anchor] = float(_overload_time.get(anchor, 0.0)) + dt
			if float(_overload_time[anchor]) >= OVERLOAD_MINUTES:
				var cell: Vector2i = net.cells[rng.randi_range(0, net.cells.size() - 1)]
				wires[cell] = 0.0
				_overload_time.erase(anchor)
				_dirty = true
				events.append({"type": "wire_burnt", "cell": cell})
		else:
			_overload_time.erase(net.anchor)
		# Surplus charges batteries.
		var surplus := maxf(0.0, supply - want)
		var surplus_before := surplus
		for b: MachineState in batteries:
			if surplus <= 0.0:
				break
			var bd: Dictionary = def_of(b).battery
			var room := (float(bd.get("capacity", 600.0)) - b.stored) / maxf(dt, 0.001)
			var take := minf(minf(float(bd.get("rate", 30.0)), room), surplus)
			if take > 0.0:
				b.stored += take * dt
				b.power_in = take
				surplus -= take
		var used := minf(supply, load) + (surplus_before - surplus)
		net.supply = supply + discharge
		net.demand = want
		net.load = load
		net.overloaded = overloaded
		for id in net.machines:
			var m: MachineState = machines[id]
			if float(demand.get(id, 0.0)) > 0.0:
				m.power_sat = sat
				m.power_in = float(demand[id]) * sat
				if overloaded:
					reasons[id].append(&"overloaded")
			var pot: float = potential.get(id, 0.0)
			if pot > 0.0:
				var util := clampf(used / maxf(supply, 0.001), 0.0, 1.0)
				m.power_out = pot * util
				m.efficiency = util
	for id in ids:
		var m: MachineState = machines[id]
		if float(demand.get(id, 0.0)) > 0.0:
			if m.on_power_net and m.power_sat < 0.05:
				reasons[id].append(&"no_power")
			elif not m.on_power_net:
				m.power_sat = 0.0

	# 3. Water networks ---------------------------------------------------------------
	for net in water_nets:
		_solve_water(net, grid, dt, reasons, base_eff, events)
	for id in ids:
		var m: MachineState = machines[id]
		var d := def_of(m)
		if _water_demand(m, d, grid, 1.0) > 0.0 and not m.on_water_net and not d.has("pump"):
			reasons[id].append(&"no_water")

	# 4. Apply effects ----------------------------------------------------------------
	for id in ids:
		var m: MachineState = machines[id]
		var d := def_of(m)
		var eff: float = base_eff[id]
		if d.has("power") and d.power.has("consume"):
			eff *= m.power_sat
		if d.has("water_use"):
			eff *= m.water_sat
			if m.water_sat < 0.05 and m.on_water_net:
				reasons[id].append(&"no_water")
		_apply(m, d, grid, dt, eff, reasons[id], events)
		m.status = _pick_status(reasons[id], eff)
		last["noise"] += m.noise
	return events


func _solve_water(net: Dictionary, grid: UcGrid, dt: float, reasons: Dictionary,
		base_eff: Dictionary, _events: Array) -> void:
	var pump_cap := 0.0
	var sources: Array = []      # [machine, available]
	var tanks: Array = []
	var consumers: Array = []    # [machine, demand]
	var need := 0.0
	var tank_store := 0.0
	var tank_space := 0.0
	for id in net.machines:
		var m: MachineState = machines[id]
		var d := def_of(m)
		var e: float = base_eff[id]
		if d.has("pump"):
			var pd: Dictionary = d.pump
			var run := e
			if bool(pd.get("manual", false)):
				run = e if m.manual_timer > 0.0 else 0.0
			elif d.has("power") and d.power.has("consume"):
				run *= m.power_sat
			pump_cap += float(pd.get("rate", 0.5)) * run * dt
			var avail := _cells_water(grid, m)
			if avail > 0.0:
				sources.append([m, avail])
			elif run > 0.0 and not bool(pd.get("manual", false)):
				reasons[id].append(&"dry")
		if d.has("intake"):
			var avail := minf(_cells_water(grid, m), float(d.intake.get("rate", 1.0)) * dt)
			if avail > 0.0:
				sources.append([m, avail])
			else:
				reasons[id].append(&"dry")
		if d.has("tank"):
			tanks.append(m)
			tank_store += m.stored
			tank_space += maxf(0.0, float(d.tank.get("capacity", 10.0)) - m.stored)
		var dem := _water_demand(m, d, grid, dt) * (1.0 if e > 0.0 else 0.0)
		if dem > 0.0:
			consumers.append([m, dem])
			need += dem
	var pumpable := 0.0
	for s in sources:
		pumpable += float(s[1])
	var pumped := minf(minf(pump_cap, pumpable), PIPE_CAPACITY * dt)
	# Leaks: burst/cracked pipe segments lose part of everything that passes.
	var leak_frac := 0.0
	var leak_cells: Array = []
	for c in net.cells:
		var hp := float(pipes.get(c, 1.0))
		if hp < 1.0:
			leak_frac += 1.0 - hp
			leak_cells.append(c)
	leak_frac = clampf(leak_frac, 0.0, 1.0)
	var to_consumers := minf(need, pumped + tank_store)
	var from_pumped := minf(to_consumers, pumped)
	var from_tanks := to_consumers - from_pumped
	var spare := pumped - from_pumped
	var to_tanks := minf(spare, tank_space)
	var drawn := from_pumped + to_tanks
	# Draw the pumped water out of the grid, proportionally to what each source offered.
	if drawn > 0.0 and pumpable > 0.0:
		for s in sources:
			var share := drawn * float(s[1]) / pumpable
			_take_cells_water(grid, s[0], share)
			s[0].water_moved += share
	# Tanks
	if tank_store > 0.0 and from_tanks > 0.0:
		for t: MachineState in tanks:
			t.stored -= from_tanks * t.stored / tank_store
	var tank_in := to_tanks * (1.0 - leak_frac)
	if tank_space > 0.0 and tank_in > 0.0:
		for t: MachineState in tanks:
			var room := maxf(0.0, float(def_of(t).tank.get("capacity", 10.0)) - t.stored)
			t.stored += tank_in * room / tank_space
	var leaked := (from_pumped + to_tanks) * leak_frac
	if leaked > 0.0 and not leak_cells.is_empty():
		for c in leak_cells:
			_leak_into(grid, c, leaked / leak_cells.size())
		last["leaked"] += leaked
	var delivered := from_pumped * (1.0 - leak_frac) + from_tanks
	for pair in consumers:
		var m: MachineState = pair[0]
		var dem: float = pair[1]
		var got := delivered * dem / need if need > 0.0 else 0.0
		m.water_sat = clampf(got / dem, 0.0, 1.0)
		m.water_moved += got
		_receive_water(m, def_of(m), grid, got)
	if need > 0.0 and pump_cap <= 0.0 and tank_store <= 0.0:
		for pair in consumers:
			reasons[pair[0].id].append(&"no_water")
	net.flow = (drawn + from_tanks) / maxf(dt, 0.001)
	net.leak = leak_frac
	net.demand = need / maxf(dt, 0.001)
	last["water_pumped"] += drawn


func _water_demand(m: MachineState, d: Dictionary, grid: UcGrid, dt: float) -> float:
	var dem := 0.0
	if d.has("water_use"):
		dem += float(d.water_use) * dt
	if d.has("well"):
		dem += maxf(0.0, float(d.well.get("capacity", 4.0)) - m.basin)
	if d.has("outlet"):
		var lvl := _water_level(grid, m)
		if lvl < 0.98:
			dem += float(d.outlet.get("rate", 1.0)) * dt
	return dem


func _receive_water(m: MachineState, d: Dictionary, grid: UcGrid, amount: float) -> void:
	if amount <= 0.0:
		return
	if d.has("well"):
		var take := minf(amount, maxf(0.0, float(d.well.get("capacity", 4.0)) - m.basin))
		m.basin += take
		amount -= take
	if d.has("outlet") and amount > 0.0:
		var c := m.cells()[m.cells().size() - 1]
		grid.add_water(c.x, c.y, amount)
	# water_use consumers simply consume it (sprinklers convert it in _apply).


func _apply(m: MachineState, d: Dictionary, grid: UcGrid, dt: float, eff: float, r: Array,
		events: Array) -> void:
	var activity := eff
	# Generators: fuel, heat and exhaust scale with how much of their output is used.
	if d.has("power") and d.power.has("produce"):
		var util := m.efficiency if m.power_out > 0.0 else 0.0
		activity = util
		if d.has("fuel") and m.fuel_minutes > 0.0 and float(base_eff_running(m)) > 0.0:
			var burn := dt * maxf(util, 0.2)
			m.fuel_minutes = maxf(0.0, m.fuel_minutes - burn)
		if bool(d.get("dirty", false)):
			last["dirty_power"] += m.power_out * dt
		else:
			last["clean_power"] += m.power_out * dt
	if d.has("turbine") or d.has("crank"):
		activity = clampf(m.power_out / maxf(float(d.get("turbine", d.get("crank", {})).get("max", 15.0)), 1.0), 0.0, 1.0)
		last["clean_power"] += m.power_out * dt
	if d.has("crank") and m.manual_timer > 0.0:
		m.manual_timer = maxf(0.0, m.manual_timer - dt)
	if d.has("pump") and bool(d.pump.get("manual", false)):
		m.manual_timer = maxf(0.0, m.manual_timer - dt)
		activity = 1.0 if m.water_moved > 0.0 else 0.0
	if d.has("pump") and not bool(d.pump.get("manual", false)):
		activity = clampf(m.water_moved / maxf(float(d.pump.get("rate", 0.5)) * dt, 0.001), 0.0, 1.0) * eff
	# Emissions
	if d.has("heat") and activity > 0.0:
		var per_cell := float(d.heat) * activity * dt / m.cells().size()
		for c in m.cells():
			grid.add_heat(c.x, c.y, per_cell)
	if d.has("emit_gas") and activity > 0.0:
		var top := _exhaust_cell(grid, m, d)
		for sp in d.emit_gas:
			var k := UcGrid.SPECIES.find(sp)
			if k >= 0:
				var amt := float(d.emit_gas[sp]) * activity * dt
				grid.add_gas(top.x, top.y, k, amt)
				last[sp] = float(last.get(sp, 0.0)) + amt
	if d.has("light") and eff > 0.0:
		m.light = eff
	if d.has("noise"):
		m.noise = float(d.noise) * activity
	# Scrubber: needs a filter; turns sour/stale back into fresh air around it.
	if d.has("scrub"):
		var sd: Dictionary = d.scrub
		if d.has("filter") and m.filter_minutes <= 0.0:
			_refilter(m, d)
		if d.has("filter") and m.filter_minutes <= 0.0:
			r.append(&"needs_filter")
		elif d.has("waste") and m.waste >= float(d.waste.get("capacity", 6.0)):
			r.append(&"output_full")
		elif eff > 0.0:
			var radius := int(sd.get("radius", 2))
			var total := 0.0
			for y in range(m.cell.y - radius, m.cell.y + m.size.y + radius):
				for x in range(m.cell.x - radius, m.cell.x + m.size.x + radius):
					if not grid.is_open(x, y):
						continue
					total += grid.convert_gas(x, y, UcGrid.SOUR, UcGrid.FRESH, float(sd.get("sour", 0.0)) * eff * dt)
					total += grid.convert_gas(x, y, UcGrid.STALE, UcGrid.FRESH, float(sd.get("stale", 0.0)) * eff * dt)
			last["scrubbed"] += total
			if d.has("filter"):
				m.filter_minutes = maxf(0.0, m.filter_minutes - dt * eff)
			if d.has("waste"):
				m.waste += total * float(d.waste.get("per_unit", 2.0))
			if total < 0.0005:
				r.append(&"idle")
	# Fan: pushes gas from the cell behind to the cell in front.
	if d.has("fan") and eff > 0.0:
		var fd: Dictionary = d.fan
		var dir_arr: Array = fd.get("dir", [0, -1])
		var dir := Vector2i(int(dir_arr[0]), int(dir_arr[1]))
		var src_c := m.cell - dir
		var dst_c := m.cell + Vector2i(maxi(0, dir.x) * (m.size.x - 1), maxi(0, dir.y) * (m.size.y - 1)) + dir
		if grid.is_open(src_c.x, src_c.y) and grid.is_open(dst_c.x, dst_c.y):
			var frac := clampf(float(fd.get("rate", 0.2)) * eff * dt, 0.0, 0.6)
			var si := grid.idx(src_c.x, src_c.y)
			for k in UcGrid.SPECIES.size():
				var mv: float = grid.gas[k][si] * frac
				grid.gas[k][si] -= mv
				grid.add_gas(dst_c.x, dst_c.y, k, mv)
		else:
			r.append(&"blocked")
	# Sprinkler: turns delivered water into topsoil moisture across nearby columns.
	if d.has("sprinkle") and m.water_moved > 0.0:
		var sp: Dictionary = d.sprinkle
		var rad := int(sp.get("radius", 2))
		var cx := m.cell.x
		var per := m.water_moved / float(rad * 2 + 1)
		for x in range(cx - rad, cx + m.size.x + rad):
			var cur := grid.surface_moisture(x)
			var add := per * float(sp.get("efficiency", 2.5))
			if cur + add > 1.0:
				# Over-watering pools on the surface.
				grid.add_water(x, grid.ground_y - 1, (cur + add - 1.0) * 0.25)
			grid.set_surface_moisture(x, cur + add)
	# Drain: steady draw by the town's mains.
	if d.has("drain"):
		var want := float(d.drain.get("rate", 0.004)) * dt * eff
		var got := _take_cells_water(grid, m, want)
		m.water_moved += got
		last["town_served"] = clampf(got / maxf(want, 0.00001), 0.0, 1.0) if want > 0.0 else 1.0
		if want > 0.0 and got < want * 0.5:
			r.append(&"dry")
	# Heat exchanger: moves heat from the cell below the machine to the cell above it.
	if d.has("heat_move") and eff > 0.0:
		var hm: Dictionary = d.heat_move
		var below := Vector2i(m.cell.x, m.cell.y + m.size.y)
		var above := Vector2i(m.cell.x, m.cell.y - 1)
		if grid.in_bounds(below.x, below.y) and grid.in_bounds(above.x, above.y):
			var bi := grid.idx(below.x, below.y)
			var ai := grid.idx(above.x, above.y)
			var diff: float = grid.temp[bi] - grid.temp[ai]
			if diff > 0.0:
				var moved := minf(diff * 0.5, float(hm.get("rate", 4.0)) * eff * dt)
				grid.temp[bi] -= moved
				grid.add_heat(above.x, above.y, moved * 1.5)
	# Compost: sludge in the hopper slowly becomes fertiliser.
	if d.has("compost") and eff > 0.0:
		var cd: Dictionary = d.compost
		var input := String(cd.get("input", "sludge"))
		if int(m.fuel_items.get(input, 0)) > 0 and m.waste < float(cd.get("capacity", 6.0)):
			m.progress += dt * eff
			if m.progress >= float(cd.get("minutes", 240.0)):
				m.progress = 0.0
				m.fuel_items[input] = int(m.fuel_items[input]) - 1
				m.waste += 1.0
				events.append({"type": "produced", "id": m.id, "item": cd.get("output", "fertiliser")})
		else:
			r.append(&"idle")
	# Battery heat when charging.
	if d.has("battery") and m.power_in > 0.0:
		grid.add_heat(m.cell.x, m.cell.y, m.power_in * 0.02 * dt)


func base_eff_running(m: MachineState) -> float:
	return 1.0 if m.enabled and m.health > 0.0 else 0.0


func _pick_status(r: Array, eff: float) -> StringName:
	for s in STATUS_PRIORITY:
		if s == &"idle" or s == &"ok":
			break
		if r.has(s):
			return s
	if r.has(&"idle") or eff <= 0.02:
		return &"idle"
	return &"ok"


func _refuel(m: MachineState, d: Dictionary) -> void:
	var fuels: Dictionary = d.fuel.get("items", {})
	var keys := fuels.keys()
	keys.sort()
	for item in keys:
		if int(m.fuel_items.get(item, 0)) > 0:
			m.fuel_items[item] = int(m.fuel_items[item]) - 1
			m.fuel_minutes += float(fuels[item])
			return


func _refilter(m: MachineState, d: Dictionary) -> void:
	var item := String(d.filter.get("item", "filter_pad"))
	if int(m.fuel_items.get(item, 0)) > 0:
		m.fuel_items[item] = int(m.fuel_items[item]) - 1
		m.filter_minutes += float(d.filter.get("minutes", 480.0))


func _story_complete(m: MachineState, d: Dictionary) -> bool:
	for part in d.get("requires", {}):
		if int(m.story.get(part, 0)) < int(d.requires[part]):
			return false
	return true


func _exhaust_cell(grid: UcGrid, m: MachineState, d: Dictionary) -> Vector2i:
	if d.has("exhaust"):
		var e: Array = d.exhaust
		return m.cell + Vector2i(int(e[0]), int(e[1]))
	for c in m.cells():
		if grid.is_open(c.x, c.y):
			return c
	return m.cell


func _cells_water(grid: UcGrid, m: MachineState) -> float:
	var s := 0.0
	for c in m.cells():
		if grid.is_open(c.x, c.y):
			s += grid.water[grid.idx(c.x, c.y)]
	return s


func _take_cells_water(grid: UcGrid, m: MachineState, amount: float) -> float:
	var got := 0.0
	var cells := m.cells()
	cells.reverse()  # bottom cells first
	for c in cells:
		if got >= amount:
			break
		got += grid.take_water(c.x, c.y, amount - got)
	return got


func _water_level(grid: UcGrid, m: MachineState) -> float:
	var s := 0.0
	var n := 0
	for c in m.cells():
		if grid.is_open(c.x, c.y):
			s += minf(grid.water[grid.idx(c.x, c.y)], 1.0)
			n += 1
	return s / n if n > 0 else 0.0


func _avg_temp(grid: UcGrid, m: MachineState) -> float:
	var s := 0.0
	var cells := m.cells()
	for c in cells:
		s += grid.temp[grid.idx(c.x, c.y)] if grid.in_bounds(c.x, c.y) else 18.0
	return s / cells.size()


func _avg_fresh(grid: UcGrid, m: MachineState) -> float:
	var s := 0.0
	var n := 0
	for c in m.cells():
		if grid.is_open(c.x, c.y):
			s += grid.gas_fraction(c.x, c.y, UcGrid.FRESH)
			n += 1
	return s / n if n > 0 else 1.0


func _avg_flow(grid: UcGrid, m: MachineState) -> float:
	var s := 0.0
	for c in m.cells():
		if grid.in_bounds(c.x, c.y):
			s += grid.flow[grid.idx(c.x, c.y)]
	return s


func _leak_into(grid: UcGrid, c: Vector2i, amount: float) -> void:
	if grid.is_open(c.x, c.y):
		grid.add_water(c.x, c.y, amount)
		return
	# Leak inside solid ground: wets the soil, the rest escapes to the nearest open cell.
	for d in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1)]:
		if grid.is_open(c.x + d.x, c.y + d.y):
			grid.add_water(c.x + d.x, c.y + d.y, amount)
			return
	grid.add_water(c.x, c.y, amount)


# --- Serialisation ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var ms := []
	var ids := machines.keys()
	ids.sort()
	for id in ids:
		ms.append(machines[id].to_dict())
	return {"next_id": next_id, "machines": ms, "pipes": _layer_to_array(pipes),
		"wires": _layer_to_array(wires), "rng": str(rng.state)}


func load_dict(d: Dictionary) -> void:
	machines.clear()
	occupancy.clear()
	pipes.clear()
	wires.clear()
	for md in d.get("machines", []):
		var m := MachineState.from_dict(md)
		if not defs.has(m.def_id):
			push_warning("machine_world: dropping unknown machine '%s'" % m.def_id)
			continue
		m.size = _size_of(defs[m.def_id])
		machines[m.id] = m
		for c in m.cells():
			occupancy[c] = m.id
	next_id = maxi(int(d.get("next_id", 1)), _max_id() + 1)
	for p in d.get("pipes", []):
		pipes[Vector2i(int(p[0]), int(p[1]))] = clampf(float(p[2]), 0.0, 1.0)
	for p in d.get("wires", []):
		wires[Vector2i(int(p[0]), int(p[1]))] = clampf(float(p[2]), 0.0, 1.0)
	if d.has("rng"):
		rng.state = String(str(d.rng)).to_int()
	_dirty = true


func _max_id() -> int:
	var mx := 0
	for id in machines:
		mx = maxi(mx, int(id))
	return mx


static func _layer_to_array(layer: Dictionary) -> Array:
	var out := []
	var keys := layer.keys()
	keys.sort()
	for c in keys:
		out.append([c.x, c.y, layer[c]])
	return out
