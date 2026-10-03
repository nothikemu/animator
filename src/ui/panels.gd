class_name Panels
extends CanvasLayer
## Every full-screen-ish panel the player opens: inventory, workbench, shops, notice board,
## journal (notes / people / lore), map, lore pages, pause, saves and settings.
## One window at a time; time stops while it's open; Esc / B closes or goes back.
## Opened through Events.ui_open(panel, data).

const W := 900.0
const H := 580.0
const GIFT_LINES := {
	"love": ["Oh. Oh, for me? I— thank you. Really.", "...You remembered. People don't remember."],
	"like": ["That's thoughtful. Thank you.", "Oh, good. I'll use that."],
	"neutral": ["...Thank you?", "I'll find a place for it."],
	"dislike": ["Ah. Hm. That's... a thing. Thank you.", "Lovely. I'll put it somewhere far away."],
}

var root: Control
var window: PanelContainer
var title_label: Label
var hint_label: Label
var content: MarginContainer
var current := ""
var data: Dictionary = {}
var _back: Array = []                    ## [[panel, data]] for nested panels (pause -> settings)
var _selected_item := ""


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UiTheme.get_theme()
	root.visible = false
	add_child(root)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.03, 0.025, 0.05, 0.62)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	window = PanelContainer.new()
	window.custom_minimum_size = Vector2(W, H)
	var pb := UiTheme.panel_box(UiTheme.PANEL, UiTheme.BORDER, 2, 18)
	pb.shadow_size = 8
	window.add_theme_stylebox_override("panel", pb)
	center.add_child(window)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	window.add_child(v)
	var head := HBoxContainer.new()
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", UiTheme.size(28))
	title_label.add_theme_color_override("font_color", UiTheme.ACCENT)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_label = Label.new()
	hint_label.add_theme_color_override("font_color", UiTheme.DIM)
	hint_label.add_theme_font_size_override("font_size", UiTheme.size(15))
	head.add_child(title_label)
	head.add_child(hint_label)
	v.add_child(head)
	var sep := HSeparator.new()
	v.add_child(sep)
	content = MarginContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(content)
	Events.ui_open.connect(open)
	Events.inventory_changed.connect(func() -> void:
		if current in ["inventory", "craft", "shop"]:
			_rebuild())
	Events.money_changed.connect(func(_m: int) -> void:
		if current == "shop":
			_rebuild())
	Events.settings_changed.connect(func(s: StringName) -> void:
		if s == &"access":
			UiTheme.invalidate()
			root.theme = UiTheme.get_theme())


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
	if current != "" and p in ["settings", "saves"]:
		_back.append([current, data])
	elif current == "":
		_back.clear()
		Clock.pause("ui")
		_freeze(true)
		Audio.ui("ui_open", -8.0)
	current = p
	data = d
	_selected_item = ""
	root.visible = true
	_rebuild()


func close() -> void:
	if current == "":
		return
	if not _back.is_empty():
		var prev: Array = _back.pop_back()
		current = String(prev[0])
		data = prev[1]
		_rebuild()
		return
	var was := current
	current = ""
	root.visible = false
	Clock.resume("ui")
	_freeze(false)
	Audio.ui("ui_close", -8.0)
	Events.ui_closed.emit(StringName(was))


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
	hint_label.text = "[%s] close" % Settings.binding_label("cancel")
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


