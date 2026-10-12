class_name OpeningFall
extends Control
## The cold open, drawn in pixels on the fade layer: a salvager hanging on a cable in a rock
## shaft with a coin of daylight far above; the cable snaps; the walls stream upward as they
## fall and the daylight shrinks to a point; then black. game.opening() drives the beats with
## `phase` ("hang", "snap", "fall") and frees it at the moss.

const PX := 4.0                               ## one art pixel, in screen pixels
const ROCK := Color("1b1a22")
const ROCK_LIT := Color("3a3445")
const ROCK_RIM := Color("5a4f62")
const SKY := Color("cfd9e6")
const LAMP := Color("f5c875")

var phase := "hang"
var _t := 0.0                                  ## time in the current phase
var _scroll := 0.0                             ## how far the walls have moved, in art pixels
var _speed := 0.0
var _fall_y := 0.0                             ## the figure's drop during the snap
var _spin := 0.0
var _streaks: Array = []                       ## [x, y, length] dust streaks while falling
var _motes: Array = []                         ## [x, y, drift] dust while hanging
var _glow: GradientTexture2D


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if size.x < 1.0:
		size = get_viewport_rect().size
	for i in 40:
		_motes.append([randf(), randf(), randf_range(0.004, 0.015)])
	for i in 26:
		_streaks.append([randf(), randf(), randf_range(6.0, 22.0)])
	_glow = GradientTexture2D.new()
	_glow.fill = GradientTexture2D.FILL_RADIAL
	_glow.fill_from = Vector2(0.5, 0.5)
	_glow.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	g.colors = PackedColorArray([Color(SKY, 0.38), Color(SKY, 0.12), Color(SKY, 0.0)])
	_glow.gradient = g


func set_phase(p: String) -> void:
	phase = p
	_t = 0.0


func _process(delta: float) -> void:
	_t += delta
	match phase:
		"hang":
			_speed = lerpf(_speed, 6.0, delta)          # lowering, slowly
		"snap":
			_speed = lerpf(_speed, 0.0, delta * 8.0)
			_fall_y += delta * 30.0 * (1.0 + _t * 4.0)
		"fall":
			_speed = minf(_speed + delta * 900.0, 1400.0)
			_spin += delta * (2.0 + _t * 3.0)
	_scroll += _speed * delta
	queue_redraw()


func _snap(v: float) -> float:
	return floorf(v / PX) * PX


## Wall edge (in art pixels from the screen edge) at shaft depth `d`: jagged, never smooth.
static func _edge(d: float, seed: int) -> float:
	var a := sin(d * 0.045 + seed) * 7.0 + sin(d * 0.13 + seed * 2.1) * 3.0
	var step := float(int(floor(d / 6.0 + seed)) * 7919 % 5)
	return 52.0 + a + step


func _draw() -> void:
	var w := size.x
	var h := size.y
	var cols := int(w / PX)
	var rows := int(h / PX) + 1
	draw_rect(Rect2(0, 0, w, h), Color("07060a"))
	# Daylight at the top of the shaft: wide while hanging, a shrinking coin as you fall.
	var light := clampf(1.0 - _scroll / 2600.0, 0.0, 1.0) if phase == "fall" else 1.0
	if light > 0.0:
		var cx := w * 0.5
		var rad := lerpf(6.0, 90.0, light) if phase == "fall" else 90.0
		var gr := rad * 5.0
		draw_texture_rect(_glow, Rect2(cx - gr, -gr, gr * 2.0, gr * 2.0), false, Color(1, 1, 1, light))
		draw_rect(Rect2(_snap(cx - rad), 0, _snap(rad * 2.0), PX * 2.0), Color(SKY, 0.8 * light))
	# The shaft walls, drawn in art-pixel rows so they stay crisp.
	var lamp_y := _figure_pos().y
	for row in rows:
		var y := row * PX
		var depth := _scroll + float(row)
		var left := _edge(depth, 3) * (w / 320.0)
		var right := w - _edge(depth, 11) * (w / 320.0)
		left = _snap(left)
		right = _snap(right)
		# Lit by the headlamp near the figure; by the daylight near the top.
		var near := clampf(1.0 - absf(y - lamp_y) / (h * 0.35), 0.0, 1.0)
		var sky := clampf(1.0 - y / (h * 0.5), 0.0, 1.0) * light
		var lit := maxf(near * 0.9, sky * 0.7)
		var col := ROCK.lerp(ROCK_LIT, lit)
		draw_rect(Rect2(0, y, left, PX), col)
		draw_rect(Rect2(right, y, w - right, PX), col)
		draw_rect(Rect2(left - PX, y, PX, PX), ROCK_RIM.lerp(ROCK, 1.0 - lit))
		draw_rect(Rect2(right, y, PX, PX), ROCK_RIM.lerp(ROCK, 1.0 - lit))
		# Texture: cracks and darker stones, fixed to the rock so they scroll with it.
		var di := int(floor(depth))
		for k in 3:
			var hsh := absi((di * 73856093) ^ (k * 19349663)) % 1000
			if hsh < 380:
				var fx := float(hsh % 37) / 37.0
				var fl := float(hsh % 5 + 2) * PX
				draw_rect(Rect2(_snap(fx * (left - PX * 3.0)), y, fl, PX), col.darkened(0.35))
				draw_rect(Rect2(_snap(right + PX * 2.0 + fx * (w - right - PX * 3.0)), y, fl, PX), col.darkened(0.35))
		if absi(di * 2246822519) % 41 == 0:
			# A ledge catching the light.
			draw_rect(Rect2(left - PX * 3.0, y, PX * 3.0, PX), ROCK_RIM.lerp(ROCK, 1.0 - lit * 0.8))
		# Strata glints: crystal and ore in the rock.
		var g := int(depth) * 2654435761 % 97
		if g < 3:
			var gx := _snap(left - PX * float(2 + g * 3))
			draw_rect(Rect2(gx, y, PX, PX), Color("56e0d4") if g == 0 else Color("e8a33d", 0.8))
		elif g > 94:
			draw_rect(Rect2(_snap(right + PX * float(2 + g % 4)), y, PX, PX), Color("56e0d4", 0.8))
	# Dust: drifting motes while hanging, streaks rushing up while falling.
	if phase == "fall":
		for s: Array in _streaks:
			var sy := fposmod(float(s[1]) * h - _scroll * 0.9 * (0.6 + float(s[0]) * 0.8), h)
			var sx := _snap(w * 0.3 + float(s[0]) * w * 0.4)
			draw_rect(Rect2(sx, _snap(sy), PX * 0.5, float(s[2]) * PX * minf(_speed / 400.0, 3.0)), Color(SKY, 0.35))
	else:
		for m: Array in _motes:
			var my := fposmod(float(m[1]) * h - _t * 12.0 * float(m[2]) * 60.0, h)
			var mx := w * 0.3 + float(m[0]) * w * 0.4 + sin(_t + float(m[1]) * 9.0) * 6.0
			draw_rect(Rect2(_snap(mx), _snap(my), PX * 0.5, PX * 0.5), Color(SKY, 0.25))
	_draw_figure()


