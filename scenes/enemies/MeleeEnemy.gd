class_name MeleeEnemy
extends CharacterBody3D

## Melee chaser: walks toward the player, then commits to a telegraphed
## fan-swing attack instead of dealing damage on body contact. Body
## collision no longer hurts the PC at all — every monster in the
## "melee_enemies" group resolves its damage through the shared
## FanTelegraph effect (red ground decal, 0.5s wind-up, line sweep).

@export var data: EnemyData
@export var sprite_rig_path: NodePath

## 행동 타입 — CHASER = 추적 후 근접(부채) 공격 전용. LEAPER = 리프(곡선 점프
## + 빨간 원형 슬램) 전용. Leaper.tscn 이 LEAPER 로 설정해 베리에이션2 가 된다.
enum Behavior { CHASER, LEAPER }
@export var behavior: int = Behavior.CHASER
## 비주얼 교체(리퍼 색 구분 등). null 이면 DEFAULT_VISUALS 사용.
@export var visuals_override: CharacterVisuals

## Distance at which the enemy stops and begins the fan-swing telegraph.
## Sized a touch beyond the combined capsule radii so the wind-up
## triggers from a readable stand-off rather than from a body-mash.
@export var attack_range: float = 1.6
## Damage applied to PC inside the fan area when the sweep resolves.
@export var attack_damage: int = 1
## Fan dimensions for THIS monster's telegraph (Elite/Boss override).
@export var fan_radius: float = 1.8
@export var fan_angle_deg: float = 70.0
## Shared FanTelegraph PackedScene wired in MeleeEnemy.tscn.
@export var telegraph_scene: PackedScene

## ── 리프(내려찍기) 어택 ── 중거리에서 확률적으로 곡선 점프 후 슬램.
## leap_chance / leap_radius / leap_damage 는 enemy.csv(근접몹)에서 조절.
@export var leap_chance: float = 0.3
@export var leap_range: float = 6.0
@export var leap_radius: float = 2.2
@export var leap_damage: int = 1
@export var leap_duration: float = 0.7
@export var leap_height: float = 2.6
@export var leap_recheck: float = 0.6
## 빨간 원형 데칼 텔레그래프(LeapTelegraph) — MeleeEnemy.tscn 에서 주입.
@export var leap_telegraph_scene: PackedScene

const DEFAULT_VISUALS: CharacterVisuals = preload("res://resources/enemies/melee_visuals.tres")
## 데이터 관리 로더 (preload + 정적 호출 — 헤드리스 class_name 캐시 안전).
const _CombatDataScript := preload("res://scripts/managers/CombatData.gd")

## Multiplier injected by bullet-time. 1.0 = normal, 0.25 = slow.
var time_scale_mult: float = 1.0
## Mob level. WaveManager bumps this to 2 past the 1:00 mark; EXP system
## reads it to award the right EXP (LV2 = 2 EXP instead of 1).
var _lv: int = 1

var _player: Node3D
var _sprite_rig: SpriteRig
var _health: HealthComponent
var _dead: bool = false
## True from telegraph spawn until the FanTelegraph self-frees — keeps us
## rooted in place and prevents a second telegraph stacking on top of an
## in-flight wind-up.
var _attacking: bool = false
## Time until the next attack is allowed. Includes telegraph wind-up so
## the post-attack recovery sits AFTER the swing resolves.
var _attack_cd: float = 0.0
## In-flight FanTelegraph ref (spawn-and-forget, but tracked so a
## preemptive kill can cancel it — ⏱ M3 후속). Cleared on telegraph done.
var _active_telegraph: Node = null
## 리프 상태 — true 동안 곡선 점프 중(추격/공격 잠금).
var _leaping: bool = false
var _leap_start: Vector3
var _leap_end: Vector3
var _leap_elapsed: float = 0.0
var _active_leap_decal: Node = null

