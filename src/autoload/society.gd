extends Node
## Residents' relationships with the player: axes, memories, moods, gossip and gifts.
## Deeds are interpreted through each resident's own *values* (data/npcs/*.json), so the
## same act can earn Odile's respect and Hesper's resentment.

## Raw deed kinds -> value keys residents care about.
const DEED_VALUES := {
	"repaired": "good_engineering",
	"built_clean": "clean_power",
	"built_dirty": "industrial_power",
	"industrial_power": "industrial_power",
	"clean_power": "clean_power",
	"pollution": "pollution",
	"leaked_water": "leak_caused",
	"sold": "sold_goods",
	"sold_food": "sold_food",
	"community_help": "community_help",
	"water_restored": "water_restored",
	"moss_damaged": "moss_damaged",
	"ecosystem_restored": "ecosystem_restored",
	"kept_word": "kept_word",
	"broke_word": "broke_word",
	"hoarding": "hoarding",
	"studied_life": "curious_about_life",
	"town_dry": "town_dry",
	"endangered": "endangered_people",
	"helped_barnaby": "helped_him",
}
## How much one unit of each deed counts (amounts vary wildly between deed kinds).
const DEED_SCALE := {"pollution": 0.4, "industrial_power": 0.5, "clean_power": 0.6, "leaked_water": 0.5,
	"sold": 0.2, "sold_food": 0.2}
const DAILY_CAP := 8.0                   ## max change per axis per value per day

var socials: Dictionary = {}             ## npc id -> NpcSocial
var _daily: Dictionary = {}              ## "npc:value:axis" -> applied today
var _noticed_today: Dictionary = {}


func _ready() -> void:
	Events.deed.connect(_on_deed)
	Clock.day_started.connect(_on_day)
	Clock.hour_changed.connect(_on_hour)
	Clock.minute_tick.connect(_on_minute)


func reset() -> void:
	socials.clear()
	_daily.clear()
	_noticed_today.clear()
	for id in Content.npcs:
		socials[id] = NpcSocial.new(id)


func social(npc: String) -> NpcSocial:
	if not socials.has(npc) and Content.npcs.has(npc):
		socials[npc] = NpcSocial.new(npc)
	return socials.get(npc)


func display_name(npc: String) -> String:
	return String(Content.npc(npc).get("short", npc.capitalize()))


func mark_met(npc: String) -> void:
	var s := social(npc)
	if s != null and not s.met:
		s.met = true
		GameState.discover("people", npc)
		Events.relationship_changed.emit(StringName(npc))


func is_met(npc: String) -> bool:
	var s := social(npc)
	return s != null and s.met


func axis(npc: String, axis_name: String) -> float:
	var s := social(npc)
	return s.get_axis(axis_name) if s != null else 0.0


func change(npc: String, axis_name: String, delta: float) -> void:
	var s := social(npc)
	if s == null:
		return
	s.change(axis_name, delta)
	Events.relationship_changed.emit(StringName(npc))


func remember(npc: String, mem_id: String, importance: float, sentiment: float, lasting := false) -> void:
	var s := social(npc)
	if s != null and s.remember(mem_id, importance, sentiment, Clock.day, lasting):
		Events.memory_added.emit(StringName(npc), StringName(mem_id))


func has_memory(npc: String, mem_id: String) -> bool:
	var s := social(npc)
	if s == null:
		return false
	return s.has_memory(mem_id) or s.has_memory("heard:" + mem_id)


func mood(npc: String) -> String:
	var s := social(npc)
	return s.mood if s != null else "content"


func talked_today(npc: String) -> bool:
	var s := social(npc)
	return s != null and s.talked_today


func gifted_today(npc: String) -> bool:
	var s := social(npc)
	return s != null and s.gifts_today > 0


func describe(npc: String) -> String:
	var s := social(npc)
	return s.describe(display_name(npc)) if s != null else ""


# --- Deeds -> relationships ----------------------------------------------------------------

