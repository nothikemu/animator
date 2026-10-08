class_name Hud
extends CanvasLayer
## Minimal heads-up display. Nothing here is a bar unless it has to be.

var root: Control
var dial_label: Label
var phase_label: Label
var money_label: Label
var thread_label: Label
var tool_icon: TextureRect
var tool_label: Label
var prompt_panel: PanelContainer
var prompt_label: Label
var toast_box: VBoxContainer
var notice_label: Label
var caption_label: Label
var breath_bar: ProgressBar
var save_icon: TextureRect
var save_label: Label
var minimap: Minimap
var area_label: Label
var _map_box: Control
var _notice_t := 0.0
var _caption_t := 0.0
var _save_t := 0.0
var _saving := false


func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.get_theme()
	add_child(root)
	_build()
	Events.toast.connect(toast)
	Events.toast.connect(func(_t: String, kind: StringName) -> void:
		if kind in [&"thread", &"learn", &"good"]:
			Audio.ui("chime", -10.0))
	Events.noticed.connect(func(_n: StringName, _t: String) -> void: Audio.ui("notice", -12.0))
	Events.noticed.connect(func(_npc: StringName, text: String) -> void: notice(text))
	Events.caption.connect(caption)
	Events.prompt_changed.connect(set_prompt)
	# Panels cover the middle of the screen; keep the corners quiet while they're up.
	Events.ui_open.connect(func(_p: StringName, _d: Dictionary) -> void:
		thread_label.visible = false
		_map_box.visible = false
		prompt_panel.visible = false)
	Events.ui_closed.connect(func(_p: StringName) -> void:
		thread_label.visible = true
		_apply_minimap_size())
	Events.save_started.connect(func(_s: int) -> void: _saving = true; _save_t = 0.0)
	Events.save_finished.connect(_on_saved)
	Events.settings_changed.connect(func(s: StringName) -> void:
		if s == &"access":
			UiTheme.invalidate()
			root.theme = UiTheme.get_theme()
			_apply_minimap_size())


