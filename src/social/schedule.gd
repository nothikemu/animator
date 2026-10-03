class_name Schedule
extends RefCounted
## Resolves where a resident should be and what they are doing at a given time.
## Schedules are lists of blocks; later blocks with satisfied conditions override earlier
## ones (so data can express "normally X, but on exhale days Y").
##   {"from": "06:00", "to": "09:30", "at": "annex", "do": "tea", "when": ["..."], "why": "..."}


static func to_minutes(hhmm: String) -> int:
	var parts := hhmm.split(":")
	if parts.size() != 2:
		return 0
	return int(parts[0]) * 60 + int(parts[1])


static func in_block(block: Dictionary, minute: int) -> bool:
	var a := to_minutes(String(block.get("from", "00:00")))
	var b := to_minutes(String(block.get("to", "24:00")))
	var m := minute % 1440
	if a <= b:
		return m >= a and m < b
	return m >= a or m < b  # wraps past midnight


## Returns the active block, or a default "home/rest" block when nothing matches.
static func resolve(schedule: Array, minute: int, ctx: Object) -> Dictionary:
	var chosen := {}
	for block in schedule:
		if not block is Dictionary:
			continue
		if not in_block(block, minute):
			continue
		if block.has("when") and ctx != null and not Conditions.check(block.when, ctx):
			continue
		chosen = block
	if chosen.is_empty():
		return {"at": "home", "do": "rest", "why": "nothing else to do"}
	return chosen
