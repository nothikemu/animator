extends Node
## Player settings: graphics, audio, accessibility and input bindings.
## Gameplay never reads raw keys; it reads the named actions defined here.

const PATH := "user://settings.cfg"
const BUSES := ["Music", "Ambience", "SFX", "UI", "Voice"]

## Default bindings. Keyboard/mouse and gamepad are designed together.
## Entry formats: ["key", KEY_*], ["mouse", MOUSE_BUTTON_*], ["joy", JOY_BUTTON_*], ["axis", JOY_AXIS_*, sign]
const DEFAULT_BINDINGS := {
	"move_up": [["key", KEY_W], ["key", KEY_UP], ["axis", JOY_AXIS_LEFT_Y, -1.0]],
	"move_down": [["key", KEY_S], ["key", KEY_DOWN], ["axis", JOY_AXIS_LEFT_Y, 1.0]],
	"move_left": [["key", KEY_A], ["key", KEY_LEFT], ["axis", JOY_AXIS_LEFT_X, -1.0]],
	"move_right": [["key", KEY_D], ["key", KEY_RIGHT], ["axis", JOY_AXIS_LEFT_X, 1.0]],
	"interact": [["key", KEY_E], ["joy", JOY_BUTTON_A]],
	"context": [["key", KEY_F], ["joy", JOY_BUTTON_X]],
	"confirm": [["key", KEY_SPACE], ["key", KEY_ENTER], ["joy", JOY_BUTTON_A]],
	"cancel": [["key", KEY_ESCAPE], ["joy", JOY_BUTTON_B]],
	"menu": [["key", KEY_ESCAPE], ["joy", JOY_BUTTON_START]],
	"inventory": [["key", KEY_TAB], ["joy", JOY_BUTTON_Y]],
	"tool_next": [["key", KEY_Q], ["joy", JOY_BUTTON_RIGHT_SHOULDER]],
	"tool_prev": [["joy", JOY_BUTTON_LEFT_SHOULDER]],
	"primary": [["mouse", MOUSE_BUTTON_LEFT], ["axis", JOY_AXIS_TRIGGER_RIGHT, 1.0]],
	"secondary": [["mouse", MOUSE_BUTTON_RIGHT], ["axis", JOY_AXIS_TRIGGER_LEFT, 1.0]],
	"cut_view": [["key", KEY_C], ["joy", JOY_BUTTON_BACK]],
	"journal": [["key", KEY_J], ["joy", JOY_BUTTON_DPAD_UP]],
	"map": [["key", KEY_M], ["joy", JOY_BUTTON_DPAD_DOWN]],
	"overlay_next": [["key", KEY_V], ["joy", JOY_BUTTON_DPAD_RIGHT]],
	"build_menu": [["key", KEY_B], ["joy", JOY_BUTTON_DPAD_LEFT]],
	"time_pause": [["key", KEY_P], ["joy", JOY_BUTTON_LEFT_STICK]],
	"time_speed": [["key", KEY_T], ["joy", JOY_BUTTON_RIGHT_STICK]],
	"zoom_in": [["mouse", MOUSE_BUTTON_WHEEL_UP], ["axis", JOY_AXIS_RIGHT_Y, -1.0]],
	"zoom_out": [["mouse", MOUSE_BUTTON_WHEEL_DOWN], ["axis", JOY_AXIS_RIGHT_Y, 1.0]],
	"inspect": [["mouse", MOUSE_BUTTON_MIDDLE]],
	"dev_overlay": [["key", KEY_F3]],
	"dev_console": [["key", KEY_F1]],
}

## Actions the player may remap in the Controls menu (order = display order).
const REMAPPABLE := ["move_up", "move_down", "move_left", "move_right", "interact", "context",
	"confirm", "cancel", "menu", "inventory", "tool_next", "tool_prev", "primary", "secondary",
	"cut_view", "journal", "map", "overlay_next", "build_menu", "time_pause", "time_speed"]

const PRESETS := {
	"low": {"shadows": false, "dof": false, "glow": false, "ssao": false, "volumetric": false,
		"particles": 0.35, "render_scale": 0.75, "ambient_fx": false, "post": false},
	"medium": {"shadows": true, "dof": true, "glow": true, "ssao": false, "volumetric": false,
		"particles": 0.65, "render_scale": 1.0, "ambient_fx": true, "post": true},
	"high": {"shadows": true, "dof": true, "glow": true, "ssao": true, "volumetric": false,
		"particles": 1.0, "render_scale": 1.0, "ambient_fx": true, "post": true},
	"ultra": {"shadows": true, "dof": true, "glow": true, "ssao": true, "volumetric": true,
		"particles": 1.0, "render_scale": 1.0, "ambient_fx": true, "post": true},
}

