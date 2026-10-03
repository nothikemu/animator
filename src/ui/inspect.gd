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
