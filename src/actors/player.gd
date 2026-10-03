class_name Player
extends Node3D
## The salvager. Moves on the area grid with acceleration/deceleration, faces in four
## directions, carries a headlamp, and acts on the world through interactables (E) and
## tools (F). Movement reads named input actions only.

signal acted(kind: String, cell: Vector2i)

const ACCEL := 26.0
const DECEL := 30.0
const SPEED := 3.6
const RADIUS := 0.27
const INTERACT_RANGE := 1.35
const PLAYER_LAYER := 4

var area: AreaMap
var sprite: PixelSprite3D
var lamp: SpotLight3D
var glow_light: OmniLight3D
var shadow: MeshInstance3D
var velocity := Vector3.ZERO
var facing := Vector2(0, 1)              ## XZ direction
var view := "down"
var busy := 0.0                          ## seconds of tool animation remaining
var frozen := false                      ## dialogue, menus, cut view
var target: Node = null                  ## current interactable
var _y := 0.0
var _step_timer := 0.0
var _last_cell := Vector2i(-1, -1)


func _ready() -> void:
	sprite = PixelSprite3D.new()
	sprite.setup_character("player")
	sprite.play("idle_down")
	sprite.layers = PLAYER_LAYER
	add_child(sprite)
	shadow = make_blob_shadow(0.42)
	add_child(shadow)
	# Headlamp: the salvager's own light, warm and narrow, aimed where they face.
	lamp = SpotLight3D.new()
	lamp.light_color = Color("f5c875")
	lamp.light_energy = 2.4
	lamp.spot_range = 9.0
	lamp.spot_angle = 30.0
	lamp.spot_attenuation = 0.8
	lamp.shadow_enabled = true
	lamp.position = Vector3(0, 1.75, 0)
	lamp.light_cull_mask = ~PLAYER_LAYER & 0xFFFFF
	add_child(lamp)
	# A faint fill so the player always reads against the dark.
	glow_light = OmniLight3D.new()
	glow_light.light_color = Color("e8c8a0")
	glow_light.light_energy = 0.55
	glow_light.omni_range = 3.0
	glow_light.position = Vector3(0, 1.6, 1.4)
	glow_light.light_cull_mask = PLAYER_LAYER
	glow_light.shadow_enabled = false
	add_child(glow_light)


static func make_blob_shadow(radius: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(radius * 2.0, radius * 1.4)
	q.orientation = PlaneMesh.FACE_Y
	m.mesh = q
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/blob_shadow.gdshader")
	m.material_override = mat
	m.position = Vector3(0, 0.03, 0)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


func place(cell_pos: Vector2, a: AreaMap) -> void:
	area = a
	position = Vector3(cell_pos.x, a.world_y(int(cell_pos.x), int(cell_pos.y)), cell_pos.y)
	_y = position.y
	velocity = Vector3.ZERO


func cell() -> Vector2i:
	return Vector2i(int(floor(position.x)), int(floor(position.z)))


## The cell in front of the player (for tools).
func facing_cell() -> Vector2i:
	var p := Vector2(position.x, position.z) + facing.normalized() * 0.75
	return Vector2i(int(floor(p.x)), int(floor(p.y)))


func get_velocity_hint() -> Vector3:
	return velocity


func _physics_process(delta: float) -> void:
	if area == null:
		return
	var input := Vector2.ZERO
	if not frozen and busy <= 0.0:
		input = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var want := Vector3(input.x, 0, input.y) * SPEED
	var rate := ACCEL if want.length() > 0.01 else DECEL
	velocity = velocity.move_toward(want, rate * delta)
	if input.length() > 0.2:
		facing = input.normalized()
	_move(delta)
	_animate(delta, input)
	# Smooth vertical follow over steps and stairs.
	var c := cell()
	var ty := area.world_y(c.x, c.y)
	_y = move_toward(_y, ty, delta * 4.0)
	position.y = _y
	if busy > 0.0:
		busy -= delta
	_aim_lamp(delta)


func _move(delta: float) -> void:
	var from := cell()
	var step := velocity * delta
	var p := position
	p.x += step.x
	if not _free_at(p, from):
		p.x = position.x
		velocity.x = 0.0
	p.z += step.z
	if not _free_at(p, from):
		p.z = position.z
		velocity.z = 0.0
	position.x = p.x
	position.z = p.z


func _free_at(p: Vector3, from: Vector2i) -> bool:
	for off in [Vector2(-RADIUS, -RADIUS), Vector2(RADIUS, -RADIUS), Vector2(-RADIUS, RADIUS), Vector2(RADIUS, RADIUS)]:
		var cx := int(floor(p.x + off.x))
		var cz := int(floor(p.z + off.y))
		if cx == from.x and cz == from.y:
			continue
		if not area.can_step(from.x, from.y, cx, cz):
			# Allow diagonal corners if both orthogonal neighbours are passable.
			return false
	return true


func _animate(delta: float, input: Vector2) -> void:
	var moving := velocity.length() > 0.4
	if absf(facing.x) > absf(facing.y) * 1.1:
		view = "side"
		sprite.set_flip(facing.x < 0.0)
	else:
		view = "down" if facing.y > 0.0 else "up"
		sprite.set_flip(false)
	if busy > 0.0:
		sprite.play("work_" + view)
	elif moving:
		sprite.play("walk_" + view)
		_step_timer -= delta * velocity.length() / SPEED
		if _step_timer <= 0.0:
			_step_timer = 0.28
			_footstep()
	else:
		sprite.play("idle_" + view)
		_step_timer = 0.0


func _footstep() -> void:
	var c := cell()
	var m := area.mat_at(c.x, c.y)
	var snd := "step_soft"
	if m in ["cobble", "rock_floor", "stone", "stairs", "blackstone", "basalt", "rock"]:
		snd = "step_stone"
	elif m in ["plank"]:
		snd = "step_wood"
	elif m in ["gravel", "ash"]:
		snd = "step_gravel"
	elif m in ["mud", "farm_soil", "moss_deep"]:
		snd = "step_soft"
	Audio.play_at(snd, global_position, -14.0, 0.12)


func _aim_lamp(delta: float) -> void:
	var dir := Vector3(facing.x, -0.55, facing.y).normalized()
	var want := Basis.looking_at(dir, Vector3.UP)
	lamp.basis = lamp.basis.slerp(want, clampf(delta * 8.0, 0.0, 1.0)).orthonormalized()
	var side := 0.18 if view == "side" else 0.0
	lamp.position = Vector3(facing.x * side, 1.75, 0.05 + facing.y * 0.1)


## Plays the tool-use animation for `seconds` with feedback.
func use_tool_anim(seconds := 0.45) -> void:
	busy = seconds
	velocity = Vector3.ZERO
	sprite.play("work_" + view, true)


func flash(color: Color) -> void:
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: sprite.set_flash(color, v), 0.7, 0.0, 0.25)
