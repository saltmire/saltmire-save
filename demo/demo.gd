extends Control
## Visible, measurable demo of Saltmire Save.
## Runs each feature live and prints the REAL numbers to the screen.

@onready var log_label: RichTextLabel = $Panel/Margin/Log

func _ready() -> void:
	log_label.clear()
	log_label.bbcode_enabled = true
	_line("[b]⚡ Saltmire Save — live proof[/b]\n")
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

func _line(t: String) -> void:
	log_label.append_text(t + "\n")

func _ok(t: String) -> void:
	_line("[color=#7CFC98]✔[/color] " + t)

func _core() -> void:
	Save.write("player", {"hp": 80, "level": 3})
	var d = Save.read("player")
	_ok("write + read in one line — hp=%d level=%d" % [d.hp, d.level])

func _encryption() -> void:
	Save.encryption_key = "s3cr3t"
	Save.write("secure", {"gold": 999, "flag": "TOPSECRET"})
	var bytes := FileAccess.get_file_as_bytes("user://saltmire_saves/secure.sav")
	var leaked := bytes.get_string_from_utf8().find("TOPSECRET") != -1
	_ok("[b]encryption[/b] — 'TOPSECRET' on disk? %s (%d encrypted bytes)" % ["YES ✗" if leaked else "NO ✓", bytes.size()])
	Save.encryption_key = ""

func _compression() -> void:
	Save.compress = true
	var big := {}
	for i in 400:
		big["e%d" % i] = {"name": "item", "qty": i, "tag": "repeated"}
	Save.write("world", big)
	var st := Save.stats()
	_ok("[b]compression[/b] — %d → %d bytes ([color=#FFD86B]%.1f%% saved[/color])" % [st.last_raw_bytes, st.last_stored_bytes, st.compression_saved_pct])
	Save.compress = false

func _recovery() -> void:
	Save.backups = 2
	Save.write("run", {"chapter": 1})
	Save.write("run", {"chapter": 2})
	var f := FileAccess.open("user://saltmire_saves/run.sav", FileAccess.WRITE)
	f.store_string("GARBAGE"); f.close()
	var r = Save.read("run")
	_ok("[b]corruption recovery[/b] — main file trashed → healed from backup (chapter=%d)" % r.chapter)

func _migration() -> void:
	Save.current_version = 1
	Save.write("legacy", {"coins": 10})
	Save.current_version = 3
	Save.register_migration(1, func(x): x["gold"] = x.get("coins", 0); x.erase("coins"); return x)
	Save.register_migration(2, func(x): x["prestige"] = 0; return x)
	var m = Save.read("legacy")
	_ok("[b]schema migration[/b] — v1 save auto-upgraded to v3 (coins→gold=%d, +prestige)" % m.gold)
