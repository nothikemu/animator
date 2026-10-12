class_name Panels
extends CanvasLayer
## Every full-screen-ish panel the player opens: inventory, workbench, shops, notice board,
## journal (notes / people / lore), map, lore pages, pause, saves and settings.
## One window at a time; time stops while it's open; Esc / B closes or goes back.
## Opened through Events.ui_open(panel, data).

const W := 920.0
const H := 600.0
## Panels that size to their content instead of the standard window.
const FIT := {"pause": 600.0, "saves": 820.0, "lore": 720.0}
const ICONS := {"inventory": "ui_pack", "craft": "ui_bench", "shop": "glim", "board": "ui_pin",
	"journal": "ui_book", "map": "ui_map", "lore": "ui_book", "pause": "gear", "saves": "ui_save",
	"settings": "gear"}
const INK := Color("3a2e22")
const PAPER := Color("d9c9a3")
const GIFT_LINES := {
	"love": ["Oh. Oh, for me? I— thank you. Really.", "...You remembered. People don't remember."],
	"like": ["That's thoughtful. Thank you.", "Oh, good. I'll use that."],
	"neutral": ["...Thank you?", "I'll find a place for it."],
	"dislike": ["Ah. Hm. That's... a thing. Thank you.", "Lovely. I'll put it somewhere far away."],
}

var root: Control
var dim: ColorRect
var window: PanelContainer
var title_icon: TextureRect
var title_label: Label
var hint_box: HBoxContainer
var content: MarginContainer
var current := ""
var data: Dictionary = {}
var _back: Array = []                    ## [[panel, data]] for nested panels (pause -> settings)
var _selected_item := ""
var _selected_recipe := ""
var _tween: Tween


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UiTheme.get_theme()
	root.visible = false
	add_child(root)
	dim = ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.03, 0.025, 0.05, 0.66)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	window = PanelContainer.new()
	window.custom_minimum_size = Vector2(W, H)
	window.add_theme_stylebox_override("panel", UiTheme.frame("panel", 14))
	window.resized.connect(func() -> void: window.pivot_offset = (window.size * 0.5).floor())
	center.add_child(window)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	window.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	title_icon = TextureRect.new()
	title_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	title_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title_icon.custom_minimum_size = Vector2(32, 32)
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", UiTheme.size(30))
	title_label.add_theme_color_override("font_color", UiTheme.ACCENT)
	title_label.add_theme_color_override("font_shadow_color", Color(0.1, 0.05, 0.0, 0.9))
	title_label.add_theme_constant_override("shadow_offset_x", 2)
	title_label.add_theme_constant_override("shadow_offset_y", 2)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_box = HBoxContainer.new()
	hint_box.add_theme_constant_override("separation", 14)
	hint_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title_icon)
	head.add_child(title_label)
	head.add_child(hint_box)
	v.add_child(head)
	v.add_child(BrassRule.new())
	content = MarginContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("margin_top", 4)
	v.add_child(content)
	Events.ui_open.connect(open)
	Events.inventory_changed.connect(func() -> void:
		if current in ["inventory", "craft", "shop", "board"]:
			_rebuild())
	Events.money_changed.connect(func(_m: int) -> void:
		if current in ["shop", "inventory"]:
			_rebuild())
	Events.settings_changed.connect(func(s: StringName) -> void:
		if s == &"access":
			UiTheme.invalidate()
			root.theme = UiTheme.get_theme()
			window.add_theme_stylebox_override("panel", UiTheme.frame("panel", 14)))


func is_open() -> bool:
	return current != ""


func _game() -> Node:
	return get_tree().current_scene


# --- Open / close -----------------------------------------------------------------------------

func open(panel: StringName, d: Dictionary) -> void:
	var p := String(panel)
	if Dialogue.active:
		return
	if current == p and p in ["inventory", "journal", "map"]:
		close()   # the same key toggles it shut
		return
	var fresh := current == ""
	if current != "" and p in ["settings", "saves"]:
		_back.append([current, data])
	elif fresh:
		_back.clear()
		Clock.pause("ui")
		_freeze(true)
		Audio.ui("ui_open", -8.0)
	current = p
	data = d
	_selected_item = ""
	_selected_recipe = ""
	root.visible = true
	_rebuild()
	_animate_in(fresh)


func close() -> void:
	if current == "":
		return
	if not _back.is_empty():
		var prev: Array = _back.pop_back()
		current = String(prev[0])
		data = prev[1]
		_rebuild()
		_animate_in(false)
		return
	var was := current
	current = ""
	Clock.resume("ui")
	_freeze(false)
	Audio.ui("ui_close", -8.0)
	Events.ui_closed.emit(StringName(was))
	_animate_out()


## Windows ease in: a small rise in scale and opacity, the backdrop fading behind. Switching
## between panels only fades the contents.
func _animate_in(fresh: bool) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if fresh:
		window.scale = Vector2(0.94, 0.94)
		window.modulate.a = 0.0
		dim.modulate.a = 0.0
		_tween.tween_property(window, "scale", Vector2.ONE, 0.18)
		_tween.tween_property(window, "modulate:a", 1.0, 0.14)
		_tween.tween_property(dim, "modulate:a", 1.0, 0.2)
	else:
		window.scale = Vector2.ONE
		window.modulate.a = 1.0
		dim.modulate.a = 1.0
		content.modulate.a = 0.0
		_tween.tween_property(content, "modulate:a", 1.0, 0.12)


