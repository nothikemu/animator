class_name UcGrid
extends RefCounted
## The Undercroft cross-section: a 2D slice of cells (x across, y downward) holding
## material, gas mixture, water, temperature and soil moisture.
##
## Rules are deliberately few and legible:
##  * Gas: species diffuse; a heavier mixture above a lighter one swaps (sour/stale sink,
##    damp rises, hot air rises); the top row breathes with the open cavern.
##  * Water: compressible-mass cellular automaton (falls, spreads, rises only under pressure),
##    and it pushes gas out of the cells it fills.
##  * Heat: conduction by material; geothermal rock is a fixed hot source.
##  * Moisture: soil soaks water from neighbouring pools, spreads slowly, evaporates at the surface.
## Every exchange is pairwise, so species mass and water mass are conserved except at
## explicit sources/sinks. Tests rely on that.

enum Mat { AIR, TOPSOIL, SOIL, CLAY, ROCK, BRICK, STONE, METAL, INSULATION, BEDROCK, EMBER, SEAL }

const MAT_NAMES := ["air", "topsoil", "soil", "clay", "rock", "brick", "stone", "metal",
	"insulation", "bedrock", "ember", "seal"]
## Conductivity per material (fraction of temperature difference exchanged per second).
const CONDUCT := [0.10, 0.12, 0.10, 0.08, 0.16, 0.10, 0.18, 0.45, 0.005, 0.12, 0.25, 0.10]
## Heat capacity multiplier per material (water handled separately).
const CAPACITY := [1.0, 2.0, 2.2, 2.5, 3.0, 2.5, 3.0, 1.5, 2.0, 4.0, 6.0, 3.0]
## Moisture capacity per material (0 = cannot hold moisture).
const MOIST_CAP := [0.0, 1.0, 0.8, 0.55, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

const SPECIES := ["fresh", "stale", "sour", "damp"]
const FRESH := 0
const STALE := 1
const SOUR := 2
const DAMP := 3
## Molar weight-ish values used for buoyancy. Fresh air = 1.
const WEIGHT := [1.0, 1.45, 2.1, 0.55]

# Water CA constants (W-Shadow).
const MAX_MASS := 1.0
const MAX_COMPRESS := 0.02
const MIN_MASS := 0.0005
const MIN_FLOW := 0.005
const MAX_SPEED := 1.0

const GAS_DIFFUSE := 0.12      ## per step fraction toward neighbour
const VERTICAL_DIFFUSE := 0.5  ## vertical mixing is weaker than horizontal spreading
const SETTLE := 0.16           ## species drift rate (scaled by how heavy/light they are)
const BUOYANCY := 3.0          ## convective swap strength per unit density difference
const AMBIENT_RATE := 0.04     ## top row exchange with the cavern per step
const T_MIN := -20.0
const T_MAX := 400.0

var w: int
var h: int
var ground_y: int              ## row index of the surface (topsoil) layer
var mat: PackedByteArray
var gas: Array[PackedFloat32Array] = []
var water: PackedFloat32Array
var temp: PackedFloat32Array
var moisture: PackedFloat32Array
var flow: PackedFloat32Array   ## water moved through a cell during the last step
var springs: Dictionary = {}   ## Vector2i -> rate (water added per step when not full)
var vents: Dictionary = {}     ## Vector2i -> {species_index: rate}
var hot_cells: Dictionary = {} ## Vector2i -> target temperature (geothermal)

var ambient_gas := PackedFloat32Array([1.0, 0.0, 0.0, 0.0])
var ambient_temp := 18.0
var vent_scale := 1.0          ## the Breath scales vents (exhale > 1, inhale < 1)

# Scratch buffers reused every step to avoid per-frame allocation.
var _new_water: PackedFloat32Array
var _gas_delta: Array[PackedFloat32Array] = []
var _temp_delta: PackedFloat32Array
var _open: PackedByteArray             ## open & not flooded, rebuilt each gas step
var _kc: PackedFloat32Array            ## per-cell conductivity, rebuilt each heat step
var _cp: PackedFloat32Array            ## per-cell heat capacity


func _init(width: int = 1, height: int = 1, ground_row: int = 0) -> void:
	w = width
	h = height
	ground_y = ground_row
	var n := w * h
	mat = PackedByteArray()
	mat.resize(n)
	water = _zeros(n)
	temp = _filled(n, 18.0)
	moisture = _zeros(n)
	flow = _zeros(n)
	gas.clear()
	_gas_delta.clear()
	for _k in SPECIES.size():
		gas.append(_zeros(n))
		_gas_delta.append(_zeros(n))
	_new_water = _zeros(n)
	_temp_delta = _zeros(n)
	_open = PackedByteArray()
	_open.resize(n)
	_kc = _zeros(n)
	_cp = _zeros(n)


static func _zeros(n: int) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(n)
	a.fill(0.0)
	return a


static func _filled(n: int, v: float) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(n)
	a.fill(v)
	return a


# --- Cell access ------------------------------------------------------------------

func idx(x: int, y: int) -> int:
	return y * w + x


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h


func is_open(x: int, y: int) -> bool:
	return in_bounds(x, y) and mat[y * w + x] == Mat.AIR


func get_mat(x: int, y: int) -> int:
	return mat[y * w + x] if in_bounds(x, y) else Mat.BEDROCK


func set_mat(x: int, y: int, m: int) -> void:
	if not in_bounds(x, y):
		return
	var i := y * w + x
	var was_open := mat[i] == Mat.AIR
	mat[i] = m
	if m == Mat.AIR and not was_open:
		# A newly opened cell starts with whatever the cavern air holds, scaled down
		# (it was sealed), so a tremor-opened pocket is not instantly full of fresh air.
		for k in SPECIES.size():
			gas[k][i] = 0.0
		gas[FRESH][i] = 0.6
		moisture[i] = 0.0
	elif m != Mat.AIR and was_open:
		# Closing a cell pushes its contents up/out so mass is conserved where possible.
		_evict_cell(x, y)


func _evict_cell(x: int, y: int) -> void:
	var i := y * w + x
	var target := Vector2i(-1, -1)
	for d in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]:
		if is_open(x + d.x, y + d.y):
			target = Vector2i(x + d.x, y + d.y)
			break
	if target.x >= 0:
		var j := target.y * w + target.x
		for k in SPECIES.size():
			gas[k][j] += gas[k][i]
		water[j] += water[i]
	for k in SPECIES.size():
		gas[k][i] = 0.0
	water[i] = 0.0


