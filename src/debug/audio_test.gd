extends Control
## Audio test bench: every generated sound effect, voice and ambience on a button, and each
## music cue with live sliders for its stems (the same mixer the game drives).
##   godot -- --scene=res://scenes/test/audio_test.tscn


func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UiTheme.PANEL_DARK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 24
	scroll.offset_top = 20
	scroll.offset_right = -24
	scroll.offset_bottom = -20
	add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	scroll.add_child(v)
	v.add_child(_title("Music"))
	for cue: String in Audio.CUES:
		var row := HBoxContainer.new()
		var b := Button.new()
		b.text = cue
		b.custom_minimum_size = Vector2(120, 0)
		var sliders: Dictionary = {}
		b.pressed.connect(func() -> void:
			var st := {}
			for k in sliders:
				st[k] = (sliders[k] as HSlider).value
			Audio.music(cue, st))
		row.add_child(b)
		for stem: String in Audio.CUES[cue]:
			var l := Label.new()
			l.text = stem
			row.add_child(l)
			var s := HSlider.new()
			s.min_value = 0.0
			s.max_value = 1.0
			s.step = 0.05
			s.value = 1.0 if stem == Audio.CUES[cue][0] else 0.6
			s.custom_minimum_size = Vector2(90, 20)
			sliders[stem] = s
			s.value_changed.connect(func(_x: float) -> void:
				if Audio.current_cue() == cue:
					var st := {}
					for k in sliders:
						st[k] = (sliders[k] as HSlider).value
					Audio.set_stems(st))
			row.add_child(s)
		v.add_child(row)
	var crisis := HBoxContainer.new()
	var cl := Label.new()
	cl.text = "Crisis (low-pass + drive)"
	crisis.add_child(cl)
	var cs := HSlider.new()
	cs.max_value = 1.0
	cs.step = 0.05
	cs.custom_minimum_size = Vector2(200, 20)
	cs.value_changed.connect(func(x: float) -> void: Audio.crisis(x))
	crisis.add_child(cs)
	v.add_child(crisis)
	v.add_child(_title("Ambience"))
	var amb := HFlowContainer.new()
	for a in ["grove", "blackstone", "ember", "sump"]:
		amb.add_child(_btn(a, func() -> void: Audio.ambience(a)))
	v.add_child(amb)
	v.add_child(_title("Sound effects"))
	var flow := HFlowContainer.new()
	var names := {}
	for f in DirAccess.get_files_at(Audio.SFX_DIR):
		if not f.ends_with(".ogg") or f.begins_with("voice_"):
			continue
		var base := f.get_basename()
		var us := base.rfind("_")
		if us > 0 and base.substr(us + 1).is_valid_int():
			base = base.substr(0, us)
		names[base] = true
	var keys: Array = names.keys()
	keys.sort()
	for n: String in keys:
		flow.add_child(_btn(n, func() -> void: Audio.play(n)))
	v.add_child(flow)
	v.add_child(_title("Voices"))
	var vf := HFlowContainer.new()
	for timbre in ["brass_muffled", "pluck_clock", "glass_bow", "reed_warm", "stone_marimba", "player"]:
		vf.add_child(_btn(timbre, func() -> void: _speak(timbre)))
	v.add_child(vf)


func _title(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_color_override("font_color", UiTheme.ACCENT)
	l.add_theme_font_size_override("font_size", 24)
	return l


func _btn(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.pressed.connect(cb)
	return b


func _speak(timbre: String) -> void:
	var line := "Hello there, topper."
	for i in line.length():
		if line[i] != " ":
			Audio.voice_blip(timbre, 1.0, line.unicode_at(i))
		await get_tree().create_timer(0.055).timeout
