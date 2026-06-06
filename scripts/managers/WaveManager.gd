extends Node

## Population-curve driven spawner. The actual curve + chapter beats live
## in a `WaveCurve` Resource (resources/chapters/chapter_N.tres) — Main
## injects it via `set_curve()` before this manager goes live, so the
## same wave engine drives every chapter.
##
## Each tick (TICK_PERIOD seconds), measures current alive count via
## `count_alive_cb` and asks Main to spawn the deficit, capped to
## MAX_SPAWN_PER_TICK so adds dribble in instead of erupting at once.
##
## Two one-shot events still fire on top of the curve:
##   curve.elite_time — elite trio spawn (Main._chapter_spawn_elites)
##   curve.boss_time  — chapter boss spawn (Main._chapter_spawn_boss)
##
## The boss is excluded from the curve's alive count via its `boss` group
## tag, so jam keeps spawning around it during the boss phase.

signal milestone_triggered(name: String, t: float)

@export var enabled: bool = true

## The curve resource — must be set before the first _process tick. Main
## calls `set_curve(chapter_curves[i])` in `_build_chapter_systems`.
@export var curve: WaveCurve

# Wired by Main on _ready:
var request_spawn_cb: Callable    # (lv: int) -> void  — Main spawns one mob
var spawn_elites_cb: Callable     # () -> void         — Main spawns the elite trio
var spawn_boss_cb: Callable       # () -> void         — Main spawns the boss
var count_alive_cb: Callable      # () -> int          — Main counts non-boss enemies

var _elapsed: float = 0.0
var _tick_accum: float = 0.0
var _elites_fired: bool = false
var _boss_fired: bool = false


## Inject the active chapter's curve. Resets all run-state so the same
## WaveManager node can be reused if Main wants to switch chapters
## in-place (current `_advance_chapter` recreates the node, but
## resetting here is cheap and keeps the option open).
func set_curve(c: WaveCurve) -> void:
	curve = c
	_elapsed = 0.0
	_tick_accum = 0.0
	_elites_fired = false
	_boss_fired = false


func _process(delta: float) -> void:
	if not enabled or curve == null:
		return
	# Don't advance the chapter clock during pause (level-up screen, clear screen).
	var tree := get_tree()
	if tree == null or tree.paused:
		return
	_elapsed += delta
	_tick_accum += delta

	# One-shot chapter beats (fire exactly once, in order).
	if not _elites_fired and _elapsed >= curve.elite_time:
		_elites_fired = true
		milestone_triggered.emit("elites", _elapsed)
		if spawn_elites_cb.is_valid():
			spawn_elites_cb.call()
	if not _boss_fired and _elapsed >= curve.boss_time:
		_boss_fired = true
		milestone_triggered.emit("boss", _elapsed)
		if spawn_boss_cb.is_valid():
			spawn_boss_cb.call()

	# Population maintenance tick.
	if _tick_accum >= curve.tick_period:
		_tick_accum -= curve.tick_period
		_maintain_population()


func _maintain_population() -> void:
	if curve == null:
		return
	if not request_spawn_cb.is_valid() or not count_alive_cb.is_valid():
		return
	var target: int = curve.target_for_elapsed(_elapsed)
	var lv: int = curve.lv_for_elapsed(_elapsed)
	var alive: int = count_alive_cb.call()
	var deficit: int = target - alive
	if deficit <= 0:
		return
	var n: int = min(deficit, curve.max_spawn_per_tick)
	for i in n:
		request_spawn_cb.call(lv)


func elapsed() -> float:
	return _elapsed


func current_target() -> int:
	if curve == null:
		return 0
	return curve.target_for_elapsed(_elapsed)


func current_lv() -> int:
	if curve == null:
		return 1
	return curve.lv_for_elapsed(_elapsed)


## Probability a single drip-spawn is a ranged mob. Lifted from the curve
## so Main's `_request_spawn` reads it without poking the curve directly.
func ranged_ratio() -> float:
	if curve == null:
		return 0.16
	return curve.ranged_ratio


## Test/debug helper: jump the clock forward. Resets the one-shot guards
## so a test can re-trigger elites/boss without rebooting the scene.
func force_time(t: float) -> void:
	_elapsed = t
	if curve == null:
		return
	_elites_fired = _elapsed >= curve.elite_time and _elites_fired
	_boss_fired = _elapsed >= curve.boss_time and _boss_fired
