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
enum Behavior { CHASER, LEAPER, SLAMMER }
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
## 점프 전 "삐슝" 사전 경고(빨간 플래시) 시간(초). 끝나면 점프 + 착지 데칼 등장.
@export var leap_pre_time: float = 0.32
## 빨간 원형 데칼 텔레그래프(LeapTelegraph) — MeleeEnemy.tscn 에서 주입.
@export var leap_telegraph_scene: PackedScene

## ── 슬래머(내려찍기) 어택 ── SLAMMER behavior: 걸어와 제자리에서 slam_windup(2초)
## "힘주기" → slam_radius 넓은 원형 슬램(회피 전용). 기본 근접보다 느리지만 광역.
## PC 위치를 중심으로 데칼을 깔아 가만히 있으면 못 피한다. enemy.csv(105) 로 조절.
@export var slam_range: float = 2.2
@export var slam_windup: float = 2.0
@export var slam_radius: float = 2.8
@export var slam_damage: int = 1
@export var slam_cooldown: float = 1.8
## 슬램 데칼(LeapTelegraph 재사용) — Slammer.tscn 에서 주입.
@export var slam_telegraph_scene: PackedScene

## ── 군집 분리 (Boid) ── 잡몹/리퍼끼리 겹치지 않게 추격 방향에 회피력을 섞는다.
## enemy.csv(근접·리퍼) 에서 조절. 0 = 분리 끔. (엘리트는 자체 분리 별도 유지.)
@export var separation_radius: float = 1.3
@export var separation_weight: float = 1.2

## ── 경직(아머 게이지) ── 0 = 아머 없음(잡몹은 한 방 처치라 경직 미적용). enemy.csv 로 조절.
@export var armor_max: int = 0
@export var stagger_duration: float = 0.4

const DEFAULT_VISUALS: CharacterVisuals = preload("res://resources/enemies/melee_visuals.tres")
## 데이터 관리 로더 (preload + 정적 호출 — 헤드리스 class_name 캐시 안전).
const _CombatDataScript := preload("res://scripts/managers/CombatData.gd")
## 스무스 넉백 컴포넌트(피격/피탄 시 부드럽게 밀림).
const _KnockbackScript := preload("res://scripts/components/Knockback.gd")
## 머리 위 HP 바(모든 몬스터 공통 — 코드 인스턴스).
const _HpBar3DScene := preload("res://scenes/ui/HpBar3D.tscn")
## 머리 위 상태(버프/디버프) 아이콘 스트립(공용 — 표식 등 폴링 표시).
const _StatusStripScript := preload("res://scenes/ui/StatusIconStrip3D.gd")
## 표식 표시(holrim 슬롯) — 핑크 디버프 아이콘 색/상한. S2 가 slash_mark 로 의미 전환 예정.
const _HOLRIM_COLOR := Color(1.0, 0.37, 0.69)
const _HOLRIM_CAP := 8.0

## 군집 분리용 프레임당 공유 이웃 캐시(정적). 몹마다 get_nodes_in_group 을 부르면
## 할당/순회가 폭증하므로 프레임당 1회만 갱신해 모든 MeleeEnemy 가 공유한다.
## ▶ 추후 공간 그리드(C)로 확장하려면 _refresh_sep_list 의 리스트 채우는 줄만
##   교체하면 된다(이웃 질의 추상화 지점).
static var _sep_frame: int = -1
static var _sep_list: Array = []
## 리퍼 그룹 AI — 동시에 한 마리만 리프 공격하도록 공유 '공격 토큰' 보유자.
## null/무효(죽음·해제)면 자유. 보유자가 착지/사망/취소 시 해제. (게임 시작2 리퍼 개편)
static var _leap_attacker = null

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
## CHASER 공격 윈드업 단계 — true 동안 IDLE 정지(휘두르지 않음, PC 향함) + 데칼 차오름.
## FanTelegraph 의 `swing` 신호(히트 순간)에 false 로 풀리며 스트라이크 프레임으로 전환.
var _melee_windup: bool = false
## 리프 상태 — true 동안 곡선 점프 중(추격/공격 잠금).
var _leaping: bool = false
var _leap_start: Vector3
var _leap_end: Vector3
var _leap_above: Vector3
var _leap_elapsed: float = 0.0
var _leap_phase: int = 0  # 0=PRE(삐슝 사전경고) / 1=AIR(점프~체공~내려찍기)
var _leap_pre_t: float = 0.0
var _active_leap_decal: Node = null
## 슬래머 슬램 데칼(취소용 — 피격/사망 시 펜딩 슬램 제거).
var _active_slam_decal: Node = null
## 스무스 넉백 상태(피격/피탄 시 밀림).
var _kb = _KnockbackScript.new()
## 머리 위 상태 아이콘 스트립(표식/버프 폴링 표시). _ready 에서 인스턴스.
var _status_strip: Node = null