func _ready() -> void:
	if data == null:
		data = EnemyData.new()
		data.type = EnemyData.EnemyType.MELEE
	if visuals_override != null:
		data.visuals = visuals_override
	elif data.visuals == null:
		data.visuals = DEFAULT_VISUALS

	# 데이터 관리 — 행동 타입에 맞는 CSV 행 적용 (melee=101 / leaper=104).
	_CombatDataScript.apply_to_enemy(self, "leaper" if behavior == Behavior.LEAPER else "melee")

	add_to_group("enemies")
	# Opt-in to the melee category — FanTelegraph attacks live here.
	# Instance-level (not class-level) so future archetypes can mix.
	add_to_group("melee_enemies")
	collision_layer = 1 << 2  # Enemy
	collision_mask = (1 << 0) | (1 << 1)  # World + Player (bump only, no damage)

	_sprite_rig = get_node_or_null(sprite_rig_path) as SpriteRig
	if _sprite_rig != null:
		_sprite_rig.fallback_color = Color(1.0, 0.45, 0.4)
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
	if _attack_cd > 0.0:
		_attack_cd -= delta

	# 리프 점프 중 — 곡선 이동만 처리(추격/공격 잠금).
	if _leaping:
		_update_leap(delta)
		return

	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		velocity = Vector3.ZERO
		move_and_slide()
		return

	# Rooted during the wind-up: stand still, face direction is locked at
	# telegraph spawn, sweep + damage happen out of our hands now.
	if _attacking:
		velocity = Vector3.ZERO
		move_and_slide()
		if _sprite_rig != null:
			_sprite_rig.set_state(SpriteRig.State.ATTACK)
		return

	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()

	# CHASER — 추적 후 근접(부채) 공격 전용.
	if behavior == Behavior.CHASER:
		if dist <= attack_range and _attack_cd <= 0.0:
			_begin_telegraph(to_player)
			return
	# LEAPER — 리프(곡선 점프 + 빨간 원형 슬램) 전용. leap_range 안에서 확률 발동.
	# 실패하면 leap_recheck 동안 재굴림을 막아 매 프레임 굴리지 않는다.
	elif behavior == Behavior.LEAPER:
		if leap_telegraph_scene != null and _attack_cd <= 0.0 and dist <= leap_range:
			if randf() < leap_chance:
				_begin_leap(to_player, dist)
				return
			_attack_cd = leap_recheck

	# No detection_range gate — the mob always chases the PC regardless
	# of distance, so the player can never "outrun" the swarm by sprinting
	# to a corner of the world. The constant-velocity chase is a couple
	# of vector ops per tick, so even hundreds of mobs cost nothing
	# measurable; the real performance ceiling is rendering, not AI.
	var dir := to_player.normalized()
	velocity.x = dir.x * data.move_speed * time_scale_mult
	velocity.z = dir.z * data.move_speed * time_scale_mult
	velocity.y = 0.0
	move_and_slide()
	if _sprite_rig != null:
		_sprite_rig.set_state(SpriteRig.State.WALK)
		_sprite_rig.set_facing(dir.x)

## Spawn a FanTelegraph at our feet aimed at the PC. We commit the
## position/direction now — the telegraph itself owns the rest (wind-up
## timer, sweep, damage). When the effect self-frees we clear `_attacking`
## via its `tree_exited` signal.
func _begin_telegraph(to_player_xz: Vector3) -> void:
	if telegraph_scene == null:
		# Without a wired scene we can't attack — stay rooted to avoid
		# walking into the PC and dealing zero damage forever. Cooldown
		# still ticks so a later wave / hot-swap can recover.
		_attack_cd = data.melee_attack_cooldown
		return
	var fan := telegraph_scene.instantiate()
	get_tree().current_scene.add_child(fan)
	if fan.has_method("configure"):
		fan.call("configure", global_position, to_player_xz,
			fan_radius, fan_angle_deg, attack_damage, 0.5, 0.15)
	if fan.has_signal("tree_exited"):
		fan.tree_exited.connect(_on_telegraph_done, CONNECT_ONE_SHOT)
	_active_telegraph = fan
	_attacking = true
	# Cooldown spans the full telegraph + sweep + a recovery breath.
	_attack_cd = data.melee_attack_cooldown + 0.5
	velocity = Vector3.ZERO
	move_and_slide()
	if _sprite_rig != null:
		_sprite_rig.set_state(SpriteRig.State.ATTACK)
		_sprite_rig.set_facing(to_player_xz.x)

