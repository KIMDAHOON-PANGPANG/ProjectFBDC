class_name Boss
extends CharacterBody3D

## 멧돼지 돌진 보스. 추적 → 호밍 윈드업(돌진 레인 데칼) → 직진 돌진 → 정지 회복의
## 상태머신(BState)으로 동작한다. 돌진은 회피 전용 패턴(패리 없음).
##
## Owner (Main) listens for `boss_defeated` to invoke the chapter-clear flow.

signal boss_defeated
signal summon_requested(origin: Vector3, count: int)

## 멧돼지 AI 상태 — 추적 / 돌진 호밍 윈드업 / 돌진 / 회복.
enum BState { CHASE, WINDUP, CHARGE, RECOVER }

## 데이터 관리 로더 (preload + 정적 호출 — 헤드리스 class_name 캐시 안전).
const _CombatDataScript := preload("res://scripts/managers/CombatData.gd")
## 머리 위 HP+아머 바(코드 인스턴스 — .tscn 수정 불필요).
const _HpBar3DScene := preload("res://scenes/ui/HpBar3D.tscn")
## 머리 위 상태(버프/디버프) 아이콘 스트립(공용 — 표식 등 폴링 표시).
const _StatusStripScript := preload("res://scenes/ui/StatusIconStrip3D.gd")
## 표식 '참(斬)' 표시 — 청백(冷光) 아이콘. 만개(5) 도달 시 _poll_status 에서 붉게 점멸.
## 단 보스는 만개여도 납도 처형 면역(marks×피해만) — 점멸은 '많이 새겨짐' 연출 의미.
const _MARK_COLOR := Color(0.67, 0.8, 1.0)
const _MARK_CAP := 5.0

## 보스 변형 식별자 (1=Boss / 2=Boss2 / 3=Boss3). 각 .tscn 에서 지정.
## CombatData 가 enemy_combat.json 의 "보스_<id>" 섹션을 적용하는 키.
@export var boss_id: int = 1

@export var move_speed: float = 1.5
@export var detection_range: float = 30.0
@export var attack_range: float = 2.4
@export var attack_cooldown: float = 1.6
@export var max_hp: int = 15
## ── 경직(아머 게이지) ── 보스는 데미지 6 누적되면 경직 → 큰 반격 기회. 0=없음. enemy.csv 로 조절.
@export var armor_max: int = 6
@export var stagger_duration: float = 0.6

@export var number_label_path: NodePath
@export var mesh_path: NodePath
## 보스 해골 스프라이트 틴트(보스별 테마색). Boss2=보라/Boss3=청록은 .tscn 에서 지정.
@export var boss_tint: Color = Color(1.0, 0.55, 0.55)

## Fan-telegraph tuning. Boss is a wide, hard-hitting swing — bigger arc
## and reach than mobs, 2 damage on connect (same as the legacy attack).
@export var attack_damage: int = 2
@export var fan_radius: float = 3.0
@export var fan_angle_deg: float = 90.0

@export_group("Charge (멧돼지 돌진 — 기본 패턴)")
## 돌진을 시작할 수 있는 최대 거리(유닛). "아주 먼 거리에서" — 크게.
@export var charge_range: float = 22.0
## 호밍 텔레그래프 시간(초) — 이 동안 데칼이 PC 를 따라다니다 고정 후 돌진.
@export var charge_windup: float = 1.0
## 돌진 속도(유닛/초) — 빠르게.
@export var charge_speed: float = 18.0
## 돌진 거리(유닛) — 길게.
@export var charge_distance: float = 16.0
## 돌진 적중 데미지.
@export var charge_damage: int = 2
## 돌진 후 정지(초) — "잠시 정지" 회복.
@export var charge_recover: float = 0.9
## 돌진 쿨다운(초) — 다음 돌진까지 간격.
@export var charge_cooldown: float = 1.6
## 돌진 판정/데칼 폭(유닛).
@export var charge_width: float = 2.4
## 돌진 레인 데칼 — Boss.tscn 에 ChargeTelegraph.tscn 주입.
@export var charge_telegraph_scene: PackedScene

@export_group("Summon (근접 몹 소환 — 돌진과 번갈아)")
## 소환 주기(초). 이 간격마다 보스가 근접 몹 소환을 요청한다.
@export var summon_interval: float = 5.0
## 한 번에 소환할 근접 몹 수.
@export var summon_count: int = 3
## 소환 몹이 놓이는 보스 주변 링 반경(유닛).
@export var summon_ring_radius: float = 3.0