func _ready() -> void:
	if data == null:
		data = EnemyData.new()
		data.type = EnemyData.EnemyType.MELEE
	if visuals_override != null:
		data.visuals = visuals_override
	elif data.visuals == null:
		data.visuals = DEFAULT_VISUALS

	# 데이터 관리 — 행동 타입에 맞는 CSV 행 적용 (melee=101 / leaper=104 / slammer=105).
	var _kind := "melee"
	if behavior == Behavior.LEAPER:
		_kind = "leaper"
	elif behavior == Behavior.SLAMMER:
		_kind = "slammer"
	_CombatDataScript.apply_to_enemy(self, _kind)

	add_to_group("enemies")
	# Opt-in to the melee category — FanTelegraph attacks live here.
	# Instance-level (not class-level) so future archetypes can mix.
	add_to_group("melee_enemies")
	# 리퍼는 별도 그룹 — 스폰 캡(동시 3마리) + 그룹 AI 토큰 질의에 사용.
	if behavior == Behavior.LEAPER:
		add_to_group("leapers")
	collision_layer = 1 << 2  # Enemy
	collision_mask = (1 << 0) | (1 << 1)  # World + Player — PC 와 겹치면 스스로 빠져나감(=PC 가 밀침). PC 는 안 막힘.

	_sprite_rig = get_node_or_null(sprite_rig_path) as SpriteRig
	if _sprite_rig != null:
		_sprite_rig.fallback_color = Color(1.0, 0.45, 0.4)
		_sprite_rig.set_visuals(data.visuals)

	_health = get_node_or_null("HealthComponent") as HealthComponent
	if _health != null:
		_health.setup(data.max_hp)
		_health.setup_armor(armor_max, stagger_duration)
		_health.died.connect(_on_died)
		# 머리 위 HP 바 — 모든 몬스터 공통(잡몹/리퍼). 코드 인스턴스.
		var bar := _HpBar3DScene.instantiate()
		if "follow_offset" in bar:
			bar.follow_offset = Vector3(0, 1.55, 0)
		add_child(bar)
		if bar.has_method("attach_health"):
			bar.call("attach_health", _health)

	# 머리 위 상태 아이콘 스트립 — HP 바 위(1.55 → 2.1). 표식 등 폴링 표시.
	var strip := _StatusStripScript.new()
	if "follow_offset" in strip:
		strip.follow_offset = Vector3(0, 2.1, 0)
	add_child(strip)
	_status_strip = strip

	_player = get_tree().get_first_node_in_group("player")

