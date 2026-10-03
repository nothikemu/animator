class_name PixelSprite3D
extends MeshInstance3D
## A pixel-art billboard: a quad whose bottom edge sits on the node origin, rendered with
## shaders/pixel_sprite.gdshader. Materials are shared per texture so instances batch;
## frame/flip/tint/flash/fade are per-instance uniforms.

const PIXEL := 1.0 / 16.0
const SHADER := preload("res://shaders/pixel_sprite.gdshader")

static var _materials: Dictionary = {}

var frame_size := Vector2i(16, 16)
var columns := 1
var rows := 1
var anims: Dictionary = {}
var current := ""
var _t := 0.0
var _frame_index := 0
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


func play(anim: String, restart := false) -> void:
	if anim == current and not restart:
		return
	if not anims.has(anim):
		return
	current = anim
	_t = 0.0
	_frame_index = 0
	_apply()


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
	if not playing or current == "" or not anims.has(current):
		return
	var a: Dictionary = anims[current]
	_t += delta * float(a.get("fps", 6))
	var n := int(a.get("frames", 1))
	var idx := int(_t)
	if bool(a.get("loop", true)):
		idx = idx % n
	else:
		idx = mini(idx, n - 1)
	if idx != _frame_index:
		_frame_index = idx
		_apply()


func _apply() -> void:
	if not anims.has(current):
		return
	var a: Dictionary = anims[current]
	set_frame(int(a.get("row", 0)) * columns + _frame_index)


func frame_in_anim() -> int:
	return _frame_index
