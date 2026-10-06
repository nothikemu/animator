class_name ObjectiveMarker
extends Node3D
## A small amber gem that hangs, bobbing and turning, over where the active thread wants you
## (or over the exit that leads there). It fades when you're standing on it and stays out of
## dialogue, the cut view and anything the settings turn off.

var _gem: MeshInstance3D
var _light: OmniLight3D
var _t := 0.0
var _alpha := 0.0
var _mat: StandardMaterial3D


func _ready() -> void:
	_gem = MeshInstance3D.new()
	var m := PrismMesh.new()
	m.size = Vector3(0.28, 0.36, 0.28)
	_gem.mesh = m
	_gem.rotation_degrees = Vector3(180, 0, 0)          # point down at the spot
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color("e8a33d")
	_mat.emission_enabled = true
	_mat.emission = Color("e8a33d")
	_mat.emission_energy_multiplier = 1.6
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_gem.material_override = _mat
	_gem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_gem)
	_light = OmniLight3D.new()
	_light.light_color = Color("e8a33d")
	_light.light_energy = 0.6
	_light.omni_range = 2.2
	_light.shadow_enabled = false
	add_child(_light)
	visible = false


func _process(delta: float) -> void:
	_t += delta
	var game := get_parent()
	var show := false
	if game and game.area and game.player and bool(Settings.access.get("objective_marker", true)) \
			and GameState.view_mode != "cut" and not Dialogue.active:
		var lt := Objectives.local_target(Objectives.current(), game.area)
		if not lt.is_empty():
			var c: Vector2i = lt.cell
			var base := Vector3(c.x + 0.5, game.area.world_y(c.x, c.y), c.y + 0.5)
			var dist := Vector2(base.x - game.player.position.x, base.z - game.player.position.z).length()
			show = dist > 1.6
			position = base + Vector3(0, 2.3 + sin(_t * 2.4) * 0.12, 0)
			_gem.rotation.y = _t * 1.6
	_alpha = move_toward(_alpha, 1.0 if show else 0.0, delta * 3.0)
	visible = _alpha > 0.01
	_mat.albedo_color.a = _alpha
	_light.light_energy = 0.6 * _alpha
