class_name TestCase
extends RefCounted
## Base class for test suites. Methods named test_* are run by tests/test_runner.gd.

var failures: PackedStringArray = []
var current := ""


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append("%s: %s" % [current, msg])


func eq(a: Variant, b: Variant, msg: String) -> void:
	if typeof(a) != typeof(b) and not (typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]):
		failures.append("%s: %s (type %s vs %s: %s vs %s)" % [current, msg, type_string(typeof(a)), type_string(typeof(b)), a, b])
	elif a != b:
		failures.append("%s: %s (got %s, expected %s)" % [current, msg, a, b])


func near(a: float, b: float, eps: float, msg: String) -> void:
	if absf(a - b) > eps:
		failures.append("%s: %s (got %.5f, expected %.5f ± %.5f)" % [current, msg, a, b, eps])


func before_each() -> void:
	pass


## Builds a fresh content-backed undercroft for integration-style tests.
static func wick_grid() -> UcGrid:
	return WickBuilder.build_grid(Content.undercroft)