var graphics := {
	"preset": "high", "window_mode": "windowed", "vsync": true,
	"shadows": true, "dof": true, "glow": true, "ssao": true, "volumetric": false,
	"particles": 1.0, "render_scale": 1.0, "ambient_fx": true, "post": true,
}
var audio := {"Master": 0.85, "Music": 0.7, "Ambience": 0.8, "SFX": 0.85, "UI": 0.7, "Voice": 0.8}
var access := {
	"screen_shake": true, "shake_scale": 0.6, "flash": 0.7, "text_speed": 1.0,
	"font_scale": 1.0, "readable_font": false, "high_contrast": false, "captions": true,
}
var bindings: Dictionary = {}       ## action -> Array of serialized events

## Last input device class used: "kb" or "pad". UI prompts adapt to it.
var last_device := "kb"
signal device_changed(kind: String)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	bindings = _default_bindings_serialized()
	load_settings()
	apply_bindings()
	apply_audio()
	apply_window()


func _input(event: InputEvent) -> void:
	var kind := last_device
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.4):
		kind = "pad"
	elif event is InputEventKey or event is InputEventMouseButton:
		kind = "kb"
	if kind != last_device:
		last_device = kind
		device_changed.emit(kind)


# --- Persistence ---------------------------------------------------------------

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for k in graphics:
		graphics[k] = cfg.get_value("graphics", k, graphics[k])
	for k in audio:
		audio[k] = clampf(float(cfg.get_value("audio", k, audio[k])), 0.0, 1.0)
	for k in access:
		access[k] = cfg.get_value("access", k, access[k])
	access["font_scale"] = clampf(float(access["font_scale"]), 0.75, 1.75)
	access["text_speed"] = clampf(float(access["text_speed"]), 0.25, 4.0)
	if cfg.has_section("controls"):
		for action in cfg.get_section_keys("controls"):
			if DEFAULT_BINDINGS.has(action):
				var evs: Variant = cfg.get_value("controls", action, [])
				if evs is Array:
					bindings[action] = evs


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in graphics:
		cfg.set_value("graphics", k, graphics[k])
	for k in audio:
		cfg.set_value("audio", k, audio[k])
	for k in access:
		cfg.set_value("access", k, access[k])
	for action in bindings:
		cfg.set_value("controls", action, bindings[action])
	var err := cfg.save(PATH)
	if err != OK:
		Log.error("settings", "could not save settings (%s)" % error_string(err))


# --- Input -----------------------------------------------------------------------

func _default_bindings_serialized() -> Dictionary:
	var out := {}
	for action in DEFAULT_BINDINGS:
		out[action] = DEFAULT_BINDINGS[action].duplicate(true)
	return out


func reset_bindings() -> void:
	bindings = _default_bindings_serialized()
	apply_bindings()
	save_settings()


func apply_bindings() -> void:
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.35)
		InputMap.action_erase_events(action)
		for spec in bindings[action]:
			var ev := deserialize_event(spec)
			if ev != null:
				InputMap.action_add_event(action, ev)
	# Make built-in UI navigation work with the left stick as well as the d-pad.
	_add_if_missing("ui_up", deserialize_event(["axis", JOY_AXIS_LEFT_Y, -1.0]))
	_add_if_missing("ui_down", deserialize_event(["axis", JOY_AXIS_LEFT_Y, 1.0]))
	_add_if_missing("ui_left", deserialize_event(["axis", JOY_AXIS_LEFT_X, -1.0]))
	_add_if_missing("ui_right", deserialize_event(["axis", JOY_AXIS_LEFT_X, 1.0]))


func _add_if_missing(action: String, ev: InputEvent) -> void:
	if ev == null or not InputMap.has_action(action):
		return
	for existing in InputMap.action_get_events(action):
		if existing.is_match(ev):
			return
	InputMap.action_add_event(action, ev)


## Replaces the binding of `action` for the given device class ("kb" or "pad").
func rebind(action: String, event: InputEvent) -> void:
	var spec := serialize_event(event)
	if spec.is_empty():
		return
	var is_pad: bool = spec[0] == "joy" or spec[0] == "axis"
	var kept: Array = []
	for s in bindings.get(action, []):
		var s_pad: bool = s[0] == "joy" or s[0] == "axis"
		if s_pad != is_pad:
			kept.append(s)
	kept.push_front(spec)
	bindings[action] = kept
	apply_bindings()
	save_settings()


static func serialize_event(ev: InputEvent) -> Array:
	if ev is InputEventKey:
		var code: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
		return ["key", code]
	if ev is InputEventMouseButton:
		return ["mouse", ev.button_index]
	if ev is InputEventJoypadButton:
		return ["joy", ev.button_index]
	if ev is InputEventJoypadMotion and absf(ev.axis_value) > 0.5:
		return ["axis", ev.axis, signf(ev.axis_value)]
	return []


