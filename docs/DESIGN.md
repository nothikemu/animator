# BELLOWS — Design Document

*Working title. Formerly "Project Underground".*

> **One line:** Build a life inside a living underground machine — and find out who else is still breathing down there.

---

## 1. Identity in one paragraph

You are a surface salvager whose line snapped at the bottom of a shaft. You land in **Wick**, a lamp-lit
settlement of people who live on top of a two-hundred-year-old machine they no longer understand. You
farm crops that care about the *air*, mend pipes you can only see by cutting the world open, and get to
know neighbours who each want something different from the machine beneath them. The game's signature
moment is a camera move: the tilted, lamp-lit diorama of village life **splits open along a cut line and
swings down into a side-on cross-section**. There, gas pools, water falls and heat creeps through
rock. The farm and the plumbing are one place seen two ways.

### What makes it not a mashup (originality test)

| Borrowed principle | Where it came from | What we do that they don't |
|---|---|---|
| Daily rhythm, crops, neighbours | Life sims | Crops are **environmental instruments**: their health is a readout of the air, heat and water you engineered. There is no stamina bar, no seasons calendar, no inherited farm. |
| Gas/water/heat simulation | Colony sims | One **cross-section slice** of your actual village, not a colony base. You are one person, not a manager of workers. The sim exists to make the village *feel* consequences. |
| The world remembers you | Character-driven RPGs | No combat, no mercy system. Memory is about **infrastructure deeds**: who you flooded, whose moss you gassed, who you carried home. |
| Diorama look | HD-2D | Underground: no sun or sky. Light comes from bioluminescence and lamps the player builds. Brightness tells the story of progress. Plus the cutaway, which needs a real 3D world. |

If you removed every reference game's name, the remaining pitch is still:
*"A cozy village sim where you see your village in cross-section, and the village's air, water and
heat are a single simulated machine whose original purpose is the central mystery."*

---

## 2. Design pillars

1. **Two views, one world.** Everything in the village has an underside. The cross-section isn't a
   minigame screen. It's the same place, and changes made there visibly change the village.
2. **Crops are instruments.** Each crop is happiest in a different air/heat/light/water niche. A
   healthy farm means you understood the machine; a sick one tells you exactly what's wrong.
3. **Remembered deeds, not morality.** People track what you actually did to *them* and to the
   places they love, on several separate axes. The game never tells you which choice was right.
4. **Quiet, strange, warm.** Long stretches of comfort punctuated by small crises. Dry humour from
   character, not jokes. Never relentlessly cute or dark.
5. **Light is progress.** You start in a dark, broken corner. Everything you build adds light, and
   the brightness of your home is the most honest progress bar in the game.

Every feature must answer: *Why does the player care? What other system does it touch? Is it more fun?*

---

## 3. World bible

### 3.1 The Deep and the Bellows
The Deep is a vast column of caverns under the surface. Its inhabitants call its slow, periodic wind
**the Breath**. Every few days the air **exhales** (gas rises out of the lower levels through every
vent) and then **inhales**. They call the whole system **the Bellows**, as you'd name the weather.

**The truth (revealed in fragments, never in a lore dump):** the Deep is an engineered life-support
machine: forty **Respiratory Stations** stacked in a column and joined by great air-and-water
conduits called **Trunk Lines**. Its builders seeded it with engineered organisms to do the work:
glowroots carry heat and light along old conduits, cave moss scrubs stale air, sulfur ferns eat
waste gas. Generations later the organisms and the machine are fused, and the ecosystem *is* the
machine. Nobody alive knows that.

Two centuries ago something called **the Quiet** happened. Trunk Lines collapsed or were sealed,
stations lost contact, and each settlement came to believe it was alone. Wick is built on
**Station 7**. Its great pump is dead. Its Trunk valve was sealed eleven years ago by Barnaby, during a
flood, with his crew partner on the other side.

**What the MVP reveals:** when the player restores Station 7 and the Trunk valve is opened, a pressure
gauge labelled LOWER STATIONS moves, and a **knock** comes back up the pipe in old crew code. Someone,
or something, below is still running the machine. **The MVP ends there: "I want to see what is
deeper down."**

**What stays unanswered:** why the Quiet happened; who built the Deep; what the surface knows; who is
knocking. Every revelation raises a new question.

