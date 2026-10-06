class_name Fx
extends RefCounted
## Particle effects: one-shot bursts for verbs and ambient motes that keep the world alive.
## Square pixel particles (unshaded, emissive where they should glow); counts scale with the
## graphics "particles" setting.

static var _mats: Dictionary = {}


static func _mat(color: Color, glow: float) -> StandardMaterial3D:
	var key := "%s|%.2f" % [color.to_html(), glow]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR if glow <= 0.0 else BaseMaterial3D.TRANSPARENCY_ALPHA
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mats[key] = m
	return m


static func _quality() -> float:
	return clampf(float(Settings.graphics.get("particles", 1.0)), 0.0, 1.0)


const KINDS := {
	"dirt": {"color": Color("6b5443"), "n": 14, "speed": 2.2, "gravity": -9.0, "size": 0.07, "life": 0.6, "glow": 0.0},
	"water": {"color": Color("7fc3d9"), "n": 16, "speed": 1.6, "gravity": -7.0, "size": 0.05, "life": 0.55, "glow": 0.0},
	"harvest": {"color": Color("8fa64c"), "n": 12, "speed": 2.0, "gravity": -5.0, "size": 0.06, "life": 0.7, "glow": 0.0},
	"glint": {"color": Color("56e0d4"), "n": 10, "speed": 1.2, "gravity": 0.5, "size": 0.05, "life": 1.0, "glow": 2.0},
	"rock": {"color": Color("6f6c78"), "n": 18, "speed": 2.8, "gravity": -9.0, "size": 0.08, "life": 0.6, "glow": 0.0},
	"spark": {"color": Color("f5c875"), "n": 14, "speed": 3.2, "gravity": -6.0, "size": 0.04, "life": 0.4, "glow": 3.0},
	"dust": {"color": Color("a89e86"), "n": 30, "speed": 1.4, "gravity": -1.0, "size": 0.09, "life": 1.4, "glow": 0.0},
	"sour": {"color": Color("b5b84a"), "n": 10, "speed": 0.5, "gravity": 0.3, "size": 0.12, "life": 2.0, "glow": 0.0},
	"seed": {"color": Color("c9a25a"), "n": 6, "speed": 0.8, "gravity": -6.0, "size": 0.04, "life": 0.4, "glow": 0.0},
}


static func burst(parent: Node3D, pos: Vector3, kind: String) -> void:
	var k: Dictionary = KINDS.get(kind, KINDS.dirt)
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = maxi(2, int(int(k.n) * maxf(_quality(), 0.3)))
	p.lifetime = float(k.life)
	p.direction = Vector3(0, 1, 0)
	p.spread = 55.0
	p.initial_velocity_min = float(k.speed) * 0.5
	p.initial_velocity_max = float(k.speed)
	p.gravity = Vector3(0, float(k.gravity), 0)
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.2
	var q := QuadMesh.new()
	q.size = Vector2.ONE * float(k.size)
	p.mesh = q
	p.material_override = _mat(k.color, float(k.glow))
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = ramp
	p.position = pos
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


## A little puff of whatever the ground is made of, kicked up by a footfall.
static func puff(parent: Node3D, pos: Vector3, material: String) -> void:
	if _quality() < 0.2:
		return
	var col := Color("a89e86")
	match material:
		"mud", "farm_soil": col = Color("5a4636")
		"moss", "moss_deep", "grass": col = Color("6f8a48")
		"ash": col = Color("8a8790")
		"plank": col = Color("8a7458")
		"gravel": col = Color("9a958c")
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = maxi(2, int(5 * _quality()))
	p.lifetime = 0.45
	p.direction = Vector3(0, 1, 0)
	p.spread = 80.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 0.8
	p.gravity = Vector3(0, -1.5, 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.4
	var q := QuadMesh.new()
	q.size = Vector2.ONE * 0.07
	p.mesh = q
	p.material_override = _mat(col, 0.0)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.9))
	ramp.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = ramp
	p.position = pos
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


