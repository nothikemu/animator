extends Node
## Dialogue: rule-based line selection (most specific matching rule wins; tiers story >
## reactive > ambient) and a small conversation runner (say / choice / do / if / goto / open).
## Data: data/dialogue/<npc>.json -> {"lines": [...], "convos": {id: [nodes]}}

const TIER_WEIGHT := {"story": 300, "reactive": 200, "ambient": 100, "bark": 0}

var used: Dictionary = {}                ## line id -> day last used (once-lines stay used)
var seen_convos: Dictionary = {}
var active := false
var npc := ""
var _nodes: Array = []
var _labels: Dictionary = {}
var _index := 0
var _choices: Array = []                 ## currently offered choices (filtered)
var _pending_open := ""
var current := {"speaker": "", "text": "", "emote": ""}


func reset() -> void:
	used.clear()
	seen_convos.clear()
	active = false


# --- Selection -----------------------------------------------------------------------------

## Returns the best line rule for an NPC right now (or {}).
func pick_line(npc_id: String, include_barks := false) -> Dictionary:
	var data: Dictionary = Content.dialogue.get(npc_id, {})
	var best := {}
	var best_score := -1
	for line in data.get("lines", []):
		var tier := String(line.get("tier", "ambient"))
		if tier == "bark" and not include_barks:
			continue
		if tier != "bark" and include_barks:
			continue
		var id := String(line.get("id", ""))
		if bool(line.get("once", false)) and used.has(id):
			continue
		var spec := Conditions.score(line.get("when", []), GameState)
		if spec < 0:
			continue
		var score: int = int(TIER_WEIGHT.get(tier, 100)) + spec * 5 + int(line.get("priority", 0))
		# Prefer lines not already heard today.
		if int(used.get(id, -1)) == Clock.day:
			score -= 60
		if score > best_score:
			best_score = score
			best = line
	return best


func pick_bark(npc_id: String) -> String:
	var line := pick_line(npc_id, true)
	if line.is_empty():
		return ""
	used[String(line.id)] = Clock.day
	return format(String(line.get("text", "")))


# --- Running -------------------------------------------------------------------------------

func start_with(npc_id: String) -> bool:
	var line := pick_line(npc_id)
	if line.is_empty():
		return false
	used[String(line.get("id", ""))] = Clock.day
	npc = npc_id
	if line.has("convo"):
		return start_convo(npc_id, String(line.convo))
	_nodes = [{"say": String(line.get("text", "...")), "emote": String(line.get("emote", ""))}]
	if line.has("do"):
		_nodes.append({"do": line.do})
	_begin()
	return true


## One-off lines outside the rule system (player monologue, signs, notes).
func say_lines(speaker: String, lines: Array) -> void:
	if active:
		return
	npc = speaker
	_nodes = []
	for l in lines:
		_nodes.append({"say": String(l), "who": speaker})
	_labels.clear()
	_index = 0
	_pending_open = ""
	active = true
	Clock.pause("dialogue")
	Events.dialogue_started.emit(StringName(speaker))
	_run()


func start_convo(npc_id: String, convo_id: String) -> bool:
	var data: Dictionary = Content.dialogue.get(npc_id, {})
	var nodes: Variant = data.get("convos", {}).get(convo_id)
	if not nodes is Array:
		Log.warn("dialogue", "missing convo %s/%s" % [npc_id, convo_id])
		return false
	npc = npc_id
	seen_convos[convo_id] = Clock.day
	_nodes = nodes
	_begin()
	return true


func _begin() -> void:
	_labels.clear()
	for i in _nodes.size():
		if _nodes[i].has("label"):
			_labels[String(_nodes[i].label)] = i
	_index = 0
	_pending_open = ""
	active = true
	Clock.pause("dialogue")
	Society.mark_met(npc)
	var s := Society.social(npc)
	if s != null:
		s.talked_today = true
	Events.dialogue_started.emit(StringName(npc))
	_run()


## Advances past the current line.
func advance() -> void:
	if not active or not _choices.is_empty():
		return
	_index += 1
	_run()


