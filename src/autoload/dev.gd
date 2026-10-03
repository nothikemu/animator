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


func arg(name: String, default := "") -> String:
	return String(capture_args.get(name, default))


func has_arg(name: String) -> bool:
	return capture_args.has(name)
