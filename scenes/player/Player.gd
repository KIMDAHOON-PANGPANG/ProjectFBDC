class_name Player
extends CharacterBody3D

## Player samurai. Movement: WASD on XZ plane.
## Attack: hold LMB to charge an aim arrow (length grows w/ charge), release to
## perform an iaijutsu slash — dashes through enemies along the arrow and spawns
## a damage trail that kills everything in its width.

signal slash_started
signal slash_finished

enum State { IDLE, AIMING, DASHING, COOLDOWN, EVADING }

@export var data: PlayerData
@export var slash_attack_scene: PackedScene
@export var aim_arrow_path: NodePath
@export var sprite_rig_path: NodePath

var _state: int = State.IDLE
var _charge_t: float = 0.0
var _aim_dir: Vector3 = Vector3(1, 0, 0)
var _cooldown_t: float = 0.0
var _dash_start: Vector3
var _dash_end: Vector3
var _dash_elapsed: float = 0.0
var _aim_arrow: AimArrow
var _sprite_rig: SpriteRig
var _health: HealthComponent
## Foot-dust emitter — toggled on while WASD-moving / dashing / evading
## so the player has a clear "I am moving" cue even on an empty plane
## (the grid ground gives world-scrolling, this gives self-motion).
var _dust_emitter: CPUParticles3D

# Shift-dash (evade) state.
var _evade_dir: Vector3 = Vector3.ZERO
var _evade_start: Vector3
var _evade_end: Vector3
var _evade_elapsed: float = 0.0
var _evade_cd: float = 0.0

# Post-hit i-frame timer. While > 0, take_hit is suppressed. Generous 1s
# window lets the player visibly re-position before the next damage is
# possible — also long enough for the strobe blink to read.
const HIT_IFRAME: float = 1.0
var _iframe_t: float = 0.0

func _ready() -> void:
	if data == null:
		data = PlayerData.new()
	if data.visuals == null:
		data.visuals = CharacterVisuals.new()
		data.visuals.placeholder_tint = Color(0.85, 0.9, 1.0)

	collision_layer = 1 << 1  # Player
	collision_mask = (1 << 0) | (1 << 2)  # World + Enemy (block on enemies optional; we still pass over)

	_aim_arrow = get_node_or_null(aim_arrow_path) as AimArrow
	_sprite_rig = get_node_or_null(sprite_rig_path) as SpriteRig
	if _sprite_rig != null:
		_sprite_rig.fallback_color = Color(0.85, 0.9, 1.0)
		_sprite_rig.set_visuals(data.visuals)

	_health = get_node_or_null("HealthComponent") as HealthComponent
	if _health != null:
		_health.setup(data.max_hp)
		_health.died.connect(_on_died)
		# Wire the floating head-bar to the same HealthComponent.
		var hpbar := get_node_or_null("HpBar3D")
		if hpbar != null and hpbar.has_method("attach_health"):
			hpbar.call("attach_health", _health)

	_build_dust_emitter()

func _physics_process(delta: float) -> void:
	# Evade cooldown ticks independently of state so it counts down during
	# slash / cooldown / etc.
	if _evade_cd > 0.0:
		_evade_cd -= delta
	if _iframe_t > 0.0:
		_iframe_t -= delta
	match _state:
		State.IDLE:
			_handle_move(delta)
			_check_attack_start()
			_check_evade_start()
			if _cooldown_t > 0.0:
				_cooldown_t -= delta
		State.AIMING:
			velocity = Vector3.ZERO
			move_and_slide()
			_update_aim(delta)
			_check_attack_release()
		State.DASHING:
			_update_dash(delta)
		State.COOLDOWN:
			_handle_move(delta)
			_check_evade_start()
			_cooldown_t -= delta
			if _cooldown_t <= 0.0:
				_set_state(State.IDLE)
		State.EVADING:
			_update_evade(delta)

func _handle_move(delta: float) -> void:
	var input := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	var dir := Vector3(input.x, 0.0, input.y)
	if dir.length() > 1.0:
		dir = dir.normalized()
	velocity.x = dir.x * data.move_speed
	velocity.z = dir.z * data.move_speed
	velocity.y = 0.0
	move_and_slide()
	var moving: bool = dir.length_squared() > 0.01
	if _sprite_rig != null:
		if moving:
			_sprite_rig.set_state(SpriteRig.State.WALK)
			_sprite_rig.set_facing(dir.x)
		else:
			_sprite_rig.set_state(SpriteRig.State.IDLE)
	# Dust kicks on whenever we're actually moving — gives a visible
	# self-motion cue on top of the world-anchored grid ground.
	if _dust_emitter != null:
		_dust_emitter.emitting = moving

