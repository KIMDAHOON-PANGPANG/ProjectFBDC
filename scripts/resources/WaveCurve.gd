class_name WaveCurve
extends Resource

## A chapter's population curve + chapter beats. Injected into WaveManager
## so the same wave engine can run any chapter — the const Ch1 schedule
## that used to live in WaveManager.gd is now resources/chapters/*.tres.
##
## Three parallel value-typed arrays (PackedFloat32 / PackedInt32) define
## a piecewise step function: from `curve_times[i]` onward, the spawner
## targets `curve_targets[i]` alive enemies with mob level `curve_lvs[i]`.
## All three must be the same length.
##
## Tip — bumping `boss_time` lengthens a chapter. Bumping
## `curve_targets[*]` raises the surround pressure; bumping
## `max_spawn_per_tick` lets the spawner catch up to a deficit faster.

## Chapter ID — used for SaveSystem section keys, label text, etc.
@export var chapter_id: int = 1
## Display name shown on the clear screen.
@export var chapter_name: String = "Chapter 1"

@export_group("Population Curve")
@export var curve_times: PackedFloat32Array = PackedFloat32Array([0.0, 30.0, 60.0, 90.0, 120.0])
@export var curve_targets: PackedInt32Array = PackedInt32Array([18, 39, 39, 55, 9])
@export var curve_lvs: PackedInt32Array = PackedInt32Array([1, 1, 2, 2, 2])

@export_group("Chapter Beats")
## One-shot elite trio spawn time.
@export var elite_time: float = 60.0
## One-shot boss spawn time.
@export var boss_time: float = 120.0

@export_group("Spawn Pacing")
## How often (seconds) WaveManager re-evaluates the deficit and adds.
@export var tick_period: float = 1.0
## Max spawns per tick — keeps adds visually staggered.
@export var max_spawn_per_tick: int = 4
## Probability a single drip-spawn is a ranged mob (≈1/6 → 5:1 melee:ranged).
@export var ranged_ratio: float = 0.16


## Defensive lookup — caller passes elapsed time, gets back the active
## curve index. Returns 0 if the curve is empty (shouldn't happen with
## a valid resource).
func index_for_elapsed(elapsed: float) -> int:
	var n: int = curve_times.size()
	if n == 0:
		return 0
	var idx: int = 0
	for i in n:
		if elapsed >= curve_times[i]:
			idx = i
		else:
			break
	return idx


func target_for_elapsed(elapsed: float) -> int:
	var idx := index_for_elapsed(elapsed)
	if idx >= curve_targets.size():
		return 0
	return curve_targets[idx]


func lv_for_elapsed(elapsed: float) -> int:
	var idx := index_for_elapsed(elapsed)
	if idx >= curve_lvs.size():
		return 1
	return curve_lvs[idx]
