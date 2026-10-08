extends Node
## The Almanac: what this player has seen across every save and every playthrough. Endings,
## the deepest station reached, pages found, and runs begun. It lives outside save slots
## (user://almanac.cfg) so starting again never forgets it. The title screen shows it.

const PATH := "user://almanac.cfg"
const ENDINGS := {
	"everything": "Everything Breathing",
	"together": "Breathe Together",
	"watch": "The Long Watch",
	"sealed": "Sealed",
	"topside": "Topside",
}

var endings: Dictionary = {}            ## id -> {"first": unix time, "count": n}
var lore: Dictionary = {}               ## lore id -> true (union over all runs)
var deepest := 0
var runs := 0


func _ready() -> void:
	_load()
	Events.discovered.connect(func(kind: StringName, id: StringName) -> void:
		if kind == &"lore" and not lore.has(String(id)):
			lore[String(id)] = true
			_save())


func record_ending(id: String) -> void:
	var e: Dictionary = endings.get(id, {"first": int(Time.get_unix_time_from_system()), "count": 0})
	e["count"] = int(e.get("count", 0)) + 1
	endings[id] = e
	_save()


func record_depth(d: int) -> void:
	if d > deepest:
		deepest = d
		_save()


func record_run() -> void:
	runs += 1
	_save()


func seen(id: String) -> bool:
	return endings.has(id)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	var e: Variant = cfg.get_value("almanac", "endings", {})
	endings = e if e is Dictionary else {}
	var l: Variant = cfg.get_value("almanac", "lore", {})
	lore = l if l is Dictionary else {}
	deepest = int(cfg.get_value("almanac", "deepest", 0))
	runs = int(cfg.get_value("almanac", "runs", 0))


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("almanac", "endings", endings)
	cfg.set_value("almanac", "lore", lore)
	cfg.set_value("almanac", "deepest", deepest)
	cfg.set_value("almanac", "runs", runs)
	if cfg.save(PATH) != OK:
		Log.warn("almanac", "could not save the almanac")
