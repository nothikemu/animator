class_name WorldActions
extends RefCounted
## The player's verbs in the world: interactables for an area and tool use on cells.
## Keeps game.gd small; everything here talks to state through the autoloads.

const CAN_MAX := 10

var game: Node


func _init(g: Node) -> void:
	game = g


# --- Interactables ----------------------------------------------------------------------------

func build_for(area: AreaMap, parent: Node3D) -> void:
	if area.id == "wick":
		_wick(area, parent)
	else:
		_reach(area, parent)


func _add(parent: Node3D, cell: Vector2, prompt: Callable, action: Callable, r := 1.3, prio := 0) -> Interactable:
	var y := 0.0
	var i := Interactable.make(Vector3(cell.x, y, cell.y), prompt, action, r, prio)
	parent.add_child(i)
	return i


func _wick(area: AreaMap, parent: Node3D) -> void:
	# The town well (also a surface machine in the cross-section).
	_add(parent, Vector2(24.5, 20.3), func() -> String:
		var w := Sim.well()
		if w == null:
			return ""
		if w.basin > 0.05 and int(GameState.player.get("can", 0)) < CAN_MAX and GameState.has_tool("can"):
			return "Fill the can"
		return "Crank the well", func() -> void: _well_action(), 1.5, 5)
	# The Lease: seed tin, old tools, bed, bench.
	_add(parent, Vector2(4.5, 13.5), func() -> String:
		return "Search the seed tin" if not GameState.has_flag("lease_seed_tin") else "Storage chest",
		func() -> void: _seed_tin(), 1.2)
	_add(parent, Vector2(9.5, 13.5), func() -> String:
		return "Look through the old tools" if not GameState.has_flag("lease_tools") else "",
		func() -> void: _old_tools(), 1.2)
	_add(parent, Vector2(4.5, 12.0), func() -> String: return "Sleep until morning",
		func() -> void: game.sleep(), 1.2, 2)
	_add(parent, Vector2(7.5, 11.5), func() -> String: return "Workbench",
		func() -> void: Events.ui_open.emit(&"craft", {"station": "bench"}), 1.2, 1)
	_add(parent, Vector2(43.5, 16.5), func() -> String:
		return "Barnaby's workbench" if Society.is_met("barnaby") else "",
		func() -> void: Events.ui_open.emit(&"craft", {"station": "bench"}), 1.2)
	_add(parent, Vector2(27.5, 12.0), func() -> String: return "Read the notice board",
		func() -> void: Events.ui_open.emit(&"board", {}), 1.3)
	_add(parent, Vector2(44.5, 15.5), func() -> String:
		return "Go down into the Reach" if GameState.has_flag("reach_open") else "The Reach (Barnaby says not yet)",
		func() -> void: _reach_gate(), 1.5, 3)
	_add(parent, Vector2(10.5, 26.0), func() -> String: return "Study the moss frames",
		func() -> void: _study_moss(), 1.4)
	_add(parent, Vector2(4.5, 4.5), func() -> String:
		return "The broken harness" if not GameState.has_flag("saw_harness") else "",
		func() -> void:
			GameState.set_flag("saw_harness", true)
			game.monologue("The cable sheared clean. Forty metres of it, somewhere up there. Nobody's pulling you back up today."), 1.4)


func _reach(area: AreaMap, parent: Node3D) -> void:
	for ex in area.exits:
		var to := String(ex.to)
		var kind := String(ex.get("kind", ""))
		var c := Vector2(float(ex.arrive[0]) + 0.5, float(ex.arrive[1]) + 0.5)
		_add(parent, c, func() -> String:
			if not ReachGen.passable({"kind": kind}, GameState.flags):
				return "Collapsed rock" if kind == "collapsible" else "Sealed with rubble"
			if to == "wick":
				return "Climb back to Wick"
			return "Go on to %s" % String(ReachGen.node_by_id(GameState.reach_graph, to).get("name", to)),
			func() -> void:
				if ReachGen.passable({"kind": kind}, GameState.flags):
					game.travel(to), 1.6, 4)