static func deserialize_event(spec: Variant) -> InputEvent:
	if not spec is Array or (spec as Array).size() < 2:
		return null
	match String(spec[0]):
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = int(spec[1]) as Key
			return k
		"mouse":
			var m := InputEventMouseButton.new()
			m.button_index = int(spec[1]) as MouseButton
			return m
		"joy":
			var j := InputEventJoypadButton.new()
			j.button_index = int(spec[1]) as JoyButton
			j.device = -1
			return j
		"axis":
			var a := InputEventJoypadMotion.new()
			a.axis = int(spec[1]) as JoyAxis
			a.axis_value = float(spec[2]) if spec.size() > 2 else 1.0
			a.device = -1
			return a
	return null


## Human-readable label for the first binding of an action on the current device.
func binding_label(action: String, device := "") -> String:
	var want_pad := (device if device != "" else last_device) == "pad"
	for spec in bindings.get(action, []):
		var is_pad: bool = spec[0] == "joy" or spec[0] == "axis"
		if is_pad == want_pad:
			return spec_label(spec)
	var list: Array = bindings.get(action, [])
	return spec_label(list[0]) if not list.is_empty() else "—"


static func spec_label(spec: Array) -> String:
	match String(spec[0]):
		"key":
			return OS.get_keycode_string(int(spec[1]))
		"mouse":
			match int(spec[1]):
				MOUSE_BUTTON_LEFT: return "LMB"
				MOUSE_BUTTON_RIGHT: return "RMB"
				MOUSE_BUTTON_MIDDLE: return "MMB"
				MOUSE_BUTTON_WHEEL_UP: return "Wheel Up"
				MOUSE_BUTTON_WHEEL_DOWN: return "Wheel Down"
			return "Mouse %d" % int(spec[1])
		"joy":
			const NAMES := {0: "A", 1: "B", 2: "X", 3: "Y", 4: "Back", 6: "Start", 7: "L3", 8: "R3",
				9: "LB", 10: "RB", 11: "D-Up", 12: "D-Down", 13: "D-Left", 14: "D-Right"}
			return NAMES.get(int(spec[1]), "Pad %d" % int(spec[1]))
		"axis":
			const AX := {0: "L-Stick X", 1: "L-Stick Y", 2: "R-Stick X", 3: "R-Stick Y", 4: "LT", 5: "RT"}
			var sgn := "+" if float(spec[2]) > 0 else "−"
			var name: String = AX.get(int(spec[1]), "Axis %d" % int(spec[1]))
			return name if int(spec[1]) >= 4 else "%s%s" % [name, sgn]
	return "?"


# --- Audio -------------------------------------------------------------------------

func _ensure_buses() -> void:
	for bus_name in BUSES:
		if AudioServer.get_bus_index(bus_name) == -1:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")
	# The music bus carries a low-pass + soft distortion used for crisis states.
	var music := AudioServer.get_bus_index("Music")
	if AudioServer.get_bus_effect_count(music) == 0:
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(music, lp)
		var dist := AudioEffectDistortion.new()
		dist.mode = AudioEffectDistortion.MODE_OVERDRIVE
		dist.drive = 0.0
		dist.post_gain = 0.0
		AudioServer.add_bus_effect(music, dist)
		AudioServer.set_bus_effect_enabled(music, 1, false)


func apply_audio() -> void:
	for bus_name in audio:
		var idx := AudioServer.get_bus_index(bus_name)
		if idx == -1:
			continue
		var v: float = audio[bus_name]
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(idx, v <= 0.001)


func set_volume(bus_name: String, value: float) -> void:
	audio[bus_name] = clampf(value, 0.0, 1.0)
	apply_audio()
	settings_changed_emit("audio")


# --- Graphics ----------------------------------------------------------------------

func apply_preset(preset: String) -> void:
	if not PRESETS.has(preset):
		return
	graphics["preset"] = preset
	for k in PRESETS[preset]:
		graphics[k] = PRESETS[preset][k]
	apply_window()
	settings_changed_emit("graphics")


func set_graphics(key: String, value: Variant) -> void:
	graphics[key] = value
	graphics["preset"] = "custom"
	apply_window()
	settings_changed_emit("graphics")


func apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var win := get_window()
	match String(graphics.get("window_mode", "windowed")):
		"fullscreen":
			win.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
		"borderless":
			win.mode = Window.MODE_FULLSCREEN
		_:
			if win.mode != Window.MODE_WINDOWED:
				win.mode = Window.MODE_WINDOWED
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if graphics.get("vsync", true) else DisplayServer.VSYNC_DISABLED)
	var vp := get_viewport()
	vp.scaling_3d_scale = clampf(float(graphics.get("render_scale", 1.0)), 0.5, 1.0)


# --- Accessibility -------------------------------------------------------------

func set_access(key: String, value: Variant) -> void:
	access[key] = value
	settings_changed_emit("access")


func shake_multiplier() -> float:
	return float(access["shake_scale"]) if access["screen_shake"] else 0.0


func settings_changed_emit(section: String) -> void:
	Events.settings_changed.emit(StringName(section))
