class_name ReachGen
extends RefCounted
## Deterministic generator for the Reach: a graph of caverns below Wick, and the layout of
## each cavern. Same seed => same world. Runtime changes (mined nodes, the tremor) are
## stored as deltas in the save, never by regenerating differently.
##
## Design rules enforced here:
##  * three depth tiers; tier 1 is reachable from Wick; the Trunk chamber is on the deepest tier
##  * every node is reachable once the sealed Trunk passage opens (critical path guaranteed)
##  * biome follows depth/heat/moisture; at least one Blackstone (tier 1) and one Ember (tier 2)
##  * exits are always connected by walkable floor; no orphan pockets
##  * one ruin vignette per tier (environmental storytelling + lore)

const CAVERN_MIN := Vector2i(34, 24)

const NAME_PARTS := {
	"fringe": [["Lantern", "Pale", "Hush", "Willow", "Drowse", "Spindle"], ["Hollow", "Mere", "Grotto", "Bower", "Reach"]],
	"blackstone": [["Rust", "Cinder", "Slag", "Iron", "Knapper", "Gallows"], ["Cut", "Gallery", "Seam", "Works", "Shelf"]],
	"ember": [["Ember", "Kiln", "Smoulder", "Bellows", "Ash"], ["Vents", "Throat", "Flue", "Hearth"]],
	"sump": [["Cold", "Drowned", "Low", "Gloam", "Still"], ["Sump", "Cistern", "Sink", "Basin"]],
}


static func rng_for(seed_value: int, tag: String, index: int = 0) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed_value, tag, index])
	return r


# --- Graph -------------------------------------------------------------------------------

static func generate_graph(seed_value: int) -> Dictionary:
	var rng := rng_for(seed_value, "graph")
	var nodes: Array = []
	var tiers := [3, 2 + rng.randi_range(0, 1), 2]
	for t in tiers.size():
		for k in tiers[t]:
			nodes.append({
				"id": "r%d_%d" % [t + 1, k], "tier": t + 1, "index": nodes.size(),
				"heat": clampf(rng.randf() * 0.65 + 0.18 * t, 0.0, 1.0),
				"moisture": rng.randf(), "biome": "", "name": "", "ruin": false, "trunk": false,
			})
	# Biomes by rule.
	for n in nodes:
		if n.tier == 3:
			n.biome = "sump"
		elif n.heat > 0.6 and n.tier >= 2:
			n.biome = "ember"
		elif n.moisture > 0.6 and n.tier == 1:
			n.biome = "fringe"
		else:
			n.biome = "blackstone"
	_ensure_biome(nodes, 1, "blackstone", "moisture", false)
	_ensure_biome(nodes, 2, "ember", "heat", true)
	# Trunk chamber: first tier-3 node. Ruins: one per tier.
	var t3 := _tier(nodes, 3)
	t3[0].trunk = true
	for t in [1, 2]:
		var tn := _tier(nodes, t)
		tn[rng.randi_range(0, tn.size() - 1)].ruin = true
	t3[1].ruin = true
	# Names (unique).
	var used := {}
	for n in nodes:
		var parts: Array = NAME_PARTS[n.biome]
		var name := ""
		for _attempt in 12:
			name = "%s %s" % [parts[0][rng.randi_range(0, parts[0].size() - 1)],
				parts[1][rng.randi_range(0, parts[1].size() - 1)]]
			if not used.has(name):
				break
		if n.trunk:
			name = "The Trunk Chamber"
		used[name] = true
		n.name = name
	# Edges.
	var edges: Array = []
	var t1 := _tier(nodes, 1)
	edges.append({"a": "wick", "b": t1[0].id, "kind": "gate"})
	for t in [1, 2, 3]:
		var tn := _tier(nodes, t)
		for k in tn.size() - 1:
			if tn[k + 1].trunk or tn[k].trunk:
				continue
			edges.append({"a": tn[k].id, "b": tn[k + 1].id, "kind": "passage"})
	for t in [2, 3]:
		var lower := _tier(nodes, t)
		var upper := _tier(nodes, t - 1)
		for n in lower:
			if n.trunk:
				continue
			var up: Dictionary = upper[rng.randi_range(0, upper.size() - 1)]
			edges.append({"a": up.id, "b": n.id, "kind": "descent"})
	# The Trunk chamber is sealed until the tremor opens it from the other sump.
	var sump_open: Dictionary = t3[1]
	edges.append({"a": sump_open.id, "b": t3[0].id, "kind": "sealed"})
	# One shortcut that the tremor will collapse (never on the only route anywhere).
	var shortcut := {"a": t1[t1.size() - 1].id, "b": _tier(nodes, 2)[0].id, "kind": "collapsible"}
	if not _has_edge(edges, shortcut.a, shortcut.b):
		edges.append(shortcut)
	return {"seed": seed_value, "nodes": nodes, "edges": edges}