## 머리 위 상태 아이콘 폴링 — 적 meta(holrim_marks 등)를 매 프레임 읽어 스트립 갱신.
## BoonExecutor 가 meta 를 세팅하고 여기선 읽기만 한다(HpBar3D 의 health 폴링과 동일).
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
	if _attack_cd > 0.0:
		_attack_cd -= delta
	# 스무스 넉백 — 어느 상태든 위치를 부드럽게 밀고 감쇠(피격/피탄 반응).
	_kb.integrate(self, delta)
	# 경직(아머 소거) 중 — 이동/공격/리프 정지(넉백은 위에서 적용 = 밀리며 경직).
	if _health != null:
		_health.tick_stagger(delta)
		if _health.is_staggered():
			velocity = Vector3.ZERO
			move_and_slide()
			return

	# 물귀신 속박(boon_root_until_msec) — 잡몹/리퍼 한정 정박(이동 봉인, 넉백은 위에서 적용).
	# 사망/경직 우선(위에서 이미 return) → 그 다음 속박. 보스/엘리트는 별 클래스라 미적용.
	if int(get_meta("boon_root_until_msec", 0)) > Time.get_ticks_msec():
		velocity = Vector3.ZERO
		move_and_slide()
		return

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
			# CHASER 근접: 윈드업 동안은 IDLE 로 정지(휘두름 X) — 데칼이 차오르며 전조.
			# 히트 순간(swing 신호)에 play_melee_strike 로 전환되므로 여기선 IDLE 만 유지.
			# 슬래머/리프 등 다른 행동은 자체 윈드업 모션을 _begin_*에서 이미 세팅했으니
			# CHASER + 윈드업 단계일 때만 IDLE 로 덮는다(다른 모션을 지우지 않게).
			if behavior == Behavior.CHASER and _melee_windup:
				_sprite_rig.set_state(SpriteRig.State.IDLE)
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
		# 그룹 AI — 다른 리퍼가 공격(토큰 보유) 중이면 공격 금지, 뒷걸음/대기 추적만.
		if not _leap_token_free():
			_leap_standoff_move(to_player, dist)
			return
		# 토큰 자유 + 쿨다운 + 사거리 + PC 시야(화면) 안에 보일 때만 리프 발동.
		if leap_telegraph_scene != null and _attack_cd <= 0.0 and dist <= leap_range and _is_on_screen():
			if randf() < leap_chance:
				_begin_leap(to_player, dist)
				return
			_attack_cd = leap_recheck
	# SLAMMER — 걸어와 슬램 사거리 안 + 쿨다운 차면 제자리 힘주기 슬램. 아니면 추격(아래).
	elif behavior == Behavior.SLAMMER:
		if slam_telegraph_scene != null and _attack_cd <= 0.0 and dist <= slam_range:
			_begin_slam(to_player)
			return

	# No detection_range gate — the mob always chases the PC regardless
	# of distance, so the player can never "outrun" the swarm by sprinting
	# to a corner of the world. The constant-velocity chase is a couple
	# of vector ops per tick, so even hundreds of mobs cost nothing
	# measurable; the real performance ceiling is rendering, not AI.
	var chase_dir := to_player.normalized()
	# 군집 분리 — 추격 방향에 이웃 회피력을 섞어 서로 겹치지 않게 한다.
	var move_dir := chase_dir
	var sep := _separation_vector()
	if sep.length_squared() > 0.000001:
		var blended := chase_dir + sep * separation_weight
		if blended.length() > 0.001:
			move_dir = blended.normalized()
	velocity.x = move_dir.x * data.move_speed * time_scale_mult
	velocity.z = move_dir.z * data.move_speed * time_scale_mult
	velocity.y = 0.0
	move_and_slide()
	if _sprite_rig != null:
		# 실제 이동량 기준 IDLE/WALK — 분리(boid)·막힘·도착으로 velocity≈0 이면 IDLE.
		# 임계값(0.04 = 속도 0.2m/s 제곱)으로 분리벡터 미세 떨림은 무시(깜빡임 방지).
		var moving: bool = Vector3(velocity.x, 0.0, velocity.z).length_squared() > 0.04
		_sprite_rig.set_state(SpriteRig.State.WALK if moving else SpriteRig.State.IDLE)
		_sprite_rig.set_facing(chase_dir.x)  # 바라보는 방향은 분리와 무관하게 플레이어 쪽


## 프레임당 1회 공유 이웃 리스트 갱신(정적). "melee_enemies" 그룹 = 잡몹+리퍼+
## 엘리트+보스. 같은 프레임에 또 불리면 즉시 반환(몹당 호출돼도 수집은 1회).
static func _refresh_sep_list(tree: SceneTree) -> void:
	if tree == null:
		return
	var f: int = Engine.get_physics_frames()
	if f == _sep_frame:
		return
	_sep_frame = f
	_sep_list = tree.get_nodes_in_group("melee_enemies")

## Boid 분리 벡터 — 공유 이웃 중 separation_radius 안의 몹에서 멀어지는 합력
## (가까울수록 강함, 선형 감쇠). EliteEnemy._compute_separation 과 동일 수식.
func _separation_vector() -> Vector3:
	if separation_radius <= 0.0:
		return Vector3.ZERO
	_refresh_sep_list(get_tree())
	var avoid := Vector3.ZERO
	var my_pos := global_position
	for other in _sep_list:
		if other == self or not is_instance_valid(other):
			continue
		if "_dead" in other and other._dead:
			continue
		var d: Vector3 = my_pos - (other as Node3D).global_position
		d.y = 0.0
		var dist := d.length()
		if dist < separation_radius and dist > 0.01:
			avoid += d.normalized() * (1.0 - dist / separation_radius)
	return avoid


