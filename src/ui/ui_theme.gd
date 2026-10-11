class_name UiTheme
extends RefCounted
## Builds the game's Theme in code so accessibility settings (font scale, readable font,
## high contrast) can rebuild it live. Visual language: dark basalt panels, brass borders,
## cream text, amber focus — a salvager's brass instrument and notebook.

const PIXEL_FONT := "res://assets/fonts/PixelifySans.ttf"
const READABLE_FONT := "res://assets/fonts/AtkinsonHyperlegible-Regular.ttf"
const READABLE_BOLD := "res://assets/fonts/AtkinsonHyperlegible-Bold.ttf"

const BG := Color("17161cf0")
const PANEL := Color("211f28f2")
const PANEL_DARK := Color("121116f5")
const BORDER := Color("9c7a3c")
const BORDER_DIM := Color("4e4130")
const TEXT := Color("efe3c2")
const DIM := Color("a89e86")
const ACCENT := Color("e8a33d")
const LIVING := Color("56e0d4")
const DANGER := Color("e2552c")

const UI_DIR := "res://assets/textures/ui/"

static var _cache: Theme
static var _icons: Texture2D
static var _icon_map: Dictionary = {}
static var _ui_meta: Dictionary = {}


static func get_theme() -> Theme:
	if _cache == null:
		_cache = build()
	return _cache


static func invalidate() -> void:
	_cache = null


static var _fonts: Dictionary = {}


static func font(bold := false) -> Font:
	if Settings.access.get("readable_font", false):
		return load(READABLE_BOLD if bold else READABLE_FONT)
	var key := "bold" if bold else "regular"
	if _fonts.has(key):
		return _fonts[key]
	# The pixel font's "fi"/"fl" ligatures render as a single odd glyph; spell letters out.
	var ts := TextServerManager.get_primary_interface()
	var v := FontVariation.new()
	v.base_font = load(PIXEL_FONT)
	v.opentype_features = {ts.name_to_tag("liga"): 0, ts.name_to_tag("clig"): 0, ts.name_to_tag("dlig"): 0}
	if bold:
		v.variation_opentype = {"wght": 700}
	_fonts[key] = v
	return v


static func size(base: int) -> int:
	return int(round(base * float(Settings.access.get("font_scale", 1.0))))