func _animate_out() -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.tween_property(window, "scale", Vector2(0.97, 0.97), 0.1)
	_tween.tween_property(window, "modulate:a", 0.0, 0.1)
	_tween.tween_property(dim, "modulate:a", 0.0, 0.12)
	_tween.chain().tween_callback(func() -> void:
		if current == "":
			root.visible = false)


func _freeze(on: bool) -> void:
	var g := _game()
	if g == null or not g.get("player"):
		return
	var eng: Variant = g.get("engineering")
	if eng and eng.is_active():
		return
	if Dialogue.active:
		return
	g.player.frozen = on


func _unhandled_input(event: InputEvent) -> void:
	if current == "":
		return
	if event.is_action_pressed("cancel") or (event.is_action_pressed("menu") and current != "pause"):
		get_viewport().set_input_as_handled()
		close()
	elif event.is_action_pressed("inventory") and current == "inventory" \
			or event.is_action_pressed("journal") and current == "journal" \
			or event.is_action_pressed("map") and current == "map":
		get_viewport().set_input_as_handled()
		close()
	else:
		get_viewport().set_input_as_handled()   # nothing leaks into the world while a panel is up


func _rebuild() -> void:
	for c in content.get_children():
		content.remove_child(c)
		c.queue_free()
	for c in hint_box.get_children():
		hint_box.remove_child(c)
		c.queue_free()
	if current == "inventory":
		hint_box.add_child(_coin(GameState.money()))
	hint_box.add_child(UiTheme.keycap(Settings.binding_label("cancel"), "back" if not _back.is_empty() else "close"))
	title_icon.texture = UiTheme.icon(String(ICONS.get(current, "gear")))
	var fit: float = FIT.get(current, 0.0)
	window.custom_minimum_size = Vector2(fit, 0) if fit > 0.0 else Vector2(W, H)
	window.size = window.custom_minimum_size
	var body: Control
	match current:
		"inventory": body = _inventory()
		"craft": body = _craft()
		"shop": body = _shop()
		"board": body = _board()
		"journal": body = _journal()
		"map": body = _map()
		"lore": body = _lore()
		"pause": body = _pause()
		"saves": body = _saves()
		"settings":
			title_label.text = "Settings"
			body = SettingsPanel.build()
		_:
			title_label.text = current.capitalize()
			body = _label("Nothing here yet.")
	content.add_child(body)
	_focus_first.call_deferred(body)


func _focus_first(node: Node) -> void:
	if Settings.last_device != "pad" or not is_instance_valid(node):
		return
	var b := _find_focusable(node)
	if b:
		b.grab_focus()


func _find_focusable(n: Node) -> Control:
	if n is BaseButton and (n as BaseButton).visible and not (n as BaseButton).disabled:
		return n as Control
	for c in n.get_children():
		var f := _find_focusable(c)
		if f:
			return f
	return null


# --- Small builders ---------------------------------------------------------------------------

func _label(text: String, size := 18, color := UiTheme.TEXT, wrap := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", UiTheme.size(size))
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(120, 0)
	return l


func _button(text: String, cb: Callable, icon := "", enabled := true) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	if icon != "":
		b.icon = UiTheme.icon(icon)
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", 24)
	b.pressed.connect(func() -> void:
		Audio.ui("ui_select", -6.0)
		cb.call())
	b.mouse_entered.connect(func() -> void:
		if not b.disabled:
			Audio.ui("ui_move", -18.0))
	return b


func _scroll(child: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(child)
	return s


func _icon(name: String, px := 32) -> TextureRect:
	var t := TextureRect.new()
	t.texture = UiTheme.icon(name)
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(px, px)
	return t


func _money_label() -> Control:
	return _coin(GameState.money())


## A glim amount with its coin.
func _coin(amount: int, px := 18, color := UiTheme.LIVING) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	h.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_icon("glim", int(px * 1.3)))
	h.add_child(_label(str(amount), px, color, false))
	return h


## A recessed card for a row or a section.
func _card(pad := 6.0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.well(pad))
	return p


## An item in a slot: the icon large and crisp, its count in the corner.
func _slot(id: String, n: int, selected := false, px := 64) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.frame("slot_selected" if selected else "slot", 0))
	p.custom_minimum_size = Vector2(px, px)
	if id == "":
		return p
	var ic := _icon(id, int(px * 0.62))
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_child(ic)
	if n > 1:
		# The count sits in the corner, over the frame's edge, like a stamp.
		var c := _label(str(n), 15 if px >= 56 else 13, Color.WHITE, false)
		c.add_theme_constant_override("outline_size", 5)
		c.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.06))
		c.size_flags_horizontal = Control.SIZE_SHRINK_END
		c.size_flags_vertical = Control.SIZE_SHRINK_END
		p.add_child(c)
	return p


## A slot that can be clicked or focused with a pad.
func _slot_button(id: String, n: int, selected: bool, on_pick: Callable, px := 64) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(px, px)
	b.focus_mode = Control.FOCUS_ALL
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	b.tooltip_text = Content.item_name(id) if id != "" else ""
	var sl := _slot(id, n, selected, px)
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sl.set_anchors_preset(Control.PRESET_FULL_RECT)
	for c in sl.get_children():
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(sl)
	b.mouse_entered.connect(func() -> void: sl.modulate = Color(1.18, 1.12, 1.0))
	b.mouse_exited.connect(func() -> void: sl.modulate = Color.WHITE)
	if id != "":
		b.pressed.connect(func() -> void:
			Audio.ui("ui_tick", -10.0)
			on_pick.call())
		b.focus_entered.connect(func() -> void:
			if Settings.last_device == "pad" and not selected:
				on_pick.call_deferred())
	else:
		b.focus_mode = Control.FOCUS_NONE
	return b


