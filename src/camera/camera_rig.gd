class_name CameraRig
extends Node3D
## The diorama camera: a narrow-FOV perspective camera tilted over the world, following a
## target with a critically damped spring, a little look-ahead, a breathing idle drift,
## tilt-shift depth of field, and opt-in trauma-based shake. Also hosts the cut transition
## into the side-on Undercroft view (see EngineeringView).

const FOV := 30.0
const PITCH := -46.0
const ZOOM_MIN := 15.0
const ZOOM_MAX := 32.0

var camera: Camera3D
var attrs: CameraAttributesPractical
var target: Node3D
var distance := 24.0
var _zoom_target := 24.0
var _pos := Vector3.ZERO
var _vel := Vector3.ZERO
var _trauma := 0.0
var _t := 0.0
var bounds := Rect2(0, 0, 48, 32)
var mode := "explore"                    ## explore | cut | dialogue | free
var free_transform := Transform3D()      ## used in "free" mode (transitions, cut view)
var focus_override: Variant = null       ## Vector3 to frame during dialogue
var _dialogue_zoom := 0.0


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = FOV
	camera.near = 0.3
	camera.far = 140.0
	attrs = CameraAttributesPractical.new()
	attrs.dof_blur_amount = 0.09
	camera.attributes = attrs
	add_child(camera)
	camera.current = true
	Events.camera_impulse.connect(add_trauma)
	_apply_dof_settings()
	Events.settings_changed.connect(func(s: StringName) -> void:
		if s == &"graphics":
			_apply_dof_settings())


func _apply_dof_settings() -> void:
	var on := bool(Settings.graphics.get("dof", true)) and RenderingServer.get_current_rendering_method() != "gl_compatibility"
	attrs.dof_blur_far_enabled = on
	attrs.dof_blur_near_enabled = on


func snap() -> void:
	if target:
		_pos = _desired_focus()
		_vel = Vector3.ZERO
		_update_transform(0.0)


func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount * Settings.shake_multiplier(), 0.0, 1.0)


func _desired_focus() -> Vector3:
	if focus_override is Vector3:
		return focus_override
	var p := target.global_position if target else Vector3.ZERO
	var look := Vector3.ZERO
	if target and target.has_method("get_velocity_hint"):
		look = target.get_velocity_hint() * 0.35
	p += look
	# Keep the framing inside the authored world.
	p.x = clampf(p.x, bounds.position.x + 6.0, bounds.end.x - 6.0)
	p.z = clampf(p.z, bounds.position.y + 3.0, bounds.end.y - 1.0)
	return p


func _unhandled_input(event: InputEvent) -> void:
	if mode != "explore":
		return
	if event.is_action_pressed("zoom_in"):
		_zoom_target = clampf(_zoom_target - 1.5, ZOOM_MIN, ZOOM_MAX)
	elif event.is_action_pressed("zoom_out"):
		_zoom_target = clampf(_zoom_target + 1.5, ZOOM_MIN, ZOOM_MAX)


func _process(delta: float) -> void:
	_t += delta
	if mode == "free":
		camera.global_transform = free_transform
		_trauma = maxf(0.0, _trauma - delta * 1.4)
		return
	var stick := Input.get_action_strength("zoom_out") - Input.get_action_strength("zoom_in")
	if absf(stick) > 0.3 and Settings.last_device == "pad":
		_zoom_target = clampf(_zoom_target + stick * delta * 8.0, ZOOM_MIN, ZOOM_MAX)
	_dialogue_zoom = move_toward(_dialogue_zoom, 1.0 if mode == "dialogue" else 0.0, delta * 1.6)
	distance = lerpf(distance, _zoom_target - _dialogue_zoom * 4.5, clampf(delta * 4.0, 0.0, 1.0))
	# Critically damped spring toward the focus point.
	var goal := _desired_focus()
	var omega := 5.5
	var x := _pos - goal
	var a := -omega * omega * x - 2.0 * omega * _vel
	_vel += a * delta
	_pos += _vel * delta
	_update_transform(delta)


func _update_transform(delta: float) -> void:
	var pitch := deg_to_rad(PITCH + _dialogue_zoom * 6.0)
	var drift := Vector3(sin(_t * 0.23) * 0.05, sin(_t * 0.31) * 0.03, 0.0)
	var focus := _pos + Vector3(0, 0.9, 0) + drift
	var back := Vector3(0, -sin(pitch), cos(pitch)) * distance
	var cam_pos := focus + back
	var basis := Basis.looking_at(focus - cam_pos, Vector3.UP)
	var t := Transform3D(basis, cam_pos)
	if _trauma > 0.0:
		var s := _trauma * _trauma
		t.origin += Vector3(sin(_t * 31.0) * 0.18, cos(_t * 27.0) * 0.12, 0.0) * s
		t.basis = t.basis.rotated(t.basis.z.normalized(), sin(_t * 23.0) * 0.012 * s)
		_trauma = maxf(0.0, _trauma - delta * 1.4)
	camera.global_transform = t
	# Tilt-shift: sharp around the focus point, softening in front and behind.
	attrs.dof_blur_far_distance = distance + 5.5
	attrs.dof_blur_far_transition = 9.0
	attrs.dof_blur_near_distance = maxf(distance - 6.5, 1.0)
	attrs.dof_blur_near_transition = 3.5


## World point under a screen position on the ground plane y = plane_y.
func screen_to_ground(screen_pos: Vector2, plane_y := 0.0) -> Variant:
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return null
	var t := (plane_y - from.y) / dir.y
	if t < 0.0:
		return null
	return from + dir * t
