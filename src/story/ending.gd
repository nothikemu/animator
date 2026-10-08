class_name Ending
extends RefCounted
## Which ending the player reached, and the epilogue: a card for each person, chosen by what
## the player actually did. Nothing here is a score. Each line is a consequence somebody lived.

const TITLES := {
	"everything": "Everything Breathing",
	"together": "Breathe Together",
	"watch": "The Long Watch",
	"sealed": "Sealed",
}


static func _f(name: String) -> bool:
	return GameState.has_flag(name)


static func _fs(name: String) -> String:
	var v: Variant = GameState.flag(name)
	return String(v) if v != null else ""


## The ending, from the choice made at the console and the state of everything else.
static func resolve() -> String:
	var choice := _fs("ending")
	if choice == "watch":
		return "watch"
	if choice == "sealed":
		return "sealed"
	var clean := GameState.deed("clean_power") >= GameState.deed("industrial_power")
	var arcs := _f("o_trade_sent") and _f("learned_tincture") and _f("mags_stores_ok") \
		and (_f("reunion_done") or _f("grief_done") or _f("journal_given")) and _f("ways_open")
	if _f("heart_running") and not _f("wren_died") and clean and arcs:
		return "everything"
	return "together"


## Cards: [{lines: [...], hold: seconds, color: Color}]
static func cards(id: String) -> Array:
	var out: Array = []
	out.append({"lines": [String(TITLES.get(id, ""))], "hold": 2.6, "color": UiTheme.ACCENT})
	match id:
		"everything":
			out.append({"lines": ["The Bellows breathed, and every station breathed with it.",
				"On the next Quietlight the lampmoths rose through forty stations at once,",
				"and everything alive down there was lit by everything else alive down there."], "hold": 2.8, "color": UiTheme.LIVING})
		"together":
			out.append({"lines": ["The Bellows breathed, and every station breathed with it.",
				"Not everything that was lost on the way came back.", "Most things did."], "hold": 2.6, "color": UiTheme.LIVING})
		"watch":
			out.append({"lines": ["The Heart kept breathing, slowly, the way it had for eleven years.",
				"The lift ran every morning. Two towns knocked to each other every night.",
				"It was careful, and kind, and running down, and nobody was alone."], "hold": 2.6, "color": UiTheme.TEXT})
		"sealed":
			out.append({"lines": ["Wick was safe, and dry, and alone.",
				"Sometimes, at Hush, the pipe-heads knocked.", "Nobody answered."], "hold": 2.8, "color": UiTheme.DIM})
	out.append({"lines": _people(id), "hold": 2.9, "color": UiTheme.TEXT})
	out.append({"lines": [_you(id)], "hold": 3.2, "color": UiTheme.TEXT})
	return out


static func _people(id: String) -> Array:
	var lines: Array = []
	# Barnaby.
	if _f("reunion_done"):
		lines.append("Barnaby Coil took his tea at Sallow on Tuesdays and in Wick on Wednesdays. The quiet table got a second cup.")
	elif _f("grief_done") or _f("journal_given"):
		lines.append("Barnaby kept Wren's journal by the gauge, and wrote in it every night. Every entry began 'W —'.")
	else:
		lines.append("Barnaby kept the gauge. He still said everything once.")
	# Wren and Pell.
	if _f("wren_saved"):
		lines.append("Wren Askew taught the letter code to the children of every station she could reach, and lost every argument about it on purpose.")
	elif _f("wren_died"):
		lines.append("Pell kept knocking. Every night, three-two-three, for anyone below who hadn't heard yet.")
	if _f("pell_in_wick"):
		lines.append("Pell went to look at the lake every week, and never got used to it, which was the point.")
	# Odile.
	if _f("o_page40_done"):
		lines.append("Odile Brask tore out page forty. Nobody ever found out why prices went down.")
	elif _f("o_trade_sent"):
		lines.append("The Exchange traded down-river and down the lift. Odile's ledger grew a second volume, then a third.")
	else:
		lines.append("Odile kept the ledger. She kept the coughs column shortest of all.")
	# Hesper.
	var strain := _fs("h_strain_choice")
	if id in ["everything", "together"] and strain != "wrong":
		lines.append("Hesper Mott became Keeper of the Frames for forty stations, and still spoke more politely to moss than to people.")
	elif strain == "wrong":
		lines.append("Hesper never forgave the builders. She forgave the moss, which had never needed it.")
	else:
		lines.append("Hesper tended the frames, and counted the lampmoths, and was right about the air.")
	# Mags.
	if _f("long_table_done"):
		lines.append("The Lantern House kept the long table. It never went back to being several tables.")
	elif _f("mags_stores_ok"):
		lines.append("Mags ate supper every night, in front of people.")
	else:
		lines.append("Mags kept counting the jars, more quietly than before.")
	# Grist and the Knappers.
	if _f("ways_open"):
		lines.append("The Knappers walked the ways again. Grist came to market every day, slowly, and was never once late.")
	# Tolley.
	if _f("tolley_returned"):
		lines.append("Tolley Brand apologised to the Lease plots every morning. They grew anyway.")
	elif _f("tolley_met"):
		lines.append("Tolley stayed at Sallow with the pale fungus, and wrote to Wick, and apologised in every letter.")
	return lines


static func _you(id: String) -> String:
	var clean := GameState.deed("clean_power") >= GameState.deed("industrial_power")
	var who := String(GameState.player.get("name", "The salvager"))
	if id == "sealed":
		return "%s stayed in Wick, and kept the farm, and sometimes stood in the lane at Hush with a hand on the brass." % who
	if clean:
		return "%s fell down a shaft into the dark, and left it brighter, and quieter, than they found it." % who
	return "%s fell down a shaft into the dark, and left it brighter than they found it, and louder." % who
