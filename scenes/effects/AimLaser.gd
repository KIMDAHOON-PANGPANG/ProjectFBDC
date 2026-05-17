class_name AimLaser
extends Node3D

## Spider-Man-2-style aim telegraph for any ranged attacker.
## This is a SHARED component — every future ranged enemy / boss / turret
## should reuse this scene rather than re-rolling its own beam.
##
## Two-phase readability:
##   • Phase 1 (lock_duration − red_window seconds): translucent WHITE beam
##     while the attacker is "tracking" the target. Player has time to read it.
##   • Phase 2 (last `red_window` seconds): beam snaps to bright RED + a
##     thicker scale, locking onto wherever the target is RIGHT NOW. This is
##     the "you must react now" window.
##
## `red_window` defaults to 0.2s, which is the standard fighting-game
## reaction reference — players can reliably dodge a 0.2s window with
## practice, so the red phase doubles as both a fairness commitment from
## the game ("you had 200ms to read me") and a difficulty knob.
##
## After `lock_duration` total seconds the beam fires an arrow in whatever
## direction the beam was pointing at that instant, then queue_frees itself.
##
## Caller (e.g. RangedEnemy) does:
##     var laser = aim_laser_scene.instantiate()
##     scene.add_child(laser)
##     laser.configure(shooter, target, arrow_scene, arrow_speed)
## and forgets about it.

@export var lock_duration: float = 1.0
## Last N seconds of the lock are the red "react now" window.
@export var red_window: float = 0.2

@export var beam_thickness: float = 0.06
## How much thicker the beam gets in the red phase (multiplied on y/z scale).
@export var red_thickness_mult: float = 1.6

## Phase 1 colour — translucent white "I am looking at you".
@export var aim_color: Color = Color(1.0, 1.0, 1.0, 0.45)
## Phase 2 colour — opaque red "I am about to shoot".
@export var lock_color: Color = Color(1.0, 0.15, 0.15, 0.95)

@export var aim_emission_energy: float = 0.5
@export var lock_emission_energy: float = 1.6

var _shooter: Node3D
var _target: Node3D
var _arrow_scene: PackedScene
var _arrow_speed: float = 13.2
var _elapsed: float = 0.0
var _consumed: bool = false
var _beam: MeshInstance3D
var _mat: StandardMaterial3D
var _last_dir: Vector3 = Vector3(1, 0, 0)
# True once we've already snapped to the red phase. Guards against running
# the color/scale assignment every frame in the last 200ms.
var _in_red_phase: bool = false
# Cached thickness multiplier; updated by _enter_red_phase.
var _thickness_scale: float = 1.0

func configure(shooter: Node3D, target: Node3D, arrow_scene: PackedScene, arrow_speed: float) -> void:
	_shooter = shooter
	_target = target
	_arrow_scene = arrow_scene
	_arrow_speed = arrow_speed

func _ready() -> void:
	add_to_group("aim_lasers")
	_beam = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.0, beam_thickness, beam_thickness)
	_beam.mesh = box
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.emission_enabled = true
	_apply_phase_visual(false)  # start in white phase
	_beam.material_override = _mat
	add_child(_beam)

func _process(delta: float) -> void:
	if _consumed:
		return
	if _shooter == null or not is_instance_valid(_shooter):
		queue_free()
		return
	if _target == null or not is_instance_valid(_target):
		queue_free()
		return

	# Anchor at the shooter; orient the beam toward the current target pos.
	var from: Vector3 = (_shooter as Node3D).global_position + Vector3(0, 0.6, 0)
	var to: Vector3 = (_target as Node3D).global_position + Vector3(0, 0.6, 0)
	var diff: Vector3 = to - from
	var len: float = diff.length()
	if len < 0.01:
		len = 0.01
	_last_dir = diff.normalized()
	# Place beam at midpoint and rotate so local +X faces the target.
	global_position = (from + to) * 0.5
	var yaw: float = atan2(-diff.z, diff.x)
	rotation = Vector3(0.0, yaw, 0.0)
	_beam.scale = Vector3(len, _thickness_scale, _thickness_scale)

	_elapsed += delta

	# Phase transition: enter the red "must react now" window.
	if not _in_red_phase and (lock_duration - _elapsed) <= red_window:
		_in_red_phase = true
		_apply_phase_visual(true)

	if _elapsed >= lock_duration:
		_fire_arrow(from)

## Apply the visual associated with the current phase. Centralised so the
## init in `_ready` and the runtime transition in `_process` cannot drift.
func _apply_phase_visual(red: bool) -> void:
	if _mat == null:
		return
	if red:
		_mat.albedo_color = lock_color
		_mat.emission = lock_color
		_mat.emission_energy_multiplier = lock_emission_energy
		_thickness_scale = red_thickness_mult
	else:
		_mat.albedo_color = aim_color
		_mat.emission = aim_color
		_mat.emission_energy_multiplier = aim_emission_energy
		_thickness_scale = 1.0

func _fire_arrow(from: Vector3) -> void:
	if _consumed:
		return
	_consumed = true
	if _arrow_scene != null:
		var arrow = _arrow_scene.instantiate()
		# Speed override + bullet-time inheritance (shooter carries the slow).
		arrow.speed = _arrow_speed
		if _shooter and "time_scale_mult" in _shooter and "time_scale_mult" in arrow:
			arrow.time_scale_mult = _shooter.time_scale_mult
		get_tree().current_scene.add_child(arrow)
		if arrow.has_method("launch"):
			arrow.call("launch", _last_dir, from + _last_dir * 0.5)
	queue_free()

## Test/debug helper — true once the beam is in its red react-window phase.
func is_in_red_phase() -> bool:
	return _in_red_phase