### 3.2 Tone references (in spirit, not content)
Quiet as a small-town night shift. Funny the way tired professionals are funny. Strange like
finding a working machine in a ruin. Melancholic like an empty chair kept at a table.

### 3.3 Places (MVP)

| Place | Biome | Mood & light | Purpose |
|---|---|---|---|
| **Wick** (hand-authored) | Glowroot Grove | Warm amber lanterns against cyan glowroots, a still lake, steam from the Lantern House | Home, farm, neighbours, market, the Undercroft cross-section |
| **The Undercroft** | (cross-section under Wick) | Strata, old brick, brass pipework, the dead Station pump, the sealed Trunk valve | Engineering. Water, power, gas, heat. |
| **The Reach: Blackstone Cuts** (procedural) | Dry, mineral-rich, ruined industry | Rust and amber ore glints, harsh old work-lights, Knapper tunnels | Ore, brass scrap, glowglass, ruins and lore, Grist's people |
| **The Reach: Ember Vents** (procedural) | Geothermal | Orange uplight, heat shimmer, steam | Thermal ore, emberroot cuttings, heat hazard |
| **The Reach: The Sump** (procedural) | Cold, flooded, gas pockets | Blue-violet dark, pale fungus, still black water | Bellcap spores, danger, the Trunk Line chamber (critical path) |

### 3.4 Time and environmental cycles
* **Day** = one *Wake*. 06:00 Wake → 12:00 Bloom (glowroots brightest) → 18:00 Dimming → 22:00 Hush
  (lamps on, night creatures) → 02:00 the player is exhausted and wakes at home. ~14 real minutes per day.
  There is no stamina bar. Time gives rhythm, not pressure.
* **The Breath:** every third day the Deep exhales. Gas from below rises through vents, and the next
  day it inhales. Exhale days are when sourgas reaches the farm if your vents are badly placed.
* **Tremors:** rare tectonic shifts, chosen by the Event Director (one guaranteed in the MVP arc). They
  crack pipes, open new caves, collapse tunnels, release gas pockets.
* **Quietlight** (community event, once in MVP): Wick puts out every lamp for one Hush to watch
  the grove bloom. The bloom's strength depends on air quality and the lampmoth population. Odile wants
  the market lamps on; Hesper wants them dark. They argue whether or not you take a side.

### 3.5 Materials taxonomy
Every material exists to *enable* something specific. No generic iron or gold.

| Material | Source | Enables |
|---|---|---|
| **Glowbeet** | Crop | Food (Mags buys), biofuel for the Burner, light when mature |
| **Moss Fiber** | Cave Moss crop | Filters, wire insulation, insulation panels |
| **Sulfur** | Sulfur Fern crop (from sourgas) | Filter pads, fertiliser |
| **Ember Resin** | Emberroot crop (needs heat) | Seal gum (pipe repair), high-grade fuel |
| **Bellcap** | Bellcap crop (needs darkness, fruits at Hush) | Delicacy food, Quietlight stew |
| **Blackstone** | Mined in the Reach | Machine housings, insulation |
| **Brass Scrap** | Salvaged from ruins | Pipes, wire, fittings (the backbone of engineering) |
| **Glowglass** | Crystals in the Reach | Lamps, lenses, turbines |
| **Thermal Ore** | Ember Vents | Heat cells (batteries), heat exchangers |
| **Governor Coil** | One per world, in a ruin | The Station 7 pump repair (story item) |
| Crafted: Pipe Section, Wire Coil, Filter Pad, Seal Gum, Fertiliser | Workbench | — |
| Fluids/gases: water, fresh air, stale air, **sourgas**, **damp** (marsh gas) | Simulation | — |

Currency: **glims**, tiny beads of glowglass. Prices are low numbers (a glowbeet is ~6 glims).

---

## 4. Characters (NPC bible)

Every resident has: role, schedule, preferences, fears, goals, contradictions, environmental
tolerance, a music motif, a voice timbre, and a set of *values* that decide which of your deeds they
notice. Full sheets live in `data/npcs/*.json`; the character essentials follow.

### 4.1 Barnaby Coil — the mechanic who sealed the door
* **Silhouette:** tall and stooped, with a long dark oilskin coat, long arms and a tool roll at the hip. A
  **cracked brass breathing helmet** with a round faceplate. A thread of glowing cyan moss grows in
  the crack. Two pale eye-glints show behind the glass and change shape with emotion.