@export_group("Variant Signal")
## 레거시 보스 변형 식별용 비율(WHITE 시그널 — 현재 시각 구분만, 패리 없음).
## CombatData 가 monster_table.tres 의 white_ratio 를 브리지한다.
@export var white_ratio: float = 0.0

## Boss body footprint half-size on XZ (BoxShape3D in Boss.tscn is 2.1
## cube, half = 1.05). The PC's iaido dash uses direct global_position
## assignment which bypasses physics — if the dash terminates inside
## the boss body the PC gets wedged, since neither side's CharacterBody
## solver can push them out from full overlap. We snap the PC to the
## nearest face each tick when overlap is detected.
const _BOSS_HALF_XZ: float = 1.05
## PC capsule radius (Player.tscn: CapsuleShape3D radius = 0.35).
const _PC_RADIUS: float = 0.35
## Slack added on top so the eject lands clearly outside the body —
## previously 0.05 was too tight and floating-point noise caused the
## eject to retrigger every tick. 0.25 = unambiguous clearance.
const _EJECT_SLACK: float = 0.25
## PC State.DASHING enum value (Player.gd:13). Hard-coded to avoid a
## cross-script dependency for one constant.
const _PC_STATE_DASHING: int = 2

var time_scale_mult: float = 1.0

var _player: Node3D
## 보스 박스의 월드 X/Z 반경(노드 스케일 반영) — _ready 에서 콜리전 셰입×scale 로
## 산출. PC 끼임 방지 eject 경계 계산에 쓴다(스케일을 바꿔도 자동 추종).
var _boss_half_xz: float = _BOSS_HALF_XZ
var _health: HealthComponent
var _attack_cd: float = 0.0
var _dead: bool = false
var _label: Label3D
var _sprite: Sprite3D

# ── 멧돼지 돌진 상태 ──
var _bstate: int = BState.CHASE
var _charge_dir: Vector3 = Vector3.FORWARD
var _windup_t: float = 0.0
var _recover_t: float = 0.0
var _charge_t: float = 0.0
var _charge_start: Vector3 = Vector3.ZERO
var _charge_hit_done: bool = false
var _charge_decal: Node3D = null
var _summon_t: float = 0.0
## 머리 위 상태 아이콘 스트립(표식/버프 폴링 표시). _ready 에서 인스턴스.
var _status_strip: Node = null

func _ready() -> void:
	add_to_group("enemies")
	add_to_group("boss")
	# 돌진(멧돼지) 보스 — 근접 부채 패턴을 안 쓰므로 melee_enemies 그룹 미가입.
	collision_layer = 1 << 2  # Enemy
	# 비대칭 충돌 — 보스는 Player 를 마스크해 PC 와 겹치면 스스로 빠져나간다(=PC 가
	# 밀침). PC 는 Enemy 를 마스크하지 않아 보스에 안 막히고 안 밀린다. 한 방향
	# 디펜트레이션이라 예전의 상호 끼임/밀림 + eject 호출이 일으킨 "쭉 밀림" 버그는
	# 재발하지 않는다(eject 호출은 _physics_process 에서 제거된 상태 유지).
	collision_mask = (1 << 0) | (1 << 1)  # World + Player

	# 데이터 관리 — enemy_combat.json(보스_공통 + 보스_<boss_id>) 적용. 보스 HP 는
	# 변형별 고정값이라 여기서 적용되고, 아래 _health.setup(max_hp) 가 그 값을 쓴다.
	_CombatDataScript.apply_to_enemy(self, "boss")

	_health = get_node_or_null("HealthComponent") as HealthComponent
	if _health != null:
		_health.setup(max_hp)
		_health.setup_armor(armor_max, stagger_duration)
		_health.died.connect(_on_died)
		_health.damaged.connect(_on_damaged)
		# 머리 위 HP+아머 바(코드 인스턴스). width 는 _build 전에 설정해야 반영됨.
		var bar := _HpBar3DScene.instantiate()
		if "width" in bar:
			bar.width = 1.2  # 보스는 더 넓은 바
		if "follow_offset" in bar:
			bar.follow_offset = Vector3(0, 2.7, 0)
		add_child(bar)
		if bar.has_method("attach_health"):
			bar.call("attach_health", _health)

	# 머리 위 상태 아이콘 스트립 — HP 바(2.7) 위.
	var strip := _StatusStripScript.new()
	if "follow_offset" in strip:
		strip.follow_offset = Vector3(0, 3.3, 0)
	add_child(strip)
	_status_strip = strip

	_label = get_node_or_null(number_label_path) as Label3D
	if _label != null:
		_label.text = str(max_hp)

	# 해골 스프라이트 — 보스 테마색(boss_tint)으로 틴트. 알파 안전(d3d12).
	_sprite = get_node_or_null(mesh_path) as Sprite3D
	if _sprite != null:
		_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_sprite.shaded = false
		_sprite.transparent = true
		_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		_sprite.alpha_scissor_threshold = 0.5
		_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_sprite.modulate = boss_tint

	_player = get_tree().get_first_node_in_group("player")

	# 보스 박스 월드 X/Z 반경 산출(노드 스케일 반영) — PC 끼임 방지 eject 경계용.
	var _cs := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if _cs != null and _cs.shape is BoxShape3D:
		_boss_half_xz = (_cs.shape as BoxShape3D).size.x * 0.5 * scale.x

	_summon_t = summon_interval


