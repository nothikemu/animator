class_name EngUi
extends CanvasLayer
## Chrome for the Undercroft view: tool strip, overlay legend, hover line, inspect panel and
## build palette. Everything is reachable by mouse, keyboard and pad; nothing is read only
## through colour (status words accompany every colour, legends name every tint).

signal tool_picked(tool: String)
signal build_picked(def_id: String)
signal action_picked(action: String, arg: String)
signal panel_closed()

const TOOLS := [
	["inspect", "Look", "tool_glass"],
	["pipe", "Pipe", "pipe_section"],
	["wire", "Wire", "wire_coil"],
	["build", "Build", "gear"],
	["repair", "Mend", "tool_wrench"],
	["fill", "Pack", "blackstone"],
	["remove", "Salvage", "tool_hammer"],
]
const LEGENDS := {
	"gas": [["Sour gas — heavy, sinks", Color(0.71, 0.72, 0.29)], ["Stale air — settles low", Color(0.55, 0.59, 0.66)],
		["Damp air — rises", Color(0.65, 0.55, 0.84)], ["Fresh air (faint)", Color(0.85, 0.9, 0.95)]],
	"water": [["Pipes carrying water pulse", Color(0.5, 0.85, 0.9)], ["Cracked pipe — leaking", Color(0.9, 0.2, 0.12)],
		["Standing water", Color(0.2, 0.45, 0.6)]],
	"power": [["Live wire sparks", Color(1.0, 0.82, 0.35)], ["Burnt wire", Color(0.9, 0.2, 0.12)],
		["Copper wire", Color(0.62, 0.3, 0.2)]],
	"heat": [["Cold", Color(0.15, 0.3, 0.75)], ["Mild", Color(0.25, 0.6, 0.35)], ["Warm", Color(0.95, 0.75, 0.2)],
		["Scalding", Color(0.95, 0.25, 0.1)]],
}

var root: Control
var title_label: Label
var keys_label: Label
var tool_bar: HBoxContainer
var tool_buttons: Dictionary = {}
var hover_panel: PanelContainer
var hover_label: Label
var hint_label: Label
var side_panel: PanelContainer
var side_box: VBoxContainer
var legend: PanelContainer
var legend_box: VBoxContainer
var mode := ""                           ## "" | "inspect" | "build"
var _sprite_meta: Dictionary = {}


func _ready() -> void:
	layer = 11
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.get_theme()
	add_child(root)
	var meta: Variant = Content.read_json("res://assets/textures/machines/machines.json")
	_sprite_meta = meta if meta is Dictionary else {}
	_build()
	Events.inventory_changed.connect(func() -> void:
		if mode == "build":
			show_build_menu())
	Settings.device_changed.connect(func(_k: String) -> void: refresh_keys())


func _build() -> void:
	# Title + key hints (top centre).
	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.position = Vector2(-260, 12)
	top.custom_minimum_size = Vector2(520, 0)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label = Label.new()
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", UiTheme.size(24))
	title_label.add_theme_color_override("font_color", UiTheme.ACCENT)
	keys_label = Label.new()
	keys_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	keys_label.add_theme_font_size_override("font_size", UiTheme.size(15))
	keys_label.add_theme_color_override("font_color", UiTheme.DIM)
	top.add_child(title_label)
	top.add_child(keys_label)
	root.add_child(top)
	# Tool strip (bottom centre).
	var strip := PanelContainer.new()
	strip.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	strip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	strip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	strip.position = Vector2(0, -14)
	tool_bar = HBoxContainer.new()
	tool_bar.add_theme_constant_override("separation", 4)
	for i in TOOLS.size():
		var t: Array = TOOLS[i]
		var b := Button.new()
		b.text = "%d %s" % [i + 1, t[1]]
		b.icon = UiTheme.icon(String(t[2]))
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", 24)
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = _tool_tip(String(t[0]))
		var id := String(t[0])
		b.pressed.connect(func() -> void: tool_picked.emit(id))
		tool_bar.add_child(b)
		tool_buttons[id] = b
	strip.add_child(tool_bar)
	root.add_child(strip)
	# Hover line (just above the strip).
	hover_panel = PanelContainer.new()
	hover_panel.add_theme_stylebox_override("panel", UiTheme.panel_box(UiTheme.PANEL_DARK, UiTheme.BORDER_DIM, 1, 8))
	hover_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hover_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hover_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hover_panel.position = Vector2(0, -74)
	hover_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 0)
	hover_label = Label.new()
	hover_label.add_theme_font_size_override("font_size", UiTheme.size(18))
	hover_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label = Label.new()
	hint_label.add_theme_font_size_override("font_size", UiTheme.size(15))
	hint_label.add_theme_color_override("font_color", UiTheme.DIM)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hv.add_child(hover_label)
	hv.add_child(hint_label)
	hover_panel.add_child(hv)
	root.add_child(hover_panel)
	# Side panel (right): inspect or build palette.
	side_panel = PanelContainer.new()
	side_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	side_panel.offset_left = -360
	side_panel.offset_right = -14
	side_panel.offset_top = 96
	side_panel.offset_bottom = -140
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side_box = VBoxContainer.new()
	side_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_box.add_theme_constant_override("separation", 8)
	scroll.add_child(side_box)
	side_panel.add_child(scroll)
	side_panel.visible = false
	root.add_child(side_panel)
	# Overlay legend (bottom-left).
	legend = PanelContainer.new()
	legend.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	legend.grow_vertical = Control.GROW_DIRECTION_BEGIN
	legend.position = Vector2(14, -14)
	legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	legend_box = VBoxContainer.new()
	legend.add_child(legend_box)
	legend.visible = false
	root.add_child(legend)