## A small coloured tag ("Food", "Story").
func _chip(text: String, color := UiTheme.DIM) -> PanelContainer:
	var p := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(color, 0.16)
	st.border_color = Color(color, 0.7)
	st.set_border_width_all(1)
	st.content_margin_left = 6
	st.content_margin_right = 6
	st.content_margin_top = 1
	st.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", st)
	p.add_child(_label(text, 14, color, false))
	return p


## Five hearts for an affection value.
func _hearts(value: float) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 0)
	var full := clampi(int(floor((value + 5.0) / 10.0)), 0, 5)
	for i in 5:
		h.add_child(_icon("ui_heart" if i < full else "ui_heart_empty", 18))
	return h


## Paper: notes on the board, lore pages. Dark ink, no drop shadow.
func _paper(pad := 14) -> PanelContainer:
	var p := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = PAPER
	st.border_color = Color("8a7350")
	st.border_width_bottom = 3
	st.border_width_right = 2
	st.border_width_left = 1
	st.border_width_top = 1
	st.shadow_color = Color(0, 0, 0, 0.35)
	st.shadow_size = 4
	st.shadow_offset = Vector2(3, 4)
	st.content_margin_left = pad
	st.content_margin_right = pad
	st.content_margin_top = pad * 0.8
	st.content_margin_bottom = pad
	p.add_theme_stylebox_override("panel", st)
	return p


func _ink(text: String, size := 17, color := INK) -> Label:
	var l := _label(text, size, color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	return l


func _set_title(text: String) -> void:
	title_label.text = text


# --- Inventory --------------------------------------------------------------------------------

func _nearby_npc() -> Npc:
	var g := _game()
	if g == null or not g.get("npcs") or not g.get("player"):
		return null
	var best: Npc = null
	var best_d := 2.6
	for n: Npc in g.npcs.values():
		if n.indoors or not Society.is_met(n.id):
			continue
		var d: float = n.global_position.distance_to(g.player.global_position)
		if d < best_d:
			best_d = d
			best = n
	return best


func _inventory() -> Control:
	title_label.text = "Pack"
	var slots: Array = GameState.inventory.to_array()
	if _selected_item == "" or GameState.inventory.count(_selected_item) <= 0:
		_selected_item = ""
		for s in slots:
			if s is Dictionary and String(s.get("id", "")) != "":
				_selected_item = String(s.id)
				break
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	# The pack itself: every slot, empty ones too, so you can see how much room is left.
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	var used := 0
	for s in slots:
		var id := String(s.get("id", "")) if s is Dictionary else ""
		var n := int(s.get("n", 0)) if s is Dictionary else 0
		if id != "":
			used += 1
		var pick := id
		grid.add_child(_slot_button(id, n, id != "" and id == _selected_item, func() -> void:
			_selected_item = pick
			_rebuild(), 72))
	var pack_card := _card(8)
	pack_card.add_child(grid)
	left.add_child(pack_card)
	var foot := HBoxContainer.new()
	foot.add_child(_label("%d of %d slots used" % [used, slots.size()], 15, UiTheme.DIM, false))
	left.add_child(foot)
	# Tools on the belt, the one in hand lit.
	var belt := HBoxContainer.new()
	belt.add_theme_constant_override("separation", 6)
	belt.add_child(_label("Tools", 16, UiTheme.ACCENT, false))
	for t: String in GameState.player.get("tools", []):
		var ts := _slot("tool_" + t, 0, t == GameState.current_tool(), 44)
		ts.tooltip_text = Hud._tool_name(t)
		belt.add_child(ts)
	if GameState.has_tool("can"):
		var can := int(GameState.player.get("can", 0))
		var cl := _label("  Can %d/10%s" % [can, " (brine)" if GameState.player.get("can_brine", false) else ""], 15, UiTheme.DIM, false)
		cl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		belt.add_child(cl)
	left.add_child(belt)
	h.add_child(left)
	# The detail card.
	var right := _card(12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 10)
	right.add_child(rv)
	if _selected_item != "":
		var it: Dictionary = Content.item(_selected_item)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 12)
		head.add_child(_slot(_selected_item, 0, true, 84))
		var hv := VBoxContainer.new()
		hv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hv.add_child(_label(Content.item_name(_selected_item), 24, UiTheme.ACCENT, false))
		var tags := HBoxContainer.new()
		tags.add_theme_constant_override("separation", 6)
		var cat := String(it.get("category", ""))
		if cat != "":
			tags.add_child(_chip(cat.capitalize(), UiTheme.LIVING if cat == "story" else UiTheme.DIM))
		for u: String in it.get("uses", []):
			tags.add_child(_chip(u.capitalize(), UiTheme.ACCENT))
		hv.add_child(tags)
		head.add_child(hv)
		rv.add_child(head)
		rv.add_child(BrassRule.new())
		rv.add_child(_label(String(it.get("desc", "")), 18))
		var facts := HBoxContainer.new()
		facts.add_theme_constant_override("separation", 16)
		facts.add_child(_label("You have %d" % GameState.inventory.count(_selected_item), 16, UiTheme.DIM, false))
		if int(it.get("value", 0)) > 0:
			var worth := HBoxContainer.new()
			worth.add_child(_label("Worth about", 16, UiTheme.DIM, false))
			worth.add_child(_coin(int(it.value), 16, UiTheme.TEXT))
			facts.add_child(worth)
		rv.add_child(facts)
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		rv.add_child(spacer)
		var npc := _nearby_npc()
		if npc and cat != "story":
			var who := Society.display_name(npc.id)
			var can_give := not Society.gifted_today(npc.id)
			var item := _selected_item
			rv.add_child(_button("Give to %s" % who if can_give else "%s has had a gift today" % who,
				func() -> void: _give(npc, item), "ui_heart", can_give))
		elif cat != "story":
			rv.add_child(_label("Stand near someone to give it as a gift.", 15, UiTheme.DIM))
	else:
		rv.add_child(_label("Your pack is empty. The Reach is full of things; so is the farm, eventually.", 18, UiTheme.DIM))
	h.add_child(right)
	return h


