extends Node
## Save slots. Each save collects one section per system, is written to a temp file and
## renamed into place (atomic), and keeps the previous file as a .bak fallback.
## Slot 0 is the autosave (written on sleep); slots 1-3 are manual.

const DIR := "user://saves"
const SLOTS := [0, 1, 2, 3]

var last_saved_at := 0
var last_slot := -1


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)


func slot_path(slot: int) -> String:
	return "%s/slot_%d.json" % [DIR, slot]


func collect_sections() -> Dictionary:
	return {
		"world": GameState.to_dict(), "clock": Clock.to_dict(), "sim": Sim.to_dict(),
		"society": Society.to_dict(), "economy": Economy.to_dict(), "threads": Threads.to_dict(),
		"director": Director.to_dict(), "dialogue": Dialogue.to_dict(), "requests": Requests.to_dict(),
	}


func make_meta() -> Dictionary:
	var area := String(GameState.current_area)
	if area != "wick":
		var n := ReachGen.node_by_id(GameState.reach_graph, area)
		area = String(n.get("name", area))
	else:
		area = "Wick"
	return {"name": String(GameState.player.get("name", "")), "day": Clock.day,
		"time": Clock.time_string(), "place": area, "playtime": int(GameState.playtime),
		"saved_at": int(Time.get_unix_time_from_system()), "game_version": String(ProjectSettings.get_setting("application/config/version", "0"))}


func save(slot: int) -> bool:
	Events.save_started.emit(slot)
	var text := SaveCodec.encode(make_meta(), collect_sections())
	var ok := write_atomic(slot_path(slot), text)
	if ok:
		last_saved_at = int(Time.get_unix_time_from_system())
		last_slot = slot
		Log.info("saves", "saved slot %d (%d bytes)" % [slot, text.length()])
	else:
		Log.error("saves", "could not save slot %d" % slot)
	Events.save_finished.emit(slot, ok)
	return ok


static func write_atomic(path: String, text: String) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("saves: cannot open %s (%s)" % [tmp, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(text)
	f.flush()
	f.close()
	# Verify what landed on disk before replacing the previous save.
	var check := FileAccess.get_file_as_string(tmp)
	if check.length() != text.length():
		push_error("saves: short write to %s" % tmp)
		return false
	if FileAccess.file_exists(path):
		var bak := path + ".bak"
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)
		DirAccess.rename_absolute(path, bak)
	return DirAccess.rename_absolute(tmp, path) == OK


## Reads and decodes a slot, falling back to its backup if the main file is damaged.
func read_slot(slot: int) -> Dictionary:
	var path := slot_path(slot)
	var result := {"ok": false, "error": "empty slot"}
	if FileAccess.file_exists(path):
		result = SaveCodec.decode(FileAccess.get_file_as_string(path))
		if result.ok:
			return result
		Log.warn("saves", "slot %d unreadable (%s); trying backup" % [slot, result.error])
	var bak := path + ".bak"
	if FileAccess.file_exists(bak):
		var b := SaveCodec.decode(FileAccess.get_file_as_string(bak))
		if b.ok:
			b["from_backup"] = true
			return b
	return result


func slot_info(slot: int) -> Dictionary:
	var r := read_slot(slot)
	if not r.ok:
		return {}
	var meta: Dictionary = r.meta
	meta["from_backup"] = r.get("from_backup", false)
	return meta


func has_any_save() -> bool:
	for s in SLOTS:
		if FileAccess.file_exists(slot_path(s)):
			return true
	return false


func latest_slot() -> int:
	var best := -1
	var best_t := -1
	for s in SLOTS:
		var info := slot_info(s)
		if not info.is_empty() and int(info.get("saved_at", 0)) > best_t:
			best_t = int(info.saved_at)
			best = s
	return best


## Applies a decoded save to every system. Returns "" or an error message.
func apply(sections: Dictionary) -> String:
	if not sections.get("world") is Dictionary:
		return "save has no world data"
	GameState.load_dict(sections.world)
	Clock.load_dict(sections.get("clock", {}))
	Sim.load_dict(sections.get("sim", {}), GameState.seed_value)
	Society.load_dict(sections.get("society", {}))
	Economy.load_dict(sections.get("economy", {}))
	Threads.load_dict(sections.get("threads", {}))
	Director.reset(GameState.seed_value)
	Director.load_dict(sections.get("director", {}))
	Dialogue.load_dict(sections.get("dialogue", {}))
	Requests.load_dict(sections.get("requests", {}))
	return ""


func load_slot(slot: int) -> String:
	var r := read_slot(slot)
	if not r.ok:
		return String(r.error)
	return apply(r.sections)


func delete_slot(slot: int) -> void:
	for suffix in ["", ".bak", ".tmp"]:
		var p: String = slot_path(slot) + String(suffix)
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