# --- Actions ----------------------------------------------------------------------------------

func _well_action() -> void:
	var w := Sim.well()
	if w == null:
		return
	if w.basin > 0.05 and int(GameState.player.get("can", 0)) < CAN_MAX and GameState.has_tool("can"):
		var need := float(CAN_MAX - int(GameState.player.get("can", 0))) * 0.03
		var got := Sim.take_well_water(need)
		GameState.player["can"] = mini(CAN_MAX, int(GameState.player.get("can", 0)) + int(round(got / 0.03)))
		GameState.player["can_brine"] = false
		Audio.play_at("water_fill", game.player.global_position, -6.0)
		Events.toast.emit("Can filled from the well.", &"info")
		return
	Sim.crank(w.id)
	game.player.use_tool_anim(0.6)
	Audio.play_at("well_crank", Vector3(24.5, 0.5, 20.5), -4.0)
	Events.camera_impulse.emit(0.05)
	GameState.set_flag("cranked_well", int(GameState.flag("cranked_well") if GameState.flag("cranked_well") else 0) + 1)
	if not GameState.has_flag("well_fixed"):
		Events.caption.emit("[the pump coughs; somewhere below, water hisses]", 2.5)


func _seed_tin() -> void:
	if GameState.has_flag("lease_seed_tin"):
		Events.ui_open.emit(&"inventory", {})
		return
	GameState.set_flag("lease_seed_tin", true)
	GameState.give("glowbeet_seed", 6)
	GameState.give("moss_spore", 4)
	game.monologue("A tin of seeds, labelled in a careful hand: GLOWBEET — WARM, WET, LIT. MOSS — ANYWHERE DAMP. Tolley, presumably.")


func _old_tools() -> void:
	GameState.set_flag("lease_tools", true)
	GameState.add_tool("tiller")
	GameState.add_tool("can")
	GameState.player["can"] = 0
	Events.toast.emit("Found a tiller and a watering can.", &"learn")
	Audio.play("pickup", -6.0)


func _reach_gate() -> void:
	if GameState.has_flag("reach_open"):
		game.travel(String(GameState.reach_graph.nodes[0].id))
	else:
		game.monologue("The tunnel drops away into the dark. Not without a light worth the name, and not before you know where you're sleeping.")


func _study_moss() -> void:
	if not GameState.has_flag("studied_moss"):
		GameState.set_flag("studied_moss", true)
		GameState.add_deed("studied_life", 1.0)
		GameState.discover("lore", "moss_frames")
	game.monologue("The moss grows in tidy frames, each tagged with a date. Some of the tags go back forty years. It breathes — you can see it, faintly, when the Deep is quiet.")


# --- Tools on cells ---------------------------------------------------------------------------

## Uses the current tool on the cell the player faces. Returns true if something happened.
func use_tool(cell: Vector2i) -> bool:
	var tool := GameState.current_tool()
	match tool:
		"tiller": return _till_or_plant(cell)
		"can": return _water(cell)
		"hands": return _hands(cell)
		"hammer": return _hammer(cell)
		"glass":
			game.toggle_cut_view()
			return true
	return false


func _till_or_plant(cell: Vector2i) -> bool:
	if game.area.id != "wick":
		return false
	var p := Sim.plot_at(cell)
	if p.is_empty():
		if Sim.till(cell):
			game.player.use_tool_anim(0.45)
			game.fx_burst(cell, "dirt")
			Audio.play_at("till", game.cell_pos(cell), -4.0)
			Events.camera_impulse.emit(0.04)
			GameState.add_deed("tilled", 1.0)
			return true
		Events.toast.emit("This ground won't take a tiller.", &"info")
		return false
	if String(p.crop) == "":
		var seeds := _seeds_in_inventory()
		if seeds.is_empty():
			Events.toast.emit("No seeds.", &"info")
			return false
		var seed: String = seeds[int(GameState.player.get("seed_index", 0)) % seeds.size()]
		var crop := String(Content.item(seed).get("crop", ""))
		if GameState.take(seed, 1) and Sim.plant(cell, crop):
			game.player.use_tool_anim(0.35)
			Audio.play_at("plant", game.cell_pos(cell), -6.0)
			Events.toast.emit("Planted %s." % Content.crop(crop).get("name", crop), &"info")
			return true
	return false