func gas_total(i: int) -> float:
	return gas[0][i] + gas[1][i] + gas[2][i] + gas[3][i]


## Fraction of a species in the cell's gas mixture (0 for empty / solid cells).
func gas_fraction(x: int, y: int, k: int) -> float:
	if not is_open(x, y):
		return 0.0
	var i := y * w + x
	var t := gas_total(i)
	return gas[k][i] / t if t > 0.0001 else 0.0


func fill_open_with_ambient() -> void:
	for i in w * h:
		if mat[i] == Mat.AIR:
			for k in SPECIES.size():
				gas[k][i] = ambient_gas[k]


func add_gas(x: int, y: int, k: int, amount: float) -> void:
	if not is_open(x, y):
		return
	var i := y * w + x
	gas[k][i] = maxf(0.0, gas[k][i] + amount)


## Removes up to `amount` of species k; returns how much was actually removed.
func take_gas(x: int, y: int, k: int, amount: float) -> float:
	if not is_open(x, y):
		return 0.0
	var i := y * w + x
	var got := minf(gas[k][i], maxf(0.0, amount))
	gas[k][i] -= got
	return got


## Converts `amount` of species `from_k` into species `to_k` (scrubbers, ferns): keeps pressure stable.
func convert_gas(x: int, y: int, from_k: int, to_k: int, amount: float) -> float:
	var got := take_gas(x, y, from_k, amount)
	if got > 0.0:
		add_gas(x, y, to_k, got)
	return got


