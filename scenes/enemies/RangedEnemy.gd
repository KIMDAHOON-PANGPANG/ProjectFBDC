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
## ── 경직(아머 게이지) ── 0 = 아머 없음.
@export var armor_max: int = 0
@export var stagger_duration: float = 0.4
## ── 군집 분리 (Boid) ── 원거리끼리 겹치지 않게 PC 링 둘레로 360° 분산.
@export var separation_radius: float = 2.5
@export var separation_weight: float = 1.5
## ★엘리트 — 원거리 기반 변형. 일섬 10방(20HP)·처치 시 PC 레벨 1업. Main elite_time 비트/Testplay 버튼이 set.
@export var is_star_elite: bool = false
## ★엘리트 전용 HP — 인스턴스 HealthComponent 에 주입(공유 .tres 불변). 일섬 base 데미지 2 × 10방 ≈ 20.
@export var star_hp: int = 20

const DEFAULT_VISUALS: CharacterVisuals = preload("res://resources/enemies/ranged_visuals.tres")
## 데이터 관리 로더 (preload + 정적 호출 — 헤드리스 class_name 캐시 안전).
const _CombatDataScript := preload("res://scripts/managers/CombatData.gd")
## 스무스 넉백 컴포넌트(피격/피탄 시 부드럽게 밀림).
const _KnockbackScript := preload("res://scripts/components/Knockback.gd")
## 전체 원거리 적 중 동시에 사격(텔레그래프)할 수 있는 비율 — 나머지는 추적/대기.
const _FIRE_FRACTION: float = 0.25
## 머리 위 HP 바(모든 몬스터 공통 — 코드 인스턴스).
const _HpBar3DScene := preload("res://scenes/ui/HpBar3D.tscn")
## 머리 위 상태(버프/디버프) 아이콘 스트립(공용 — 표식 등 폴링 표시).
const _StatusStripScript := preload("res://scenes/ui/StatusIconStrip3D.gd")
## 표식 표시(holrim 슬롯) — 핑크 디버프 아이콘 색/상한. S2 가 slash_mark 로 의미 전환 예정.
const _HOLRIM_COLOR := Color(1.0, 0.37, 0.69)
const _HOLRIM_CAP := 8.0

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
## 스무스 넉백 상태(피격/피탄 시 밀림).
var _kb = _KnockbackScript.new()
## 머리 위 상태 아이콘 스트립(표식/버프 폴링 표시). _ready 에서 인스턴스.
var _status_strip: Node = null

func _ready() -> void:
	if data == null:
		data = EnemyData.new()
		data.type = EnemyData.EnemyType.RANGED
	if data.visuals == null:
		data.visuals = DEFAULT_VISUALS

	# 데이터 관리 — enemy_combat.json(원거리몹) 행동 파라미터 적용(HP 제외).
	_CombatDataScript.apply_to_enemy(self, "ranged")

	add_to_group("enemies")
	add_to_group("ranged_enemies")  # 동시 사격 캡(텔레그래프 회전) 계산용.
	collision_layer = 1 << 2  # Enemy
	collision_mask = (1 << 0) | (1 << 1)  # World + Player — PC 가 밀침(자기 빠져나감). PC 는 안 막힘.

	_sprite_rig = get_node_or_null(sprite_rig_path) as SpriteRig
	if _sprite_rig != null:
		_sprite_rig.fallback_color = Color(1.0, 0.75, 0.25)
		_sprite_rig.set_visuals(data.visuals)

	_health = get_node_or_null("HealthComponent") as HealthComponent
	if _health != null:
		_health.setup(data.max_hp)
		if is_star_elite:
			_health.setup(star_hp)
			add_to_group("elites")
			add_to_group("star_elites")
		_health.setup_armor(armor_max, stagger_duration)
		_health.died.connect(_on_died)
		# 머리 위 HP 바 — 모든 몬스터 공통(원거리). 코드 인스턴스.
		var bar := _HpBar3DScene.instantiate()
		if "follow_offset" in bar:
			bar.follow_offset = Vector3(0, 1.55, 0)
		add_child(bar)
		if bar.has_method("attach_health"):
			bar.call("attach_health", _health)

	# 머리 위 상태 아이콘 스트립 — HP 바(1.55) 위.
	var strip := _StatusStripScript.new()
	if "follow_offset" in strip:
		strip.follow_offset = Vector3(0, 2.1, 0)
	add_child(strip)
	_status_strip = strip

	if is_star_elite:
		var star := Label3D.new()
		star.text = "★"
		star.modulate = Color(1.0, 0.85, 0.2)
		star.font_size = 64
		star.pixel_size = 0.012
		star.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		star.no_depth_test = true
		star.position = Vector3(0, 2.5, 0)
		add_child(star)
		if _sprite_rig != null:
			_sprite_rig.fallback_color = Color(1.0, 0.85, 0.2)

	_player = get_tree().get_first_node_in_group("player")

## 머리 위 상태 아이콘 폴링 — 적 meta(holrim_marks 등)를 매 프레임 읽어 스트립 갱신.
func _poll_status() -> void:
	if _status_strip == null or not is_instance_valid(_status_strip):
		return
	var marks := int(get_meta("holrim_marks", 0))
	if marks > 0:
		_status_strip.call("set_status", "holrim", {
			"value": clampf(float(marks) / _HOLRIM_CAP, 0.0, 1.0),
			"mode": 0,
			"color": _HOLRIM_COLOR,
			"icon": null,
		})
	else:
		_status_strip.call("clear_status", "holrim")

