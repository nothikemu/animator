extends Node
## Global signal bus. Systems publish facts here instead of reaching into each other.

# --- Player-facing feedback -------------------------------------------------
signal toast(text: String, kind: StringName)          ## small transient message
signal noticed(npc_id: StringName, text: String)       ## "Hesper noticed." soft consequence line
signal caption(text: String, seconds: float)           ## accessibility captions for story sounds
signal prompt_changed(text: String)                     ## world interaction prompt

# --- World / state ---------------------------------------------------------
signal deed(kind: StringName, amount: float, context: Dictionary)
signal flag_changed(flag: StringName, value: Variant)
signal inventory_changed()
signal money_changed(amount: int)
signal tool_changed(tool_id: StringName)
signal area_changed(area_id: StringName)
signal area_ready(area_id: StringName)
signal world_event(event_id: StringName, data: Dictionary)
signal discovered(kind: StringName, id: StringName)

# --- Simulation ------------------------------------------------------------
signal sim_topology_changed()                           ## conduits or machines added/removed
signal machine_changed(machine_id: int)
signal machine_status_changed(machine_id: int, status: StringName)
signal crop_changed(plot_index: int)
signal harvest(crop_id: StringName, amount: int)
signal grid_cells_changed(cells: Array)                  ## solid/open changes (tremor, digging)
signal light_sources_changed()

# --- Social / narrative ----------------------------------------------------
signal relationship_changed(npc_id: StringName)
signal memory_added(npc_id: StringName, memory_id: StringName)
signal thread_updated(thread_id: StringName, stage: int)
signal dialogue_started(npc_id: StringName)
signal dialogue_line(speaker: StringName, text: String, emote: StringName)
signal dialogue_choices(choices: Array)
signal dialogue_ended(npc_id: StringName)

# --- Views / UI ------------------------------------------------------------
signal view_mode_requested(mode: StringName)
signal view_mode_changed(mode: StringName)
signal ui_open(panel: StringName, data: Dictionary)
signal ui_closed(panel: StringName)
signal save_started(slot: int)
signal save_finished(slot: int, ok: bool)
signal settings_changed(section: StringName)
signal camera_impulse(strength: float)                   ## screen-shake request (scaled by settings)
signal flash(color: Color, strength: float)              ## full-screen flash (scaled by settings)
