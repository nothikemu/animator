extends TestCase
## Chapters Two to Four, played by a plain autopilot through the real dialogue, threads and
## events: every hour, go everywhere the routes allow, talk to whoever has something to say,
## pick the first answer that isn't on the avoid list, gather what the notes ask for, and sleep
## at night. If these pass, every ending can be reached from the knock, and none soft-locks.
##
## The autopilot cheats on two things: it is handed the goods a note or a story line asks for
## (crew cable, salt, medicine), and the field simulation is frozen once Station 7 runs, because
## farming, crafting and engineering are covered by their own suites (and it keeps this fast).

const PLACES := ["wick", "d1_0", "d1_1", "sallow", "d2_0", "d2_1", "d3_0", "ways", "heart"]
const OBJECTS := {"wick": ["_telegraph"], "sallow": ["_archive"], "heart": ["_bellows"], "ways": ["_mural"]}

var avoid: Array = []          ## choice text fragments the autopilot won't pick
var hold_back: Array = []      ## items the autopilot won't fetch (to let something go wrong)
var heard := {}                ## "line@day" already run
var trail := PackedStringArray()


func before_each() -> void:
	GameFlow.new_game(2024, "Tester")
	heard.clear()
	trail.clear()
	avoid = []
	hold_back = []
	# Where Chapter One leaves Wick (see test_full_arc): the knock heard through an open valve.
	for f in ["intro_done", "lease_tools", "lease_seed_tin", "got_glass", "learned_pipes", "well_fixed",
			"reach_open", "tremor_done", "quietlight_announced", "quietlight_done", "b_station_asked",
			"seen_station_pump", "b_valve_talk", "knock_heard", "valve_open", "chapter_one_done"]:
		GameState.set_flag(f)
	GameState.set_flag("valve_choice", "open")
	for id in ["barnaby", "odile", "hesper", "mags", "grist"]:
		Society.mark_met(id)
		Society.change(id, "trust", 8.0)
		Society.change(id, "affection", 6.0)
	GameState.discover("places", "undercroft")
	_run_station_pump()
	Sim.active = false
	Clock.start(9, 8 * 60)
	for t: String in ["dry_well", "power", "first_harvest"]:
		if Content.threads.has(t):
			Threads.set_stage(t, (Content.threads[t].get("stages", []) as Array).size())
	Threads.check()


func _ticks(minutes: int) -> void:
	for i in minutes:
		Sim._tick_machines(1.0)
		for k in 3:
			Sim._field_step()


## Station 7 at full power and the lift winch fitted (as test_full_arc does it).
func _run_station_pump() -> void:
	for it: String in {"governor_coil": 1, "seal_gum": 4}:
		GameState.give(it, 4, true)
	GameState.give("brass_scrap", 40, true)
	GameState.give("wire_coil", 40, true)
	var sp := Sim.find_machine("station_pump")
	Sim.load_item(sp.id, "governor_coil", 1)
	Sim.load_item(sp.id, "seal_gum", 4)
	for x in [35, 40, 43]:
		Sim.build("crank", Vector2i(x, 15))
	var wire: Array = []
	for x in range(35, 45):
		wire.append(Vector2i(x, 15))
	Sim.lay_conduit("wire", wire)
	for c in [Vector2i(33, 12), Vector2i(34, 12), Vector2i(41, 17), Vector2i(41, 19), Vector2i(24, 13)]:
		Sim.repair("pipe", c)
	_crank_all()


func _crank_all() -> void:
	for m: MachineState in Sim.machines.machines.values():
		if m.def_id == "crank":
			for i in 4:
				Sim.crank(m.id)
	_ticks(6)


# --- The autopilot ----------------------------------------------------------------------------

func _reachable(place: String) -> bool:
	return place == "wick" or Objectives.next_hop("wick", place) != ""


func _speakers(place: String) -> Array:
	var out: Array = []
	for id: String in Content.npcs:
		if Npc.area_of(id) == place:
			out.append(id)
	out.append_array(OBJECTS.get(place, []))
	return out


func _choose() -> void:
	var opts: Array = Dialogue._choices
	var pick := -1
	for i in opts.size():
		var t := String(opts[i].get("text", ""))
		var bad := false
		for a: String in avoid:
			if t.contains(a):
				bad = true
		if not bad:
			pick = i
			break
	if pick < 0:
		pick = opts.size() - 1
	trail.append("    > " + String(opts[pick].get("text", "")))
	Dialogue.choose(pick)


