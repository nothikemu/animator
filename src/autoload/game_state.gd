extends Node
## The save-able state root (world flags, deed history, player, inventory, discoveries)
## and the single context object that resolves every key used by the rule language
## (dialogue, threads, director cards, schedules). See src/social/conditions.gd.

const START_MONEY := 20

var seed_value := 0
var flags: Dictionary = {}
var history: Dictionary = {}           ## deed kind -> accumulated amount
var discovered := {"places": {}, "recipes": {}, "lore": {}, "people": {}, "machines": {}}
var player := {}
var inventory := Inventory.new()
var areas: Dictionary = {}             ## reach node id -> {"mined": {res_id: n_left}, "visited": bool}
var reach_graph: Dictionary = {}
var view_mode := "explore"             ## explore | cut | dialogue
var current_area := "wick"
var playtime := 0.0
var started := false


func _ready() -> void:
	inventory.changed.connect(func() -> void: Events.inventory_changed.emit())


func _process(delta: float) -> void:
	if started and not get_tree().paused:
		playtime += delta


func new_game(seed_v: int, player_name: String) -> void:
	seed_value = seed_v
	flags.clear()
	history.clear()
	discovered = {"places": {}, "recipes": {}, "lore": {}, "people": {}, "machines": {}}
	player = {"name": player_name.strip_edges() if not player_name.strip_edges().is_empty() else "Salvager",
		"area": "wick", "pos": [4.5, 5.5], "facing": [0.0, 1.0], "money": START_MONEY,
		"tools": ["hands"], "tool_index": 0, "gear": {}, "effects": {}}
	inventory = Inventory.new()
	inventory.changed.connect(func() -> void: Events.inventory_changed.emit())
	for id in Content.items:
		inventory.stack_limits[id] = int(Content.items[id].get("stack", 99))
	areas.clear()
	reach_graph = ReachGen.generate_graph(seed_value)
	current_area = "wick"
	view_mode = "explore"
	playtime = 0.0
	started = true


# --- Flags and deeds ------------------------------------------------------------------

func flag(name: String) -> Variant:
	return flags.get(name, null)


func has_flag(name: String) -> bool:
	return Conditions._truthy(flags.get(name, null))


func set_flag(name: String, value: Variant = true) -> void:
	if flags.get(name) == value:
		return
	flags[name] = value
	Events.flag_changed.emit(StringName(name), value)


func add_deed(kind: String, amount: float = 1.0, context: Dictionary = {}) -> void:
	history[kind] = float(history.get(kind, 0.0)) + amount
	Events.deed.emit(StringName(kind), amount, context)


func deed(kind: String) -> float:
	return float(history.get(kind, 0.0))


# --- Money, items, tools ---------------------------------------------------------------

func money() -> int:
	return int(player.get("money", 0))


func add_money(n: int) -> void:
	player["money"] = maxi(0, money() + n)
	Events.money_changed.emit(money())


func spend(n: int) -> bool:
	if money() < n:
		return false
	add_money(-n)
	return true


func give(item: String, n: int = 1, quiet := false) -> int:
	var left := inventory.add(item, n)
	var got := n - left
	if got > 0 and not quiet:
		Events.toast.emit("+%d %s" % [got, Content.item_name(item)], &"item")
	if left > 0:
		Events.toast.emit("No room for %d %s." % [left, Content.item_name(item)], &"warn")
	return got


func take(item: String, n: int = 1) -> bool:
	return inventory.remove(item, n)


func has_tool(tool_id: String) -> bool:
	return (player.get("tools", []) as Array).has(tool_id)


func add_tool(tool_id: String) -> void:
	var tools: Array = player.get("tools", [])
	if not tools.has(tool_id):
		tools.append(tool_id)
		player["tools"] = tools
		Events.tool_changed.emit(StringName(current_tool()))


func current_tool() -> String:
	var tools: Array = player.get("tools", ["hands"])
	var i := clampi(int(player.get("tool_index", 0)), 0, tools.size() - 1)
	return String(tools[i])


