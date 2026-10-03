extends Node
## Developer tools: enabled with the --dev command-line flag or in debug builds that pass
## --dev. Provides the debug overlay and console (built in src/debug/). Never active in a
## normal release run.

var enabled := false
var capture_args: Dictionary = {}        ## parsed --key=value user args (screenshots, scenarios)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg == "--dev":
			enabled = true
		elif arg.begins_with("--") and arg.contains("="):
			var eq := arg.find("=")
			capture_args[arg.substr(2, eq - 2)] = arg.substr(eq + 1)
		elif arg.begins_with("--"):
			capture_args[arg.substr(2)] = "true"


## --capture=<png> [--frames=N] [--keep] [--ui=<panel>]: screenshot after N frames, in any scene.
var _capture_frames := -1


func _process(_delta: float) -> void:
	if _capture_frames < 0:
		if has_arg("capture") and _capture_frames == -1:
			_capture_frames = int(arg("frames", "45"))
			if has_arg("ui"):
				get_tree().create_timer(0.5).timeout.connect(func() -> void:
					var parts := arg("ui").split(":", true, 1)
					Events.ui_open.emit(StringName(parts[0]), {"arg": parts[1] if parts.size() > 1 else ""}))
		return
	_capture_frames -= 1
	if _capture_frames == 0:
		_capture_frames = -2
		_capture()


func _capture() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(arg("capture"))
	Log.info("capture", "saved %s (%dx%d)" % [arg("capture"), img.get_width(), img.get_height()])
	if not has_arg("keep"):
		get_tree().quit()


func arg(name: String, default := "") -> String:
	return String(capture_args.get(name, default))


func has_arg(name: String) -> bool:
	return capture_args.has(name)
