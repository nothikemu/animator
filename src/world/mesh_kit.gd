class_name MeshKit
extends RefCounted
## Builds atlas-textured boxes, gable roofs and decals into a SurfaceTool. Faces are split into
## 1 m cells so every surface keeps the world's 16 px/m texel density.

var st := SurfaceTool.new()
var color := Color.WHITE


func _init() -> void:
	st.begin(Mesh.PRIMITIVE_TRIANGLES)


func commit() -> ArrayMesh:
	st.generate_normals()
	return st.commit()


## Axis-aligned box from `p` (min corner) of `size`. tiles: {"top", "side", "front", "bottom"}
## (missing keys fall back to "side"). shade_bottom darkens the lower edge (fake AO).
func box(p: Vector3, size: Vector3, tiles: Dictionary, shade_bottom := true, faces := 0x3F) -> void:
	var side: String = tiles.get("side", "rock_0")
	var top: String = tiles.get("top", side)
	var front: String = tiles.get("front", side)
	var back: String = tiles.get("back", side)
	var x0 := p.x
	var y0 := p.y
	var z0 := p.z
	var x1 := p.x + size.x
	var y1 := p.y + size.y
	var z1 := p.z + size.z
	if faces & 1:  # top
		_grid_face(Vector3(x0, y1, z0), Vector3(size.x, 0, 0), Vector3(0, 0, size.z), top, false)
	if faces & 2:  # south (+z, toward camera)
		_grid_face(Vector3(x0, y1, z1), Vector3(size.x, 0, 0), Vector3(0, -size.y, 0), front, shade_bottom)
	if faces & 4:  # north
		_grid_face(Vector3(x1, y1, z0), Vector3(-size.x, 0, 0), Vector3(0, -size.y, 0), back, shade_bottom, 0.8)
	if faces & 8:  # east
		_grid_face(Vector3(x1, y1, z1), Vector3(0, 0, -size.z), Vector3(0, -size.y, 0), side, shade_bottom, 0.9)
	if faces & 16:  # west
		_grid_face(Vector3(x0, y1, z0), Vector3(0, 0, size.z), Vector3(0, -size.y, 0), side, shade_bottom, 0.9)
	if faces & 32:  # bottom (rarely visible)
		_grid_face(Vector3(x0, y0, z1), Vector3(size.x, 0, 0), Vector3(0, 0, -size.z), tiles.get("bottom", side), false, 0.5)


## A flat rectangle spanning u and v vectors from origin `o`, split into ≤1 m cells.
func _grid_face(o: Vector3, u: Vector3, v: Vector3, tile: String, shade_bottom: bool, light := 1.0) -> void:
	var lu := u.length()
	var lv := v.length()
	var nu := maxi(1, int(ceil(lu - 0.001)))
	var nv := maxi(1, int(ceil(lv - 0.001)))
	var du := u / lu if lu > 0 else Vector3.ZERO
	var dv := v / lv if lv > 0 else Vector3.ZERO
	var uv := Atlas.uv_rect(tile)
	for j in nv:
		var v0 := float(j)
		var v1 := minf(lv, float(j + 1))
		for i in nu:
			var u0 := float(i)
			var u1 := minf(lu, float(i + 1))
			var a := o + du * u0 + dv * v0
			var b := o + du * u1 + dv * v0
			var c := o + du * u1 + dv * v1
			var d := o + du * u0 + dv * v1
			var ta := uv.position + Vector2(0, 0)
			var tb := uv.position + Vector2(uv.size.x * (u1 - u0), 0)
			var tc := uv.position + Vector2(uv.size.x * (u1 - u0), uv.size.y * (v1 - v0))
			var td := uv.position + Vector2(0, uv.size.y * (v1 - v0))
			var s0 := light
			var s1 := light
			if shade_bottom:
				s0 = light * (1.0 - 0.35 * (v0 / maxf(lv, 0.001)) ** 2)
				s1 = light * (1.0 - 0.35 * (v1 / maxf(lv, 0.001)) ** 2)
			_quad([a, b, c, d], [ta, tb, tc, td], [color * s0, color * s0, color * s1, color * s1])


func _quad(p: Array, uv: Array, col: Array) -> void:
	for idx in [0, 1, 2, 0, 2, 3]:
		var c: Color = col[idx]
		c.a = 1.0
		st.set_color(c)
		st.set_uv(uv[idx])
		st.add_vertex(p[idx])


