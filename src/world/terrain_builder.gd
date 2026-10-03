class_name TerrainBuilder
extends RefCounted
## Builds chunked terrain meshes from an AreaMap: top faces, exposed cliff sides, per-vertex
## ambient occlusion, a lake bed under water cells and a separate water surface mesh.

const CHUNK := 16
const LAKE_BED := -0.9
const WATER_Y := -0.28

## Surface material -> top tile base name.
const TOP := {
	"moss_floor": "moss_floor", "moss_deep": "moss_deep", "gravel": "gravel", "cobble": "cobble",
	"farm_soil": "farm_soil", "rock_floor": "rock_floor", "stairs": "stairs", "plank": "plank",
	"dirt": "dirt", "blackstone": "blackstone", "ash": "ash", "basalt": "basalt", "mud": "mud",
	"stone": "stone", "vent": "vent", "rock": "rock", "sand": "sand", "water": "mud",
}
## Surface material -> side (cliff) tile base name.
const SIDE := {
	"moss_floor": "side_earth", "moss_deep": "side_earth", "farm_soil": "side_earth_plain",
	"dirt": "side_earth_plain", "gravel": "side_rock", "cobble": "side_rock", "rock_floor": "side_rock",
	"stairs": "side_rock", "plank": "side_plank", "blackstone": "side_blackstone", "ash": "side_basalt",
	"basalt": "side_basalt", "mud": "side_mud", "stone": "side_rock", "vent": "side_basalt",
	"rock": "side_rock", "sand": "side_earth_plain", "water": "side_mud",
}


static func build(area: AreaMap, material: Material, water_material: Material) -> Node3D:
	var root := Node3D.new()
	root.name = "Terrain"
	for cz in range(0, area.d, CHUNK):
		for cx in range(0, area.w, CHUNK):
			var mesh := _chunk(area, cx, cz)
			if mesh == null:
				continue
			var mi := MeshInstance3D.new()
			mi.name = "Chunk_%d_%d" % [cx / CHUNK, cz / CHUNK]
			mi.mesh = mesh
			mi.material_override = material
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			root.add_child(mi)
	var water := _water(area)
	if water != null:
		var wm := MeshInstance3D.new()
		wm.name = "Water"
		wm.mesh = water
		wm.material_override = water_material
		wm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(wm)
	return root


## Cavern rock is drawn cut down to an uneven low plateau (the diorama convention: you look
## *into* a cave from above, not at its walls). Collision still treats it as full height.
const CAVE_WALL := 1.5


static func top_y(area: AreaMap, x: int, z: int) -> float:
	var h := area.h_at(x, z)
	if h == AreaMap.WATER_LEVEL:
		return LAKE_BED
	if h >= AreaMap.WALL_LEVEL and area.id != "wick":
		return CAVE_WALL + float(absi((x / 2) * 73 + (z / 2) * 151) % 5) * 0.12
	return float(h) * AreaMap.STEP


