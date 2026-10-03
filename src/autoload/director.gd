extends Node
## Event Director. Each in-game hour it considers authored event cards whose conditions
## match the world state (never pure randomness), respecting cooldowns, one-shot cards and a
## tension budget: after a crisis there is a calm window so the game stays cozy between peaks.
##   {"when": [conds], "chance": 0.3, "weight": 1, "cooldown": 2, "once": false,
##    "intensity": 2, "effects": [...], "hook": "tremor", "toast": "...", "caption": "..."}

signal fired(event_id: String)

var tension := 0.0
var last_fired: Dictionary = {}          ## id -> day
var fired_once: Dictionary = {}
var log_lines: Array = []                ## recent events for the debug overlay
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	Clock.hour_changed.connect(_on_hour)
	Clock.day_started.connect(func(_d: int) -> void:
		tension = maxf(0.0, tension - 1.5)
		end_quietlight())


func reset(seed_value: int) -> void:
	tension = 0.0
	last_fired.clear()
	fired_once.clear()
	log_lines.clear()
	rng.seed = hash([seed_value, "director"])


func _on_hour(_h: int) -> void:
	if not GameState.started:
		return
	tension = maxf(0.0, tension - 0.1)
	var candidates: Array = []
	var total := 0.0
	for id in Content.events:
		var c: Dictionary = Content.events[id]
		if bool(c.get("manual", false)):
			continue
		if not _eligible(id, c):
			continue
		var w := float(c.get("weight", 1.0))
		candidates.append([id, w])
		total += w
	if candidates.is_empty():
		return
	var roll := rng.randf() * total
	for cand in candidates:
		roll -= float(cand[1])
		if roll <= 0.0:
			var c: Dictionary = Content.events[cand[0]]
			if rng.randf() <= float(c.get("chance", 1.0)):
				trigger(cand[0])
			return


func _eligible(id: String, c: Dictionary) -> bool:
	if bool(c.get("once", false)) and fired_once.has(id):
		return false
	var cd := int(c.get("cooldown", 1))
	if last_fired.has(id) and Clock.day - int(last_fired[id]) < cd:
		return false
	var intensity := float(c.get("intensity", 0.0))
	if intensity >= 2.0 and tension > 1.0:
		return false   # calm window after a crisis
	return Conditions.check(c.get("when", []), GameState)


## Fires an event by id (also used by the "event:" effect).
func trigger(id: String) -> void:
	var c: Dictionary = Content.events.get(id, {})
	if c.is_empty():
		Log.warn("director", "unknown event '%s'" % id)
		return
	last_fired[id] = Clock.day
	if bool(c.get("once", false)):
		fired_once[id] = true
	tension += float(c.get("intensity", 0.0))
	var hook := String(c.get("hook", ""))
	if not hook.is_empty() and has_method("_hook_" + hook):
		call("_hook_" + hook, c)
	GameState.apply_effects(c.get("effects", []), "event:" + id)
	if c.has("toast"):
		Events.toast.emit(String(c.toast), &"event")
	if c.has("caption"):
		Events.caption.emit(String(c.caption), 4.0)
	if c.has("shake"):
		Events.camera_impulse.emit(float(c.shake))
	log_lines.append("D%d %s %s" % [Clock.day, Clock.time_string(), id])
	if log_lines.size() > 20:
		log_lines.pop_front()
	Events.world_event.emit(StringName(id), c)
	fired.emit(id)


# --- Hooks: events that reshape the world ---------------------------------------------------

## The Tremor: opens the fissure under the Lease into the sour pocket, cracks pipes,
## and rewires the Reach (Trunk chamber opens, a shortcut collapses).
func _hook_tremor(_c: Dictionary) -> void:
	var grid := Sim.grid
	var opened: Array = []
	for cell in Content.undercroft.get("fissure", []):
		var c := Vector2i(int(cell[0]), int(cell[1]))
		if not grid.is_open(c.x, c.y):
			grid.set_mat(c.x, c.y, UcGrid.Mat.AIR)
			opened.append(c)
	# Pressure releases: the pocket's gas pushes into the fissure immediately.
	for c in opened:
		grid.add_gas(c.x, c.y, UcGrid.SOUR, 1.0)
	# Shake damage: crack a few pipe segments.
	var pipe_cells := Sim.machines.pipes.keys()
	pipe_cells.sort()
	var cracked := 0
	for i in pipe_cells.size():
		if cracked >= 3:
			break
		var c: Vector2i = pipe_cells[(i * 7 + rng.randi_range(0, 3)) % pipe_cells.size()]
		if float(Sim.machines.pipes[c]) > 0.5:
			Sim.machines.damage_conduit("pipe", c, 0.55)
			cracked += 1
	GameState.set_flag("tremor_done", true)
	GameState.set_flag("fissure_open", true)
	Events.grid_cells_changed.emit(opened)
	Events.sim_topology_changed.emit()
	Events.flash.emit(Color(1.0, 0.9, 0.7), 0.35)


## The Breath surge on exhale days: the deep vents push more gas up.
func _hook_exhale_surge(_c: Dictionary) -> void:
	for c in Sim.grid.vents:
		for k in Sim.grid.vents[c]:
			Sim.grid.add_gas(c.x, c.y, int(k), 0.3)


## Lampmoth swarm: visual event; pollinates every lit glowbeet.
func _hook_moth_swarm(_c: Dictionary) -> void:
	for cell in Sim.plots:
		var p: Dictionary = Sim.plots[cell]
		if p.crop == "glowbeet":
			p.pollinated = true


## Quietlight: every lamp in Wick goes out for the Hush and the grove blooms. How bright it
## blooms is decided by the air the player has left the town with, and by whether the
## market lamps stayed lit (Odile's side of the argument).
func _hook_quietlight(_c: Dictionary) -> void:
	var air := Sim.village_pollution()
	var bright := air < 0.06 and String(GameState.flag("ql_side") if GameState.flag("ql_side") else "") != "odile"
	GameState.set_flag("ql_bloom", "bright" if bright else "thin")
	GameState.set_flag("quietlight_active", true)
	GameState.discover("lore", "quietlight")


## The morning after Quietlight.
func end_quietlight() -> void:
	if GameState.has_flag("quietlight_active"):
		GameState.set_flag("quietlight_active", false)
		trigger("quietlight_end")


## The Trunk valve turns: pressure equalises, the gauge needle drops off its pin.
func _hook_valve_turn(_c: Dictionary) -> void:
	GameState.set_flag("valve_turned", true)
	Audio.play("valve_turn", -2.0)
	Events.flash.emit(Color(0.85, 0.95, 1.0), 0.15)


## Three, two, three, from below the Lower Stations.
func _hook_knock(_c: Dictionary) -> void:
	Audio.play("knock_323", 0.0)
	GameState.discover("lore", "the_knock")


func to_dict() -> Dictionary:
	return {"tension": tension, "last_fired": last_fired.duplicate(), "fired_once": fired_once.duplicate(),
		"rng": str(rng.state)}


func load_dict(d: Dictionary) -> void:
	tension = clampf(float(d.get("tension", 0.0)), 0.0, 10.0)
	last_fired = d.get("last_fired", {}) if d.get("last_fired") is Dictionary else {}
	fired_once = d.get("fired_once", {}) if d.get("fired_once") is Dictionary else {}
	if d.has("rng"):
		rng.state = String(str(d.rng)).to_int()
