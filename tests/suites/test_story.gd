extends TestCase
## Narrative content: a linter over every rule and effect in the data, plus a scripted walk
## through the first day's main path using the real systems.

const VALUE_KINDS := ["flag", "met", "trust", "respect", "affection", "resentment", "fear", "shared",
	"mem", "mood", "thread", "item", "money", "deed", "tool", "day", "hour", "minute", "phase",
	"breath", "place", "area", "view", "recipe", "lore", "discovered", "market_day", "talked",
	"gifted", "seen_places", "weekday", "since", "gear", "depth", "pressure_ready", "air_ready", "votes_yes",
	# Sim facts
	"pollution", "pollution_farm", "cistern", "town_water", "noise_lane", "exhale", "planted",
	"well_flowing", "fissure_sealed", "power", "leaks", "machine", "running", "air_sour_hesper",
	"air_sour_barnaby", "air_sour_odile", "air_sour_mags"]
const EFFECT_KINDS := ["flag", "give", "take", "learn", "unlock", "tool", "thread", "event", "deed",
	"met", "mem", "toast", "caption", "notice", "discover", "trust", "respect", "affection",
	"resentment", "fear", "shared"]


func before_each() -> void:
	GameState.new_game(4242, "Tester")
	Clock.start(1, 7 * 60)
	Sim.new_world(4242)
	Society.reset()
	Economy.reset()
	Threads.reset()
	Director.reset(4242)
	Dialogue.reset()


func _clause_ok(clause: String) -> String:
	var p := Conditions.parse(clause)
	var key := String(p.key)
	var dot := key.find(".")
	var kind := key.substr(0, dot) if dot >= 0 else key
	if not VALUE_KINDS.has(kind):
		return "unknown condition kind '%s' in '%s'" % [kind, clause]
	if kind == "running" or kind == "machine":
		var m := key.substr(dot + 1)
		if not Content.machines.has(m):
			return "unknown machine '%s' in '%s'" % [m, clause]
	if kind == "item" and not Content.items.has(key.substr(dot + 1)):
		return "unknown item in '%s'" % clause
	if kind == "thread" and not Content.threads.has(key.substr(dot + 1)):
		return "unknown thread in '%s'" % clause
	if (kind in NpcSocial.AXES or kind == "met") and not Content.npcs.has(key.substr(dot + 1)):
		return "unknown npc in '%s'" % clause
	return ""


func _effect_ok(e: String) -> String:
	e = e.strip_edges()
	if e.begins_with("!flag:") or e.begins_with("money"):
		return ""
	var colon := e.find(":")
	var kind := e.substr(0, colon) if colon >= 0 else e
	var arg := e.substr(colon + 1) if colon >= 0 else ""
	if not EFFECT_KINDS.has(kind):
		return "unknown effect kind '%s' in '%s'" % [kind, e]
	if kind in ["give", "take"]:
		var it := arg.split("*")[0]
		if not Content.items.has(it):
			return "unknown item '%s' in '%s'" % [it, e]
	if kind == "event" and not Content.events.has(arg):
		return "unknown event '%s'" % arg
	if kind == "thread" and not Content.threads.has(arg.split("=")[0]):
		return "unknown thread in '%s'" % e
	if kind in NpcSocial.AXES:
		var at := maxi(arg.rfind("+"), arg.rfind("-"))
		if at <= 0 or not Content.npcs.has(arg.substr(0, at)):
			return "bad axis effect '%s'" % e
	if kind == "mem" and not Content.npcs.has(arg.split(":")[0]):
		return "unknown npc in '%s'" % e
	if kind == "tool" and not ["hands", "tiller", "can", "hammer", "wrench", "glass"].has(arg):
		return "unknown tool '%s'" % arg
	return ""


func _lint_rules(rules: Variant, where: String) -> void:
	if rules == null:
		return
	for c in (rules if rules is Array else [rules]):
		var err := _clause_ok(String(c))
		check(err == "", "%s: %s" % [where, err])


func _lint_effects(effects: Variant, where: String) -> void:
	if effects == null:
		return
	for e in (effects if effects is Array else [effects]):
		var err := _effect_ok(String(e))
		check(err == "", "%s: %s" % [where, err])