func _give(npc: Npc, item: String) -> void:
	var tier := Society.give_gift(npc.id, item)
	if tier == "":
		return
	var lines: Array = GIFT_LINES.get(tier, GIFT_LINES.neutral)
	var line := String(lines[randi() % lines.size()])
	close()
	npc.face_towards(_game().player.global_position)
	npc.bark(line, 4.0)
	if tier == "love":
		Events.noticed.emit(StringName(npc.id), "%s will remember that." % Society.display_name(npc.id))


# --- Workbench --------------------------------------------------------------------------------

func _craft() -> Control:
	var station := String(data.get("station", "bench"))
	title_label.text = "Workbench"
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	var known := 0
	var ready := 0
	for id: String in Content.recipes_for_station(station):
		var r: Dictionary = Content.recipes[id]
		if not GameState.knows_recipe(id):
			continue
		known += 1
		var out: Dictionary = r.get("output", {})
		var out_id := String(out.get("item", ""))
		var card := _card(8)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		card.add_child(row)
		row.add_child(_slot(out_id, int(out.get("n", 1)), false, 60))
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 4)
		var title := HBoxContainer.new()
		title.add_child(_label(Content.item_name(out_id), 20, UiTheme.TEXT, false))
		if int(out.get("n", 1)) > 1:
			title.add_child(_label("  ×%d" % int(out.get("n", 1)), 17, UiTheme.DIM, false))
		info.add_child(title)
		var needs := HBoxContainer.new()
		needs.add_theme_constant_override("separation", 14)
		var ok := true
		for inp: String in r.get("inputs", {}):
			var need := int(r.inputs[inp])
			var have := GameState.inventory.count(inp)
			ok = ok and have >= need
			var chip := HBoxContainer.new()
			chip.add_theme_constant_override("separation", 3)
			var ic := _icon(inp, 26)
			ic.tooltip_text = Content.item_name(inp)
			chip.add_child(ic)
			chip.add_child(_label("%d/%d" % [mini(have, 99), need], 16, UiTheme.LIVING if have >= need else UiTheme.DANGER, false))
			needs.add_child(chip)
		info.add_child(needs)
		row.add_child(info)
		var make := _button("Make", func() -> void: _do_craft(id, r), "ui_bench", ok)
		make.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		make.custom_minimum_size = Vector2(120, 44)
		row.add_child(make)
		if not ok:
			card.modulate = Color(1, 1, 1, 0.72)
		else:
			ready += 1
		list.add_child(card)
	if known == 0:
		list.add_child(_label("You don't know how to make anything here yet. People in Wick know things. Ask them.", 18, UiTheme.DIM))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	if known > 0:
		v.add_child(_label("%d recipe%s known · %d you can make now" % [known, "" if known == 1 else "s", ready], 15, UiTheme.DIM))
	v.add_child(_scroll(list))
	return v


func _do_craft(id: String, r: Dictionary) -> void:
	var inputs: Dictionary = r.get("inputs", {})
	if not GameState.inventory.has_all(inputs):
		return
	var out: Dictionary = r.get("output", {})
	var out_id := String(out.get("item", ""))
	if GameState.inventory.room_for(out_id) < int(out.get("n", 1)):
		Events.toast.emit("No room in your pack.", &"warn")
		return
	GameState.inventory.remove_all(inputs)
	GameState.give(out_id, int(out.get("n", 1)))
	GameState.discover("recipes", id)
	Audio.play("craft", -5.0)


# --- Shops ------------------------------------------------------------------------------------