## 피격(플레이어 AOE)/피탄(비도) 시 외부에서 호출 — 스무스 넉백 시작.
func apply_knockback(dir: Vector3, speed: float) -> void:
	_kb.push(dir, speed)

## World node to parent spawned effects (telegraphs, decals) under. Normally
## the active scene; during a scene reload current_scene is briefly null, so
## we fall back to our own parent and finally the tree root. Returns null only
## if we're fully detached (caller then skips spawning to avoid a crash).
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
	var host := _effect_host()
	if host == null:
		# Scene is mid-reload (current_scene null) — bail without crashing.
		fan.queue_free()
		_attack_cd = data.melee_attack_cooldown
		return
	host.add_child(fan)
	if fan.has_method("configure"):
		fan.call("configure", global_position, to_player_xz,
			fan_radius, fan_angle_deg, attack_damage, 1.0, 0.1)  # 윈드업 1초(데칼 차오름) → 끝에 타격
	if fan.has_signal("tree_exited"):
		fan.tree_exited.connect(_on_telegraph_done, CONNECT_ONE_SHOT)
	# 히트 타이밍(윈드업 끝)에 스트라이크 프레임으로 전환 — 휘두름과 데미지가 동시.
	if fan.has_signal("swing"):
		fan.connect("swing", _on_telegraph_swing, CONNECT_ONE_SHOT)
	_active_telegraph = fan
	_attacking = true
	_melee_windup = true
	# Cooldown spans the full telegraph + sweep + a recovery breath.
	_attack_cd = data.melee_attack_cooldown + 0.5
	velocity = Vector3.ZERO
	move_and_slide()
	if _sprite_rig != null:
		# 윈드업 동안엔 휘두르지 않고 IDLE 로 정지(PC 향함). 빨간 FanTelegraph 데칼이
		# 차오르며 전조를 표현하고, 차오름 끝(swing 신호)에 _on_telegraph_swing 이
		# 스트라이크 프레임으로 전환한다(휘두름 + 히트 동시 = 예측 가능).
		_sprite_rig.set_state(SpriteRig.State.IDLE)
		_sprite_rig.set_facing(to_player_xz.x)

## 히트 순간(FanTelegraph.swing) — 윈드업 IDLE 정지에서 스트라이크 프레임으로 전환.
## 데칼 데미지 점검과 같은 프레임이라 "휘두름 + 히트"가 정확히 일치한다.
func _on_telegraph_swing() -> void:
	if not is_inside_tree():
		return
	_melee_windup = false
	if _dead:
		return
	if _sprite_rig != null and _sprite_rig.has_method("play_melee_strike"):
		_sprite_rig.call("play_melee_strike")

func _on_telegraph_done() -> void:
	_attacking = false
	_melee_windup = false
	_active_telegraph = null

## SLAMMER 슬램 시작 — PC 의 현재 위치를 중심으로 넓은 원형 데칼(LeapTelegraph 재사용)을
## 깔고 제자리에서 slam_windup 동안 "힘주기"(rooted). 차오름 끝 = 슬램 데미지 + 쉐이크.
## PC 가 데칼 밖으로 회피하지 않으면 맞는다(넓은 반경 = 걸어선 빠듯, 회피 권장).
func _begin_slam(to_player_xz: Vector3) -> void:
	if slam_telegraph_scene == null:
		_attack_cd = slam_cooldown
		return
	var target: Vector3 = global_position
	if _player != null and is_instance_valid(_player):
		target = (_player as Node3D).global_position
	var decal = slam_telegraph_scene.instantiate()
	var host := _effect_host()
	if host == null:
		decal.queue_free()
		_attack_cd = slam_cooldown
		return
	host.add_child(decal)
	if decal.has_method("configure"):
		decal.call("configure", target, slam_radius, slam_damage, slam_windup)
	if decal.has_signal("tree_exited"):
		decal.tree_exited.connect(_on_slam_done, CONNECT_ONE_SHOT)
	_active_slam_decal = decal
	_attacking = true
	# 차징(힘주기) + 슬램 + 회복 동안 다음 공격 잠금.
	_attack_cd = slam_cooldown + slam_windup + 0.4
	velocity = Vector3.ZERO
	move_and_slide()
	if _sprite_rig != null:
		# 슬래머 전용 — slam_windup 길이에 맞춰 힘주기 윈드업을 느리게 왕복 재생
		# (일반 ATTACK 1회 재생은 고정 길이라 정지처럼 보이는 문제 회피).
		if _sprite_rig.has_method("play_slam_windup"):
			_sprite_rig.call("play_slam_windup", slam_windup)
		else:
			_sprite_rig.set_state(SpriteRig.State.ATTACK)
		_sprite_rig.set_facing(to_player_xz.x)

