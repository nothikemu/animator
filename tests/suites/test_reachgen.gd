extends TestCase
## Procedural Reach: determinism, design rules, connectivity.

const SEEDS := [1, 2, 3, 42, 1337, 9001, 271828, 31415]


## The Reach proper: tiers 1-3 below the gate, not the Lower Stations, the Ways or the Unmapped.
static func _reach_only(g: Dictionary) -> Array:
	return (g.nodes as Array).filter(func(n: Dictionary) -> bool:
		return not bool(n.get("deep", false)) and String(n.id) != "ways")


func test_same_seed_same_world() -> void:
	var a := ReachGen.generate_graph(1234)
	var b := ReachGen.generate_graph(1234)
	eq(JSON.stringify(a), JSON.stringify(b), "graph is deterministic")
	var id: String = a.nodes[2].id
	var ca := ReachGen.generate_cavern(1234, a, id)
	var cb := ReachGen.generate_cavern(1234, b, id)
	eq(JSON.stringify(ca.to_dict()), JSON.stringify(cb.to_dict()), "cavern is deterministic")


func test_different_seeds_differ() -> void:
	var names := {}
	for s in SEEDS:
		var g := ReachGen.generate_graph(s)
		var sig := ""
		for n in g.nodes:
			sig += String(n.biome) + String(n.name)
		names[sig] = true
	check(names.size() >= SEEDS.size() - 1, "seeds produce varied worlds (%d distinct of %d)" % [names.size(), SEEDS.size()])


func test_biome_and_ruin_rules() -> void:
	for s in SEEDS:
		var g := ReachGen.generate_graph(s)
		var t1_black := false
		var t2_ember := false
		var trunk := 0
		var ruins := {}
		for n in g.nodes:
			if n.tier == 1 and n.biome == "blackstone":
				t1_black = true
			if n.tier == 2 and n.biome == "ember":
				t2_ember = true
			if n.trunk:
				trunk += 1
				check(n.tier == 3, "trunk on the deepest tier")
			if n.ruin:
				ruins[n.tier] = true
		check(t1_black, "seed %d: tier 1 has a Blackstone cavern" % s)
		check(t2_ember, "seed %d: tier 2 has Ember Vents" % s)
		eq(trunk, 1, "seed %d: exactly one Trunk chamber" % s)
		check(ruins.has(1) and ruins.has(2), "seed %d: a ruin per upper tier" % s)


func test_critical_path_opens_after_the_tremor() -> void:
	for s in SEEDS:
		var g := ReachGen.generate_graph(s)
		var trunk_id := ""
		for n in g.nodes:
			if n.trunk:
				trunk_id = n.id
		var reach := _reach_only(g)
		var before := ReachGen.reachable(g, {})
		check(not before.has(trunk_id), "seed %d: Trunk sealed before the tremor" % s)
		var after := ReachGen.reachable(g, {"tremor_done": true})
		eq(after.size(), reach.size() + 1, "seed %d: every Reach cavern reachable after the tremor" % s)
		eq(before.size(), reach.size(), "seed %d: everything but the Trunk reachable before" % s)
		# The rest of the world opens with the story: the lift, the Knappers, the Heart door, the ending.
		var all_open := ReachGen.reachable(g, {"tremor_done": true, "lift_built": true, "grist_guide": true,
			"ways_open": true, "unmapped_open": true})
		eq(all_open.size(), g.nodes.size() + 1, "seed %d: every place reachable once the story opens it" % s)
		check(all_open.has("sallow") and all_open.has("heart") and all_open.has("ways"), "seed %d: Sallow, the Heart and the Ways reachable" % s)
		check(not ReachGen.reachable(g, {"tremor_done": true, "lift_built": true}).has("heart"), "seed %d: the Heart needs the Knappers" % s)


func test_every_cavern_connects_its_exits() -> void:
	for s in [1, 42, 9001]:
		var g := ReachGen.generate_graph(s)
		for n in g.nodes:
			if n.get("authored", false):
				continue
			var a := ReachGen.generate_cavern(s, g, n.id)
			var astar := a.build_astar()
			var hub: Vector2i = a.points.hub
			check(a.is_walkable(hub.x, hub.y), "seed %d %s: hub walkable" % [s, n.id])
			for ex in a.exits:
				var start := Vector2i(int(ex.arrive[0]), int(ex.arrive[1]))
				check(a.is_walkable(start.x, start.y), "seed %d %s: exit arrival walkable" % [s, n.id])
				var path := astar.get_id_path(start, hub)
				check(path.size() > 0, "seed %d %s: exit to %s reaches the hub" % [s, n.id, ex.to])
			if n.ruin or n.trunk:
				check(a.points.has("ruin"), "seed %d %s: ruin placed" % [s, n.id])
				var rp: Vector2i = a.points.ruin
				var path := astar.get_id_path(hub, rp)
				check(path.size() > 0, "seed %d %s: ruin reachable" % [s, n.id])


func test_heights_are_climbable() -> void:
	var g := ReachGen.generate_graph(5)
	for n in g.nodes:
		if n.get("authored", false):
			continue
		var a := ReachGen.generate_cavern(5, g, n.id)
		for z in a.d:
			for x in a.w:
				if not a.is_walkable(x, z):
					continue
				for dd in [Vector2i.RIGHT, Vector2i.DOWN]:
					var nx: int = x + dd.x
					var nz: int = z + dd.y
					if a.is_walkable(nx, nz):
						check(absi(a.h_at(x, z) - a.h_at(nx, nz)) <= AreaMap.MAX_CLIMB,
							"%s: step too tall at %d,%d" % [n.id, x, z])


func test_unmapped_goes_on() -> void:
	var g := ReachGen.generate_graph(77)
	ReachGen.ensure_unmapped(g, 6)
	var deepest := 0
	for n: Dictionary in g.nodes:
		deepest = maxi(deepest, int(n.get("unmapped", 0)))
	eq(deepest, 7, "the Unmapped always has one more station below the deepest visited")
	var a := ReachGen.generate_cavern(77, g, "u7")
	check(a.points.has("ruin"), "an Unmapped station has a ruin to read")
	var again := ReachGen.generate_graph(77)
	ReachGen.ensure_unmapped(again, 6)
	eq(JSON.stringify(g), JSON.stringify(again), "the Unmapped is deterministic per seed")
