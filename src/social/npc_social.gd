class_name NpcSocial
extends RefCounted
## One resident's view of the player: six hidden axes plus weighted memories.
## Axes are never shown as numbers; `describe()` turns them into a short phrase.

const AXES := ["trust", "respect", "affection", "resentment", "fear", "shared"]
const MEMORY_FLOOR := 0.6
const DAILY_DECAY := 0.82

var npc_id := ""
var axes: Dictionary = {}
var memories: Array = []     ## [{id, sentiment, importance, day, lasting, heard, spread}]
var met := false
var gifts_today := 0
var talked_today := false
var mood := "content"


func _init(id: String = "") -> void:
	npc_id = id
	for a in AXES:
		axes[a] = 0.0


func get_axis(axis: String) -> float:
	return float(axes.get(axis, 0.0))


func change(axis: String, delta: float) -> void:
	if not axes.has(axis):
		return
	# Diminishing returns near the extremes so one action can't max a relationship.
	var cur: float = axes[axis]
	var room := 100.0 - absf(cur) if signf(delta) == signf(cur) else 100.0
	var scaled := delta * clampf(room / 100.0 + 0.25, 0.25, 1.0)
	axes[axis] = clampf(cur + scaled, -100.0, 100.0)


func remember(id: String, importance: float, sentiment: float, day: int, lasting := false,
		heard := false) -> bool:
	for m in memories:
		if m.id == id:
			m.importance = maxf(float(m.importance), importance)
			m.day = day
			m.lasting = m.lasting or lasting
			return false
	memories.append({"id": id, "sentiment": clampf(sentiment, -1.0, 1.0),
		"importance": importance, "day": day, "lasting": lasting, "heard": heard, "spread": false})
	return true


func has_memory(id: String) -> bool:
	for m in memories:
		if m.id == id:
			return true
	return false


func memory(id: String) -> Dictionary:
	for m in memories:
		if m.id == id:
			return m
	return {}


## Daily fading: unimportant memories are forgotten, lasting ones remain.
func decay() -> void:
	var kept: Array = []
	for m in memories:
		if not m.lasting:
			m.importance = float(m.importance) * DAILY_DECAY
		if m.lasting or float(m.importance) >= MEMORY_FLOOR:
			kept.append(m)
	memories = kept
	# Resentment and fear soften slowly over time; shared history never does.
	for a in ["resentment", "fear"]:
		axes[a] = float(axes[a]) * 0.97
	gifts_today = 0
	talked_today = false


## Short natural-language description of how this person regards the player.
func describe(display_name: String) -> String:
	if not met:
		return "%s hasn't met you." % display_name
	var parts: Array = []
	var t := get_axis("trust")
	var r := get_axis("respect")
	var a := get_axis("affection")
	if get_axis("resentment") > 35.0:
		parts.append([-1, "holds a grudge"])
	if get_axis("fear") > 35.0:
		parts.append([-1, "is wary of you"])
	if r > 45.0:
		parts.append([1, "respects your work"])
	elif r > 15.0:
		parts.append([1, "thinks you know what you're doing"])
	elif r < -20.0:
		parts.append([-1, "thinks you're careless"])
	if t > 45.0:
		parts.append([1, "trusts you"])
	elif t > 15.0:
		parts.append([1, "is starting to trust you"])
	elif t < -20.0:
		parts.append([-1, "doesn't trust you"])
	elif r > 15.0 or a > 15.0:
		parts.append([0, "doesn't trust you yet"])
	if a > 45.0:
		parts.append([1, "is fond of you"])
	elif a > 15.0:
		parts.append([1, "likes having you around"])
	elif a < -20.0:
		parts.append([-1, "finds you hard to like"])
	if parts.is_empty():
		return "%s barely knows you." % display_name
	if parts.size() == 1:
		return "%s %s." % [display_name, parts[0][1]]
	var first: Array = parts[0]
	var second: Array = parts[1]
	var joiner := " and " if (int(first[0]) >= 0) == (int(second[0]) >= 0) else " but "
	return "%s %s%s%s." % [display_name, first[1], joiner, second[1]]


func to_dict() -> Dictionary:
	return {"axes": axes.duplicate(), "memories": memories.duplicate(true), "met": met,
		"gifts_today": gifts_today, "talked_today": talked_today, "mood": mood}


static func from_dict(id: String, d: Dictionary) -> NpcSocial:
	var s := NpcSocial.new(id)
	var ax: Variant = d.get("axes", {})
	if ax is Dictionary:
		for a in AXES:
			s.axes[a] = clampf(float(ax.get(a, 0.0)), -100.0, 100.0)
	for m in d.get("memories", []):
		if m is Dictionary and m.has("id"):
			s.memories.append({"id": String(m.id), "sentiment": clampf(float(m.get("sentiment", 0.0)), -1.0, 1.0),
				"importance": maxf(0.0, float(m.get("importance", 1.0))), "day": int(m.get("day", 0)),
				"lasting": bool(m.get("lasting", false)), "heard": bool(m.get("heard", false)),
				"spread": bool(m.get("spread", false))})
	s.met = bool(d.get("met", false))
	s.gifts_today = int(d.get("gifts_today", 0))
	s.talked_today = bool(d.get("talked_today", false))
	s.mood = String(d.get("mood", "content"))
	return s