func _tool_tip(id: String) -> String:
	match id:
		"inspect": return "Look at anything: machines say what's wrong in plain words."
		"pipe": return "Click and drag to lay pipe. Each cell uses one pipe section."
		"wire": return "Click and drag to run wire. Each cell uses one wire coil."
		"build": return "Place a machine you know how to make."
		"repair": return "Mend cracked pipe (seal gum) or burnt wire (a coil)."
		"fill": return "Pack an open cell with blackstone — seals gaps and stops gas."
		"remove": return "Take something apart and get half its materials back."
	return ""


func set_tool(id: String) -> void:
	for k in tool_buttons:
		(tool_buttons[k] as Button).button_pressed = k == id


func set_title(text: String) -> void:
	title_label.text = text


func refresh_keys() -> void:
	var k := func(a: String) -> String: return Settings.binding_label(a)
	keys_label.text = "[%s] overlay   [%s] build   [%s/%s] tool   [%s] pause   [%s] speed   [%s] back to the lane" % [
		k.call("overlay_next"), k.call("build_menu"), k.call("tool_prev") if Settings.last_device == "pad" else "1-7",
		k.call("tool_next"), k.call("time_pause"), k.call("time_speed"), k.call("cut_view")]


func set_hover(text: String, hint: String) -> void:
	hover_label.text = text
	hint_label.text = hint
	hover_panel.visible = text != "" or hint != ""


func set_overlay(o: String) -> void:
	for c in legend_box.get_children():
		c.queue_free()
	legend.visible = LEGENDS.has(o)
	if not legend.visible:
		return
	var head := Label.new()
	head.text = o.capitalize()
	head.add_theme_color_override("font_color", UiTheme.ACCENT)
	legend_box.add_child(head)
	for e: Array in LEGENDS[o]:
		var row := HBoxContainer.new()
		var sw := ColorRect.new()
		sw.color = e[1]
		sw.custom_minimum_size = Vector2(18, 18)
		var l := Label.new()
		l.text = String(e[0])
		l.add_theme_font_size_override("font_size", UiTheme.size(15))
		row.add_child(sw)
		row.add_child(l)
		legend_box.add_child(row)


func is_panel_open() -> bool:
	return side_panel.visible


func close_panel() -> void:
	if side_panel.visible:
		side_panel.visible = false
		mode = ""
		panel_closed.emit()


func focus_panel() -> void:
	for c in side_box.get_children():
		if c is Button and not (c as Button).disabled:
			(c as Button).grab_focus()
			return


func _clear() -> void:
	for c in side_box.get_children():
		side_box.remove_child(c)
		c.queue_free()


