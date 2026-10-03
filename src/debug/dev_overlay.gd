class_name DevOverlay
extends CanvasLayer
## Developer tools, available in debug builds or with --dev:
##   F3  overlay: frame timing, draw calls, simulation cost, clock, world facts, director log
##   F1  console: give / money / flag / time / skip / event / thread / area / tp / learn /
##       save / load / tremor / quietlight / unlock / help

var panel: PanelContainer
var text: Label
var console: PanelContainer
var input: LineEdit
var output: RichTextLabel
var _history: PackedStringArray = []
var _hist_i := 0
var _t := 0.0


static func allowed() -> bool:
	return Dev.enabled or OS.is_debug_build()


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	var theme_root := Control.new()
	theme_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	theme_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme_root.theme = UiTheme.get_theme()
	add_child(theme_root)
	panel = PanelContainer.new()
	panel.position = Vector2(16, 90)
	panel.add_theme_stylebox_override("panel", UiTheme.panel_box(Color(0.05, 0.05, 0.07, 0.82), UiTheme.BORDER_DIM, 1, 8))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text = Label.new()
	text.add_theme_font_override("font", load(UiTheme.READABLE_FONT))
	text.add_theme_font_size_override("font_size", 13)
	panel.add_child(text)
	panel.visible = false
	theme_root.add_child(panel)
	console = PanelContainer.new()
	console.set_anchors_preset(Control.PRESET_TOP_WIDE)
	console.offset_bottom = 280
	console.add_theme_stylebox_override("panel", UiTheme.panel_box(Color(0.04, 0.04, 0.06, 0.94), UiTheme.ACCENT, 1, 10))
	var v := VBoxContainer.new()
	output = RichTextLabel.new()
	output.scroll_following = true
	output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	output.add_theme_font_override("normal_font", load(UiTheme.READABLE_FONT))
	output.add_theme_font_size_override("normal_font_size", 14)
	v.add_child(output)
	input = LineEdit.new()
	input.placeholder_text = "command (help)"
	input.text_submitted.connect(_run)
	input.gui_input.connect(_history_keys)
	v.add_child(input)
	console.add_child(v)
	console.visible = false
	theme_root.add_child(console)
	_print("[color=#a89e86]Bellows dev console. 'help' lists commands.[/color]")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("dev_overlay"):
		panel.visible = not panel.visible
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("dev_console"):
		console.visible = not console.visible
		if console.visible:
			input.grab_focus()
			Clock.pause("console")
		else:
			input.release_focus()
			Clock.resume("console")
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_t -= delta
	if not panel.visible or _t > 0.0:
		return
	_t = 0.25
	var lines := PackedStringArray()
	lines.append("FPS %d  frame %.1f ms  draws %d  prims %dk" % [Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0)])
	lines.append("sim step %.2f ms  machine tick %.2f ms  steps %d  nodes %d  mem %d MB" % [Sim.last_step_ms, Sim.last_tick_ms,
		Sim.field_steps, Performance.get_monitor(Performance.OBJECT_NODE_COUNT), int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)])
	lines.append("Day %d %s  %s  breath %s  speed x%.0f%s" % [Clock.day, Clock.time_string(), Clock.phase(), Clock.breath(), Clock.speed, "  PAUSED" if Clock.is_paused() else ""])
	var g := get_parent()
	if g and g.get("player") and g.get("area"):
		var p: Vector3 = g.player.position
		lines.append("area %s  cell %d,%d  view %s" % [g.area.id, int(p.x), int(p.z), GameState.view_mode])
	if Sim.grid:
		lines.append("pollution %.3f  farm %.3f  cistern %.2f  town water %.2f  power %.0f  leaks %d" % [float(Sim.fact("pollution")),
			float(Sim.fact("pollution_farm")), Sim.cistern_level(), Sim.town_water, float(Sim.fact("power")), int(Sim.fact("leaks"))])
	lines.append("tension %.2f  flags %d  money %d" % [Director.tension, GameState.flags.size(), GameState.money()])
	for n: Dictionary in Threads.active_notes():
		lines.append("  thread %s @%d" % [n.id, Threads.stage(String(n.id))])
	for l in Director.log_lines.slice(-4):
		lines.append("  " + String(l))
	text.text = "\n".join(lines)