func add_water(x: int, y: int, amount: float) -> void:
	if is_open(x, y):
		water[y * w + x] += maxf(0.0, amount)
	elif in_bounds(x, y) and MOIST_CAP[mat[y * w + x]] > 0.0:
		var i := y * w + x
		moisture[i] = minf(MOIST_CAP[mat[i]], moisture[i] + amount)


func take_water(x: int, y: int, amount: float) -> float:
	if not is_open(x, y):
		return 0.0
	var i := y * w + x
	var got := minf(water[i], maxf(0.0, amount))
	water[i] -= got
	return got


func add_heat(x: int, y: int, degrees: float) -> void:
	if in_bounds(x, y):
		var i := y * w + x
		temp[i] = clampf(temp[i] + degrees / CAPACITY[mat[i]], T_MIN, T_MAX)


# --- Aggregates ----------------------------------------------------------------------

func total_species(k: int) -> float:
	var s := 0.0
	for i in w * h:
		s += gas[k][i]
	return s


func total_water() -> float:
	var s := 0.0
	for i in w * h:
		s += water[i]
	return s


## Air conditions just above the surface in column x (the settlement's air).
func surface_air(x: int) -> Dictionary:
	x = clampi(x, 0, w - 1)
	var out := {"fresh": 0.0, "stale": 0.0, "sour": 0.0, "damp": 0.0, "temp": ambient_temp}
	var n := 0
	var t := 0.0
	for y in [ground_y - 1, ground_y - 2]:
		if is_open(x, y):
			for k in SPECIES.size():
				out[SPECIES[k]] += gas_fraction(x, y, k)
			t += temp[y * w + x]
			n += 1
	if n > 0:
		for k in SPECIES.size():
			out[SPECIES[k]] /= n
		out["temp"] = t / n
	return out


func surface_moisture(x: int) -> float:
	x = clampi(x, 0, w - 1)
	var i := ground_y * w + x
	var cap: float = MOIST_CAP[mat[i]]
	return moisture[i] / cap if cap > 0.0 else 0.0


func set_surface_moisture(x: int, value: float) -> void:
	x = clampi(x, 0, w - 1)
	var i := ground_y * w + x
	moisture[i] = clampf(value, 0.0, MOIST_CAP[mat[i]])


# --- Simulation step --------------------------------------------------------------------

## One field step. `dt` is in sim-seconds (normally 0.25).
func step(dt: float) -> void:
	_step_water()
	_displace_gas_by_water()
	_step_gas(dt)
	_step_heat(dt)
	_step_moisture(dt)
	_apply_sources(dt)


func _step_water() -> void:
	var n := w * h
	for i in n:
		_new_water[i] = water[i]
		flow[i] = 0.0
	for y in h:
		for x in w:
			var i := y * w + x
			if mat[i] != Mat.AIR:
				continue
			var remaining := water[i]
			if remaining <= MIN_MASS:
				continue
			var f := 0.0
			# Down
			if y + 1 < h and mat[i + w] == Mat.AIR:
				f = _stable_state(remaining + water[i + w]) - water[i + w]
				if f > MIN_FLOW:
					f *= 0.5
				f = clampf(f, 0.0, minf(MAX_SPEED, remaining))
				_new_water[i] -= f
				_new_water[i + w] += f
				flow[i] += f
				flow[i + w] += f
				remaining -= f
				if remaining <= 0.0:
					continue
			# Left
			if x > 0 and mat[i - 1] == Mat.AIR:
				f = (water[i] - water[i - 1]) / 4.0
				if f > MIN_FLOW:
					f *= 0.5
				f = clampf(f, 0.0, remaining)
				_new_water[i] -= f
				_new_water[i - 1] += f
				flow[i] += f
				remaining -= f
				if remaining <= 0.0:
					continue
			# Right
			if x + 1 < w and mat[i + 1] == Mat.AIR:
				f = (water[i] - water[i + 1]) / 4.0
				if f > MIN_FLOW:
					f *= 0.5
				f = clampf(f, 0.0, remaining)
				_new_water[i] -= f
				_new_water[i + 1] += f
				flow[i] += f
				remaining -= f
				if remaining <= 0.0:
					continue
			# Up (only when compressed)
			if y > 0 and mat[i - w] == Mat.AIR:
				f = remaining - _stable_state(remaining + water[i - w])
				if f > MIN_FLOW:
					f *= 0.5
				f = clampf(f, 0.0, minf(MAX_SPEED, remaining))
				_new_water[i] -= f
				_new_water[i - w] += f
				flow[i] += f
				remaining -= f
	for i in n:
		var v := _new_water[i]
		water[i] = v if v > MIN_MASS * 0.1 else 0.0


