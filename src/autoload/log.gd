extends Node
## Structured logging. Every message carries a context tag so problems in data or
## simulation can be traced to a file/system. Keeps a ring buffer for the debug overlay.

const MAX_LINES := 200

var lines: PackedStringArray = []
var error_count := 0
var warning_count := 0
## When true (tests), info lines are not printed to stdout.
var quiet := false


func info(ctx: String, msg: String) -> void:
	_store("I", ctx, msg)
	if not quiet:
		print("[%s] %s" % [ctx, msg])


func warn(ctx: String, msg: String) -> void:
	warning_count += 1
	_store("W", ctx, msg)
	push_warning("[%s] %s" % [ctx, msg])


func error(ctx: String, msg: String) -> void:
	error_count += 1
	_store("E", ctx, msg)
	push_error("[%s] %s" % [ctx, msg])


func recent(count: int = 12) -> PackedStringArray:
	var start := maxi(0, lines.size() - count)
	return lines.slice(start)


func _store(level: String, ctx: String, msg: String) -> void:
	lines.append("%s %s: %s" % [level, ctx, msg])
	if lines.size() > MAX_LINES:
		lines = lines.slice(lines.size() - MAX_LINES)