func test_dialogue_content_lints_clean() -> void:
	for npc in Content.dialogue:
		var d: Dictionary = Content.dialogue[npc]
		# "_name" files are things you talk to (the telegraph, the archive, the Bellows console).
		check(Content.npcs.has(npc) or npc.begins_with("_"), "dialogue for unknown npc %s" % npc)
		for line: Dictionary in d.get("lines", []):
			var where := "%s/%s" % [npc, line.get("id", "?")]
			_lint_rules(line.get("when"), where)
			_lint_effects(line.get("do"), where)
			if line.has("convo"):
				check(d.get("convos", {}).has(String(line.convo)), "%s: missing convo %s" % [where, line.convo])
			if line.has("open"):
				var target := String(line.open).split(":")
				check(target[0] != "shop" or Content.markets.has(target[1]), "%s: unknown market %s" % [where, line.open])
		for cid in d.get("convos", {}):
			var labels := {}
			for n: Dictionary in d.convos[cid]:
				if n.has("label"):
					labels[String(n.label)] = true
			for n: Dictionary in d.convos[cid]:
				var where := "%s/%s" % [npc, cid]
				_lint_rules(n.get("when"), where)
				_lint_rules(n.get("if"), where)
				_lint_effects(n.get("do"), where)
				if n.has("goto"):
					check(String(n.goto) == "end" or labels.has(String(n.goto)), "%s: bad goto %s" % [where, n.goto])
				for c: Dictionary in n.get("choice", []):
					_lint_rules(c.get("when"), where)
					_lint_effects(c.get("do"), where)
					if c.has("goto"):
						check(String(c.goto) == "end" or labels.has(String(c.goto)), "%s: bad choice goto %s" % [where, c.goto])
				if n.has("who"):
					var who := String(n.who)
					check(who in ["narrator", "player"] or Content.npcs.has(who), "%s: unknown speaker %s" % [where, who])


func test_threads_and_events_lint_clean() -> void:
	for id in Content.threads:
		var t: Dictionary = Content.threads[id]
		_lint_rules(t.get("start"), "thread %s" % id)
		var stages: Array = t.get("stages", [])
		check(not stages.is_empty(), "thread %s has stages" % id)
		var has_done := false
		for i in stages.size():
			var st: Dictionary = stages[i]
			_lint_rules(st.get("advance"), "thread %s/%d" % [id, i + 1])
			_lint_effects(st.get("on_enter"), "thread %s/%d" % [id, i + 1])
			has_done = has_done or bool(st.get("done", false))
			for br: Dictionary in st.get("branch", []):
				_lint_rules(br.get("when"), "thread %s/%d branch" % [id, i + 1])
				check(int(br.goto) >= 1 and int(br.goto) <= stages.size(), "thread %s branch target in range" % id)
		check(has_done, "thread %s can complete" % id)
	for id in Content.events:
		var c: Dictionary = Content.events[id]
		_lint_rules(c.get("when"), "event %s" % id)
		_lint_effects(c.get("effects"), "event %s" % id)
		if c.has("hook"):
			check(Director.has_method("_hook_" + String(c.hook)), "event %s: hook %s exists" % [id, c.hook])


func test_every_discoverable_lore_exists() -> void:
	for id in ["moss_frames", "first_knock", "tier1", "tier2", "tier3", "trunk", "the_knock", "quietlight",
			"relic_crew_locker", "relic_gauge", "relic_trunk_valve", "relic_stencil", "relic_old_pipes"]:
		check(Content.lore.has(id), "lore entry %s" % id)


func _run_convo_choosing(first_choice := 0) -> void:
	var guard := 0
	while Dialogue.active and guard < 80:
		guard += 1
		if Dialogue.has_choices():
			Dialogue.choose(first_choice)
		else:
			Dialogue.advance()
	check(not Dialogue.active, "conversation finishes")