func _label(text: String, size := 17, color := UiTheme.TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(300, 0)
	l.add_theme_font_size_override("font_size", UiTheme.size(size))
	l.add_theme_color_override("font_color", color)
	return l


func machine_icon(def_id: String, scale := 2.0) -> TextureRect:
	var tr := TextureRect.new()
	var info: Dictionary = _sprite_meta.get(def_id, {})
	var path := "res://assets/textures/machines/%s.png" % def_id
	if info.is_empty() or not ResourceLoader.exists(path):
		return tr
	var a := AtlasTexture.new()
	a.atlas = load(path)
	a.region = Rect2(0, 0, float(info.w), float(info.h))
	tr.texture = a
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.custom_minimum_size = Vector2(minf(float(info.w) * scale, 96.0), minf(float(info.h) * scale, 96.0))
	return tr


static func status_color(s: StringName) -> Color:
	if s == &"ok":
		return UiTheme.LIVING
	if s == &"idle" or s == &"off":
		return UiTheme.DIM
	if s in [&"broken", &"flooded", &"overloaded", &"too_hot", &"choking"]:
		return UiTheme.DANGER
	return UiTheme.ACCENT


## Inspect panel for a machine. actions: [[action, arg, label, enabled]]
func show_machine(m: MachineState, d: Dictionary, lines: PackedStringArray, actions: Array) -> void:
	_clear()
	mode = "inspect"
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.add_child(machine_icon(m.def_id))
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 0)
	var name_l := _label(String(d.get("name", m.def_id)), 22)
	name_l.custom_minimum_size = Vector2(200, 0)
	hv.add_child(name_l)
	var st := _label(Inspect.status(m.status), 18, status_color(m.status))
	st.custom_minimum_size = Vector2(200, 0)
	hv.add_child(st)
	head.add_child(hv)
	side_box.add_child(head)
	side_box.add_child(_label(String(d.get("desc", "")), 15, UiTheme.DIM))
	side_box.add_child(HSeparator.new())
	for line in lines:
		side_box.add_child(_label("• " + line, 17))
	_add_actions(actions)
	side_panel.visible = true


## Inspect panel for anything else (conduits, cells, relics).
func show_info(title: String, body: String, lines: PackedStringArray = PackedStringArray(), actions: Array = []) -> void:
	_clear()
	mode = "inspect"
	side_box.add_child(_label(title, 22, UiTheme.ACCENT))
	if body != "":
		side_box.add_child(_label(body, 16, UiTheme.DIM))
	for line in lines:
		side_box.add_child(_label("• " + line, 17))
	_add_actions(actions)
	side_panel.visible = true


func _add_actions(actions: Array) -> void:
	if actions.is_empty():
		return
	side_box.add_child(HSeparator.new())
	for a: Array in actions:
		var b := Button.new()
		b.text = String(a[2])
		b.disabled = not bool(a[3]) if a.size() > 3 else false
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if a.size() > 4:
			b.icon = UiTheme.icon(String(a[4]))
		var act := String(a[0])
		var arg := String(a[1])
		b.pressed.connect(func() -> void:
			Audio.ui("ui_select", -6.0)
			action_picked.emit(act, arg))
		side_box.add_child(b)


## Build palette: conduits first, then every machine — known ones buildable, the rest teased.
func show_build_menu() -> void:
	_clear()
	mode = "build"
	side_box.add_child(_label("Build", 22, UiTheme.ACCENT))
	side_box.add_child(_label("Parts in your pack are spent where you place them.", 15, UiTheme.DIM))
	var ids: Array = Content.machines.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		return String(Content.machine(a).get("name", a)) < String(Content.machine(b).get("name", b)))
	var known: Array = []
	var locked: Array = []
	for id: String in ids:
		var d: Dictionary = Content.machine(id)
		if bool(d.get("fixed", false)) or id.begins_with("_"):
			continue
		if GameState.can_build(id):
			known.append(id)
		else:
			locked.append(id)
	for id: String in known:
		var d: Dictionary = Content.machine(id)
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var ok: bool = GameState.inventory.has_all(d.get("cost", {}))
		b.text = "%s\n%s" % [String(d.get("name", id)), _cost_text(d.get("cost", {}))]
		b.add_theme_font_size_override("font_size", UiTheme.size(17))
		var ic := machine_icon(id)
		if ic.texture:
			b.icon = ic.texture
			b.expand_icon = false
			b.add_theme_constant_override("icon_max_width", 40)
		b.modulate = Color.WHITE if ok else Color(1, 1, 1, 0.6)
		b.tooltip_text = String(d.get("desc", ""))
		b.pressed.connect(func() -> void:
			Audio.ui("ui_select", -6.0)
			build_picked.emit(id))
		side_box.add_child(b)
	if not locked.is_empty():
		side_box.add_child(HSeparator.new())
		side_box.add_child(_label("Not yet understood", 16, UiTheme.DIM))
		for id: String in locked:
			var l := _label("%s — needs a schematic" % String(Content.machine(id).get("name", id)), 15, Color(UiTheme.DIM, 0.7))
			side_box.add_child(l)
	side_panel.visible = true


static func _cost_text(cost: Dictionary) -> String:
	var parts := PackedStringArray()
	for item: String in cost:
		var have := GameState.inventory.count(item)
		parts.append("%d %s (%d)" % [int(cost[item]), Content.item_name(item).to_lower(), have])
	return ", ".join(parts) if not parts.is_empty() else "free"
