class_name SaveSystem
extends RefCounted

## Persistent save store — chapter best records + meta progression hooks.
##
## Static class (RefCounted pattern, identical to UpgradeSystem) so any
## scene can call `SaveSystem.record_clear(...)` without bootstrapping a
## Node instance. The underlying ConfigFile is loaded lazily on first
## access and cached for the rest of the session.
##
## Save file: `user://save.cfg` (Godot ConfigFile — INI-style, safe to
## hand-edit during development).
##
## Schema (per chapter section "chapter_{id}"):
##   best_time   : float seconds, lower is better. -1.0 = no record yet.
##   best_kills  : int — peak kill count across all runs (clear OR death).
##   best_level  : int — peak PC level across all runs.
##   cleared     : bool — true once any run cleared this chapter.
##   clear_count : int — successful chapter completions.
##   death_count : int — runs that ended with PC death on this chapter.
##
## All record_* calls return a `beat` dict — which of {time/kills/level}
## were freshly improved this run, so the result screen can NEW! badge them.

const SAVE_PATH := "user://save.cfg"

static var _cfg: ConfigFile = null


## Lazy load. Idempotent. If the file doesn't exist yet, _cfg becomes a
## fresh empty ConfigFile (writes will create the file on save).
static func _ensure_loaded() -> void:
	if _cfg != null:
		return
	_cfg = ConfigFile.new()
	var err := _cfg.load(SAVE_PATH)
	# ERR_FILE_NOT_FOUND is the expected "first run" case — silent.
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning("SaveSystem: load failed code=%s — starting fresh" % err)


## Lookup the saved record for a chapter. Returns {} if none yet.
## Callers can `.get(key, default)` defensively.
static func best_for(chapter_id: int) -> Dictionary:
	_ensure_loaded()
	var section := _section_for(chapter_id)
	if not _cfg.has_section(section):
		return {}
	var result: Dictionary = {}
	for key in _cfg.get_section_keys(section):
		result[key] = _cfg.get_value(section, key)
	return result


## Mark chapter `chapter_id` as cleared with these run stats and update
## any best-records that this run beat. Returns the `beat` dictionary:
##   {"time": bool, "kills": bool, "level": bool}
## so the clear screen can NEW! badge each beaten field.
static func record_clear(chapter_id: int, time_seconds: float, kills: int, level: int) -> Dictionary:
	_ensure_loaded()
	var prev := best_for(chapter_id)
	var beat: Dictionary = {"time": false, "kills": false, "level": false}
	var prev_time: float = float(prev.get("best_time", -1.0))
	var prev_kills: int = int(prev.get("best_kills", 0))
	var prev_level: int = int(prev.get("best_level", 1))

	var new_time: float = prev_time
	if prev_time < 0.0 or time_seconds < prev_time:
		new_time = time_seconds
		beat["time"] = true

	var new_kills: int = prev_kills
	if kills > prev_kills:
		new_kills = kills
		beat["kills"] = true

	var new_level: int = prev_level
	if level > prev_level:
		new_level = level
		beat["level"] = true

	var record := {
		"best_time": new_time,
		"best_kills": new_kills,
		"best_level": new_level,
		"cleared": true,
		"clear_count": int(prev.get("clear_count", 0)) + 1,
		"death_count": int(prev.get("death_count", 0)),
	}
	_write(_section_for(chapter_id), record)
	save()
	return beat


## Record a death on `chapter_id` — does NOT touch best_time (deaths
## aren't a valid speedrun result), but DOES track peak kills/level
## across attempts so quitters still see progress.
static func record_death(chapter_id: int, _time_seconds: float, kills: int, level: int) -> Dictionary:
	_ensure_loaded()
	var prev := best_for(chapter_id)
	var beat: Dictionary = {"kills": false, "level": false}
	var prev_kills: int = int(prev.get("best_kills", 0))
	var prev_level: int = int(prev.get("best_level", 1))

	var new_kills: int = prev_kills
	if kills > prev_kills:
		new_kills = kills
		beat["kills"] = true

	var new_level: int = prev_level
	if level > prev_level:
		new_level = level
		beat["level"] = true

	var record := {
		"best_time": float(prev.get("best_time", -1.0)),
		"best_kills": new_kills,
		"best_level": new_level,
		"cleared": bool(prev.get("cleared", false)),
		"clear_count": int(prev.get("clear_count", 0)),
		"death_count": int(prev.get("death_count", 0)) + 1,
	}
	_write(_section_for(chapter_id), record)
	save()
	return beat


## Flush the in-memory ConfigFile to disk. Called automatically by
## record_clear/record_death; exposed for manual flush if needed.
static func save() -> void:
	_ensure_loaded()
	var err := _cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("SaveSystem: save failed code=%s" % err)


## Wipe every section — handy for a debug "reset save" menu later.
## Forces an immediate disk write so the next launch reads the cleared
## state, not the lingering file.
static func clear_all() -> void:
	_ensure_loaded()
	for section in _cfg.get_sections():
		_cfg.erase_section(section)
	save()


static func _section_for(chapter_id: int) -> String:
	return "chapter_%d" % chapter_id


static func _write(section: String, data: Dictionary) -> void:
	for k in data.keys():
		_cfg.set_value(section, str(k), data[k])
