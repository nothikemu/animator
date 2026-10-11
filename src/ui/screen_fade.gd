class_name ScreenFade
extends CanvasLayer
## Full-screen fades (sleep, area transitions, blackouts) and accessibility-scaled flashes.

var rect: ColorRect
var title: Label
var hint: Label
var glow: TextureRect
var card_rule: BrassRule
var _glow_t := 0.0
var _in_card := false
var _skip := false


func _ready() -> void:
	layer = 50
	rect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.color = Color(0.03, 0.025, 0.04, 0.0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	title = Label.new()
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.offset_left = 120
	title.offset_right = -120
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.theme = UiTheme.get_theme()
	title.add_theme_font_size_override("font_size", UiTheme.size(26))
	title.modulate.a = 0.0
	# Behind story cards: a slow, wide breath of light, eight seconds in and out, like the
	# Bellows; and a brass rule under each line.
	glow = TextureRect.new()
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	g.width = 256
	g.height = 256
	var grad := Gradient.new()
	grad.set_color(0, Color(0.34, 0.88, 0.83, 0.22))
	grad.set_color(1, Color(0.34, 0.88, 0.83, 0.0))
	g.gradient = grad
	glow.texture = g
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.offset_left = -200
	glow.offset_right = 200
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.modulate.a = 0.0
	add_child(glow)
	add_child(title)
	card_rule = BrassRule.new()
	card_rule.set_anchors_preset(Control.PRESET_CENTER)
	card_rule.custom_minimum_size = Vector2(320, 14)
	card_rule.size = Vector2(320, 14)
	card_rule.position = Vector2(-160, 84)
	card_rule.modulate.a = 0.0
	add_child(card_rule)
	hint = Label.new()
	hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.position = Vector2(-220, -56)
	hint.theme = UiTheme.get_theme()
	hint.add_theme_font_size_override("font_size", UiTheme.size(15))
	hint.add_theme_color_override("font_color", Color(UiTheme.DIM, 0.55))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.visible = false
	add_child(hint)
	Events.flash.connect(flash)


func fade_out(seconds := 0.6, text := "") -> void:
	title.text = text
	var tw := create_tween().set_parallel(true)
	tw.tween_property(rect, "color:a", 1.0, seconds)
	if text != "":
		tw.tween_property(title, "modulate:a", 1.0, seconds)
	await tw.finished


func fade_in(seconds := 0.8) -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(rect, "color:a", 0.0, seconds)
	tw.tween_property(title, "modulate:a", 0.0, seconds * 0.6)
	await tw.finished


## Instantly black (scene starts that open on darkness).
func black() -> void:
	rect.color.a = 1.0
	title.modulate.a = 0.0


## Shows lines of text one after another on black. Assumes the screen is already black.
## Interact or accept moves on to the next line once it has faded in.
func card(lines: Array, hold := 3.2, color := UiTheme.TEXT) -> void:
	title.add_theme_color_override("font_color", color)
	_in_card = true
	hint.text = "[%s] continue" % Settings.binding_label("interact")
	hint.visible = true
	create_tween().tween_property(glow, "modulate:a", 1.0, 1.2)
	for line in lines:
		title.text = String(line)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(title, "modulate:a", 1.0, 0.9)
		tw.tween_property(card_rule, "modulate:a", 0.8, 1.1)
		await tw.finished
		_skip = false
		var t := 0.0
		while t < hold and not _skip:
			await get_tree().process_frame
			t += get_process_delta_time()
		var tw2 := create_tween().set_parallel(true)
		tw2.tween_property(title, "modulate:a", 0.0, 0.5 if _skip else 0.8)
		tw2.tween_property(card_rule, "modulate:a", 0.0, 0.5 if _skip else 0.8)
		await tw2.finished
	_in_card = false
	hint.visible = false
	create_tween().tween_property(glow, "modulate:a", 0.0, 0.8)
	title.remove_theme_color_override("font_color")


func _process(delta: float) -> void:
	if glow.modulate.a > 0.0:
		_glow_t += delta
		var b := 0.5 + 0.5 * sin(_glow_t * TAU / 8.0)
		glow.scale = Vector2.ONE * lerpf(0.92, 1.08, b)
		glow.pivot_offset = glow.size * 0.5
		glow.self_modulate.a = lerpf(0.55, 1.0, b)


func _input(event: InputEvent) -> void:
	if _in_card and (event.is_action_pressed("interact") or event.is_action_pressed("ui_accept")):
		_skip = true
		get_viewport().set_input_as_handled()


func flash(color: Color, strength: float) -> void:
	var s := strength * float(Settings.access.get("flash", 0.7))
	if s <= 0.01:
		return
	var f := ColorRect.new()
	f.set_anchors_preset(Control.PRESET_FULL_RECT)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.color = Color(color.r, color.g, color.b, s)
	add_child(f)
	var tw := create_tween()
	tw.tween_property(f, "color:a", 0.0, 0.5)
	tw.tween_callback(f.queue_free)
