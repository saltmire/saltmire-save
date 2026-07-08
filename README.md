# Saltmire Save — One-Line Save/Load for Godot 4

![Godot 4.6+](https://img.shields.io/badge/Godot-4.6%2B-478cbf?logo=godotengine&logoColor=white)
![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)

Saving game state is something **every** game needs and nobody enjoys wiring.
Saltmire Save does it in one line — and then handles the parts that actually
bite you in production: **corrupt saves, save-file editing, schema changes when
your game updates, and bloated save sizes.**

```gdscript
Save.write("slot1", {"hp": 80, "level": 3})   # save
var data = Save.read("slot1")                  # load (null if missing)
```

That's the whole Lite API. Everything below is real, tested, and **measurable** —
run the headless selftest and see the numbers yourself.

## Why it's worth it (proven, not promised)

Every feature ships with an assertion in `selftest.gd` that prints a real number:

| Feature | What it does | Measured proof |
|---|---|---|
| 🔒 **Encryption** | AES-encrypts the file on disk | plaintext markers are **absent** from disk bytes; wrong key returns `null` — save-editing blocked |
| 🗜️ **Compression** | gzip payloads, kept only if smaller | a 400-entry save: **27,827 → 2,094 bytes (92.5% smaller)** |
| ♻️ **Corruption recovery** | rotating backups + auto-heal | a deliberately trashed main file is **restored from backup** on the next read |
| ⬆️ **Schema migration** | upgrade old saves as your game evolves | a v1 save is auto-migrated to v3 in **2 steps**, no data loss |
| 💾 **Smart autosave** | dirty-flag skips pointless writes | 2 ticks, nothing changed → **1 write, 1 skipped** |
| 📇 **Slot metadata** | level/playtime/timestamp for a load screen | read without deserializing the full payload |

Run it:

```
godot --headless --script selftest.gd
```

You'll see `SELFTEST PASS` with every number above.

## Install

1. Copy `addons/saltmire_save/` into your project's `addons/` folder.
2. **Project → Project Settings → Plugins → enable "Saltmire Save".**
3. That registers the `Save` autoload. Done.

## Full API

```gdscript
# --- core ---
Save.write("slot1", data)          # data = Dictionary/Array/primitive
Save.read("slot1")                 # -> data, or null
Save.has("slot1")                  # -> bool
Save.erase("slot1")                # deletes slot + its backups
Save.list_slots()                  # -> PackedStringArray

# --- autosave (smart: only writes when something changed) ---
Save.autosave("slot1", func(): return get_state(), 30.0)
Save.mark_dirty()                  # call when state changes
Save.stop_autosave()

# --- encryption ---
Save.encryption_key = "your-key"   # set once; all writes/reads use it

# --- compression ---
Save.compress = true               # gzip payloads

# --- backups + recovery (automatic) ---
Save.backups = 2                   # rotating .bak copies kept per slot

# --- schema migration ---
Save.current_version = 3
Save.register_migration(1, func(d): d["gold"] = d["coins"]; d.erase("coins"); return d)
Save.register_migration(2, func(d): d["prestige"] = 0; return d)

# --- load screen ---
Save.slot_meta("slot1")            # {level, playtime, saved_at, version, ...}
Save.list_slots_meta()             # Array of the above, one per slot

# --- proof-of-value snapshot ---
Save.stats()                       # {compression_saved_pct, writes, writes_skipped, recoveries, ...}
```

### Signals

`saved(slot)` · `loaded(slot)` · `recovered(slot)` · `migrated(slot, from, to)`

## Demo

Open the project and run `demo/demo.tscn` — it performs every feature live and
prints the real numbers on screen.

## Notes

- Saves live in `user://saltmire_saves/`. On desktop that's a real folder; on web
  it's IndexedDB — same API either way.
- Encryption uses Godot's built-in `FileAccess.open_encrypted_with_pass` (AES-256).
- Compression is only kept when it actually shrinks the file; tiny saves stay raw.
- Backups rotate: `slot.sav.bak1` is the previous save, `.bak2` the one before it.

## Part of Saltmire

Made by **Saltmire** — small, honest, drop-in tools for Godot 4.
See the game-feel family too: [Juice](https://saltmire.itch.io/saltmire-juice) ·
[FX](https://saltmire.itch.io/saltmire-fx) ·
[Spark](https://saltmire.itch.io/saltmire-spark) ·
[Impact](https://saltmire.itch.io/saltmire-impact).

## License

MIT — use it in anything, commercial or not. See `LICENSE.txt`.

https://saltmire.itch.io