## 머리 위 상태 아이콘 폴링 — 보스 meta(slash_mark)를 매 프레임 읽어 스트립 갱신.
func _poll_status() -> void:
	if _status_strip == null or not is_instance_valid(_status_strip):
		return
	var marks := int(get_meta("slash_mark", 0))
	if marks > 0:
		var full: bool = marks >= int(_MARK_CAP)
		var col: Color = _MARK_COLOR
		if full:
			var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 90.0)
			col = Color(1.0, 0.25, 0.25).lerp(Color(1.0, 0.7, 0.7), pulse)
		_status_strip.call("set_status", "slash_mark", {
			"value": clampf(float(marks) / _MARK_CAP, 0.0, 1.0),
			"mode": 0,
			"color": col,
			"icon": null,
		})
	else:
		_status_strip.call("clear_status", "slash_mark")

func _physics_process(delta: float) -> void:
	if _dead:
		return
	_poll_status()
	delta *= time_scale_mult
	if _attack_cd > 0.0:
		_attack_cd -= delta

	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		velocity = Vector3.ZERO
		move_and_slide()
		return

	# PC 가 보스 박스 안에 끼면(일섬 관통 실패 등) 박스 밖으로 밀어낸다. 대시 중엔
	# 내부에서 스킵 — 슬래시 대시의 프레임별 위치 갱신과 싸우지 않게(끼임만 해소).
	_eject_overlapping_player()

	# 경직(아머 소거) 중 — 보스도 이동/공격 정지(사망이 아닐 때만). 큰 반격 기회.
	if _health != null:
		_health.tick_stagger(delta)
		if _health.is_staggered():
			velocity = Vector3.ZERO
			move_and_slide()
			return

	_tick_summon(delta)

	# ── 멧돼지 AI: 추적 → 돌진(호밍 윈드업 → 고정 → 돌진) → 잠시 정지 ──
	match _bstate:
		BState.CHASE:
			_state_chase(delta)
		BState.WINDUP:
			_state_windup(delta)
		BState.CHARGE:
			_state_charge(delta)
		BState.RECOVER:
			_state_recover(delta)

# ══════════════ 멧돼지 돌진 AI (추적 → 호밍 윈드업 → 돌진 → 정지) ══════════════

## 추적 — PC 로 천천히 다가간다. 돌진 사거리 안 + 쿨 차면 윈드업 진입.
func _state_chase(delta: float) -> void:
	var to := _player.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	if _attack_cd <= 0.0 and dist <= charge_range and dist > 0.5:
		_begin_windup(to.normalized())
		return
	var dir := to.normalized()
	velocity.x = dir.x * move_speed * time_scale_mult
	velocity.z = dir.z * move_speed * time_scale_mult
	velocity.y = 0.0
	move_and_slide()

