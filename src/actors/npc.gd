class_name Npc
extends Node3D
## A resident. Knows where they're going, what they're doing and why (their schedule block),
## walks there on the grid, performs the activity, goes indoors to sleep or hide from bad air,
## and occasionally says something when the player passes.

const SPEED := 2.1
const INDOOR := ["sleep", "away", "ill"]
## Schedule activity -> the animation that shows it (falls back to idle if a sheet lacks it).
const DO_ANIM := {"tea": "tea", "work": "wrench", "crank": "crank", "inspect": "inspect", "sit": "sit",
	"ledger": "ledger", "trade": "coins", "tend": "tend", "observe": "observe", "cook": "cook",
	"serve": "serve", "talk": "talk"}

var id := ""
var def: Dictionary = {}
var area: AreaMap
var astar: AStarGrid2D
var sprite: PixelSprite3D
var shadow: MeshInstance3D
var interact: Interactable
var bark_label: Label3D
var block: Dictionary = {}               ## current schedule block
var path: PackedVector2Array = []
var path_i := 0
var view := "down"
var facing := Vector2(0, 1)
var indoors := false
var talking := false
var override_target: Variant = null      ## Vector2i forced destination (story beats)
var _bark_cooldown := 20.0
var _bark_t := 0.0
var _fade := 1.0
var _blocked_notice := false
var _speaking := false                   ## their line is on screen
var _oneshot := ""                       ## emote / fidget / wave in progress
var _idle_t := 0.0
var _next_fidget := 12.0
var _waved_day := -1
var _player: Node3D


## Where a resident lives right now: their sheet's "area" (default Wick), overridden by the
## last matching {"when": [...], "area": ...} rule in "areas" (Barnaby goes down to Sallow).
static func area_of(npc_id: String) -> String:
	var d := Content.npc(npc_id)
	var out := String(d.get("area", "wick"))
	for rule: Dictionary in d.get("areas", []):
		if Conditions.check(rule.get("when", []), GameState):
			out = String(rule.get("area", out))
	return out


## Every named spot in every place a resident can be (home area plus any "areas" rule).
static func points_for(npc_id: String) -> Dictionary:
	var def := Content.npc(npc_id)
	var areas := [String(def.get("area", "wick"))]
	for r: Dictionary in def.get("areas", []):
		areas.append(String(r.get("area", "")))
	var out := {}
	for a: String in areas:
		var m: Dictionary = Content.wick_map if a == "wick" else Content.maps.get(a, {})
		for k in m.get("points", {}):
			out[k] = true
	return out


func setup(npc_id: String, a: AreaMap, grid: AStarGrid2D) -> void:
	id = npc_id
	def = Content.npc(id)
	area = a
	astar = grid
	name = "Npc_" + id
	sprite = PixelSprite3D.new()
	sprite.setup_character(String(def.get("sprite", id)))
	sprite.play("idle_down")
	sprite.finished.connect(func(a: String) -> void:
		if a == _oneshot:
			_oneshot = "")
	sprite.event.connect(func(ev: String) -> void:
		if ev == "step" and visible and _fade > 0.5:
			Audio.play_at("step_soft" if id != "grist" else "step_stone", global_position, -22.0 if id != "grist" else -14.0, 0.15))
	add_child(sprite)
	Events.dialogue_line.connect(_on_line)
	_next_fidget = randf_range(8.0, 20.0)
	shadow = Player.make_blob_shadow(0.45 if id != "grist" else 0.8)
	add_child(shadow)
	bark_label = Label3D.new()
	bark_label.font = UiTheme.font()
	bark_label.font_size = 40
	bark_label.pixel_size = 0.006
	bark_label.outline_size = 10
	bark_label.outline_modulate = Color(0.05, 0.04, 0.07, 0.9)
	bark_label.modulate = Color(UiTheme.TEXT)
	bark_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bark_label.no_depth_test = true
	bark_label.position = Vector3(0, 2.7 if id != "grist" else 3.4, 0)
	bark_label.width = 420
	bark_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bark_label.visible = false
	add_child(bark_label)
	interact = Interactable.make(Vector3(0, 0, 0), _prompt, _talk, 1.6, 10)
	add_child(interact)
	_bark_cooldown = randf_range(8.0, 30.0)


