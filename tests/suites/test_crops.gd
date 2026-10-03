extends TestCase
## Crop rules: factors, growth, health, yield.

func _beet() -> Dictionary:
	return Content.crop("glowbeet")


func _good_env() -> Dictionary:
	return {"light": 0.6, "moisture": 0.7, "temp": 22.0, "sour": 0.0}


func test_factors_are_one_inside_ranges() -> void:
	var f := CropLogic.factors(_beet(), _good_env())
	for c in f:
		near(f[c], 1.0, 0.0001, "factor %s" % c)


func test_factor_falls_off_outside_range() -> void:
	var env := _good_env()
	env.temp = 12.0  # 4 below the 16 minimum, margin 8 -> 0.5
	var f := CropLogic.factors(_beet(), env)
	near(f.temp, 0.5, 0.0001, "half-way down the margin")
	var w := CropLogic.worst(_beet(), env, f)
	eq(w.cond, "temp", "worst condition")
	eq(w.dir, "low", "too cold, not too hot")


func test_crop_matures_in_its_listed_days_in_good_conditions() -> void:
	var p := {"crop": "glowbeet", "growth": 0.0, "health": 1.0, "water": 1.0}
	var days := float(_beet().days)
	for i in int(days * 144):
		p.water = 1.0
		CropLogic.advance(p, _beet(), _good_env(), 10.0)
	check(CropLogic.is_mature(p), "mature after %d days (growth %.3f)" % [days, p.growth])


func test_bad_conditions_kill_slowly_not_instantly() -> void:
	var p := {"crop": "glowbeet", "growth": 0.2, "health": 1.0, "water": 1.0}
	var env := _good_env()
	env.sour = 0.6
	CropLogic.advance(p, _beet(), env, 60.0)
	check(not p.dead and p.health < 1.0, "one hour of foul air hurts but does not kill")
	for i in 48:
		CropLogic.advance(p, _beet(), env, 60.0)
	check(p.dead, "two days of foul air kills a glowbeet")


func test_sulfur_fern_tolerates_sour_air() -> void:
	var fern := Content.crop("sulfur_fern")
	var env := _good_env()
	env.sour = 0.5
	var f := CropLogic.factors(fern, env)
	near(f.sour, 1.0, 0.0001, "fern is happy in sour air")


func test_yield_scales_with_health() -> void:
	var healthy := CropLogic.expected_yield({"health": 1.0}, _beet())
	var sick := CropLogic.expected_yield({"health": 0.3}, _beet())
	check(int(healthy.glowbeet) > int(sick.glowbeet), "healthier crops yield more")


func test_every_crop_definition_is_growable_somewhere() -> void:
	for id in Content.crops:
		var c: Dictionary = Content.crops[id]
		var env := {}
		for cond in c.ranges:
			var r: Array = c.ranges[cond]
			env[cond] = (float(r[0]) + float(r[1])) * 0.5
		var f := CropLogic.factors(c, env)
		near(CropLogic.growth_rate(c, f), 1.0, 0.0001, "%s grows at its range midpoint" % id)
