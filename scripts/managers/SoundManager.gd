extends Node

## M7 sound infrastructure (placeholder). Autoload — register in
## project.godot `[autoload]` so any scene can call
## `SoundManager.play_sfx("slash")`. Audio files live under
## `res://audio/sfx/<name>.ogg` and `res://audio/bgm/<name>.ogg`
## but the project ships with NO .ogg yet — every play_* is a
## silent no-op until the assets land.
##
## Why ship the manager before the audio:
## 1. The hook points (Player.slash_finished, Player.take_hit, etc.)
##    settle into the right places now; dropping .ogg files in later
##    is a single-file change per cue.
## 2. The PR diff stays small: code stabilizes one pass, audio another.

const SFX_DIR := "res://audio/sfx"
const BGM_DIR := "res://audio/bgm"

## Master volume sliders (Settings UI lands in a later pass).
@export var sfx_volume_linear: float = 1.0
@export var bgm_volume_linear: float = 0.6

var _sfx_cache: Dictionary = {}  # name -> AudioStream
var _bgm_cache: Dictionary = {}
var _sfx_players: Array[AudioStreamPlayer] = []
const _SFX_POOL_SIZE: int = 6
var _bgm_player: AudioStreamPlayer
var _current_bgm: String = ""


func _ready() -> void:
	# SFX player pool — round-robin so a fast-firing cue (e.g. slash
	# while a previous slash sound is still tailing) doesn't cut the
	# previous instance.
	for i in _SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_sfx_players.append(p)
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_bgm_player)


## Fire-and-forget SFX cue. `name` is the file stem under audio/sfx/
## (no `.ogg`). Silently no-ops if the file isn't present so the
## production code doesn't need to gate on file existence.
func play_sfx(name: String) -> void:
	var stream := _load_sfx(name)
	if stream == null:
		return
	var p := _next_sfx_player()
	if p == null:
		return
	p.stream = stream
	p.volume_db = linear_to_db(sfx_volume_linear)
	p.play()


## Crossfade to a new BGM track. Same-stem call as the current track
## is a no-op so callers can spam it on every level enter without
## restarting the music.
func play_bgm(name: String) -> void:
	if name == _current_bgm and _bgm_player.playing:
		return
	var stream := _load_bgm(name)
	_current_bgm = name
	if stream == null:
		_bgm_player.stop()
		return
	_bgm_player.stream = stream
	_bgm_player.volume_db = linear_to_db(bgm_volume_linear)
	_bgm_player.play()


func stop_bgm() -> void:
	_current_bgm = ""
	_bgm_player.stop()


func set_sfx_volume(linear: float) -> void:
	sfx_volume_linear = clampf(linear, 0.0, 1.0)


func set_bgm_volume(linear: float) -> void:
	bgm_volume_linear = clampf(linear, 0.0, 1.0)
	_bgm_player.volume_db = linear_to_db(bgm_volume_linear)


# ────── internals ──────

func _load_sfx(name: String) -> AudioStream:
	if _sfx_cache.has(name):
		return _sfx_cache[name]
	var path := "%s/%s.ogg" % [SFX_DIR, name]
	if not ResourceLoader.exists(path):
		_sfx_cache[name] = null  # cache the miss so we don't re-check
		return null
	var stream := load(path) as AudioStream
	_sfx_cache[name] = stream
	return stream


func _load_bgm(name: String) -> AudioStream:
	if _bgm_cache.has(name):
		return _bgm_cache[name]
	var path := "%s/%s.ogg" % [BGM_DIR, name]
	if not ResourceLoader.exists(path):
		_bgm_cache[name] = null
		return null
	var stream := load(path) as AudioStream
	_bgm_cache[name] = stream
	return stream


func _next_sfx_player() -> AudioStreamPlayer:
	# Prefer an idle player; if all are busy, take the oldest (index 0
	# and rotate).
	for p in _sfx_players:
		if not p.playing:
			return p
	var first := _sfx_players[0]
	_sfx_players.remove_at(0)
	_sfx_players.append(first)
	return first
