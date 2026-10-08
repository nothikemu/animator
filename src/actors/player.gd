class_name Player
extends Node3D
## The salvager. Moves on the area grid with acceleration/deceleration, faces in four
## directions, carries a headlamp, and acts on the world through interactables (E) and
## tools (F). Movement reads named input actions only.
##
## How the salvager moves says how they're doing: a walk, a run while the run button is held,
## a slow slump after midnight, a hunched shuffle with a sleeve over the mouth in bad air,
## and a careful two-handed carry while holding something precious. Standing still for a
## while brings out small habits (looking round, tapping the headlamp, stretching, a yawn at
## night, a shiver in the cold Sump). Tool use plays the matching action, and its effects land
## on the frame the tool does.

signal acted(kind: String, cell: Vector2i)

const ACCEL := 26.0
const DECEL := 30.0
const SPEED := 3.6
const RADIUS := 0.27
const INTERACT_RANGE := 1.35
const PLAYER_LAYER := 4
const STYLE_SPEED := {"walk": 1.0, "run": 1.6, "tired": 0.72, "cautious": 0.7, "carry": 0.85, "carrycoil": 0.9}

var area: AreaMap
var sprite: PixelSprite3D
var lamp: SpotLight3D
var glow_light: OmniLight3D
var shadow: MeshInstance3D
var velocity := Vector3.ZERO
var facing := Vector2(0, 1)              ## XZ direction
var view := "down"
var busy := 0.0                          ## seconds of action remaining
var frozen := false                      ## dialogue, menus, cut view
var target: Node = null                  ## current interactable
var air_bad := false                     ## set by the game: sour air here
var cold := false                        ## set by the game: a cold cavern
var style := "walk"                      ## current locomotion style
var _y := 0.0
var _last_cell := Vector2i(-1, -1)
var _action := ""                        ## one-shot animation in progress ("" = locomotion)
var _on_hit: Callable
var _idle_t := 0.0
var _next_fidget := 7.0
var _squash := Vector2.ONE
var _was_moving := false
var _lamp_base := 2.4


func _ready() -> void:
	sprite = PixelSprite3D.new()
	sprite.setup_character("player")
	sprite.play("idle_down")
	sprite.layers = PLAYER_LAYER
	sprite.event.connect(_on_sprite_event)
	sprite.finished.connect(_on_sprite_finished)
	add_child(sprite)
	shadow = make_blob_shadow(0.42)
	add_child(shadow)
	# Headlamp: the salvager's own light, warm and narrow, aimed where they face.
	lamp = SpotLight3D.new()
	lamp.light_color = Color("f5c875")
	lamp.light_energy = _lamp_base
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
	_next_fidget = randf_range(6.0, 10.0)


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
	if not frozen and busy <= 0.0 and _action == "":
		input = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	style = _pick_style(input)
	var mult := float(STYLE_SPEED.get(style, 1.0))
	if style == "carrycoil" and Input.is_action_pressed("run"):
		mult *= 1.4            # a careful jog: still both hands on it
	var want := Vector3(input.x, 0, input.y) * SPEED * mult
	var rate := ACCEL if want.length() > 0.01 else DECEL
	velocity = velocity.move_toward(want, rate * delta)
	if input.length() > 0.2:
		facing = input.normalized()
	_move(delta)
	_animate(delta)
	# Smooth vertical follow over steps and stairs.
	var c := cell()
	var ty := area.world_y(c.x, c.y)
	_y = move_toward(_y, ty, delta * 4.0)
	position.y = _y
	if busy > 0.0:
		busy -= delta
		if busy <= 0.0 and _action != "" and bool(sprite.anims.get(_action, {}).get("loop", false)):
			_action = ""          # looping actions (cranking) end when their time is up
			_fire_hit()
	_aim_lamp(delta)
	_squash = _squash.lerp(Vector2.ONE, clampf(delta * 12.0, 0.0, 1.0))
	sprite.scale = Vector3(_squash.x, _squash.y, 1.0)


func _pick_style(input: Vector2) -> String:
	if GameState.inventory.count("governor_coil") > 0 and not GameState.has_flag("coil_installed"):
		return "carrycoil"
	if air_bad:
		return "cautious"
	if input.length() > 0.2 and Input.is_action_pressed("run"):
		return "run"
	var h := Clock.hour()
	if h >= 23 or h < 4:
		return "tired"
	return "walk"


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
			return false
	return true


func _update_view() -> void:
	if absf(facing.x) > absf(facing.y) * 1.1:
		view = "side"
		sprite.set_flip(facing.x < 0.0)
	else:
		view = "down" if facing.y > 0.0 else "up"
		sprite.set_flip(false)