func _physics_process(delta: float) -> void:
	if _dead:
		return
	_poll_status()
	# Bullet-time slows enemies but not the player. Apply to delta + velocity.
	delta *= time_scale_mult
	# 스무스 넉백 — 피탄/피격 시 부드럽게 밀고 감쇠.
	_kb.integrate(self, delta)
	# 경직(아머 소거) 중 — 이동/사격 정지.
	if _health != null:
		_health.tick_stagger(delta)
		if _health.is_staggered():
			velocity = Vector3.ZERO
			move_and_slide()
			return
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
	# 군집 분리 — 다른 원거리에서 멀어지는 힘을 섞어 PC 둘레로 골고루 퍼진다(겹침 방지).
	var move := desired_dir + _separation_vector() * separation_weight
	if move.length() > 1.0:
		move = move.normalized()
	velocity.x = move.x * data.move_speed * time_scale_mult
	velocity.z = move.z * data.move_speed * time_scale_mult
	velocity.y = 0.0
	move_and_slide()

	if _sprite_rig != null:
		_sprite_rig.set_facing(dir.x)
		# 실제 이동량 기준 IDLE/WALK — 거리유지 밴드 정지·막힘·분리떨림으로 velocity≈0 이면
		# IDLE. 임계값(0.04 = 0.2m/s 제곱)으로 분리벡터 미세 떨림 무시(깜빡임 방지).
		var moving: bool = Vector3(velocity.x, 0.0, velocity.z).length_squared() > 0.04
		_sprite_rig.set_state(SpriteRig.State.WALK if moving else SpriteRig.State.IDLE)

	# Fire when in range and roughly facing.
	_attack_cd -= delta
	if not _aiming and dist <= data.ranged_attack_range and _attack_cd <= 0.0:
		# 가시성 게이트(PC 가 화면에 보일 때만) + 동시 사격 캡(전체 원거리의 ~25%만
		# 동시에 쏘고 나머지는 추적/대기 — 활성 텔레그래프 수로 회전 제어).
		if _player_in_view() and _can_fire_now():
			_begin_aim_shot()
			_attack_cd = data.ranged_attack_cooldown + aim_lock_duration

## 동시 사격 캡 — 활성 텔레그래프(aim_lasers) 수가 전체 원거리의 _FIRE_FRACTION 미만일
## 때만 새로 쏜다. 레이저가 곧 슬롯이라(발사 후 자동 소멸) 누수 없이 자연 회전한다.
func _can_fire_now() -> bool:
	var total: int = get_tree().get_nodes_in_group("ranged_enemies").size()
	var cap: int = max(1, int(ceil(float(total) * _FIRE_FRACTION)))
	return get_tree().get_nodes_in_group("aim_lasers").size() < cap

## Boid 분리 — "ranged_enemies" 그룹 중 separation_radius 안 이웃에서 멀어지는 합력.
## keep_distance(반경 고정)와 합쳐지면 원거리들이 PC 둘레 360° 로 자연 분산(겹침 방지).
func _separation_vector() -> Vector3:
	if separation_radius <= 0.0:
		return Vector3.ZERO
	var avoid := Vector3.ZERO
	var my_pos := global_position
	for other in get_tree().get_nodes_in_group("ranged_enemies"):
		if other == self or not is_instance_valid(other):
			continue
		if "_dead" in other and other._dead:
			continue
		var d: Vector3 = my_pos - (other as Node3D).global_position
		d.y = 0.0
		var dd := d.length()
		if dd < separation_radius and dd > 0.01:
			avoid += d.normalized() * (1.0 - dd / separation_radius)
	return avoid


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
	var host := _effect_host()
	if host == null:
		laser.queue_free()
		_aiming = false
		return
	host.add_child(laser)
	if laser.has_method("configure"):
		laser.call("configure", self, _player, ascene, data.arrow_speed)
	if laser.has_signal("tree_exited"):
		laser.tree_exited.connect(_on_aim_laser_done, CONNECT_ONE_SHOT)
	if _sprite_rig != null:
		_sprite_rig.set_state(SpriteRig.State.ATTACK)

func _on_aim_laser_done() -> void:
	_aiming = false

## World node to parent spawned projectiles/lasers under. Active scene
## normally; falls back to our parent / tree root during a scene reload when
## current_scene is briefly null. Null only if fully detached.
func _effect_host() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	if tree.current_scene != null:
		return tree.current_scene
	var p := get_parent()
	if p != null:
		return p
	return tree.root

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
	var host := _effect_host()
	if host == null:
		arrow.queue_free()
		return
	host.add_child(arrow)
	if arrow.has_method("launch"):
		arrow.speed = data.arrow_speed
		arrow.call("launch", direction, global_position + Vector3(0, 0.6, 0) + direction * 0.5)
	if _sprite_rig != null:
		_sprite_rig.set_state(SpriteRig.State.ATTACK)

## 피격(플레이어 AOE)/피탄(비도) 시 외부에서 호출 — 스무스 넉백 시작.
func apply_knockback(dir: Vector3, speed: float) -> void:
	_kb.push(dir, speed)

func take_hit(amount: int = 1) -> void:
	if _dead:
		return
	if _health != null:
		_health.take_damage(amount)
	else:
		_on_died()

func _on_died() -> void:
	if _dead:
		return
	_dead = true
	# 사망 시 넉백/경직 즉시 정지 — 밀리던 중이라도 그 자리에서 죽는다(요청).
	_kb.vel = Vector3.ZERO
	if _health != null:
		_health.clear_stagger()
	# Stash death position for the EXP gem drop (tree_exited is too late).
	set_meta("death_position", global_position)
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 0
	if _sprite_rig != null:
		_sprite_rig.play_death_then_free(self, 0.4)
	else:
		queue_free()