func _build() -> void:
	# Time dial (top-left).
	var dial := PanelContainer.new()
	dial.position = Vector2(16, 14)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 0)
	dial_label = Label.new()
	dial_label.add_theme_font_size_override("font_size", UiTheme.size(22))
	phase_label = Label.new()
	phase_label.add_theme_color_override("font_color", UiTheme.DIM)
	phase_label.add_theme_font_size_override("font_size", UiTheme.size(16))
	dv.add_child(dial_label)
	dv.add_child(phase_label)
	dial.add_child(dv)
	root.add_child(dial)
	notice_label = Label.new()
	notice_label.position = Vector2(20, 84)
	notice_label.add_theme_color_override("font_color", UiTheme.LIVING)
	notice_label.add_theme_font_size_override("font_size", UiTheme.size(17))
	notice_label.modulate.a = 0.0
	root.add_child(notice_label)
	# Money and thread (top-right).
	var tr := VBoxContainer.new()
	tr.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tr.position = Vector2(-16, 14)
	tr.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tr.alignment = BoxContainer.ALIGNMENT_END
	var mp := PanelContainer.new()
	mp.size_flags_horizontal = Control.SIZE_SHRINK_END
	var mh := HBoxContainer.new()
	var gi := TextureRect.new()
	gi.texture = UiTheme.icon("glim")
	gi.custom_minimum_size = Vector2(24, 24)
	gi.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	gi.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	money_label = Label.new()
	money_label.add_theme_font_size_override("font_size", UiTheme.size(20))
	mh.add_child(gi)
	mh.add_child(money_label)
	mp.add_child(mh)
	tr.add_child(mp)
	# Minimap (N cycles small / large / hidden).
	var mbox := VBoxContainer.new()
	mbox.size_flags_horizontal = Control.SIZE_SHRINK_END
	mbox.add_theme_constant_override("separation", 2)
	minimap = Minimap.new()
	minimap.custom_minimum_size = Vector2(184, 150)
	mbox.add_child(minimap)
	area_label = Label.new()
	area_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	area_label.add_theme_font_size_override("font_size", UiTheme.size(15))
	area_label.add_theme_color_override("font_color", UiTheme.DIM)
	mbox.add_child(area_label)
	tr.add_child(mbox)
	_map_box = mbox
	_apply_minimap_size()
	thread_label = Label.new()
	thread_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	thread_label.add_theme_font_size_override("font_size", UiTheme.size(17))
	thread_label.add_theme_color_override("font_color", UiTheme.TEXT)
	thread_label.custom_minimum_size = Vector2(380, 0)
	thread_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tr.add_child(thread_label)
	root.add_child(tr)
	# Tool (bottom-left).
	var tp := PanelContainer.new()
	tp.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	tp.position = Vector2(16, -70)
	var th := HBoxContainer.new()
	tool_icon = TextureRect.new()
	tool_icon.custom_minimum_size = Vector2(32, 32)
	tool_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tool_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tool_label = Label.new()
	tool_label.add_theme_font_size_override("font_size", UiTheme.size(18))
	th.add_child(tool_icon)
	th.add_child(tool_label)
	tp.add_child(th)
	root.add_child(tp)
	# The hand tool means nothing in the cut view, which has its own tool strip.
	Events.view_mode_changed.connect(func(m: StringName) -> void:
		tp.visible = m != &"cut"
		thread_label.visible = m != &"cut"
		if m == &"cut":
			_map_box.visible = false
		else:
			_apply_minimap_size())
	# Prompt (bottom-centre).
	# A bottom-wide centring strip keeps the prompt centred whatever its width.
	var prompt_strip := CenterContainer.new()
	prompt_strip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	prompt_strip.offset_top = -124
	prompt_strip.offset_bottom = -76
	prompt_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(prompt_strip)
	prompt_panel = PanelContainer.new()
	prompt_label = Label.new()
	prompt_label.add_theme_font_size_override("font_size", UiTheme.size(20))
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_panel.add_child(prompt_label)
	prompt_panel.visible = false
	prompt_strip.add_child(prompt_panel)
	caption_label = Label.new()
	caption_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	caption_label.offset_top = -164
	caption_label.offset_bottom = -134
	caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption_label.add_theme_font_size_override("font_size", UiTheme.size(18))
	caption_label.add_theme_color_override("font_color", UiTheme.DIM)
	caption_label.modulate.a = 0.0
	root.add_child(caption_label)
	# Toasts (right side).
	toast_box = VBoxContainer.new()
	toast_box.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	toast_box.position = Vector2(-330, -40)
	toast_box.custom_minimum_size = Vector2(310, 0)
	toast_box.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(toast_box)
	# Breath meter (top-centre, hazards only).
	breath_bar = ProgressBar.new()
	breath_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	breath_bar.position = Vector2(-110, 20)
	breath_bar.size = Vector2(220, 14)
	breath_bar.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("121116cc")
	bg.border_color = UiTheme.BORDER
	bg.set_border_width_all(1)
	var fg := StyleBoxFlat.new()
	fg.bg_color = UiTheme.LIVING
	breath_bar.add_theme_stylebox_override("background", bg)
	breath_bar.add_theme_stylebox_override("fill", fg)
	breath_bar.visible = false
	root.add_child(breath_bar)
	# Save indicator (bottom-right).
	var sh := HBoxContainer.new()
	sh.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	sh.position = Vector2(-150, -44)
	save_icon = TextureRect.new()
	save_icon.texture = UiTheme.icon("gear")
	save_icon.custom_minimum_size = Vector2(24, 24)
	save_icon.pivot_offset = Vector2(12, 12)
	save_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	save_label = Label.new()
	save_label.add_theme_font_size_override("font_size", UiTheme.size(16))
	save_label.add_theme_color_override("font_color", UiTheme.DIM)
	sh.add_child(save_icon)
	sh.add_child(save_label)
	sh.modulate.a = 0.0
	sh.name = "SaveBox"
	root.add_child(sh)


func _process(delta: float) -> void:
	dial_label.text = "Day %d · %s" % [Clock.day, Clock.time_string()]
	var phase := Clock.phase()
	var breath := Clock.breath()
	var b := ""
	if breath == "exhale":
		b = " · the Deep exhales"
	elif breath == "inhale":
		b = " · the Deep inhales"
	phase_label.text = phase.capitalize() + b
	money_label.text = "%d" % GameState.money()
	if _map_box.visible:
		var a := GameState.current_area
		area_label.text = "Wick" if a == "wick" else String(ReachGen.node_by_id(GameState.reach_graph, a).get("name", ""))
	var notes := Threads.active_notes()
	thread_label.text = String(notes[0].note) if not notes.is_empty() else ""
	var tool := GameState.current_tool()
	tool_icon.texture = UiTheme.icon("tool_" + _tool_icon(tool))
	var extra := ""
	if tool == "can":
		extra = "  %d/10" % int(GameState.player.get("can", 0))
	tool_label.text = "%s%s   [%s]" % [_tool_name(tool), extra, Settings.binding_label("tool_next")]
	if _notice_t > 0.0:
		_notice_t -= delta
		notice_label.modulate.a = clampf(_notice_t, 0.0, 1.0)
	if _caption_t > 0.0:
		_caption_t -= delta
		caption_label.modulate.a = clampf(_caption_t, 0.0, 1.0)
	var sb: Control = root.get_node("SaveBox")
	if _saving:
		save_icon.rotation += delta * 4.0
		sb.modulate.a = 1.0
	elif _save_t > 0.0:
		_save_t -= delta
		sb.modulate.a = clampf(_save_t, 0.0, 1.0)


