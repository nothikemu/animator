class_name PixelSprite3D
extends MeshInstance3D
## A pixel-art billboard: a quad whose bottom edge sits on the node origin, rendered with
## shaders/pixel_sprite.gdshader. Materials are shared per texture so instances batch;
## frame/flip/tint/flash/fade are per-instance uniforms.
##
## Character sheets carry named animations ("walk_side", "till_down"...). Each has a first
## frame, a length, a rate, a loop flag and events on particular frames ("step", "hit"),
## which are emitted as the frame comes up so sounds and particles land on the right pixel.
## A one-shot animation emits `finished` on its last frame and holds there.

signal event(name: String)
signal finished(anim: String)

const PIXEL := 1.0 / 16.0
const SHADER := preload("res://shaders/pixel_sprite.gdshader")

static var _materials: Dictionary = {}

var frame_size := Vector2i(16, 16)
var columns := 1
var rows := 1
var anims: Dictionary = {}
var current := ""
var speed := 1.0                         ## playback rate multiplier
var _t := 0.0
var _frame_index := 0
var _done := false
var playing := true


static func material_for(tex: Texture2D, emit: Texture2D, grid: Vector2i, opts: Dictionary = {}) -> ShaderMaterial:
	var key := "%s|%s|%d|%d|%s" % [tex.resource_path, emit.resource_path if emit else "", grid.x, grid.y, str(opts)]
	if _materials.has(key):
		return _materials[key]
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("sheet", tex)
	if emit != null:
		m.set_shader_parameter("emit_sheet", emit)
		m.set_shader_parameter("has_emit", true)
	m.set_shader_parameter("frames", Vector2(grid.x, grid.y))
	for k in opts:
		m.set_shader_parameter(k, opts[k])
	_materials[key] = m
	return m


## Loads a texture plus its optional "_emit" companion.
static func load_tex(path: String) -> Array:
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	var emit_path := path.get_basename() + "_emit.png"
	var emit: Texture2D = load(emit_path) if ResourceLoader.exists(emit_path) else null
	return [tex, emit]


func setup(tex: Texture2D, emit: Texture2D, fsize: Vector2i, grid := Vector2i(1, 1), opts: Dictionary = {}, scale_px := 1.0) -> void:
	frame_size = fsize
	columns = grid.x
	rows = grid.y
	var q := QuadMesh.new()
	q.size = Vector2(fsize.x, fsize.y) * PIXEL * scale_px
	q.center_offset = Vector3(0, q.size.y * 0.5, 0)
	mesh = q
	material_override = material_for(tex, emit, grid, opts)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	set_instance_shader_parameter("frame", 0.0)


## Character sheets: frames described by assets/textures/chars/<id>.json.
func setup_character(id: String) -> void:
	var meta: Variant = Content.read_json("res://assets/textures/chars/%s.json" % id)
	if not meta is Dictionary:
		Log.error("sprite", "missing character sheet %s" % id)
		return
	var t := load_tex("res://assets/textures/chars/%s.png" % id)
	anims = meta.anims
	setup(t[0], t[1] if meta.get("emit", false) else null, Vector2i(int(meta.w), int(meta.h)),
		Vector2i(int(meta.cols), int(meta.rows)), {"rim_strength": 0.5})


## Plays `anim`, falling back to the same animation in another view, then to idle.
## Returns the name actually played.
func play(anim: String, restart := false) -> String:
	var name := resolve(anim)
	if name == "":
		return ""
	if name == current and not restart:
		return name
	current = name
	_t = 0.0
	_frame_index = 0
	_done = false
	_apply()
	_emit_events(0)
	return name


func resolve(anim: String) -> String:
	if anims.has(anim):
		return anim
	var base := anim.get_slice("_", 0)
	var view := anim.get_slice("_", 1) if anim.contains("_") else "down"
	for v in [view, "down", "side", "up"]:
		if anims.has(base + "_" + v):
			return base + "_" + v
	if anims.has("idle_" + view):
		return "idle_" + view
	return ""


func has_anim(anim: String) -> bool:
	return anims.has(anim)


## Seconds from the start of `anim` until its first `ev` event (or its end).
func time_to_event(anim: String, ev: String) -> float:
	var name := resolve(anim)
	if name == "":
		return 0.0
	var a: Dictionary = anims[name]
	var fps := maxf(1.0, float(a.get("fps", 6))) * speed
	var evs: Dictionary = a.get("events", {})
	if evs.has(ev) and not (evs[ev] as Array).is_empty():
		return float(evs[ev][0]) / fps
	return float(a.get("frames", 1)) / fps


func length_of(anim: String) -> float:
	var name := resolve(anim)
	if name == "":
		return 0.0
	var a: Dictionary = anims[name]
	return float(a.get("frames", 1)) / (maxf(1.0, float(a.get("fps", 6))) * speed)


func is_done() -> bool:
	return _done


func set_flip(f: bool) -> void:
	set_instance_shader_parameter("flip", f)


func set_tint(c: Color) -> void:
	set_instance_shader_parameter("tint", c)


func set_flash(c: Color, amount: float) -> void:
	set_instance_shader_parameter("flash_color", Color(c.r, c.g, c.b, amount))


func set_fade(f: float) -> void:
	set_instance_shader_parameter("fade", f)


func set_frame(i: int) -> void:
	set_instance_shader_parameter("frame", float(i))


func _process(delta: float) -> void:
	if not playing or current == "" or not anims.has(current) or _done:
		return
	var a: Dictionary = anims[current]
	_t += delta * float(a.get("fps", 6)) * speed
	var n := int(a.get("frames", 1))
	var idx := int(_t)
	var looping := bool(a.get("loop", true))
	if looping:
		idx = idx % n
	elif idx >= n:
		idx = n - 1
		if not _done:
			_done = true
			finished.emit(current)
	if idx != _frame_index:
		_frame_index = idx
		_apply()
		_emit_events(idx)


func _emit_events(idx: int) -> void:
	var evs: Dictionary = anims.get(current, {}).get("events", {})
	for ev: String in evs:
		if (evs[ev] as Array).has(idx) or (evs[ev] as Array).has(float(idx)):
			event.emit(ev)


func _apply() -> void:
	if not anims.has(current):
		return
	var a: Dictionary = anims[current]
	var start := int(a.get("start", int(a.get("row", 0)) * columns))
	set_frame(start + _frame_index)


func frame_in_anim() -> int:
	return _frame_index
