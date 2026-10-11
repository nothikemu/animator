class_name BrassRule
extends Control
## A divider in the frames' language: a dark groove, a brass line, and a small lozenge in the
## middle. Drawn on whole pixels so it stays crisp at any width.


func _init() -> void:
	custom_minimum_size = Vector2(0, 14)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var y := floorf(size.y * 0.5)
	var w := size.x
	draw_rect(Rect2(0, y - 1, w, 1), Color(UiTheme.PANEL_DARK, 0.9))
	draw_rect(Rect2(0, y, w, 2), Color(UiTheme.BORDER_DIM, 1.0))
	var cx := floorf(w * 0.5)
	var pts := PackedVector2Array([Vector2(cx, y - 6), Vector2(cx + 7, y + 1), Vector2(cx, y + 8), Vector2(cx - 7, y + 1)])
	draw_colored_polygon(pts, UiTheme.BORDER)
	var inner := PackedVector2Array([Vector2(cx, y - 3), Vector2(cx + 4, y + 1), Vector2(cx, y + 5), Vector2(cx - 4, y + 1)])
	draw_colored_polygon(inner, UiTheme.BORDER_DIM)
	draw_rect(Rect2(cx - 1, y - 4, 2, 2), Color("c9a25a"))
