class_name SettingsPanel
extends RefCounted
## The settings tabs, shared by the pause menu and the title screen. Every change applies
## immediately and is saved; nothing needs an "Apply" button.

const ACTION_NAMES := {
	"move_up": "Move up", "move_down": "Move down", "move_left": "Move left", "move_right": "Move right",
	"run": "Run (hold)", "minimap": "Minimap size",
	"interact": "Interact / talk", "context": "Use tool", "confirm": "Confirm", "cancel": "Back / cancel",
	"menu": "Pause", "inventory": "Pack", "tool_next": "Next tool", "tool_prev": "Previous tool",
	"primary": "Primary (cut view: place)", "secondary": "Secondary (cycle seed / stop)",
	"cut_view": "Plumb-glass (cut view)", "journal": "Journal", "map": "Map", "overlay_next": "Overlay",
	"build_menu": "Build menu", "time_pause": "Pause time (cut view)", "time_speed": "Time speed (cut view)",
}


static func build() -> Control:
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(_scroll(_graphics()))
	tabs.set_tab_title(0, "Graphics")
	tabs.add_child(_scroll(_audio()))
	tabs.set_tab_title(1, "Sound")
	tabs.add_child(_scroll(_access()))
	tabs.set_tab_title(2, "Accessibility")
	tabs.add_child(_scroll(_controls()))
	tabs.set_tab_title(3, "Controls")
	return tabs


