extends SceneTree
## Headless selftest for Saltmire Save. Run:
##   godot --headless --script selftest.gd
## Exits code 0 on PASS, 1 on FAIL.
## Every PRO feature is proven with a MEASURABLE assertion.

func _init() -> void:
	var fails := 0
	var S = load("res://addons/saltmire_save/save.gd").new()
	get_root().add_child(S)
	# fresh sandbox
	for s in S.list_slots():
		S.erase(s)

	# --- CORE: round-trip ----------------------------------------------------
	S.write("slot1", {"hp": 80, "level": 3})
	var d = S.read("slot1")
	if d != null and d.get("hp") == 80 and d.get("level") == 3:
		print("PASS core round-trip (hp=%d level=%d)" % [d.hp, d.level])
	else:
		print("FAIL core round-trip ", d); fails += 1

	if S.has("slot1") and not S.has("nope"):
		print("PASS has() correct")
	else:
		print("FAIL has()"); fails += 1

	# --- CORE: list + erase --------------------------------------------------
	S.write("slot2", {"x": 1})
	if S.list_slots().size() == 2:
		print("PASS list_slots (2)")
	else:
		print("FAIL list_slots ", S.list_slots()); fails += 1
	S.erase("slot2")
	if not S.has("slot2"):
		print("PASS erase()")
	else:
		print("FAIL erase()"); fails += 1

	# --- PRO: ENCRYPTION is real (plaintext NOT on disk) ---------------------
	S.encryption_key = "s3cr3t-key"
	S.write("enc", {"password_flag": "TOPSECRET_MARKER", "gold": 999})
	var raw_bytes := FileAccess.get_file_as_bytes("user://saltmire_saves/enc.sav")
	var on_disk := raw_bytes.get_string_from_utf8()
	if on_disk.find("TOPSECRET_MARKER") == -1 and on_disk.find("999") == -1:
		print("PASS encryption: plaintext marker NOT found in %d on-disk bytes" % raw_bytes.size())
	else:
		print("FAIL encryption: plaintext leaked to disk"); fails += 1
	# correct key reads back
	var back = S.read("enc")
	if back != null and back.get("gold") == 999:
		print("PASS encryption: correct key decrypts (gold=999)")
	else:
		print("FAIL encryption: correct key failed ", back); fails += 1
	# wrong key fails to read (tamper/edit protection)
	S.encryption_key = "wrong-key"
	var bad = S.read("enc")
	if bad == null:
		print("PASS encryption: wrong key returns null (save-edit blocked)")
	else:
		print("FAIL encryption: wrong key leaked data ", bad); fails += 1
	S.encryption_key = ""

	# --- PRO: COMPRESSION is real (measurable byte reduction) ----------------
	S.compress = true
	var big := {}
	for i in 400:
		big["entry_%d" % i] = {"name": "item", "qty": i, "tag": "repeated_payload_string"}
	S.write("big", big)
	var st = S.stats()
	if st.last_stored_bytes < st.last_raw_bytes and st.compression_saved_pct > 20.0:
		print("PASS compression: %d -> %d bytes (%.1f%% saved)" % [st.last_raw_bytes, st.last_stored_bytes, st.compression_saved_pct])
	else:
		print("FAIL compression ", st); fails += 1
	var big_back = S.read("big")
	if big_back != null and big_back.size() == 400 and big_back["entry_399"]["qty"] == 399:
		print("PASS compression: round-trip intact (400 entries)")
	else:
		print("FAIL compression round-trip"); fails += 1
	S.compress = false

	# --- PRO: BACKUP + CORRUPTION RECOVERY -----------------------------------
	S.backups = 2
	S.write("prog", {"chapter": 1})
	S.write("prog", {"chapter": 2})   # bak1 now holds chapter 1
	# corrupt the main file
	var cf := FileAccess.open("user://saltmire_saves/prog.sav", FileAccess.WRITE)
	cf.store_string("GARBAGE-NOT-A-SAVE")
	cf.close()
	var rec = S.read("prog")
	if rec != null and rec.get("chapter") == 1 and S.recoveries == 1:
		print("PASS recovery: corrupt main healed from backup (chapter=%d)" % rec.chapter)
	else:
		print("FAIL recovery ", rec, " recoveries=", S.recoveries); fails += 1

	# --- PRO: SCHEMA MIGRATION -----------------------------------------------
	S.current_version = 1
	S.write("mig", {"coins": 10})            # written as v1
	S.current_version = 3
	S.register_migration(1, func(data):      # v1 -> v2: rename coins->gold
		data["gold"] = data.get("coins", 0); data.erase("coins"); return data)
	S.register_migration(2, func(data):      # v2 -> v3: add prestige
		data["prestige"] = 0; return data)
	var mig = S.read("mig")
	if mig != null and mig.get("gold") == 10 and mig.has("prestige") and not mig.has("coins") and S.migrations_run == 2:
		print("PASS migration: v1->v3 ran %d steps (gold=%d, prestige added)" % [S.migrations_run, mig.gold])
	else:
		print("FAIL migration ", mig, " ran=", S.migrations_run); fails += 1

	# --- PRO: SMART AUTOSAVE skips unchanged writes --------------------------
	S.write("auto", {"t": 0})
	var w0 : int = S.writes
	# simulate two autosave ticks with no change between them
	S._autosave_slot = "auto"
	S._autosave_cb = func(): return {"t": 1}
	S._dirty = false
	S._timer = Timer.new(); S._timer.set_meta("smart", true); S.add_child(S._timer)
	S._on_autosave()                 # should skip (not dirty)
	S.mark_dirty()
	S._on_autosave()                 # should write (dirty)
	if S.writes == w0 + 1 and S.writes_skipped == 1:
		print("PASS smart autosave: 1 write, 1 skipped (no wasted I/O)")
	else:
		print("FAIL smart autosave writes=%d skipped=%d" % [S.writes, S.writes_skipped]); fails += 1

	# --- PRO: SLOT METADATA for load screen ----------------------------------
	S.write("save_a", {"level": 7, "playtime": 3600, "name": "Hero"})
	var m = S.slot_meta("save_a")
	if m.get("level") == 7 and m.get("playtime") == 3600 and m.has("saved_at") and m.get("version") == 3:
		print("PASS slot metadata (level=%d, playtime=%d, saved_at present)" % [m.level, m.playtime])
	else:
		print("FAIL slot metadata ", m); fails += 1

	# cleanup
	for s in S.list_slots():
		S.erase(s)

	if fails == 0:
		print("\nSELFTEST PASS")
		quit(0)
	else:
		print("\nSELFTEST FAIL (", fails, ")")
		quit(1)