func _run_dialogue() -> void:
	var guard := 0
	while Dialogue.active and guard < 120:
		guard += 1
		if Dialogue.has_choices():
			_choose()
		else:
			Dialogue.advance()
	if Dialogue.active:
		failures.append("%s: a conversation never ended (%s)" % [current, Dialogue.npc])
		Dialogue.cancel()


## Talks to `who` if they have a story or reactive line not yet heard today.
func _talk(who: String) -> bool:
	var line := Dialogue.pick_line(who)
	if line.is_empty():
		return false
	var tier := String(line.get("tier", "ambient"))
	var id := String(line.get("id", ""))
	if tier == "ambient" or heard.has("%s@%d" % [id, Clock.day]):
		return false
	heard["%s@%d" % [id, Clock.day]] = true
	trail.append("D%d %s %s: %s" % [Clock.day, Clock.time_string(), who, id])
	Dialogue.start_with(who)
	_run_dialogue()
	Threads.check()
	return true


## The goods the current notes and story lines are waiting on.
func _gather() -> void:
	var wants: Array = []
	for n: Dictionary in Threads.active_notes():
		var d := Threads.def(String(n.id))
		var s := Threads.stage(String(n.id))
		var stages: Array = d.get("stages", [])
		if s >= 1 and s <= stages.size():
			wants.append_array(stages[s - 1].get("advance", []))
	for who: String in Content.dialogue:
		for l: Dictionary in Content.dialogue[who].get("lines", []):
			if String(l.get("tier", "")) == "story":
				wants.append_array(l.get("when", []))
		for convo: Array in Content.dialogue[who].get("convos", {}).values():
			for node: Dictionary in convo:
				wants.append_array(node.get("if", []))
	for c in wants:
		var clause := String(c)
		if clause.begins_with("item:") and not Conditions.eval_clause(clause, GameState):
			var p := Conditions.parse(clause)
			var item := String(p.key).get_slice(".", 1)
			if hold_back.has(item) or Content.item(item).get("value", 1) == 0:
				continue
			var need := int(p.values[0]) if not (p.values as Array).is_empty() else 1
			if Content.items.has(item):
				GameState.give(item, maxi(1, need - GameState.inventory.count(item)), true)
		elif clause.begins_with("deed:") and not Conditions.eval_clause(clause, GameState):
			# Selling, harvesting, keeping your word: done the long way in play.
			var p := Conditions.parse(clause)
			var kind := String(p.key).get_slice(".", 1)
			var need := float(p.values[0]) if not (p.values as Array).is_empty() else 1.0
			GameState.add_deed(kind, maxf(1.0, need - GameState.deed(kind)))
	# The lift winch, once there's cable for it.
	if GameState.inventory.count("crew_cable") >= 2 and Threads.stage("the_lift") == 2:
		var w := Sim.find_machine("lift_winch")
		if w:
			GameState.give("brass_scrap", 6, true)
			Sim.load_item(w.id, "crew_cable", 2)
			Sim.load_item(w.id, "brass_scrap", 6)
			# Its own wire (one wire carries sixty; the pump takes fifty-five): two cranks on
			# the winch's roof, wired down into it, apart from the pump's run along row 15.
			eq(Sim.build("crank", Vector2i(42, 11)), "", "a crank on the winch")
			eq(Sim.build("crank", Vector2i(43, 11)), "", "and another")
			eq(Sim.lay_conduit("wire", [Vector2i(42, 11), Vector2i(43, 11), Vector2i(42, 12)]), 3, "wired into the winch")
			_crank_all()
			if not Conditions._truthy(Sim.fact("running.lift_winch")):
				failures.append("%s: the lift winch won't run once fitted (status %s)" % [current, String(w.status)])
	if GameState.knows_recipe("moss_tincture") and GameState.inventory.count("moss_tincture") < 1 and not hold_back.has("moss_tincture"):
		GameState.give("moss_tincture", 1, true)


func _visit(place: String) -> bool:
	GameState.current_area = place
	GameState.discover("places", place)
	var node := ReachGen.node_by_id(GameState.reach_graph, place)
	if bool(node.get("ruin", false)) or bool(node.get("deep", false)):
		var lore := ReachGen.lore_for(node)
		if Content.lore.has(lore):
			GameState.discover("lore", lore)
	var any := false
	for who: String in _speakers(place):
		if _talk(who):
			any = true
	return any


