extends TestCase
## Every panel opens and closes without engine errors, with and without content.


func before_each() -> void:
	GameFlow.new_game(99, "Tester")


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func test_every_panel_opens_and_closes() -> void:
	var p := Panels.new()
	_root().add_child(p)
	GameState.give("glowbeet", 5, true)
	GameState.discover("lore", "tier1")
	Society.mark_met("barnaby")
	for spec in [["inventory", {}], ["craft", {"station": "bench"}], ["shop", {"arg": "exchange"}],
			["shop", {"arg": "lantern"}], ["shop", {"arg": "grist"}], ["board", {}], ["journal", {}],
			["map", {}], ["lore", {"id": "tier1"}], ["pause", {}], ["saves", {}], ["settings", {}]]:
		p.open(StringName(spec[0]), spec[1])
		eq(p.current, String(spec[0]), "%s opened" % spec[0])
		check(p.content.get_child_count() == 1, "%s has content" % spec[0])
		p.close()
		while p.is_open():
			p.close()
	check(not Clock.is_paused() or not Clock.running, "clock resumes after panels close")
	p.queue_free()


func test_nested_settings_returns_to_pause() -> void:
	var p := Panels.new()
	_root().add_child(p)
	p.open(&"pause", {})
	p.open(&"settings", {})
	eq(p.current, "settings", "settings on top")
	p.close()
	eq(p.current, "pause", "back to pause")
	p.close()
	check(not p.is_open(), "closed")
	p.queue_free()


func test_crafting_moss_tea() -> void:
	var p := Panels.new()
	_root().add_child(p)
	GameState.give("moss_fiber", 2, true)
	p._do_craft("moss_tea", Content.recipes["moss_tea"])
	eq(GameState.inventory.count("moss_tea"), 1, "made tea")
	eq(GameState.inventory.count("moss_fiber"), 0, "used the fibre")
	p.queue_free()


func test_settings_panel_builds() -> void:
	var s := SettingsPanel.build()
	check(s is TabContainer and s.get_child_count() == 4, "four settings tabs")
	s.free()


func test_dev_console_commands() -> void:
	var d := DevOverlay.new()
	_root().add_child(d)
	check(d.run_command("give glowbeet 3").begins_with("gave 3"), "give")
	eq(GameState.inventory.count("glowbeet"), 3, "has beets")
	d.run_command("money 50")
	check(GameState.money() >= 50, "money")
	d.run_command("flag test_flag 7")
	eq(int(GameState.flag("test_flag")), 7, "flag with value")
	d.run_command("time 21:30")
	eq(Clock.time_string(), "21:30", "time set")
	d.run_command("unlock")
	check(GameState.can_build("burner") and GameState.has_tool("glass"), "unlock")
	check(d.run_command("nonsense").begins_with("unknown"), "unknown command")
	check(d.run_command("facts").contains("cistern="), "facts")
	d.queue_free()