func _money_label() -> Label:
	return _label("%d glim" % GameState.money(), 18, UiTheme.LIVING, false)


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
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	var slots: Array = GameState.inventory.to_array()
	var shown := 0
	for s in slots:
		if not s is Dictionary or String(s.get("id", "")) == "":
			continue
		var id := String(s.id)
		var n := int(s.get("n", 1))
		var b := Button.new()
		b.custom_minimum_size = Vector2(76, 68)
		b.icon = UiTheme.icon(id)
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.text = "×%d" % n
		b.add_theme_font_size_override("font_size", UiTheme.size(15))
		b.tooltip_text = Content.item_name(id)
		b.toggle_mode = true
		b.button_pressed = id == _selected_item
		b.pressed.connect(func() -> void:
			_selected_item = id
			_rebuild())
		b.focus_entered.connect(func() -> void:
			if Settings.last_device == "pad" and _selected_item != id:
				_selected_item = id
				_rebuild.call_deferred())
		grid.add_child(b)
		shown += 1
	if shown == 0:
		left.add_child(_label("Your pack is empty. The Reach is full of things; so is the farm, eventually.", 17, UiTheme.DIM))
	left.add_child(_scroll(grid))
	var tools := HBoxContainer.new()
	tools.add_child(_label("Tools: ", 16, UiTheme.DIM, false))
	for t: String in GameState.player.get("tools", []):
		var ic := _icon("tool_" + t, 28)
		ic.tooltip_text = t.capitalize()
		tools.add_child(ic)
	var can := int(GameState.player.get("can", 0))
	if GameState.has_tool("can"):
		tools.add_child(_label("   Can: %d/10%s" % [can, " (brine)" if GameState.player.get("can_brine", false) else ""], 16, UiTheme.DIM, false))
	left.add_child(tools)
	h.add_child(left)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(300, 0)
	right.add_theme_constant_override("separation", 8)
	right.add_child(_money_label())
	if _selected_item != "" and GameState.inventory.count(_selected_item) > 0:
		var it: Dictionary = Content.item(_selected_item)
		var head := HBoxContainer.new()
		head.add_child(_icon(_selected_item, 48))
		head.add_child(_label(Content.item_name(_selected_item), 22, UiTheme.ACCENT))
		right.add_child(head)
		right.add_child(_label(String(it.get("desc", "")), 16, UiTheme.TEXT))
		right.add_child(_label(String(it.get("category", "")).capitalize() + (" · worth about %d glim" % int(it.get("value", 0)) if int(it.get("value", 0)) > 0 else ""), 15, UiTheme.DIM))
		var npc := _nearby_npc()
		if npc and String(it.get("category", "")) != "story":
			var who := Society.display_name(npc.id)
			var can_give := not Society.gifted_today(npc.id)
			var item := _selected_item
			right.add_child(_button("Give to %s" % who if can_give else "%s has had a gift today" % who,
				func() -> void: _give(npc, item), "gear", can_give))
	else:
		right.add_child(_label("Pick something to look at it.", 16, UiTheme.DIM))
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
	list.add_theme_constant_override("separation", 6)
	var known := 0
	for id: String in Content.recipes_for_station(station):
		var r: Dictionary = Content.recipes[id]
		if not GameState.knows_recipe(id):
			continue
		known += 1
		var out: Dictionary = r.get("output", {})
		var out_id := String(out.get("item", ""))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(_icon(out_id, 36))
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(_label("%s ×%d" % [Content.item_name(out_id), int(out.get("n", 1))], 19))
		var parts := PackedStringArray()
		var ok := true
		for inp: String in r.get("inputs", {}):
			var need := int(r.inputs[inp])
			var have := GameState.inventory.count(inp)
			ok = ok and have >= need
			parts.append("%d %s (%d)" % [need, Content.item_name(inp).to_lower(), have])
		info.add_child(_label("Needs " + ", ".join(parts), 15, UiTheme.TEXT if ok else UiTheme.DIM))
		row.add_child(info)
		row.add_child(_button("Make", func() -> void: _do_craft(id, r), "", ok))
		list.add_child(row)
	if known == 0:
		list.add_child(_label("You don't know how to make anything here yet. People in Wick know things. Ask them.", 17, UiTheme.DIM))
	return _scroll(list)


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
	var mid := String(data.get("arg", "exchange"))
	var def: Dictionary = Content.markets.get(mid, {})
	var m := Economy.market(mid)
	title_label.text = String(def.get("name", mid))
	if mid == "grist":
		Economy.grist_visited()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	# Sell column
	var sell := VBoxContainer.new()
	sell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sell.add_child(_label("Sell", 20, UiTheme.ACCENT))
	var any := false
	for item: String in def.get("buys", []):
		var have := GameState.inventory.count(item)
		if have <= 0:
			continue
		any = true
		var row := HBoxContainer.new()
		row.add_child(_icon(item, 28))
		var price := Economy.sell_price(mid, item)
		var trend := m.trend(item) if m else ""
		var name_l := _label("%s ×%d — %d each %s" % [Content.item_name(item), have, price, _trend_mark(trend)], 16)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_l)
		row.add_child(_button("1", func() -> void: Economy.sell(mid, item, 1)))
		if have > 1:
			row.add_child(_button("All", func() -> void: Economy.sell(mid, item, GameState.inventory.count(item))))
		sell.add_child(row)
	if not any:
		sell.add_child(_label("Nothing they want in your pack.", 16, UiTheme.DIM))
	if bool(def.get("food_quality", false)) and Economy.food_quality() < 0.95:
		sell.add_child(_label("Food from sour soil fetches less here.", 15, UiTheme.DIM))
	h.add_child(_scroll(sell))
	# Buy column
	var buy := VBoxContainer.new()
	buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var top := HBoxContainer.new()
	var bl := _label("Buy", 20, UiTheme.ACCENT, false)
	bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(bl)
	top.add_child(_money_label())
	buy.add_child(top)
	for item: String in def.get("sells", []):
		var price := Economy.buy_price(mid, item)
		var row := HBoxContainer.new()
		row.add_child(_icon(item, 28))
		var l := _label("%s — %d" % [Content.item_name(item), price], 16)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(_button("1", func() -> void: Economy.buy(mid, item, 1), "", GameState.money() >= price))
		row.add_child(_button("5", func() -> void: Economy.buy(mid, item, 5), "", GameState.money() >= price * 5))
		buy.add_child(row)
	var schem := Economy.schematics(mid)
	if not schem.is_empty():
		buy.add_child(HSeparator.new())
		buy.add_child(_label("Schematics", 18, UiTheme.ACCENT))
		for s: Dictionary in schem:
			var sid := String(s.id)
			buy.add_child(_button("%s — %d" % [String(s.name), int(s.price)],
				func() -> void:
					if Economy.buy_schematic(mid, sid):
						_rebuild(), "gear", GameState.money() >= int(s.price)))
	h.add_child(_scroll(buy))
	return h


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
	for n: Array in notes:
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", UiTheme.panel_box(Color("2a2520f0"), UiTheme.BORDER_DIM, 1, 12))
		var nv := VBoxContainer.new()
		nv.add_child(_label(String(n[0]), 15, UiTheme.ACCENT))
		nv.add_child(_label(String(n[1]), 17))
		p.add_child(nv)
		v.add_child(p)
	return _scroll(v)


