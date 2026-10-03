extends Node
## Quest threads (the player's "Notes"). A thread is a list of stages; each stage has a
## one-line note, optional conditions that auto-advance it, and effects applied on entry.
## Stage 0 = not started. A stage marked "done" completes the thread.
##   {"title": "...", "start": [conds], "stages": [{"note": "...", "advance": [conds],
##    "on_enter": [effects], "done": false, "branch": [{"when": [...], "goto": 4}]}]}

var stages: Dictionary = {}              ## thread id -> current stage (int)
var completed: Dictionary = {}           ## thread id -> day completed
var _checking := false


func _ready() -> void:
	Clock.minute_tick.connect(func(_m: int) -> void: check())


func reset() -> void:
	stages.clear()
	completed.clear()


func def(id: String) -> Dictionary:
	return Content.threads.get(id, {})


func stage(id: String) -> int:
	return int(stages.get(id, 0))


func is_done(id: String) -> bool:
	return completed.has(id)


func set_stage(id: String, s: int) -> void:
	var d := def(id)
	if d.is_empty():
		Log.warn("threads", "unknown thread '%s'" % id)
		return
	var list: Array = d.get("stages", [])
	s = clampi(s, 0, list.size())
	if stage(id) == s:
		return
	stages[id] = s
	if s >= 1:
		var st: Dictionary = list[s - 1]
		GameState.apply_effects(st.get("on_enter", []), "thread:" + id)
		if bool(st.get("done", false)):
			completed[id] = Clock.day
		var note := String(st.get("note", ""))
		if not note.is_empty() and not bool(st.get("silent", false)):
			Events.toast.emit(note, &"thread")
	Events.thread_updated.emit(StringName(id), s)


## Starts threads whose start conditions hold and advances active ones.
func check() -> void:
	if _checking or not GameState.started:
		return
	_checking = true
	for id in Content.threads:
		var d: Dictionary = Content.threads[id]
		var s := stage(id)
		if completed.has(id):
			continue
		if s == 0:
			if d.has("start") and Conditions.check(d.start, GameState):
				set_stage(id, 1)
			continue
		var list: Array = d.get("stages", [])
		if s > list.size():
			continue
		var st: Dictionary = list[s - 1]
		for br in st.get("branch", []):
			if Conditions.check(br.get("when", []), GameState):
				set_stage(id, int(br.goto))
				break
		if stage(id) == s and st.has("advance") and Conditions.check(st.advance, GameState):
			set_stage(id, s + 1)
	_checking = false


## Active one-line notes for the journal/HUD, most recent first.
func active_notes() -> Array:
	var out: Array = []
	for id in stages:
		if completed.has(id) or stage(id) == 0:
			continue
		var d := def(id)
		var list: Array = d.get("stages", [])
		var s := stage(id)
		if s >= 1 and s <= list.size():
			out.append({"id": id, "title": String(d.get("title", id)), "note": String(list[s - 1].get("note", "")),
				"priority": int(d.get("priority", 0))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.priority > b.priority)
	return out


func to_dict() -> Dictionary:
	return {"stages": stages.duplicate(), "completed": completed.duplicate()}


func load_dict(d: Dictionary) -> void:
	reset()
	var s: Variant = d.get("stages", {})
	if s is Dictionary:
		for id in s:
			if Content.threads.has(id):
				stages[id] = int(s[id])
	var c: Variant = d.get("completed", {})
	if c is Dictionary:
		for id in c:
			completed[id] = int(c[id])