func test_first_day_main_path() -> void:
	GameState.set_flag("intro_done")
	Threads.check()
	eq(Threads.stage("dry_well"), 1, "dry well starts after the opening")
	# Barnaby at the well.
	eq(String(Dialogue.pick_line("barnaby").get("id", "")), "b_intro", "first talk is the intro")
	check(Dialogue.start_with("barnaby"), "intro starts")
	_run_convo_choosing(0)
	check(Society.is_met("barnaby"), "met Barnaby")
	Threads.check()
	eq(Threads.stage("dry_well"), 2, "pointed to the Lease")
	# The Lease.
	GameState.set_flag("lease_tools")
	GameState.set_flag("lease_seed_tin")
	Threads.check()
	eq(Threads.stage("dry_well"), 3, "found the Lease kit")
	eq(Threads.stage("first_harvest"), 1, "farming thread starts with the seed tin")
	# Barnaby hands over the glass.
	eq(String(Dialogue.pick_line("barnaby").get("id", "")), "b_glass", "glass conversation is next")
	Dialogue.start_with("barnaby")
	_run_convo_choosing(1)
	check(GameState.has_tool("glass"), "has the plumb-glass")
	check(GameState.inventory.count("seal_gum") >= 2, "has seal gum")
	Threads.check()
	eq(Threads.stage("dry_well"), 4, "told to look through the glass")
	GameState.discover("places", "undercroft")
	Threads.check()
	eq(Threads.stage("dry_well"), 5, "told to mend the line")
	# Mend the burst segment and crank.
	eq(Sim.repair("pipe", Vector2i(24, 13)), "", "the burst well line mends")
	for i in 30:
		Sim.crank(Sim.well().id)
		Sim._tick_machines(1.0)
		for k in 3:
			Sim._field_step()
	check(bool(Sim.fact("well_flowing")), "well flows after the repair (basin %.2f)" % Sim.well().basin)
	Threads.check()
	check(GameState.has_flag("well_fixed"), "well_fixed set by the thread")
	check(Threads.is_done("dry_well"), "dry well thread complete")
	# Barnaby's thanks starts the power thread.
	eq(String(Dialogue.pick_line("barnaby").get("id", "")), "b_well_fixed", "Barnaby reacts to the well")
	Dialogue.start_with("barnaby")
	_run_convo_choosing(0)
	Threads.check()
	eq(Threads.stage("power"), 1, "power thread begins")
	check(Society.has_memory("mags", "fixed_well"), "Mags heard about the well")


func test_quietlight_bloom_follows_the_air() -> void:
	GameState.set_flag("quietlight_announced")
	Director.trigger("quietlight")
	eq(String(GameState.flag("ql_bloom")), "bright", "clean air, no market lamps: bright bloom")
	GameState.set_flag("ql_side", "odile")
	Director.trigger("quietlight")
	eq(String(GameState.flag("ql_bloom")), "thin", "market lamps on: thin bloom")


func test_tremor_opens_fissure_and_thread() -> void:
	Director.trigger("tremor")
	check(GameState.has_flag("tremor_done"), "tremor flag")
	check(not bool(Sim.fact("fissure_sealed")), "fissure open after the tremor")
	Threads.check()
	eq(Threads.stage("tremor"), 1, "sour ground thread starts")
	GameState.give("blackstone", 4, true)
	eq(Sim.fill_cell(Vector2i(7, 12)), "", "pack a fissure cell")
	check(bool(Sim.fact("fissure_sealed")), "fissure sealed")
	Threads.check()
	check(Threads.is_done("tremor"), "thread completes")


func test_critical_items_have_a_source() -> void:
	# Everything the Station needs can be found, bought or made without luck or a lost line.
	eq(Economy.buy_price("exchange", "seal_gum") > 0, true, "seal gum is sold at the Exchange")
	var resin := false
	for n: Dictionary in GameState.reach_graph.nodes:
		if String(n.get("biome", "")) == "ember":
			var a := ReachGen.generate_cavern(GameState.seed_value, GameState.reach_graph, String(n.id))
			for r: Dictionary in a.resources:
				if String(r.get("item", "")) == "ember_resin":
					resin = true
	check(resin, "ember resin can be mined in an Ember cavern")
	check(Content.recipes.has("seal_gum"), "seal gum has a recipe")
	var teaches := 0
	for line in FileAccess.get_file_as_string("res://data/dialogue/barnaby.json").split("learn:learned_seal"):
		teaches += 1
	check(teaches - 1 >= 2, "Barnaby teaches seal gum in more than one conversation")


func test_every_unlock_can_be_learned() -> void:
	# Collect every flag that any effect or shop can set.
	var taught := {"start": true}
	var scan := func(effects: Variant) -> void:
		if effects == null:
			return
		for e in (effects if effects is Array else [effects]):
			var s := String(e)
			for prefix in ["learn:", "unlock:", "flag:"]:
				if s.begins_with(prefix):
					taught[s.substr(prefix.length()).split("=")[0]] = true
	for npc in Content.dialogue:
		for line: Dictionary in Content.dialogue[npc].get("lines", []):
			scan.call(line.get("do"))
		for cid in Content.dialogue[npc].get("convos", {}):
			for n: Dictionary in Content.dialogue[npc].convos[cid]:
				scan.call(n.get("do"))
				for c: Dictionary in n.get("choice", []):
					scan.call(c.get("do"))
	for id in Content.threads:
		for st: Dictionary in Content.threads[id].get("stages", []):
			scan.call(st.get("on_enter"))
	for id in Content.events:
		scan.call(Content.events[id].get("effects"))
	for m in Content.markets:
		for sid in Content.markets[m].get("schematics", {}):
			taught[sid] = true
	for id: String in Content.machines:
		var u := String(Content.machine(id).get("unlock", ""))
		if u != "":
			check(taught.has(u), "machine %s unlock '%s' is taught somewhere" % [id, u])
	for id: String in Content.recipes:
		var u := String(Content.recipes[id].get("unlock", ""))
		if u != "":
			check(taught.has(u), "recipe %s unlock '%s' is taught somewhere" % [id, u])


