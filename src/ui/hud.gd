class_name Hud
extends CanvasLayer
## The heads-up display: small brass plaques at the corners, nothing in the middle unless it
## matters. Clock and phase (top-left), glim, minimap and the current note (top-right), the
## tool in hand (bottom-left), prompts (bottom-centre), toasts (right), the air gauge only
## when the air is bad, and the save gear when Wick saves itself.

const TOAST_MAX := 4

var root: Control
var dial_label: Label
var phase_label: Label
var phase_icon: TextureRect
var money_label: Label
var money_plate: Control
var note_plate: PanelContainer
var note_title: Label
var note_text: Label
var tool_icon: TextureRect
var tool_label: Label
var tool_plate: Control
var prompt_panel: PanelContainer
var prompt_key: Label
var prompt_label: Label
var toast_box: VBoxContainer
var notice_label: Label
var caption_label: Label
var breath_box: PanelContainer
var breath_bar: TextureProgressBar
var save_icon: TextureRect
var save_label: Label
var minimap: Minimap
var area_label: Label
var _map_box: Control
var _notice_t := 0.0
var _caption_t := 0.0
var _save_t := 0.0
var _saving := false
var _shown_money := -1.0
var _note_id := ""
var _phase := ""
var _breath_t := 0.0
var _pulse_note := false
var hint_plate: PanelContainer
var _hints: Array = []                   ## queued [id, keys, done Callable, seconds]
var _hint_now: Array = []
var _hint_t := 0.0


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
	# Toasts rise above the dialogue box while someone is talking, and settle back after.
	Events.dialogue_started.connect(func(_n: StringName) -> void: _lift_toasts(true))
	Events.dialogue_ended.connect(func(_n: StringName) -> void: _lift_toasts(false))
	Events.prompt_changed.connect(set_prompt)
	# Panels cover the middle of the screen; keep the corners quiet while they're up.
	Events.ui_open.connect(func(_p: StringName, _d: Dictionary) -> void:
		note_plate.visible = false
		_map_box.visible = false
		prompt_panel.visible = false)
	Events.ui_closed.connect(func(_p: StringName) -> void:
		_note_id = "~"
		_apply_minimap_size())
	Events.save_started.connect(func(_s: int) -> void: _saving = true; _save_t = 0.0)
	Events.save_finished.connect(_on_saved)
	Events.settings_changed.connect(func(s: StringName) -> void:
		if s == &"access":
			UiTheme.invalidate()
			root.theme = UiTheme.get_theme()
			for p in [money_plate, tool_plate, note_plate, breath_box, prompt_panel]:
				(p as Control).add_theme_stylebox_override("panel", UiTheme.frame("hud", 2))
			_apply_minimap_size())


func _plate() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.frame("hud", 2))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _glyph(name: String, px: int) -> TextureRect:
	var t := TextureRect.new()
	t.texture = UiTheme.icon(name)
	t.custom_minimum_size = Vector2(px, px)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return t


