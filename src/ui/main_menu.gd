extends Node3D
## Title screen. Wick at Hush, seen slowly from above like a model on a table, under a
## small brass-and-basalt menu. Continue / New / Load / Settings / Credits / Quit.

const CAM_PITCH := -38.0
const CAM_DIST := 30.0

var env: EnvCtl
var view: AreaView
var cam: Camera3D
var attrs: CameraAttributesPractical
var ui: Control
var menu_box: VBoxContainer
var sub: PanelContainer
var sub_box: VBoxContainer
var _t := 0.0
var _name_edit: LineEdit
var _seed_edit: LineEdit


func _ready() -> void:
	GameState.started = false
	Sim.active = false
	Clock.clear_pauses()
	Clock.start(1, 22 * 60 + 40)   # Hush: lamps lit, glowroots low
	Clock.running = false
	RenderingServer.global_shader_parameter_set("cut_amount", 0.0)
	env = EnvCtl.new()
	add_child(env)
	env.set_biome("grove")
	view = AreaView.new()
	add_child(view)
	view.build(AreaMap.from_ascii(Content.wick_map))
	Fx.ambient(view, "grove", 48, 32)
	cam = Camera3D.new()
	cam.fov = 30.0
	attrs = CameraAttributesPractical.new()
	attrs.dof_blur_far_enabled = bool(Settings.graphics.get("dof", true)) and RenderingServer.get_current_rendering_method() != "gl_compatibility"
	attrs.dof_blur_far_distance = CAM_DIST + 4.0
	attrs.dof_blur_far_transition = 10.0
	attrs.dof_blur_amount = 0.08
	cam.attributes = attrs
	add_child(cam)
	cam.current = true
	_build_ui()
	Audio.music("menu", {"pad": 1.0, "melody": 0.7, "glass": 0.6, "drone": 0.8})
	Audio.ambience("grove")
	if Dev.has_arg("autostart"):
		# Dev/capture path: press New game -> Begin, exactly as a player would.
		get_tree().create_timer(0.4).timeout.connect(func() -> void:
			_show_new_game()
			_start_new())


func _process(delta: float) -> void:
	_t += delta
	var x := 24.0 + sin(_t * 0.045) * 13.0
	var focus := Vector3(x, 0.6, 16.0 + sin(_t * 0.031) * 2.0)
	var pitch := deg_to_rad(CAM_PITCH)
	var pos := focus + Vector3(0, -sin(pitch), cos(pitch)) * CAM_DIST
	cam.global_transform = Transform3D(Basis.looking_at(focus - pos, Vector3.UP), pos)
	view.update_lights(delta, Clock.glow_level(), Clock.darkness(), 1.0)


# --- UI -----------------------------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.theme = UiTheme.get_theme()
	layer.add_child(ui)
	# Soft vignette on the left so the menu reads over the town.
	var shade := TextureRect.new()
	shade.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	shade.offset_right = 560
	var grad := Gradient.new()
	grad.set_color(0, Color(0.04, 0.035, 0.06, 0.88))
	grad.set_color(1, Color(0.04, 0.035, 0.06, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(shade)
	var col := VBoxContainer.new()
	col.position = Vector2(72, 120)
	col.custom_minimum_size = Vector2(360, 0)
	col.add_theme_constant_override("separation", 6)
	ui.add_child(col)
	var title := Label.new()
	title.text = "BELLOWS"
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", UiTheme.ACCENT)
	title.add_theme_color_override("font_shadow_color", Color(0.1, 0.05, 0.0, 0.8))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 3)
	col.add_child(title)
	var tag := Label.new()
	tag.text = "Build a life inside a living machine."
	tag.add_theme_font_size_override("font_size", UiTheme.size(19))
	tag.add_theme_color_override("font_color", UiTheme.DIM)
	col.add_child(tag)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 36)
	col.add_child(gap)
	menu_box = VBoxContainer.new()
	menu_box.add_theme_constant_override("separation", 8)
	col.add_child(menu_box)
	var latest := Saves.latest_slot()
	if latest >= 0:
		var info := Saves.slot_info(latest)
		_menu_button("Continue", func() -> void: _continue(latest), "Day %d · %s" % [int(info.get("day", 1)), String(info.get("place", "Wick"))])
	_menu_button("New game", _show_new_game)
	if Saves.has_any_save():
		_menu_button("Load", _show_load)
	_menu_button("Settings", _show_settings)
	_menu_button("Credits", _show_credits)
	if OS.get_name() != "Web":
		_menu_button("Quit", func() -> void: get_tree().quit())
	var ver := Label.new()
	ver.text = "v%s · first chapter" % String(ProjectSettings.get_setting("application/config/version", "0"))
	ver.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	ver.position = Vector2(72, -40)
	ver.add_theme_color_override("font_color", Color(UiTheme.DIM, 0.6))
	ver.add_theme_font_size_override("font_size", UiTheme.size(14))
	ui.add_child(ver)
	# Side panel for sub-pages (new game, load, settings, credits).
	sub = PanelContainer.new()
	sub.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	sub.offset_left = -700
	sub.offset_right = -48
	sub.offset_top = 80
	sub.offset_bottom = -80
	sub_box = VBoxContainer.new()
	sub_box.add_theme_constant_override("separation", 10)
	sub.add_child(sub_box)
	sub.visible = false
	ui.add_child(sub)
	_focus_first.call_deferred(menu_box)