func _check_attack_start() -> void:
	if Input.is_action_just_pressed("attack") and _cooldown_t <= 0.0:
		# Suppress the slash when the click was on a UI control (testplay
		# spawn buttons, level-up cards, chapter-clear screen, …).
		# `Input.is_action_just_pressed` polls global input state and
		# fires even when a Button consumed the click via mouse_filter —
		# the polling layer is below UI event propagation. We check the
		# hovered Control instead. Labels default to MOUSE_FILTER_IGNORE
		# so HUD text never blocks the slash.
		if _is_pointer_over_ui():
			return
		_set_state(State.AIMING)
		_charge_t = 0.0
		if _aim_arrow != null:
			_aim_arrow.show_arrow()
			_aim_arrow.set_charge(0.0)

func _is_pointer_over_ui() -> bool:
	var vp := get_viewport()
	if vp == null:
		return false
	return vp.gui_get_hovered_control() != null

func _check_attack_release() -> void:
	if not Input.is_action_pressed("attack"):
		_fire_slash()

func _update_aim(delta: float) -> void:
	_charge_t = min(_charge_t + delta, data.max_charge_time)
	var dir := _mouse_to_world_dir()
	if dir.length_squared() > 0.0001:
		_aim_dir = dir
	if _aim_arrow != null:
		var charge_frac: float = _charge_t / max(data.max_charge_time, 0.0001)
		_aim_arrow.set_charge(charge_frac)
		_aim_arrow.aim_at_direction(_aim_dir)
	if _sprite_rig != null:
		_sprite_rig.set_facing(_aim_dir.x)
		_sprite_rig.set_state(SpriteRig.State.IDLE)

func _fire_slash() -> void:
	var charge_frac: float = clamp(_charge_t / max(data.max_charge_time, 0.0001), 0.0, 1.0)
	var slash_range: float = lerp(data.min_slash_range, data.max_slash_range, charge_frac)
	_dash_start = global_position
	_dash_end = global_position + _aim_dir.normalized() * slash_range
	_dash_elapsed = 0.0
	_set_state(State.DASHING)
	if _aim_arrow != null:
		_aim_arrow.hide_arrow()
	if _sprite_rig != null:
		_sprite_rig.set_state(SpriteRig.State.ATTACK)
		_sprite_rig.set_facing(_aim_dir.x)
	# Spawn slash trail at the start of the dash.
	_spawn_slash_attack(_dash_start, _dash_end)
	slash_started.emit()

func _update_dash(delta: float) -> void:
	_dash_elapsed += delta
	var t: float = clamp(_dash_elapsed / max(data.dash_duration, 0.0001), 0.0, 1.0)
	# Smooth easing (ease-out)
	var eased: float = 1.0 - pow(1.0 - t, 2.0)
	global_position = _dash_start.lerp(_dash_end, eased)
	# Dust trails the dash for a chunky burst-line read.
	if _dust_emitter != null:
		_dust_emitter.emitting = true
	if t >= 1.0:
		_cooldown_t = data.slash_cooldown
		slash_finished.emit()
		_set_state(State.COOLDOWN if data.slash_cooldown > 0.0 else State.IDLE)

func _spawn_slash_attack(start: Vector3, end: Vector3) -> void:
	var attack: SlashAttack
	if slash_attack_scene != null:
		attack = slash_attack_scene.instantiate() as SlashAttack
	else:
		attack = SlashAttack.new()
	get_tree().current_scene.add_child(attack)
	attack.configure(start, end, data.slash_width)
	attack.lifetime = data.slash_hit_lifetime

func _set_state(s: int) -> void:
	_state = s

func _mouse_to_world_dir() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return _aim_dir
	var mouse := get_viewport().get_mouse_position()
	var origin: Vector3 = cam.project_ray_origin(mouse)
	var normal: Vector3 = cam.project_ray_normal(mouse)
	# Intersect with the horizontal plane at player's Y.
	if abs(normal.y) < 0.0001:
		return _aim_dir
	var t: float = (global_position.y - origin.y) / normal.y
	if t < 0.0:
		return _aim_dir
	var hit: Vector3 = origin + normal * t
	var dir: Vector3 = Vector3(hit.x - global_position.x, 0.0, hit.z - global_position.z)
	if dir.length_squared() < 0.0001:
		return _aim_dir
	return dir.normalized()