static func _stable_state(total: float) -> float:
	if total <= 1.0:
		return 1.0
	elif total < 2.0 * MAX_MASS + MAX_COMPRESS:
		return (MAX_MASS * MAX_MASS + total * MAX_COMPRESS) / (MAX_MASS + MAX_COMPRESS)
	return (total + MAX_COMPRESS) / 2.0


## Water occupies volume: gas in a cell may not exceed the space water leaves free.
## Processed bottom-up so displaced gas can bubble up a whole column in one step.
func _displace_gas_by_water() -> void:
	for y in range(h - 1, -1, -1):
		for x in w:
			var i := y * w + x
			if mat[i] != Mat.AIR:
				continue
			var wv := water[i]
			if wv < 0.05:
				continue
			var cap := maxf(0.0, 1.0 - minf(wv, 1.0))
			var total := gas_total(i)
			var excess := total - cap - 0.02
			if excess <= 0.0 or total <= 0.0:
				continue
			var target := -1
			if y > 0 and mat[i - w] == Mat.AIR:
				target = i - w
			elif x > 0 and mat[i - 1] == Mat.AIR and water[i - 1] < wv:
				target = i - 1
			elif x + 1 < w and mat[i + 1] == Mat.AIR and water[i + 1] < wv:
				target = i + 1
			if target < 0:
				continue
			var frac := excess / total
			for k in SPECIES.size():
				var move := gas[k][i] * frac
				gas[k][i] -= move
				gas[k][target] += move


