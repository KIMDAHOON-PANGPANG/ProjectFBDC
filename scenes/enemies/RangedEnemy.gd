class_name RangedEnemy
extends CharacterBody3D

## Ranged archer: keeps preferred distance from player, shoots arrows.

@export var data: EnemyData
@export var sprite_rig_path: NodePath
@export var arrow_scene: PackedScene
## Telegraph laser shown for `aim_lock_duration` seconds before firing.
## When null we skip the telegraph (fall back to legacy instant fire).
@export var aim_laser_scene: PackedScene
@export var aim_lock_duration: float = 1.0

const DEFAULT_VISUALS: CharacterVisuals = preload("res://resources/enemies/ranged_visuals.tres")

## Multiplier injected by bullet-time. 1.0 = normal, 0.25 = slow.
var time_scale_mult: float = 1.0
## Mob level — for EXP awarding parity with MeleeEnemy.
var _lv: int = 1
## Set true while a laser is locked on, so we don't queue another shot.
var _aiming: bool = false

var _player: Node3D
var _sprite_rig: SpriteRig
var _health: HealthComponent
var _attack_cd: float = 1.0
var _dead: bool = false

func _ready() -> void:
	if data == null:
		data = EnemyData.new()
		data.type = EnemyData.EnemyType.RANGED
	if data.visuals == null:
		data.visuals = DEFAULT_VISUALS

	add_to_group("enemies")
	collision_layer = 1 << 2  # Enemy
	collision_mask = (1 << 0) | (1 << 1)  # World + Player

	_sprite_rig = get_node_or_null(sprite_rig_path) as SpriteRig
	if _sprite_rig != null:
		_sprite_rig.fallback_color = Color(1.0, 0.75, 0.25)
		_sprite_rig.set_visuals(data.visuals)

	_health = get_node_or_null("HealthComponent") as HealthComponent
	if _health != null:
		_health.setup(data.max_hp)
		_health.died.connect(_on_died)

	_player = get_tree().get_first_node_in_group("player")

func _physics_process(delta: float) -> void:
	if _dead:
		return
	# Bullet-time slows enemies but not the player. Apply to delta + velocity.
	delta *= time_scale_mult
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		velocity = Vector3.ZERO
		move_and_slide()
		return
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	var dir := to_player.normalized() if dist > 0.001 else Vector3.ZERO

	# No detection_range gate — the archer always closes / strafes toward
	# the PC's keep-distance band, so the PC can't escape arrow range by
	# walking off into the distance.

	# Keep distance: move away if too close, approach if too far, strafe-stop in band.
	var keep := data.ranged_keep_distance
	var band := 0.6
	var desired_dir := Vector3.ZERO
	if dist < keep - band:
		desired_dir = -dir
	elif dist > keep + band:
		desired_dir = dir
	velocity.x = desired_dir.x * data.move_speed * time_scale_mult
	velocity.z = desired_dir.z * data.move_speed * time_scale_mult
	velocity.y = 0.0
	move_and_slide()

	if _sprite_rig != null:
		_sprite_rig.set_facing(dir.x)
		if desired_dir.length_squared() > 0.01:
			_sprite_rig.set_state(SpriteRig.State.WALK)
		else:
			_sprite_rig.set_state(SpriteRig.State.IDLE)

	# Fire when in range and roughly facing.
	_attack_cd -= delta
	if not _aiming and dist <= data.ranged_attack_range and _attack_cd <= 0.0:
		# Frustum gate: only AIM at the PC when the PC is visible.
		# Off-screen shooters stay quiet (no AIM, no shot).
		if _player_in_view():
			_begin_aim_shot()
			_attack_cd = data.ranged_attack_cooldown + aim_lock_duration

## Returns true if the camera rig considers the PC visible.
## Used to gate the AIM telegraph so off-screen archers stay quiet.
func _player_in_view() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	var rig := get_tree().get_first_node_in_group("camera_rig")
	if rig == null or not rig.has_method("is_world_pos_visible"):
		# No camera = headless / early frame; default to visible to keep
		# behaviour usable.
		return true
	return rig.call("is_world_pos_visible", (_player as Node3D).global_position)

## Begin a telegraphed shot: spawn an AimLaser pointed at the PC. The laser
## tracks the player for `aim_lock_duration` seconds, then fires the arrow.
func _begin_aim_shot() -> void:
	var ascene: PackedScene = arrow_scene
	if ascene == null:
		ascene = data.arrow_scene
	if ascene == null:
		return
	if aim_laser_scene == null:
		# Fallback: instant fire if no telegraph asset assigned.
		_fire_arrow_direct((_player.global_position - global_position).normalized())
		return
	_aiming = true
	var laser = aim_laser_scene.instantiate()
	get_tree().current_scene.add_child(laser)
	if laser.has_method("configure"):
		laser.call("configure", self, _player, ascene, data.arrow_speed)
	if laser.has_signal("tree_exited"):
		laser.tree_exited.connect(_on_aim_laser_done, CONNECT_ONE_SHOT)
	if _sprite_rig != null:
		_sprite_rig.set_state(SpriteRig.State.ATTACK)

func _on_aim_laser_done() -> void:
	_aiming = false

## Legacy direct-fire path (no telegraph) — kept for the no-laser-scene case.
func _fire_arrow_direct(direction: Vector3) -> void:
	var scene: PackedScene = arrow_scene
	if scene == null:
		scene = data.arrow_scene
	if scene == null:
		return
	var arrow = scene.instantiate()
	if "time_scale_mult" in arrow:
		arrow.time_scale_mult = time_scale_mult
	get_tree().current_scene.add_child(arrow)
	if arrow.has_method("launch"):
		arrow.speed = data.arrow_speed
		arrow.call("launch", direction, global_position + Vector3(0, 0.6, 0) + direction * 0.5)
	if _sprite_rig != null:
		_sprite_rig.set_state(SpriteRig.State.ATTACK)

func take_hit() -> void:
	if _dead:
		return
	if _health != null:
		_health.take_damage(1)
	else:
		_on_died()

func _on_died() -> void:
	if _dead:
		return
	_dead = true
	# Stash death position for the EXP gem drop (tree_exited is too late).
	set_meta("death_position", global_position)
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 0
	if _sprite_rig != null:
		_sprite_rig.play_death_then_free(self, 0.4)
	else:
		queue_free()