static func _chunk(area: AreaMap, cx: int, cz: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for z in range(cz, mini(cz + CHUNK, area.d)):
		for x in range(cx, mini(cx + CHUNK, area.w)):
			any = true
			_cell(st, area, x, z)
	if not any:
		return null
	st.generate_normals()
	return st.commit()


static func _cell(st: SurfaceTool, area: AreaMap, x: int, z: int) -> void:
	var y := top_y(area, x, z)
	var mat_name := area.mat_at(x, z)
	var wall := area.h_at(x, z) >= AreaMap.WALL_LEVEL
	var top_base: String = "rock" if wall else String(TOP.get(mat_name, "rock_floor"))
	var uv := Atlas.uv_rect(Atlas.variant(top_base, x, z))
	# Top face with corner AO from higher neighbours.
	var p0 := Vector3(x, y, z)
	var p1 := Vector3(x + 1, y, z)
	var p2 := Vector3(x + 1, y, z + 1)
	var p3 := Vector3(x, y, z + 1)
	var a0 := _corner_ao(area, x, z, -1, -1, y)
	var a1 := _corner_ao(area, x, z, 1, -1, y)
	var a2 := _corner_ao(area, x, z, 1, 1, y)
	var a3 := _corner_ao(area, x, z, -1, 1, y)
	var tint := _tint(area, x, z)
	var top_tint := tint
	if wall and area.id != "wick":
		top_tint = tint.darkened(0.78)   # the cut top of the rock mass reads as depth, not floor
	_quad(st, [p0, p1, p2, p3], [uv.position, uv.position + Vector2(uv.size.x, 0), uv.end,
		uv.position + Vector2(0, uv.size.y)], [top_tint * a0, top_tint * a1, top_tint * a2, top_tint * a3])
	# Sides where the neighbour is lower.
	var side_base: String = "side_rock" if wall else String(SIDE.get(mat_name, "side_rock"))
	if wall and (x * 7 + z * 13) % 9 == 0:
		side_base = "side_rock_glint"
	for dir in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		var nx: int = x + dir.x
		var nz: int = z + dir.y
		var ny: float
		if area.inside(nx, nz):
			ny = top_y(area, nx, nz)
		else:
			continue
		if ny >= y - 0.001:
			continue
		_side(st, x, z, dir, ny, y, side_base, tint)


static func _side(st: SurfaceTool, x: int, z: int, dir: Vector2i, y0: float, y1: float,
		base: String, tint: Color) -> void:
	# Build the face in 1 m tall segments so the texture tiles at 16 px/m.
	var a: Vector2
	var b: Vector2
	match dir:
		Vector2i(0, -1): a = Vector2(x + 1, z); b = Vector2(x, z)
		Vector2i(1, 0): a = Vector2(x + 1, z + 1); b = Vector2(x + 1, z)
		Vector2i(0, 1): a = Vector2(x, z + 1); b = Vector2(x + 1, z + 1)
		_: a = Vector2(x, z); b = Vector2(x, z + 1)
	var top := y1
	var seg := 0
	while top > y0 + 0.001:
		var bottom := maxf(y0, top - 1.0)
		var frac := top - bottom
		var uv := Atlas.uv_rect(Atlas.variant(base, x + seg * 3 + dir.x * 5, z + seg * 7 + dir.y * 11))
		# The first (top) segment of an earth cliff shows the mossy lip; deeper ones plain.
		if seg > 0 and base == "side_earth":
			uv = Atlas.uv_rect(Atlas.variant("side_earth_plain", x, z + seg))
		var v0 := uv.position.y
		var v1 := uv.position.y + uv.size.y * frac
		var shade_top := 1.0 - 0.06 * seg
		var shade_bot := maxf(0.42, 1.0 - 0.06 * seg - 0.2 * frac - (0.3 if bottom <= y0 + 0.001 else 0.0))
		# Faces pointing away from the camera (north) read darker.
		var facing := 0.78 if dir == Vector2i(0, -1) else (0.9 if dir.x != 0 else 1.0)
		_quad(st, [Vector3(a.x, top, a.y), Vector3(b.x, top, b.y), Vector3(b.x, bottom, b.y), Vector3(a.x, bottom, a.y)],
			[Vector2(uv.position.x, v0), Vector2(uv.end.x, v0), Vector2(uv.end.x, v1), Vector2(uv.position.x, v1)],
			[tint * shade_top * facing, tint * shade_top * facing, tint * shade_bot * facing, tint * shade_bot * facing])
		top = bottom
		seg += 1


static func _corner_ao(area: AreaMap, x: int, z: int, dx: int, dz: int, y: float) -> float:
	var occ := 0
	for o in [Vector2i(dx, 0), Vector2i(0, dz), Vector2i(dx, dz)]:
		if top_y(area, x + o.x, z + o.y) > y + 0.3:
			occ += 1
	return 1.0 - 0.17 * occ


static func _tint(area: AreaMap, x: int, z: int) -> Color:
	# Tiny per-cell value variation breaks up tiling without changing the palette.
	var hsh := float(absi((x * 92837111) ^ (z * 689287499)) % 1000) / 1000.0
	var v := 0.94 + hsh * 0.1
	return Color(v, v, v, 1.0)


static func _quad(st: SurfaceTool, p: Array, uv: Array, col: Array) -> void:
	for idx in [0, 1, 2, 0, 2, 3]:
		st.set_color(col[idx])
		st.set_uv(uv[idx])
		st.add_vertex(p[idx])


static func _water(area: AreaMap) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for z in area.d:
		for x in area.w:
			if area.h_at(x, z) != AreaMap.WATER_LEVEL:
				continue
			any = true
			# UV carries world position so the shader can tile and ripple seamlessly;
			# vertex colour alpha marks shore edges for foam.
			var shore := 0.0
			for dd in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
				if area.h_at(x + dd.x, z + dd.y) != AreaMap.WATER_LEVEL:
					shore = 1.0
			var c := Color(1, 1, 1, shore)
			_quad(st, [Vector3(x, WATER_Y, z), Vector3(x + 1, WATER_Y, z), Vector3(x + 1, WATER_Y, z + 1), Vector3(x, WATER_Y, z + 1)],
				[Vector2(x, z), Vector2(x + 1, z), Vector2(x + 1, z + 1), Vector2(x, z + 1)], [c, c, c, c])
	if not any:
		return null
	st.generate_normals()
	return st.commit()