static func _tier(nodes: Array, t: int) -> Array:
	var out: Array = []
	for n in nodes:
		if n.tier == t:
			out.append(n)
	return out


static func _ensure_biome(nodes: Array, tier: int, biome: String, key: String, highest: bool) -> void:
	var tn := _tier(nodes, tier)
	for n in tn:
		if n.biome == biome:
			return
	var best: Dictionary = tn[0]
	for n in tn:
		if (highest and n[key] > best[key]) or (not highest and n[key] < best[key]):
			best = n
	best.biome = biome


static func _has_edge(edges: Array, a: String, b: String) -> bool:
	for e in edges:
		if (e.a == a and e.b == b) or (e.a == b and e.b == a):
			return true
	return false


static func node_by_id(graph: Dictionary, id: String) -> Dictionary:
	for n in graph.nodes:
		if n.id == id:
			return n
	return {}


## Edges usable given world flags (tremor opens "sealed", collapses "collapsible").
static func passable(edge: Dictionary, flags: Dictionary) -> bool:
	var tremor := bool(flags.get("tremor_done", false))
	match String(edge.kind):
		"sealed":
			return tremor
		"collapsible":
			return not tremor
	return true


static func neighbours(graph: Dictionary, id: String, flags: Dictionary) -> Array:
	var out: Array = []
	for e in graph.edges:
		if not passable(e, flags):
			continue
		if e.a == id:
			out.append(e.b)
		elif e.b == id:
			out.append(e.a)
	return out


static func reachable(graph: Dictionary, flags: Dictionary) -> Dictionary:
	var seen := {"wick": true}
	var stack := ["wick"]
	while not stack.is_empty():
		var cur: String = stack.pop_back()
		for nb in neighbours(graph, cur, flags):
			if not seen.has(nb):
				seen[nb] = true
				stack.append(nb)
	return seen


# --- Caverns ------------------------------------------------------------------------------