func _on_telegraph_done() -> void:
	_attacking = false
	_active_telegraph = null

## 리프 시작 — 착지 지점에 빨간 원형 데칼을 깔고 곡선 점프를 건다.
func _begin_leap(to_player_xz: Vector3, dist: float) -> void:
	var dir := to_player_xz
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3(1, 0, 0)
	var travel: float = min(dist, leap_range)
	_leap_start = global_position
	_leap_end = global_position + dir * travel
	_leap_end.y = _leap_start.y
	_leap_elapsed = 0.0
	_leaping = true
	# 점프 + 슬램 + 회복 동안 다음 공격 잠금.
	_attack_cd = data.melee_attack_cooldown + leap_duration + 0.4
	var decal = leap_telegraph_scene.instantiate()
	get_tree().current_scene.add_child(decal)
	if decal.has_method("configure"):
		# windup = 점프 시간 → 데칼이 착지 순간에 슬램 데미지 판정.
		decal.call("configure", _leap_end, leap_radius, leap_damage, leap_duration)
	_active_leap_decal = decal
	velocity = Vector3.ZERO
	if _sprite_rig != null:
		_sprite_rig.set_state(SpriteRig.State.ATTACK)
		_sprite_rig.set_facing(dir.x)

## 곡선 점프 진행 — 포물선(t=0.5 정점)으로 착지 지점까지. 슬램 데미지는 데칼이
## 자기 windup 타이머로 착지 순간에 처리한다.
func _update_leap(delta: float) -> void:
	_leap_elapsed += delta
	var t: float = clamp(_leap_elapsed / max(leap_duration, 0.0001), 0.0, 1.0)
	var flat: Vector3 = _leap_start.lerp(_leap_end, t)
	var h: float = leap_height * 4.0 * t * (1.0 - t)
	global_position = Vector3(flat.x, _leap_start.y + h, flat.z)
	if _sprite_rig != null:
		_sprite_rig.set_state(SpriteRig.State.ATTACK)
	if t >= 1.0:
		global_position = _leap_end
		_leaping = false
		_active_leap_decal = null

## Called by SlashAttack when this enemy is inside its volume.
## 1 damage per slash so LV2 mobs (max_hp=2) take 2 hits, LV1 (max_hp=1) dies
## in one. WaveManager / spawn upgrades the EnemyData to bump max_hp.
func take_hit() -> void:
	if _dead:
		return
	# ⏱ Preemptive-slash reward (M3 후속) — a slash that lands DURING the
	# wind-up cancels the pending sweep so it deals no damage. Without
	# this the spawn-and-forget FanTelegraph still resolves and can clip
	# the PC even though the attacker is already dead. Only the killing
	# blow matters for LV1 (1 HP); for LV2 the first of two hits cancels.
	if _attacking and _active_telegraph != null and is_instance_valid(_active_telegraph):
		if _active_telegraph.has_method("cancel"):
			_active_telegraph.call("cancel")
		_active_telegraph = null
		_attacking = false
	# 슬래시(PC)는 잡몹/리퍼를 한 방에 정리한다(시그니처 유지). 비도는 Kunai 가
	# 자체 데미지로 HealthComponent 를 직접 깎으므로 이 경로와 무관.
	if _health != null:
		_health.take_damage(999)
	else:
		_on_died()

func _on_died() -> void:
	if _dead:
		return
	_dead = true
	# 리프 중 사망 — 펜딩 슬램 데칼 취소(유령 데미지 방지).
	_leaping = false
	if _active_leap_decal != null and is_instance_valid(_active_leap_decal) \
			and _active_leap_decal.has_method("cancel"):
		_active_leap_decal.call("cancel")
	_active_leap_decal = null
	# Stash the death position NOW — by the time tree_exited fires (where
	# Main drops the EXP gem) the node is detaching and global_position
	# reads as origin.
	set_meta("death_position", global_position)
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 0
	if _sprite_rig != null:
		_sprite_rig.play_death_then_free(self, 0.4)
	else:
		queue_free()
