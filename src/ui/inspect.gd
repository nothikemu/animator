class_name Inspect
extends RefCounted
## Plain-language descriptions of world state. The game never asks the player to read
## numbers to understand why something is unhappy.

const STATUS_TEXT := {
	&"ok": "Running.",
	&"idle": "Idle.",
	&"off": "Switched off.",
	&"broken": "Broken.",
	&"flooded": "Flooded — water in the works.",
	&"not_connected": "Not connected to any wire.",
	&"no_power": "No power reaching it.",
	&"overloaded": "The wires are overloaded.",
	&"no_fuel": "Out of fuel.",
	&"needs_filter": "Needs a fresh filter pad.",
	&"output_full": "Full — empty it.",
	&"no_water": "No water reaching it.",
	&"dry": "Nothing to draw from — it's dry.",
	&"too_hot": "Running too hot.",
	&"choking": "Choking on foul air.",
	&"incomplete": "Missing parts.",
	&"blocked": "Something is blocking it.",
}

const COND_TEXT := {
	"light": {"low": "too dark", "high": "too bright"},
	"moisture": {"low": "too dry", "high": "waterlogged"},
	"temp": {"low": "too cold", "high": "too hot"},
	"sour": {"low": "", "high": "the air is fouled"},
}


static func status(s: StringName) -> String:
	return STATUS_TEXT.get(s, String(s).capitalize())


static func crop_line(crop: String, plot: Dictionary, worst: Dictionary) -> String:
	var name := String(Content.crop(crop).get("name", crop))
	if plot.get("dead", false):
		return "The %s is dead. Clear it and try somewhere it'll be happier." % name.to_lower()
	var g := float(plot.get("growth", 0.0))
	var stage := "just sprouted" if g < 0.2 else ("growing" if g < 0.55 else ("nearly there" if g < 1.0 else "ready"))
	var line := "%s, %s." % [name, stage]
	var cond := String(worst.get("cond", ""))
	if cond != "":
		var f := float(worst.get("factor", 1.0))
		var how := String(COND_TEXT.get(cond, {}).get(String(worst.get("dir", "low")), ""))
		if how != "":
			if f < 0.25:
				line += " It's struggling: %s." % how
			elif f < 0.75:
				line += " A little %s." % how.trim_prefix("too ")
	elif g < 1.0:
		line += " Happy where it is."
	var h := float(plot.get("health", 1.0))
	if h < 0.5:
		line += " The leaves are yellowing."
	if plot.get("pollinated", false):
		line += " Moths have been at it."
	return line


static func crop_detail(crop: String, plot: Dictionary, env: Dictionary) -> Dictionary:
	var def: Dictionary = Content.crop(crop)
	var f := CropLogic.factors(def, env)
	return {"growth": float(plot.get("growth", 0.0)), "health": float(plot.get("health", 1.0)),
		"water": float(env.get("moisture", 0.0)), "factors": f,
		"expected": CropLogic.expected_yield(plot, def), "worst": CropLogic.worst(def, env, f)}


# --- Undercroft ----------------------------------------------------------------------------------

const PLACE_TEXT := {
	"blocked": "Solid ground in the way.",
	"occupied": "Something's already there.",
	"needs_floor": "Needs solid footing beneath it.",
	"needs_surface": "Has to stand on the surface, in the lane.",
	"needs_ceiling": "Needs a ceiling to hang from.",
	"out_of_bounds": "Out of reach.",
	"no_materials": "You're short of materials.",
	"not_known": "You don't know how to build that yet.",
	"not_damaged": "Nothing to mend here.",
	"unknown": "That isn't something you can build.",
}


static func place_reason(key: String) -> String:
	return PLACE_TEXT.get(key, key.capitalize())


static func temp_word(t: float) -> String:
	if t < 4.0:
		return "freezing"
	if t < 13.0:
		return "cold"
	if t < 23.0:
		return "mild"
	if t < 38.0:
		return "warm"
	if t < 70.0:
		return "hot"
	return "scalding"


## One short phrase for the air in an open cell.
static func air_text(grid: UcGrid, x: int, y: int) -> String:
	var i := grid.idx(x, y)
	if grid.water[i] > 0.85:
		return "under water"
	var total := grid.gas_total(i)
	if total < 0.05:
		return "almost no air at all"
	var sour := grid.gas[UcGrid.SOUR][i] / total
	var stale := grid.gas[UcGrid.STALE][i] / total
	var damp := grid.gas[UcGrid.DAMP][i] / total
	var words := ""
	if sour > 0.45:
		words = "foul, sour air — it sinks and pools"
	elif sour > 0.12:
		words = "a sour tang in the air"
	elif stale > 0.4:
		words = "stale, used-up air"
	elif damp > 0.4:
		words = "damp air, rising"
	elif stale > 0.15 or damp > 0.15:
		words = "close air"
	else:
		words = "fresh air"
	if total > 1.6:
		words += ", pressing hard"
	elif total < 0.5:
		words += ", thin"
	if grid.water[i] > 0.15:
		words += "; water on the floor"
	return words