func _history_keys(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var k := (event as InputEventKey).keycode
		if k == KEY_UP and not _history.is_empty():
			_hist_i = maxi(0, _hist_i - 1)
			input.text = _history[_hist_i]
			input.caret_column = input.text.length()
		elif k == KEY_DOWN and not _history.is_empty():
			_hist_i = mini(_history.size(), _hist_i + 1)
			input.text = _history[_hist_i] if _hist_i < _history.size() else ""


func _print(s: String) -> void:
	output.append_text(s + "\n")


func _run(line: String) -> void:
	input.clear()
	line = line.strip_edges()
	if line.is_empty():
		return
	_history.append(line)
	_hist_i = _history.size()
	_print("[color=#e8a33d]> %s[/color]" % line)
	_print(run_command(line))


## Executes one console command; returns the reply. Public so tests can drive it.
func run_command(line: String) -> String:
	var a := line.split(" ", false)
	var cmd := a[0].to_lower()
	var g := get_parent()
	match cmd:
		"help":
			return "give <item> [n] · money <n> · flag <name> [value] · time <hh:mm> · day <n> · skip <minutes> · event <id> · thread <id> <stage> · area <id|wick> · tp <x> <z> · learn <flag> · unlock · save <slot> · load <slot> · tremor · quietlight · speed <x> · facts"
		"give":
			if a.size() < 2 or not Content.items.has(a[1]):
				return "unknown item"
			var n := int(a[2]) if a.size() > 2 else 1
			return "gave %d" % GameState.give(a[1], n)
		"money":
			GameState.add_money(int(a[1]) if a.size() > 1 else 100)
			return "money %d" % GameState.money()
		"flag":
			if a.size() < 2:
				return "flag <name> [value]"
			GameState.set_flag(a[1], GameState._parse_value(a[2]) if a.size() > 2 else true)
			return "%s = %s" % [a[1], GameState.flag(a[1])]
		"time":
			var hm := (a[1] if a.size() > 1 else "07:00").split(":")
			Clock.start(Clock.day, int(hm[0]) * 60 + (int(hm[1]) if hm.size() > 1 else 0))
			return Clock.time_string()
		"day":
			Clock.start(int(a[1]) if a.size() > 1 else Clock.day + 1, Clock.minute)
			return "day %d" % Clock.day
		"skip":
			Clock.advance(float(a[1]) if a.size() > 1 else 60.0)
			return Clock.time_string()
		"speed":
			Clock.set_speed(float(a[1]) if a.size() > 1 else 1.0)
			return "speed %.1f" % Clock.speed
		"event":
			if a.size() < 2 or not Content.events.has(a[1]):
				return "unknown event"
			Director.trigger(a[1])
			return "fired %s" % a[1]
		"tremor":
			Director.trigger("tremor")
			return "the ground lurches"
		"quietlight":
			GameState.set_flag("quietlight_announced")
			Director.trigger("quietlight")
			return "lamps out (%s)" % GameState.flag("ql_bloom")
		"thread":
			if a.size() < 3:
				return "thread <id> <stage>"
			Threads.set_stage(a[1], int(a[2]))
			return "%s @%d" % [a[1], Threads.stage(a[1])]
		"learn":
			if a.size() < 2:
				return "learn <flag>"
			GameState.set_flag(a[1])
			return "learned %s" % a[1]
		"unlock":
			for m: String in Content.machines:
				var u := String(Content.machine(m).get("unlock", ""))
				if u != "" and u != "start":
					GameState.set_flag(u)
			for r: String in Content.recipes:
				var u2 := String(Content.recipes[r].get("unlock", ""))
				if u2 != "":
					GameState.set_flag(u2)
			for t in ["tiller", "can", "glass", "hammer", "wrench"]:
				GameState.add_tool(t)
			GameState.set_flag("reach_open")
			return "everything unlocked"
		"area":
			if g and g.has_method("travel"):
				g.travel(a[1] if a.size() > 1 else "wick")
				return "travelling"
			return "no game"
		"tp":
			if g and g.get("player") and a.size() > 2:
				g.player.place(Vector2(float(a[1]) + 0.5, float(a[2]) + 0.5), g.area)
				g.rig.snap()
				return "ok"
			return "tp <x> <z>"
		"save":
			return "saved" if Saves.save(int(a[1]) if a.size() > 1 else 1) else "save failed"
		"load":
			var err := GameFlow.continue_from(get_tree(), int(a[1]) if a.size() > 1 else 1)
			return "loading" if err == "" else err
		"facts":
			var out := PackedStringArray()
			for k in ["pollution", "pollution_farm", "cistern", "town_water", "power", "leaks", "planted", "well_flowing", "fissure_sealed"]:
				out.append("%s=%s" % [k, Sim.fact(k)])
			return "  ".join(out)
	return "unknown command '%s' (help)" % cmd
