extends TestCase
## Save format, migration, corruption handling and full-game round trips.


func before_each() -> void:
	GameState.new_game(777, "Tester")
	Clock.start(1, 6 * 60)
	Sim.new_world(777)
	Society.reset()
	Economy.reset()
	Threads.reset()
	Director.reset(777)
	Dialogue.reset()


func test_codec_round_trip() -> void:
	var text := SaveCodec.encode({"name": "x"}, {"world": {"a": 1}})
	var r := SaveCodec.decode(text)
	check(r.ok, "decodes")
	eq(int(r.sections.world.a), 1, "section data")


func test_codec_refuses_future_and_garbage() -> void:
	var future := JSON.stringify({"format": SaveCodec.FORMAT, "version": SaveCodec.VERSION + 5, "sections": {}})
	check(not SaveCodec.decode(future).ok, "future version refused")
	check(not SaveCodec.decode("{not json").ok, "garbage refused")
	check(not SaveCodec.decode("").ok, "empty refused")
	check(not SaveCodec.decode(JSON.stringify({"format": "other"})).ok, "foreign file refused")


func test_v1_save_is_migrated() -> void:
	var v1 := JSON.stringify({"format": SaveCodec.FORMAT, "version": 1, "meta": {},
		"sections": {"money": 55, "world": {"player": {"name": "Old"}}}})
	var r := SaveCodec.decode(v1)
	check(r.ok, "v1 decodes")
	eq(int(r.sections.world.player.money), 55, "money moved into the player")
	check(r.sections.world.has("history"), "history section added")


func test_full_game_round_trip() -> void:
	GameState.give("glowbeet", 7, true)
	GameState.set_flag("well_fixed", true)
	GameState.add_money(13)
	Society.change("barnaby", "trust", 12.0)
	Society.remember("hesper", "moss_gassed", 5.0, -0.9)
	Sim.till(Vector2i(8, 17))
	Sim.plant(Vector2i(8, 17), "cave_moss")
	Sim.grid.add_gas(10, 5, UcGrid.SOUR, 0.3)
	Clock.advance(95.0)
	var sections := Saves.collect_sections()
	var text := SaveCodec.encode(Saves.make_meta(), sections)
	var expected := JSON.stringify(sections)
	# Scramble live state, then load.
	GameState.new_game(1, "Someone Else")
	Sim.new_world(1)
	Society.reset()
	var r := SaveCodec.decode(text)
	check(r.ok, "decodes")
	eq(Saves.apply(r.sections), "", "applies")
	eq(GameState.inventory.count("glowbeet"), 7, "inventory")
	check(GameState.has_flag("well_fixed"), "flags")
	eq(GameState.money(), GameState.START_MONEY + 13, "money")
	near(Society.axis("barnaby", "trust"), 12.0 * 1.0, 3.0, "relationship axis")
	check(Society.has_memory("hesper", "moss_gassed"), "memory")
	eq(String(Sim.plot_at(Vector2i(8, 17)).get("crop", "")), "cave_moss", "planted crop")
	eq(Clock.day, 1, "day")
	near(Clock.minute, 6 * 60 + 95, 0.01, "time")
	var again := Saves.collect_sections()
	var orig: Dictionary = JSON.parse_string(expected)
	for key in orig:
		var a := JSON.stringify(orig[key])
		var b := JSON.stringify(JSON.parse_string(JSON.stringify(again.get(key))))
		if a != b:
			var at := 0
			while at < mini(a.length(), b.length()) and a[at] == b[at]:
				at += 1
			failures.append("%s: section '%s' differs after reload near: ...%s... vs ...%s..." % [current, key,
				a.substr(maxi(0, at - 60), 140), b.substr(maxi(0, at - 60), 140)])


func test_atomic_write_and_backup_fallback() -> void:
	var slot := 3
	Saves.delete_slot(slot)
	check(Saves.save(slot), "first save")
	GameState.add_money(100)
	check(Saves.save(slot), "second save keeps the first as backup")
	# Corrupt the main file: loading must fall back to the backup, not crash.
	var f := FileAccess.open(Saves.slot_path(slot), FileAccess.WRITE)
	f.store_string("{\"format\": \"bellows-save\", \"vers")
	f.close()
	var r := Saves.read_slot(slot)
	check(r.ok, "falls back to backup")
	check(r.get("from_backup", false), "reports the fallback")
	Saves.delete_slot(slot)


func test_reload_does_not_change_the_world() -> void:
	var before := JSON.stringify(ReachGen.generate_cavern(777, GameState.reach_graph, GameState.reach_graph.nodes[0].id).to_dict())
	var text := SaveCodec.encode({}, Saves.collect_sections())
	Saves.apply(SaveCodec.decode(text).sections)
	var after := JSON.stringify(ReachGen.generate_cavern(777, GameState.reach_graph, GameState.reach_graph.nodes[0].id).to_dict())
	eq(after, before, "reloading regenerates the identical Reach")