## 윈드업 시작 — 제자리에 서서 돌진 레인 데칼 생성(이후 매 프레임 호밍).
func _begin_windup(dir: Vector3) -> void:
	_bstate = BState.WINDUP
	_windup_t = charge_windup
	_charge_dir = dir
	velocity = Vector3.ZERO
	move_and_slide()
	if charge_telegraph_scene != null:
		_charge_decal = charge_telegraph_scene.instantiate()
		var host := _effect_host()
		if host == null:
			_charge_decal.queue_free()
			_charge_decal = null
		else:
			host.add_child(_charge_decal)
			if _charge_decal.has_method("set_lane"):
				_charge_decal.call("set_lane", global_position, _charge_dir, charge_width, charge_distance)

## 윈드업 — 데칼이 charge_windup 초 동안 PC 를 호밍하며 따라다닌다. 끝나면 고정 + 돌진.
func _state_windup(delta: float) -> void:
	velocity = Vector3.ZERO
	move_and_slide()
	_windup_t -= delta
	# 호밍 — PC 방향으로 매 프레임 재조준.
	var to := _player.global_position - global_position
	to.y = 0.0
	if to.length_squared() > 0.0001:
		_charge_dir = to.normalized()
	if _charge_decal != null and is_instance_valid(_charge_decal) and _charge_decal.has_method("set_lane"):
		_charge_decal.call("set_lane", global_position, _charge_dir, charge_width, charge_distance)
		# 전조 진행도(0=시작 → 1=발사 순간)를 데칼에 전달 — 중심→끝으로 fill 차오름.
		if _charge_decal.has_method("set_fill") and charge_windup > 0.0001:
			var frac: float = 1.0 - (_windup_t / charge_windup)
			_charge_decal.call("set_fill", frac)
	if _windup_t <= 0.0:
		# 고정 — 데칼 색 진하게, 카메라 짧게 흔들(돌진 직전 긴장).
		if _charge_decal != null and is_instance_valid(_charge_decal) and _charge_decal.has_method("lock"):
			_charge_decal.call("lock")
		var rig := get_tree().get_first_node_in_group("camera_rig")
		if rig != null and rig.has_method("shake"):
			rig.call("shake", 0.12, 0.18)
		_bstate = BState.CHARGE
		_charge_start = global_position
		_charge_t = 0.0
		_charge_hit_done = false

## 돌진 — 고정된 방향으로 빠르게 직진. charge_distance 만큼(또는 안전 캡) 가면 멈춘다.
## 지나가며 PC 와 가까워지면 1회 데미지.
func _state_charge(delta: float) -> void:
	velocity.x = _charge_dir.x * charge_speed * time_scale_mult
	velocity.z = _charge_dir.z * charge_speed * time_scale_mult
	velocity.y = 0.0
	move_and_slide()
	if not _charge_hit_done and _player != null and is_instance_valid(_player):
		var d := _player.global_position - global_position
		d.y = 0.0
		if d.length() <= charge_width * 0.5 + _PC_RADIUS + 0.4:
			_charge_hit_done = true
			if _player.has_method("take_hit"):
				_player.call("take_hit", charge_damage)
	_charge_t += delta
	var traveled := (global_position - _charge_start).length()
	var max_t: float = charge_distance / maxf(charge_speed, 1.0) + 0.4  # 벽 막힘 등 안전 캡
	if traveled >= charge_distance or _charge_t >= max_t:
		_end_charge()