static func generate_cavern(seed_value: int, graph: Dictionary, node_id: String) -> AreaMap:
	var node := node_by_id(graph, node_id)
	var rng := rng_for(seed_value, "cavern", int(node.get("index", 0)))
	var w := CAVERN_MIN.x + rng.randi_range(0, 6)
	var d := CAVERN_MIN.y + rng.randi_range(0, 4)
	var a := AreaMap.new(w, d)
	a.id = node_id
	a.biome = String(node.biome)
	a.meta = {"name": node.name, "tier": node.tier, "trunk": node.trunk, "ruin": node.ruin}
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.09
	noise.fractal_octaves = 2

	# 1. Cellular automaton walls.
	var wall := PackedByteArray()
	wall.resize(w * d)
	for z in d:
		for x in w:
			var border := x == 0 or z == 0 or x == w - 1 or z == d - 1
			wall[z * w + x] = 1 if border or rng.randf() < 0.46 else 0
	for _iter in 4:
		var nxt := wall.duplicate()
		for z in range(1, d - 1):
			for x in range(1, w - 1):
				var c := 0
				for dz in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						c += wall[(z + dz) * w + x + dx]
				nxt[z * w + x] = 1 if c >= 5 else 0
		wall = nxt

	# 2. Exits on the borders, one per incident edge. Upward links west/north, deeper east/south.
	var protected := {}
	var exit_list: Array = []
	var incident: Array = []
	for e in graph.edges:
		if e.a == node_id or e.b == node_id:
			incident.append(e)
	var sides_used := {}
	for e in incident:
		var other: String = e.b if e.a == node_id else e.a
		var other_tier := 0 if other == "wick" else int(node_by_id(graph, other).tier)
		var side := "west" if other_tier < int(node.tier) else ("east" if other_tier > int(node.tier) else "south")
		if other_tier == int(node.tier):
			side = "north" if sides_used.has("south") else "south"
		sides_used[side] = int(sides_used.get(side, 0)) + 1
		var cell := _exit_cell(side, int(sides_used[side]), w, d, rng)
		var inward := _inward(side)
		for k in 5:
			var c: Vector2i = cell + inward * k
			for off in [Vector2i.ZERO, Vector2i(inward.y, inward.x), -Vector2i(inward.y, inward.x)]:
				var cc: Vector2i = c + off
				if cc.x > 0 and cc.y > 0 and cc.x < w - 1 and cc.y < d - 1:
					wall[cc.y * w + cc.x] = 0
					protected[cc] = true
		wall[cell.y * w + cell.x] = 0
		protected[cell] = true
		exit_list.append({"x": cell.x, "z": cell.y, "to": other, "kind": e.kind, "side": side,
			"arrive": [cell.x + inward.x * 2, cell.y + inward.y * 2]})

	# 3. Connect every exit to the largest open region by carving tunnels.
	var hub := _largest_region_center(wall, w, d)
	if hub == Vector2i(-1, -1):
		hub = Vector2i(w / 2, d / 2)
		wall[hub.y * w + hub.x] = 0
	for ex in exit_list:
		_carve(wall, w, d, Vector2i(int(ex.arrive[0]), int(ex.arrive[1])), hub, rng, protected)
	# Remove orphan pockets not connected to the hub.
	var reach := _flood(wall, w, d, hub)
	for z in d:
		for x in w:
			if wall[z * w + x] == 0 and not reach.has(Vector2i(x, z)):
				var size := _flood(wall, w, d, Vector2i(x, z)).size()
				if size >= 10:
					_carve(wall, w, d, Vector2i(x, z), hub, rng, protected)
					reach = _flood(wall, w, d, hub)
				else:
					for c in _flood(wall, w, d, Vector2i(x, z)):
						wall[c.y * w + c.x] = 1

	# 4. Heights: gentle terraces from noise, neighbours differ by at most one level.
	for z in d:
		for x in w:
			var i := z * w + x
			if wall[i] == 1:
				a.height[i] = AreaMap.WALL_LEVEL
			else:
				var n := noise.get_noise_2d(x, z)
				a.height[i] = clampi(int(floor((n + 0.6) * 2.2)), 0, 3)
	for _pass in 6:
		for z in d:
			for x in w:
				var i := z * w + x
				if a.height[i] >= AreaMap.WALL_LEVEL:
					continue
				var lowest := 99
				for dd in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
					var nx: int = x + dd.x
					var nz: int = z + dd.y
					if a.inside(nx, nz) and a.height[nz * w + nx] < AreaMap.WALL_LEVEL:
						lowest = mini(lowest, a.height[nz * w + nx])
				if lowest < 99 and a.height[i] > lowest + 1:
					a.height[i] = lowest + 1
	for c in protected:
		var pc: Vector2i = c
		if a.height[pc.y * w + pc.x] < AreaMap.WALL_LEVEL:
			pass

	# 5. Surface materials and biome features.
	var floor_mat: String = {"fringe": "moss_floor", "blackstone": "blackstone", "ember": "ash", "sump": "mud"}[a.biome]
	for z in d:
		for x in w:
			var i := z * w + x
			a.mat[i] = "rock" if wall[i] == 1 else floor_mat
			if wall[i] == 0 and rng.randf() < 0.12:
				a.mat[i] = {"fringe": "dirt", "blackstone": "gravel", "ember": "basalt", "sump": "stone"}[a.biome]
	if a.biome == "sump":
		# Low ground floods, except on the guaranteed path.
		var path := _path_cells(a, exit_list, hub)
		for z in d:
			for x in w:
				var i := z * w + x
				if wall[i] == 0 and a.height[i] == 0 and noise.get_noise_2d(x * 1.7, z * 1.7) < -0.12 and not path.has(Vector2i(x, z)):
					a.height[i] = AreaMap.WATER_LEVEL
					a.mat[i] = "water"
	if a.biome == "ember":
		var vents := 0
		for _k in 60:
			var x := rng.randi_range(2, w - 3)
			var z := rng.randi_range(2, d - 3)
			if wall[z * w + x] == 0 and not protected.has(Vector2i(x, z)) and vents < 5:
				a.mat[z * w + x] = "vent"
				a.props.append({"type": "heat_vent", "x": x, "z": z})
				a.lights.append({"x": x + 0.5, "z": z + 0.5, "y": 0.6, "color": "ember", "energy": 2.2, "range": 5.0, "kind": "vent"})
				vents += 1

	# Critical paths (exit -> hub) are now final: nothing that blocks may be placed on them.
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			protected[hub + Vector2i(dx, dz)] = true
	for c in _path_cells(a, exit_list, hub):
		protected[c] = true

	# 6. Exits become doorway props (sealed ones blocked by rubble until the tremor).
	for ex in exit_list:
		a.exits.append(ex)
		a.points["from_" + String(ex.to)] = Vector2i(int(ex.arrive[0]), int(ex.arrive[1]))
		if ex.kind == "sealed" or ex.kind == "collapsible":
			a.props.append({"type": "rubble", "x": ex.x, "z": ex.z, "edge": ex.kind, "to": ex.to})

	# 7. Resources along walls.
	var wall_adjacent: Array = []
	for z in range(1, d - 1):
		for x in range(1, w - 1):
			if wall[z * w + x] == 0 and not protected.has(Vector2i(x, z)) and a.height[z * w + x] >= 0:
				var near_wall := false
				for dd in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
					if wall[(z + dd.y) * w + x + dd.x] == 1:
						near_wall = true
				if near_wall:
					wall_adjacent.append(Vector2i(x, z))
	_shuffle(wall_adjacent, rng)
	var table: Array = {
		"fringe": [["glowglass_node", "glowglass", 2], ["moss_patch", "moss_fiber", 4], ["moss_patch", "moss_fiber", 4], ["blackstone_node", "blackstone", 4]],
		"blackstone": [["blackstone_node", "blackstone", 6], ["blackstone_node", "blackstone", 6], ["scrap_pile", "brass_scrap", 4], ["glowglass_node", "glowglass", 3]],
		"ember": [["thermal_node", "thermal_ore", 6], ["ember_crystal", "ember_resin", 3], ["emberroot_wild", "emberroot_seed", 2], ["thermal_node", "thermal_ore", 5], ["blackstone_node", "blackstone", 4]],
		"sump": [["bellcap_wild", "bellcap_spore", 2], ["scrap_pile", "brass_scrap", 6], ["glowglass_node", "glowglass", 4], ["moss_patch", "moss_fiber", 3]],
	}[a.biome]
	var count := 8 + rng.randi_range(0, 4)
	for k in mini(count, wall_adjacent.size()):
		var c: Vector2i = wall_adjacent[k]
		var entry: Array = table[k % table.size()]
		a.resources.append({"id": "%s_res%d" % [node_id, k], "type": entry[0], "x": c.x, "z": c.y,
			"item": entry[1], "n": int(entry[2]) + rng.randi_range(0, 2)})
		a.blocked[c.y * w + c.x] = 1

	# 8. Ambient lights (glow crystals / fungus) — capped for performance.
	var light_color: String = {"fringe": "glow", "blackstone": "amber", "ember": "ember", "sump": "violet"}[a.biome]
	var floor_cells: Array = []
	for z in d:
		for x in w:
			if a.is_walkable(x, z) and not protected.has(Vector2i(x, z)):
				floor_cells.append(Vector2i(x, z))
	_shuffle(floor_cells, rng)
	var nl := 0
	for c in floor_cells:
		if nl >= 5:
			break
		var too_close := false
		for l in a.lights:
			if Vector2(float(l.x), float(l.z)).distance_to(Vector2(c.x + 0.5, c.y + 0.5)) < 7.0:
				too_close = true
		if too_close:
			continue
		a.lights.append({"x": c.x + 0.5, "z": c.y + 0.5, "y": 1.2, "color": light_color, "energy": 1.6, "range": 6.5, "kind": "ambient"})
		a.props.append({"type": {"fringe": "glowroot", "blackstone": "work_lamp", "ember": "ember_crystal", "sump": "pale_fungus"}[a.biome], "x": c.x, "z": c.y})
		a.blocked[c.y * w + c.x] = 1
		nl += 1
	# Decorative clutter (non-blocking).
	var deco: Array = {"fringe": ["moss_tuft", "glowroot_small", "mushroom"], "blackstone": ["rubble_small", "rail", "crate_broken"],
		"ember": ["ash_pile", "cinder_rock"], "sump": ["pale_fungus_small", "reed", "drip_rock"]}[a.biome]
	for k in mini(18, floor_cells.size()):
		var c: Vector2i = floor_cells[floor_cells.size() - 1 - k]
		if a.blocked[c.y * w + c.x] == 0:
			a.props.append({"type": deco[k % deco.size()], "x": c.x, "z": c.y, "deco": true})

	# 9. Ruin vignette.
	if node.ruin or node.trunk:
		_place_ruin(a, node, rng, protected, hub)

	a.points["hub"] = hub
	_ensure_connected(a, exit_list, hub)
	return a


