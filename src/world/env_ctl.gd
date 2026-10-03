class_name EnvCtl
extends WorldEnvironment
## Owns the Environment: biome look, time of day, pollution, and graphics quality.
## Pollution is shown, not iconised: fog turns sour green, colour drains, light hardens.

var biome := "grove"
var pollution := 0.0                 ## 0..1 local foul-air amount near the player
var fill: DirectionalLight3D         ## the cavern ceiling's faint glow: keeps the diorama legible
var _target := {}
var _current := {}


func _ready() -> void:
	environment = Environment.new()
	var e := environment
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("0b0a0f")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_exposure = 1.0
	e.glow_enabled = true
	e.glow_normalized = false
	e.glow_intensity = 0.55
	e.glow_strength = 1.0
	e.glow_bloom = 0.04
	e.glow_hdr_threshold = 0.85
	e.glow_hdr_scale = 2.0
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	for i in 7:
		e.set_glow_level(i, [0.0, 0.6, 0.9, 0.8, 0.5, 0.25, 0.0][i])
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	e.fog_density = 0.018
	e.fog_sky_affect = 0.0
	e.fog_height = 0.6
	e.fog_height_density = 0.12
	e.ssao_enabled = true
	e.ssao_radius = 1.2
	e.ssao_intensity = 1.6
	e.ssao_power = 1.4
	e.adjustment_enabled = true
	e.adjustment_brightness = 1.0
	e.adjustment_contrast = 1.06
	e.adjustment_saturation = 1.05
	fill = DirectionalLight3D.new()
	fill.name = "CavernFill"
	fill.rotation_degrees = Vector3(-62, 28, 0)
	fill.light_color = Color("8c9cc8")
	fill.light_energy = 0.32
	fill.shadow_enabled = true
	fill.shadow_blur = 2.0
	fill.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	fill.directional_shadow_max_distance = 60.0
	add_child(fill)
	set_biome("grove")
	apply_quality()
	Events.settings_changed.connect(func(s: StringName) -> void:
		if s == &"graphics":
			apply_quality())


func set_biome(b: String) -> void:
	biome = b
	var def: Dictionary = Content.biomes.get(b, Content.biomes.get("grove", {}))
	_target = {
		"ambient": Color(String(def.get("ambient_light", "#3a4a66"))),
		"ambient_energy": float(def.get("ambient_energy", 0.4)),
		"fog": Color(String(def.get("fog_color", "#16222a"))),
		"fog_density": float(def.get("fog_density", 0.018)),
		"fill": float(def.get("fill", 0.3)),
	}
	if _current.is_empty():
		_current = _target.duplicate()


func apply_quality() -> void:
	var g: Dictionary = Settings.graphics
	var e := environment
	e.glow_enabled = bool(g.get("glow", true))
	if fill:
		fill.shadow_enabled = bool(g.get("shadows", true))
	e.ssao_enabled = bool(g.get("ssao", true)) and RenderingServer.get_current_rendering_method() == "forward_plus"
	e.volumetric_fog_enabled = bool(g.get("volumetric", false)) and RenderingServer.get_current_rendering_method() == "forward_plus"
	if e.volumetric_fog_enabled:
		e.volumetric_fog_density = 0.012
		e.volumetric_fog_albedo = Color(0.7, 0.75, 0.8)
		e.volumetric_fog_emission = Color(0, 0, 0)
		e.volumetric_fog_anisotropy = 0.4
		e.volumetric_fog_length = 40.0


func _process(delta: float) -> void:
	var k := clampf(delta * 1.2, 0.0, 1.0)
	for key in _target:
		var a: Variant = _current.get(key, _target[key])
		var b: Variant = _target[key]
		if a is Color:
			_current[key] = (a as Color).lerp(b, k)
		else:
			_current[key] = lerpf(float(a), float(b), k)
	var e := environment
	var glow := Clock.glow_level()
	var amb: Color = _current.ambient
	var sour := Color("b5b84a")
	# Time of day: the grove's glow lifts the ambient light a little at Bloom.
	var energy: float = float(_current.ambient_energy) * (0.75 + 0.35 * glow)
	e.ambient_light_color = amb.lerp(sour.darkened(0.3), pollution * 0.6)
	e.ambient_light_energy = energy
	e.fog_light_color = (_current.fog as Color).lerp(sour.darkened(0.45), pollution * 0.85)
	if fill:
		fill.light_energy = float(_current.get("fill", 0.3)) * (0.7 + 0.4 * glow)
		fill.light_color = Color("8c9cc8").lerp(Color("c8c47a"), pollution * 0.5)
	e.fog_density = float(_current.fog_density) * (1.0 + pollution * 2.4)
	e.adjustment_saturation = lerpf(1.06, 0.62, pollution)
	e.adjustment_contrast = lerpf(1.06, 1.18, pollution)
	RenderingServer.global_shader_parameter_set("pollution", pollution)