static func cell_text(grid: UcGrid, c: Vector2i) -> String:
	if not grid.in_bounds(c.x, c.y):
		return ""
	if c.y < grid.ground_y:
		return "The lane above — %s." % air_text(grid, c.x, c.y)
	if grid.is_open(c.x, c.y):
		return "Open space: %s. %s." % [air_text(grid, c.x, c.y), temp_word(grid.temp[grid.idx(c.x, c.y)]).capitalize()]
	var m: String = UcGrid.MAT_NAMES[grid.get_mat(c.x, c.y)]
	var desc := {"topsoil": "Topsoil", "soil": "Packed soil", "clay": "Wet clay", "rock": "Rock",
		"brick": "Old brickwork", "stone": "Dressed stone", "metal": "Riveted plate",
		"insulation": "Felt insulation", "bedrock": "Bedrock — nothing gets through",
		"ember": "Ember seam, warm to the touch", "seal": "A poured seal. Someone wanted this shut."}
	return "%s. %s." % [desc.get(m, m.capitalize()), temp_word(grid.temp[grid.idx(c.x, c.y)]).capitalize()]


static func _amount(v: float, full: float) -> String:
	var f := v / maxf(full, 0.0001)
	if f <= 0.01:
		return "nothing"
	if f < 0.25:
		return "a trickle"
	if f < 0.6:
		return "some"
	if f < 0.95:
		return "plenty"
	return "everything it can"


static func _share(f: float) -> String:
	if f >= 0.98:
		return "all it needs"
	if f >= 0.6:
		return "most of what it needs"
	if f >= 0.25:
		return "some of what it needs"
	if f > 0.01:
		return "barely any of what it needs"
	return "none of what it needs"


## Plain-language lines about a machine (no numbers needed to understand it).
static func machine_lines(m: MachineState, d: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var power: Dictionary = d.get("power", {})
	if power.has("produce") or d.has("turbine") or d.has("crank"):
		var full := float(power.get("produce", d.get("turbine", {}).get("max", d.get("crank", {}).get("power", 10.0))))
		out.append("Making power: %s." % _amount(m.power_out, full))
	if power.has("consume"):
		out.append("Getting %s in power." % _share(m.power_sat))
	if d.has("pump") or d.has("intake"):
		out.append("Moving water: %s." % _amount(m.water_moved, float(d.get("pump", d.get("intake", {})).get("rate", 1.0))))
	if d.has("water_use"):
		out.append("Getting %s in water." % _share(m.water_sat))
	if d.has("fuel"):
		var items: Dictionary = m.fuel_items
		var n := 0
		for k in items:
			n += int(items[k])
		if n > 0 or m.fuel_minutes > 0.0:
			var hours := (m.fuel_minutes + _fuel_minutes_waiting(m, d)) / 60.0
			out.append("Fuel for about %s." % ("an hour" if hours < 1.5 else "%d hours" % int(round(hours))))
		else:
			out.append("The hopper is empty.")
	if d.has("filter"):
		var f := m.filter_minutes / maxf(float(d.filter.get("minutes", 720.0)), 1.0)
		out.append("Filter pad: %s." % ("none fitted" if f <= 0.0 else ("spent" if f < 0.1 else ("worn" if f < 0.5 else "fresh"))))
	if d.has("waste") or d.has("compost"):
		var cap := float(d.get("waste", d.get("compost", {})).get("capacity", 6))
		if m.waste >= 1.0:
			out.append("Holding %d %s%s." % [int(m.waste), Content.item_name(String(d.get("waste", {}).get("item", d.get("compost", {}).get("output", "")))).to_lower(), " — it's full" if m.waste >= cap else ""])
	if d.has("tank"):
		var f := m.stored / maxf(float(d.tank.get("capacity", 10.0)), 1.0)
		out.append("Tank: %s." % ("empty" if f < 0.03 else ("low" if f < 0.3 else ("about half" if f < 0.7 else ("nearly full" if f < 0.97 else "full")))))
	if d.has("battery"):
		var f := m.stored / maxf(float(d.battery.get("capacity", 100.0)), 1.0)
		out.append("Charge: %s." % ("empty" if f < 0.03 else ("low" if f < 0.3 else ("about half" if f < 0.7 else ("high" if f < 0.97 else "full")))))
	if d.has("well"):
		var f := m.basin / maxf(float(d.well.get("capacity", 3.0)), 1.0)
		out.append("Basin: %s." % ("dry" if f < 0.05 else ("a little water" if f < 0.4 else ("half full" if f < 0.8 else "full"))))
	if d.has("requires"):
		var missing := PackedStringArray()
		for item: String in d.requires:
			var need := int(d.requires[item]) - int(m.story.get(item, 0))
			if need > 0:
				missing.append("%d × %s" % [need, Content.item_name(item).to_lower()])
		if not missing.is_empty():
			out.append("Still missing: %s." % ", ".join(missing))
	if m.manual_timer > 0.0:
		out.append("Still turning from the last crank.")
	if not m.on_power_net and (power.has("consume") or power.has("produce") or d.has("turbine") or d.has("crank") or d.has("battery")):
		out.append("Not wired to anything.")
	if not m.on_water_net and (d.has("pump") or d.has("water_use") or d.has("outlet") or d.has("intake")) and not d.has("well"):
		out.append("No pipe connected.")
	return out


static func _fuel_minutes_waiting(m: MachineState, d: Dictionary) -> float:
	var total := 0.0
	var per: Dictionary = d.get("fuel", {}).get("items", {})
	for k in m.fuel_items:
		total += float(per.get(k, 60.0)) * int(m.fuel_items[k])
	return total