static func _tool_icon(tool: String) -> String:
	return {"hands": "hands", "tiller": "tiller", "can": "can", "hammer": "hammer", "wrench": "wrench", "glass": "glass"}.get(tool, "hands")


static func _tool_name(tool: String) -> String:
	return {"hands": "Hands", "tiller": "Tiller", "can": "Watering can", "hammer": "Knapping hammer",
		"wrench": "Wrench", "glass": "Plumb-glass"}.get(tool, tool.capitalize())


## Settings.access.minimap: 0 hidden, 1 small, 2 large.
func _apply_minimap_size() -> void:
	var m := int(Settings.access.get("minimap", 1))
	_map_box.visible = m > 0 and GameState.view_mode != "cut"
	minimap.custom_minimum_size = Vector2(300, 240) if m == 2 else Vector2(184, 150)
	minimap.zoom = 1.25 if m == 2 else 1.0


func cycle_minimap() -> void:
	Settings.access["minimap"] = (int(Settings.access.get("minimap", 1)) + 1) % 3
	Settings.save_settings()
	_apply_minimap_size()
	Audio.ui("ui_tick", -10.0)


func set_prompt(text: String) -> void:
	if text.is_empty():
		prompt_panel.visible = false
		return
	prompt_label.text = text
	prompt_panel.visible = true


func toast(text: String, kind: StringName = &"info") -> void:
	var p := PanelContainer.new()
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", UiTheme.size(17))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(250, 0)
	match kind:
		&"warn": l.add_theme_color_override("font_color", UiTheme.DANGER)
		&"thread": l.add_theme_color_override("font_color", UiTheme.ACCENT)
		&"learn": l.add_theme_color_override("font_color", UiTheme.LIVING)
	h.add_child(l)
	p.add_child(h)
	toast_box.add_child(p)
	p.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.2)
	tw.tween_interval(3.2 if kind != &"thread" else 5.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)
	while toast_box.get_child_count() > 5:
		toast_box.get_child(0).queue_free()
		toast_box.remove_child(toast_box.get_child(0))


func notice(text: String) -> void:
	notice_label.text = text
	_notice_t = 3.5


func caption(text: String, seconds: float) -> void:
	if not Settings.access.get("captions", true):
		return
	caption_label.text = text
	_caption_t = seconds


## A chapter title across the top of the screen: small label, large title, a rule; fades in,
## holds, fades out, without stopping play.
func banner(small: String, big: String) -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	box.position = Vector2(-300, 92)
	box.custom_minimum_size = Vector2(600, 0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var a := Label.new()
	a.text = small.to_upper()
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	a.add_theme_font_size_override("font_size", UiTheme.size(16))
	a.add_theme_color_override("font_color", UiTheme.LIVING)
	var b := Label.new()
	b.text = big
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_font_size_override("font_size", UiTheme.size(40))
	b.add_theme_color_override("font_color", UiTheme.ACCENT)
	b.add_theme_constant_override("outline_size", 8)
	b.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.07, 0.9))
	var rule := ColorRect.new()
	rule.color = UiTheme.BORDER
	rule.custom_minimum_size = Vector2(0, 2)
	box.add_child(a)
	box.add_child(b)
	box.add_child(rule)
	root.add_child(box)
	box.modulate.a = 0.0
	Audio.ui("chime", -6.0)
	var tw := create_tween()
	tw.tween_property(box, "modulate:a", 1.0, 1.2)
	tw.parallel().tween_property(box, "position:y", 100.0, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_interval(3.5)
	tw.tween_property(box, "modulate:a", 0.0, 1.4)
	tw.tween_callback(box.queue_free)


func set_breath(value: float, show: bool) -> void:
	breath_bar.visible = show
	breath_bar.value = value * 100.0


func _on_saved(_slot: int, ok: bool) -> void:
	_saving = false
	_save_t = 2.5
	save_label.text = "Saved" if ok else "Save failed"
