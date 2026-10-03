class_name CropLogic
extends RefCounted
## Pure crop rules. A crop's growth rate is the product of per-condition factors; each factor
## is 1 inside the crop's comfortable range and falls off linearly outside it. Health drains
## while any factor is badly wrong, which is what makes a crop an *instrument*: its state
## reads out the air, heat, water and light you engineered.

const CONDITIONS := ["light", "moisture", "temp", "sour"]
## How far outside a range (in range units) until the factor hits zero.
const MARGIN := {"light": 0.35, "moisture": 0.3, "temp": 8.0, "sour": 0.25}
const MINUTES_PER_DAY := 1440.0


## Per-condition factors for environment `env` = {light, moisture, temp, sour}.
static func factors(def: Dictionary, env: Dictionary) -> Dictionary:
	var ranges: Dictionary = def.get("ranges", {})
	var out := {}
	for c in CONDITIONS:
		if not ranges.has(c):
			out[c] = 1.0
			continue
		var r: Array = ranges[c]
		var lo := float(r[0])
		var hi := float(r[1])
		var v := float(env.get(c, 0.0))
		var m: float = MARGIN[c]
		var f := 1.0
		if v < lo:
			f = 1.0 - (lo - v) / m
		elif v > hi:
			f = 1.0 - (v - hi) / m
		out[c] = clampf(f, 0.0, 1.0)
	return out


static func growth_rate(def: Dictionary, f: Dictionary) -> float:
	var rate := 1.0
	for c in f:
		rate *= f[c]
	return rate


## Worst condition and how it is wrong, for player-facing inspection ("too cold").
static func worst(def: Dictionary, env: Dictionary, f: Dictionary) -> Dictionary:
	var worst_c := ""
	var worst_v := 1.01
	for c in f:
		if f[c] < worst_v:
			worst_v = f[c]
			worst_c = c
	if worst_c.is_empty() or worst_v >= 0.999:
		return {"cond": "", "factor": 1.0, "dir": ""}
	var r: Array = def.ranges[worst_c]
	var v := float(env.get(worst_c, 0.0))
	var dir := "low" if v < float(r[0]) else "high"
	return {"cond": worst_c, "factor": worst_v, "dir": dir}


## Advances one plot by `minutes`. Mutates and returns the plot dictionary.
## plot = {crop, growth (0..1), health (0..1), water (0..1), dead, pollinated}
static func advance(plot: Dictionary, def: Dictionary, env: Dictionary, minutes: float) -> Dictionary:
	if not plot.has("dead"):
		plot["dead"] = false
	if plot.get("crop", "") == "" or plot.get("dead", false):
		return plot
	var f := factors(def, env)
	var rate := growth_rate(def, f)
	var days := maxf(0.25, float(def.get("days", 3.0)))
	var g := float(plot.get("growth", 0.0))
	if g < 1.0:
		g = minf(1.0, g + rate * minutes / (days * MINUTES_PER_DAY))
		if g > 0.9995:
			g = 1.0
	plot["growth"] = g
	var health := float(plot.get("health", 1.0))
	var min_f := 1.0
	for c in f:
		min_f = minf(min_f, f[c])
	if min_f < 0.25:
		health -= (0.25 - min_f) * minutes / 240.0
	elif min_f > 0.6:
		health += 0.15 * minutes / 1440.0
	plot["health"] = clampf(health, 0.0, 1.0)
	if plot["health"] <= 0.0:
		plot["dead"] = true
	# The plot's own water drains with time and warmth; crops drink.
	var drink := float(def.get("thirst", 0.6)) * minutes / MINUTES_PER_DAY
	var heat := clampf((float(env.get("temp", 18.0)) - 10.0) / 20.0, 0.2, 2.0)
	plot["water"] = clampf(float(plot.get("water", 0.0)) - drink * heat, 0.0, 1.0)
	plot["last_factors"] = f
	return plot


## Expected harvest given the plot's current health (and pollination bonus).
static func expected_yield(plot: Dictionary, def: Dictionary) -> Dictionary:
	var out := {}
	var h := float(plot.get("health", 1.0))
	var bonus := 1.25 if plot.get("pollinated", false) else 1.0
	for item in def.get("yield", {}):
		var r: Array = def.yield[item]
		var base := lerpf(float(r[0]), float(r[1]), h)
		out[item] = maxi(1 if h > 0.2 else 0, roundi(base * bonus))
	return out


static func is_mature(plot: Dictionary) -> bool:
	return float(plot.get("growth", 0.0)) >= 0.9995 and not plot.get("dead", false)


## Visual growth stage 0..3 (seedling, young, grown, mature).
static func stage(plot: Dictionary) -> int:
	var g := float(plot.get("growth", 0.0))
	if g >= 1.0:
		return 3
	if g >= 0.55:
		return 2
	if g >= 0.2:
		return 1
	return 0
