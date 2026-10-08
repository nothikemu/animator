extends TestCase
## References that would otherwise fail silently: a schedule point that doesn't exist sends an
## NPC to the commons; an icon that doesn't exist shows a warning sign.


func test_schedule_points_exist() -> void:
	for id: String in Content.npcs:
		var def: Dictionary = Content.npc(id)
		var pts: Dictionary = Npc.points_for(id)
		var home := String(def.get("home", ""))
		check(pts.has(home), "%s's home '%s' is a point on the map" % [id, home])
		for b: Dictionary in def.get("schedule", []):
			var at := String(b.get("at", ""))
			check(at in ["home", "away"] or pts.has(at), "%s goes to '%s', which exists" % [id, at])


func test_item_icons_exist() -> void:
	var meta: Variant = Content.read_json("res://assets/textures/icons.json")
	check(meta is Dictionary, "icon manifest")
	var icons: Dictionary = meta.icons
	for id: String in Content.items:
		var icon := String(Content.item(id).get("icon", id))
		check(icons.has(icon) or icons.has(id), "item %s has an icon (%s)" % [id, icon])


func test_machine_sprites_exist() -> void:
	var meta: Variant = Content.read_json("res://assets/textures/machines/machines.json")
	for id: String in Content.machines:
		check((meta as Dictionary).has(id), "machine %s has a sprite strip" % id)
