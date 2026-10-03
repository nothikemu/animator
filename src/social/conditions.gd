class_name Conditions
extends RefCounted
## Tiny rule language shared by dialogue, threads (quests), event cards and NPC schedules.
##
## A rule is an array of clause strings that must ALL hold. Clause grammar:
##     [!]kind[:arg][op value]
## Examples:
##     "flag:valve_open"            truthy flag
##     "!met:barnaby"               negation
##     "trust:barnaby>=20"          relationship axis
##     "phase:hush|dimming"         membership (phase, place, breath, view)
##     "thread:dry_well>=2"         quest stage
##     "mem:hesper:moss_gassed"     NPC remembers something
##     "pollution>0.3"              world fact
## A context object resolves keys via `value(key: String) -> Variant`.
## The match score is the number of clauses (Ruskin's "most specific rule wins").

const MEMBERSHIP := ["phase", "place", "breath", "view", "area", "weekday"]
const OPS := [">=", "<=", "!=", "=", ">", "<"]

static var _cache: Dictionary = {}


## Parses a clause into {neg, key, op, values} (memoised).
static func parse(clause: String) -> Dictionary:
	if _cache.has(clause):
		return _cache[clause]
	var c := clause.strip_edges()
	var neg := false
	if c.begins_with("!"):
		neg = true
		c = c.substr(1)
	var op := ""
	var rhs := ""
	for o in OPS:
		var at := c.find(o)
		if at > 0:
			op = o
			rhs = c.substr(at + o.length()).strip_edges()
			c = c.substr(0, at)
			break
	var kind := c
	var arg := ""
	var colon := c.find(":")
	if colon >= 0:
		kind = c.substr(0, colon)
		arg = c.substr(colon + 1)
	var out := {"neg": neg, "key": kind, "op": op, "values": []}
	if MEMBERSHIP.has(kind) and op == "":
		out.op = "in"
		out.values = Array(arg.split("|"))
	else:
		if not arg.is_empty():
			out.key = "%s.%s" % [kind, arg]
		if op != "":
			out.values = Array(rhs.split("|"))
	_cache[clause] = out
	return out


## Returns true if every clause holds.
static func check(clauses: Variant, ctx: Object) -> bool:
	return score(clauses, ctx) >= 0


## Returns -1 if any clause fails, otherwise the number of clauses (specificity).
static func score(clauses: Variant, ctx: Object) -> int:
	if clauses == null:
		return 0
	if clauses is String:
		clauses = [clauses]
	var n := 0
	for clause in clauses:
		if not eval_clause(String(clause), ctx):
			return -1
		n += 1
	return n


static func eval_clause(clause: String, ctx: Object) -> bool:
	var p := parse(clause)
	var v: Variant = ctx.value(p.key) if p.op != "in" else ctx.value(p.key)
	var result := false
	match String(p.op):
		"":
			result = _truthy(v)
		"in":
			result = p.values.has(str(v))
		"=":
			result = _eq_any(v, p.values)
		"!=":
			result = not _eq_any(v, p.values)
		_:
			var a := _num(v)
			var b := _num(p.values[0])
			match String(p.op):
				">=": result = a >= b
				"<=": result = a <= b
				">": result = a > b
				"<": result = a < b
	return result != bool(p.neg)


static func _truthy(v: Variant) -> bool:
	if v == null:
		return false
	match typeof(v):
		TYPE_BOOL: return v
		TYPE_INT, TYPE_FLOAT: return v != 0
		TYPE_STRING, TYPE_STRING_NAME: return not String(v).is_empty() and String(v) != "false"
		TYPE_ARRAY, TYPE_DICTIONARY: return not v.is_empty()
	return true


static func _eq_any(v: Variant, values: Array) -> bool:
	for want in values:
		var s := String(want)
		if typeof(v) in [TYPE_INT, TYPE_FLOAT] and s.is_valid_float():
			if is_equal_approx(float(v), float(s)):
				return true
		elif typeof(v) == TYPE_BOOL:
			if (s == "true") == v:
				return true
		elif str(v) == s:
			return true
	return false


static func _num(v: Variant) -> float:
	match typeof(v):
		TYPE_INT, TYPE_FLOAT: return float(v)
		TYPE_BOOL: return 1.0 if v else 0.0
		TYPE_STRING, TYPE_STRING_NAME:
			var s := String(v)
			return float(s) if s.is_valid_float() else 0.0
	return 0.0


## Simple dictionary-backed context for tests and offline evaluation.
class DictContext:
	extends RefCounted
	var facts: Dictionary

	func _init(f: Dictionary = {}) -> void:
		facts = f

	func value(key: String) -> Variant:
		return facts.get(key, null)