func test_every_ruin_page_exists() -> void:
	for n in 12:
		var id := ReachGen.lore_for({"unmapped": n, "tier": 9})
		check(Content.lore.has(id), "Unmapped page %s" % id)
	for st in [8, 9, 10]:
		check(Content.lore.has(ReachGen.lore_for({"deep": true, "station": st, "tier": 4})), "Station %d page" % st)
	for node: Dictionary in GameState.reach_graph.get("nodes", []):
		if bool(node.get("ruin", false)):
			check(Content.lore.has(ReachGen.lore_for(node)), "ruin page for %s" % String(node.id))


func test_requests_post_seeded_and_pay() -> void:
	Requests.reset()
	Society.mark_met("mags")
	GameState.set_flag("well_fixed")
	Requests.refresh(2)
	eq(Requests.open.size(), 1, "one request goes up")
	var first: Dictionary = Requests.open[0].duplicate()
	Requests.reset()
	Requests.refresh(2)
	eq(JSON.stringify(Requests.open[0]), JSON.stringify(first), "the same seed and day post the same request")
	var r: Dictionary = Requests.open[0]
	check(not Requests.can_fill(r), "can't hand in without the goods")
	GameState.give(String(r.item), int(r.n), true)
	var money := GameState.money()
	var aff := Society.axis(String(r.npc), "affection")
	check(Requests.fill(int(r.id)), "hands in")
	eq(GameState.money(), money + int(r.reward), "paid")
	check(Society.axis(String(r.npc), "affection") > aff, "%s is pleased" % String(r.npc))
	eq(Requests.open.size(), 0, "the note comes down")
	eq(Requests.total_done(), 1, "counted")
	# Notes expire.
	Requests.refresh(3)
	var up := Requests.open.size()
	Requests.refresh(3 + int(Content.requests.get("days_open", 4)) + 1)
	check(Requests.open.size() <= up, "stale notes come down")
	Requests.reset()


func test_request_templates_are_sound() -> void:
	var npcs := Content.npcs.keys()
	for t: Dictionary in Content.requests.get("templates", []):
		check(Content.items.has(String(t.item)), "request item %s exists" % String(t.item))
		check(npcs.has(String(t.npc)), "request asker %s exists" % String(t.npc))
		for c in t.get("when", []):
			var err := _clause_ok(String(c))
			check(err == "", "request %s/%s: %s" % [String(t.npc), String(t.item), err])


func test_origins_and_echoes() -> void:
	var saved_endings := Almanac.endings
	Almanac.endings = {"sealed": {"first": 0, "count": 1}}
	for id: String in Content.origins:
		for e in Content.origins[id].get("effects", []):
			var err := _effect_ok(String(e))
			check(err == "", "origin %s: %s" % [id, err])
		GameFlow.new_game(99, "Tester", id, false)
		check(GameState.has_flag("origin_" + id), "origin %s flagged" % id)
		check(not GameState.has_flag("echo"), "no echoes unless asked")
		check(Ending._you("together").contains(String(Content.origins[id].after)), "origin %s in the epilogue" % id)
	GameFlow.new_game(99, "Tester", "seedkeeper", true)
	check(GameState.inventory.count("glowbeet_seed") >= 6, "seed-keeper brought seeds")
	check(GameState.has_flag("echo") and GameState.has_flag("echo_sealed"), "echoes remember the sealed ending")
	Society.mark_met("barnaby")
	Clock.day = 3
	var echo_line := {}
	for l: Dictionary in Content.dialogue.barnaby.lines:
		if String(l.id) == "b_echo_sealed":
			echo_line = l
	check(not echo_line.is_empty() and Conditions.check(echo_line.when, GameState), "Barnaby can half-remember the valve")
	Almanac.endings = saved_endings
	GameFlow.new_game(4242, "Tester")