func _build() -> void:
	# Clock (top-left): the phase glyph, the day and time, the phase and the Deep's breath.
	var dial := _plate()
	dial.position = Vector2(16, 14)
	var dh := HBoxContainer.new()
	dh.add_theme_constant_override("separation", 10)
	phase_icon = _glyph("ph_wake", 36)
	phase_icon.pivot_offset = Vector2(18, 18)
	dh.add_child(phase_icon)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", -2)
	dial_label = Label.new()
	dial_label.add_theme_font_size_override("font_size", UiTheme.size(22))
	phase_label = Label.new()
	phase_label.add_theme_color_override("font_color", UiTheme.DIM)
	phase_label.add_theme_font_size_override("font_size", UiTheme.size(15))
	dv.add_child(dial_label)
	dv.add_child(phase_label)
	dh.add_child(dv)
	dial.add_child(dh)
	root.add_child(dial)
	notice_label = Label.new()
	notice_label.position = Vector2(22, 92)
	notice_label.add_theme_color_override("font_color", UiTheme.LIVING)
	notice_label.add_theme_font_size_override("font_size", UiTheme.size(17))
	notice_label.add_theme_constant_override("outline_size", 6)
	notice_label.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.06, 0.85))
	notice_label.modulate.a = 0.0
	root.add_child(notice_label)
	# Top-right column: glim, the minimap, the current note.
	var tr := VBoxContainer.new()
	tr.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tr.position = Vector2(-16, 14)
	tr.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tr.add_theme_constant_override("separation", 8)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	money_plate = _plate()
	money_plate.size_flags_horizontal = Control.SIZE_SHRINK_END
	var mh := HBoxContainer.new()
	mh.add_theme_constant_override("separation", 6)
	mh.add_child(_glyph("glim", 24))
	money_label = Label.new()
	money_label.add_theme_font_size_override("font_size", UiTheme.size(20))
	money_label.custom_minimum_size = Vector2(44, 0)
	money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mh.add_child(money_label)
	money_plate.add_child(mh)
	tr.add_child(money_plate)
	var mbox := VBoxContainer.new()
	mbox.size_flags_horizontal = Control.SIZE_SHRINK_END
	mbox.add_theme_constant_override("separation", 2)
	var mframe := PanelContainer.new()
	mframe.add_theme_stylebox_override("panel", UiTheme.frame("hud", -6))
	mframe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap = Minimap.new()
	minimap.custom_minimum_size = Vector2(184, 150)
	mframe.add_child(minimap)
	mbox.add_child(mframe)
	area_label = Label.new()
	area_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	area_label.add_theme_font_size_override("font_size", UiTheme.size(15))
	area_label.add_theme_color_override("font_color", UiTheme.TEXT)
	area_label.add_theme_constant_override("outline_size", 6)
	area_label.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.06, 0.85))
	mbox.add_child(area_label)
	tr.add_child(mbox)
	_map_box = mbox
	_apply_minimap_size()
	note_plate = _plate()
	note_plate.size_flags_horizontal = Control.SIZE_SHRINK_END
	note_plate.custom_minimum_size = Vector2(300, 0)
	var nh := HBoxContainer.new()
	nh.add_theme_constant_override("separation", 8)
	var pin := _glyph("ui_pin", 20)
	pin.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	nh.add_child(pin)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", 0)
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note_title = Label.new()
	note_title.add_theme_font_size_override("font_size", UiTheme.size(15))
	note_title.add_theme_color_override("font_color", UiTheme.ACCENT)
	note_text = Label.new()
	note_text.add_theme_font_size_override("font_size", UiTheme.size(15))
	note_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_text.custom_minimum_size = Vector2(250, 0)
	nv.add_child(note_title)
	nv.add_child(note_text)
	nh.add_child(nv)
	note_plate.add_child(nh)
	note_plate.visible = false
	tr.add_child(note_plate)
	root.add_child(tr)
	# Tool in hand (bottom-left).
	tool_plate = _plate()
	tool_plate.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	tool_plate.position = Vector2(16, -74)
	tool_plate.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 8)
	tool_icon = _glyph("tool_hands", 34)
	tool_label = Label.new()
	tool_label.add_theme_font_size_override("font_size", UiTheme.size(18))
	th.add_child(tool_icon)
	th.add_child(tool_label)
	th.add_child(UiTheme.keycap(Settings.binding_label("tool_next")))
	tool_plate.add_child(th)
	root.add_child(tool_plate)
	# The hand tool means nothing in the cut view, which has its own tool strip.
	Events.view_mode_changed.connect(func(m: StringName) -> void:
		tool_plate.visible = m != &"cut"
		_note_id = "~"
		if m == &"cut":
			_map_box.visible = false
			note_plate.visible = false
		else:
			_apply_minimap_size())
	# Prompt (bottom-centre): a key cap and what it does.
	var prompt_strip := CenterContainer.new()
	prompt_strip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	prompt_strip.offset_top = -128
	prompt_strip.offset_bottom = -76
	prompt_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(prompt_strip)
	prompt_panel = _plate()
	var ph := HBoxContainer.new()
	ph.add_theme_constant_override("separation", 10)
	var cap := PanelContainer.new()
	cap.add_theme_stylebox_override("panel", UiTheme.frame("button_hover", -1))
	prompt_key = Label.new()
	prompt_key.add_theme_font_size_override("font_size", UiTheme.size(17))
	prompt_key.add_theme_color_override("font_color", UiTheme.ACCENT)
	cap.add_child(prompt_key)
	ph.add_child(cap)
	prompt_label = Label.new()
	prompt_label.add_theme_font_size_override("font_size", UiTheme.size(19))
	prompt_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ph.add_child(prompt_label)
	prompt_panel.add_child(ph)
	prompt_panel.visible = false
	prompt_strip.add_child(prompt_panel)
	# First-time hints sit above the prompt: key caps and what they do.
	var hint_strip := CenterContainer.new()
	hint_strip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint_strip.offset_top = -232
	hint_strip.offset_bottom = -180
	hint_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hint_strip)
	hint_plate = _plate()
	hint_plate.visible = false
	hint_strip.add_child(hint_plate)
	caption_label = Label.new()
	caption_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	caption_label.offset_top = -168
	caption_label.offset_bottom = -138
	caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption_label.add_theme_font_size_override("font_size", UiTheme.size(18))
	caption_label.add_theme_color_override("font_color", UiTheme.TEXT)
	caption_label.add_theme_constant_override("outline_size", 6)
	caption_label.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.06, 0.9))
	caption_label.modulate.a = 0.0
	root.add_child(caption_label)
	# Toasts (right edge, above the save gear), newest at the bottom.
	toast_box = VBoxContainer.new()
	toast_box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	toast_box.position = Vector2(-336, -96)
	toast_box.custom_minimum_size = Vector2(320, 0)
	toast_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	toast_box.alignment = BoxContainer.ALIGNMENT_END
	toast_box.add_theme_constant_override("separation", 6)
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toast_box)
	# Air gauge (top-centre, hazards only).
	breath_box = _plate()
	breath_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	breath_box.position = Vector2(-150, 16)
	breath_box.custom_minimum_size = Vector2(300, 0)
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 8)
	bh.add_child(_glyph("ui_breath", 26))
	var bl := Label.new()
	bl.text = "Air"
	bl.add_theme_font_size_override("font_size", UiTheme.size(16))
	bl.add_theme_color_override("font_color", UiTheme.DIM)
	bh.add_child(bl)
	breath_bar = TextureProgressBar.new()
	breath_bar.texture_under = load(UiTheme.UI_DIR + "gauge_track.png")
	breath_bar.texture_progress = load(UiTheme.UI_DIR + "gauge_fill.png")
	breath_bar.nine_patch_stretch = true
	for side in ["stretch_margin_left", "stretch_margin_right", "stretch_margin_top", "stretch_margin_bottom"]:
		breath_bar.set(side, 6)
	breath_bar.custom_minimum_size = Vector2(200, 16)
	breath_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	breath_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	breath_bar.max_value = 100.0
	bh.add_child(breath_bar)
	breath_box.add_child(bh)
	breath_box.visible = false
	root.add_child(breath_box)
	# Save indicator (bottom-right).
	var sh := HBoxContainer.new()
	sh.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	sh.position = Vector2(-150, -44)
	save_icon = _glyph("gear", 24)
	save_icon.pivot_offset = Vector2(12, 12)
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
	if phase != _phase:
		var first := _phase == ""
		_phase = phase
		phase_icon.texture = UiTheme.icon("ph_" + phase)
		if not first:
			var tw := create_tween()
			phase_icon.scale = Vector2(1.5, 1.5)
			tw.tween_property(phase_icon, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var breath := Clock.breath()
	var b := ""
	if breath == "exhale":
		b = " · the Deep exhales"
	elif breath == "inhale":
		b = " · the Deep inhales"
	phase_label.text = phase.capitalize() + b
	_tick_money(delta)
	_tick_hint(delta)
	if _map_box.visible:
		var a := GameState.current_area
		area_label.text = "Wick" if a == "wick" else String(ReachGen.node_by_id(GameState.reach_graph, a).get("name", ""))
	_update_note()
	var tool := GameState.current_tool()
	tool_icon.texture = UiTheme.icon("tool_" + _tool_icon(tool))
	var extra := ""
	if tool == "can":
		extra = "  %d/10" % int(GameState.player.get("can", 0))
	tool_label.text = _tool_name(tool) + extra
	if _notice_t > 0.0:
		_notice_t -= delta
		notice_label.modulate.a = clampf(_notice_t, 0.0, 1.0)
	if _caption_t > 0.0:
		_caption_t -= delta
		caption_label.modulate.a = clampf(_caption_t, 0.0, 1.0)
	if breath_box.visible:
		_breath_t += delta
		var low := breath_bar.value < 30.0
		breath_bar.tint_progress = Color(1.0, 0.55, 0.45) if low else Color.WHITE
		breath_box.modulate = Color(1, 1, 1, 0.75 + 0.25 * absf(sin(_breath_t * 5.0))) if low else Color.WHITE
	var sb: Control = root.get_node("SaveBox")
	if _saving:
		save_icon.rotation += delta * 4.0
		sb.modulate.a = 1.0
	elif _save_t > 0.0:
		_save_t -= delta
		sb.modulate.a = clampf(_save_t, 0.0, 1.0)


## The glim counter runs to its new value rather than jumping, and flashes on a change.
func _tick_money(delta: float) -> void:
	var target := float(GameState.money())
	if _shown_money < 0.0:
		_shown_money = target
	if absf(target - _shown_money) > 0.01:
		var up := target > _shown_money
		var step := maxf(1.0, absf(target - _shown_money) * 6.0 * delta)
		_shown_money = move_toward(_shown_money, target, step)
		money_label.add_theme_color_override("font_color", UiTheme.LIVING if up else UiTheme.DANGER)
	else:
		_shown_money = target
		money_label.add_theme_color_override("font_color", UiTheme.TEXT)
	money_label.text = "%d" % int(round(_shown_money))


func _update_note() -> void:
	var notes := Threads.active_notes()
	var id := String(notes[0].id) + ":" + str(Threads.stage(String(notes[0].id))) if not notes.is_empty() else ""
	if id == _note_id:
		return
	_note_id = id
	var show := not notes.is_empty() and GameState.view_mode != "cut" and not _panels_open()
	note_plate.visible = show
	if notes.is_empty():
		return
	note_title.text = String(notes[0].title)
	note_text.text = String(notes[0].note)
	if show and _pulse_note:
		_pulse_note = false
		note_plate.pivot_offset = note_plate.size * 0.5
		note_plate.scale = Vector2(1.06, 1.06)
		note_plate.modulate = Color(1.6, 1.3, 0.8)
		var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(note_plate, "scale", Vector2.ONE, 0.5)
		tw.tween_property(note_plate, "modulate", Color.WHITE, 1.2)
	elif show:
		note_plate.modulate.a = 0.0
		create_tween().tween_property(note_plate, "modulate:a", 1.0, 0.4)


func _panels_open() -> bool:
	var g := get_tree().current_scene
	return g != null and g.get("panels") != null and g.panels.has_method("is_open") and g.panels.is_open()


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


## "[E] Talk to Mags" becomes a key cap and the words.
func set_prompt(text: String) -> void:
	if text.is_empty():
		prompt_panel.visible = false
		return
	var key := ""
	var words := text
	if text.begins_with("[") and text.find("]") > 0:
		key = text.substr(1, text.find("]") - 1)
		words = text.substr(text.find("]") + 1).strip_edges()
	prompt_key.get_parent().visible = key != ""
	prompt_key.text = key
	prompt_label.text = words
	if not prompt_panel.visible:
		prompt_panel.visible = true
		prompt_panel.modulate.a = 0.0
		create_tween().tween_property(prompt_panel, "modulate:a", 1.0, 0.12)


## A toast slides in from the right edge. Repeats of the same pickup merge ("+1 Glowbeet",
## "+1 Glowbeet" becomes "+2 Glowbeet") and never more than four are up at once.
func toast(text: String, kind: StringName = &"info") -> void:
	# A new step on the note already pinned top-right: flash the plaque, don't repeat it.
	if kind == &"thread" and GameState.view_mode != "cut":
		var notes := Threads.active_notes()
		if not notes.is_empty() and String(notes[0].note) == text:
			_note_id = "~"
			_pulse_note = true
			return
	var item := ""
	var n := 0
	if kind == &"item" and text.begins_with("+"):
		var sp := text.find(" ")
		n = int(text.substr(1, sp - 1))
		item = Content.item_id_by_name(text.substr(sp + 1))
		for c in toast_box.get_children():
			if c.get_meta("item", "") == item and item != "" and not c.is_queued_for_deletion():
				var total := int(c.get_meta("n", 0)) + n
				c.set_meta("n", total)
				(c.get_meta("label") as Label).text = "+%d %s" % [total, Content.item_name(item)]
				c.set_meta("life", 3.2)
				var pop := create_tween()
				c.scale = Vector2(1.06, 1.06)
				pop.tween_property(c, "scale", Vector2.ONE, 0.18)
				return
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.frame("toast", 4))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var glyph := ""
	match kind:
		&"item": glyph = item if item != "" else "ui_pack"
		&"warn": glyph = "st_warn"
		&"thread": glyph = "ui_pin"
		&"learn": glyph = "ui_book"
		&"good": glyph = "st_ok"
		&"event": glyph = "ph_hush"
	if glyph != "":
		h.add_child(_glyph(glyph, 24))
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", UiTheme.size(16))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(250, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	match kind:
		&"warn": l.add_theme_color_override("font_color", UiTheme.DANGER)
		&"thread": l.add_theme_color_override("font_color", UiTheme.ACCENT)
		&"learn", &"good": l.add_theme_color_override("font_color", UiTheme.LIVING)
	h.add_child(l)
	p.add_child(h)
	p.set_meta("item", item)
	p.set_meta("n", n)
	p.set_meta("label", l)
	p.set_meta("life", 5.0 if kind in [&"thread", &"event", &"learn"] else 3.2)
	toast_box.add_child(p)
	p.pivot_offset = Vector2(160, 20)
	p.modulate.a = 0.0
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(p, "modulate:a", 1.0, 0.18)
	while toast_box.get_child_count() > TOAST_MAX:
		var old := toast_box.get_child(0)
		toast_box.remove_child(old)
		old.queue_free()