* **Palette:** coat charcoal-violet, brass helmet with verdigris, cream gloves, cyan moss accent.
* **Role:** Wick's unofficial mechanic. Gives the player the **plumb-glass**, an old crew
  surveying lens that shows the world in cross-section. This is the diegetic reason the engineering
  view exists. He teaches pipes and wire, and gates the Station 7 restoration.
* **Personality:** dry, precise, quietly funny. Has opinions and states them once. Not depressed;
  tired in a way that's become a personality. Fixes other people's water lines at night and denies it.
* **Regret:** eleven years ago, during the Sump flood, he sealed the Trunk valve to save Wick.
  His crew partner **Wren** was down-line. Half the town thinks he did the right thing. He isn't sure.
* **Contradiction:** cynical about Wick and indispensable to it.
* **Likes:** moss tea, well-made tools, honesty, quiet machines. **Dislikes:** waste, rattling pumps,
  people who say "should be easy".
* **Fears:** floods, the Trunk valve, being needed.
* **Values (what he notices):** competent engineering (+respect), keeping your word (+trust), waste
  and sloppy leaks (−respect), endangering people (+fear, −trust).
* **Environmental tolerance:** high (helmet), so pollution doesn't hurt him, but he *notices* it professionally.
* **Schedule:** Wake: tea at the annex → workshop → midday rounds of the pipe-heads → Lantern House
  at Dimming (sits alone) → Hush: "night rounds" (secretly mending lines).
* **Motif:** muted brass over low percussion, ending unresolved on a suspended 4th.
* **Voice blip:** muffled low reed through a helmet (band-passed).
* **Arc (MVP):** stranger → colleague → confidant. Ends at the Trunk valve.

### 4.2 Odile Brask — the quartermaster who wants Wick to grow
* **Silhouette:** short, square-shouldered, in a long brass-buttoned waistcoat over a work dress, with a
  ledger always under one arm and spectacles pushed up into tight grey braids.
* **Role:** runs **the Exchange** (market). Sets prices, sells schematics (the Burner), funds projects.
* **Wants:** Wick to trade with the down-river settlement for medicine. The damp season makes the
  children cough every year, and trade means doctors. **She is not wrong.**
* **Contradiction:** a hard bargainer who secretly carries half the town on credit.
* **Values:** productivity and output (+respect), reliability (+trust), sentimentality about moss (mild eye-roll).
* **Fears:** another winter like the one that took her brother.
* **Motif:** plucked strings over a ticking, clockwork pulse.

### 4.3 Hesper Mott — the moss-tender who loves the grove too much
* **Silhouette:** lanky and barefoot, with a patchwork shawl covered in pinned specimen jars, wild hair full of
  moss, and stained green hands.
* **Role:** tends the moss beds at the lake, studies organisms, teaches Filter Pads, gives Bellcap
  spores, and leads Quietlight.
* **Wants:** keep the grove "in balance." She opposes *all* machinery on principle, including machines that would
  help. **She is not always right:** her "natural balance" is itself an engineered system, and the reveal
  undercuts her worldview. She also refuses to cull rock-lice that eat everyone's moss.
* **Contradiction:** preaches balance; her own hut is chaos.
* **Values:** clean air and restoration (+affection), pollution (+resentment), curiosity about
  organisms (+respect).
* **Environmental tolerance:** low. Sourgas makes her ill and she stays indoors on bad-air days.
* **Motif:** soft bowed strings and glass harmonica.

### 4.4 Mags Pellow — the cook who hears everything
* **Silhouette:** round and sturdy, sleeves rolled, a huge ladle, a steaming apron. Strong forearms.
* **Role:** runs **the Lantern House** (food, the gathering place). Buys food. **Gossip hub**:
  every Dimming, notable memories spread through her to the rest of town.
* **Contradiction:** relentlessly cheerful host; privately counting the food stores every night.
* **Values:** community (+affection), sharing food (+trust), hoarding (+resentment).
* **Motif:** warm accordion-like reed with a waltz lilt.

### 4.5 Grist — a Knapper (not human)
* **Silhouette:** huge, slow, stone-grey and hunched, with a crystalline back ridge. It walks on its knuckles
  and its eyes are two small amber lights. It visits Wick on market days through the Reach tunnel.
