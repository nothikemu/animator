extends TestCase
## Market price bounds, supply response, inventory rules.


func _market() -> Market:
	var m := Market.new()
	m.setup("t", {"buys": ["glowbeet"], "sells": ["glowbeet"], "targets": {"glowbeet": 20}})
	return m


func test_prices_are_bounded() -> void:
	var m := _market()
	m.stock["glowbeet"] = 100000.0
	check(m.sell_price("glowbeet", 6.0) >= 1, "never zero")
	near(m.scarcity("glowbeet"), Market.MIN_FACTOR, 0.0001, "flooded market floor")
	m.stock["glowbeet"] = 0.0
	check(m.scarcity("glowbeet") <= Market.MAX_FACTOR, "scarcity cap")


func test_selling_lowers_the_price_and_it_recovers() -> void:
	var m := _market()
	var p0 := m.sell_price("glowbeet", 10.0)
	m.record_sale("glowbeet", 30)
	var p1 := m.sell_price("glowbeet", 10.0)
	check(p1 < p0, "flooding lowers price (%d -> %d)" % [p0, p1])
	for i in 6:
		m.daily_relax()
	var p2 := m.sell_price("glowbeet", 10.0)
	check(p2 > p1, "price recovers over days")
	eq(m.trend("glowbeet"), "steady", "back to steady")


func test_buy_price_exceeds_sell_price() -> void:
	var m := _market()
	check(m.buy_price("glowbeet", 10.0) > m.sell_price("glowbeet", 10.0), "no infinite money loop")


func test_inventory_stacks_and_limits() -> void:
	var inv := Inventory.new(3)
	inv.stack_limits = {"a": 10, "b": 1}
	eq(inv.add("a", 25), 0, "25 'a' fit in three slots")
	eq(inv.count("a"), 25, "count")
	eq(inv.add("b", 1), 1, "no room left for 'b'")
	check(inv.remove("a", 12), "remove across stacks")
	eq(inv.count("a"), 13, "remaining")
	check(not inv.remove("a", 99), "all-or-nothing removal")
	eq(inv.count("a"), 13, "unchanged after failed removal")
	check(inv.has_all({"a": 13}), "has_all")


func test_inventory_drops_unknown_items_on_load() -> void:
	var inv := Inventory.new(4)
	inv.load_array([{"id": "glowbeet", "n": 3}, {"id": "not_a_real_item", "n": 2}], Content.items)
	eq(inv.count("glowbeet"), 3, "kept known item")
	eq(inv.count("not_a_real_item"), 0, "dropped unknown item")