func _on_slam_done() -> void:
	_attacking = false
	_active_slam_decal = null
	# 슬램 임팩트 시점 — 스트라이크 프레임 고정.
	if _sprite_rig != null and _sprite_rig.has_method("play_slam_strike"):
		_sprite_rig.call("play_slam_strike")

## 리프 시작 — 착지 지점에 빨간 원형 데칼을 깔고 곡선 점프를 건다.
func _begin_leap(to_player_xz: Vector3, dist: float) -> void:
	var dir := to_player_xz
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3(1, 0, 0)
	var travel: float = min(dist, leap_range)
	_leap_start = global_position
	_leap_end = global_position + dir * travel
	_leap_end.y = _leap_start.y
	_leap_above = Vector3(_leap_end.x, _leap_start.y + leap_height, _leap_end.z)
	_leap_elapsed = 0.0
	_leap_pre_t = 0.0
	_leap_phase = 0  # PRE — "삐슝" 사전 경고
	_leaping = true
	_leap_attacker = self  # 그룹 AI 토큰 획득(이 동안 다른 리퍼는 공격 대기)
	# 사전경고 + 점프(체공=데칼 차오름) + 슬램 + 회복 동안 다음 공격 잠금.
	_attack_cd = data.melee_attack_cooldown + leap_pre_time + leap_duration + 0.4
	velocity = Vector3.ZERO
	# 삐슝! — 점프 전 빨간 사전 경고(스프라이트 플래시). 착지 데칼은 점프 시작 때 등장.
	if _sprite_rig != null:
		if _sprite_rig.has_method("flash"):
			_sprite_rig.call("flash", 0.25)
		_sprite_rig.set_state(SpriteRig.State.ATTACK)
		_sprite_rig.set_facing(dir.x)

## 곡선 점프 진행 — 포물선(t=0.5 정점)으로 착지 지점까지. 슬램 데미지는 데칼이
## 자기 windup 타이머로 착지 순간에 처리한다.
func _update_leap(delta: float) -> void:
	# PRE — "삐슝" 사전 경고(점프 전 제자리). 끝나면 점프 + 착지 데칼 등장.
	if _leap_phase == 0:
		velocity = Vector3.ZERO
		_leap_pre_t += delta
		if _leap_pre_t >= leap_pre_time:
			_spawn_leap_decal()   # 데칼이 보임 — 중심→바깥 100% 차오름 시작
			_leap_phase = 1       # AIR
			_leap_elapsed = 0.0
		return
	# AIR — 빠르게 상승 → 체공(데칼 차오르는 동안) → 순식간에 내려찍기.
	_leap_elapsed += delta
	var t: float = clamp(_leap_elapsed / max(leap_duration, 0.0001), 0.0, 1.0)
	# 수평: 초반(0~0.5)에 착지점 위로 이동(smoothstep) 후 고정.
	var hzt: float = clamp(t / 0.5, 0.0, 1.0)
	hzt = hzt * hzt * (3.0 - 2.0 * hzt)
	var flat: Vector3 = _leap_start.lerp(_leap_end, hzt)
	# 수직: 상승(0~0.22) → 체공 유지(~0.82) → 가속 낙하(0.82~1.0, 순식간).
	var h: float
	if t < 0.22:
		h = leap_height * (t / 0.22)
	elif t < 0.82:
		h = leap_height
	else:
		var dt: float = (t - 0.82) / 0.18
		h = leap_height * (1.0 - dt * dt)
	global_position = Vector3(flat.x, _leap_start.y + h, flat.z)
	if _sprite_rig != null:
		_sprite_rig.set_state(SpriteRig.State.ATTACK)
	if t >= 1.0:
		global_position = _leap_end
		_leaping = false
		_active_leap_decal = null
		_release_leap_token()  # 착지(슬램) → 다음 리퍼가 공격 가능