## Safety net: if anything still separates an exit or the ruin from the hub, clear the
## blocking props along a direct line. Generation should never need this, but a guarantee
## beats a probability.
static func _ensure_connected(a: AreaMap, exits: Array, hub: Vector2i) -> void:
	var targets: Array = []
	for ex in exits:
		targets.append(Vector2i(int(ex.arrive[0]), int(ex.arrive[1])))
	if a.points.has("ruin"):
		targets.append(a.points.ruin)
	for t: Vector2i in targets:
		var astar := a.build_astar()
		if not astar.get_id_path(t, hub).is_empty():
			continue
		var c := t
		var guard := 0
		while c != hub and guard < 200:
			guard += 1
			if a.inside(c.x, c.y) and a.blocked[c.y * a.w + c.x] == 1:
				a.blocked[c.y * a.w + c.x] = 0
				a.props = a.props.filter(func(p: Dictionary) -> bool:
					return not (int(p.x) == c.x and int(p.z) == c.y and not p.has("size")))
				a.resources = a.resources.filter(func(r: Dictionary) -> bool:
					return not (int(r.x) == c.x and int(r.z) == c.y))
			if a.h_at(c.x, c.y) >= AreaMap.WALL_LEVEL or a.h_at(c.x, c.y) == AreaMap.WATER_LEVEL:
				a.height[c.y * a.w + c.x] = clampi(a.h_at(hub.x, hub.y), 0, 3)
				a.mat[c.y * a.w + c.x] = "gravel"
			if c.x != hub.x:
				c.x += signi(hub.x - c.x)
			else:
				c.y += signi(hub.y - c.y)