func _shop() -> Control:
	var mid := String(data.get("arg", ""))
	if mid == "":
		mid = "exchange"
	var def: Dictionary = Content.markets.get(mid, {})
	var m := Economy.market(mid)
	title_label.text = String(def.get("name", mid.capitalize()))
	if mid == "grist":
		Economy.grist_visited()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	# What they'll buy from you.
	var sell_card := _card(10)
	sell_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sell := VBoxContainer.new()
	sell.add_theme_constant_override("separation", 6)
	sell_card.add_child(sell)
	sell.add_child(_label("They buy", 20, UiTheme.ACCENT))
	sell.add_child(BrassRule.new())
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	var any := false
	for item: String in def.get("buys", []):
		var have := GameState.inventory.count(item)
		if have <= 0:
			continue
		any = true
		var price := Economy.sell_price(mid, item)
		var row := _shop_row(item, have, price, m.trend(item) if m else "")
		row.add_child(_button("Sell 1", func() -> void: Economy.sell(mid, item, 1)))
		if have > 1:
			row.add_child(_button("All", func() -> void: Economy.sell(mid, item, GameState.inventory.count(item))))
		rows.add_child(row)
	if not any:
		rows.add_child(_label("Nothing they want in your pack. They take: %s." % _list_names(def.get("buys", [])), 16, UiTheme.DIM))
	sell.add_child(_scroll(rows))
	if bool(def.get("food_quality", false)) and Economy.food_quality() < 0.95:
		sell.add_child(_label("Food from sour soil fetches less here.", 15, UiTheme.DANGER))
	h.add_child(sell_card)
	# What they sell.
	var buy_card := _card(10)
	buy_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var buy := VBoxContainer.new()
	buy.add_theme_constant_override("separation", 6)
	buy_card.add_child(buy)
	var top := HBoxContainer.new()
	var bl := _label("They sell", 20, UiTheme.ACCENT, false)
	bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(bl)
	top.add_child(_coin(GameState.money()))
	buy.add_child(top)
	buy.add_child(BrassRule.new())
	var brows := VBoxContainer.new()
	brows.add_theme_constant_override("separation", 6)
	for item: String in def.get("sells", []):
		var price := Economy.buy_price(mid, item)
		var row := _shop_row(item, -1, price, "")
		row.add_child(_button("Buy 1", func() -> void: Economy.buy(mid, item, 1), "", GameState.money() >= price))
		row.add_child(_button("5", func() -> void: Economy.buy(mid, item, 5), "", GameState.money() >= price * 5))
		brows.add_child(row)
	var schem := Economy.schematics(mid)
	if not schem.is_empty():
		brows.add_child(_label("Schematics", 18, UiTheme.ACCENT))
		for sc: Dictionary in schem:
			var sid := String(sc.id)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			row.add_child(_slot("gear", 0, false, 44))
			var nl := _label(String(sc.name), 17)
			nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(nl)
			row.add_child(_coin(int(sc.price), 16, UiTheme.TEXT))
			row.add_child(_button("Learn", func() -> void:
				if Economy.buy_schematic(mid, sid):
					_rebuild(), "", GameState.money() >= int(sc.price)))
			brows.add_child(row)
	buy.add_child(_scroll(brows))
	h.add_child(buy_card)
	return h


## Icon, name (and how many you have), price with its trend.
func _shop_row(item: String, have: int, price: int, trend: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_slot(item, have if have > 0 else 0, false, 44))
	var nl := _label(Content.item_name(item), 17)
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nl.tooltip_text = String(Content.item(item).get("desc", ""))
	nl.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(nl)
	var pr := _coin(price, 16, UiTheme.TEXT)
	if trend == "dear":
		pr.add_child(_icon("ui_up", 16))
		pr.tooltip_text = "Paying well right now."
	elif trend == "cheap":
		pr.add_child(_icon("ui_down", 16))
		pr.tooltip_text = "Paying poorly right now."
	row.add_child(pr)
	return row


static func _list_names(ids: Array) -> String:
	var out := PackedStringArray()
	for id in ids:
		out.append(Content.item_name(String(id)).to_lower())
	return ", ".join(out) if not out.is_empty() else "nothing"


static func _trend_mark(t: String) -> String:
	match t:
		"dear": return "(dear)"
		"cheap": return "(cheap)"
	return ""


# --- Notice board -----------------------------------------------------------------------------

func _board() -> Control:
	title_label.text = "Notice Board"
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	var notes: Array = []
	if Clock.is_market_day():
		notes.append(["MARKET DAY", "Grist is in from the Blackstone. The Exchange is open late."])
	else:
		notes.append(["MARKET", "Next market day in %d day(s). Knappers prefer you don't shout." % _days_to_market()])
	var ex := Economy.market("exchange")
	if ex:
		var parts := PackedStringArray()
		for item in ["glowbeet", "glowglass", "brass_scrap", "blackstone"]:
			parts.append("%s %d %s" % [Content.item_name(item), Economy.sell_price("exchange", item), _trend_mark(ex.trend(item))])
		notes.append(["EXCHANGE PAYS", "  ·  ".join(parts)])
	if not GameState.has_flag("cistern_fed") and GameState.has_flag("well_fixed"):
		notes.append(["WATER", "Cistern dropping. Boil twice, wash never. — M."])
	if GameState.has_flag("quietlight_announced") and not GameState.has_flag("quietlight_done"):
		notes.append(["QUIETLIGHT", "Fifth night. All lamps out at Hush. ALL lamps. — H."])
	if GameState.has_flag("tremor_done") and not bool(Sim.fact("fissure_sealed")):
		notes.append(["WARNING", "Sour gas west end. Keep children off the low ground. Blackstone at the Exchange."])
	notes.append(["LOST", "One winch cable, forty metres, last seen falling. Return to sender (up)."])
	notes.append(["REMINDER", "The Reach gate is NOT a shortcut to anywhere. — B."])
	# Paper on cork.
	var cork := PanelContainer.new()
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color("5b4030")
	cs.border_color = Color("33241a")
	cs.set_border_width_all(3)
	cs.content_margin_left = 14
	cs.content_margin_right = 10
	cs.content_margin_top = 12
	cs.content_margin_bottom = 12
	cork.add_theme_stylebox_override("panel", cs)
	v.add_theme_constant_override("separation", 12)
	var rh := HBoxContainer.new()
	rh.add_child(_label("Requests", 20, UiTheme.TEXT, false))
	var rhint := _label("  Bring what's asked. People remember who helped.", 15, Color(UiTheme.TEXT, 0.6), false)
	rhint.size_flags_vertical = Control.SIZE_SHRINK_END
	rh.add_child(rhint)
	v.add_child(rh)
	var rgrid := GridContainer.new()
	rgrid.columns = 2
	rgrid.add_theme_constant_override("h_separation", 16)
	rgrid.add_theme_constant_override("v_separation", 16)
	for r: Dictionary in Requests.open:
		rgrid.add_child(_request_note(r))
	if Requests.open.is_empty():
		var empty := _paper()
		empty.custom_minimum_size = Vector2(390, 0)
		empty.add_child(_ink("Nobody's asking for anything today. Give it a morning.", 17, Color(INK, 0.7)))
		rgrid.add_child(empty)
	v.add_child(rgrid)
	v.add_child(_label("Notices", 20, UiTheme.TEXT, false))
	var ngrid := GridContainer.new()
	ngrid.columns = 2
	ngrid.add_theme_constant_override("h_separation", 16)
	ngrid.add_theme_constant_override("v_separation", 16)
	for n: Array in notes:
		var paper := _paper(12)
		paper.custom_minimum_size = Vector2(390, 0)
		paper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var nv := VBoxContainer.new()
		nv.add_child(_ink(String(n[0]), 15, Color("8a3a22")))
		nv.add_child(_ink(String(n[1]), 17))
		paper.add_child(nv)
		ngrid.add_child(paper)
	v.add_child(ngrid)
	cork.add_child(_scroll(v))
	return cork