func _step_gas(dt: float) -> void:
	# Hot path. Species arrays are hoisted into typed locals (packed arrays are shared by
	# reference) and the four species are unrolled: same maths, far less dispatch.
	var n := w * h
	var g0: PackedFloat32Array = gas[FRESH]
	var g1: PackedFloat32Array = gas[STALE]
	var g2: PackedFloat32Array = gas[SOUR]
	var g3: PackedFloat32Array = gas[DAMP]
	var d0: PackedFloat32Array = _gas_delta[0]
	var d1: PackedFloat32Array = _gas_delta[1]
	var d2: PackedFloat32Array = _gas_delta[2]
	var d3: PackedFloat32Array = _gas_delta[3]
	d0.fill(0.0)
	d1.fill(0.0)
	d2.fill(0.0)
	d3.fill(0.0)
	var open := _open
	for i in n:
		open[i] = 1 if mat[i] == Mat.AIR and water[i] <= 0.92 else 0
	var d := minf(GAS_DIFFUSE * clampf(dt / 0.25, 0.0, 1.6), 0.2)
	var dv := d * VERTICAL_DIFFUSE
	# Pairwise diffusion (right and down neighbours), double-buffered.
	for y in h:
		var row := y * w
		for x in w:
			var i := row + x
			if open[i] == 0:
				continue
			if x + 1 < w and open[i + 1] == 1:
				var j := i + 1
				var t := (g0[i] - g0[j]) * d
				d0[i] -= t
				d0[j] += t
				t = (g1[i] - g1[j]) * d
				d1[i] -= t
				d1[j] += t
				t = (g2[i] - g2[j]) * d
				d2[i] -= t
				d2[j] += t
				t = (g3[i] - g3[j]) * d
				d3[i] -= t
				d3[j] += t
			if y + 1 < h and open[i + w] == 1:
				var j := i + w
				var t := (g0[i] - g0[j]) * dv
				d0[i] -= t
				d0[j] += t
				t = (g1[i] - g1[j]) * dv
				d1[i] -= t
				d1[j] += t
				t = (g2[i] - g2[j]) * dv
				d2[i] -= t
				d2[j] += t
				t = (g3[i] - g3[j]) * dv
				d3[i] -= t
				d3[j] += t
	for i in n:
		g0[i] = maxf(0.0, g0[i] + d0[i])
		g1[i] = maxf(0.0, g1[i] + d1[i])
		g2[i] = maxf(0.0, g2[i] + d2[i])
		g3[i] = maxf(0.0, g3[i] + d3[i])
	# Settling: each heavy species drifts down and each light species drifts up, trading
	# places with fresh air so pressure is kept. This is what makes gases pool and layer.
	var sf := SETTLE * clampf(dt / 0.25, 0.0, 1.6)
	var s_stale := sf * (WEIGHT[STALE] - 1.0) / WEIGHT[STALE]
	var s_sour := sf * (WEIGHT[SOUR] - 1.0) / WEIGHT[SOUR]
	var s_damp := sf * (1.0 - WEIGHT[DAMP])
	for y in h - 1:
		var row := y * w
		for x in w:
			var u := row + x
			var l := u + w
			if open[u] == 0 or open[l] == 0:
				continue
			# Convection wins over settling when the lower cell is clearly hotter.
			var calm := clampf(1.0 - (temp[l] - temp[u]) / 12.0, 0.0, 1.0)
			var mv := minf(g1[u] * s_stale * calm, g0[l])
			if mv > 0.0:
				g1[u] -= mv
				g1[l] += mv
				g0[l] -= mv
				g0[u] += mv
			mv = minf(g2[u] * s_sour * calm, g0[l])
			if mv > 0.0:
				g2[u] -= mv
				g2[l] += mv
				g0[l] -= mv
				g0[u] += mv
			var up := minf(g3[l] * s_damp, g0[u])
			if up > 0.0:
				g3[l] -= up
				g3[u] += up
				g0[u] -= up
				g0[l] += up
	# Convection: a denser (colder/heavier) mixture above a lighter one swaps a share.
	var b := BUOYANCY * clampf(dt / 0.25, 0.0, 1.6)
	var w0: float = WEIGHT[FRESH]
	var w1: float = WEIGHT[STALE]
	var w2: float = WEIGHT[SOUR]
	var w3: float = WEIGHT[DAMP]
	for y in h - 1:
		var row := y * w
		for x in w:
			var u := row + x
			var l := u + w
			if open[u] == 0 or open[l] == 0:
				continue
			var tu := g0[u] + g1[u] + g2[u] + g3[u]
			var tl := g0[l] + g1[l] + g2[l] + g3[l]
			if tu < 0.001 or tl < 0.001:
				continue
			# Hot gas is lighter (ideal-gas style scaling around 18 °C).
			var rho_u := ((g0[u] * w0 + g1[u] * w1 + g2[u] * w2 + g3[u] * w3) / tu) * (291.0 / maxf(temp[u] + 273.0, 100.0))
			var rho_l := ((g0[l] * w0 + g1[l] * w1 + g2[l] * w2 + g3[l] * w3) / tl) * (291.0 / maxf(temp[l] + 273.0, 100.0))
			var diff := rho_u - rho_l
			if diff <= 0.002:
				continue
			var share := clampf(diff * b, 0.0, 0.3)
			var amount := share * minf(tu, tl)
			var fu := amount / tu
			var fl := amount / tl
			var dn := g0[u] * fu
			var upv := g0[l] * fl
			g0[u] += upv - dn
			g0[l] += dn - upv
			dn = g1[u] * fu
			upv = g1[l] * fl
			g1[u] += upv - dn
			g1[l] += dn - upv
			dn = g2[u] * fu
			upv = g2[l] * fl
			g2[u] += upv - dn
			g2[l] += dn - upv
			dn = g3[u] * fu
			upv = g3[l] * fl
			g3[u] += upv - dn
			g3[l] += dn - upv
			# Heat travels with the moving air: this is what makes plumes rise.
			var dT := (temp[l] - temp[u]) * share
			temp[u] += dT
			temp[l] -= dT
	# Top row breathes with the open cavern.
	var a0: float = ambient_gas[0]
	var a1: float = ambient_gas[1]
	var a2: float = ambient_gas[2]
	var a3: float = ambient_gas[3]
	for x in w:
		if mat[x] != Mat.AIR:
			continue
		g0[x] += (a0 - g0[x]) * AMBIENT_RATE
		g1[x] += (a1 - g1[x]) * AMBIENT_RATE
		g2[x] += (a2 - g2[x]) * AMBIENT_RATE
		g3[x] += (a3 - g3[x]) * AMBIENT_RATE