## 소환 타이머 — summon_interval 마다, 돌진/윈드업 중이 아닐 때(CHASE/RECOVER)만
## 소환을 요청한다. 이렇게 게이트하면 '소환 → 돌진 → (회복) → 소환' 으로 자연히
## 번갈아 나온다(돌진 중엔 타이머가 차도 발동을 미뤄 겹침을 막음).
func _tick_summon(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_summon_t -= delta
	if _summon_t > 0.0:
		return
	# 돌진/윈드업 중이면 발동 보류(타이머는 0 이하로 유지 → CHASE/RECOVER 복귀 즉시 발동).
	if _bstate == BState.WINDUP or _bstate == BState.CHARGE:
		return
	_summon_t = summon_interval
	summon_requested.emit(global_position, summon_count)


func _end_charge() -> void:
	_bstate = BState.RECOVER
	_recover_t = charge_recover
	_attack_cd = charge_cooldown
	velocity = Vector3.ZERO
	move_and_slide()
	if _charge_decal != null and is_instance_valid(_charge_decal):
		_charge_decal.queue_free()
	_charge_decal = null

## 잠시 정지 — 돌진 후 회복. 끝나면 추적으로.
func _state_recover(delta: float) -> void:
	velocity = Vector3.ZERO
	move_and_slide()
	_recover_t -= delta
	if _recover_t <= 0.0:
		_bstate = BState.CHASE


## take_hit — 돌진 보스는 패리 패턴이 없다(돌진은 회피 전용). 그냥 피해.
## amount 기본 1, SlashAttack 가 보스 데미지(boss_slash_damage_normal)를 넘겨 호출.
func take_hit(amount: int = 1) -> void:
	if _dead:
		return
	if _health != null:
		_health.take_damage(amount)

## If the PC's XZ position is inside our extended footprint (boss half-
## size + PC radius + slack), snap them outward along the axis with the
## smallest penetration. Box-vs-circle eject — picks the nearest face
## rather than crossing a corner. Direct global_position assignment is
## the only thing that reliably works against an iaido dash that
## teleported them in here, since neither character body can solve out
## from full inside-overlap.
##
## We deliberately SKIP the eject while the PC is mid-dash. The dash
## sets global_position via a frame-by-frame lerp; ejecting at the same
## time means we push the PC off the dash path, then the dash's next
## frame snaps them back inside, then we push again — a tug-of-war
## that reads visually as the PC "sliding endlessly" alongside us.
## Letting the dash complete first and ejecting on the next tick gives
## a single clean snap to the boss's surface.
func _eject_overlapping_player() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var pc := _player as CharacterBody3D
	if pc == null:
		return
	if "_state" in _player and _player._state == _PC_STATE_DASHING:
		return  # Dash overrides position; eject would fight it.
	var dx: float = pc.global_position.x - global_position.x
	var dz: float = pc.global_position.z - global_position.z
	var bound: float = _boss_half_xz + _PC_RADIUS + _EJECT_SLACK
	if absf(dx) >= bound or absf(dz) >= bound:
		return  # Not inside the extended footprint — nothing to do.
	var push_x: float = bound - absf(dx)
	var push_z: float = bound - absf(dz)
	if push_x <= push_z:
		var sx: float = 1.0 if dx >= 0.0 else -1.0
		pc.global_position.x += sx * push_x
	else:
		var sz: float = 1.0 if dz >= 0.0 else -1.0
		pc.global_position.z += sz * push_z

func _on_damaged(_amount: int) -> void:
	if _label != null and _health != null:
		_label.text = str(max(_health.hp, 0))
	# Brief white flash on hit (skip lethal hit to avoid fighting death anim).
	if _sprite == null or _health == null or _health.hp <= 0:
		return
	var original: Color = boss_tint
	var flash: Color = Color(2.5, 2.5, 2.5, original.a)
	var t := create_tween()
	t.tween_property(_sprite, "modulate", flash, 0.04)
	t.tween_property(_sprite, "modulate", original, 0.14)

func _on_died() -> void:
	if _dead:
		return
	_dead = true
	# 돌진/윈드업 중 죽으면 레인 데칼이 남으니 정리.
	if _charge_decal != null and is_instance_valid(_charge_decal):
		_charge_decal.queue_free()
	_charge_decal = null
	if _health != null:
		_health.clear_stagger()
	# Stash death position for the EXP gem drop (tree_exited is too late).
	set_meta("death_position", global_position)
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 0
	boss_defeated.emit()
	_play_death_fade()

func _play_death_fade() -> void:
	var duration := 0.9
	var t := create_tween()
	t.set_parallel(true)
	if _sprite != null:
		t.tween_property(_sprite, "modulate:a", 0.0, duration)
	if _label != null:
		t.tween_property(_label, "modulate:a", 0.0, duration)
	t.tween_property(self, "position:y", position.y - 1.0, duration)
	t.chain().tween_callback(_safe_free)
	# Backup free — the fade tween stalls under tree.paused (level-up) or a
	# strong time-scale, which would otherwise strand a faded, collision-off
	# boss with its HP bar floating. Scene-timer past the tween duration
	# guarantees the free; _safe_free de-dupes the race.
	var tree := get_tree()
	if tree != null:
		tree.create_timer(duration + 0.2).timeout.connect(_safe_free)


## Free exactly once — death tween callback and backup timer may race.
func _safe_free() -> void:
	if is_instance_valid(self) and not is_queued_for_deletion():
		queue_free()

## World node to parent the charge telegraph under. Active scene normally;
## falls back to parent / tree root during a scene reload (current_scene null).
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
