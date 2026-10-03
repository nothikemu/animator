extends Node
## In-game time. One in-game minute = 0.7 real seconds at 1x (a Wake-to-Hush day is ~14 min).
## Phases: wake 06-12, bloom 12-18, dimming 18-22, hush 22-02, night 02-06 (asleep).
## The Breath: every third day the Deep exhales (gas rises); the day after, it inhales.

signal advanced(minutes: float)          ## every frame the clock moves
signal minute_tick(minute: int)          ## once per in-game minute
signal hour_changed(hour: int)
signal phase_changed(phase: String)
signal day_started(day: int)
signal time_skipped(minutes: float)      ## sleep / blackout fast-forward
signal exhausted()                       ## 02:00 reached while awake

const REAL_SECONDS_PER_MINUTE := 0.7
const WAKE_MINUTE := 6 * 60
const EXHAUST_MINUTE := 2 * 60
const SPEEDS := [1.0, 3.0]

var day := 1
var minute := float(WAKE_MINUTE)
var speed := 1.0
var running := false
var _pause_reasons: Dictionary = {}
var _last_minute := -1
var _last_hour := -1
var _last_phase := ""
var _exhaust_fired := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


func start(at_day := 1, at_minute := float(WAKE_MINUTE)) -> void:
	day = at_day
	minute = at_minute
	_last_minute = int(minute)
	_last_hour = hour()
	_last_phase = phase()
	_exhaust_fired = false
	running = true
	_update_globals()


func stop() -> void:
	running = false


func pause(reason: String) -> void:
	_pause_reasons[reason] = true


func resume(reason: String) -> void:
	_pause_reasons.erase(reason)


func clear_pauses() -> void:
	_pause_reasons.clear()


func is_paused() -> bool:
	return not _pause_reasons.is_empty() or not running


func set_speed(s: float) -> void:
	speed = clampf(s, 0.0, 4.0)


func _process(delta: float) -> void:
	if is_paused():
		_update_globals()
		return
	var adv := delta / REAL_SECONDS_PER_MINUTE * speed
	advance(adv)


## Moves time forward by `minutes` (normal flow). Emits ticks for every crossed minute.
func advance(minutes: float) -> void:
	if minutes <= 0.0:
		return
	minute += minutes
	advanced.emit(minutes)
	var guard := 0
	while int(minute) != _last_minute and guard < 120:
		guard += 1
		_last_minute += 1
		if _last_minute >= 1440:
			_last_minute -= 1440
			minute -= 1440.0
			day += 1
		minute_tick.emit(_last_minute)
		_check_boundaries()
	_update_globals()


func _check_boundaries() -> void:
	var h := hour()
	if h != _last_hour:
		_last_hour = h
		hour_changed.emit(h)
	var p := phase()
	if p != _last_phase:
		_last_phase = p
		phase_changed.emit(p)
	if not _exhaust_fired and int(minute) >= EXHAUST_MINUTE and int(minute) < WAKE_MINUTE:
		_exhaust_fired = true
		exhausted.emit()


## Sleep until the next morning. Emits time_skipped so the simulation can catch up.
func sleep_until_morning() -> float:
	var target_day := day + 1 if minute >= WAKE_MINUTE else day
	var skipped := (target_day - day) * 1440.0 + WAKE_MINUTE - minute
	day = target_day
	minute = float(WAKE_MINUTE)
	_last_minute = int(minute)
	_last_hour = hour()
	_last_phase = phase()
	_exhaust_fired = false
	time_skipped.emit(skipped)
	day_started.emit(day)
	phase_changed.emit(_last_phase)
	_update_globals()
	return skipped


func hour() -> int:
	return int(minute) / 60 % 24


func time_string() -> String:
	return "%02d:%02d" % [hour(), int(minute) % 60]


func phase() -> String:
	return phase_at(int(minute))


static func phase_at(m: int) -> String:
	var h := (m / 60) % 24
	if h >= 6 and h < 12:
		return "wake"
	if h >= 12 and h < 18:
		return "bloom"
	if h >= 18 and h < 22:
		return "dimming"
	if h >= 22 or h < 2:
		return "hush"
	return "night"


func breath() -> String:
	return breath_on(day)


static func breath_on(d: int) -> String:
	if d % 3 == 0:
		return "exhale"
	if d % 3 == 1 and d > 1:
		return "inhale"
	return "still"


func is_market_day() -> bool:
	return day % 3 == 2


## Brightness of the grove's bioluminescence over the day (0.35 night .. 1.0 bloom).
func glow_level() -> float:
	var m := fmod(minute, 1440.0)
	var t := (m - 14.0 * 60.0) / 1440.0 * TAU
	return clampf(0.68 + 0.32 * cos(t), 0.35, 1.0)


## 0 = full day lighting, 1 = deep Hush. Lamps light up as this rises.
func darkness() -> float:
	var m := fmod(minute, 1440.0)
	if m >= 18.0 * 60.0:
		return clampf((m - 18.0 * 60.0) / 240.0, 0.0, 1.0)
	if m < 6.0 * 60.0:
		return 1.0
	if m < 8.0 * 60.0:
		return clampf(1.0 - (m - 6.0 * 60.0) / 120.0, 0.0, 1.0)
	return 0.0


func _update_globals() -> void:
	RenderingServer.global_shader_parameter_set("world_time", Time.get_ticks_msec() / 1000.0)
	RenderingServer.global_shader_parameter_set("glow_level", glow_level())


func to_dict() -> Dictionary:
	return {"day": day, "minute": minute, "speed": speed}


func load_dict(d: Dictionary) -> void:
	start(maxi(1, int(d.get("day", 1))), clampf(float(d.get("minute", WAKE_MINUTE)), 0.0, 1439.0))
	speed = 1.0