static func _scroll(c: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(c)
	return s


static func _box() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	return v


static func _row(label: String, control: Control, note := "") -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(300, 0)
	l.add_theme_font_size_override("font_size", UiTheme.size(18))
	if note != "":
		l.tooltip_text = note
		l.mouse_filter = Control.MOUSE_FILTER_STOP
	h.add_child(l)
	control.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if control is CheckButton else Control.SIZE_EXPAND_FILL
	h.add_child(control)
	return h


static func _check(on: bool, cb: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.button_pressed = on
	c.toggled.connect(func(v: bool) -> void:
		cb.call(v)
		Settings.save_settings())
	return c


static func _slider(value: float, lo: float, hi: float, step: float, cb: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(260, 24)
	s.value_changed.connect(func(v: float) -> void: cb.call(v))
	s.drag_ended.connect(func(_c: bool) -> void: Settings.save_settings())
	s.focus_exited.connect(func() -> void: Settings.save_settings())
	return s


static func _options(items: Array, current: String, cb: Callable) -> OptionButton:
	var o := OptionButton.new()
	for i in items.size():
		o.add_item(String(items[i]).capitalize(), i)
		if String(items[i]) == current:
			o.select(i)
	o.item_selected.connect(func(i: int) -> void:
		cb.call(String(items[i]))
		Settings.save_settings())
	return o


static func _graphics() -> Control:
	var g: Dictionary = Settings.graphics
	var v := _box()
	v.add_child(_row("Quality preset", _options(["low", "medium", "high", "ultra"], String(g.get("preset", "high")),
		func(p: String) -> void: Settings.apply_preset(p))))
	v.add_child(_row("Window", _options(["windowed", "borderless", "fullscreen"], String(g.get("window_mode", "windowed")),
		func(m: String) -> void: Settings.set_graphics("window_mode", m))))
	v.add_child(_row("V-sync", _check(bool(g.get("vsync", true)), func(on: bool) -> void: Settings.set_graphics("vsync", on))))
	v.add_child(_row("Shadows", _check(bool(g.get("shadows", true)), func(on: bool) -> void: Settings.set_graphics("shadows", on))))
	v.add_child(_row("Depth of field (miniature blur)", _check(bool(g.get("dof", true)), func(on: bool) -> void: Settings.set_graphics("dof", on))))
	v.add_child(_row("Glow", _check(bool(g.get("glow", true)), func(on: bool) -> void: Settings.set_graphics("glow", on))))
	v.add_child(_row("Ambient occlusion", _check(bool(g.get("ssao", true)), func(on: bool) -> void: Settings.set_graphics("ssao", on))))
	v.add_child(_row("Particles", _slider(float(g.get("particles", 1.0)), 0.0, 1.0, 0.05, func(x: float) -> void: Settings.set_graphics("particles", x))))
	v.add_child(_row("Render scale", _slider(float(g.get("render_scale", 1.0)), 0.5, 1.0, 0.05, func(x: float) -> void: Settings.set_graphics("render_scale", x)),
		"Lower renders the 3D world at a smaller size and scales it up. The pixel art doesn't mind much."))
	return v


static func _audio() -> Control:
	var v := _box()
	var names := {"Master": "Everything", "Music": "Music", "Ambience": "Ambience", "SFX": "Effects", "UI": "Interface", "Voice": "Voices"}
	for bus: String in ["Master"] + Settings.BUSES:
		var b := bus
		v.add_child(_row(String(names.get(bus, bus)), _slider(float(Settings.audio.get(bus, 0.8)), 0.0, 1.0, 0.05,
			func(x: float) -> void: Settings.set_volume(b, x))))
	return v


static func _access() -> Control:
	var a: Dictionary = Settings.access
	var v := _box()
	v.add_child(_row("Text size", _slider(float(a.get("font_scale", 1.0)), 0.75, 1.75, 0.05, func(x: float) -> void: Settings.set_access("font_scale", x))))
	v.add_child(_row("Readable font", _check(bool(a.get("readable_font", false)), func(on: bool) -> void: Settings.set_access("readable_font", on)),
		"Swaps the pixel font for Atkinson Hyperlegible, designed for low-vision readers."))
	v.add_child(_row("High-contrast panels", _check(bool(a.get("high_contrast", false)), func(on: bool) -> void: Settings.set_access("high_contrast", on))))
	v.add_child(_row("Captions for sounds", _check(bool(a.get("captions", true)), func(on: bool) -> void: Settings.set_access("captions", on))))
	v.add_child(_row("Text speed", _slider(float(a.get("text_speed", 1.0)), 0.25, 4.0, 0.25, func(x: float) -> void: Settings.set_access("text_speed", x))))
	v.add_child(_row("Screen shake", _check(bool(a.get("screen_shake", true)), func(on: bool) -> void: Settings.set_access("screen_shake", on))))
	v.add_child(_row("Shake strength", _slider(float(a.get("shake_scale", 0.6)), 0.0, 1.0, 0.05, func(x: float) -> void: Settings.set_access("shake_scale", x))))
	v.add_child(_row("Flashes", _slider(float(a.get("flash", 0.7)), 0.0, 1.0, 0.05, func(x: float) -> void: Settings.set_access("flash", x)),
		"Brightness of full-screen flashes (tremors, valves). Zero turns them off."))
	return v


static func _controls() -> Control:
	var v := _box()
	var note := Label.new()
	note.text = "Pick an action, then press the key or button you want. Keyboard and pad bindings are kept separately."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(300, 0)
	note.add_theme_color_override("font_color", UiTheme.DIM)
	v.add_child(note)
	for action: String in Settings.REMAPPABLE:
		var h := HBoxContainer.new()
		var l := Label.new()
		l.text = String(ACTION_NAMES.get(action, action.capitalize()))
		l.custom_minimum_size = Vector2(300, 0)
		h.add_child(l)
		var kb := RebindButton.new()
		kb.setup(action, "kb")
		h.add_child(kb)
		var pad := RebindButton.new()
		pad.setup(action, "pad")
		h.add_child(pad)
		v.add_child(h)
	var reset := Button.new()
	reset.text = "Reset all controls"
	reset.pressed.connect(func() -> void:
		Settings.reset_bindings()
		Settings.save_settings()
		for c in v.get_children():
			if c is HBoxContainer:
				for b in c.get_children():
					if b is RebindButton:
						(b as RebindButton).refresh())
	v.add_child(reset)
	return v


## Shows an action's binding for one device; click it, then press the new input.
class RebindButton:
	extends Button

	var action := ""
	var device := "kb"
	var listening := false

	func setup(a: String, d: String) -> void:
		action = a
		device = d
		custom_minimum_size = Vector2(170, 0)
		refresh()
		pressed.connect(func() -> void:
			listening = true
			text = "press a %s..." % ("key" if device == "kb" else "button"))

	func refresh() -> void:
		listening = false
		text = ("Keys: " if device == "kb" else "Pad: ") + Settings.binding_label(action, device)

	func _input(event: InputEvent) -> void:
		if not listening:
			return
		var pad_event := event is InputEventJoypadButton or event is InputEventJoypadMotion
		var kb_event := event is InputEventKey or event is InputEventMouseButton
		if not event.is_pressed() or (device == "pad" and not pad_event) or (device == "kb" and not kb_event):
			return
		if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and get_global_rect().has_point((event as InputEventMouseButton).position):
			return   # the click that started listening
		if event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) < 0.6:
			return
		get_viewport().set_input_as_handled()
		Settings.rebind(action, event)
		refresh()
