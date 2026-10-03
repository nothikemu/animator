extends Node3D
## Machines that stand on the surface (the town well, sprinklers, anything placed in the
## lane from the cut view) drawn in the 3D town as billboards on the slice row, with the
## same status frames as the cross-section and a light where they make one.

var _nodes: Dictionary = {}              ## machine id -> {sprite, light, cells}
var _meta: Dictionary = {}
var _t := 0.0


func _ready() -> void:
	var d: Variant = Content.read_json("res://assets/textures/machines/machines.json")
	_meta = d if d is Dictionary else {}
	Events.sim_topology_changed.connect(sync)
	Sim.ticked.connect(sync)
	sync()


func _area() -> AreaMap:
	var g := get_tree().current_scene
	return g.get("area") as AreaMap if g else null


func sync() -> void:
	if Sim.machines == null or Sim.grid == null:
		return
	var area := _area()
	var surface_row := Sim.grid.ground_y - 1
	var z := float(Sim.slice_z) + 0.5
	for id: int in _nodes.keys():
		if not Sim.machines.machines.has(id):
			var e: Dictionary = _nodes[id]
			(e.sprite as Node).queue_free()
			if e.light:
				(e.light as Node).queue_free()
			if area:
				for x: int in e.cells:
					area.blocked[Sim.slice_z * area.w + x] = 0
			_nodes.erase(id)
	for id: int in Sim.machines.machines:
		var m: MachineState = Sim.machines.machines[id]
		if m.cell.y + m.size.y - 1 != surface_row or _nodes.has(id):
			continue
		var s := UndercroftView.make_machine_sprite(m.def_id, _meta, true)
		if s == null:
			continue
		var x := m.cell.x + m.size.x * 0.5
		var y := area.world_y(m.cell.x, Sim.slice_z) if area else 0.0
		s.position = Vector3(x, y, z)
		s.name = "Surface_%s_%d" % [m.def_id, id]
		add_child(s)
		var shadow := Player.make_blob_shadow(0.35 * m.size.x)
		shadow.position = Vector3(0, 0.02, 0)
		s.add_child(shadow)
		var cells: Array[int] = []
		for dx in m.size.x:
			cells.append(m.cell.x + dx)
			if area and m.def_id != "old_well":
				area.blocked[Sim.slice_z * area.w + m.cell.x + dx] = 1
		var light: OmniLight3D = null
		var d: Dictionary = Content.machine(m.def_id)
		if d.has("light"):
			light = OmniLight3D.new()
			light.light_color = Content.color(String(d.light.get("color", "amber")), Color(1.0, 0.76, 0.42))
			light.omni_range = float(d.light.get("range", 5.0))
			light.light_energy = 0.0
			light.position = Vector3(x, y + 1.6, z + 0.3)
			light.layers = 1
			add_child(light)
		_nodes[id] = {"sprite": s, "light": light, "cells": cells, "run": false, "broken": false}
	for id: int in _nodes:
		var m: MachineState = Sim.machines.machines[id]
		var e: Dictionary = _nodes[id]
		e.run = m.status == &"ok" or m.efficiency > 0.05 or m.manual_timer > 0.0
		e.broken = m.health <= 0.0 or m.status == &"broken"
		if e.light:
			var d: Dictionary = Content.machine(m.def_id)
			(e.light as OmniLight3D).light_energy = float(d.light.get("energy", 1.0)) * m.light if e.run else 0.0


func _process(delta: float) -> void:
	_t += delta
	var step := int(_t * 7.0)
	for id: int in _nodes:
		var e: Dictionary = _nodes[id]
		var f := 4 if e.broken else (1 + (step + id) % 3 if e.run else 0)
		(e.sprite as GeometryInstance3D).set_instance_shader_parameter("frame", float(f))
