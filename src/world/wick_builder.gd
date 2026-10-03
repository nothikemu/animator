class_name WickBuilder
extends RefCounted
## Builds the Undercroft simulation (grid + machines) from data/undercroft_wick.json.


static func build_grid(def: Dictionary) -> UcGrid:
	var w := int(def.get("w", 48))
	var h := int(def.get("h", 24))
	var grid := UcGrid.new(w, h, int(def.get("ground_y", 10)))
	var legend: Dictionary = def.get("legend", {})
	var rows: Array = def.get("rows", [])
	for y in mini(h, rows.size()):
		var row := String(rows[y])
		for x in mini(w, row.length()):
			var name := String(legend.get(row[x], "rock"))
			var m := UcGrid.MAT_NAMES.find(name)
			grid.mat[y * w + x] = m if m >= 0 else UcGrid.Mat.ROCK
	grid.fill_open_with_ambient()
	# Underground temperature gradient: cooler near the surface, warmer below.
	for y in h:
		for x in w:
			grid.temp[y * w + x] = 18.0 + maxf(0.0, float(y - grid.ground_y)) * 0.6
	for c in def.get("water", []):
		grid.water[int(c[1]) * w + int(c[0])] = float(c[2])
	for s in def.get("springs", []):
		grid.springs[Vector2i(int(s[0]), int(s[1]))] = float(s[2])
	for v in def.get("vents", []):
		var spec := {}
		for k in (v[2] as Dictionary):
			spec[int(k)] = float(v[2][k])
		grid.vents[Vector2i(int(v[0]), int(v[1]))] = spec
	for hc in def.get("hot", []):
		var c := Vector2i(int(hc[0]), int(hc[1]))
		grid.hot_cells[c] = float(hc[2])
		grid.temp[c.y * w + c.x] = float(hc[2])
	for p in def.get("pockets", []):
		var r: Array = p.cells
		var gas: Dictionary = p.gas
		for y in range(int(r[1]), int(r[3]) + 1):
			for x in range(int(r[0]), int(r[2]) + 1):
				if grid.is_open(x, y):
					for k in UcGrid.SPECIES.size():
						grid.gas[k][y * w + x] = float(gas.get(str(k), 0.0))
	# Topsoil starts lightly damp; soil near the cistern and Sink is wetter.
	for x in w:
		var i := grid.ground_y * w + x
		if UcGrid.MOIST_CAP[grid.mat[i]] > 0.0:
			grid.moisture[i] = 0.25
	return grid


static func build_machines(def: Dictionary, defs: Dictionary, seed_value: int) -> MachineWorld:
	var mw := MachineWorld.new(defs, hash([seed_value, "machines"]))
	for p in def.get("pipes", []):
		mw.set_conduit("pipe", Vector2i(int(p[0]), int(p[1])), float(p[2]))
	for p in def.get("wires", []):
		mw.set_conduit("wire", Vector2i(int(p[0]), int(p[1])), float(p[2]))
	for m in def.get("machines", []):
		if not defs.has(String(m.def)):
			push_error("undercroft: unknown machine '%s'" % m.def)
			continue
		mw.add_machine(String(m.def), Vector2i(int(m.x), int(m.y)), bool(m.get("fixed", false)))
	return mw


## Drains drains: natural cracks that carry water away into the deeper Deep.
static func apply_drains(grid: UcGrid, drains: Array, steps: float) -> void:
	for d in drains:
		var x := int(d[0])
		var y := int(d[1])
		if grid.is_open(x, y):
			grid.take_water(x, y, float(d[2]) * steps)