static func _days_to_market() -> int:
	for i in range(1, 4):
		if (Clock.day + i) % 3 == 2:
			return i
	return 3


# --- Journal ----------------------------------------------------------------------------------

func _journal() -> Control:
	title_label.text = "Journal"
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.current_tab = int(data.get("tab", 0))
	# Notes
	var notes := VBoxContainer.new()
	notes.name = "Notes"
	notes.add_theme_constant_override("separation", 12)
	var active := Threads.active_notes()
	for n: Dictionary in active:
		notes.add_child(_label(String(n.title), 19, UiTheme.ACCENT))
		notes.add_child(_label(String(n.note), 17))
	if active.is_empty():
		notes.add_child(_label("Nothing pressing. Walk around. Somebody will need something.", 17, UiTheme.DIM))
	var done: Array = Threads.completed.keys()
	if not done.is_empty():
		notes.add_child(HSeparator.new())
		notes.add_child(_label("Done", 16, UiTheme.DIM))
		for id: String in done:
			notes.add_child(_label("- " + String(Threads.def(id).get("title", id)), 15, UiTheme.DIM))
	tabs.add_child(_scroll(notes))
	tabs.set_tab_title(0, "Notes")
	# People
	var people := VBoxContainer.new()
	people.add_theme_constant_override("separation", 14)
	var met := 0
	for id: String in Content.npcs:
		if not Society.is_met(id):
			continue
		met += 1
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var por := TextureRect.new()
		por.texture = DialogueBox.portrait_for(id, "")
		por.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		por.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		por.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		por.custom_minimum_size = Vector2(64, 64)
		row.add_child(por)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var def: Dictionary = Content.npc(id)
		info.add_child(_label("%s — %s" % [String(def.get("name", id)), String(def.get("title", ""))], 18, Content.color(String(def.get("color", "amber")), UiTheme.ACCENT)))
		info.add_child(_label(Society.describe(id), 16))
		var mood := Society.mood(id)
		if mood != "" and mood != "content":
			info.add_child(_label("Seems %s today." % mood, 15, UiTheme.DIM))
		if Society.axis(id, "affection") >= 10.0:
			var likes := PackedStringArray()
			for it: String in def.get("likes", []):
				likes.append(Content.item_name(it).to_lower())
			info.add_child(_label("Likes: " + ", ".join(likes), 15, UiTheme.DIM))
		row.add_child(info)
		people.add_child(row)
	if met == 0:
		people.add_child(_label("You haven't met anyone yet. Wick is small; that won't last.", 17, UiTheme.DIM))
	tabs.add_child(_scroll(people))
	tabs.set_tab_title(1, "People")
	# Lore
	var lore := VBoxContainer.new()
	lore.add_theme_constant_override("separation", 12)
	var found: Dictionary = GameState.discovered.get("lore", {})
	var shown := 0
	for id: String in Content.lore:
		if not found.has(id):
			continue
		shown += 1
		var e: Dictionary = Content.lore[id]
		lore.add_child(_label(String(e.get("title", id)), 19, UiTheme.ACCENT))
		lore.add_child(_label(String(e.get("where", "")), 14, UiTheme.DIM))
		lore.add_child(_label(String(e.get("text", "")), 16))
	if shown == 0:
		lore.add_child(_label("Nothing found yet. Old things are everywhere down here, if you look.", 17, UiTheme.DIM))
	tabs.add_child(_scroll(lore))
	tabs.set_tab_title(2, "Found")
	tabs.tab_changed.connect(func(t: int) -> void: data["tab"] = t)
	return tabs