* **Role:** trades ore and glowglass. Knappers eat rock and hear through vibration.
* **Contradiction:** terrifying to look at; timid. Speaks in short, odd, careful sentences.
* **Environmental tolerance:** *noise.* Running machines near the Reach tunnel hurt it. Loud
  industry makes Grist stop coming, and ore prices rise. (NPC tolerance → economy.)
* **Motif:** stone marimba.

### 4.6 The player
A surface salvage-diver. Rope coil on one shoulder, oilcloth cape, a **headlamp** (the player's own
dynamic light), heavy boots. Named on New Game; NPCs mostly say "topper." No gendered pronouns
are ever used for the player.

### 4.7 Relationship model
Hidden axes per NPC, each in [−100, 100]:
`trust`, `respect`, `affection`, `resentment`, `fear`, `shared` (shared history).
Deeds modify different axes according to each NPC's **values**. The relationship is *displayed*
only as a short, changing descriptive phrase in the journal ("Barnaby: *respects your work; doesn't
trust you yet*"), not as numbers or hearts.

**Memory:** `{id, subject, sentiment, importance, day}`. Importance decays daily; memories under a
floor are forgotten unless flagged `lasting`. Dialogue rules can test memories. Mags spreads
memories with importance ≥ 3 to everyone at Dimming (at reduced importance), so you don't need to
talk to everyone for news to travel.

---

## 5. Core systems

### 5.1 The Undercroft cross-section (engineering)
A grid slice under Wick (48 × 24 cells): 10 rows of cavern air above ground, the surface row (farm
plots, house footings, the well), then soil, clay, rock, the cistern, the dead Station pump, the
spring, a geothermal seam, a sealed sourgas pocket, and the Trunk valve at the bottom.

**Simulated per cell (4 Hz):**
* **Gas:** amounts of `fresh`, `stale`, `sour`, `damp`. Diffusion; *buoyancy* (sour and stale
  sink, damp rises, hot air rises); top row exchanges with the open cavern.
* **Water:** compressible-mass cellular automaton. It falls, spreads, and rises only under pressure. Water
  pushes gas out of the cells it fills.
* **Heat:** temperature per cell (solid or open), conduction by material (rock, soil, water, metal, insulation).
* **Moisture:** soil holds moisture, wicking from adjacent water. Topsoil moisture *is* the farm's water.

**Networks (1 Hz, solved per connected component, recomputed only when topology changes):**
* **Power (wires):** producers, consumers, batteries; satisfaction = supply/demand; wire capacity →
  *overload* (wire heats, then burns out).
* **Water (pipes):** pumps/taps draw from cells or tanks; consumers get proportional share;
  pipe throughput cap; **broken pipes leak into the CA grid**. Leaks are floods.
* Gas and heat aren't networks. They're fields. Machines read and write them at their cells.

**Machines (data-driven):** each declares size, build cost, ports, inputs, outputs, field emissions,
operating ranges, and status messages. Status is always one human-readable reason:
*No power · No water · No fuel · Output full · Too hot · Choking on gas · Broken · Flooded*.

| Machine | In → Out | Side-effects (the interesting part) |
|---|---|---|
| Hand Pump | effort → water | Free, slow, manual |
| Glowbeet Burner | fuel → **power 40** | **heat + sourgas**. Cheap and strong. Odile's choice |
| Drip Turbine | falling water → **power 12** | Clean. Needs pipework and height. Hesper's choice |
| Electric Pump | power 15 + water source → pressure | Drains what it draws from |
| Sprinkler | water → topsoil moisture | Automates watering. Over-watering floods the plot |
| Moss Scrubber | power 10 + water + filter pad → removes sour/stale | Makes sludge (needs emptying or a compost vat) |
| Vent Fan | power 6 → moves gas | Where you vent is a decision with neighbours |
| Glow Lamp | power 4 → light | Crops need light. Moths come to light |
| Heat Cell (battery) | stores power | Gets hot when charging |
| Compost Vat | sludge + water → fertiliser | Closes the waste loop |
| Heat Exchanger | moves heat from hot rock to surface | Warms emberroot beds. Overheats glowbeets if overdone |
| Station 7 Pump (story) | power 60 + governor coil + seals | The finale |

### 5.2 Farming
Plots on the surface row. Each crop defines ranges for **light, moisture, temperature, sourgas** and
growth time. Growth rate = product of per-condition factors (1 inside range, falling outside). A
crop's *health* drops while badly out of range, and a dead crop leaves a husk. Inspecting a crop shows
growth, water, health, expected harvest, and *which condition is wrong*, in words ("too cold").

| Crop | Days | Niche | Gives | System hook |
|---|---|---|---|---|
| Glowbeet | 3 | warm, moist, lit | food, fuel | **Emits light** when mature (lights your farm) |
| Cave Moss | 2 | damp, cool, any light | fiber | **Scrubs stale air** in its column |
| Sulfur Fern | 3 | tolerates sourgas | sulfur | **Eats sourgas**. Turns pollution into material |
| Emberroot | 4 | **hot** (needs heat source) | resin | Wants to live next to your machines |
| Bellcap | 3 | **dark**, damp | delicacy | Fruits only at Hush; light kills it |

Farm layout thus becomes an engineering problem. Emberroot goes by the Burner's heat, Bellcap in the
shade of the house, ferns downwind of the exhaust. Lampmoths (drawn by light, repelled by sourgas)
pollinate glowbeets for bonus yield.

### 5.3 Exploration — the Reach
Generated from the world seed: a graph of 7–9 caverns in three depth tiers. Each cavern is a 3D
diorama area with biome chosen by depth/heat/moisture rules, resource nodes per biome rules, a
guaranteed walkable path between exits, one ruin vignette per tier (environmental storytelling +
a lore fragment), creatures, hazards, and the **Trunk chamber** guaranteed on the deepest tier.
The Tremor event rewires the graph: one passage collapses, a new one opens, ore is exposed.

**Hazards and counterplay:** sourgas pockets (respirator / hold breath; a *Breath* meter
appears only in bad air), heat (Ember Vents: go at Hush when vents quiet, or carry a cooled flask),
darkness (headlamp upgrade), flood (high ground), cave-ins (tremors). There's no health bar. Running out of
breath means you black out and wake in Wick, carried home by someone who remembers doing it.

**Creatures:** lampmoths (light-seeking pollinators, killed off by bad air), rock-lice (eat moss,
breed when moss beds grow), gulpers (Sump water. They bump you back, avoid them; they clog pump
intakes if you pump from the Sump).

### 5.4 Economy
Two buyers (the Exchange and the Lantern House) with per-item **stock** that decays toward
equilibrium daily. Price = base × scarcity (stock vs. target) × quality (food grown in sourgas sells
lower) × Grist availability for ores, clamped to [0.5×, 2×]. Selling 40 glowbeets in one day
visibly drops the price, and it recovers over days. Odile reveals the trend in words, not graphs.

### 5.5 Consequence: the deed ledger
`GameState.history` accumulates *deeds*: `pollution_emitted`, `water_restored`, `industrial_power`,
`clean_power`, `moss_beds_damaged`, `ecosystem_restored`, `community_help`, `hoarding`,
`automation`. Deeds generate **memories** for NPCs who witness them (by location, values or
gossip). Reputation emerges from memories and axes. There is never a "+10 good" popup. The only UI
for this is a single soft line when someone *takes note* ("Hesper noticed.").

### 5.6 Dialogue
Rule-based, most-specific-match (Ruskin) with priority tiers (Hades): `story` > `reactive` >
`ambient`. Lines and conversations have **criteria** over facts (time, place, relationship axes,
memories, quest stage, pollution, weather/Breath, NPC mood), optional **choices**, and **effects**
(axes, memories, flags, items, quest stages, events). Conversations are short. Nobody
explains mechanics. They talk about what the mechanics *did*.

### 5.7 Event Director
Every in-game hour, it evaluates authored event cards against state: `conditions`, `weight`,
`cooldown`, `intensity`. It keeps a tension value with a calm window after any crisis. Cards include
pipe stress fractures (more likely under high pressure), sourgas surges on Exhale days, a lampmoth
swarm when air is clean and lamps are lit, Grist visiting, a gulper clogging an intake, Hesper
falling ill in bad air, and the scripted-but-conditioned Tremor.

### 5.8 Tools
Toolbelt (cycle with Q): **Hands** (interact, pick up), **Tiller** (prepare and plant), **Can**
(water, refill at water), **Hammer** (mine, break rubble), **Wrench** (repair, rotate, deconstruct). The
**Plumb-glass** (from Barnaby) opens the cross-section from anywhere in Wick.

### 5.9 Crafting
A dozen recipes, each solving one problem. Some are discovered: pipes and wire come from Barnaby, filter pads
from Hesper, the Burner schematic from Odile (bought), the Drip Turbine from a crew schematic in a
ruin, the Respirator from Barnaby *only if he trusts you*. Experiment: combining sulfur and
bellcap at the bench reveals a fertiliser-like "spore mash" not listed anywhere.

---

## 6. The first 30 minutes (beat sheet)

| # | Beat | Teaches (without saying so) |
|---|---|---|
| 1 | **Black.** Winch creak, cable snap, a long fall in sound only. Fade in at the shaft bottom in the grove's edge. Headlamp flickers. | — |
| 2 | Only one direction has light. Walking toward it, glowroots brighten as you pass (they react to warmth). | Movement; light matters |
| 3 | The path opens onto **Wick**: the camera slowly pulls back to reveal lanterns, the lake and the dead pump hall. Music enters. | Sense of place |
| 4 | At the well, Barnaby is swearing politely at a hand pump that gives nothing. First talk: he names you "topper," points you to the abandoned **Lease** ("Tolley went down-line. Doesn't need it.") | Interact; NPC voice |
| 5 | The Lease: a dark, cold, broken house; wild moss; a seed tin with glowbeets. Plant. The soil is dry. The can is empty. The well is dry. | Farming; the problem |
| 6 | Barnaby has traced it: "Dry from here to the cistern. Something below's drinking it." Hands you the **plumb-glass**. "Look at it the way the pipe sees it." | — |
| 7 | **The cut.** The camera splits the world open and swings down. You see the crack in the old feeder pipe, water spraying into a pocket, the cistern full but cut off. | Engineering view |
| 8 | Repair the segment (he gives two pipe sections). Water visibly runs; the pump coughs; the pocket drains, and **reveals an old bricked door** in the Undercroft. | Building; consequence; curiosity |
| 9 | Water your beets. They visibly perk up overnight. | Feedback loop |
| 10 | The cistern level is now *falling*. Refilling it needs a powered pump, so you need power. Odile offers a Burner on credit; Hesper (at the lake) talks about a turbine on the spring; Barnaby notes the hand pump "builds character." | A real choice with no right answer |
| 11 | Dimming at the Lantern House: people already know what you did. Mags tells it back to you, slightly wrong. | Information spreads |
| 12 | Sleep. At night, the pipes knock: three, two, three. | Hook |

**By the end of the first hour** you have built power, chosen how dirty it is, seen the farm react
to your air, visited the Reach, met Grist, found a ruin with a Station 7 crew log, and been
asked by Barnaby to look at the old pump "just look."

---

## 7. Progression (MVP arc, ~2–3 hours, 6–8 in-game days)

| Day | Threads | Systems emphasised |
|---|---|---|
| 1 | Dry Well → Power choice | Water network, building |
| 2 | First harvest, market; Reach tier 1 (Blackstone); Grist | Economy, exploration |
| 3 | **Exhale**: sourgas reaches the farm if vents are careless; Hesper's beds; the Burner's heat makes emberroot possible | Gas, heat, crops-as-instruments |
| 4 | Barnaby's night rounds (relationship event); ruin with crew schematic; scrubber or ferns | Relationships, crafting |
| 5 | **Quietlight** festival: NPC conflict over lamps; the bloom reflects your air | Consequence made visible |
| 6 | **The Tremor**: pipes crack, the sour pocket opens, the Sump floods, the Trunk chamber opens in the Reach | Crisis, failure as story |
| 7+ | **Station 7**: governor coil from the Trunk chamber, seals, 60 power; the valve decision; **the knock** | Everything at once |

Outcomes differ: valve opened or kept shut, which power you chose, the state of the moss beds,
who trusts you. Each produces different dialogue and different post-ending circumstances
(Odile's trade plans, Hesper's beds, Grist's visits, Barnaby moving back into the pump hall or not).

---

## 8. Visual bible

* **Technique:** true 3D diorama (cells = 1 m, 16 texels/m, nearest filtering), billboard pixel
  sprites (16 px/m), perspective camera with narrow FOV (~32°) tilted ~42°, tilt-shift DOF,
  filmic tonemapping, restrained glow, exponential fog, a custom final grade pass (vignette, grade by
  place and pollution, subtle grain). Characters stay crisp; light stays smooth.
* **Palette** (`assets/palette.json`): deep charcoal `#121116`, basalt `#23222b`, slate `#34333f`,
  earth `#4a3d33`, clay `#6b5443`, brass `#9c7a3c`/`#c9a25a`, verdigris `#4f8c7e`, moss
  `#5f7d3a`/`#8fa64c`, amber `#e8a33d`, cream `#efe3c2`, glow cyan `#56e0d4`/`#2fb3b0`, violet
  `#8d6bd6`/`#5a3f8f`, danger `#e2552c`, sour `#b5b84a`. **Brightness means something:** cyan =
  living, amber = people, violet = deep/unknown, sour green = harm, red-orange = danger.
* **Sprites:** selective outlines tinted from the adjacent fill; three-tone hue-shifted ramps;
  strong silhouettes readable at 1×; 4-direction (side mirrored), idle breathing, walk, work, talk,
  and emotion states. Barnaby's emotion lives in his faceplate glints.
* **Lighting by place:** Wick = amber/cyan complement; Reach-Blackstone = rust + harsh white;
  Ember Vents = orange uplight; Sump = cold violet; polluted = sickly desaturation and haze.
* **Life at rest:** water ripples, glowroots pulse, moss sways, dust motes drift, machines vibrate, and lamps
  flicker a little.
* **The cut:** the ground in front of the cut line sinks and dissolves into falling earth, and the camera
  lowers *through* the strata (a brief band of passing soil layers) and settles side-on.

## 9. Audio bible

* **Harmonic language:** D Dorian with an occasional raised 4th, which sounds warm and slightly off.
  The world's signature is the **Breath swell**, a harmonium chord that inhales and exhales over
  eight seconds.
* **Instruments (all synthesised in-house):** tine harp (plucked metal tines, inharmonic),
  harmonium/reed pad that breathes, bowed glass, muted brass (Barnaby), soft bowed strings
  (Hesper), clockwork pulse (Odile), stone marimba (Grist), pipework percussion in 7/8 (engineering),
  sub drones and filtered noise (the Deep).
* **Adaptive music:** each cue is a set of synchronized stems whose gains follow game state
  (place, time, engineering view, crisis, nearby character). Cue changes crossfade on bar
  boundaries. Crisis applies a low-pass and saturation on the music bus and thins the stems.
* **Ambience:** grove (drips, soft insects, distant water), Undercroft (pipe ticks, hum), Blackstone
  (low wind, metal resonance), Vents (rumble, steam), Sump (cold drips, bubbles).
* **SFX language:** soft, woody and metallic, never "mobile clicky." UI sounds are small glass/brass taps.
  Machines are identifiable by ear (Burner chug, pump heartbeat, scrubber hiss, turbine whir).
* **Voices:** per-character blips derived from their motif instrument. Barnaby's is muffled through the
  helmet.

## 10. UX
* **HUD:** nearly nothing. Time and day appear as a small brass dial, the active tool as an icon, and a breath meter
  only in bad air. Context prompts appear in the world near the target.
* **Notes:** the journal is the player's salvager notebook (threads, people, places, recipes,
  observations). Threads are one line each.
* **Engineering UI:** build palette, placement preview (valid/invalid/connected/powered), hover
  inspection (inputs, outputs, status reason, efficiency), overlays (power, water, gas, heat,
  pollution), time controls (pause / 1× / 3×). Pauses automatically while a build menu is open.
* **Menus:** keyboard, mouse and gamepad navigable. Settings: graphics, audio, controls, accessibility,
  saves.
* **Accessibility:** full remapping, five volume buses, screen-shake toggle and scale, flash
  intensity, text speed, font scale, readable-font option (Atkinson Hyperlegible), high-contrast
  UI, overlays that use pattern plus colour, captions for story-relevant sounds.

## 11. MVP scope

| Item | Target | Notes |
|---|---|---|
| Settlement | Wick (1) | Hand-authored |
| Home | The Lease (1) | Upgradable: lights, bench, bed, storage, decorations |
| Farm | 12 plots | |
| NPCs | 5 | Barnaby full arc; Odile, Hesper meaningful threads; Mags hub; Grist trader |
| Biomes | 4 | Grove, Blackstone, Ember Vents, Sump |
| Resources | ~14 | §3.5 |
| Machines | 11 + Station pump | §5.1 |
| Crops | 5 | §5.2 |
| Infrastructure crisis | The Tremor (and the opening Dry Well) | |
| Environmental event | The Breath / Exhale; Quietlight | |
| Mystery | Station 7 and the knock | |
| Relationship arc | Barnaby | |
| Procedural | The Reach from seed | |
| Save/load | Versioned JSON, 3 slots, autosave on sleep | |

**Explicitly out of scope:** romance, combat, multiple settlements, seasons, fishing, multiplayer,
dozens of recipes.

## 12. Future scope (after the MVP proves itself)
Lower stations (8–12) as new biomes and settlements with their own politics; Trunk Line travel;
automation logic gates (sensor → condition → machine); creature husbandry; trade routes; deeper
heat engineering (steam); seasons of the Breath; more residents with intertwined arcs; the surface
question.

---

## 13. Design critique (and what was changed)

**What feels generic?**
* *Planting, watering, selling* is the most familiar loop in the genre. → **Changed:** crops are
  defined by environmental niches, not seasons; the can is a stopgap that sprinklers replace;
  crop health reads out the air. Watering by hand is deliberately the *worst* way to water.
* *A mysterious ancient civilisation.* → **Changed:** no prophecy, no relics of power. The ancients
  were engineers and the "ruins" are maintenance infrastructure. The mystery is mechanical (what is
  this machine for, who still runs it) and personal (Barnaby's sealed valve).

**What feels derivative?**
* A side-view gas sim screams one particular colony game. → **Changed:** a single slice under
  *your village* instead of a sprawling base; mixtures, not one-gas-per-tile; no worker management;
  the gas matters because it reaches *Hesper's moss* and *your beets*. The cut transition ties it to
  the diorama.
* A cook who gossips and a moody mechanic are archetypes. → **Changed:** each has a contradiction tied
  to the systems (Mags privately rationing food responds to the market; Barnaby's night rounds are
  visible in the pipe network as repaired segments you didn't fix).

**What is too complicated?**
* Five fields (gas, water, heat, moisture, light) plus two networks plus economy plus relationships.
  → **Changed:** progressive disclosure. Day 1 shows only water. Power arrives on day 1–2. Gas becomes
  relevant on the first Exhale (day 3). Heat stays implicit (crop/machine messages) until emberroot.
  Overlays and plain-language status make the hidden state legible. Damp (marsh gas) is limited to
  the Sump in the MVP.
* Liquids beyond water. → **Cut** for MVP (brine kept only as flavour).

**What is boring?**
* Walking back and forth to water. → Sprinklers by day 2; the farm sits on top of the cistern.
* Waiting for crops. → Days are short (~14 min), with plenty to do in parallel (Reach, engineering, people).

**What would make players quit?**
* Not knowing what to do → one-line threads in Notes; residents mention the next thread naturally.
* Feeling punished by consequences → failures create *stories and recoveries*, never game-overs; pollution
  is fixable; relationships can recover.
* A slow opening → the first engineering cut happens within ~6 minutes.

**What is technically risky?** → see `RISKS.md`.

**What is unnecessarily expensive?**
* Full 3D modelling. → Everything is built from textured cells, boxes and billboards generated by
  code. No sculpted meshes.
* Large procedural worlds → small cavern areas (≈32×24 cells), loaded one at a time.
* Volumetric fog → optional (High/Ultra only). Gas is shown with cheap shader quads that work on every renderer.

**What could become the identity?**
* **The cut.** Village life split open to show its plumbing, cozy on top and machine underneath.
* **Crops as instruments.** Your farm is a readout of your air.
* **Barnaby and the knock.** A deeply human story told through a pipe.
* **Light is progress.** A dark world that you, specifically, made glow.

### Revision summary
1. Engineering view made **diegetic** (Barnaby's plumb-glass) and **spatial** (cut line under the farm band).
2. Gas model switched from one-substance-per-tile to mixtures with species buoyancy.
3. Crops redefined around niches; added Emberroot (heat) and Bellcap (darkness) so every field has a crop that cares.
4. No health bar; breath meter only in hazards; blackouts become memories.
5. Festival redesigned as a *lights-off* event so it interacts with lighting, pollution and NPC conflict.
6. Scope cut: liquids other than water, combat, romance, seasons, multiple settlements.