## Shows a hint once per save: `keys` is [[key, what it does], ...]. It stays until `done`
## returns true (or for `seconds` if no test is given), one hint at a time.
func hint(id: String, keys: Array, done: Callable = Callable(), seconds := 7.0) -> void:
	if GameState.has_flag("hint_" + id):
		return
	for h: Array in _hints:
		if String(h[0]) == id:
			return
	if not _hint_now.is_empty() and String(_hint_now[0]) == id:
		return
	_hints.append([id, keys, done, seconds])


func _tick_hint(delta: float) -> void:
	if _hint_now.is_empty():
		if _hints.is_empty() or Dialogue.active or _panels_open():
			return
		_hint_now = _hints.pop_front()
		_hint_t = 0.0
		for c in hint_plate.get_children():
			hint_plate.remove_child(c)
			c.queue_free()
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		for pair: Array in _hint_now[1]:
			row.add_child(UiTheme.keycap(String(pair[0]), String(pair[1])))
		hint_plate.add_child(row)
		hint_plate.visible = true
		hint_plate.modulate.a = 0.0
		create_tween().tween_property(hint_plate, "modulate:a", 1.0, 0.4)
		GameState.set_flag("hint_" + String(_hint_now[0]))
		return
	_hint_t += delta
	var done: Callable = _hint_now[2]
	var finished := (done.is_valid() and bool(done.call()) and _hint_t > 1.5) or (not done.is_valid() and _hint_t > float(_hint_now[3])) \
		or _hint_t > 45.0
	hint_plate.visible = not Dialogue.active and not _panels_open()
	if finished:
		_hint_now = []
		var tw := create_tween()
		tw.tween_property(hint_plate, "modulate:a", 0.0, 0.5)
		tw.tween_callback(func() -> void:
			if _hint_now.is_empty():
				hint_plate.visible = false)