func _menu_button(text: String, cb: Callable, detail := "") -> void:
	var b := Button.new()
	b.text = text if detail == "" else "%s   (%s)" % [text, detail]
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", UiTheme.size(24))
	b.custom_minimum_size = Vector2(360, 46)
	b.pressed.connect(func() -> void:
		Audio.ui("ui_select", -4.0)
		cb.call())
	b.focus_entered.connect(func() -> void: Audio.ui("ui_move", -12.0))
	menu_box.add_child(b)


func _focus_first(n: Node) -> void:
	for c in n.get_children():
		if c is Button:
			(c as Button).grab_focus()
			return


func _clear_sub(title: String) -> void:
	for c in sub_box.get_children():
		sub_box.remove_child(c)
		c.queue_free()
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", UiTheme.size(28))
	t.add_theme_color_override("font_color", UiTheme.ACCENT)
	sub_box.add_child(t)
	sub.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel") and sub.visible:
		sub.visible = false
		_focus_first(menu_box)
		get_viewport().set_input_as_handled()


func _show_new_game() -> void:
	_clear_sub("A new descent")
	var l := Label.new()
	l.text = "Your line will snap. That part isn't up to you. The rest is."
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", UiTheme.DIM)
	sub_box.add_child(l)
	_name_edit = LineEdit.new()
	_name_edit.text = "Salvager"
	_name_edit.max_length = 18
	sub_box.add_child(SettingsPanel._row("Name", _name_edit))
	_seed_edit = LineEdit.new()
	_seed_edit.text = str(GameFlow.random_seed())
	_seed_edit.tooltip_text = "The Reach below Wick is drawn from this number. Share it to share a world."
	sub_box.add_child(SettingsPanel._row("World seed", _seed_edit))
	var go := Button.new()
	go.text = "Begin"
	go.add_theme_font_size_override("font_size", UiTheme.size(24))
	go.pressed.connect(_start_new)
	sub_box.add_child(go)
	if Settings.last_device == "pad":
		go.grab_focus()
	else:
		_name_edit.grab_focus()


func _start_new() -> void:
	var nm := _name_edit.text.strip_edges()
	if nm.is_empty():
		nm = "Salvager"
	var sv := int(_seed_edit.text) if _seed_edit.text.strip_edges().is_valid_int() else _seed_edit.text.hash()
	GameFlow.new_game(absi(sv), nm)
	GameFlow.start(get_tree())


func _continue(slot: int) -> void:
	var err := GameFlow.continue_from(get_tree(), slot)
	if err != "":
		_clear_sub("That save won't open")
		var l := Label.new()
		l.text = "%s\n\nThe file is still there; nothing was deleted." % err
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub_box.add_child(l)


func _show_load() -> void:
	_clear_sub("Load")
	for slot in Saves.SLOTS:
		var info := Saves.slot_info(slot)
		if info.is_empty():
			continue
		var s: int = slot
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%s%s — Day %d, %s, %s" % ["Autosave: " if slot == 0 else "Slot %d: " % slot, String(info.get("name", "")),
			int(info.get("day", 1)), String(info.get("time", "")), String(info.get("place", ""))]
		b.pressed.connect(func() -> void: _continue(s))
		sub_box.add_child(b)
	_focus_first(sub_box)


func _show_settings() -> void:
	_clear_sub("Settings")
	var s := SettingsPanel.build()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sub_box.add_child(s)


func _show_credits() -> void:
	_clear_sub("Credits")
	var t := Label.new()
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.text = "Bellows — first chapter.\n\nDesign, code, pixel art, music and sound generated for this project, procedurally, from scratch.\n\nFonts: Pixelify Sans and Atkinson Hyperlegible, under the SIL Open Font License.\n\nBuilt with Godot Engine (MIT).\n\nIn loving memory of every pipe that ever knocked back."
	sub_box.add_child(t)