func _density(i: int, total: float) -> float:
	var m := 0.0
	for k in SPECIES.size():
		m += gas[k][i] * WEIGHT[k]
	# Hot gas is lighter (ideal-gas style scaling around 18 °C).
	var kelvin := maxf(temp[i] + 273.0, 100.0)
	return (m / total) * (291.0 / kelvin)


func _step_heat(dt: float) -> void:
	var n := w * h
	var td := _temp_delta
	td.fill(0.0)
	var s := clampf(dt, 0.0, 2.0)
	# Per-cell conductivity and heat capacity, once per step.
	var kc := _kc
	var cp := _cp
	for i in n:
		var m := mat[i]
		if m == Mat.AIR:
			kc[i] = 0.35 if water[i] > 0.3 else CONDUCT[0]
			cp[i] = 1.0 + water[i] * 3.0
		else:
			kc[i] = CONDUCT[m]
			cp[i] = CAPACITY[m]
	var half := 0.5 * s
	for y in h:
		var row := y * w
		for x in w:
			var i := row + x
			var ka := kc[i]
			var ti := temp[i]
			var ci := cp[i]
			if x + 1 < w:
				var j := i + 1
				var dT := (temp[j] - ti) * minf(ka, kc[j]) * half
				td[i] += dT / ci
				td[j] -= dT / cp[j]
			if y + 1 < h:
				var j := i + w
				var dT := (temp[j] - ti) * minf(ka, kc[j]) * half
				td[i] += dT / ci
				td[j] -= dT / cp[j]
	for i in n:
		temp[i] = clampf(temp[i] + td[i], T_MIN, T_MAX)
	# Cavern air at the top stays near ambient.
	for x in w:
		if mat[x] == Mat.AIR:
			temp[x] += (ambient_temp - temp[x]) * 0.08 * s
	# Geothermal sources.
	for c in hot_cells:
		var i: int = c.y * w + c.x
		temp[i] += (float(hot_cells[c]) - temp[i]) * 0.2 * s


func _cap(i: int) -> float:
	if mat[i] == Mat.AIR:
		return 1.0 + water[i] * 3.0
	return CAPACITY[mat[i]]


func _step_moisture(dt: float) -> void:
	var s := clampf(dt, 0.0, 2.0)
	for y in h:
		for x in w:
			var i := y * w + x
			var cap: float = MOIST_CAP[mat[i]]
			if cap <= 0.0:
				continue
			# Soak from adjacent standing water.
			for j in [i - w, i - 1, i + 1, i + w]:
				if j < 0 or j >= w * h:
					continue
				if (j == i - 1 and x == 0) or (j == i + 1 and x == w - 1):
					continue
				if mat[j] == Mat.AIR and water[j] > MIN_MASS:
					var room := cap - moisture[i]
					if room <= 0.0:
						break
					var soak := minf(minf(water[j], room), 0.02 * s)
					water[j] -= soak
					moisture[i] += soak
			# Slow diffusion to soil neighbours (right and down).
			if x + 1 < w and MOIST_CAP[mat[i + 1]] > 0.0:
				_moist_exchange(i, i + 1, 0.02 * s)
			if y + 1 < h and MOIST_CAP[mat[i + w]] > 0.0:
				_moist_exchange(i, i + w, 0.015 * s)
	# Surface evaporation, faster when warm.
	if ground_y >= h:
		return
	for x in w:
		var i := ground_y * w + x
		if MOIST_CAP[mat[i]] > 0.0 and is_open(x, ground_y - 1):
			var t := temp[i]
			var rate := 0.00025 * s * clampf((t + 5.0) / 25.0, 0.2, 3.0)
			moisture[i] = maxf(0.0, moisture[i] - rate)