func _request_note(r: Dictionary) -> Control:
	var paper := _paper(12)
	paper.custom_minimum_size = Vector2(390, 0)
	paper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	paper.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	head.add_child(_icon("ui_pin", 22))
	var who := String(r.npc)
	var from := _ink("From %s" % Society.display_name(who), 16, Color("6b2f1c"))
	from.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(from)
	var left := int(r.expires) - Clock.day
	head.add_child(_ink("last day" if left <= 0 else "%d days left" % (left + 1), 14, Color(INK, 0.6)))
	v.add_child(head)
	v.add_child(_ink("\"%s\"" % String(r.text), 17))
	var have := GameState.inventory.count(String(r.item))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_slot(String(r.item), int(r.n), false, 48))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)
	info.add_child(_ink("%d × %s" % [int(r.n), Content.item_name(String(r.item))], 16))
	info.add_child(_ink("you have %d" % have, 14, Color("2f6b5e") if have >= int(r.n) else Color("8a3a22")))
	row.add_child(info)
	var pay := HBoxContainer.new()
	pay.add_child(_icon("glim", 22))
	pay.add_child(_ink(str(int(r.reward)), 17))
	pay.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(pay)
	var id := int(r.id)
	var b := _button("Hand in", func() -> void:
		if Requests.fill(id):
			Audio.ui("chime", -6.0)
			_rebuild(), "", Requests.can_fill(r))
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(b)
	v.add_child(row)
	return paper


static func _days_to_market() -> int:
	for i in range(1, 4):
		if (Clock.day + i) % 3 == 2:
			return i
	return 3


# --- Journal ----------------------------------------------------------------------------------

## Where a note's current stage points, in words ("Pump hall", "Sallow"), or "".
static func _note_where(thread_id: String) -> String:
	var d := Threads.def(thread_id)
	var stages: Array = d.get("stages", [])
	var st := Threads.stage(thread_id)
	if st < 1 or st > stages.size():
		return ""
	var where := String(stages[st - 1].get("where", ""))
	if where == "":
		return ""
	return String(Objectives.resolve(where).get("label", ""))


func _journal() -> Control:
	title_label.text = "Journal"
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.current_tab = int(data.get("tab", 0))
	# Notes
	var notes := VBoxContainer.new()
	notes.name = "Notes"
	notes.add_theme_constant_override("separation", 10)
	var active := Threads.active_notes()
	for n: Dictionary in active:
		var card := _card(10)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var pin := _icon("ui_pin", 24)
		pin.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(pin)
		var nv := VBoxContainer.new()
		nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nv.add_child(_label(String(n.title), 20, UiTheme.ACCENT))
		nv.add_child(_label(String(n.note), 17))
		var where := _note_where(String(n.id))
		if where != "":
			var wr := HBoxContainer.new()
			wr.add_theme_constant_override("separation", 4)
			wr.add_child(_icon("ui_map", 18))
			wr.add_child(_label(where, 15, UiTheme.LIVING, false))
			nv.add_child(wr)
		row.add_child(nv)
		card.add_child(row)
		notes.add_child(card)
	if active.is_empty():
		notes.add_child(_label("Nothing pressing. Walk around. Somebody will need something.", 17, UiTheme.DIM))
	var done: Array = Threads.completed.keys()
	if not done.is_empty():
		notes.add_child(BrassRule.new())
		notes.add_child(_label("Done", 17, UiTheme.DIM))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 18)
		flow.add_theme_constant_override("v_separation", 6)
		for id: String in done:
			var d := HBoxContainer.new()
			d.add_child(_icon("st_ok", 18))
			d.add_child(_label(String(Threads.def(id).get("title", id)), 15, UiTheme.DIM, false))
			flow.add_child(d)
		notes.add_child(flow)
	tabs.add_child(_scroll(notes))
	tabs.set_tab_title(0, "Notes")
	tabs.set_tab_icon(0, UiTheme.icon("ui_pin"))
	# People
	var people := VBoxContainer.new()
	people.add_theme_constant_override("separation", 10)
	var met := 0
	for id: String in Content.npcs:
		if not Society.is_met(id):
			continue
		met += 1
		var card := _card(8)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		card.add_child(row)
		var frame := PanelContainer.new()
		frame.add_theme_stylebox_override("panel", UiTheme.frame("slot", 0))
		var por := TextureRect.new()
		por.texture = DialogueBox.portrait_for(id, "")
		por.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		por.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		por.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		por.custom_minimum_size = Vector2(72, 72)
		frame.add_child(por)
		frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(frame)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 4)
		var def: Dictionary = Content.npc(id)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 10)
		top.add_child(_label(String(def.get("name", id)), 20, Content.color(String(def.get("color", "amber")), UiTheme.ACCENT), false))
		var tl := _label(String(def.get("title", "")), 15, UiTheme.DIM, false)
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tl.size_flags_vertical = Control.SIZE_SHRINK_END
		top.add_child(tl)
		top.add_child(_hearts(Society.axis(id, "affection")))
		info.add_child(top)
		info.add_child(_label(Society.describe(id), 16))
		var tags := HBoxContainer.new()
		tags.add_theme_constant_override("separation", 6)
		var mood := Society.mood(id)
		if mood != "" and mood != "content":
			tags.add_child(_chip("Seems " + mood, UiTheme.DIM))
		if Society.gifted_today(id):
			tags.add_child(_chip("Gift given today", UiTheme.LIVING))
		if Society.axis(id, "affection") >= 10.0:
			var likes := PackedStringArray()
			for it: String in def.get("likes", []):
				likes.append(Content.item_name(it).to_lower())
			if not likes.is_empty():
				tags.add_child(_chip("Likes " + ", ".join(likes), UiTheme.ACCENT))
		if tags.get_child_count() > 0:
			info.add_child(tags)
		row.add_child(info)
		people.add_child(card)
	if met == 0:
		people.add_child(_label("You haven't met anyone yet. Wick is small; that won't last.", 17, UiTheme.DIM))
	tabs.add_child(_scroll(people))
	tabs.set_tab_title(1, "People")
	tabs.set_tab_icon(1, UiTheme.icon("ui_people"))
	# Lore
	var lore := VBoxContainer.new()
	lore.add_theme_constant_override("separation", 12)
	var found: Dictionary = GameState.discovered.get("lore", {})
	var shown := 0
	for id: String in Content.lore:
		if not found.has(id) or id.begins_with("_"):
			continue
		shown += 1
		var e: Dictionary = Content.lore[id]
		var card := _paper(14)
		var lv := VBoxContainer.new()
		lv.add_theme_constant_override("separation", 4)
		lv.add_child(_ink(String(e.get("title", id)), 19, Color("6b2f1c")))
		lv.add_child(_ink(String(e.get("where", "")), 14, Color(INK, 0.65)))
		lv.add_child(_ink(String(e.get("text", "")), 16))
		card.add_child(lv)
		lore.add_child(card)
	if shown == 0:
		lore.add_child(_label("Nothing found yet. Old things are everywhere down here, if you look.", 17, UiTheme.DIM))
	tabs.add_child(_scroll(lore))
	tabs.set_tab_title(2, "Found (%d)" % shown)
	tabs.set_tab_icon(2, UiTheme.icon("ui_book"))
	tabs.tab_changed.connect(func(t: int) -> void:
		data["tab"] = t
		Audio.ui("ui_tick", -10.0))
	return tabs


