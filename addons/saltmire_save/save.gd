extends Node
## Saltmire Save — one-line save/load for Godot 4.
##
## Lite (free, MIT): write / read / has / erase / list_slots / autosave.
## PRO: encryption, schema migration, backup + corruption recovery,
##      gzip compression, smart (dirty-flag) autosave, slot metadata.
##
## Every PRO feature reports a measurable number via `stats()` so you can SEE
## the value (bytes saved, backups kept, migrations run, writes skipped).

signal saved(slot: String)
signal loaded(slot: String)
signal recovered(slot: String)          ## emitted when a corrupt save was rescued from backup
signal migrated(slot: String, from_version: int, to_version: int)

const DIR := "user://saltmire_saves/"
const _MAGIC := 0x534D  # "SM" — file header so we can detect our own format

# ---- configuration (PRO knobs; all optional, safe defaults) ----------------
var encryption_key: String = ""         ## if set, files are AES-encrypted on disk
var compress: bool = false              ## gzip payloads before writing
var backups: int = 2                    ## rotating .bak copies kept per slot (corruption safety net)
var current_version: int = 1            ## your game's current save schema version

# ---- measurable stats (proof of value) -------------------------------------
var last_raw_bytes: int = 0             ## JSON size before compression/encryption
var last_stored_bytes: int = 0          ## bytes actually written to disk
var writes: int = 0                     ## total writes performed
var writes_skipped: int = 0             ## smart-autosave writes skipped (nothing changed)
var migrations_run: int = 0
var recoveries: int = 0

var _migrations: Dictionary = {}        # {from_version:int -> Callable(data)->data}
var _dirty: bool = true
var _autosave_slot: String = ""
var _autosave_cb: Callable = Callable()
var _timer: Timer = null


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)


# ============================================================================
#  CORE / LITE
# ============================================================================

## Write `data` (Dictionary/Array/primitive) to a named slot. Returns true on success.
func write(slot: String, data) -> bool:
	var envelope := {
		"__v": current_version,
		"__t": int(Time.get_unix_time_from_system()),
		"__meta": _meta_for(slot, data),
		"data": data,
	}
	var json := JSON.stringify(envelope)
	var raw := json.to_utf8_buffer()
	last_raw_bytes = raw.size()

	var payload := raw
	var flags := 0
	if compress:
		var packed := raw.compress(FileAccess.COMPRESSION_GZIP)
		# only keep compression if it actually helped
		if packed.size() < raw.size():
			payload = _with_uint32(raw.size(), packed)  # prepend original length
			flags |= 1
	var body := _framed(flags, payload)
	last_stored_bytes = body.size()

	var path := _path(slot)
	_rotate_backups(slot)
	if not _write_bytes(path, body):
		return false
	writes += 1
	_dirty = false
	saved.emit(slot)
	return true


## Read a slot. Returns the stored data, or `null` if it doesn't exist / is unreadable.
## If the main file is corrupt, transparently recovers from the newest good backup.
func read(slot: String):
	var envelope = _read_envelope(_path(slot))
	if envelope == null:
		# corruption recovery: walk backups newest-first
		for i in range(1, backups + 1):
			var bpath := _path(slot) + ".bak%d" % i
			envelope = _read_envelope(bpath)
			if envelope != null:
				recoveries += 1
				recovered.emit(slot)
				_write_bytes(_path(slot), FileAccess.get_file_as_bytes(bpath))  # heal main
				break
	if envelope == null:
		return null
	envelope = _apply_migrations(slot, envelope)
	loaded.emit(slot)
	return envelope.get("data")


func has(slot: String) -> bool:
	return FileAccess.file_exists(_path(slot))


## Delete a slot and all its backups. Returns true if the main file existed.
func erase(slot: String) -> bool:
	var existed := has(slot)
	var d := DirAccess.open(DIR)
	if d:
		var base := slot + ".sav"
		for f in d.get_files():
			if f == base or f.begins_with(base + ".bak"):
				d.remove(f)
	return existed


func list_slots() -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(DIR)
	if d:
		for f in d.get_files():
			if f.ends_with(".sav"):
				out.append(f.substr(0, f.length() - 4))
	return out


## Lite autosave: writes `cb.call()` to `slot` every `interval` seconds.
## PRO smart mode (default): skips the write when nothing called mark_dirty().
func autosave(slot: String, cb: Callable, interval: float = 30.0, smart: bool = true) -> void:
	_autosave_slot = slot
	_autosave_cb = cb
	if _timer == null:
		_timer = Timer.new()
		add_child(_timer)
		_timer.timeout.connect(_on_autosave.bind())
	_timer.set_meta("smart", smart)
	_timer.wait_time = max(0.05, interval)
	_timer.start()


func stop_autosave() -> void:
	if _timer:
		_timer.stop()


## Call whenever game state changes; smart autosave only writes if this fired.
func mark_dirty() -> void:
	_dirty = true


func _on_autosave() -> void:
	if not _autosave_cb.is_valid():
		return
	if _timer.get_meta("smart", true) and not _dirty:
		writes_skipped += 1
		return
	write(_autosave_slot, _autosave_cb.call())