func _animate(delta: float) -> void:
	var moving := velocity.length() > 0.4
	_update_view()
	if _action != "":
		_idle_t = 0.0
		return
	if moving:
		_idle_t = 0.0
		if not _was_moving:
			_squash = Vector2(0.94, 1.05)      # push off
		var name := style + "_" + view
		sprite.play(name)
		# Playback keeps feet planted: the cycle speeds up with ground speed.
		var nominal := SPEED * float(STYLE_SPEED.get(style, 1.0))
		sprite.speed = clampf(velocity.length() / maxf(0.1, nominal), 0.5, 1.3)
	else:
		if _was_moving:
			_squash = Vector2(1.05, 0.95)      # settle
		sprite.speed = 1.0
		_idle_t += delta
		if frozen:
			_idle_t = 0.0
		if _idle_t > _next_fidget and not frozen:
			_fidget()
		elif cold and _idle_t > 2.5:
			sprite.play("shiver_" + view)
		elif air_bad and _idle_t < 0.9:
			sprite.play("cough_" + view)
		elif not sprite.current.begins_with("idle") or sprite.current != "idle_" + view:
			sprite.play("idle_" + view)
	_was_moving = moving


## A small habit, chosen by where and when.
func _fidget() -> void:
	var pool: Array = ["look", "look", "rope"]
	var h := Clock.hour()
	if h >= 21 or h < 5:
		pool += ["yawn", "yawn"]
	elif h < 10:
		pool += ["stretch", "stretch"]
	if area and area.id != "wick":
		pool += ["lamp", "lamp"]
	else:
		pool.append("stretch")
	if cold:
		pool += ["shiver"]
	var pick: String = pool[randi() % pool.size()]
	_idle_t = 0.0
	_next_fidget = randf_range(8.0, 15.0)
	if pick == "shiver":
		sprite.play("shiver_" + view)
		return
	play_once(pick)


## Plays a one-shot animation (fidget, emote, special move) without locking movement
## longer than it lasts.
func play_once(anim: String) -> void:
	var played := sprite.play(anim + "_" + view, true)
	if played == "" or sprite.anims.get(played, {}).get("loop", true):
		return
	_action = played


## Plays the action for a tool or verb and calls `on_hit` when it lands (the "hit" event),
## holding the player still until the animation ends.
func perform(action: String, on_hit: Callable = Callable()) -> void:
	velocity = Vector3.ZERO
	_update_view()
	var played := sprite.play(action + "_" + view, true)
	_on_hit = on_hit
	if played == "":
		_fire_hit()
		return
	_action = played
	busy = sprite.length_of(played)
	var evs: Dictionary = sprite.anims.get(played, {}).get("events", {})
	if not evs.has("hit"):
		_fire_hit()


## Legacy entry point: a generic tool swing for `seconds`.
func use_tool_anim(seconds := 0.45) -> void:
	var tool := GameState.current_tool()
	var anim := String({"tiller": "till", "can": "water", "hammer": "hammer", "wrench": "wrench"}.get(tool, "pickup"))
	perform(anim)
	busy = maxf(busy, seconds)


func react(emote: String) -> void:
	if emote in ["happy", "sad", "surprised", "annoyed", "celebrate", "wave"]:
		play_once(emote)


func _fire_hit() -> void:
	if _on_hit.is_valid():
		var cb := _on_hit
		_on_hit = Callable()
		cb.call()


func _on_sprite_event(ev: String) -> void:
	match ev:
		"step":
			if _action == "":
				_footstep()
		"hit":
			_squash = Vector2(1.08, 0.92)
			if _action.begins_with("knock"):
				Audio.play_at("knock_single", global_position, -4.0, 0.08)
			_fire_hit()
		"tap":
			Audio.play_at("ui_tick", global_position, -18.0, 0.2)


func _on_sprite_finished(anim: String) -> void:
	if anim != _action:
		return
	_action = ""
	busy = 0.0
	_fire_hit()          # in case the animation had no hit frame and nothing fired it


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
	var loud := -11.0 if style == "run" else (-17.0 if style in ["cautious", "tired"] else -14.0)
	Audio.play_at(snd, global_position, loud, 0.12)
	if style == "run" or m in ["mud", "farm_soil", "ash", "gravel"]:
		var parent := get_parent()
		if parent:
			Fx.puff(parent, global_position + Vector3(-facing.x * 0.15, 0.05, -facing.y * 0.15), m)


func _aim_lamp(delta: float) -> void:
	var dir := Vector3(facing.x, -0.55, facing.y).normalized()
	var want := Basis.looking_at(dir, Vector3.UP)
	lamp.basis = lamp.basis.slerp(want, clampf(delta * 8.0, 0.0, 1.0)).orthonormalized()
	var side := 0.18 if view == "side" else 0.0
	lamp.position = Vector3(facing.x * side, 1.75 + (-0.12 if _action.begins_with("plant") or _action.begins_with("harvest") else 0.0), 0.05 + facing.y * 0.1)
	# The headlamp gutters when tapped, and dims a little when the salvager is worn out.
	# A glowglass lens throws it further and wider.
	var lens := GameState.has_gear("lens")
	lamp.spot_range = 13.0 if lens else 9.0
	lamp.spot_angle = 36.0 if lens else 30.0
	var want_e := _lamp_base * (1.25 if lens else 1.0) * (0.85 if style == "tired" else 1.0)
	if _action.begins_with("lamp") and sprite.frame_in_anim() in [4, 5]:
		want_e = 0.25
	lamp.light_energy = move_toward(lamp.light_energy, want_e, delta * 20.0)


func flash(color: Color) -> void:
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: sprite.set_flash(color, v), 0.7, 0.0, 0.25)