# --- Map --------------------------------------------------------------------------------------

func _map() -> Control:
	title_label.text = "Map"
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(W - 40, H - 120)
	# Here: the current area, whole, with names, residents and the objective.
	var here := VBoxContainer.new()
	var mm := Minimap.new()
	mm.full = true
	mm.custom_minimum_size = Vector2(W - 60, H - 210)
	mm.size_flags_vertical = Control.SIZE_EXPAND_FILL
	here.add_child(mm)
	var o := Objectives.current()
	var hint := "Amber ring: where your notes point. Arrows: ways out." if not o.is_empty() else "No notes pointing anywhere just now."
	if not o.is_empty():
		hint = "%s — %s" % [String(o.title), String(o.note)]
	here.add_child(_label(hint, 15, UiTheme.DIM))
	tabs.add_child(here)
	var here_name := "Wick" if GameState.current_area == "wick" else String(ReachGen.node_by_id(GameState.reach_graph, GameState.current_area).get("name", "Here"))
	tabs.set_tab_title(0, here_name)
	# The Reach: the graph of caverns.
	var v := VBoxContainer.new()
	var mv := MapView.new()
	mv.custom_minimum_size = Vector2(W - 60, H - 210)
	mv.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(mv)
	v.add_child(_label("Wick sits at the top. Every passage you've walked is drawn; the rest is guesswork.", 15, UiTheme.DIM))
	tabs.add_child(v)
	tabs.set_tab_title(1, "The Reach")
	tabs.current_tab = clampi(int(data.get("tab", 0)), 0, 1)
	tabs.tab_changed.connect(func(t: int) -> void:
		data["tab"] = t
		Audio.ui("ui_tick", -10.0))
	return tabs


