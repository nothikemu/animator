class_name Scenarios
extends RefCounted
## Developer scenarios for screenshots and testing: put the world into a specific state.
##   godot -- --scenario=wick_day --capture=/tmp/shot.png


static func run(game: Node, name: String) -> void:
	var parts := name.split(":")
	match parts[0]:
		"wick_day":
			Clock.start(1, 10 * 60)
			_place(game, Vector2(12.5, 17.5))
		"wick_night":
			Clock.start(1, 23 * 60)
			_place(game, Vector2(22.5, 14.5))
		"commons":
			Clock.start(1, 19 * 60)
			_place(game, Vector2(23.5, 15.5))
		"arrival":
			Clock.start(1, 7 * 60)
			_place(game, Vector2(4.5, 6.5))
		"lease":
			Clock.start(1, 9 * 60)
			_place(game, Vector2(6.5, 12.5))
		"pumphall":
			Clock.start(1, 14 * 60)
			_place(game, Vector2(40.5, 14.5))
		"lake":
			Clock.start(1, 21 * 60)
			_place(game, Vector2(14.5, 22.5))
		"reach":
			var id: String = parts[1] if parts.size() > 1 else String(GameState.reach_graph.nodes[0].id)
			game.load_area(id)
		"pos":
			_place(game, Vector2(float(parts[1]), float(parts[2])))
	if game.has_method("on_scenario"):
		game.on_scenario(name)


static func _place(game: Node, p: Vector2) -> void:
	game.player.place(p, game.area)
	game.rig.snap()
