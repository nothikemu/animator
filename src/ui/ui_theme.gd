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

static var _cache: Theme
static var _icons: Texture2D
static var _icon_map: Dictionary = {}


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


static func build() -> Theme:
	var t := Theme.new()
	var hc := bool(Settings.access.get("high_contrast", false))
	var text := Color.WHITE if hc else TEXT
	var panel := PANEL_DARK if hc else PANEL
	t.default_font = font()
	t.default_font_size = size(18)
	# Panels
	var pb := panel_box(panel)
	pb.shadow_size = 4
	t.set_stylebox("panel", "PanelContainer", pb)
	t.set_stylebox("panel", "Panel", pb)
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
	var normal := panel_box(Color("1b1a21e8"), BORDER_DIM, 2, 8)
	var hover := panel_box(Color("2a2733f0"), BORDER, 2, 8)
	var pressed := panel_box(Color("100f14f0"), ACCENT, 2, 8)
	var focus := panel_box(Color(0, 0, 0, 0), ACCENT, 2, 8)
	focus.draw_center = false
	var disabled := panel_box(Color("16151af0"), Color("2c2a33"), 2, 8)
	for cls in ["Button", "OptionButton", "CheckBox", "CheckButton"]:
		t.set_stylebox("normal", cls, normal)
		t.set_stylebox("hover", cls, hover)
		t.set_stylebox("pressed", cls, pressed)
		t.set_stylebox("focus", cls, focus)
		t.set_stylebox("disabled", cls, disabled)
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
	t.set_stylebox("tab_selected", "TabContainer", panel_box(panel, ACCENT, 2, 8))
	t.set_stylebox("tab_unselected", "TabContainer", panel_box(Color("1b1a21"), BORDER_DIM, 2, 8))
	t.set_stylebox("tab_hovered", "TabContainer", panel_box(Color("2a2733"), BORDER, 2, 8))
	t.set_stylebox("panel", "TabContainer", panel_box(panel, BORDER, 2, 12))
	t.set_color("font_selected_color", "TabContainer", Color.WHITE)
	t.set_color("font_unselected_color", "TabContainer", DIM)
	t.set_font_size("font_size", "TabContainer", size(18))
	# Line edit
	t.set_stylebox("normal", "LineEdit", panel_box(Color("121116"), BORDER_DIM, 2, 8))
	t.set_stylebox("focus", "LineEdit", panel_box(Color("121116"), ACCENT, 2, 8))
	t.set_color("font_color", "LineEdit", text)
	t.set_color("caret_color", "LineEdit", ACCENT)
	# Scroll
	var grab := StyleBoxFlat.new()
	grab.bg_color = BORDER_DIM
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("scroll", "VScrollBar", StyleBoxEmpty.new())
	# Tooltips
	t.set_stylebox("panel", "TooltipPanel", panel_box(PANEL_DARK, BORDER, 1, 6))
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