func _on_deed(kind: StringName, amount: float, _context: Dictionary) -> void:
	var value_key: String = DEED_VALUES.get(String(kind), "")
	if value_key.is_empty():
		return
	var scale := float(DEED_SCALE.get(String(kind), 1.0))
	var units := clampf(amount * scale, 0.0, 3.0)
	if units <= 0.0:
		return
	for npc in socials:
		var values: Dictionary = Content.npc(npc).get("values", {})
		if not values.has(value_key):
			continue
		var s: NpcSocial = socials[npc]
		var strongest := 0.0
		for ax in values[value_key]:
			var delta := float(values[value_key][ax]) * units
			var key := "%s:%s:%s" % [npc, value_key, ax]
			var room := DAILY_CAP - float(_daily.get(key, 0.0))
			if room <= 0.01:
				continue
			var allowed := clampf(delta, -room, room)
			var used := float(_daily.get(key, 0.0))
			_daily[key] = used + absf(allowed)
			s.change(ax, allowed)
			strongest = maxf(strongest, absf(allowed))
		if strongest >= 2.5 and s.met:
			var nk := "%s:%s" % [npc, value_key]
			if not _noticed_today.has(nk):
				_noticed_today[nk] = true
				Events.noticed.emit(StringName(npc), "%s noticed." % display_name(npc))
		Events.relationship_changed.emit(StringName(npc))


# --- Gifts -----------------------------------------------------------------------------------

## Returns the reaction tier: "love", "like", "dislike", "neutral", or "" if not allowed.
func give_gift(npc: String, item: String) -> String:
	var s := social(npc)
	if s == null or s.gifts_today > 0:
		return ""
	if not GameState.take(item, 1):
		return ""
	s.gifts_today += 1
	var def: Dictionary = Content.npc(npc)
	var tier := "neutral"
	if (def.get("loves", []) as Array).has(item):
		tier = "love"
		s.change("affection", 9.0)
		s.change("shared", 3.0)
	elif (def.get("likes", []) as Array).has(item):
		tier = "like"
		s.change("affection", 4.5)
	elif (def.get("dislikes", []) as Array).has(item):
		tier = "dislike"
		s.change("affection", -3.0)
		s.change("resentment", 2.0)
	else:
		s.change("affection", 1.0)
	s.remember("gift:" + item, 2.5 if tier == "love" else 1.5, -0.5 if tier == "dislike" else 0.6, Clock.day)
	Events.relationship_changed.emit(StringName(npc))
	return tier


# --- Daily rhythm ----------------------------------------------------------------------------

func _on_day(_day: int) -> void:
	_daily.clear()
	_noticed_today.clear()
	for npc in socials:
		socials[npc].decay()


func _on_minute(m: int) -> void:
	# Dimming gossip at the Lantern House.
	if m == 18 * 60 + 45:
		spread_gossip()


func _on_hour(_h: int) -> void:
	update_moods()


## Notable memories about the player spread to everyone at the evening gathering.
func spread_gossip() -> void:
	var news: Array = []
	for npc in socials:
		var s: NpcSocial = socials[npc]
		for m in s.memories:
			if not m.spread and not m.heard and float(m.importance) >= 3.0:
				m.spread = true
				news.append([npc, m])
	for item in news:
		var source: String = item[0]
		var m: Dictionary = item[1]
		for npc in socials:
			if npc == source or Content.npc(npc).get("nonhuman", false):
				continue
			var s: NpcSocial = socials[npc]
			if not s.has_memory(m.id):
				s.remember("heard:" + String(m.id), float(m.importance) * 0.5, float(m.sentiment), Clock.day, false, true)
	if not news.is_empty():
		Events.world_event.emit(&"gossip", {"count": news.size()})


func update_moods() -> void:
	for npc in socials:
		var s: NpcSocial = socials[npc]
		var def: Dictionary = Content.npc(npc)
		var tol: Dictionary = def.get("tolerance", {})
		var sour := float(Sim.fact("air_sour_" + npc)) if Sim.grid != null else 0.0
		var mood := "content"
		if sour > float(tol.get("sour", 0.5)):
			mood = "ill"
		elif s.get_axis("resentment") > 40.0:
			mood = "cold"
		elif npc == "mags" and Sim.town_water < 0.6:
			mood = "worried"
		elif Clock.phase() == "hush":
			mood = "tired"
		else:
			for mem in s.memories:
				if int(mem.day) >= Clock.day - 1 and float(mem.sentiment) > 0.5 and float(mem.importance) >= 3.0:
					mood = "cheerful"
					break
		s.mood = mood


# --- Serialisation -----------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var out := {}
	for npc in socials:
		out[npc] = socials[npc].to_dict()
	return {"npcs": out}


func load_dict(d: Dictionary) -> void:
	reset()
	var n: Variant = d.get("npcs", {})
	if n is Dictionary:
		for npc in n:
			if Content.npcs.has(npc) and n[npc] is Dictionary:
				socials[npc] = NpcSocial.from_dict(npc, n[npc])
