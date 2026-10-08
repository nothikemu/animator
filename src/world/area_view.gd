class_name AreaView
extends Node3D
## Visual representation of one AreaMap: terrain, structures, billboards and lights.
## Rebuildable from data at any time (area streaming = free this node, build another).

const TERRAIN_SHADER := preload("res://shaders/terrain.gdshader")
const WATER_SHADER := preload("res://shaders/water.gdshader")

static var _terrain_mat: ShaderMaterial
static var _water_mat: ShaderMaterial

var area: AreaMap
var _breath_rising := false
var props: PropBuilder
var fade_targets: Dictionary = {}        ## group name -> target fade
var _flicker_t := 0.0
var _quiet := 0.0                        ## 0..1 Quietlight blend (lamps fade out slowly)


static func terrain_material() -> ShaderMaterial:
	if _terrain_mat == null:
		_terrain_mat = ShaderMaterial.new()
		_terrain_mat.shader = TERRAIN_SHADER
		_terrain_mat.set_shader_parameter("atlas", load(Atlas.TEX_PATH))
		_terrain_mat.set_shader_parameter("atlas_emit", load(Atlas.EMIT_PATH))
	return _terrain_mat


static func water_material() -> ShaderMaterial:
	if _water_mat == null:
		_water_mat = ShaderMaterial.new()
		_water_mat.shader = WATER_SHADER
	return _water_mat


func build(a: AreaMap) -> void:
	area = a
	name = "Area_" + a.id
	var terrain := TerrainBuilder.build(a, terrain_material(), water_material())
	add_child(terrain)
	props = PropBuilder.new(a, self)
	props.build_all(terrain_material())
	for g in props.fade_groups:
		fade_targets[g] = 1.0


## Fades interior-house roofs when `pos` (player, world XZ) is inside them.
func update_fades(pos: Vector3, delta: float) -> void:
	for gname in props.fade_groups:
		var group: Node3D = props.fade_groups[gname]
		var r: Rect2 = group.get_meta("rect")
		var inside := r.grow(-0.1).has_point(Vector2(pos.x, pos.z))
		var target := 0.08 if inside else 1.0
		var cur := float(group.get_meta("fade", 1.0))
		cur = move_toward(cur, target, delta * 2.5)
		group.set_meta("fade", cur)
		for child in group.get_children():
			if child is GeometryInstance3D:
				child.set_instance_shader_parameter("fade", cur)


## Light life: glowroots breathe with the grove, lamps flicker a little.
func update_lights(delta: float, glow: float, dark: float, lamp_quality: float) -> void:
	_flicker_t += delta
	# Quietlight: every lamp out; the grove blooms as bright as the air allows.
	var quiet := GameState.has_flag("quietlight_active")
	var bloom := 1.0
	if quiet:
		bloom = 3.2 if String(GameState.flag("ql_bloom")) == "bright" else 1.2
	_quiet = move_toward(_quiet, 1.0 if quiet else 0.0, delta * 0.35)
	RenderingServer.global_shader_parameter_set("lamp_level", 1.0 - 0.96 * _quiet)
	if _quiet > 0.0:
		RenderingServer.global_shader_parameter_set("glow_level", glow * lerpf(1.0, bloom, _quiet))
		if _quiet > 0.4 and not has_node("Lampmoths"):
			Fx.lampmoths(self, area.w, area.d, bloom > 2.0)
	elif has_node("Lampmoths"):
		get_node("Lampmoths").queue_free()
	if not props.breathers.is_empty():
		# Still, the Heart keeps a shallow half-minute breath; restarted, a deep one every eight seconds.
		var running := GameState.has_flag("heart_running")
		var b := 0.5 + 0.5 * sin(_flicker_t * TAU / (8.0 if running else 30.0))
		var lift := lerpf(0.7, 1.0, b) if running else lerpf(0.86, 0.92, b)
		for lung in props.breathers:
			lung.scale.y = lift
		# Running, each in-breath is heard: once per cycle, as the lids start to rise.
		var rising := cos(_flicker_t * TAU / 8.0) > 0.0
		if running and rising and not _breath_rising:
			Audio.play_at("heart_breath", props.breathers[0].global_position + Vector3(4.0, 3.0, 4.0), -4.0, 0.0)
		_breath_rising = rising
	for l in props.lights:
		var base := float(l.get_meta("base_energy", 1.0))
		var kind := String(l.get_meta("kind", ""))
		var phase := l.position.x * 0.37 + l.position.z * 0.21
		match kind:
			"glow":
				l.light_energy = base * (0.55 + 0.45 * glow) * (1.0 + 0.06 * sin(_flicker_t * 0.9 + phase)) * lerpf(1.0, bloom, _quiet)
			"amber":
				var f := 1.0 + 0.05 * sin(_flicker_t * 7.3 + phase) + 0.03 * sin(_flicker_t * 13.1 + phase * 2.0)
				l.light_energy = base * (0.75 + 0.35 * dark) * f * (1.0 - _quiet)
			"ember":
				l.light_energy = base * (1.0 + 0.15 * sin(_flicker_t * 3.1 + phase))
			"bellows":
				# Still, the Heart barely glows; restarted, it breathes in and out over eight seconds.
				var running := GameState.has_flag("heart_running")
				var breath := 0.5 + 0.5 * sin(_flicker_t * TAU / 8.0)
				l.light_energy = base * (lerpf(0.9, 2.4, breath) if running else 0.7 + 0.2 * (0.5 + 0.5 * sin(_flicker_t * TAU / 30.0)))
			"pump":
				l.light_energy = base * (0.7 + 0.3 * absf(sin(_flicker_t * 1.3 + phase)))
			"fire":
				l.light_energy = base * (1.0 + 0.12 * sin(_flicker_t * 9.1 + phase) + 0.08 * sin(_flicker_t * 15.7))
			"console":
				l.light_energy = base * (0.8 + 0.2 * sin(_flicker_t * 2.0))
			_:
				l.light_energy = base
		l.shadow_enabled = l.shadow_enabled and lamp_quality > 0.0