# --- Map --------------------------------------------------------------------------------------

func _map() -> Control:
	title_label.text = "Map"
	var v := VBoxContainer.new()
	var mv := MapView.new()
	mv.custom_minimum_size = Vector2(W - 40, H - 150)
	v.add_child(mv)
	v.add_child(_label("Wick sits at the top. Every passage you've walked is drawn; the rest is guesswork.", 15, UiTheme.DIM))
	return v


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
			var label := "Wick" if id == "wick" else (String(ReachGen.node_by_id(GameState.reach_graph, id).get("name", id)) if known else "?")
			draw_string(font, pos[id] + Vector2(12, 6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.size(16), c)
			if here:
				draw_string(font, pos[id] + Vector2(12, 24), "you are here", HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.size(13), UiTheme.DIM)


# --- Lore page --------------------------------------------------------------------------------

func _lore() -> Control:
	var id := String(data.get("id", ""))
	var e: Dictionary = Content.lore.get(id, {})
	title_label.text = String(e.get("title", "Something written"))
	GameState.discover("lore", id)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.add_child(_label(String(e.get("where", "")), 15, UiTheme.DIM))
	var page := PanelContainer.new()
	page.add_theme_stylebox_override("panel", UiTheme.panel_box(Color("2b2620f0"), UiTheme.BORDER_DIM, 1, 22))
	page.add_child(_label(String(e.get("text", "The writing has gone to nothing.")), 20))
	v.add_child(page)
	v.add_child(_label("Copied into your journal.", 15, UiTheme.DIM))
	v.add_child(_button("Close", close))
	return v


# --- Pause, saves -----------------------------------------------------------------------------

func _pause() -> Control:
	title_label.text = "Paused"
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.add_child(_label("Day %d · %s · %s" % [Clock.day, Clock.time_string(), Saves.make_meta().get("place", "")], 18, UiTheme.DIM))
	v.add_child(_button("Resume", close))
	v.add_child(_button("Save or load", func() -> void: open(&"saves", {})))
	v.add_child(_button("Journal", func() -> void:
		current = ""
		open(&"journal", {})))
	v.add_child(_button("Settings", func() -> void: open(&"settings", {})))
	v.add_child(_button("Save and quit to title", func() -> void:
		Saves.save(0)
		root.visible = false
		current = ""
		GameFlow.quit_to_menu(get_tree())))
	return v


func _saves() -> Control:
	title_label.text = "Save or Load"
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	for slot in Saves.SLOTS:
		var info := Saves.slot_info(slot)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var desc := "Empty"
		if not info.is_empty():
			desc = "%s — Day %d, %s, %s%s" % [String(info.get("name", "")), int(info.get("day", 1)), String(info.get("time", "")),
				String(info.get("place", "")), " (recovered)" if info.get("from_backup", false) else ""]
		var l := _label(("Autosave: " if slot == 0 else "Slot %d: " % slot) + desc, 17)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		if slot != 0:
			row.add_child(_button("Save here", func() -> void:
				if Saves.save(slot):
					Events.toast.emit("Saved.", &"info")
				_rebuild()))
		row.add_child(_button("Load", func() -> void:
			var err := GameFlow.continue_from(get_tree(), slot)
			if err != "":
				Events.toast.emit("Couldn't load: %s" % err, &"warn")
			else:
				root.visible = false
				current = "", "", not info.is_empty()))
		v.add_child(row)
	v.add_child(_label("Wick also saves itself every time you sleep.", 15, UiTheme.DIM))
	return v
