extends Node

## Population-curve driven spawner for Chapter 1.
##
## Maintains a *target alive count* defined as a piecewise function of time.
## Every TICK_PERIOD seconds, measures the current alive count (via Main's
## `count_alive_cb`) and asks Main to spawn the deficit, capped to
## MAX_SPAWN_PER_TICK so adds dribble in instead of erupting all at once.
##
## Two one-shot events still fire on top of the curve (these are NOT
## population-managed — they're chapter beats that should land regardless):
##   t=60s — elite trio spawn
##   t=120s — chapter boss spawn
##
## The boss is excluded from the curve's alive count via its `boss` group
## tag, so jam keeps spawning around it during the boss phase.

signal milestone_triggered(name: String, t: float)

@export var enabled: bool = true

## How often (seconds) we evaluate the population deficit and drip in spawns.
const TICK_PERIOD: float = 1.0
## Maximum spawns per tick. Keeps adds visually staggered.
## History: 2 → 3 for 12-sector surround, then 3 → 4 (+30% from user
## tuning pass). Combined with the 30%-bumped curve targets below, the
## PC now has roughly 1/3 more bodies to weave through at any phase.
const MAX_SPAWN_PER_TICK: int = 4

## One-shot event times (chapter beats).
const ELITE_TIME: float = 60.0
const BOSS_TIME: float = 120.0

## Piecewise population curve stored as three parallel value-typed arrays
## (PackedFloat32 / PackedInt32). We tried storing this as a `const
## Array[Dictionary]` and even an instance `var Array`; Godot 4.7-dev2
## prints spurious `Parameter "_p" is null` errors from Dictionary._unref
## whenever those arrays get iterated under physics tick load. Parallel
## value arrays sidestep ref-counting entirely.
##
## Index i means: "from CURVE_TIMES[i] onward, target is CURVE_TARGETS[i]
## and newly-spawned melee are level CURVE_LVS[i]".
## Tuning history: Medium baseline → +20% (14/30/30/42/7) → +30% by user
## request (18/39/39/55/9) for more surround pressure.
const CURVE_TIMES: PackedFloat32Array   = [0.0, 30.0, 60.0, 90.0, 120.0]
const CURVE_TARGETS: PackedInt32Array   = [18,  39,   39,   55,    9]
const CURVE_LVS: PackedInt32Array       = [1,   1,    2,    2,     2]

# (No instance state for the curve — it's static via the const arrays above.)

# Wired by Main on _ready:
var request_spawn_cb: Callable    # (lv: int) -> void  — Main spawns one mob
var spawn_elites_cb: Callable     # () -> void         — Main spawns the elite trio
var spawn_boss_cb: Callable       # () -> void         — Main spawns the boss
var count_alive_cb: Callable      # () -> int          — Main counts non-boss enemies

var _elapsed: float = 0.0
var _tick_accum: float = 0.0
var _elites_fired: bool = false
var _boss_fired: bool = false

func _process(delta: float) -> void:
	if not enabled:
		return
	# Don't advance the chapter clock during pause (level-up screen, clear screen).
	var tree := get_tree()
	if tree == null or tree.paused:
		return
	_elapsed += delta
	_tick_accum += delta

	# One-shot chapter beats (fire exactly once, in order).
	if not _elites_fired and _elapsed >= ELITE_TIME:
		_elites_fired = true
		milestone_triggered.emit("elites", _elapsed)
		if spawn_elites_cb.is_valid():
			spawn_elites_cb.call()
	if not _boss_fired and _elapsed >= BOSS_TIME:
		_boss_fired = true
		milestone_triggered.emit("boss", _elapsed)
		if spawn_boss_cb.is_valid():
			spawn_boss_cb.call()

	# Population maintenance tick.
	if _tick_accum >= TICK_PERIOD:
		_tick_accum -= TICK_PERIOD
		_maintain_population()

func _maintain_population() -> void:
	if not request_spawn_cb.is_valid() or not count_alive_cb.is_valid():
		return
	var idx: int = _current_index()
	var target: int = CURVE_TARGETS[idx]
	var lv: int = CURVE_LVS[idx]
	var alive: int = count_alive_cb.call()
	var deficit: int = target - alive
	if deficit <= 0:
		return
	var n: int = min(deficit, MAX_SPAWN_PER_TICK)
	for i in n:
		request_spawn_cb.call(lv)

## Latest curve step whose `CURVE_TIMES[i] <= _elapsed`. Returns the index;
## callers read into the parallel arrays. Linear scan is fine (curve has
## only 5 entries).
func _current_index() -> int:
	var idx: int = 0
	for i in CURVE_TIMES.size():
		if _elapsed >= CURVE_TIMES[i]:
			idx = i
		else:
			break
	return idx

func elapsed() -> float:
	return _elapsed

func current_target() -> int:
	return CURVE_TARGETS[_current_index()]

func current_lv() -> int:
	return CURVE_LVS[_current_index()]

## Test/debug helper: jump the clock forward. Resets the one-shot guards
## so a test can re-trigger elites/boss without rebooting the scene.
func force_time(t: float) -> void:
	_elapsed = t
	_elites_fired = _elapsed >= ELITE_TIME and _elites_fired
	_boss_fired = _elapsed >= BOSS_TIME and _boss_fired