## Plays hour by hour until an ending is chosen, or `stop` is set, or `days` run out. Returns
## the ending flag.
func _play(days: int, stop := "ending_chosen") -> String:
	var until := Clock.day + days
	var day := Clock.day
	var t0 := Time.get_ticks_msec()
	while Clock.day < until and not GameState.has_flag("ending_chosen") and not GameState.has_flag(stop):
		_gather()
		for place: String in PLACES:
			if _reachable(place):
				for i in 3:
					if not _visit(place) or GameState.has_flag("ending_chosen"):
						break
		GameState.current_area = "wick"
		Threads.check()
		if Clock.day != day and OS.has_feature("debug") and OS.get_cmdline_user_args().has("--arc-trace"):
			print("  day %d (%d ms)" % [Clock.day, Time.get_ticks_msec() - t0])
			day = Clock.day
		if Clock.hour() >= 23 or Clock.hour() < 6:
			Clock.sleep_until_morning()
		else:
			Clock.advance(60.0)
	if OS.get_cmdline_user_args().has("--arc-trace"):
		print("  --- %s ended day %d:\n  %s" % [current, Clock.day, "\n  ".join(trail)])
	return String(GameState.flag("ending")) if GameState.flag("ending") != null else ""


func _stuck_report() -> String:
	var notes := PackedStringArray()
	for n: Dictionary in Threads.active_notes():
		notes.append("%s(%d)" % [String(n.id), Threads.stage(String(n.id))])
	if not GameState.has_flag("ending_chosen"):
		print("  --- %s stuck on day %d; noise %s, pollution %s; last steps:\n  %s" % [current, Clock.day,
			str(Sim.fact("noise_lane")), str(Sim.fact("pollution")), "\n  ".join(trail.slice(maxi(0, trail.size() - 40)))])
	return "day %d, open: %s" % [Clock.day, ", ".join(notes)]


# --- The endings ------------------------------------------------------------------------------

func test_everything_breathing() -> void:
	avoid = ["Long Watch", "Seal Wick", "Not yet"]
	var e := _play(40)
	eq(e, "breathe", "the lever is pulled together (%s)" % _stuck_report())
	check(GameState.has_flag("heart_running"), "the Heart breathes")
	check(not GameState.has_flag("wren_died"), "Wren lives")
	check(Threads.is_done("the_heart"), "the Bellows thread completes")
	eq(Ending.resolve(), "everything", "every arc tied: o_trade %s tincture %s stores %s barnaby %s ways %s" % [
		GameState.has_flag("o_trade_sent"), GameState.has_flag("learned_tincture"), GameState.has_flag("mags_stores_ok"),
		GameState.has_flag("reunion_done") or GameState.has_flag("grief_done") or GameState.has_flag("journal_given"),
		GameState.has_flag("ways_open")])
	check(Clock.day <= 32, "the arc fits the planned days (ended day %d)" % Clock.day)


func test_the_long_watch() -> void:
	avoid = ["Pull the lever", "Seal Wick", "Not yet"]
	var e := _play(40)
	eq(e, "watch", "the Heart is left to Sallow (%s)" % _stuck_report())
	eq(Ending.resolve(), "watch", "The Long Watch")
	check(not GameState.has_flag("heart_running"), "the Heart is not restarted")


func test_sealed() -> void:
	avoid = ["Pull the lever", "Long Watch", "Not yet"]
	var e := _play(40)
	eq(e, "sealed", "Wick seals itself off (%s)" % _stuck_report())
	eq(Ending.resolve(), "sealed", "Sealed")
	check(not GameState.has_flag("valve_open"), "the valve is closed for good")


func test_wren_can_be_lost_and_the_story_goes_on() -> void:
	avoid = ["Give her", "Pull the lever", "Long Watch", "Seal Wick", "Not yet"]
	hold_back = ["moss_tincture", "river_medicine"]
	_play(20, "wren_died")
	check(GameState.has_flag("wren_died"), "Wren dies without medicine (%s)" % _stuck_report())
	avoid = ["Give her", "Long Watch", "Seal Wick", "Not yet"]
	var e := _play(30)
	check(GameState.has_flag("grief_done") or GameState.has_flag("journal_given"), "Barnaby grieves, or is given the journal")
	eq(e, "breathe", "the Heart can still be restarted (%s)" % _stuck_report())
	eq(Ending.resolve(), "together", "Breathe Together, not Everything")


func test_ending_before_wren_is_cured_is_not_everything() -> void:
	avoid = ["Give her", "Long Watch", "Seal Wick", "Not yet"]
	hold_back = ["moss_tincture", "river_medicine"]
	var e := _play(40)
	eq(e, "breathe", "the Heart restarts (%s)" % _stuck_report())
	if not GameState.has_flag("wren_saved"):
		eq(Ending.resolve(), "together", "Wren never cured: not Everything")
		check(Ending._people("together").any(func(l: String) -> bool: return l.contains("Wren")), "Wren still has an epilogue line")