func _seeds_in_inventory() -> Array:
	var out: Array = []
	for s in GameState.inventory.slots:
		if s.is_empty():
			continue
		if String(Content.item(s.id).get("category", "")) == "seed" and not out.has(s.id):
			out.append(s.id)
	return out


func cycle_seed() -> String:
	var seeds := _seeds_in_inventory()
	if seeds.is_empty():
		return ""
	GameState.player["seed_index"] = (int(GameState.player.get("seed_index", 0)) + 1) % seeds.size()
	return seeds[int(GameState.player.seed_index)]


func current_seed() -> String:
	var seeds := _seeds_in_inventory()
	if seeds.is_empty():
		return ""
	return seeds[int(GameState.player.get("seed_index", 0)) % seeds.size()]


func _water(cell: Vector2i) -> bool:
	# Refill at the lake: free, but brackish.
	if game.area.id == "wick" and _near_lake():
		if int(GameState.player.get("can", 0)) < CAN_MAX:
			GameState.player["can"] = CAN_MAX
			GameState.player["can_brine"] = true
			Audio.play_at("water_fill", game.player.global_position, -6.0)
			game.monologue("Lake water. It smells faintly of salt and pennies.")
			return true
	var p := Sim.plot_at(cell)
	if p.is_empty():
		return false
	if int(GameState.player.get("can", 0)) <= 0:
		Events.toast.emit("The can is empty.", &"info")
		return false
	GameState.player["can"] = int(GameState.player.can) - 1
	Sim.water_plot(cell)
	if GameState.player.get("can_brine", false) and String(p.crop) != "":
		p.health = maxf(0.0, float(p.health) - 0.08)
		GameState.add_deed("brine_watered", 1.0)
	game.player.use_tool_anim(0.4)
	game.fx_burst(cell, "water")
	Audio.play_at("water_pour", game.cell_pos(cell), -5.0)
	return true


func _near_lake() -> bool:
	var c: Vector2i = game.player.cell()
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if game.area.h_at(c.x + dx, c.y + dz) == AreaMap.WATER_LEVEL:
				return true
	return false


func _hands(cell: Vector2i) -> bool:
	if game.area.id != "wick":
		return false
	var p := Sim.plot_at(cell)
	if p.is_empty() or String(p.crop) == "":
		return false
	var was_dead := bool(p.get("dead", false))
	var crop := String(p.crop)
	var got := Sim.harvest(cell)
	if was_dead:
		Events.toast.emit("Cleared the dead %s." % Content.crop(crop).get("name", crop), &"info")
		game.player.use_tool_anim(0.3)
		return true
	if got.is_empty():
		var def: Dictionary = Content.crop(crop)
		var env := Sim.plot_env(cell)
		var f := CropLogic.factors(def, env)
		var w := CropLogic.worst(def, env, f)
		game.monologue(Inspect.crop_line(crop, p, w))
		return true
	for item in got:
		GameState.give(item, int(got[item]))
		Fx.item_pop(game.area_view, game.cell_pos(cell), game.player, String(item), int(got[item]))
	GameState.add_deed("harvested", 1.0, {"crop": crop})
	game.player.use_tool_anim(0.35)
	game.fx_burst(cell, "harvest")
	Audio.play_at("harvest", game.cell_pos(cell), -4.0)
	return true


func _hammer(cell: Vector2i) -> bool:
	return game.mine_at(cell)
