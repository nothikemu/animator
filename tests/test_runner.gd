extends Node
## Headless test runner:  godot --headless --path . res://tests/test_runner.tscn
## Runs every tests/suites/test_*.gd, reports failures (including engine/script errors
## raised while a test ran) and exits with a non-zero code if anything failed.

class ErrorCounter:
	extends Logger
	var count := 0
	var messages: PackedStringArray = []
	var mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		mutex.lock()
		count += 1
		messages.append("%s (%s:%d in %s) %s" % [code, file.get_file(), line, function, rationale])
		mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass


var counter := ErrorCounter.new()


func _ready() -> void:
	Log.quiet = true
	OS.add_logger(counter)
	await get_tree().process_frame
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.substr(7)
	var total := 0
	var failed := 0
	var lines: PackedStringArray = []
	var dir := DirAccess.open("res://tests/suites")
	var files := dir.get_files()
	files.sort()
	var t0 := Time.get_ticks_msec()
	for f in files:
		if not f.begins_with("test_") or not f.ends_with(".gd"):
			continue
		if only != "" and not f.contains(only):
			continue
		var script: GDScript = load("res://tests/suites/" + f)
		if script == null or not script.can_instantiate():
			lines.append("LOAD FAIL %s" % f)
			failed += 1
			continue
		var suite: TestCase = script.new()
		for m in suite.get_method_list():
			var name: String = m.name
			if not name.begins_with("test_"):
				continue
			total += 1
			suite.current = "%s::%s" % [f.get_basename(), name]
			var before_fail := suite.failures.size()
			var before_err := counter.count
			suite.before_each()
			var ts := Time.get_ticks_usec()
			suite.call(name)
			var ms := (Time.get_ticks_usec() - ts) / 1000.0
			var errs := counter.count - before_err
			if errs > 0:
				for k in range(counter.messages.size() - errs, counter.messages.size()):
					suite.failures.append("%s: engine error: %s" % [suite.current, counter.messages[k]])
			if suite.failures.size() > before_fail:
				failed += 1
				lines.append("FAIL %s (%.1f ms)" % [suite.current, ms])
				for k in range(before_fail, suite.failures.size()):
					var msg := suite.failures[k]
					if msg.length() > 400:
						msg = msg.substr(0, 400) + " …[truncated]"
					lines.append("     - " + msg)
			else:
				lines.append("ok   %s (%.1f ms)" % [suite.current, ms])
	for l in lines:
		print(l)
	print("\n%d tests, %d failed, %.1f s" % [total, failed, (Time.get_ticks_msec() - t0) / 1000.0])
	if Content.errors.size() > 0:
		print("CONTENT ERRORS:")
		for e in Content.errors:
			print("  " + e)
		failed += 1
	get_tree().quit(1 if failed > 0 else 0)