func _moist_exchange(a: int, b: int, rate: float) -> void:
	var ca: float = MOIST_CAP[mat[a]]
	var cb: float = MOIST_CAP[mat[b]]
	var ra := moisture[a] / ca
	var rb := moisture[b] / cb
	var t := (ra - rb) * rate * minf(ca, cb)
	moisture[a] = clampf(moisture[a] - t, 0.0, ca)
	moisture[b] = clampf(moisture[b] + t, 0.0, cb)


func _apply_sources(dt: float) -> void:
	var s := clampf(dt / 0.25, 0.0, 4.0)
	for c in springs:
		var i: int = c.y * w + c.x
		if mat[i] == Mat.AIR and water[i] < MAX_MASS:
			water[i] += float(springs[c]) * s
	for c in vents:
		var spec: Dictionary = vents[c]
		for k in spec:
			add_gas(c.x, c.y, int(k), float(spec[k]) * s * vent_scale)


# --- Serialisation -------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var g := []
	for k in SPECIES.size():
		g.append(Marshalls.raw_to_base64(gas[k].to_byte_array()))
	var sp := []
	for c in springs:
		sp.append([c.x, c.y, springs[c]])
	var vt := []
	for c in vents:
		vt.append([c.x, c.y, vents[c]])
	var hc := []
	for c in hot_cells:
		hc.append([c.x, c.y, hot_cells[c]])
	return {
		"w": w, "h": h, "ground_y": ground_y,
		"mat": Marshalls.raw_to_base64(mat),
		"gas": g,
		"water": Marshalls.raw_to_base64(water.to_byte_array()),
		"temp": Marshalls.raw_to_base64(temp.to_byte_array()),
		"moisture": Marshalls.raw_to_base64(moisture.to_byte_array()),
		"springs": sp, "vents": vt, "hot": hc,
		"ambient_temp": ambient_temp,
	}


static func from_dict(d: Dictionary) -> UcGrid:
	var g := UcGrid.new(int(d.get("w", 1)), int(d.get("h", 1)), int(d.get("ground_y", 0)))
	var n := g.w * g.h
	var m := Marshalls.base64_to_raw(String(d.get("mat", "")))
	if m.size() == n:
		g.mat = m
	var gl: Array = d.get("gas", [])
	for k in mini(gl.size(), SPECIES.size()):
		var arr := Marshalls.base64_to_raw(String(gl[k])).to_float32_array()
		if arr.size() == n:
			g.gas[k] = _sanitize(arr, 0.0, 50.0)
	var wa := Marshalls.base64_to_raw(String(d.get("water", ""))).to_float32_array()
	if wa.size() == n:
		g.water = _sanitize(wa, 0.0, 10.0)
	var te := Marshalls.base64_to_raw(String(d.get("temp", ""))).to_float32_array()
	if te.size() == n:
		g.temp = _sanitize(te, T_MIN, T_MAX)
	var mo := Marshalls.base64_to_raw(String(d.get("moisture", ""))).to_float32_array()
	if mo.size() == n:
		g.moisture = _sanitize(mo, 0.0, 1.0)
	for s in d.get("springs", []):
		g.springs[Vector2i(int(s[0]), int(s[1]))] = float(s[2])
	for v in d.get("vents", []):
		var spec := {}
		for k in (v[2] as Dictionary):
			spec[int(k)] = float(v[2][k])
		g.vents[Vector2i(int(v[0]), int(v[1]))] = spec
	for hcell in d.get("hot", []):
		g.hot_cells[Vector2i(int(hcell[0]), int(hcell[1]))] = float(hcell[2])
	g.ambient_temp = float(d.get("ambient_temp", 18.0))
	return g


## Clamps NaN/inf/out-of-range values that could come from a damaged save.
static func _sanitize(a: PackedFloat32Array, lo: float, hi: float) -> PackedFloat32Array:
	for i in a.size():
		var v := a[i]
		if is_nan(v) or is_inf(v):
			a[i] = lo
		else:
			a[i] = clampf(v, lo, hi)
	return a