func cycle_tool(dir: int) -> void:
	var tools: Array = player.get("tools", ["hands"])
	if tools.size() <= 1:
		return
	player["tool_index"] = posmod(int(player.get("tool_index", 0)) + dir, tools.size())
	Events.tool_changed.emit(StringName(current_tool()))


func select_tool(tool_id: String) -> void:
	var tools: Array = player.get("tools", ["hands"])
	var i := tools.find(tool_id)
	if i >= 0:
		player["tool_index"] = i
		Events.tool_changed.emit(StringName(tool_id))


func discover(kind: String, id: String) -> bool:
	if not discovered.has(kind):
		discovered[kind] = {}
	if discovered[kind].has(id):
		return false
	discovered[kind][id] = Clock.day
	Events.discovered.emit(StringName(kind), StringName(id))
	return true


func knows_recipe(recipe_id: String) -> bool:
	var r: Dictionary = Content.recipes.get(recipe_id, {})
	if r.is_empty():
		return false
	var unlock := String(r.get("unlock", ""))
	return unlock.is_empty() or has_flag(unlock)


func can_build(machine_id: String) -> bool:
	var unlock := String(Content.machine(machine_id).get("unlock", ""))
	return unlock == "start" or (not unlock.is_empty() and has_flag(unlock))


# --- Effects (shared by dialogue, threads and director cards) ----------------------------

## Applies effect strings such as "trust:barnaby+5", "give:pipe_section*2", "flag:x=3".
func apply_effects(effects: Variant, speaker := "") -> void:
	if effects == null:
		return
	if effects is String:
		effects = [effects]
	for e in effects:
		_apply_effect(String(e), speaker)


func _apply_effect(e: String, speaker: String) -> void:
	e = e.strip_edges()
	if e.is_empty():
		return
	if e.begins_with("!flag:"):
		set_flag(e.substr(6), false)
		return
	var colon := e.find(":")
	var kind := e.substr(0, colon) if colon >= 0 else e
	var arg := e.substr(colon + 1) if colon >= 0 else ""
	match kind:
		"flag":
			var eq := arg.find("=")
			if eq >= 0:
				set_flag(arg.substr(0, eq), _parse_value(arg.substr(eq + 1)))
			else:
				set_flag(arg, true)
		"give":
			var p := _item_count(arg)
			give(p[0], p[1])
		"take":
			var p := _item_count(arg)
			take(p[0], p[1])
		"learn", "unlock":
			set_flag(arg, true)
			if Content.recipes.has(arg.trim_prefix("learned_")):
				discover("recipes", arg.trim_prefix("learned_"))
		"tool":
			add_tool(arg)
		"thread":
			var eq := arg.find("=")
			if eq >= 0:
				Threads.set_stage(arg.substr(0, eq), int(arg.substr(eq + 1)))
		"event":
			Director.trigger(arg)
		"deed":
			var sign_at := maxi(arg.rfind("+"), arg.rfind("-"))
			if sign_at > 0:
				add_deed(arg.substr(0, sign_at), float(arg.substr(sign_at)))
			else:
				add_deed(arg, 1.0)
		"met":
			Society.mark_met(arg)
		"mem":
			# mem:npc:memory_id:importance[:sentiment][:lasting]
			var parts := arg.split(":")
			if parts.size() >= 3:
				var sentiment := float(parts[3]) if parts.size() > 3 else 0.0
				var lasting := parts.size() > 4 and parts[4] == "lasting"
				Society.remember(parts[0], parts[1], float(parts[2]), sentiment, lasting)
		"toast":
			Events.toast.emit(arg, &"info")
		"caption":
			Events.caption.emit(arg, 3.0)
		"notice":
			var parts := arg.split(":", true, 1)
			if parts.size() == 2:
				Events.noticed.emit(StringName(parts[0]), parts[1])
		"discover":
			var parts := arg.split(":", true, 1)
			if parts.size() == 2:
				discover(parts[0], parts[1])
		_:
			if kind.begins_with("money"):
				add_money(int(e.substr(5)))
				return
			# Relationship axis: axis:npc+N
			if NpcSocial.AXES.has(kind):
				var sign_at := maxi(arg.rfind("+"), arg.rfind("-"))
				if sign_at > 0:
					Society.change(arg.substr(0, sign_at), kind, float(arg.substr(sign_at)))
				return
			Log.warn("effects", "unknown effect '%s' (speaker %s)" % [e, speaker])