func take_hit(amount: int = 1) -> void:
	# Invincible for the duration of the iaido slash (DASHING), during a
	# Shift-evade (EVADING), and for HIT_IFRAME seconds after the previous
	# damage landed.
	if is_invincible():
		return
	if _health != null:
		_health.take_damage(amount)
	# Hit feedback — i-frame + strobe blink + camera shake. Runs even if
	# the hit was fatal (the strobe blends naturally into the death fade).
	_iframe_t = HIT_IFRAME
	if _sprite_rig != null and _sprite_rig.has_method("start_iframe_blink"):
		_sprite_rig.call("start_iframe_blink", HIT_IFRAME)
	var rig := get_tree().get_first_node_in_group("camera_rig")
	if rig != null and rig.has_method("shake"):
		rig.call("shake", 0.08, 0.18)

func is_invincible() -> bool:
	return _state == State.DASHING or _state == State.EVADING or _iframe_t > 0.0

## --- Shift evade dash ---

func _check_evade_start() -> void:
	if _evade_cd > 0.0:
		return
	if not Input.is_action_just_pressed("dash"):
		return
	# Direction priority: current WASD input, else last aim direction, else
	# +X. This means a stationary PC dashes forward (toward last facing).
	var input := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	var dir := Vector3(input.x, 0.0, input.y)
	if dir.length() < 0.01:
		dir = _aim_dir
	if dir.length() < 0.01:
		dir = Vector3(1, 0, 0)
	dir = dir.normalized()
	_evade_dir = dir
	_evade_start = global_position
	_evade_end = global_position + dir * data.evade_distance
	_evade_elapsed = 0.0
	_evade_cd = data.evade_cooldown
	_set_state(State.EVADING)
	if _sprite_rig != null:
		_sprite_rig.set_facing(dir.x)
	# Nudge the camera so it trails the dash briefly.
	var rig := get_tree().get_first_node_in_group("camera_rig")
	if rig != null and rig.has_method("nudge_lag"):
		rig.call("nudge_lag", 0.35, 0.4)

func _update_evade(delta: float) -> void:
	_evade_elapsed += delta
	var t: float = clamp(_evade_elapsed / max(data.evade_duration, 0.0001), 0.0, 1.0)
	# Ease-out: feels snappy at start, settles smoothly at end.
	var eased: float = 1.0 - pow(1.0 - t, 2.0)
	global_position = _evade_start.lerp(_evade_end, eased)
	# Evade kicks the dust trail on too — gives the i-frame dash a
	# satisfying afterimage even on a flat plane.
	if _dust_emitter != null:
		_dust_emitter.emitting = true
	if t >= 1.0:
		_set_state(State.IDLE)

func _on_died() -> void:
	if _sprite_rig != null:
		_sprite_rig.play_death_then_free(self, 0.5)
	else:
		queue_free()

## Foot-dust particle emitter. Lives as a child of the PC so it follows
## the body without any explicit position sync. We toggle `emitting`
## from movement code paths; the particles themselves are CPU-driven
## with a short lifetime (0.4s) so the trail clears quickly when the
## PC stops.
func _build_dust_emitter() -> void:
	_dust_emitter = CPUParticles3D.new()
	_dust_emitter.name = "DustEmitter"
	_dust_emitter.amount = 10
	_dust_emitter.lifetime = 0.4
	_dust_emitter.one_shot = false
	_dust_emitter.emitting = false
	_dust_emitter.explosiveness = 0.0
	_dust_emitter.local_coords = false  # particles stay in world space, trailing the PC
	_dust_emitter.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_dust_emitter.emission_sphere_radius = 0.18
	# Particles puff upward and outward with mild spread, then settle.
	_dust_emitter.direction = Vector3(0, 1, 0)
	_dust_emitter.spread = 45.0
	_dust_emitter.initial_velocity_min = 0.3
	_dust_emitter.initial_velocity_max = 0.7
	_dust_emitter.gravity = Vector3(0, -0.6, 0)
	_dust_emitter.scale_amount_min = 0.08
	_dust_emitter.scale_amount_max = 0.18
	# Visual: a tiny billboarded quad in a muted dust tone. The material
	# is set on PrimitiveMesh.material (CPUParticles3D draws each
	# particle as a copy of mesh, taking that material).
	var dust_mat := StandardMaterial3D.new()
	dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dust_mat.albedo_color = Color(0.72, 0.65, 0.55, 0.55)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.2, 0.2)
	quad.material = dust_mat
	_dust_emitter.mesh = quad
	# Sit slightly off the ground so particles emit at foot level rather
	# than from the PC's pivot (which is at root height ~0).
	_dust_emitter.position = Vector3(0, 0.08, 0)
	add_child(_dust_emitter)
