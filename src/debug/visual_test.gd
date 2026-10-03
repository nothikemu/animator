extends Node3D
## Visual test scene: sprites, lights, shaders, camera and post in isolation.
##   godot -- res://scenes/test/visual_test.tscn  (add --capture=out.png to screenshot)

var _frames := 40


func _ready() -> void:
	var env := EnvCtl.new()
	add_child(env)
	var mode := Dev.arg("mode", "sprites")
	var floor_map := AreaMap.new(12, 8)
	floor_map.mat.fill("cobble")
	var view := AreaView.new()
	add_child(view)
	view.build(floor_map)
	var names := ["glowroot_0", "glowroot_small_0", "town_lamp", "stalagmite_0", "mushroom_0", "crop_glowbeet"]
	for i in names.size():
		var t := PixelSprite3D.load_tex("res://assets/textures/props/%s.png" % names[i])
		var tex: Texture2D = t[0]
		var s := PixelSprite3D.new()
		var frames := 5 if names[i].begins_with("crop") else 1
		s.setup(tex, t[1], Vector2i(tex.get_width() / frames, tex.get_height()), Vector2i(frames, 1), {"rim_strength": 0.25})
		s.position = Vector3(1.5 + i * 1.8, 0, 4.0)
		if mode == "selflit" and i == 0:
			s.layers = 2
		add_child(s)
	var p := PixelSprite3D.new()
	p.setup_character("player")
	p.play("idle_down")
	p.position = Vector3(5.0, 0, 6.0)
	add_child(p)
	var b := PixelSprite3D.new()
	b.setup_character("barnaby")
	b.play("idle_down")
	b.position = Vector3(7.0, 0, 6.0)
	add_child(b)
	if mode != "dark":
		var l := OmniLight3D.new()
		l.light_color = Color("56e0d4")
		l.light_energy = 1.2
		l.omni_range = 6.0
		l.position = Vector3(1.5, 2.0, 5.1)
		l.light_cull_mask = ~2 & 0xFFFFF
		add_child(l)
	var cam := Camera3D.new()
	cam.fov = 30.0
	add_child(cam)
	cam.look_at_from_position(Vector3(6, 7.5, 15.5), Vector3(6, 0.8, 4.5))


func _process(_d: float) -> void:
	if Dev.has_arg("capture"):
		_frames -= 1
		if _frames == 0:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(Dev.arg("capture"))
			get_tree().quit()
