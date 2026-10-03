extends Node
## Markets. Prices respond to what the player sells, to scarcity, to Wick's air quality
## (for food) and to Grist's visits (for ore). All factors are bounded (see Market).

var markets: Dictionary = {}             ## id -> Market
var defs: Dictionary = {}
var days_since_grist := 0


func _ready() -> void:
	Clock.day_started.connect(_on_day)


func reset() -> void:
	defs = Content.markets
	markets.clear()
	for id in defs:
		var m := Market.new()
		m.setup(id, defs[id])
		markets[id] = m
	days_since_grist = 0


func market(id: String) -> Market:
	return markets.get(id)


func food_quality() -> float:
	# Food grown and cooked in fouled air "tastes of the vent".
	var p := float(Sim.village_pollution()) if Sim.grid != null else 0.0
	return clampf(1.0 - p * 2.5, 0.5, 1.0)


func sell_price(market_id: String, item: String) -> int:
	var m := market(market_id)
	if m == null or not m.buys.has(item):
		return 0
	var q := 1.0
	if bool(defs[market_id].get("food_quality", false)) and bool(Content.item(item).get("food", false)):
		q = food_quality()
	return m.sell_price(item, float(Content.item(item).get("value", 1)), q)


func buy_price(market_id: String, item: String) -> int:
	var m := market(market_id)
	if m == null or not m.sells.has(item):
		return 0
	return m.buy_price(item, float(Content.item(item).get("value", 1)))


func sell(market_id: String, item: String, n: int) -> int:
	var m := market(market_id)
	if m == null or n <= 0 or not m.buys.has(item):
		return 0
	var earned := 0
	for i in n:
		if not GameState.take(item, 1):
			break
		earned += sell_price(market_id, item)
		m.record_sale(item, 1)
	if earned > 0:
		GameState.add_money(earned)
		GameState.add_deed("sold", float(n), {"item": item, "market": market_id})
		if bool(Content.item(item).get("food", false)):
			GameState.add_deed("sold_food", float(n), {"item": item})
	return earned


func buy(market_id: String, item: String, n: int) -> int:
	var m := market(market_id)
	if m == null or n <= 0 or not m.sells.has(item):
		return 0
	var bought := 0
	for i in n:
		var price := buy_price(market_id, item)
		if GameState.inventory.room_for(item) <= 0 or not GameState.spend(price):
			break
		GameState.give(item, 1, true)
		m.record_purchase(item, 1)
		bought += 1
	if bought > 0:
		Events.toast.emit("+%d %s" % [bought, Content.item_name(item)], &"item")
	return bought


## Schematics offered by a market right now: [{id, name, price}].
func schematics(market_id: String) -> Array:
	var out: Array = []
	var s: Dictionary = defs.get(market_id, {}).get("schematics", {})
	for id in s:
		if GameState.has_flag(id):
			continue
		if Conditions.check(s[id].get("when", []), GameState):
			out.append({"id": id, "name": s[id].name, "price": int(s[id].price)})
	return out


func buy_schematic(market_id: String, id: String) -> bool:
	for s in schematics(market_id):
		if s.id == id and GameState.spend(int(s.price)):
			GameState.set_flag(id, true)
			GameState.discover("recipes", id)
			Events.toast.emit("Learned: %s" % s.name, &"learn")
			return true
	return false


func _on_day(_d: int) -> void:
	for id in markets:
		markets[id].daily_relax()
	days_since_grist += 1
	var ex := market("exchange")
	if ex != null:
		var scarce := 1.4 if days_since_grist > 4 else 1.0
		for item in ["thermal_ore", "glowglass"]:
			ex.modifiers[item] = scarce


func grist_visited() -> void:
	days_since_grist = 0


func to_dict() -> Dictionary:
	var out := {}
	for id in markets:
		out[id] = markets[id].to_dict()
	return {"markets": out, "days_since_grist": days_since_grist}


func load_dict(d: Dictionary) -> void:
	reset()
	var ms: Variant = d.get("markets", {})
	if ms is Dictionary:
		for id in ms:
			if markets.has(id) and ms[id] is Dictionary:
				markets[id].load_dict(ms[id])
	days_since_grist = int(d.get("days_since_grist", 0))
