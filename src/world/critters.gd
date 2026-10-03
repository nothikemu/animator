class_name Critters
extends Node3D
## Small living things that make a place feel inhabited, and that answer to it:
##  * lampmoths circle lights from Dimming to night; fouled air thins them out
##  * rock-lice graze damp ground, scurry from the player, and keep clear of sulfur ferns
## Purely presentational; ecology that matters to the simulation lives in Sim.

const MOTHS := {"grove": 16, "fringe": 10, "sump": 6, "blackstone": 4, "ember": 0}
const LICE := {"grove": 8, "fringe": 6, "sump": 5, "blackstone": 6, "ember": 0}

var area: AreaMap
var player: Node3D
var moths: Array = []                    ## [{s, anchor, phase, r, h}]
var lice: Array = []                     ## [{s, pos, target, speed, wait}]
var _anchors: Array[Vector3] = []
var _t := 0.0
var _rng := RandomNumberGenerator.new()


func setup(a: AreaMap, p: Node3D) -> void:
	area = a
	player = p
	name = "Critters"
	_rng.seed = hash([GameState.seed_value, a.id, "critters"])
	for pr: Dictionary in a.props:
		if String(pr.get("type", "")) in ["glowroot", "town_lamp", "porch_lamp", "work_lamp", "pale_fungus"]:
			_anchors.append(Vector3(float(pr.x) + 0.5, a.world_y(int(pr.x), int(pr.z)), float(pr.z) + 0.5))
	if _anchors.is_empty():
		_anchors.append(Vector3(a.w * 0.5, 0, a.d * 0.5))
	var moth_tex := PixelSprite3D.load_tex("res://assets/textures/props/lampmoth.png")
	var louse_tex := PixelSprite3D.load_tex("res://assets/textures/props/rocklouse.png")
	if moth_tex[0] != null:
		for i in int(MOTHS.get(a.biome, 6)):
			var s := PixelSprite3D.new()
			s.setup(moth_tex[0], moth_tex[1], Vector2i(9, 7), Vector2i(2, 1), {"rim_strength": 0.0, "emit_strength": 3.0}, 0.55)
			s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(s)
			moths.append({"s": s, "anchor": _anchors[_rng.randi_range(0, _anchors.size() - 1)],
				"phase": _rng.randf() * TAU, "r": _rng.randf_range(0.5, 1.6), "h": _rng.randf_range(1.2, 2.6)})
	if louse_tex[0] != null:
		var spots := _louse_ground()
		for i in mini(int(LICE.get(a.biome, 4)), spots.size()):
			var s := PixelSprite3D.new()
			s.setup(louse_tex[0], null, Vector2i(10, 6), Vector2i(2, 1), {"rim_strength": 0.3}, 0.6)
			add_child(s)
			var c: Vector2i = spots[_rng.randi_range(0, spots.size() - 1)]
			var pos := Vector2(c.x + 0.5, c.y + 0.5)
			lice.append({"s": s, "pos": pos, "home": c, "target": pos, "speed": 0.5, "wait": _rng.randf_range(0.0, 2.0)})


## Damp, walkable ground: the moss beds in Wick, quiet floor near rock elsewhere.
func _louse_ground() -> Array:
	var out: Array = []
	var centre: Vector2i = area.points.get("moss_beds", area.points.get("hub", Vector2i(area.w / 2, area.d / 2)))
	var radius := 5 if area.id == "wick" else 14
	for z in range(centre.y - radius, centre.y + radius + 1):
		for x in range(centre.x - radius, centre.x + radius + 1):
			if area.is_walkable(x, z):
				out.append(Vector2i(x, z))
	return out


func _moth_share() -> float:
	var phase := Clock.phase()
	var time_k := 1.0 if phase in ["dimming", "hush", "night"] else 0.25
	var air := float(Sim.fact("pollution")) if area.id == "wick" and Sim.grid != null else 0.0
	return clampf(time_k * (1.0 - air * 4.0), 0.1, 1.0)


func _louse_share() -> int:
	if area.id != "wick":
		return lice.size()
	var ferns := 0
	for c: Vector2i in Sim.plots:
		if String(Sim.plots[c].get("crop", "")) == "sulfur_fern":
			ferns += 1
	return clampi(lice.size() - ferns, 1, lice.size())


func _process(delta: float) -> void:
	_t += delta
	var flap := int(_t * 12.0) % 2
	var share := _moth_share()
	var shown := int(round(moths.size() * share))
	for i in moths.size():
		var m: Dictionary = moths[i]
		var s: PixelSprite3D = m.s
		var on := i < shown
		s.visible = on
		if not on:
			continue
		var ph: float = m.phase + _t * (0.9 + float(i % 3) * 0.25)
		var r: float = m.r
		var a: Vector3 = m.anchor
		s.position = a + Vector3(cos(ph) * r, float(m.h) + sin(ph * 1.7) * 0.25, sin(ph) * r * 0.7)
		s.set_instance_shader_parameter("frame", float((flap + i) % 2))
	var keep := _louse_share()
	var pp := player.global_position if is_instance_valid(player) else Vector3(-99, 0, -99)
	for i in lice.size():
		var l: Dictionary = lice[i]
		var s: PixelSprite3D = l.s
		s.visible = i < keep
		if not s.visible:
			continue
		var pos: Vector2 = l.pos
		var to_player := Vector2(pp.x, pp.z) - pos
		if to_player.length() < 1.6:
			# Scurry away from the big warm thing.
			l.target = pos - to_player.normalized() * 2.5
			l.speed = 2.2
			l.wait = 0.0
		elif pos.distance_to(l.target) < 0.05:
			l.wait = float(l.wait) - delta
			if float(l.wait) <= 0.0:
				var home: Vector2i = l.home
				var c := home + Vector2i(_rng.randi_range(-3, 3), _rng.randi_range(-3, 3))
				if area.is_walkable(c.x, c.y):
					l.target = Vector2(c.x + _rng.randf_range(0.2, 0.8), c.y + _rng.randf_range(0.2, 0.8))
				l.speed = 0.45
				l.wait = _rng.randf_range(1.0, 4.0)
		var tgt: Vector2 = l.target
		var dir := tgt - pos
		var moving := dir.length() > 0.05
		if moving:
			var step := minf(dir.length(), float(l.speed) * delta)
			var nxt := pos + dir.normalized() * step
			if area.is_walkable(int(nxt.x), int(nxt.y)):
				pos = nxt
			else:
				l.target = pos
			s.set_flip(dir.x < 0.0)
		l.pos = pos
		s.position = Vector3(pos.x, area.world_y(int(pos.x), int(pos.y)) + 0.02, pos.y)
		s.set_instance_shader_parameter("frame", float(int(_t * 10.0) % 2) if moving else 0.0)
