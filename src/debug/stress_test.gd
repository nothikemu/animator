extends Node3D
## Stress bench. Part 1 (always): the simulation under a heavy, deliberately silly load —
## every open undercroft cell gassed, pipes and wires everywhere, dozens of machines — and
## reports per-step and per-tick cost. Part 2 (when rendering): Wick crowded with 300
## animated sprites and continuous particle bursts; reports frame time.
##   godot --headless -- --scene=res://scenes/test/stress_test.tscn
##   godot -- --scene=res://scenes/test/stress_test.tscn

const SIM_STEPS := 600
const MACHINE_TICKS := 200
const SPRITES := 300

var _frames := 0
var _time := 0.0
var _worst := 0.0
var view: AreaView


func _ready() -> void:
	GameFlow.new_game(777, "Bench")
	Clock.running = false
	_load_sim()
	var r := _bench_sim()
	print("STRESS sim: %d machines, %d pipe cells, %d wire cells" % [Sim.machines.machines.size(), Sim.machines.pipes.size(), Sim.machines.wires.size()])
	print("STRESS sim: field step avg %.3f ms (max %.3f), machine tick avg %.3f ms (max %.3f)" % r)
	print("STRESS sim phases (ms/step): %s" % _phases())
	if DisplayServer.get_name() == "headless":
		get_tree().quit()
		return
	_build_render_load()


func _load_sim() -> void:
	var g := Sim.grid
	for y in range(g.ground_y, g.h):
		for x in g.w:
			if g.is_open(x, y):
				g.add_gas(x, y, UcGrid.SOUR, 0.4)
				g.add_gas(x, y, UcGrid.DAMP, 0.2)
	for m: String in Content.machines:
		var u := String(Content.machine(m).get("unlock", ""))
		if u != "" and u != "start":
			GameState.set_flag(u)
	GameState.inventory = Inventory.new(64)
	for item in ["pipe_section", "wire_coil", "brass_scrap", "blackstone", "glowglass", "moss_fiber", "thermal_ore", "pipe_section", "glowbeet", "filter_pad"]:
		GameState.inventory.stack_limits[item] = 9999
		GameState.give(item, 900, true)
	# Wire and pipe every buildable cell of three long rows.
	for y in [12, 17, 20]:
		var row: Array = []
		for x in range(1, g.w - 1):
			row.append(Vector2i(x, y))
		Sim.lay_conduit("wire", row)
		Sim.lay_conduit("pipe", row)
	var tried := 0
	for x in range(2, g.w - 2):
		for y in range(g.ground_y, g.h - 1):
			for def in ["lamp", "crank", "fan", "scrubber", "pump", "burner", "heat_cell"]:
				if Sim.build(def, Vector2i(x, y)) == "":
					tried += 1
					break
	for m: MachineState in Sim.machines.machines.values():
		Sim.crank(m.id)
		Sim.load_item(m.id, "glowbeet", 5)


func _bench_sim() -> Array:
	var step_total := 0.0
	var step_max := 0.0
	for i in SIM_STEPS:
		var t0 := Time.get_ticks_usec()
		Sim._field_step()
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		step_total += ms
		step_max = maxf(step_max, ms)
	var tick_total := 0.0
	var tick_max := 0.0
	for i in MACHINE_TICKS:
		var t0 := Time.get_ticks_usec()
		Sim._tick_machines(1.0)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		tick_total += ms
		tick_max = maxf(tick_max, ms)
	return [step_total / SIM_STEPS, step_max, tick_total / MACHINE_TICKS, tick_max]


func _phases() -> String:
	var g := Sim.grid
	var names := ["water", "displace", "gas", "heat", "moisture", "sources"]
	var calls := [func() -> void: g._step_water(), func() -> void: g._displace_gas_by_water(),
		func() -> void: g._step_gas(0.25), func() -> void: g._step_heat(0.25),
		func() -> void: g._step_moisture(0.25), func() -> void: g._apply_sources(0.25)]
	var out := PackedStringArray()
	for i in calls.size():
		var t0 := Time.get_ticks_usec()
		for k in 100:
			calls[i].call()
		out.append("%s %.3f" % [names[i], (Time.get_ticks_usec() - t0) / 100000.0])
	return ", ".join(out)


func _build_render_load() -> void:
	var env := EnvCtl.new()
	add_child(env)
	env.set_biome("grove")
	view = AreaView.new()
	add_child(view)
	var area := AreaMap.from_ascii(Content.wick_map)
	view.build(area)
	Fx.ambient(view, "grove", area.w, area.d)
	var ids := ["player", "barnaby", "odile", "hesper", "mags"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in SPRITES:
		var s := PixelSprite3D.new()
		s.setup_character(ids[i % ids.size()])
		s.play(["walk_down", "walk_side", "idle_down", "work_down"][i % 4])
		s.position = Vector3(rng.randf_range(2, 46), 0.0, rng.randf_range(9, 21))
		view.add_child(s)
	var cam := Camera3D.new()
	cam.fov = 30
	add_child(cam)
	cam.look_at_from_position(Vector3(24, 18, 34), Vector3(24, 0, 15), Vector3.UP)
	cam.current = true


func _process(delta: float) -> void:
	if view == null:
		return
	view.update_lights(delta, 1.0, 0.0, 1.0)
	if _frames % 10 == 0:
		Fx.burst(view, Vector3(randf_range(4, 44), 0.2, randf_range(10, 20)), ["dirt", "water", "spark", "dust"][_frames % 4])
	_frames += 1
	if _frames > 30:
		_time += delta
		_worst = maxf(_worst, delta)
	if _frames == 330:
		print("STRESS render: %d sprites, avg frame %.2f ms, worst %.2f ms" % [SPRITES, _time / 300.0 * 1000.0, _worst * 1000.0])
		if not Dev.has_arg("keep"):
			get_tree().quit()
