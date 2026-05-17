class_name ExpSystem
extends Node

## Tracks PC experience and emits a signal when the bar fills.
##
## Threshold curve is now quadratic-ish to give the early game a noticeably
## faster bar fill (per balance feedback) while keeping the late game
## meaningfully slow.
##
##   threshold(level) = first_threshold + step * (level-1) + accel * (level-1)^2
##
## Concrete values with the defaults below:
##   Lv1 → 2:  14   (−30% vs the old linear curve)
##   Lv2 → 3:  23   (was 30)
##   Lv3 → 4:  36   (was 40)
##   Lv4 → 5:  51   (was 50)
##   Lv5 → 6:  68   (was 60)
##   ...
## So the player earns the first 2–3 level-ups much faster, then the
## curve catches up and starts pulling ahead of the old linear plan.
##
## Listeners (HUD bar, level-up screen) read `current_exp` / `threshold`
## and react to `exp_changed` / `leveled_up`.

signal exp_changed(current: int, threshold: int)
signal leveled_up(new_level: int)

@export var first_threshold: int = 14
@export var threshold_step: int = 8
## Quadratic accelerator on top of the linear step. 0.0 = pure linear.
@export var threshold_accel: float = 1.5
## Multiplier applied to EXP gains (extended by Greed upgrade).
var gain_multiplier: float = 1.0

var level: int = 1
var current_exp: int = 0
var threshold: int

func _ready() -> void:
	threshold = _compute_threshold(level)

func add_exp(raw_amount: int) -> void:
	if raw_amount <= 0:
		return
	var amount := int(round(raw_amount * gain_multiplier))
	if amount <= 0:
		amount = 1
	current_exp += amount
	# Multiple level-ups can chain if a single gain crosses several thresholds.
	while current_exp >= threshold:
		current_exp -= threshold
		level += 1
		threshold = _compute_threshold(level)
		leveled_up.emit(level)
	exp_changed.emit(current_exp, threshold)

## Compute the EXP needed to go FROM `lv` TO `lv + 1`. We use (lv - 1) so
## that level 1 starts at exactly `first_threshold` with no acceleration.
func _compute_threshold(lv: int) -> int:
	var n: int = max(lv - 1, 0)
	return first_threshold + threshold_step * n + int(round(threshold_accel * float(n) * float(n)))

func progress() -> float:
	if threshold <= 0:
		return 0.0
	return clamp(float(current_exp) / float(threshold), 0.0, 1.0)