func place_at_schedule() -> void:
	block = Schedule.resolve(def.get("schedule", []), int(Clock.minute), GameState)
	var p := _point(String(block.get("at", "home")))
	position = Vector3(p.x + 0.5, area.world_y(p.x, p.y), p.y + 0.5)
	path = []
	_set_indoors(INDOOR.has(String(block.get("do", ""))) or String(block.get("at", "")) == "away")


func _point(name: String) -> Vector2i:
	if name == "home":
		name = String(def.get("home", "commons"))
	if name == "away":
		name = String(def.get("home", "reach_gate"))
	var pts: Dictionary = area.points
	if pts.has(name):
		return pts[name]
	return pts.get("commons", pts.get("hub", Vector2i(area.w / 2, area.d / 2)))


func cell() -> Vector2i:
	return Vector2i(int(floor(position.x)), int(floor(position.z)))


## Called by the game every in-game minute.
func think() -> void:
	if talking:
		return
	var nb := Schedule.resolve(def.get("schedule", []), int(Clock.minute), GameState)
	var target_name := String(nb.get("at", "home"))
	var changed: bool = nb.get("at") != block.get("at") or nb.get("do") != block.get("do")
	block = nb
	var target := _point(target_name)
	if override_target is Vector2i:
		target = override_target
	if changed or (path.is_empty() and cell() != target):
		_route_to(target)
	if path.is_empty() and cell() == target:
		_set_indoors(INDOOR.has(String(block.get("do", ""))) or target_name == "away")


func _route_to(target: Vector2i) -> void:
	var from := cell()
	if astar.is_point_solid(from):
		# Snap out of a blocked cell (e.g. after a prop appeared).
		for d in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
			if not astar.is_point_solid(from + d):
				from = from + d
				break
	path = astar.get_point_path(from, target)
	path_i = 0
	if path.is_empty() and from != target:
		# Route blocked (flood, rubble): they notice, and remember it.
		if not _blocked_notice:
			_blocked_notice = true
			bark("Path's blocked. Long way round, then.", 3.0)
			Society.remember(id, "route_blocked_d%d" % Clock.day, 1.5, -0.2)
	else:
		_blocked_notice = false
		if not path.is_empty():
			_set_indoors(false)


func _set_indoors(v: bool) -> void:
	if indoors == v:
		return
	indoors = v
	interact.process_mode = Node.PROCESS_MODE_DISABLED if v else Node.PROCESS_MODE_INHERIT
	if v:
		interact.remove_from_group("interactable")
	else:
		interact.add_to_group("interactable")


func _process(delta: float) -> void:
	_fade = move_toward(_fade, 0.0 if indoors else 1.0, delta * 2.0)
	sprite.set_fade(_fade)
	visible = _fade > 0.01
	shadow.visible = _fade > 0.5
	if _bark_t > 0.0:
		_bark_t -= delta
		bark_label.modulate.a = clampf(_bark_t, 0.0, 1.0)
		if _bark_t <= 0.0:
			bark_label.visible = false
	_bark_cooldown -= delta
	if talking:
		if _oneshot == "":
			sprite.play(("talk_" if _speaking else "idle_") + view)
		return
	var moving := false
	if not path.is_empty() and path_i < path.size():
		var goal := Vector3(path[path_i].x + 0.5, 0, path[path_i].y + 0.5)
		var to := Vector3(goal.x - position.x, 0, goal.z - position.z)
		var dist := to.length()
		if dist < 0.06:
			path_i += 1
			if path_i >= path.size():
				path = []
		else:
			var step := minf(dist, SPEED * delta)
			position += to / dist * step
			facing = Vector2(to.x, to.z).normalized()
			moving = true
	var c := cell()
	position.y = move_toward(position.y, area.world_y(c.x, c.y), delta * 3.0)
	_animate(moving)