## Draws the Reach graph: discovered nodes named, unknown ones as faint question marks.
class MapView:
	extends Control

	func _draw() -> void:
		var g: Dictionary = GameState.reach_graph
		var nodes: Array = g.get("nodes", [])
		var seen: Dictionary = GameState.discovered.get("places", {})
		var pos := {}
		var tiers := {}
		for n: Dictionary in nodes:
			var t := int(n.get("tier", 1))
			if not tiers.has(t):
				tiers[t] = []
			tiers[t].append(n)
		var sz := size
		pos["wick"] = Vector2(sz.x * 0.5, 40)
		for t: int in tiers:
			var list: Array = tiers[t]
			for i in list.size():
				var x := sz.x * (float(i) + 1.0) / (float(list.size()) + 1.0)
				pos[String(list[i].id)] = Vector2(x, 40 + float(t) * (sz.y - 80) / 3.2)
		var font := UiTheme.font()
		for e: Dictionary in g.get("edges", []):
			var a := String(e.a)
			var b := String(e.b)
			if not pos.has(a) or not pos.has(b):
				continue
			var known := seen.has(a) or seen.has(b) or a == "wick"
			var col := Color(UiTheme.BORDER, 0.8 if known else 0.18)
			if not ReachGen.passable(e, GameState.flags):
				col = Color(UiTheme.DANGER, 0.5)
			draw_line(pos[a], pos[b], col, 3.0 if known else 1.0)
		for id: String in pos:
			var known := id == "wick" or seen.has(id)
			var here := GameState.current_area == id
			var c: Color = UiTheme.LIVING if here else (UiTheme.ACCENT if known else Color(UiTheme.DIM, 0.3))
			draw_rect(Rect2(pos[id] - Vector2(7, 7), Vector2(14, 14)), c)
			var obj := Objectives.current()
			if not obj.is_empty() and String(obj.area) == id and id != "wick":
				draw_arc(pos[id], 13.0, 0, TAU, 24, UiTheme.ACCENT, 2.0)
			var label := "Wick" if id == "wick" else (String(ReachGen.node_by_id(GameState.reach_graph, id).get("name", id)) if known else "?")
			draw_string(font, pos[id] + Vector2(12, 6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.size(16), c)
			if here:
				draw_string(font, pos[id] + Vector2(12, 24), "you are here", HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.size(13), UiTheme.DIM)


# --- Lore page --------------------------------------------------------------------------------

func _lore() -> Control:
	var id := String(data.get("id", data.get("arg", "")))
	var e: Dictionary = Content.lore.get(id, {})
	title_label.text = "Something written"
	GameState.discover("lore", id)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	var page := _paper(26)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 8)
	pv.add_child(_ink(String(e.get("title", "")), 24, Color("6b2f1c")))
	pv.add_child(_ink(String(e.get("where", "")), 15, Color(INK, 0.65)))
	pv.add_child(_ink(String(e.get("text", "The writing has gone to nothing.")), 20))
	page.add_child(pv)
	v.add_child(page)
	var foot := HBoxContainer.new()
	var copied := _label("Copied into your journal.", 15, UiTheme.DIM, false)
	copied.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(copied)
	foot.add_child(_button("Close", close, "ui_book"))
	v.add_child(foot)
	return v


# --- Pause, saves -----------------------------------------------------------------------------

func _pause() -> Control:
	title_label.text = "Paused"
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	# Where you are and what you're doing, at a glance.
	var card := _card(12)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 6)
	card.add_child(cv)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	top.add_child(_icon("ph_" + Clock.phase(), 36))
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_theme_constant_override("separation", 0)
	tv.add_child(_label("Day %d · %s" % [Clock.day, Clock.time_string()], 24, UiTheme.TEXT, false))
	tv.add_child(_label("%s · %s" % [Clock.phase().capitalize(), String(Saves.make_meta().get("place", ""))], 16, UiTheme.DIM, false))
	top.add_child(tv)
	top.add_child(_coin(GameState.money(), 20))
	cv.add_child(top)
	var o := Objectives.current()
	if not o.is_empty():
		var nr := HBoxContainer.new()
		nr.add_theme_constant_override("separation", 8)
		nr.add_child(_icon("ui_pin", 20))
		nr.add_child(_label(String(o.title), 16, UiTheme.ACCENT, false))
		cv.add_child(nr)
	var mins := int(GameState.playtime / 60.0)
	cv.add_child(_label("Played %s" % ("%d h %02d min" % [mins / 60, mins % 60] if mins >= 60 else "%d min" % mins), 14, UiTheme.DIM, false))
	v.add_child(card)
	v.add_child(BrassRule.new())
	var actions: Array = [
		["Resume", close, "st_ok"],
		["Save or load", func() -> void: open(&"saves", {}), "ui_save"],
		["Journal", func() -> void:
			current = ""
			open(&"journal", {}), "ui_book"],
		["Settings", func() -> void: open(&"settings", {}), "gear"],
		["Save and quit to title", func() -> void:
			Saves.save(0)
			root.visible = false
			current = ""
			GameFlow.quit_to_menu(get_tree()), "ui_door"],
	]
	for spec: Array in actions:
		var b := _button(String(spec[0]), spec[1], String(spec[2]))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 46)
		v.add_child(b)
	return v


func _saves() -> Control:
	title_label.text = "Save or Load"
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	for slot in Saves.SLOTS:
		var info := Saves.slot_info(slot)
		var card := _card(8)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		card.add_child(row)
		row.add_child(_icon("ui_save", 32))
		var lv := VBoxContainer.new()
		lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lv.add_theme_constant_override("separation", 0)
		lv.add_child(_label("Autosave" if slot == 0 else "Slot %d" % slot, 18, UiTheme.ACCENT, false))
		if info.is_empty():
			lv.add_child(_label("Empty", 15, UiTheme.DIM, false))
			card.modulate = Color(1, 1, 1, 0.75)
		else:
			lv.add_child(_label("%s · Day %d, %s · %s%s" % [String(info.get("name", "")), int(info.get("day", 1)),
				String(info.get("time", "")), String(info.get("place", "")),
				"  (recovered)" if info.get("from_backup", false) else ""], 16, UiTheme.TEXT, false))
		row.add_child(lv)
		if slot != 0:
			row.add_child(_button("Save here", func() -> void:
				if Saves.save(slot):
					Events.toast.emit("Saved.", &"info")
				_rebuild(), "ui_save"))
		row.add_child(_button("Load", func() -> void:
			var err := GameFlow.continue_from(get_tree(), slot)
			if err != "":
				Events.toast.emit("Couldn't load: %s" % err, &"warn")
			else:
				root.visible = false
				current = "", "", not info.is_empty()))
		v.add_child(card)
	v.add_child(_label("Wick also saves itself every time you sleep.", 15, UiTheme.DIM))
	return v
