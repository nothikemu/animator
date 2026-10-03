class_name Market
extends RefCounted
## A buyer/seller with per-item stock. Prices respond to supply (what the player sells),
## scarcity, and a world quality factor (e.g. food grown in fouled air sells for less).
## Every factor is bounded so the economy stays understandable.

const MIN_FACTOR := 0.5
const MAX_FACTOR := 2.0
const RELAX := 0.35            ## daily movement of stock back toward its target

var id := ""
var stock: Dictionary = {}     ## item -> current stock
var target: Dictionary = {}    ## item -> stock level at which price == base
var buys: Array = []           ## item ids this market buys from the player
var sells: Array = []          ## item ids this market sells to the player
var modifiers: Dictionary = {} ## item -> extra multiplier (events, Grist absence...)


func setup(market_id: String, def: Dictionary) -> void:
	id = market_id
	buys = def.get("buys", []).duplicate()
	sells = def.get("sells", []).duplicate()
	var t: Dictionary = def.get("targets", {})
	for item in buys + sells:
		target[item] = float(t.get(item, 10.0))
		if not stock.has(item):
			stock[item] = target[item]


func scarcity(item: String) -> float:
	var t := maxf(1.0, float(target.get(item, 10.0)))
	var s := float(stock.get(item, t))
	return clampf(1.0 + 0.7 * (t - s) / t, MIN_FACTOR, MAX_FACTOR)


## Price the player receives when selling one unit.
func sell_price(item: String, base: float, quality := 1.0) -> int:
	var f := scarcity(item) * float(modifiers.get(item, 1.0)) * clampf(quality, 0.3, 1.2)
	return maxi(1, roundi(base * clampf(f, MIN_FACTOR, MAX_FACTOR) * 0.85))


## Price the player pays when buying one unit.
func buy_price(item: String, base: float) -> int:
	var f := scarcity(item) * float(modifiers.get(item, 1.0))
	return maxi(1, roundi(base * clampf(f, MIN_FACTOR, MAX_FACTOR) * 1.3))


func record_sale(item: String, n: int) -> void:
	stock[item] = float(stock.get(item, 0.0)) + n


func record_purchase(item: String, n: int) -> void:
	stock[item] = maxf(0.0, float(stock.get(item, 0.0)) - n)


func daily_relax() -> void:
	for item in target:
		var s := float(stock.get(item, target[item]))
		stock[item] = s + (float(target[item]) - s) * RELAX


## Trend word for dialogue ("glowbeets are going cheap").
func trend(item: String) -> String:
	var f := scarcity(item)
	if f < 0.75:
		return "cheap"
	if f > 1.35:
		return "dear"
	return "steady"


func to_dict() -> Dictionary:
	return {"stock": stock.duplicate(), "modifiers": modifiers.duplicate()}


func load_dict(d: Dictionary) -> void:
	var s: Variant = d.get("stock", {})
	if s is Dictionary:
		for item in s:
			if target.has(item):
				stock[item] = clampf(float(s[item]), 0.0, 9999.0)
	var m: Variant = d.get("modifiers", {})
	if m is Dictionary:
		for item in m:
			modifiers[item] = clampf(float(m[item]), 0.1, 5.0)