func _lift_toasts(up: bool) -> void:
	var bottom := -236.0 if up else -96.0
	var d := bottom - toast_box.offset_bottom
	if absf(d) < 0.5:
		return
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(toast_box, "offset_bottom", bottom, 0.25)
	tw.tween_property(toast_box, "offset_top", toast_box.offset_top + d, 0.25)


func _physics_process(delta: float) -> void:
	for c in toast_box.get_children():
		var life := float(c.get_meta("life", 0.0)) - delta
		c.set_meta("life", life)
		if life < 0.5:
			c.modulate.a = clampf(life / 0.5, 0.0, 1.0)
		if life <= 0.0:
			toast_box.remove_child(c)
			c.queue_free()


func notice(text: String) -> void:
	notice_label.text = text
	_notice_t = 3.5


func caption(text: String, seconds: float) -> void:
	if not Settings.access.get("captions", true):
		return
	caption_label.text = text
	_caption_t = seconds


## A chapter title across the top of the screen: small label, large title, a brass rule;
## fades in, holds, fades out, without stopping play.
func banner(small: String, big: String) -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	box.position = Vector2(-320, 92)
	box.custom_minimum_size = Vector2(640, 0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var a := Label.new()
	a.text = small.to_upper()
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	a.add_theme_font_size_override("font_size", UiTheme.size(16))
	a.add_theme_color_override("font_color", UiTheme.LIVING)
	a.add_theme_constant_override("outline_size", 6)
	a.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.07, 0.9))
	var b := Label.new()
	b.text = big
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_font_size_override("font_size", UiTheme.size(42))
	b.add_theme_color_override("font_color", UiTheme.ACCENT)
	b.add_theme_constant_override("outline_size", 10)
	b.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.07, 0.92))
	var rule := BrassRule.new()
	rule.custom_minimum_size = Vector2(420, 14)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
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


