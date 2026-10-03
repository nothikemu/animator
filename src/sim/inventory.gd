class_name Inventory
extends RefCounted
## Slot inventory. Items are content IDs; stacks are capped by the item's `stack` value.

signal changed

const DEFAULT_SLOTS := 24

var slots: Array = []        ## each slot: {} (empty) or {"id": String, "n": int}
var stack_limits: Dictionary = {}  ## item id -> max stack (from Content)


func _init(slot_count: int = DEFAULT_SLOTS) -> void:
	slots.resize(slot_count)
	for i in slot_count:
		slots[i] = {}


func count(id: String) -> int:
	var n := 0
	for s in slots:
		if s.get("id", "") == id:
			n += int(s.n)
	return n


func has(id: String, n: int = 1) -> bool:
	return count(id) >= n


func has_all(costs: Dictionary) -> bool:
	for id in costs:
		if count(id) < int(costs[id]):
			return false
	return true


func _limit(id: String) -> int:
	return int(stack_limits.get(id, 99))


## Adds up to n items; returns how many did NOT fit.
func add(id: String, n: int = 1) -> int:
	if n <= 0 or id.is_empty():
		return 0
	var left := n
	var lim := _limit(id)
	for s in slots:
		if left <= 0:
			break
		if s.get("id", "") == id and int(s.n) < lim:
			var put := mini(left, lim - int(s.n))
			s.n = int(s.n) + put
			left -= put
	for i in slots.size():
		if left <= 0:
			break
		if slots[i].is_empty():
			var put := mini(left, lim)
			slots[i] = {"id": id, "n": put}
			left -= put
	if left != n:
		changed.emit()
	return left


func room_for(id: String) -> int:
	var lim := _limit(id)
	var room := 0
	for s in slots:
		if s.is_empty():
			room += lim
		elif s.get("id", "") == id:
			room += lim - int(s.n)
	return room


## Removes n items if available; returns true on success (all-or-nothing).
func remove(id: String, n: int = 1) -> bool:
	if count(id) < n:
		return false
	var left := n
	for i in range(slots.size() - 1, -1, -1):
		var s: Dictionary = slots[i]
		if left <= 0:
			break
		if s.get("id", "") == id:
			var take := mini(left, int(s.n))
			s.n = int(s.n) - take
			left -= take
			if int(s.n) <= 0:
				slots[i] = {}
	changed.emit()
	return true


func remove_all(costs: Dictionary) -> bool:
	if not has_all(costs):
		return false
	for id in costs:
		remove(id, int(costs[id]))
	return true


func to_array() -> Array:
	return slots.duplicate(true)


func load_array(arr: Array, valid_ids: Dictionary = {}) -> void:
	for i in slots.size():
		slots[i] = {}
	for i in mini(arr.size(), slots.size()):
		var s: Variant = arr[i]
		if s is Dictionary and s.has("id"):
			var id := String(s.id)
			if not valid_ids.is_empty() and not valid_ids.has(id):
				push_warning("inventory: dropping unknown item '%s'" % id)
				continue
			var n := clampi(int(s.get("n", 1)), 0, _limit(id))
			if n > 0:
				slots[i] = {"id": id, "n": n}
	changed.emit()
