class_name MachineState
extends RefCounted
## Runtime state of one placed machine. Behaviour comes from its definition in machines.json.

var id: int = 0
var def_id: String = ""
var cell := Vector2i.ZERO          ## top-left cell of the footprint
var size := Vector2i.ONE
var enabled := true
var health := 1.0
var fixed := false                 ## story machines cannot be deconstructed

# Consumables / buffers
var fuel_minutes := 0.0            ## burn time remaining
var fuel_items: Dictionary = {}    ## item id -> count waiting in the hopper
var filter_minutes := 0.0
var waste := 0.0                   ## output buffer (e.g. sludge)
var stored := 0.0                  ## battery charge (pw·min) or tank water
var basin := 0.0                   ## well basin water available to the player
var manual_timer := 0.0            ## minutes of manual cranking remaining
var progress := 0.0                ## generic process progress (compost)
var story: Dictionary = {}         ## story-specific state (e.g. installed parts)

# Last tick results (not saved; recomputed every tick)
var status: StringName = &"idle"
var efficiency := 0.0
var power_sat := 0.0
var water_sat := 0.0
var power_out := 0.0
var power_in := 0.0
var water_moved := 0.0
var light := 0.0
var noise := 0.0
var on_power_net := false
var on_water_net := false


func cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dy in size.y:
		for dx in size.x:
			out.append(cell + Vector2i(dx, dy))
	return out


func contains(c: Vector2i) -> bool:
	return c.x >= cell.x and c.y >= cell.y and c.x < cell.x + size.x and c.y < cell.y + size.y


func center() -> Vector2:
	return Vector2(cell.x + size.x * 0.5, cell.y + size.y * 0.5)


func to_dict() -> Dictionary:
	return {
		"id": id, "def": def_id, "x": cell.x, "y": cell.y, "w": size.x, "h": size.y,
		"enabled": enabled, "health": health, "fixed": fixed,
		"fuel_minutes": fuel_minutes, "fuel_items": fuel_items.duplicate(),
		"filter_minutes": filter_minutes, "waste": waste, "stored": stored, "basin": basin,
		"manual_timer": manual_timer, "progress": progress, "story": story.duplicate(true),
	}


static func from_dict(d: Dictionary) -> MachineState:
	var m := MachineState.new()
	m.id = int(d.get("id", 0))
	m.def_id = String(d.get("def", ""))
	m.cell = Vector2i(int(d.get("x", 0)), int(d.get("y", 0)))
	m.size = Vector2i(maxi(1, int(d.get("w", 1))), maxi(1, int(d.get("h", 1))))
	m.enabled = bool(d.get("enabled", true))
	m.health = clampf(float(d.get("health", 1.0)), 0.0, 1.0)
	m.fixed = bool(d.get("fixed", false))
	m.fuel_minutes = maxf(0.0, float(d.get("fuel_minutes", 0.0)))
	var fi: Variant = d.get("fuel_items", {})
	if fi is Dictionary:
		for k in fi:
			m.fuel_items[String(k)] = maxi(0, int(fi[k]))
	m.filter_minutes = maxf(0.0, float(d.get("filter_minutes", 0.0)))
	m.waste = maxf(0.0, float(d.get("waste", 0.0)))
	m.stored = maxf(0.0, float(d.get("stored", 0.0)))
	m.basin = maxf(0.0, float(d.get("basin", 0.0)))
	m.manual_timer = maxf(0.0, float(d.get("manual_timer", 0.0)))
	m.progress = maxf(0.0, float(d.get("progress", 0.0)))
	var st: Variant = d.get("story", {})
	if st is Dictionary:
		m.story = st.duplicate(true)
	return m
