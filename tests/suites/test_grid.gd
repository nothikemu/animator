extends TestCase
## Undercroft field simulation: conservation, buoyancy, water behaviour, heat bounds.


func _box(w: int, h: int) -> UcGrid:
	var g := UcGrid.new(w, h, h)
	for y in h:
		for x in w:
			var wall := x == 0 or y == 0 or x == w - 1 or y == h - 1
			g.mat[g.idx(x, y)] = UcGrid.Mat.ROCK if wall else UcGrid.Mat.AIR
	g.fill_open_with_ambient()
	return g


func test_water_is_conserved_in_a_closed_box() -> void:
	var g := _box(10, 8)
	g.water[g.idx(3, 2)] = 1.0
	g.water[g.idx(4, 2)] = 1.0
	g.water[g.idx(5, 3)] = 0.7
	var before := g.total_water()
	for i in 300:
		g.step(0.25)
	near(g.total_water(), before, 0.01, "water mass changed in a sealed box")


func test_water_falls_and_settles_at_the_bottom() -> void:
	var g := _box(8, 8)
	g.water[g.idx(3, 1)] = 1.0
	for i in 200:
		g.step(0.25)
	var bottom := 0.0
	for x in range(1, 7):
		bottom += g.water[g.idx(x, 6)]
	check(bottom > 0.9, "water should collect on the floor (got %.3f)" % bottom)
	check(g.water[g.idx(3, 1)] < 0.01, "source cell should drain")


func test_gas_species_are_conserved() -> void:
	var g := _box(12, 10)
	g.add_gas(3, 3, UcGrid.SOUR, 0.8)
	g.add_gas(8, 7, UcGrid.DAMP, 0.6)
	# Close the top row so there is no exchange with the cavern.
	var before := [g.total_species(UcGrid.SOUR), g.total_species(UcGrid.DAMP), g.total_species(UcGrid.FRESH)]
	for i in 200:
		g.step(0.25)
	near(g.total_species(UcGrid.SOUR), before[0], 0.01, "sour mass changed")
	near(g.total_species(UcGrid.DAMP), before[1], 0.01, "damp mass changed")
	near(g.total_species(UcGrid.FRESH), before[2], 0.02, "fresh mass changed")


func test_sour_sinks_and_damp_rises() -> void:
	var g := _box(6, 12)
	for y in range(1, 11):
		for x in range(1, 5):
			var i := g.idx(x, y)
			g.gas[UcGrid.SOUR][i] = 0.3 if y < 6 else 0.0
			g.gas[UcGrid.DAMP][i] = 0.3 if y >= 6 else 0.0
			g.gas[UcGrid.FRESH][i] = 0.7
	for i in 400:
		g.step(0.25)
	var sour_top := 0.0
	var sour_bottom := 0.0
	var damp_top := 0.0
	var damp_bottom := 0.0
	for x in range(1, 5):
		for y in range(1, 4):
			sour_top += g.gas_fraction(x, y, UcGrid.SOUR)
			damp_top += g.gas_fraction(x, y, UcGrid.DAMP)
		for y in range(8, 11):
			sour_bottom += g.gas_fraction(x, y, UcGrid.SOUR)
			damp_bottom += g.gas_fraction(x, y, UcGrid.DAMP)
	check(sour_bottom > sour_top * 1.5, "sour should pool low (top %.3f, bottom %.3f)" % [sour_top, sour_bottom])
	check(damp_top > damp_bottom * 1.5, "damp should rise (top %.3f, bottom %.3f)" % [damp_top, damp_bottom])


func test_hot_air_rises() -> void:
	# Same heater, once in an air-filled shaft and once in solid rock: convection must carry
	# far more heat to the top than conduction alone.
	var air := _box(6, 10)
	var rock := _box(6, 10)
	for y in range(1, 9):
		for x in range(1, 5):
			rock.mat[rock.idx(x, y)] = UcGrid.Mat.SOIL
	for i in 300:
		air.temp[air.idx(3, 8)] = 160.0
		rock.temp[rock.idx(3, 8)] = 160.0
		air.step(0.25)
		rock.step(0.25)
	var top_air := air.temp[air.idx(3, 1)]
	var top_rock := rock.temp[rock.idx(3, 1)]
	check(top_air > top_rock + 15.0, "warm air should rise (top %.1f in air vs %.1f in soil)" % [top_air, top_rock])


func test_water_displaces_gas_upward() -> void:
	var g := _box(5, 8)
	for x in range(1, 4):
		g.water[g.idx(x, 6)] = 1.0
		g.water[g.idx(x, 5)] = 1.0
	g.step(0.25)
	check(g.gas_total(g.idx(2, 6)) < 0.2, "a full water cell should hold almost no gas")


func test_heat_is_clamped() -> void:
	var g := _box(5, 5)
	g.temp[g.idx(2, 2)] = 1e9
	g.add_heat(2, 2, 1e9)
	g.step(0.25)
	for i in g.w * g.h:
		check(g.temp[i] <= UcGrid.T_MAX and g.temp[i] >= UcGrid.T_MIN, "temperature out of bounds at %d" % i)


func test_soil_soaks_up_standing_water() -> void:
	var g := _box(6, 6)
	for x in range(1, 5):
		g.mat[g.idx(x, 4)] = UcGrid.Mat.SOIL
	g.water[g.idx(2, 3)] = 0.4
	for i in 200:
		g.step(0.25)
	check(g.moisture[g.idx(2, 4)] > 0.05, "soil below a puddle should become damp")
	check(g.water[g.idx(2, 3)] < 0.4, "puddle should shrink as soil drinks")


func test_serialisation_round_trip() -> void:
	var g := _box(9, 7)
	g.water[g.idx(3, 3)] = 0.8
	g.add_gas(4, 2, UcGrid.SOUR, 0.4)
	g.springs[Vector2i(2, 2)] = 0.01
	var g2 := UcGrid.from_dict(g.to_dict())
	near(g2.total_water(), g.total_water(), 0.0001, "water")
	near(g2.total_species(UcGrid.SOUR), g.total_species(UcGrid.SOUR), 0.0001, "sour")
	eq(g2.springs.size(), 1, "springs restored")


func test_corrupt_values_are_sanitised_on_load() -> void:
	var g := _box(5, 5)
	var d := g.to_dict()
	var bad := PackedFloat32Array()
	bad.resize(25)
	bad.fill(NAN)
	d.water = Marshalls.raw_to_base64(bad.to_byte_array())
	var g2 := UcGrid.from_dict(d)
	for i in 25:
		check(not is_nan(g2.water[i]), "NaN survived load")
