extends Node
## Requests: small asks pinned to the notice board. Each morning, while fewer than max_open
## are up, one more is drawn from data/requests.json among the templates whose 'when' holds.
## The draw is seeded by the world seed and the day, so a seed always posts the same asks.
## Notes come down after days_open days. Handing one in pays the item's worth and a little
## more, and the asker remembers it.

var open: Array = []        ## [{id, npc, item, n, reward, text, posted, expires}]
var done: Dictionary = {}   ## npc -> requests filled for them
var _next_id := 1


func _ready() -> void:
	Clock.day_started.connect(_on_day)


func reset() -> void:
	open.clear()
	done.clear()
	_next_id = 1


func data() -> Dictionary:
	return Content.requests


func _on_day(day: int) -> void:
	if not GameState.started:
		return
	var before := open.size()
	refresh(day)
	if open.size() > before:
		var r: Dictionary = open.back()
		Events.toast.emit("A new note on the notice board, from %s." % Society.display_name(String(r.npc)), &"info")


## Takes down stale notes and posts at most one new one for `day`.
func refresh(day: int) -> void:
	var keep: Array = []
	for r: Dictionary in open:
		if int(r.expires) >= day:
			keep.append(r)
	open = keep
	if open.size() >= int(data().get("max_open", 3)):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:requests:%d" % [GameState.seed_value, day])
	var pool: Array = []
	for t: Dictionary in data().get("templates", []):
		if _taken(t):
			continue
		if Conditions.check(t.get("when", []), GameState):
			pool.append(t)
	if pool.is_empty():
		return
	var t: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
	var span: Array = t.get("n", [1, 1])
	var n := rng.randi_range(int(span[0]), int(span[1]))
	var worth := int(Content.item(String(t.item)).get("value", 5))
	open.append({"id": _next_id, "npc": String(t.npc), "item": String(t.item), "n": n,
		"reward": int(round(float(worth * n) * 1.6)) + 5, "text": String(t.text),
		"posted": day, "expires": day + int(data().get("days_open", 4))})
	_next_id += 1


## One note per asker and item at a time.
func _taken(t: Dictionary) -> bool:
	for r: Dictionary in open:
		if r.npc == String(t.npc) and r.item == String(t.item):
			return true
	return false


func can_fill(r: Dictionary) -> bool:
	return GameState.inventory.count(String(r.item)) >= int(r.n)


## Hands a request in. Returns false if you don't have the goods.
func fill(id: int) -> bool:
	for i in open.size():
		var r: Dictionary = open[i]
		if int(r.id) != id:
			continue
		if not can_fill(r):
			return false
		GameState.take(String(r.item), int(r.n))
		GameState.add_money(int(r.reward))
		var who := String(r.npc)
		Society.change(who, "affection", 1.5)
		Society.change(who, "trust", 0.5)
		done[who] = int(done.get(who, 0)) + 1
		if int(done[who]) == 3:
			Society.remember(who, "kept_asking", 4.0, 0.6, true)
		GameState.add_deed("helped", 1.0, {"npc": who})
		open.remove_at(i)
		Events.toast.emit("%s's request filled. +%d glim." % [Society.display_name(who), int(r.reward)], &"good")
		return true
	return false


func total_done() -> int:
	var n := 0
	for k in done:
		n += int(done[k])
	return n


func to_dict() -> Dictionary:
	return {"open": open.duplicate(true), "done": done.duplicate(), "next": _next_id}


func load_dict(d: Dictionary) -> void:
	reset()
	var o: Variant = d.get("open", [])
	if o is Array:
		for r in o:
			if r is Dictionary and Content.items.has(String(r.get("item", ""))):
				open.append({"id": int(r.get("id", 0)), "npc": String(r.get("npc", "")), "item": String(r.item),
					"n": int(r.get("n", 1)), "reward": int(r.get("reward", 0)), "text": String(r.get("text", "")),
					"posted": int(r.get("posted", 1)), "expires": int(r.get("expires", 1))})
	var dn: Variant = d.get("done", {})
	if dn is Dictionary:
		for k in dn:
			done[String(k)] = int(dn[k])
	_next_id = int(d.get("next", open.size() + 1))