## 착지 데칼 생성 — 점프 시작 시 호출. windup=leap_duration 동안 중심→바깥으로
## 100% 차오르고, 차오름이 끝나는(=몬스터 착지) 순간 슬램 데미지 + 카메라 쉐이크.
func _spawn_leap_decal() -> void:
	if leap_telegraph_scene == null:
		return
	var decal = leap_telegraph_scene.instantiate()
	var host := _effect_host()
	if host == null:
		decal.queue_free()
		return
	host.add_child(decal)
	if decal.has_method("configure"):
		decal.call("configure", _leap_end, leap_radius, leap_damage, leap_duration)
	_active_leap_decal = decal


## 그룹 AI 토큰 — null 이거나 무효(죽음/해제)면 자유.
static func _leap_token_free() -> bool:
	return _leap_attacker == null or not is_instance_valid(_leap_attacker)

func _release_leap_token() -> void:
	if _leap_attacker == self:
		_leap_attacker = null


## PC 시야(카메라 절두체) 안에 이 몬스터가 보이는가 — 보일 때만 리프 텔레그래프 발동.
func _is_on_screen() -> bool:
	var vp := get_viewport()
	if vp == null:
		return true
	var cam := vp.get_camera_3d()
	if cam == null:
		return true
	return cam.is_position_in_frustum(global_position)


## 다른 리퍼가 공격(토큰 보유) 중일 때 — 공격하지 않고 PC를 추적하되 리프 사거리
## 부근에서 대기(가까우면 뒷걸음, 멀면 접근). 군집 분리 섞음.
func _leap_standoff_move(to_player_xz: Vector3, dist: float) -> void:
	var dir := to_player_xz
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3(1, 0, 0)
	var standoff: float = leap_range * 0.85
	var move := Vector3.ZERO
	if dist < standoff - 0.3:
		move = -dir            # 뒷걸음질(너무 가까움)
	elif dist > standoff + 0.6:
		move = dir             # 추적 접근(너무 멈)
	# else: 거의 정지(대기)
	var sep := _separation_vector()
	if sep.length_squared() > 0.000001:
		move += sep * separation_weight
		if move.length() > 0.001:
			move = move.normalized()
	velocity.x = move.x * data.move_speed * time_scale_mult * 0.8
	velocity.z = move.z * data.move_speed * time_scale_mult * 0.8
	velocity.y = 0.0
	move_and_slide()
	if _sprite_rig != null:
		# 실제 이동량 기준 — 대기(거의 정지)·막힘·분리떨림이면 IDLE. 임계값으로 떨림 무시.
		var moving: bool = Vector3(velocity.x, 0.0, velocity.z).length_squared() > 0.04
		_sprite_rig.set_state(SpriteRig.State.WALK if moving else SpriteRig.State.IDLE)
		_sprite_rig.set_facing(dir.x)

## Called by SlashAttack when this enemy is inside its volume.
## amount = 일섬 데미지(Player.attack_power = slash_base_damage + 보너스). 인스턴스
## HealthComponent.max_hp 가 시간/레벨 스케일로 올라가면 여러 대 맞아야 죽는다(표식 빌드).
func take_hit(amount: int = 1) -> void:
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
		_melee_windup = false
	# 슬래머 힘주기 중 평타 적중 → 펜딩 슬램 캔슬(유령 데미지 방지).
	if _active_slam_decal != null and is_instance_valid(_active_slam_decal):
		if _active_slam_decal.has_method("cancel"):
			_active_slam_decal.call("cancel")
		_active_slam_decal = null
		_attacking = false
	# 슬래시(PC) — 잡몹/리퍼/슬래머 모두 일섬 데미지(amount)만큼. HP 스케일(시간/레벨)과
	# 함께 다중타로 처치돼 표식 누적·연쇄·흡혈 빌드가 동작한다(옛 999 원샷 제거).
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
	# 리프 중 사망 — 펜딩 슬램 데칼 취소(유령 데미지 방지) + 그룹 AI 토큰 해제.
	_leaping = false
	_release_leap_token()
	if _active_leap_decal != null and is_instance_valid(_active_leap_decal) \
			and _active_leap_decal.has_method("cancel"):
		_active_leap_decal.call("cancel")
	_active_leap_decal = null
	# 슬래머 사망 — 펜딩 슬램 데칼 취소.
	if _active_slam_decal != null and is_instance_valid(_active_slam_decal) \
			and _active_slam_decal.has_method("cancel"):
		_active_slam_decal.call("cancel")
	_active_slam_decal = null
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