static func _exit_cell(side: String, nth: int, w: int, d: int, rng: RandomNumberGenerator) -> Vector2i:
	var t := 0.3 + 0.4 * rng.randf() if nth == 1 else 0.75
	match side:
		"west": return Vector2i(0, int(d * t))
		"east": return Vector2i(w - 1, int(d * t))
		"north": return Vector2i(int(w * t), 0)
	return Vector2i(int(w * t), d - 1)


static func _inward(side: String) -> Vector2i:
	match side:
		"west": return Vector2i.RIGHT
		"east": return Vector2i.LEFT
		"north": return Vector2i.DOWN
	return Vector2i.UP


static func _flood(wall: PackedByteArray, w: int, d: int, start: Vector2i) -> Dictionary:
	var seen := {}
	if wall[start.y * w + start.x] == 1:
		return seen
	var stack: Array[Vector2i] = [start]
	seen[start] = true
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for dd in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = c + dd
			if n.x >= 0 and n.y >= 0 and n.x < w and n.y < d and wall[n.y * w + n.x] == 0 and not seen.has(n):
				seen[n] = true
				stack.append(n)
	return seen


static func _largest_region_center(wall: PackedByteArray, w: int, d: int) -> Vector2i:
	var seen := {}
	var best := {}
	for z in d:
		for x in w:
			var c := Vector2i(x, z)
			if wall[z * w + x] == 0 and not seen.has(c):
				var region := _flood(wall, w, d, c)
				for k in region:
					seen[k] = true
				if region.size() > best.size():
					best = region
	if best.is_empty():
		return Vector2i(-1, -1)
	var sum := Vector2.ZERO
	for c in best:
		sum += Vector2(c)
	var mean := sum / best.size()
	var closest := Vector2i(-1, -1)
	var cd := INF
	for c in best:
		var dist := Vector2(c).distance_squared_to(mean)
		if dist < cd:
			cd = dist
			closest = c
	return closest


## Carves a slightly wandering 2-wide tunnel from a to b.
static func _carve(wall: PackedByteArray, w: int, d: int, a: Vector2i, b: Vector2i,
		rng: RandomNumberGenerator, protected: Dictionary) -> void:
	var c := a
	var guard := 0
	while c != b and guard < 400:
		guard += 1
		for off in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN]:
			var cc: Vector2i = c + off
			if cc.x > 0 and cc.y > 0 and cc.x < w - 1 and cc.y < d - 1:
				wall[cc.y * w + cc.x] = 0
				protected[cc] = true
		var dx := signi(b.x - c.x)
		var dz := signi(b.y - c.y)
		if dx != 0 and (dz == 0 or rng.randf() < 0.55):
			c.x += dx
		elif dz != 0:
			c.y += dz
		if rng.randf() < 0.12:
			c.y = clampi(c.y + rng.randi_range(-1, 1), 1, d - 2)
	wall[b.y * w + b.x] = 0