func choose(i: int) -> void:
	if not active or i < 0 or i >= _choices.size():
		return
	var c: Dictionary = _choices[i]
	_choices = []
	GameState.apply_effects(c.get("do", []), npc)
	if c.has("goto"):
		_jump(String(c.goto))
	else:
		_index += 1
	_run()


func _jump(label: String) -> void:
	if label == "end":
		_index = _nodes.size()
	elif _labels.has(label):
		_index = int(_labels[label])
	else:
		Log.warn("dialogue", "unknown label '%s' in convo with %s" % [label, npc])
		_index = _nodes.size()


func _run() -> void:
	var guard := 0
	while _index < _nodes.size() and guard < 200:
		guard += 1
		var n: Dictionary = _nodes[_index]
		if n.has("when") and not Conditions.check(n.when, GameState):
			_index += 1
			continue
		if n.has("label"):
			_index += 1
			continue
		if n.has("do"):
			GameState.apply_effects(n.do, npc)
			if not n.has("say") and not n.has("choice"):
				_index += 1
				continue
		if n.has("if"):
			if Conditions.check(n["if"], GameState):
				_jump(String(n.get("goto", "end")))
			else:
				_index += 1
			continue
		if n.has("goto") and not n.has("say"):
			_jump(String(n.goto))
			continue
		if n.has("open"):
			_pending_open = String(n.open)
			_index += 1
			continue
		if n.has("say"):
			var who := String(n.get("who", npc))
			current = {"speaker": who, "text": format(String(n.say)), "emote": String(n.get("emote", ""))}
			Events.dialogue_line.emit(StringName(who), current.text, StringName(current.emote))
			return
		if n.has("choice"):
			_choices = []
			for c in n.choice:
				if c.has("when") and not Conditions.check(c.when, GameState):
					continue
				_choices.append(c)
			if _choices.is_empty():
				_index += 1
				continue
			var texts: Array = []
			for c in _choices:
				texts.append(format(String(c.text)))
			Events.dialogue_choices.emit(texts)
			return
		_index += 1
	_finish()


func _finish() -> void:
	active = false
	_choices = []
	Clock.resume("dialogue")
	var who := npc
	Events.dialogue_ended.emit(StringName(who))
	if not _pending_open.is_empty():
		var parts := _pending_open.split(":", true, 1)
		Events.ui_open.emit(StringName(parts[0]), {"arg": parts[1] if parts.size() > 1 else "", "npc": who})
		_pending_open = ""


func cancel() -> void:
	if active:
		_index = _nodes.size()
		_choices = []
		_finish()


func has_choices() -> bool:
	return not _choices.is_empty()


# --- Text tokens -----------------------------------------------------------------------------

## Replaces {player}, {name:npc}, {price:market:item}, {trend:market:item}, {time}, {day}.
func format(text: String) -> String:
	if not text.contains("{"):
		return text
	var out := ""
	var i := 0
	while i < text.length():
		var open := text.find("{", i)
		if open < 0:
			out += text.substr(i)
			break
		var close := text.find("}", open)
		if close < 0:
			out += text.substr(i)
			break
		out += text.substr(i, open - i)
		out += _token(text.substr(open + 1, close - open - 1))
		i = close + 1
	return out


func _token(t: String) -> String:
	var parts := t.split(":")
	match parts[0]:
		"player": return String(GameState.player.get("name", "you"))
		"name": return Society.display_name(parts[1]) if parts.size() > 1 else ""
		"price":
			if parts.size() > 2:
				return str(Economy.sell_price(parts[1], parts[2]))
		"trend":
			if parts.size() > 2 and Economy.market(parts[1]) != null:
				return Economy.market(parts[1]).trend(parts[2])
		"time": return Clock.time_string()
		"day": return str(Clock.day)
		"item": return Content.item_name(parts[1]) if parts.size() > 1 else ""
	return "{%s}" % t


func to_dict() -> Dictionary:
	return {"used": used.duplicate(), "seen": seen_convos.duplicate()}


func load_dict(d: Dictionary) -> void:
	reset()
	if d.get("used") is Dictionary:
		used = d.used
	if d.get("seen") is Dictionary:
		seen_convos = d.seen