## Long-lived ambient motes over an area (spores, dust, embers, drips).
static func ambient(parent: Node3D, biome: String, w: float, d: float) -> Node3D:
	var spec: Dictionary = {
		"grove": {"color": Color("56e0d4"), "n": 90, "glow": 1.6, "rise": 0.08, "size": 0.05},
		"fringe": {"color": Color("56e0d4"), "n": 60, "glow": 1.4, "rise": 0.06, "size": 0.05},
		"blackstone": {"color": Color("a89e86"), "n": 70, "glow": 0.0, "rise": -0.02, "size": 0.04},
		"ember": {"color": Color("ff7a2f"), "n": 70, "glow": 2.6, "rise": 0.5, "size": 0.04},
		"sump": {"color": Color("a58bd6"), "n": 50, "glow": 1.0, "rise": 0.03, "size": 0.05},
	}.get(biome, {})
	var root := Node3D.new()
	root.name = "Ambient"
	if spec.is_empty() or _quality() <= 0.05 or not Settings.graphics.get("ambient_fx", true):
		parent.add_child(root)
		return root
	var p := GPUParticles3D.new()
	p.amount = maxi(8, int(int(spec.n) * _quality()))
	p.lifetime = 12.0
	p.preprocess = 12.0
	p.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(w + 4, 14, d + 4))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(w * 0.5, 2.5, d * 0.5)
	pm.direction = Vector3(0.3, 1, 0)
	pm.spread = 40.0
	pm.initial_velocity_min = 0.02
	pm.initial_velocity_max = 0.12
	pm.gravity = Vector3(0.04, float(spec.rise), 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.4
	pm.turbulence_noise_scale = 6.0
	var curve := CurveTexture.new()
	var c := Curve.new()
	c.add_point(Vector2(0, 0))
	c.add_point(Vector2(0.15, 1))
	c.add_point(Vector2(0.85, 1))
	c.add_point(Vector2(1, 0))
	curve.curve = c
	pm.scale_curve = curve
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2.ONE * float(spec.size)
	p.draw_pass_1 = q
	p.material_override = _mat(spec.color, float(spec.glow))
	p.position = Vector3(w * 0.5, 2.8, d * 0.5)
	root.add_child(p)
	parent.add_child(root)
	return root


## Quietlight's lampmoths: thousands of soft lights rising off the lake (or a thin few when
## the air is poor). Named "Lampmoths" so the view can find and remove it in the morning.
static func lampmoths(parent: Node3D, w: float, d: float, bright: bool) -> void:
	var p := GPUParticles3D.new()
	p.name = "Lampmoths"
	p.amount = maxi(16, int((700 if bright else 90) * maxf(_quality(), 0.3)))
	p.lifetime = 14.0
	p.preprocess = 6.0
	p.visibility_aabb = AABB(Vector3(-4, -2, -4), Vector3(w + 8, 18, d + 8))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(w * 0.42, 0.3, 5.0)   # the lake and its shore
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.15
	pm.initial_velocity_max = 0.45
	pm.gravity = Vector3(0.05, 0.08, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.9
	pm.turbulence_noise_scale = 3.0
	var grad := Gradient.new()
	grad.set_color(0, Color(0.34, 0.88, 0.83, 0.0))
	grad.add_point(0.15, Color(0.34, 0.88, 0.83, 1.0))
	grad.add_point(0.6, Color(0.96, 0.78, 0.46, 1.0))
	grad.set_color(1, Color(0.96, 0.78, 0.46, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2.ONE * (0.12 if bright else 0.08)
	p.draw_pass_1 = q
	var m := _mat(Color.WHITE, 4.0 if bright else 1.6)
	p.material_override = m
	p.position = Vector3(w * 0.5, 0.2, 25.5)
	parent.add_child(p)


## Collected items pop out of where they were gathered, arc up and fly into the player.
static func item_pop(parent: Node3D, from: Vector3, target: Node3D, item: String, count: int) -> void:
	var n := clampi(count, 1, 5)
	for i in n:
		var s := Sprite3D.new()
		s.texture = UiTheme.icon(item)
		s.pixel_size = 0.035
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		s.no_depth_test = true
		s.render_priority = 3
		s.shaded = false
		s.position = from + Vector3(0, 0.3, 0)
		parent.add_child(s)
		var side := (float(i) - float(n - 1) * 0.5) * 0.35
		var peak := from + Vector3(side, 1.3 + randf() * 0.3, 0.1)
		var tw := s.create_tween()
		tw.tween_interval(i * 0.07)
		tw.tween_property(s, "position", peak, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_method(func(k: float) -> void:
			if is_instance_valid(target):
				s.position = peak.lerp(target.global_position + Vector3(0, 1.0, 0), k)
				s.scale = Vector3.ONE * lerpf(1.0, 0.4, k), 0.0, 1.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func() -> void:
			Audio.ui("ui_tick", -14.0)
			s.queue_free())
