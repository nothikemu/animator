class_name FarmView
extends Node3D
## Visuals for Wick's farm plots: tilled soil (darker when wet) and crop sprites per stage.
## Rebuilt per plot from Sim state on Events.crop_changed.

var _plots: Dictionary = {}              ## Vector2i -> {soil: MeshInstance3D, crop: PixelSprite3D}
var _area: AreaMap


func setup(area: AreaMap) -> void:
	_area = area
	Events.crop_changed.connect(_on_changed)
	for c in Sim.plots:
		_refresh(c)


func _exit_tree() -> void:
	if Events.crop_changed.is_connected(_on_changed):
		Events.crop_changed.disconnect(_on_changed)


func _on_changed(index: int) -> void:
	_refresh(Vector2i(index % 1000, index / 1000))


func refresh_all() -> void:
	for c in Sim.plots:
		_refresh(c)


func _refresh(cell: Vector2i) -> void:
	var p: Dictionary = Sim.plot_at(cell)
	var entry: Dictionary = _plots.get(cell, {})
	if p.is_empty():
		for n in entry.values():
			n.queue_free()
		_plots.erase(cell)
		return
	var y := _area.world_y(cell.x, cell.y) + 0.02
	var wet := maxf(float(p.get("water", 0.0)), Sim.grid.surface_moisture(cell.x)) > 0.45
	var tile := Atlas.variant("tilled_wet" if wet else "tilled", cell.x, cell.y)
	if not entry.has("soil") or entry.get("tile", "") != tile:
		if entry.has("soil"):
			entry.soil.queue_free()
		var k := MeshKit.new()
		k.box(Vector3(cell.x + 0.06, y - 0.06, cell.y + 0.06), Vector3(0.88, 0.1, 0.88), {"side": "side_earth_plain", "top": tile}, false)
		var mi := MeshInstance3D.new()
		mi.mesh = k.commit()
		mi.material_override = AreaView.terrain_material()
		add_child(mi)
		entry["soil"] = mi
		entry["tile"] = tile
	var crop := String(p.get("crop", ""))
	if crop == "":
		if entry.has("crop"):
			entry.crop.queue_free()
			entry.erase("crop")
	else:
		var def: Dictionary = Content.crop(crop)
		var tex_name := String(def.get("sprite", "crop_" + crop))
		if not entry.has("crop") or entry.get("crop_id", "") != crop:
			if entry.has("crop"):
				entry.crop.queue_free()
			var t := PixelSprite3D.load_tex("res://assets/textures/props/%s.png" % tex_name)
			var s := PixelSprite3D.new()
			var tex: Texture2D = t[0]
			s.setup(tex, t[1], Vector2i(tex.get_width() / 5, tex.get_height()), Vector2i(5, 1), {"rim_strength": 0.3, "sway": 0.02})
			s.position = Vector3(cell.x + 0.5, y + 0.04, cell.y + 0.55)
			add_child(s)
			entry["crop"] = s
			entry["crop_id"] = crop
		var frame := 4 if p.get("dead", false) else CropLogic.stage(p)
		(entry.crop as PixelSprite3D).set_frame(frame)
		var h := float(p.get("health", 1.0))
		(entry.crop as PixelSprite3D).set_tint(Color(1, 1, 1).lerp(Color(0.75, 0.7, 0.45), clampf(1.0 - h, 0.0, 0.8)))
	_plots[cell] = entry
