class_name BossSignal
extends Node3D

## ZZZ-style "Critical Hit" telegraph icon that floats above a boss's
## head during its wind-up. Color encodes parryability:
##   • Yellow → parryable (PC's slash, well-timed, triggers a parry)
##   • Red    → unparryable (must dodge)
##
## Owner (Boss) calls `configure(target, color, lifetime)` after
## instantiating and adding us to the scene. The signal pulses (subtle
## scale tween) while the wind-up plays out, then fades and self-frees
## on lifetime expiry — or earlier if `cancel()` is called (parry path).
##
## Why top-level + per-frame follow (instead of parenting to the boss):
##   Same reasoning as HpBar3D — Godot's parent transform inheritance
##   showed visible one-frame lag when the boss moved/took knockback,
##   making the icon trail. Pinning our global_position from the
##   target's every frame eliminates the drift.

@export var quad_size: float = 0.7
@export var head_y_offset: float = 2.6
## Fade-in / fade-out durations.
@export var fade_in_time: float = 0.06
@export var fade_out_time: float = 0.18

var _target: Node3D
var _lifetime: float = 0.7
var _color: Color = Color(1.0, 0.85, 0.2, 1.0)
var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _consumed: bool = false
var _life_timer: float = 0.0
## True once we're fading out — guards against double-cancel and against
## the lifetime timer firing after a parry already canceled us.
var _fading: bool = false

func configure(target: Node3D, color: Color, lifetime: float,
		p_head_y_offset: float = -1.0) -> void:
	_target = target
	_color = color
	_lifetime = max(lifetime, 0.05)
	if p_head_y_offset >= 0.0:
		head_y_offset = p_head_y_offset
	if _mat != null:
		_mat.albedo_color = Color(_color.r, _color.g, _color.b, 0.0)
		_mat.emission = _color
	# Snap to target immediately so the icon doesn't pop in at world
	# origin for the first frame.
	_sync_to_target()

func _ready() -> void:
	top_level = true
	_build_quad()
	# Default target = parent (if a Boss instances us as a child for some
	# reason). Normal flow is current_scene-add → configure(target,...).
	if _target == null:
		var p := get_parent()
		if p is Node3D:
			_target = p
	_sync_to_target()
	# Fade in.
	if _mat != null:
		var t := create_tween()
		t.tween_property(_mat, "albedo_color:a", _color.a, fade_in_time)

func _process(delta: float) -> void:
	_life_timer += delta
	_sync_to_target()
	if not _fading and _life_timer >= _lifetime:
		_begin_fade_out()

func _sync_to_target() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	global_position = _target.global_position + Vector3(0, head_y_offset, 0)

func _build_quad() -> void:
	_mesh = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(quad_size, quad_size)
	_mesh.mesh = quad
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Full billboard so the icon always faces the camera plane-on, even
	# when the boss/camera angle shifts mid-attack.
	_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_mat.no_depth_test = true
	_mat.albedo_color = Color(_color.r, _color.g, _color.b, 0.0)
	_mat.emission_enabled = true
	_mat.emission = _color
	_mat.emission_energy_multiplier = 1.4
	_mesh.material_override = _mat
	add_child(_mesh)

## External cancel — called by the Boss the moment a parry resolves so
## the icon disappears in sync with the canceled FanTelegraph.
func cancel() -> void:
	_begin_fade_out()

func _begin_fade_out() -> void:
	if _fading or _consumed:
		return
	_fading = true
	if _mat == null:
		_finish_free()
		return
	var t := create_tween()
	t.tween_property(_mat, "albedo_color:a", 0.0, fade_out_time)
	t.tween_callback(_finish_free)

func _finish_free() -> void:
	if _consumed:
		return
	_consumed = true
	queue_free()