## Gable roof over a footprint, ridge along X. Eaves overhang by `over`.
func gable_roof(p: Vector3, size: Vector2, rise: float, roof_tile: String, gable_tile: String, over := 0.35) -> void:
	var x0 := p.x - over
	var x1 := p.x + size.x + over
	var z0 := p.z - over
	var z1 := p.z + size.y + over
	var zm := p.z + size.y * 0.5
	var y0 := p.y
	var y1 := p.y + rise
	# South slope (faces camera).
	_grid_face(Vector3(x0, y1, zm), Vector3(x1 - x0, 0, 0), Vector3(0, y0 - y1, z1 - zm), roof_tile, false, 1.0)
	# North slope.
	_grid_face(Vector3(x1, y1, zm), Vector3(x0 - x1, 0, 0), Vector3(0, y0 - y1, z0 - zm), roof_tile, false, 0.72)
	# Gable triangles (west and east), textured with the wall tile.
	var uv := Atlas.uv_rect(gable_tile)
	for side in [0, 1]:
		var gx := p.x if side == 0 else p.x + size.x
		var a := Vector3(gx, y0, p.z)
		var b := Vector3(gx, y0, p.z + size.y)
		var c := Vector3(gx, y1, zm)
		var tri: Array = [a, c, b] if side == 0 else [a, b, c]
		for v in tri:
			st.set_color(color * 0.85)
			var t := Vector2(uv.position.x + uv.size.x * ((v.z - p.z) / size.y), uv.position.y + uv.size.y * (1.0 - (v.y - y0) / rise))
			st.set_uv(t)
			st.add_vertex(v)
	# Ridge beam.
	box(Vector3(x0, y1 - 0.12, zm - 0.12), Vector3(x1 - x0, 0.2, 0.24), {"side": "beam_0"}, false)


## A single quad decal (windows, doors, signs) on a plane facing +z (or other axis).
func decal(center: Vector3, size: Vector2, tile: String, normal := Vector3.BACK) -> void:
	var right := Vector3.UP.cross(normal).normalized()
	if normal == Vector3.UP:
		right = Vector3.RIGHT
	var up := normal.cross(right).normalized() if normal != Vector3.UP else Vector3.BACK * -1.0
	var hs := size * 0.5
	var a := center - right * hs.x + up * hs.y
	var b := center + right * hs.x + up * hs.y
	var c := center + right * hs.x - up * hs.y
	var d := center - right * hs.x - up * hs.y
	var uv := Atlas.uv_rect(tile)
	_quad([a, b, c, d], [uv.position, uv.position + Vector2(uv.size.x, 0), uv.end, uv.position + Vector2(0, uv.size.y)],
		[color, color, color, color])


## Octagonal prism (barrels, tanks, posts).
func prism(center_bottom: Vector3, radius: float, height: float, sides: int, tile: String, top_tile := "") -> void:
	var uv := Atlas.uv_rect(tile)
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var p0 := center_bottom + Vector3(cos(a0) * radius, 0, sin(a0) * radius)
		var p1 := center_bottom + Vector3(cos(a1) * radius, 0, sin(a1) * radius)
		var light := 0.7 + 0.3 * clampf(sin((a0 + a1) * 0.5), 0.0, 1.0)
		var u0 := uv.position.x + uv.size.x * float(i % 2) * 0.5
		var u1 := u0 + uv.size.x * 0.5
		_quad([p1 + Vector3.UP * height, p0 + Vector3.UP * height, p0, p1],
			[Vector2(u0, uv.position.y), Vector2(u1, uv.position.y), Vector2(u1, uv.position.y + uv.size.y * minf(height, 1.0)), Vector2(u0, uv.position.y + uv.size.y * minf(height, 1.0))],
			[color * light, color * light, color * light * 0.7, color * light * 0.7])
	if top_tile != "":
		var tu := Atlas.uv_rect(top_tile)
		var c := center_bottom + Vector3.UP * height
		for i in sides:
			var a0 := TAU * i / sides
			var a1 := TAU * (i + 1) / sides
			var p0 := c + Vector3(cos(a0) * radius, 0, sin(a0) * radius)
			var p1 := c + Vector3(cos(a1) * radius, 0, sin(a1) * radius)
			for v in [c, p0, p1]:
				st.set_color(color)
				st.set_uv(tu.position + tu.size * Vector2(0.5 + (v.x - c.x) / (radius * 2.0), 0.5 + (v.z - c.z) / (radius * 2.0)))
				st.add_vertex(v)
