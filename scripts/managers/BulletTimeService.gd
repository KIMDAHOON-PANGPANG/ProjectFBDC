extends Node

## Bullet-time / monochrome effect — slows every enemy + arrow's
## time_scale_mult, fades world saturation to 0, holds, restores.
## Extracted from Main.gd in the refactor pass that landed alongside
## M7 sound + Zen meter so Testplay can share the same code path
## without copy-paste drift.
##
## Wired by the parent scene:
##   var bt := BulletTimeService.new()
##   bt.name = "BulletTimeService"
##   add_child(bt)
##   bt.setup(_world_env)  # WorldEnvironment to pulse saturation on
##
## Read `is_active()` from spawners so freshly created enemies / arrows
## inherit the slow on creation.

const _NORMAL_SATURATION: float = 1.12

@export var slow_factor: float = 0.25
@export var duration: float = 3.0

var _world_env: WorldEnvironment
var _active: bool = false
var _tween: Tween


func setup(world_env: WorldEnvironment) -> void:
	_world_env = world_env


func is_active() -> bool:
	return _active


## Snapshot of the slow multiplier. Spawners use this to set new
## enemies' time_scale_mult on creation so the world stays consistently
## dilated even for things that didn't exist when bullet-time started.
func current_slow_factor() -> float:
	return slow_factor


func start(dur: float = -1.0) -> void:
	if _world_env == null:
		return
	if dur < 0.0:
		dur = duration
	_active = true
	for e in get_tree().get_nodes_in_group("enemies"):
		if "time_scale_mult" in e:
			e.time_scale_mult = slow_factor
	_apply_slow_to_loose_arrows(slow_factor)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var env := _world_env.environment
	_tween = create_tween()
	_tween.tween_property(env, "adjustment_saturation", 0.0, 0.15)
	_tween.tween_interval(max(dur - 0.45, 0.05))
	_tween.tween_property(env, "adjustment_saturation", _NORMAL_SATURATION, 0.3)
	_tween.tween_callback(_finish)


## Force-stop early (used by Main._advance_chapter to clean up tweens
## across chapter transitions).
func cancel() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	_active = false
	if _world_env != null and _world_env.environment != null:
		_world_env.environment.adjustment_saturation = _NORMAL_SATURATION


func _finish() -> void:
	_active = false
	for e in get_tree().get_nodes_in_group("enemies"):
		if "time_scale_mult" in e:
			e.time_scale_mult = 1.0
	_apply_slow_to_loose_arrows(1.0)


func _apply_slow_to_loose_arrows(factor: float) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	for child in scene.get_children():
		if child is EnemyArrow and "time_scale_mult" in child:
			child.time_scale_mult = factor
