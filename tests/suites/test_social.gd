extends TestCase
## Rule language, relationships, memory, schedules.


func test_condition_parsing_and_evaluation() -> void:
	var ctx := Conditions.DictContext.new({"flag.valve_open": true, "trust.barnaby": 25.0,
		"phase": "hush", "thread.dry_well": 2, "pollution": 0.4, "item.moss_tea": 0})
	check(Conditions.check(["flag:valve_open"], ctx), "truthy flag")
	check(not Conditions.check(["!flag:valve_open"], ctx), "negation")
	check(Conditions.check(["trust:barnaby>=20"], ctx), "numeric >=")
	check(not Conditions.check(["trust:barnaby>30"], ctx), "numeric >")
	check(Conditions.check(["phase:dimming|hush"], ctx), "membership")
	check(not Conditions.check(["phase:wake"], ctx), "membership miss")
	check(Conditions.check(["thread:dry_well=2"], ctx), "equality")
	check(Conditions.check(["pollution>0.3", "!item:moss_tea"], ctx), "zero items is falsey")
	check(not Conditions.check(["flag:unknown_flag"], ctx), "unknown keys are false")


func test_specificity_scoring() -> void:
	var ctx := Conditions.DictContext.new({"met.barnaby": true, "phase": "hush"})
	eq(Conditions.score([], ctx), 0, "empty rule")
	eq(Conditions.score(["met:barnaby"], ctx), 1, "one clause")
	eq(Conditions.score(["met:barnaby", "phase:hush"], ctx), 2, "two clauses")
	eq(Conditions.score(["met:barnaby", "phase:wake"], ctx), -1, "failing rule")


func test_relationship_axes_are_bounded_with_diminishing_returns() -> void:
	var s := NpcSocial.new("x")
	for i in 50:
		s.change("trust", 20.0)
	check(s.get_axis("trust") <= 100.0, "capped")
	var s2 := NpcSocial.new("y")
	s2.change("respect", 10.0)
	var first := s2.get_axis("respect")
	s2.axes["respect"] = 90.0
	s2.change("respect", 10.0)
	check(s2.get_axis("respect") - 90.0 < first, "gains shrink near the top")


func test_memories_fade_unless_lasting() -> void:
	var s := NpcSocial.new("x")
	s.remember("small", 1.0, 0.2, 1)
	s.remember("big", 6.0, -0.8, 1)
	s.remember("forever", 1.0, 1.0, 1, true)
	for i in 6:
		s.decay()
	check(not s.has_memory("small"), "minor memory forgotten")
	check(s.has_memory("big"), "important memory still there after 6 days")
	check(s.has_memory("forever"), "lasting memory kept")


func test_describe_mixes_axes() -> void:
	var s := NpcSocial.new("b")
	s.met = true
	s.axes.respect = 50.0
	s.axes.trust = -5.0
	var d := s.describe("Barnaby")
	check(d.contains("respects your work"), "mentions respect: " + d)
	check(d.contains("doesn't trust you yet"), "mentions the missing trust: " + d)


func test_schedule_resolution_and_overrides() -> void:
	var sched := [
		{"from": "06:00", "to": "12:00", "at": "a", "do": "x"},
		{"from": "22:00", "to": "02:00", "at": "night", "do": "rounds"},
		{"from": "06:00", "to": "12:00", "at": "well", "do": "crank", "when": ["!flag:well_fixed"]},
	]
	var ctx := Conditions.DictContext.new({})
	eq(Schedule.resolve(sched, 7 * 60, ctx).at, "well", "override applies while the well is broken")
	ctx.facts["flag.well_fixed"] = true
	eq(Schedule.resolve(sched, 7 * 60, ctx).at, "a", "normal block after the fix")
	eq(Schedule.resolve(sched, 23 * 60, ctx).at, "night", "block wrapping past midnight (before)")
	eq(Schedule.resolve(sched, 60, ctx).at, "night", "block wrapping past midnight (after)")
	eq(Schedule.resolve(sched, 15 * 60, ctx).at, "home", "default when nothing matches")


func test_every_npc_schedule_has_valid_places() -> void:
	var points: Dictionary = Content.wick_map.get("points", {})
	for npc in Content.npcs:
		for b in Content.npcs[npc].schedule:
			var at := String(b.at)
			check(at == "away" or at == "home" or points.has(at), "%s schedule uses unknown place '%s'" % [npc, at])
		check(points.has(String(Content.npcs[npc].home)), "%s home is a known point" % npc)