func _figure_pos() -> Vector2:
	var w := size.x
	var h := size.y
	var sway := sin(_t * 1.3) * 10.0 if phase == "hang" else 0.0
	var y := h * 0.42 + _fall_y
	if phase == "fall":
		y = h * 0.5 + sin(_t * 3.0) * 8.0
	return Vector2(w * 0.5 + sway, y)


func _draw_figure() -> void:
	var p := _figure_pos()
	# The cable: taut while hanging; a loose, whipping end after the snap.
	if phase == "hang":
		draw_line(Vector2(size.x * 0.5, 0), p + Vector2(PX * 3.75, -PX * 9), Color("8e8a96"), 2.0)
	elif phase == "snap":
		var top := Vector2(size.x * 0.5, 0)
		var end := top + Vector2(sin(_t * 30.0) * 30.0, minf(_t * 220.0, size.y * 0.3))
		draw_line(top, end, Color("8e8a96"), 2.0)
		draw_rect(Rect2(end - Vector2(PX, PX), Vector2(PX * 2, PX * 2)), Color("f5c875"))
	# Headlamp beam: a pale wedge downward, swinging as they turn.
	var ang := PI * 0.5 + (_spin if phase == "fall" else sin(_t * 1.3) * 0.15)
	var dir := Vector2(cos(ang), sin(ang))
	var side := Vector2(-dir.y, dir.x)
	var spin := _spin if phase == "fall" else 0.0
	var lamp := p + Vector2(0, -PX * 10.5).rotated(spin)   # on the helmet, wherever it points
	var beam := PackedVector2Array([lamp, lamp + dir * 170.0 + side * 46.0, lamp + dir * 170.0 - side * 46.0])
	draw_colored_polygon(beam, Color(LAMP, 0.07))
	# The salvager, in the player's colours: brass helmet, teal coat, a pack, the lamp a hot point.
	var xf := Transform2D(_spin if phase == "fall" else 0.0, p)
	draw_set_transform_matrix(xf)
	var q := PX * 1.5
	var coat := Color("2f4f58")
	var coat_d := Color("1f3540")
	var skin := Color("c49a72")
	var brass := Color("9c7a3c")
	draw_rect(Rect2(-q * 3, -q * 4, q * 1.5, q * 5), Color("5a4030"))   # pack
	draw_rect(Rect2(-q * 2, -q * 4, q * 4, q * 6), coat)                # coat
	draw_rect(Rect2(-q * 2, q * 1, q * 4, q * 1), coat_d)
	draw_rect(Rect2(q * 2, -q * 3, q, q * 4), coat_d)                    # arm reaching up
	if phase == "hang":
		draw_rect(Rect2(q * 2, -q * 6, q, q * 3), coat_d)              # gripping the cable
	draw_rect(Rect2(-q * 2, q * 2, q * 1.5, q * 3), Color("3a3440"))     # legs
	draw_rect(Rect2(q * 0.5, q * 2, q * 1.5, q * 3), Color("3a3440"))
	draw_rect(Rect2(-q * 1.5, -q * 6, q * 3, q * 2), skin)              # face
	draw_rect(Rect2(-q * 2, -q * 8, q * 4, q * 2), brass)               # helmet
	draw_rect(Rect2(-q * 2, -q * 8, q * 4, q * 0.5), Color("c9a25a"))
	draw_rect(Rect2(-q * 0.5, -q * 7.5, q, q), LAMP)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	draw_circle(lamp, PX * 2.5, Color(LAMP, 0.25))
