class_name ScreenFade
extends CanvasLayer
## Full-screen fades (sleep, area transitions, blackouts) and accessibility-scaled flashes.

var rect: ColorRect
var title: Label


func _ready() -> void:
	layer = 50
	rect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.color = Color(0.03, 0.025, 0.04, 0.0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	title = Label.new()
	title.set_anchors_preset(Control.PRESET_CENTER)
	title.position = Vector2(-400, -20)
	title.size = Vector2(800, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.theme = UiTheme.get_theme()
	title.add_theme_font_size_override("font_size", UiTheme.size(26))
	title.modulate.a = 0.0
	add_child(title)
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