## Arriving somewhere: the region small, the place large, under the top edge. A first visit
## gets a chime and stays a little longer.
func place_card(region: String, place: String, first: bool) -> void:
	for c in root.get_children():
		if c.name == "PlaceCard":
			c.queue_free()
	var box := VBoxContainer.new()
	box.name = "PlaceCard"
	box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	box.position = Vector2(-300, 70)
	box.custom_minimum_size = Vector2(600, 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 0)
	var a := Label.new()
	a.text = region.to_upper()
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	a.add_theme_font_size_override("font_size", UiTheme.size(14))
	a.add_theme_color_override("font_color", UiTheme.DIM)
	a.add_theme_constant_override("outline_size", 6)
	a.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.06, 0.9))
	var b := Label.new()
	b.text = place
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_font_size_override("font_size", UiTheme.size(32 if first else 26))
	b.add_theme_color_override("font_color", UiTheme.TEXT if not first else UiTheme.ACCENT)
	b.add_theme_constant_override("outline_size", 8)
	b.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.06, 0.92))
	box.add_child(a)
	box.add_child(b)
	if first:
		var rule := BrassRule.new()
		rule.custom_minimum_size = Vector2(260, 14)
		rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(rule)
		Audio.ui("reveal" if ResourceLoader.exists("res://assets/audio/sfx/reveal.ogg") else "chime", -8.0)
	root.add_child(box)
	box.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(box, "modulate:a", 1.0, 0.6)
	tw.parallel().tween_property(box, "position:y", 78.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_interval(2.6 if first else 1.4)
	tw.tween_property(box, "modulate:a", 0.0, 0.9)
	tw.tween_callback(box.queue_free)


func set_breath(value: float, show: bool) -> void:
	if show and not breath_box.visible:
		breath_box.modulate.a = 0.0
		create_tween().tween_property(breath_box, "modulate:a", 1.0, 0.3)
	breath_box.visible = show
	breath_bar.value = value * 100.0


func _on_saved(_slot: int, ok: bool) -> void:
	_saving = false
	_save_t = 2.5
	save_label.text = "Saved" if ok else "Save failed"