static func _path_cells(a: AreaMap, exits: Array, hub: Vector2i) -> Dictionary:
	var astar := a.build_astar()
	var out := {}
	for ex in exits:
		var p := astar.get_id_path(Vector2i(int(ex.arrive[0]), int(ex.arrive[1])), hub)
		for c in p:
			out[c] = true
			for dd in [Vector2i.RIGHT, Vector2i.DOWN]:
				out[c + dd] = true
	return out


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = t


static func _place_ruin(a: AreaMap, node: Dictionary, rng: RandomNumberGenerator,
		protected: Dictionary, hub: Vector2i) -> void:
	# Find a flat open rectangle near the hub for the vignette.
	var best := Vector2i(-1, -1)
	var best_d := INF
	for z in range(2, a.d - 7):
		for x in range(2, a.w - 8):
			var ok := true
			var base := a.h_at(x, z)
			for dz in 5:
				for dx in 6:
					var cx := x + dx
					var cz := z + dz
					if not a.is_walkable(cx, cz) or a.h_at(cx, cz) != base or protected.has(Vector2i(cx, cz)):
						ok = false
						break
				if not ok:
					break
			if ok:
				var dist := Vector2(x + 3, z + 2).distance_to(Vector2(hub))
				if dist < best_d:
					best_d = dist
					best = Vector2i(x, z)
	if best.x < 0:
		best = Vector2i(clampi(hub.x - 3, 1, a.w - 7), clampi(hub.y - 2, 1, a.d - 6))
	var kind := "trunk" if node.trunk else ("crew_post_%d" % int(node.tier))
	a.props.append({"type": "ruin", "variant": kind, "x": best.x, "z": best.y, "size": [6, 5]})
	a.points["ruin"] = best + Vector2i(3, 2)
	# Walls on three sides of the ruin (back + sides), leaving the front open.
	for dx in 6:
		_ruin_block(a, best.x + dx, best.y, "brick_wall")
	for dz in range(1, 4):
		_ruin_block(a, best.x, best.y + dz, "brick_wall")
		_ruin_block(a, best.x + 5, best.y + dz, "brick_wall")
	if node.trunk:
		a.props.append({"type": "trunk_valve_housing", "x": best.x + 2, "z": best.y + 1, "size": [2, 1], "block": true})
		a.blocked[(best.y + 1) * a.w + best.x + 2] = 1
		a.blocked[(best.y + 1) * a.w + best.x + 3] = 1
		a.resources.append({"id": "%s_coil" % a.id, "type": "story_cache", "x": best.x + 4, "z": best.y + 2,
			"item": "governor_coil", "n": 1, "story": true})
		# Wren's camp: a bedroll and cup by the valve, and her work lamp, still burning.
		a.props.append({"type": "bedroll", "x": best.x + 1, "z": best.y + 3})
		a.props.append({"type": "work_lamp", "x": best.x + 1, "z": best.y + 1, "block": true})
		a.blocked[(best.y + 1) * a.w + best.x + 1] = 1
	else:
		a.props.append({"type": "broken_machine", "x": best.x + 2, "z": best.y + 1, "size": [2, 1], "block": true})
		a.blocked[(best.y + 1) * a.w + best.x + 2] = 1
		a.blocked[(best.y + 1) * a.w + best.x + 3] = 1
		a.resources.append({"id": "%s_scrap" % a.id, "type": "scrap_pile", "x": best.x + 1, "z": best.y + 3,
			"item": "brass_scrap", "n": 5})
	a.resources.append({"id": "%s_lore" % a.id, "type": "lore_page", "x": best.x + 3, "z": best.y + 3,
		"item": "", "n": 0, "lore": "tier%d" % int(node.tier) if not node.trunk else "trunk"})
	for r in a.resources:
		if r.id.begins_with(a.id + "_coil") or r.id.begins_with(a.id + "_scrap") or r.id.begins_with(a.id + "_lore"):
			a.blocked[int(r.z) * a.w + int(r.x)] = 1


static func _ruin_block(a: AreaMap, x: int, z: int, type: String) -> void:
	if not a.inside(x, z):
		return
	a.props.append({"type": type, "x": x, "z": z, "block": true})
	a.blocked[z * a.w + x] = 1