# ============================================================================
#  PRO — schema migration
# ============================================================================

## Register a migration that upgrades a save from `from_version` to the next.
## `cb` takes the `data` Variant and returns the upgraded data.
func register_migration(from_version: int, cb: Callable) -> void:
	_migrations[from_version] = cb


func _apply_migrations(slot: String, envelope: Dictionary) -> Dictionary:
	var v := int(envelope.get("__v", 1))
	var start := v
	while v < current_version and _migrations.has(v):
		envelope["data"] = _migrations[v].call(envelope.get("data"))
		v += 1
		migrations_run += 1
	if v != start:
		envelope["__v"] = v
		migrated.emit(slot, start, v)
	return envelope


# ============================================================================
#  PRO — slot metadata (for a "Load Game" screen)
# ============================================================================

## Metadata for one slot without deserializing the whole payload’s data field.
func slot_meta(slot: String) -> Dictionary:
	var envelope = _read_envelope(_path(slot))
	if envelope == null:
		return {}
	var m: Dictionary = envelope.get("__meta", {})
	m["version"] = int(envelope.get("__v", 1))
	m["saved_at"] = int(envelope.get("__t", 0))
	return m


func list_slots_meta() -> Array:
	var out: Array = []
	for s in list_slots():
		var m := slot_meta(s)
		m["slot"] = s
		out.append(m)
	return out


## Override to attach your own metadata (playtime, level, thumbnail path…).
## Default pulls a few common keys if `data` is a Dictionary.
func _meta_for(_slot: String, data) -> Dictionary:
	var m := {}
	if data is Dictionary:
		for k in ["level", "playtime", "name", "thumbnail"]:
			if data.has(k):
				m[k] = data[k]
	return m


# ============================================================================
#  Proof-of-value snapshot
# ============================================================================

func stats() -> Dictionary:
	var ratio := 0.0
	if last_raw_bytes > 0:
		ratio = 1.0 - float(last_stored_bytes) / float(last_raw_bytes)
	return {
		"last_raw_bytes": last_raw_bytes,
		"last_stored_bytes": last_stored_bytes,
		"compression_saved_pct": snappedf(ratio * 100.0, 0.1),
		"writes": writes,
		"writes_skipped": writes_skipped,
		"migrations_run": migrations_run,
		"recoveries": recoveries,
		"encrypted": encryption_key != "",
	}


# ============================================================================
#  internals
# ============================================================================

func _path(slot: String) -> String:
	return DIR + slot + ".sav"


func _framed(flags: int, payload: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(4)
	out.encode_u16(0, _MAGIC)
	out.encode_u8(2, flags)
	out.encode_u8(3, 0)  # reserved
	out.append_array(payload)
	return out


func _with_uint32(n: int, payload: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(4)
	out.encode_u32(0, n)
	out.append_array(payload)
	return out


func _write_bytes(path: String, body: PackedByteArray) -> bool:
	var f: FileAccess
	if encryption_key != "":
		f = FileAccess.open_encrypted_with_pass(path, FileAccess.WRITE, encryption_key)
	else:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("Saltmire Save: cannot write " + path)
		return false
	f.store_buffer(body)
	f.close()
	return true


func _read_bytes(path: String) -> PackedByteArray:
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	var f: FileAccess
	if encryption_key != "":
		f = FileAccess.open_encrypted_with_pass(path, FileAccess.READ, encryption_key)
	else:
		f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedByteArray()  # wrong key / unreadable
	var b := f.get_buffer(f.get_length())
	f.close()
	return b


## Returns the parsed envelope Dictionary, or null if missing/corrupt/tampered.
func _read_envelope(path: String):
	var body := _read_bytes(path)
	if body.size() < 4:
		return null
	if body.decode_u16(0) != _MAGIC:
		return null  # not our format / tampered header
	var flags := body.decode_u8(2)
	var payload := body.slice(4)
	var raw: PackedByteArray
	if flags & 1:
		if payload.size() < 4:
			return null
		var orig := payload.decode_u32(0)
		raw = payload.slice(4).decompress(orig, FileAccess.COMPRESSION_GZIP)
	else:
		raw = payload
	var text := raw.get_string_from_utf8()
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary) or not parsed.has("data"):
		return null
	return parsed


func _rotate_backups(slot: String) -> void:
	if backups <= 0:
		return
	var main := _path(slot)
	if not FileAccess.file_exists(main):
		return
	var d := DirAccess.open(DIR)
	if d == null:
		return
	# shift bakN-1 -> bakN, oldest first
	for i in range(backups, 1, -1):
		var older := main + ".bak%d" % i
		var newer := main + ".bak%d" % (i - 1)
		if FileAccess.file_exists(newer):
			if FileAccess.file_exists(older):
				d.remove(older.get_file())
			d.copy(newer, older)
	# current main -> bak1
	if FileAccess.file_exists(main + ".bak1"):
		d.remove((main + ".bak1").get_file())
	d.copy(main, main + ".bak1")