static func panel_box(fill := PANEL, border := BORDER, width := 2, pad := 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(0)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.7
	s.content_margin_bottom = pad * 0.7
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 0
	s.shadow_offset = Vector2(3, 3)
	s.anti_aliasing = false
	return s


## A nine-slice frame from assets/textures/ui (tools/art/ui.py), with `pad` pixels of room
## inside its border. High contrast swaps every frame for a flat, stark box.
static func frame(name: String, pad := 0.0) -> StyleBox:
	if bool(Settings.access.get("high_contrast", false)):
		var flat := panel_box(PANEL_DARK if name in ["panel", "well", "slot"] else Color("1b1a21"),
			ACCENT if name in ["slot_selected", "button_hover", "button_pressed", "focus"] else Color.WHITE, 2, 8 + int(pad))
		flat.draw_center = name != "focus"
		return flat
	if _ui_meta.is_empty():
		var meta: Variant = Content.read_json(UI_DIR + "ui.json")
		_ui_meta = meta if meta is Dictionary else {}
	var m: Dictionary = _ui_meta.get(name, {})
	var s := StyleBoxTexture.new()
	s.texture = load(UI_DIR + name + ".png")
	var mg := float(m.get("margin", 8))
	s.texture_margin_left = mg
	s.texture_margin_right = mg
	s.texture_margin_top = mg
	s.texture_margin_bottom = mg
	s.content_margin_left = mg + pad
	s.content_margin_right = mg + pad
	s.content_margin_top = mg + pad * 0.6
	s.content_margin_bottom = mg + pad * 0.6
	return s


## A recessed well for sections inside a window.
static func well(pad := 6.0) -> StyleBox:
	return frame("well", pad)


## A small key cap ("Esc", "E") for hints.
static func keycap(text: String, label := "") -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var cap := PanelContainer.new()
	var st := frame("button", -2.0)
	cap.add_theme_stylebox_override("panel", st)
	var k := Label.new()
	k.text = text
	k.add_theme_font_size_override("font_size", size(14))
	k.add_theme_color_override("font_color", TEXT)
	cap.add_child(k)
	h.add_child(cap)
	if label != "":
		var l := Label.new()
		l.text = label
		l.add_theme_font_size_override("font_size", size(15))
		l.add_theme_color_override("font_color", DIM)
		h.add_child(l)
	return h


static func build() -> Theme:
	var t := Theme.new()
	var hc := bool(Settings.access.get("high_contrast", false))
	var text := Color.WHITE if hc else TEXT
	var panel := PANEL_DARK if hc else PANEL
	t.default_font = font()
	t.default_font_size = size(18)
	# Panels: the riveted brass window.
	t.set_stylebox("panel", "PanelContainer", frame("panel", 6))
	t.set_stylebox("panel", "Panel", frame("panel", 6))
	# Labels
	t.set_color("font_color", "Label", text)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.6))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 1)
	t.set_color("default_color", "RichTextLabel", text)
	t.set_font("normal_font", "RichTextLabel", font())
	t.set_font("bold_font", "RichTextLabel", font(true))
	t.set_font_size("normal_font_size", "RichTextLabel", size(20))
	t.set_font_size("bold_font_size", "RichTextLabel", size(20))
	# Buttons: quiet until hovered/focused; focus is unmistakable for pad/keyboard players.
	var normal := frame("button", 4)
	var hover := frame("button_hover", 4)
	var pressed := frame("button_pressed", 4)
	var focus := frame("focus", 4)
	var disabled := frame("button_disabled", 4)
	for cls in ["Button", "OptionButton", "CheckBox", "CheckButton"]:
		t.set_stylebox("normal", cls, normal)
		t.set_stylebox("hover", cls, hover)
		t.set_stylebox("pressed", cls, pressed)
		t.set_stylebox("focus", cls, focus)
		t.set_stylebox("disabled", cls, disabled)
		t.set_stylebox("hover_pressed", cls, pressed)
		t.set_color("font_color", cls, text)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_focus_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, ACCENT)
		t.set_color("font_disabled_color", cls, Color("6a6458"))
		t.set_font_size("font_size", cls, size(20))
	# Toggles: no box of their own; the switch/tick is the control. Focus still shows.
	for cls in ["CheckBox", "CheckButton"]:
		var flat := StyleBoxEmpty.new()
		flat.content_margin_left = 6
		flat.content_margin_right = 6
		flat.content_margin_top = 4
		flat.content_margin_bottom = 4
		for st in ["normal", "pressed", "hover", "hover_pressed", "disabled"]:
			t.set_stylebox(st, cls, flat)
		t.set_stylebox("focus", cls, focus)
	# Sliders
	var track := StyleBoxFlat.new()
	track.bg_color = Color("2c2a33")
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var fill := StyleBoxFlat.new()
	fill.bg_color = BORDER
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", _square_icon(ACCENT, 12))
	t.set_icon("grabber_highlight", "HSlider", _square_icon(Color.WHITE, 12))
	# Tabs
	t.set_stylebox("tab_selected", "TabContainer", frame("tab_selected", 6))
	t.set_stylebox("tab_unselected", "TabContainer", frame("tab", 6))
	t.set_stylebox("tab_hovered", "TabContainer", frame("button_hover", 4))
	t.set_stylebox("tab_focus", "TabContainer", frame("focus", 4))
	t.set_stylebox("panel", "TabContainer", frame("well", 10))
	t.set_color("font_hovered_color", "TabContainer", Color.WHITE)
	t.set_color("font_selected_color", "TabContainer", Color.WHITE)
	t.set_color("font_unselected_color", "TabContainer", DIM)
	t.set_font_size("font_size", "TabContainer", size(18))
	# Line edit
	t.set_stylebox("normal", "LineEdit", frame("well", 4))
	t.set_stylebox("focus", "LineEdit", frame("slot_selected", 2))
	# Option popups and dividers
	t.set_stylebox("panel", "PopupMenu", frame("panel", 0))
	t.set_stylebox("hover", "PopupMenu", frame("button_hover", 0))
	t.set_color("font_color", "PopupMenu", text)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	var line := StyleBoxLine.new()
	line.color = BORDER_DIM
	line.thickness = 2
	t.set_stylebox("separator", "HSeparator", line)
	t.set_constant("separation", "HSeparator", 12)
	t.set_color("font_color", "LineEdit", text)
	t.set_color("caret_color", "LineEdit", ACCENT)
	# Scroll
	var grab := StyleBoxFlat.new()
	grab.bg_color = BORDER_DIM
	grab.border_color = BORDER
	grab.border_width_left = 1
	grab.content_margin_left = 3
	grab.content_margin_right = 3
	var grab_hi := grab.duplicate()
	grab_hi.bg_color = BORDER
	var track_v := StyleBoxFlat.new()
	track_v.bg_color = Color("121116c0")
	track_v.content_margin_left = 3
	track_v.content_margin_right = 3
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab_hi)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab_hi)
	t.set_stylebox("scroll", "VScrollBar", track_v)
	# Tooltips
	t.set_stylebox("panel", "TooltipPanel", frame("toast", 2))
	t.set_color("font_color", "TooltipLabel", text)
	return t


static func _square_icon(c: Color, s: int) -> ImageTexture:
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(c)
	for i in s:
		img.set_pixel(i, 0, c.darkened(0.4))
		img.set_pixel(i, s - 1, c.darkened(0.4))
	return ImageTexture.create_from_image(img)


## AtlasTexture for an icon name from assets/textures/icons.json.
static func icon(name: String) -> Texture2D:
	if _icons == null:
		_icons = load("res://assets/textures/icons.png")
		var meta: Variant = Content.read_json("res://assets/textures/icons.json")
		if meta is Dictionary:
			_icon_map = meta.icons
	var key := name
	if not _icon_map.has(key):
		var item: Dictionary = Content.item(name)
		key = String(item.get("icon", name))
	if not _icon_map.has(key):
		key = "st_warn"
	var cell: Array = _icon_map.get(key, [0, 0])
	var a := AtlasTexture.new()
	a.atlas = _icons
	a.region = Rect2(float(cell[0]) * 16.0, float(cell[1]) * 16.0, 16.0, 16.0)
	return a
