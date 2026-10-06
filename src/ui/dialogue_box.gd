class_name DialogueBox
extends CanvasLayer
## Conversation UI: portrait, name plate, typewriter text with voice blips, choices.
## Works with mouse, keyboard and gamepad (choices are focusable buttons).

const CHARS_PER_SEC := 48.0

var root: Control
var panel: PanelContainer
var portrait: TextureRect
var name_label: Label
var text: RichTextLabel
var choices: VBoxContainer
var more: Label
var _visible_chars := 0.0
var _speaker := ""
var _blip_acc := 0.0
var _open := false


func _ready() -> void:
	layer = 20
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.get_theme()
	add_child(root)
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.custom_minimum_size = Vector2(820, 176)
	panel.position = Vector2(-410, -200)
	root.add_child(panel)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	panel.add_child(h)
	var pframe := PanelContainer.new()
	pframe.add_theme_stylebox_override("panel", UiTheme.panel_box(Color("0c0b10"), UiTheme.BORDER, 2, 4))
	portrait = TextureRect.new()
	portrait.custom_minimum_size = Vector2(132, 132)
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pframe.add_child(portrait)
	h.add_child(pframe)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	name_label = Label.new()
	name_label.add_theme_font_size_override("font_size", UiTheme.size(20))
	name_label.add_theme_color_override("font_color", UiTheme.ACCENT)
	v.add_child(name_label)
	text = RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.custom_minimum_size = Vector2(620, 80)
	text.add_theme_font_size_override("normal_font_size", UiTheme.size(21))
	v.add_child(text)
	choices = VBoxContainer.new()
	choices.add_theme_constant_override("separation", 4)
	v.add_child(choices)
	more = Label.new()
	more.text = "▾"
	more.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	more.add_theme_color_override("font_color", UiTheme.ACCENT)
	v.add_child(more)
	panel.visible = false
	Events.dialogue_line.connect(_on_line)
	Events.dialogue_choices.connect(_on_choices)
	Events.dialogue_ended.connect(_on_end)


func is_open() -> bool:
	return _open


func _on_line(speaker: StringName, line: String, emote: StringName) -> void:
	_open = true
	panel.visible = true
	_clear_choices()
	_speaker = String(speaker)
	var who := _speaker
	portrait.visible = who != "narrator"
	if who == "narrator":
		# Stage directions and sounds: no name, no face, dimmer text.
		name_label.text = ""
		text.add_theme_color_override("default_color", UiTheme.DIM)
	elif who == "player":
		text.remove_theme_color_override("default_color")
		name_label.text = String(GameState.player.get("name", "You"))
		name_label.add_theme_color_override("font_color", UiTheme.TEXT)
	else:
		text.remove_theme_color_override("default_color")
		name_label.text = Society.display_name(who) if Society.is_met(who) else String(Content.npc(who).get("unknown", who))
		name_label.add_theme_color_override("font_color", Content.color(String(Content.npc(who).get("color", "amber")), UiTheme.ACCENT))
	if who != "narrator":
		portrait.texture = portrait_for(who if who != "player" else "player", String(emote))
	text.text = line
	text.visible_characters = 0
	_visible_chars = 0.0
	more.visible = false
	if panel.modulate.a < 1.0:
		var tw := create_tween()
		tw.tween_property(panel, "modulate:a", 1.0, 0.15)


func _on_choices(list: Array) -> void:
	text.visible_characters = -1
	_clear_choices()
	for i in list.size():
		var b := Button.new()
		b.text = "  " + String(list[i])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func() -> void:
			Audio.ui("ui_select")
			Dialogue.choose(i))
		b.focus_entered.connect(func() -> void: Audio.ui("ui_move", -10.0))
		choices.add_child(b)
	more.visible = false
	await get_tree().process_frame
	if choices.get_child_count() > 0:
		(choices.get_child(0) as Button).grab_focus()


func _clear_choices() -> void:
	for c in choices.get_children():
		c.queue_free()


func _on_end(_npc: StringName) -> void:
	_open = false
	var tw := create_tween()
	tw.tween_property(panel, "modulate:a", 0.0, 0.15)
	tw.tween_callback(func() -> void: panel.visible = false)


func _process(delta: float) -> void:
	if not _open or text.visible_characters < 0:
		return
	var total := text.get_total_character_count()
	var speed := CHARS_PER_SEC * float(Settings.access.get("text_speed", 1.0))
	_visible_chars += delta * speed
	var n := mini(int(_visible_chars), total)
	if n != text.visible_characters:
		var plain := text.get_parsed_text()
		if n > 0 and n <= plain.length() and plain[n - 1] != " ":
			_blip_acc += 1.0
			if _blip_acc >= 2.0 and _speaker != "narrator":
				_blip_acc = 0.0
				var voice: Dictionary = Content.npc(_speaker).get("voice", {}) if _speaker != "player" else {"timbre": "player", "pitch": 1.0}
				Audio.voice_blip(String(voice.get("timbre", "")), float(voice.get("pitch", 1.0)), plain.unicode_at(n - 1))
		text.visible_characters = n
	if n >= total:
		text.visible_characters = -1
		more.visible = not Dialogue.has_choices()


## Advance: finish the line if still typing, otherwise move the conversation on.
func advance() -> void:
	if not _open:
		return
	if text.visible_characters >= 0 and text.visible_characters < text.get_total_character_count():
		text.visible_characters = -1
		return
	if Dialogue.has_choices():
		return
	Audio.ui("ui_tick", -12.0)
	Dialogue.advance()


static var _portraits: Dictionary = {}


## Head-and-shoulders crop of a character's sheet (front idle or emote frame).
static func portrait_for(char_id: String, emote: String) -> Texture2D:
	var key := char_id + ":" + emote
	if _portraits.has(key):
		return _portraits[key]
	var sprite_id := char_id if char_id == "player" else String(Content.npc(char_id).get("sprite", char_id))
	var meta: Variant = Content.read_json("res://assets/textures/chars/%s.json" % sprite_id)
	if not meta is Dictionary:
		return null
	var tex: Texture2D = load("res://assets/textures/chars/%s.png" % sprite_id)
	var fw := int(meta.w)
	var fh := int(meta.h)
	var cols := int(meta.cols)
	var portraits: Dictionary = meta.get("portraits", {})
	var idx := int(portraits.get(emote if portraits.has(emote) else "neutral", 0))
	var a := AtlasTexture.new()
	a.atlas = tex
	var crop_h := int(fh * 0.62)
	a.region = Rect2((idx % cols) * fw, (idx / cols) * fh, fw, crop_h)
	_portraits[key] = a
	return a