static func _item_count(arg: String) -> Array:
	var star := arg.find("*")
	if star >= 0:
		return [arg.substr(0, star), int(arg.substr(star + 1))]
	return [arg, 1]


static func _parse_value(s: String) -> Variant:
	if s == "true":
		return true
	if s == "false":
		return false
	if s.is_valid_int():
		return int(s)
	if s.is_valid_float():
		return float(s)
	return s


# --- Rule-language context ---------------------------------------------------------------

## Resolves a condition key (see Conditions). Unknown keys resolve to null (falsey).
func value(key: String) -> Variant:
	var dot := key.find(".")
	var kind := key.substr(0, dot) if dot >= 0 else key
	var arg := key.substr(dot + 1) if dot >= 0 else ""
	match kind:
		"flag": return flags.get(arg, null)
		"met": return Society.is_met(arg)
		"trust", "respect", "affection", "resentment", "fear", "shared":
			return Society.axis(arg, kind)
		"mem":
			var p := arg.split(":", true, 1)
			return Society.has_memory(p[0], p[1]) if p.size() == 2 else false
		"mood": return Society.mood(arg)
		"thread": return Threads.stage(arg)
		"item": return inventory.count(arg)
		"money": return money()
		"deed": return deed(arg)
		"tool": return has_tool(arg)
		"day": return Clock.day
		"hour": return Clock.hour()
		"minute": return int(Clock.minute)
		"phase": return Clock.phase()
		"breath": return Clock.breath()
		"place", "area": return current_area
		"view": return view_mode
		"recipe": return knows_recipe(arg)
		"lore": return discovered.get("lore", {}).has(arg)
		"discovered":
			var p := arg.split(":", true, 1)
			return discovered.get(p[0], {}).has(p[1]) if p.size() == 2 else false
		"market_day": return Clock.is_market_day()
		"seen_places": return discovered.get("places", {}).size()
		"talked": return Society.talked_today(arg)
		"gifted": return Society.gifted_today(arg)
	return Sim.fact(key)


# --- Serialisation -----------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"seed": seed_value, "flags": flags.duplicate(true), "history": history.duplicate(),
		"discovered": discovered.duplicate(true), "player": player.duplicate(true),
		"inventory": inventory.to_array(), "areas": areas.duplicate(true),
		"current_area": current_area, "playtime": playtime}


func load_dict(d: Dictionary) -> void:
	seed_value = int(d.get("seed", 0))
	flags = d.get("flags", {}) if d.get("flags") is Dictionary else {}
	history = {}
	var h: Variant = d.get("history", {})
	if h is Dictionary:
		for k in h:
			history[k] = float(h[k])
	var disc: Variant = d.get("discovered", {})
	discovered = {"places": {}, "recipes": {}, "lore": {}, "people": {}, "machines": {}}
	if disc is Dictionary:
		for k in disc:
			if disc[k] is Dictionary:
				discovered[k] = disc[k]
	player = d.get("player", {}) if d.get("player") is Dictionary else {}
	player["money"] = maxi(0, int(player.get("money", 0)))
	if not player.has("tools"):
		player["tools"] = ["hands"]
	inventory = Inventory.new()
	inventory.changed.connect(func() -> void: Events.inventory_changed.emit())
	for id in Content.items:
		inventory.stack_limits[id] = int(Content.items[id].get("stack", 99))
	inventory.load_array(d.get("inventory", []), Content.items)
	areas = d.get("areas", {}) if d.get("areas") is Dictionary else {}
	current_area = String(d.get("current_area", "wick"))
	playtime = float(d.get("playtime", 0.0))
	reach_graph = ReachGen.generate_graph(seed_value)
	view_mode = "explore"
	started = true
