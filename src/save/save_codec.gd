class_name SaveCodec
extends RefCounted
## Save file format: a JSON object with a header and one section per system.
##   {"format": "bellows-save", "version": N, "meta": {...}, "sections": {...}}
## Older versions are upgraded step by step by `migrate`; newer (unknown) versions are refused.

const FORMAT := "bellows-save"
const VERSION := 2


static func encode(meta: Dictionary, sections: Dictionary) -> String:
	var doc := {"format": FORMAT, "version": VERSION, "meta": meta, "sections": sections}
	return JSON.stringify(doc, "", false)


## Returns {ok, error, meta, sections}. Never throws; damaged input yields ok=false.
static func decode(text: String) -> Dictionary:
	var result := {"ok": false, "error": "", "meta": {}, "sections": {}}
	if text.strip_edges().is_empty():
		result.error = "empty file"
		return result
	var json := JSON.new()
	if json.parse(text) != OK:
		result.error = "unreadable (line %d: %s)" % [json.get_error_line(), json.get_error_message()]
		return result
	if not json.data is Dictionary:
		result.error = "not a save document"
		return result
	var doc: Dictionary = json.data
	if String(doc.get("format", "")) != FORMAT:
		result.error = "not a Bellows save"
		return result
	var v := int(doc.get("version", 0))
	if v > VERSION:
		result.error = "made by a newer version of the game (v%d)" % v
		return result
	if v < 1:
		result.error = "unknown save version"
		return result
	doc = migrate(doc)
	if not doc.get("sections") is Dictionary:
		result.error = "save has no data sections"
		return result
	result.ok = true
	result.meta = doc.get("meta", {}) if doc.get("meta") is Dictionary else {}
	result.sections = doc.sections
	return result


## Upgrades a document in place, one version at a time.
static func migrate(doc: Dictionary) -> Dictionary:
	var v := int(doc.get("version", 1))
	while v < VERSION:
		match v:
			1:
				doc = _v1_to_v2(doc)
		v += 1
		doc["version"] = v
	return doc


## v1 (pre-alpha) kept money as a top-level section and had no deed history; v2 stores it
## at world.player.money and adds world.history. Kept as a worked example of the path.
static func _v1_to_v2(doc: Dictionary) -> Dictionary:
	var s: Dictionary = doc.get("sections", {})
	var world: Dictionary = s.get("world", {}) if s.get("world") is Dictionary else {}
	var player: Dictionary = world.get("player", {}) if world.get("player") is Dictionary else {}
	if s.has("money"):
		player["money"] = int(s["money"])
		s.erase("money")
	world["player"] = player
	if not world.has("history"):
		world["history"] = {}
	s["world"] = world
	doc["sections"] = s
	return doc