func _animate(moving: bool) -> void:
	if moving:
		_oneshot = ""
	elif _oneshot == "" and not talking and _player and is_instance_valid(_player):
		# Notice the salvager standing nearby, unless busy with their hands.
		var d := Vector2(_player.global_position.x - position.x, _player.global_position.z - position.z)
		var act := String(DO_ANIM.get(String(block.get("do", "")), ""))
		if d.length() < 2.6 and act in ["", "talk", "observe", "tea", "coins", "inspect"]:
			facing = d.normalized()
		elif d.length() < 5.5 and _waved_day != Clock.day and Society.is_met(id) and act in ["", "talk", "tea", "observe"]:
			_waved_day = Clock.day
			facing = d.normalized()
			_set_view()
			_play_once("wave")
	_set_view()
	if _oneshot != "":
		return
	var hour := Clock.hour()
	if moving:
		var walk := "tired" if (hour >= 22 or hour < 5) and sprite.resolve("tired_" + view).begins_with("tired") else "walk"
		sprite.play(walk + "_" + view)
		_idle_t = 0.0
		return
	var act_anim := String(DO_ANIM.get(String(block.get("do", "")), ""))
	if act_anim != "" and sprite.resolve(act_anim + "_" + view).begins_with(act_anim):
		sprite.play(act_anim + "_" + view)
		return
	_idle_t += get_process_delta_time()
	if _idle_t > _next_fidget:
		_idle_t = 0.0
		_next_fidget = randf_range(10.0, 24.0)
		var pool := ["look", "look", "stretch"]
		if hour >= 21 or hour < 6:
			pool = ["yawn", "look"]
		_play_once(pool[randi() % pool.size()])
		return
	sprite.play("idle_" + view)


func _set_view() -> void:
	if absf(facing.x) > absf(facing.y) * 1.1:
		view = "side"
		sprite.set_flip(facing.x < 0.0)
	else:
		view = "down" if facing.y > 0.0 else "up"
		sprite.set_flip(false)


func _play_once(anim: String) -> void:
	var played := sprite.play(anim + "_" + view, true)
	if played != "" and not bool(sprite.anims.get(played, {}).get("loop", true)):
		_oneshot = played


func _on_line(speaker: StringName, _text: String, emote: StringName) -> void:
	if not talking:
		_speaking = false
		return
	_speaking = String(speaker) == id
	if _speaking and String(emote) in ["happy", "sad", "surprised", "annoyed"]:
		_play_once(String(emote))
	elif _speaking:
		_oneshot = ""


func face_towards(p: Vector3) -> void:
	var d := Vector2(p.x - position.x, p.z - position.z)
	if d.length() > 0.01:
		facing = d.normalized()
	_set_view()


func bark(text: String, seconds := 4.0) -> void:
	if text.is_empty():
		return
	bark_label.text = text
	bark_label.visible = true
	bark_label.modulate.a = 1.0
	_bark_t = seconds
	Events.caption.emit("%s: %s" % [Society.display_name(id) if Society.is_met(id) else _unknown_name(), text], seconds)


## The game hands every resident the player node so they can notice them.
func watch(p: Node3D) -> void:
	_player = p


func try_bark(player_pos: Vector3) -> void:
	if indoors or talking or _bark_cooldown > 0.0:
		return
	if position.distance_to(player_pos) > 4.0:
		return
	_bark_cooldown = randf_range(45.0, 90.0)
	var line := Dialogue.pick_bark(id)
	if line != "":
		bark(line)
		Audio.voice_blip(String(def.get("voice", {}).get("timbre", "")), float(def.get("voice", {}).get("pitch", 1.0)), 65)


func _unknown_name() -> String:
	return String(def.get("unknown", "Someone"))


func _prompt() -> String:
	if indoors:
		return ""
	if Society.is_met(id):
		return "Talk to %s" % Society.display_name(id)
	return "Talk to %s" % _unknown_name().to_lower()


func _talk() -> void:
	var game := get_tree().current_scene
	if game and game.has_method("start_dialogue"):
		game.start_dialogue(self)
