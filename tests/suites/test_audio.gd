extends TestCase
## Every sound the code asks for exists, every music cue has all its stems at the same
## length, every biome has an ambience bed and every speaker has a voice.


func _sfx_exists(name: String) -> bool:
	return ResourceLoader.exists("%s%s.ogg" % [Audio.SFX_DIR, name]) or ResourceLoader.exists("%s%s_1.ogg" % [Audio.SFX_DIR, name])


func _scan(dir: String, re: RegEx, found: Dictionary) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			var text := FileAccess.get_file_as_string(dir.path_join(f))
			for m in re.search_all(text):
				found[m.get_string(1)] = f
	for d in DirAccess.get_directories_at(dir):
		_scan(dir.path_join(d), re, found)


func test_every_requested_sfx_exists() -> void:
	var re := RegEx.create_from_string("Audio\\.(?:play|play_at|ui)\\(\"([a-z0-9_]+)\"")
	var found := {}
	_scan("res://src", re, found)
	for extra in ["wire_lay", "step_soft", "step_stone", "step_wood", "step_gravel"]:
		found[extra] = "extra"
	check(found.size() > 25, "found the sound calls (%d)" % found.size())
	for name: String in found:
		check(_sfx_exists(name), "sfx '%s' (used in %s) has a file" % [name, found[name]])


func test_music_cues_complete() -> void:
	for cue: String in Audio.CUES:
		var length := -1.0
		for stem: String in Audio.CUES[cue]:
			var path := "%s%s_%s.ogg" % [Audio.MUSIC_DIR, cue, stem]
			check(ResourceLoader.exists(path), "stem %s" % path)
			if ResourceLoader.exists(path):
				var s: AudioStream = load(path)
				if length < 0.0:
					length = s.get_length()
				else:
					near(s.get_length(), length, 0.02, "%s stems share one length" % cue)


func test_biomes_have_ambience_and_npcs_have_voices() -> void:
	for b: String in Content.biomes:
		var amb := String(Content.biomes[b].get("ambience", ""))
		check(ResourceLoader.exists("%s%s.ogg" % [Audio.AMB_DIR, amb]), "ambience %s for biome %s" % [amb, b])
	for id: String in Content.npcs:
		var t := String(Content.npc(id).get("voice", {}).get("timbre", ""))
		check(ResourceLoader.exists("%svoice_%s.ogg" % [Audio.SFX_DIR, t]), "voice %s for %s" % [t, id])
	check(ResourceLoader.exists("%svoice_player.ogg" % Audio.SFX_DIR), "player voice")
