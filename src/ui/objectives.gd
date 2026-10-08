class_name Objectives
extends RefCounted
## Where the active thread wants the salvager to go, for the minimap, the map and the in-world
## marker. A thread stage names its target with "where":
##   "point:<name>"   a named spot in Wick (data/wick_map.json points)
##   "npc:<id>"       a resident, wherever they are (their door if they're indoors)
##   "area:reach"     the first cavern below the Reach gate
##   "area:trunk"     the Trunk chamber; "area:ruin" a cavern with a ruin; "area:<node id>"
## When the target is in another area, the marker points at the exit that leads towards it.

const PLACE_NAMES := {
	"lease_door": "The Lease", "lantern_door": "Lantern House", "exchange_door": "The Exchange",
	"pumphall_door": "Pump hall", "annex_door": "Barnaby's annex", "hesper_door": "Hesper's hut",
	"moss_beds": "Moss beds", "well": "Well", "reach_gate": "Reach gate", "dock": "Dock",
	"farm": "Your plots", "grotto": "The grotto", "board": "Notice board", "odile_door": "Odile's house",
	"commons": "Commons", "pipe_heads": "Pipe-heads", "exchange_counter": "The Exchange",
	"annex_bench": "Barnaby's bench", "lake_view": "The lake",
}


## The first active thread with a target: {title, note, area, cell, label} or {}.
static func current() -> Dictionary:
	for n: Dictionary in Threads.active_notes():
		var d := Threads.def(String(n.id))
		var list: Array = d.get("stages", [])
		var s := Threads.stage(String(n.id))
		if s < 1 or s > list.size():
			continue
		var where := String(list[s - 1].get("where", ""))
		if where == "":
			continue
		var r := resolve(where)
		if r.is_empty():
			continue
		r["title"] = String(n.title)
		r["note"] = String(n.note)
		return r
	return {}


static func resolve(where: String) -> Dictionary:
	var kind := where.get_slice(":", 0)
	var arg := where.get_slice(":", 1)
	var wick_points: Dictionary = Content.wick_map.get("points", {})
	match kind:
		"point":
			if wick_points.has(arg):
				var v: Array = wick_points[arg]
				return {"area": "wick", "cell": Vector2i(int(v[0]), int(v[1])), "label": String(PLACE_NAMES.get(arg, ""))}
		"npc":
			var game := _game()
			if game and GameState.current_area == "wick" and game.npcs.has(arg):
				var npc: Node3D = game.npcs[arg]
				if npc.visible and not npc.indoors:
					return {"area": "wick", "cell": Vector2i(int(floor(npc.position.x)), int(floor(npc.position.z))),
						"label": Society.display_name(arg), "moving": true}
			var home := String(Content.npc(arg).get("home", "commons"))
			if wick_points.has(home):
				var h: Array = wick_points[home]
				return {"area": "wick", "cell": Vector2i(int(h[0]), int(h[1])), "label": Society.display_name(arg)}
		"area":
			var node := _find_node(arg)
			if not node.is_empty():
				return {"area": String(node.id), "cell": Vector2i(-1, -1), "label": String(node.get("name", ""))}
	return {}


static func _find_node(tag: String) -> Dictionary:
	var nodes: Array = GameState.reach_graph.get("nodes", [])
	if nodes.is_empty():
		return {}
	match tag:
		"reach":
			return nodes[0]
		"trunk":
			for n: Dictionary in nodes:
				if bool(n.get("trunk", false)):
					return n
		"deep":
			for n: Dictionary in nodes:
				if String(n.id) == "d1_0":
					return n
		"ruin":
			for n: Dictionary in nodes:
				if bool(n.get("ruin", false)) and int(n.get("tier", 1)) == 1:
					return n
			for n: Dictionary in nodes:
				if bool(n.get("ruin", false)):
					return n
		_:
			for n: Dictionary in nodes:
				if String(n.id) == tag:
					return n
	return {}


## Where, in the current area, to point for objective `o`: {cell, label, leads_to} or {}.
static func local_target(o: Dictionary, area: AreaMap) -> Dictionary:
	if o.is_empty() or area == null:
		return {}
	var goal := String(o.area)
	if goal == area.id:
		var c: Vector2i = o.cell
		if c.x < 0:
			c = area.points.get("hub", Vector2i(area.w / 2, area.d / 2))
		return {"cell": c, "label": String(o.get("label", "")), "here": true}
	var next := next_hop(area.id, goal)
	if next == "":
		return {}
	if area.id == "wick":
		if bool(ReachGen.node_by_id(GameState.reach_graph, next).get("deep", false)):
			var door: Vector2i = area.points.get("pumphall_door", Vector2i(41, 11))
			return {"cell": door, "label": "The Primary Lift", "here": false}
		var gate: Vector2i = area.points.get("reach_gate", Vector2i(44, 15))
		return {"cell": gate, "label": "Reach gate", "here": false}
	for ex: Dictionary in area.exits:
		if String(ex.to) == next:
			var arr: Array = ex.arrive
			var label := "Wick" if next == "wick" else String(ReachGen.node_by_id(GameState.reach_graph, next).get("name", ""))
			return {"cell": Vector2i(int(arr[0]), int(arr[1])), "label": label, "here": false}
	return {}


## The neighbouring area on the shortest open route from `from` to `to` ("" if none).
static func next_hop(from: String, to: String) -> String:
	if from == to:
		return ""
	var adj := {}
	for e: Dictionary in GameState.reach_graph.get("edges", []):
		if not ReachGen.passable(e, GameState.flags):
			continue
		var a := String(e.a)
		var b := String(e.b)
		if not adj.has(a):
			adj[a] = []
		if not adj.has(b):
			adj[b] = []
		adj[a].append(b)
		adj[b].append(a)
	var prev := {from: ""}
	var queue: Array = [from]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		if cur == to:
			break
		for nb: String in adj.get(cur, []):
			if not prev.has(nb):
				prev[nb] = cur
				queue.append(nb)
	if not prev.has(to):
		return ""
	var step := to
	while String(prev[step]) != from:
		step = String(prev[step])
		if step == "":
			return ""
	return step


static func _game() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var s := tree.current_scene
	if s and "npcs" in s:
		return s
	return null
