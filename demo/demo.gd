extends Control
## Visible, measurable demo of Saltmire Save.
## Runs each feature live and prints the REAL numbers to the screen.
##
## [FIX 1.0.1] This file used to call `Save.write(...)` directly. `Save` is an
## autoload that only exists AFTER the plugin is enabled — but Godot parses every
## .gd file the moment the zip is extracted into a project, which is BEFORE anyone
## has had a chance to enable anything. Result: a wall of "Identifier Save not
## declared in the current scope" errors on first contact with a PAID product,
## with the buyer having done nothing wrong.
## Found while fixing the same defect in the free Lite edition, which a user
## reported on itch (HYPER10N.EXE, 2026-08-03). Same root cause, both editions.
##
## The fix resolves the singleton at RUNTIME, so the parser never needs the name.

@onready var log_label: RichTextLabel = $Panel/Margin/Log

## Resolved at runtime, never seen by the parser. Null if the plugin is disabled.
var _save: Node = null

func _ready() -> void:
	log_label.clear()
	log_label.bbcode_enabled = true
	_line("[b]⚡ Saltmire Save — live proof[/b]\n")

	_save = get_node_or_null("/root/Save")
	if _save == null:
		# Tell the buyer exactly what to do, instead of crashing on a null.
		_line("[color=#FFD86B]The [b]Save[/b] autoload isn't registered yet.[/color]")
		_line("Enable it in [b]Project Settings -> Plugins -> Saltmire Save[/b],")
		_line("then run this scene again.")
		return

	await get_tree().create_timer(0.4).timeout
	_core()
	await get_tree().create_timer(0.7).timeout
	_encryption()
	await get_tree().create_timer(0.7).timeout
	_compression()
	await get_tree().create_timer(0.7).timeout
	_recovery()
	await get_tree().create_timer(0.7).timeout
	_migration()
	await get_tree().create_timer(0.7).timeout
	_line("\n[color=#7CFC98][b]All real. All measured.[/b][/color]")
	# The demo goes through a variable; your own code doesn't have to.
	_line("[color=#9AA0A6]In your game it is just: Save.write(\"slot1\", {\"hp\": 80})[/color]")

func _line(t: String) -> void:
	log_label.append_text(t + "\n")

func _ok(t: String) -> void:
	_line("[color=#7CFC98]✔[/color] " + t)

func _core() -> void:
	_save.write("player", {"hp": 80, "level": 3})
	var d = _save.read("player")
	_ok("write + read in one line — hp=%d level=%d" % [d.hp, d.level])

func _encryption() -> void:
	_save.encryption_key = "s3cr3t"
	_save.write("secure", {"gold": 999, "flag": "TOPSECRET"})
	var bytes := FileAccess.get_file_as_bytes("user://saltmire_saves/secure.sav")
	var leaked := bytes.get_string_from_utf8().find("TOPSECRET") != -1
	_ok("[b]encryption[/b] — 'TOPSECRET' on disk? %s (%d encrypted bytes)" % ["YES ✗" if leaked else "NO ✓", bytes.size()])
	_save.encryption_key = ""

func _compression() -> void:
	_save.compress = true
	var big := {}
	for i in 400:
		big["e%d" % i] = {"name": "item", "qty": i, "tag": "repeated"}
	_save.write("world", big)
	var st := _save.stats()
	_ok("[b]compression[/b] — %d → %d bytes ([color=#FFD86B]%.1f%% saved[/color])" % [st.last_raw_bytes, st.last_stored_bytes, st.compression_saved_pct])
	_save.compress = false

func _recovery() -> void:
	_save.backups = 2
	_save.write("run", {"chapter": 1})
	_save.write("run", {"chapter": 2})
	var f := FileAccess.open("user://saltmire_saves/run.sav", FileAccess.WRITE)
	f.store_string("GARBAGE"); f.close()
	var r = _save.read("run")
	_ok("[b]corruption recovery[/b] — main file trashed → healed from backup (chapter=%d)" % r.chapter)

func _migration() -> void:
	_save.current_version = 1
	_save.write("legacy", {"coins": 10})
	_save.current_version = 3
	_save.register_migration(1, func(x): x["gold"] = x.get("coins", 0); x.erase("coins"); return x)
	_save.register_migration(2, func(x): x["prestige"] = 0; return x)
	var m = _save.read("legacy")
	_ok("[b]schema migration[/b] — v1 save auto-upgraded to v3 (coins→gold=%d, +prestige)" % m.gold)
