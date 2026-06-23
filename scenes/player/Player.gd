class_name Player
extends CharacterBody3D

## Player samurai. Movement: WASD on XZ plane.
## Attack: hold LMB to charge an aim arrow (length grows w/ charge), release to
## perform an iaijutsu slash — dashes through enemies along the arrow and spawns
## a damage trail that kills everything in its width.

signal slash_started
signal slash_finished
signal rare_circular_slash_requested(pos: Vector3, radius: float, attack_power: int)
## Emitted when the PC's HP hits 0 — Main listens to trigger the
## GameOverScreen + SaveSystem.record_death. Fires BEFORE the sprite-rig
## death animation removes the node, so listeners can still read the
## final position / stats.
signal died
## ⏱ Perfect dodge (M3 후속) — emitted when an attack is avoided during
## the early window of a Shift-evade. Main / Testplay connect this to
## BulletTimeService.start(short) for a self-bullet-time reward.
signal perfect_dodge

enum State { IDLE, AIMING, DASHING, COOLDOWN, EVADING, RECOVERING }

## 데이터 관리 로더 — pc_combat.json 값을 PlayerData 에 적용. class_name 캐시
## 미스를 피하려 preload + 정적 호출(헤드리스 안전).
const _CombatDataScript := preload("res://scripts/managers/CombatData.gd")
## 메인 메뉴에서 고른 컨트롤 모드(즉발 일섬 여부)를 씬 전환 너머로 읽는다.
const _GameConfigScript := preload("res://scripts/managers/GameConfig.gd")

@export var data: PlayerData
@export var slash_attack_scene: PackedScene
## 근접 스윙 VFX 씬 (기본 공격). Player.tscn 에 MeleeSwing.tscn 주입.
@export var melee_swing_scene: PackedScene
@export var aim_arrow_path: NodePath
@export var sprite_rig_path: NodePath

var _state: int = State.IDLE
var _charge_t: float = 0.0
var _aim_dir: Vector3 = Vector3(1, 0, 0)
## 가드백 — 패리 직후 PC 가 에임 반대로 짧게 밀린다(감쇠).
var _guardback_t: float = 0.0
var _guardback_vel: Vector3 = Vector3.ZERO
var _cooldown_t: float = 0.0
var _dash_start: Vector3
var _dash_end: Vector3
var _dash_elapsed: float = 0.0
## 돌진 시간(초) — _fire_slash 에서 거리 ÷ slash_dash_speed 로 매번 갱신.
var _dash_dur: float = 0.12
var _aim_arrow: AimArrow
# 적은 SpriteRig, PC 는 PlayerSprite(둘 다 동일 API). 타입 고정 없이 덕타이핑.
var _sprite_rig
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
## 연속 대시 사이 최소 간격 타이머(data.evade_cooldown).
var _evade_cd: float = 0.0
## 회피 스택 — _ready 에서 data.evade_max_stacks 로 채움. 대시마다 1 소비,
## 전부(0) 소진되면 _evade_refill_t(=evade_refill_time) 후 한 번에 가득 찬다.
var _evade_stacks: int = 2
var _evade_refill_t: float = 0.0

# Post-hit i-frame timer. While > 0, take_hit is suppressed. 4안 — 0.5s.
# 값은 data.hit_iframe 으로 이관(CombatData/pc_combat.json 구동). iframe_bonus
# (메타)가 더해지지만 메타 효과는 현재 초기화됨.
var _iframe_t: float = 0.0

# 일섬(대시) 직후 짧은 회복 무적. > 0 동안 is_invincible() 이 참 → 착지 지점에서 적
# 충돌(접촉피해)/탄에 즉시 피격되는 불쾌감을 막는다. data.slash_post_grace 로 세팅.
var _slash_grace_t: float = 0.0

# 저스트 패리(RMB). _parry_t > 0 동안 패리 윈도우(발사체 쳐냄). _parry_cd 는 재사용 대기.
var _parry_t: float = 0.0
var _parry_cd: float = 0.0
# 회피율(레벨업) — take_hit 에서 이 확률로 피해 회피. 0~1.
var dodge_chance: float = 0.0
# 레벨업 효과 런타임 보너스(데이터 .tres 를 안 건드려 런 리셋 안전).
var slash_size_mult: float = 1.0    # 기본 공격(일섬) 범위 배수
## 기본 공격력(레벨업 "참격 강화" 카드). 슬래시/스윙이 다중타 적·보스에 주는 데미지.
var attack_power: int = 1
## 회피 스택 충전 시간 배수(레벨업 "보법" 카드, ×(1-N)). 작을수록 빨리 충전. 0.4 바닥.
var evade_refill_mult: float = 1.0
var charge_speed_bonus: float = 0.0 # 충전 속도 가산(높을수록 빨리 참)
var overheat_dur_reduce: float = 0.0 # 탈진 지속 감소(초)
var heat_delay_reduce: float = 0.0   # 열 감소 시작 유예 감소(초)
## 주술사 장판(SorcererZone) 안에 있는 동안 이동 감속. _zone_slow_t > 0 이면 _handle_move 적용.
var _zone_slow_t: float = 0.0
var _zone_slow_mult: float = 1.0

# ── 근접 기본 공격(부채꼴 스윙) 상태 ──
## 스윙 간격 쿨다운. > 0 이면 아직 다음 스윙 불가(공격 속도).
var _melee_cd: float = 0.0

## "게임 시작 2"(즉발 일섬) 모드 여부 — _ready 에서 GameConfig 로 읽는다.
## true 면 LB 가 차징 없는 즉발 일섬이 되고, 근접 스윙 + RB 게이지 일섬은
## 비활성(옛날 거합 컨트롤). 회피(SPACE)는 양쪽 모드 공통.
var _instant_slash: bool = false

# ── 열관리(Heat) — 즉발 일섬 모드 전용(럼블 열관리 게이지식) ──
## 0~100(%). 일섬마다 오르고(연타 보너스), 유예 후 지수 감소. 100 도달 시 탈진.
var _heat: float = 0.0
## 마지막 일섬 시각(ms) — 연타 윈도우 + 감소 유예 계산 기준.
var _heat_last_msec: int = 0
## 탈진 상태 — 이동 감소 + 일섬 발사 봉인.
var _overheated: bool = false
var _overheat_t: float = 0.0
var _overheat_dur: float = 0.0

# ── 4안 — 일섬 게이지 ──
## Fills from kills / gem pickups / perfect dodges. Slash (right-click)
## only fires at full, then resets to 0.
var _slash_gauge: float = 0.0
## Gauge gain multiplier — raised by the "기 충전" level-up card.
var slash_gauge_gain_mult: float = 1.0

## 4안 — knockback on hit: shove nearby enemies away when the PC is struck.
## 반경/세기는 data.knockback_radius / knockback_force 로 이관.

## ⏱ Perfect dodge (M3 후속). If an attack would have hit within
## PERFECT_DODGE_WINDOW seconds of the evade STARTING, it counts as a
## perfect dodge → emit `perfect_dodge` (Main turns it into a short
## self-bullet-time) + Zen +1. `_perfect_dodge_fired` latches per evade
## so a flurry of attacks in one window only rewards once.
## 판정 창은 data.perfect_dodge_window 로 이관.
var _perfect_dodge_fired: bool = false

## ⏱ Charge grade (M3 후속). Charge time maps to grades:
##   Quick  (0   ~ 0.3 frac) — short range, fast recovery
##   Mid    (0.3 ~ 0.9)      — linear range (existing behaviour)
##   Perfect(>= 0.9)         — max range + Zen +1 (reward, in _fire_slash)
## Holding PAST max_charge_time accumulates _overcharge_t; once it
## exceeds OVERCHARGE_GRACE the charge FIZZLES — the slash is wasted and
## all charging is locked for 1s. Punishes holding the button "just in
## case", which the linear ramp alone never discouraged.
# 유예/잠금은 data.overcharge_grace / overcharge_lockout 로 이관.
var _overcharge_t: float = 0.0

## ⏱ Perfect-parry chain reward — Boss._on_parried stamps this with
## `Time.get_ticks_msec() + window_ms`. SlashAttack reads it while
## resolving boss damage: if `Time.get_ticks_msec() <= parry_boost_until_msec`
## the next boss hit deals 3 instead of 1. No active timer or clear path
## is needed — natural expiry handles dropoff.
var parry_boost_until_msec: int = 0

## M4 meta passive — `MetaProgressionSystem.apply_to` adds owned levels
## of the "인내" passive here. take_hit uses `HIT_IFRAME + iframe_bonus`.
var iframe_bonus: float = 0.0

## M6 — yellow elite (effect_type 4) charges this on death. Each charge
## absorbs one hit's damage in `take_hit` (i-frame still triggers so the
## PC isn't immediately re-hit). No upper cap — stacks if multiple
## yellow elites die before any hit lands.
var shield_charges: int = 0

## ⏱ Zen meter integration (M4 후속). ZenSystem manages the counter +
## arms `has_zen_burst` when full. `_fire_slash` consumes the burst on
## the next slash → width × 3, range = max × 1.5, 5 dmg to bosses.
var _zen_system: Node
var has_zen_burst: bool = false

# --- M3 card flags ---
# All cards are single-pick: re-rolling the same one is a no-op until
# M5's unlock system removes already-owned cards from the draw pool.

## Multistrike — every slash auto-fires a smaller followup hit-trail
## 0.18s later (no second dash, just an extra SlashAttack volume).
var has_multistrike: bool = false
## Internal guard — set TRUE while the multistrike followup is spawning
## so the followup itself doesn't recursively schedule another one.
var _is_multistrike_followup: bool = false

## Echo — Main listens for slash_finished and spawns a CircularSlash at
## the PC's foot 0.3s after every slash. Cheap & visual, no PC state.
var has_echo: bool = false

## Rare card — after an iaijutsu dash lands, fire a wider CircularSlash
## before player control is released.
var has_rare_circular_slash: bool = false
var rare_circular_slash_radius: float = 4.6
var rare_circular_slash_recovery: float = 0.18
var _post_slash_recovery_t: float = 0.0

## Vampire — Main's award_exp_for_kill rolls vampire_chance on every
## kill and heals 1 HP on success.
var has_vampire: bool = false
var vampire_chance: float = 0.0

## Phoenix — one free revive from HP 0 → full HP + 2s i-frame.
var has_phoenix: bool = false
var _phoenix_used: bool = false

## ⏱ Counter Step — Boss.on_parry_success() stamps `counter_step_until_msec`;
## while now <= stamp, move speed multiplier is +50%.
var has_counter_step: bool = false
var counter_step_until_msec: int = 0

## ⏱ Parry Master — informational flag (UpgradeSystem mutates Boss
## export values directly on pick + Boss._ready picks up future bosses).
var has_parry_master: bool = false

func _ready() -> void:
	if data == null:
		data = PlayerData.new()
	if data.visuals == null:
		data.visuals = CharacterVisuals.new()
		data.visuals.placeholder_tint = Color(0.85, 0.9, 1.0)

	# 데이터 관리 — pc_combat.json 값으로 PlayerData 를 덮어쓴다(파일/값 없으면
	# 기존 기본값 유지). max_hp 등을 읽기 전에 적용해야 반영됨.
	_CombatDataScript.apply_to_player(self)

	# 메인 메뉴에서 "게임 시작 2" 로 들어왔으면 즉발 일섬 모드.
	_instant_slash = _GameConfigScript.instant_slash_mode

	collision_layer = 1 << 1  # Player
	# 모드2(즉발 일섬) — NPC 와 서로 밀리지 않게 PC 레이어를 비운다(적이 PC 를 못 밀침).
	# 대신 접촉 시 _check_contact_damage 로 HP 감소. 모드1 은 PC 가 군중 헤집기(기존) 유지.
	if _instant_slash:
		collision_layer = 0
	# 비대칭 충돌 — PC 는 World 만 마스크해 몬스터에 막히거나 밀리지 않는다(몬스터는
	# PC 를 못 민다). 대신 각 몬스터가 Player 를 마스크해 PC 와 겹치면 스스로 옆으로
	# 빠져나가므로, PC 가 군중을 헤집고 지나가면 몬스터가 밀려난다. 한 방향
	# 디펜트레이션이라 예전의 상호 "쭉 밀림" 끼임 버그는 재발하지 않는다.
	collision_mask = (1 << 0)  # World only (몬스터에 안 막힘 = PC 불가침)

	_aim_arrow = get_node_or_null(aim_arrow_path) as AimArrow
	_sprite_rig = get_node_or_null(sprite_rig_path)
	if _sprite_rig != null:
		_sprite_rig.fallback_color = Color(0.85, 0.9, 1.0)
		_sprite_rig.set_visuals(data.visuals)

	_evade_stacks = data.evade_max_stacks  # 회피 스택 가득 시작

	_health = get_node_or_null("HealthComponent") as HealthComponent
	if _health != null:
		_health.setup(data.max_hp)
		_health.died.connect(_on_died)
		# Wire the floating head-bar to the same HealthComponent.
		var hpbar := get_node_or_null("HpBar3D")
		if hpbar != null and hpbar.has_method("attach_health"):
			hpbar.call("attach_health", _health)
	# 머리 위 3D 바(HP/회피/열기)는 하단 PlayerHud 로 이전 — PC 자신 것은 숨긴다.
	for _bn in ["HpBar3D", "DodgeStackBar3D", "HeatBar3D"]:
		var _b := get_node_or_null(_bn) as Node3D
		if _b != null:
			_b.visible = false

	_build_dust_emitter()

func _physics_process(delta: float) -> void:
	# 근접 기본 공격 — state 무관 매 프레임(이동 중에도 휘두름). 내부에서 차징/
	# 대시/회피 중엔 억제.
	_update_melee(delta)
	# 열관리(즉발 일섬 모드) — 탈진 타이머 + 지수 감소. 모드1 이면 즉시 반환.
	_update_heat(delta)
	# 몬스터 몸 접촉 시 HP 감소(무적/대시 중 스킵). contact_damage_enabled 토글이 게이트 —
	# 근접 모드 기본 OFF, 거합(게임 시작2) 기본 ON(OutGame 시작 핸들러가 설정).
	_check_contact_damage()
	# 연속 대시 사이 최소 간격.
	if _evade_cd > 0.0:
		_evade_cd -= delta
	# 회피 스택 리필 — 가득 차지 않았으면 한 칸씩 차오른다(칸당 evade_refill_time 초).
	if _evade_stacks < data.evade_max_stacks:
		if _evade_refill_t <= 0.0:
			_evade_refill_t = data.evade_refill_time * evade_refill_mult
		_evade_refill_t -= delta
		if _evade_refill_t <= 0.0:
			_evade_stacks += 1
			_evade_refill_t = 0.0  # 아직 부족하면 다음 프레임에 재가동
	if _iframe_t > 0.0:
		_iframe_t -= delta
	if _slash_grace_t > 0.0:
		_slash_grace_t -= delta
	if _parry_t > 0.0:
		_parry_t -= delta
	if _parry_cd > 0.0:
		_parry_cd -= delta
	if _zone_slow_t > 0.0:
		_zone_slow_t -= delta
	match _state:
		State.IDLE:
			_handle_move(delta)
			if _instant_slash:
				_check_instant_slash()
			else:
				_check_attack_start()
			_check_parry()
			_check_evade_start()
			if _cooldown_t > 0.0:
				_cooldown_t -= delta
		State.AIMING:
			# 모드2(즉발 일섬)는 차징하며 이동 가능. 모드1 은 제자리 차징.
			if _instant_slash:
				_handle_move(delta)
			else:
				velocity = Vector3.ZERO
				move_and_slide()
			_update_aim(delta)
			_check_attack_release()
			_check_parry()
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
		State.RECOVERING:
			_update_post_slash_recovery(delta)

func _handle_move(delta: float) -> void:
	var input := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	var dir := Vector3(input.x, 0.0, input.y)
	if dir.length() > 1.0:
		dir = dir.normalized()
	# ⏱ Counter Step — +50% speed window after a successful parry.
	# Natural expiry, no clear path needed.
	var speed_mult: float = 1.0
	if has_counter_step and Time.get_ticks_msec() <= counter_step_until_msec:
		speed_mult = 1.5
	# 열관리 — 탈진(오버히트) 중 이동 감속(토글). 기본 패널티는 발사 봉인만이며,
	# 이동 감속은 GameConfig.overheat_move_slow_enabled 가 켜진 경우에만 적용.
	if _overheated and _GameConfigScript.overheat_move_slow_enabled:
		speed_mult *= data.heat_overheat_move_mult
	# 주술사 장판(SorcererZone) 안에 있는 동안 이동 감속 — PC 동선 방해.
	if _zone_slow_t > 0.0:
		speed_mult *= _zone_slow_mult
	# (3) 사격 중 이동 감속 기믹 제거 — 이동은 항상 정상 속도.
	velocity.x = dir.x * data.move_speed * move_speed_mult * speed_mult
	velocity.z = dir.z * data.move_speed * move_speed_mult * speed_mult
	# 가드백 — 패리 직후 에임 반대로 밀린다. 남은 시간 비례 감쇠(부드럽게 멈춤).
	if _guardback_t > 0.0:
		_guardback_t -= delta
		var gb_frac: float = clampf(_guardback_t / maxf(data.parry_guardback_dur, 0.001), 0.0, 1.0)
		velocity.x += _guardback_vel.x * gb_frac
		velocity.z += _guardback_vel.z * gb_frac
	velocity.y = 0.0
	move_and_slide()
	var moving: bool = dir.length_squared() > 0.01
	# (1) 캐릭터는 항상 마우스 커서 방향을 바라본다(이동 방향과 무관). 빌보드
	# 스프라이트라 좌/우 플립으로 표현.
	# 공격 방향(_aim_dir)은 마우스로 계속 추적 — 일섬/스윙이 이 방향으로 나간다.
	var face := _mouse_to_world_dir()
	if face.length_squared() > 0.0001:
		_aim_dir = face
	# 캐릭터(스프라이트) 방향은 WASD 이동 방향으로만 갱신 — 마우스엔 반응하지 않는다.
	if _sprite_rig != null:
		if moving:
			_sprite_rig.set_facing_vec(dir)
		_sprite_rig.set_state(SpriteRig.State.WALK if moving else SpriteRig.State.IDLE)
	# Dust kicks on whenever we're actually moving — gives a visible
	# self-motion cue on top of the world-anchored grid ground.
	if _dust_emitter != null:
		_dust_emitter.emitting = moving

func _check_attack_start() -> void:
	# 4안 — 일섬은 우클릭("slash") + 게이지 100%일 때만 시작.
	if Input.is_action_just_pressed("slash") and _cooldown_t <= 0.0:
		# Suppress when the click was on a UI control (level-up cards etc.).
		if _is_pointer_over_ui():
			return
		# Gate on a full slash gauge.
		if _slash_gauge < data.slash_gauge_max:
			return
		_set_state(State.AIMING)
		_charge_t = 0.0
		_overcharge_t = 0.0  # ⏱ fresh charge — clear any prior overcharge
		if _aim_arrow != null:
			_aim_arrow.show_arrow()
			_aim_arrow.set_charge(0.0)


## D-3 — 일섬 자원 방식. 0=열기(Heat) / 1=고정 쿨다운. 즉발 일섬 모드에서만 의미.
func _is_cooldown_resource() -> bool:
	return _instant_slash and _GameConfigScript.slash_resource_mode == 1

## D-3 — 일섬 에임 방식. 0=차징 / 1=즉발(LB 누르는 즉시 풀거리 발사). 즉발 일섬 모드 전용.
func _is_instant_aim() -> bool:
	return _instant_slash and _GameConfigScript.slash_aim_mode == 1

## D-3 — 쿨다운 자원 모드에서 다음 일섬까지의 락 잔여 타이머(초). 발사 시 세팅, 매프레임 감소.
var _slash_fixed_cd_t: float = 0.0


## 게임 시작 2(즉발 일섬) — LB 클릭으로 일섬을 발사한다.
## 자원: 열기(Heat) 또는 고정 쿨다운(GameConfig.slash_resource_mode).
## 에임: 차징(hold→release) 또는 즉발(press 즉시 풀거리, GameConfig.slash_aim_mode).
func _check_instant_slash() -> void:
	# ── 자원 게이트 ──
	if _is_cooldown_resource():
		# 고정 쿨다운 모드 — 열기 시스템 비활성. 쿨 중엔 LB 무시.
		if _slash_fixed_cd_t > 0.0:
			return
	else:
		# 열기 모드 — 탈진 중엔 발사 봉인.
		if _overheated:
			return
	# post-slash 미세 락(slash_cooldown / fizzle lockout) 공통.
	if _cooldown_t > 0.0:
		return
	if Input.is_action_just_pressed("fire"):
		if _is_pointer_over_ui():
			return
		# ── 에임 분기 ──
		if _is_instant_aim():
			# 즉발 — 차징 단계(AIMING)를 건너뛰고 풀거리(instant_slash_distance)로 즉시 발사.
			# _fire_slash 가 charge_frac=1 을 읽도록 _charge_t 를 최대로 세팅.
			_charge_t = data.max_charge_time
			_overcharge_t = 0.0
			_fire_slash()
			return
		# 차징 — 이동하며 충전(State.AIMING). LB 를 떼거나 오버차지가 끝나면
		# _fire_slash 로 발사된다. (UI 화살은 이동해도 PC 를 따라온다.)
		_set_state(State.AIMING)
		_charge_t = 0.0
		_overcharge_t = 0.0
		if _aim_arrow != null:
			_aim_arrow.show_arrow()
			_aim_arrow.set_charge(0.0)


## 저스트 패리(RMB) — 게임 시작2 우클릭. 쿨다운이 차 있으면 attack1 휘두르기로
## 패리 윈도우(parry_window) 진입. 그 동안 발사체에 맞으면 피해 없이 쳐낸다.
## 모드1 에선 RB 가 게이지 일섬이라 비활성.
func _check_parry() -> void:
	if not _instant_slash or _parry_cd > 0.0:
		return
	if Input.is_action_just_pressed("slash"):
		if _is_pointer_over_ui():
			return
		_start_parry()

func _start_parry() -> void:
	_parry_t = data.parry_window
	_parry_cd = data.parry_cooldown
	# attack1 휘두르기 — 패리 연출 길이만큼 1회 재생(이동/걷기 애니가 덮지 않게 oneshot).
	if _sprite_rig != null and _sprite_rig.has_method("play_oneshot"):
		_sprite_rig.call("play_oneshot", "attack1", data.parry_anim_dur)
	elif _sprite_rig != null:
		_sprite_rig.set_state(SpriteRig.State.ATTACK)
	_play_sfx("parry_swing")

## 패리 윈도우 활성 여부 — Arrow._on_hit 이 발사체 쳐냄 판정에 쓴다.
func is_parrying() -> bool:
	return _parry_t > 0.0

## 발사체가 패리 윈도우 중 적중 — Arrow 가 호출. 피해 없이 "쳐냈다" 연출:
## 카메라 흔들림 + 자기 히트스탑(타격감) + 반짝 스파크 + 패리 보상(Zen/카운터).
func on_projectile_parried() -> void:
	_parry_t = 0.0  # 한 번 쳐내면 윈도우 소진(연타 방지)
	var rig := get_tree().get_first_node_in_group("camera_rig")
	if rig != null:
		if rig.has_method("shake"):
			rig.call("shake", 0.18, 0.25)
		if rig.has_method("hitstop"):
			rig.call("hitstop", data.parry_hitstop_scale, data.parry_hitstop_dur)
	# 가드백 — 에임 반대 방향으로 짧게 밀려난다(쳐낸 반동, 밀리는 손맛).
	_apply_guardback(-_aim_dir)
	if _sprite_rig != null and _sprite_rig.has_method("flash"):
		_sprite_rig.call("flash", 0.22)
	_spawn_parry_spark()
	on_parry_success()  # Zen +1 / 카운터스텝 보상 재사용
	_play_sfx("parry")


## 가드백 적용 — dir 방향으로 초기속도를 주고 _handle_move 가 감쇠하며 민다.
func _apply_guardback(dir: Vector3) -> void:
	if dir.length_squared() < 0.0001:
		return
	_guardback_vel = dir.normalized() * data.parry_guardback_speed
	_guardback_t = data.parry_guardback_dur

## World node to parent spawned VFX/attacks under. Active scene normally;
## during a scene reload current_scene is briefly null, so fall back to our
## parent / tree root rather than crashing on add_child(null).
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

## "쳐냈다" 반짝 — PC 앞에 흰/금 링이 잠깐 번쩍 퍼지고 사라진다.
func _spawn_parry_spark() -> void:
	# "쳐냈다" FX — 노란 섬광 입자가 사방으로 튀는 1회 버스트. 균일한 원형 셸이 안 되게
	# 속도 편차 크게 + 약한 중력 + 댐핑으로 불규칙하게 흩뿌린다(원형 X, 섬광 O).
	var p := CPUParticles3D.new()
	var host := _effect_host()
	if host == null:
		p.queue_free()
		return
	host.add_child(p)
	p.global_position = global_position + Vector3(0, 0.9, 0)
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 20
	p.lifetime = 0.35
	p.local_coords = false
	p.direction = Vector3(0, 0.5, 0)
	p.spread = 130.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 13.0      # 편차 크게 → 깔끔한 원 안 됨
	p.gravity = Vector3(0, -9.0, 0)    # 살짝 떨어지며 흩어짐(대칭 깨짐)
	p.damping_min = 1.0
	p.damping_max = 4.0
	p.scale_amount_min = 0.04
	p.scale_amount_max = 0.14
	# 노란 섬광 → 투명으로 페이드(입자 수명 동안). vertex_color 로 입혀짐.
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.95, 0.45, 1.0))
	grad.set_color(1, Color(1.0, 0.8, 0.25, 0.0))
	p.color_ramp = grad
	var qm := QuadMesh.new()
	qm.size = Vector2(0.13, 0.13)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1, 1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.9, 0.3)
	mat.emission_energy_multiplier = 1.8
	qm.material = mat
	p.mesh = qm
	p.emitting = true
	get_tree().create_timer(p.lifetime + 0.3).timeout.connect(p.queue_free)


## 레벨업 직후(카드 선택 완료) — 자기 중심 원형으로 적을 약하게 밀어낸다(피해 없음)
## + 링 연출. Main._on_upgrade_card_selected 가 호출.
func levelup_pushback() -> void:
	if data == null:
		return
	var r: float = data.levelup_push_radius
	var sp: float = data.levelup_push_speed
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node3D):
			continue
		if "_dead" in e and e._dead:
			continue
		var to_e: Vector3 = (e as Node3D).global_position - global_position
		to_e.y = 0.0
		if to_e.length() > r or to_e.length_squared() < 0.0001:
			continue
		if e.has_method("apply_knockback"):
			e.call("apply_knockback", to_e.normalized(), sp)
	_spawn_pushback_ring(r)

func _spawn_pushback_ring(r: float) -> void:
	var ring := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 0.05
	ring.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.7, 0.9, 1.0, 0.55)
	mat.emission_enabled = true
	mat.emission = Color(0.6, 0.85, 1.0)
	mat.emission_energy_multiplier = 2.0
	ring.material_override = mat
	var host := _effect_host()
	if host == null:
		ring.queue_free()
		return
	host.add_child(ring)
	ring.global_position = global_position + Vector3(0, 0.08, 0)
	ring.scale = Vector3(0.2, 1.0, 0.2)
	var t := ring.create_tween()
	t.set_parallel(true)
	t.tween_property(ring, "scale", Vector3(r, 1.0, r), 0.3)
	t.tween_property(mat, "albedo_color:a", 0.0, 0.4)
	t.chain().tween_callback(ring.queue_free)


# ══════════════ 열관리(Heat) — 즉발 일섬 모드 전용 ══════════════

## 매 프레임 — 탈진 타이머를 깎거나(끝나면 열 0), 마지막 일섬 후 유예가 지나면
## 열을 지수적으로 식힌다. 즉발 일섬 모드가 아니면 아무것도 안 한다.
func _update_heat(delta: float) -> void:
	if not _instant_slash:
		return
	# 고정 쿨다운 자원 모드 — 열기 시스템 완전 비활성. 재발사 락만 깎는다.
	if _is_cooldown_resource():
		if _slash_fixed_cd_t > 0.0:
			_slash_fixed_cd_t -= delta
			if _slash_fixed_cd_t <= 0.0:
				_slash_fixed_cd_t = 0.0
				_play_sfx("cooldown_ready")
		# 모드 전환 잔재 정리 — 열 누적/탈진 흔적이 남지 않게.
		if _heat != 0.0:
			_heat = 0.0
		if _overheated:
			_overheated = false
		return
	if _overheated:
		_overheat_t -= delta
		if _overheat_t <= 0.0:
			_overheated = false
			_heat = 0.0
			if _sprite_rig != null and _sprite_rig.has_method("flash"):
				_sprite_rig.call("flash", 0.2)
			_play_sfx("cooldown_ready")
		return
	if _heat <= 0.0:
		return
	var since: float = float(Time.get_ticks_msec() - _heat_last_msec) / 1000.0
	if since > max(0.0, data.heat_decay_delay - heat_delay_reduce):
		# 지수 감소 — dH/dt = -k·H → H *= e^(-k·dt). 커브로 부드럽게 식음.
		_heat *= exp(-data.heat_decay_rate * delta)
		if _heat < 0.5:
			_heat = 0.0


## 외부 호출용 열기 가감(예: 잡몹 처치 -5, 패리 성공 0). 즉발 일섬 모드가 아니거나
## 탈진 중이면 음수 가산도 무시(탈진은 _update_heat 가 자연 만료). 스케일은 _heat 와 동일.
func add_heat(delta_pct: float) -> void:
	if not _instant_slash:
		return
	if _overheated:
		return
	_heat = clamp(_heat + delta_pct, 0.0, data.heat_overheat_threshold)


## 일섬 발사마다 호출 — 기본 획득에, 직전 일섬 후 combo_window 초 이내면
## combo_mult 를 곱한다. 임계 도달 시 탈진 진입.
func _add_heat() -> void:
	var now: int = Time.get_ticks_msec()
	var since: float = float(now - _heat_last_msec) / 1000.0
	var gain: float = data.heat_gain_base
	if _heat_last_msec > 0 and since <= data.heat_combo_window:
		gain *= data.heat_combo_mult
	_heat = min(_heat + gain, data.heat_overheat_threshold)
	_heat_last_msec = now
	if _heat >= data.heat_overheat_threshold:
		_enter_overheat()


## 100% 도달 — overheat_duration 초 탈진. 이동 감소(_handle_move) +
## 발사 봉인(_check_instant_slash). 진입 연출은 빨강 플래시 + 카메라 쉐이크.
func _enter_overheat() -> void:
	_overheated = true
	_overheat_t = max(0.5, data.heat_overheat_duration - overheat_dur_reduce)
	_overheat_dur = _overheat_t
	_heat = data.heat_overheat_threshold
	if _sprite_rig != null and _sprite_rig.has_method("flash"):
		_sprite_rig.call("flash", 0.45)
	var rig := get_tree().get_first_node_in_group("camera_rig")
	if rig != null and rig.has_method("shake"):
		rig.call("shake", 0.12, 0.3)
	_play_sfx("overheat")


# 머리 위 HeatBar3D 가 읽는 getter들 (덕타이핑).
func is_instant_slash_mode() -> bool:
	return _instant_slash

func get_heat_frac() -> float:
	# 고정 쿨다운 자원 모드 — 열 대신 쿨다운 차오름을 반환(0=막 발사, 1=발사 가능).
	# PlayerHud 의 5스택이 이 값으로 쿨 진행도를 표시(코드 변경 없이 의미만 모드분기).
	if _is_cooldown_resource():
		var cd: float = max(data.slash_fixed_cooldown, 0.0001)
		return clamp(1.0 - _slash_fixed_cd_t / cd, 0.0, 1.0)
	return clamp(_heat / max(data.heat_overheat_threshold, 1.0), 0.0, 1.0)

func is_overheated() -> bool:
	# 쿨다운 모드엔 탈진 개념이 없다 — 항상 false(HUD 가 회색 탈진 표시 안 함).
	if _is_cooldown_resource():
		return false
	return _overheated

func get_overheat_frac() -> float:
	if not is_overheated():
		return 0.0
	return clamp(_overheat_t / max(_overheat_dur, 0.0001), 0.0, 1.0)


func _is_pointer_over_ui() -> bool:
	var vp := get_viewport()
	if vp == null:
		return false
	return vp.gui_get_hovered_control() != null

func _check_attack_release() -> void:
	# 모드2 는 LB(fire) 홀드 차징, 모드1 은 RB(slash). 버튼을 떼면 발사.
	var action: String = "fire" if _instant_slash else "slash"
	if not Input.is_action_pressed(action):
		_fire_slash()

func _update_aim(delta: float) -> void:
	# 충전 속도 배수 — charge_speed_mult(기본 0.5)만큼 천천히 차오른다(데이터 제어).
	_charge_t = min(_charge_t + delta * (data.charge_speed_mult + charge_speed_bonus), data.max_charge_time)
	# 최대 차지 도달 후 오버차지 누적.
	if _charge_t >= data.max_charge_time:
		_overcharge_t += delta
		if _instant_slash:
			# 모드2 — instant_overcharge_hold 초 버틴 뒤 자동 발사(불발 아님).
			if _overcharge_t >= data.instant_overcharge_hold:
				_fire_slash()
				return
		# 모드1 — ⏱ grace 초과 시 불발(fizzle) + 잠금. "혹시나" 홀드를 응징.
		elif _overcharge_t >= data.overcharge_grace:
			_fizzle_charge()
			return
	var dir := _mouse_to_world_dir()
	if dir.length_squared() > 0.0001:
		_aim_dir = dir
	if _aim_arrow != null:
		var charge_frac: float = _charge_t / max(data.max_charge_time, 0.0001)
		_aim_arrow.set_charge(charge_frac)
		_aim_arrow.aim_at_direction(_aim_dir)
	# 캐릭터 방향은 마우스에 동기화하지 않는다(공격 방향만 _aim_dir 로 추적). 모드2 는
	# 이동하며 차징 → _handle_move 가 방향/걷기 애니를 정한다.
	if _sprite_rig != null and not _instant_slash:
		_sprite_rig.set_state(SpriteRig.State.IDLE)
	# LB 차징 줌아웃(ESC 토글) — 차징 동안 카메라가 서서히 빠진다(최대값 cap).
	_apply_charge_zoom(true)


## LB 차징 줌아웃(ESC 토글) — 차징 중 카메라를 서서히 빼고, 비활성/꺼짐이면 복귀.
func _apply_charge_zoom(active: bool) -> void:
	var on: bool = active and _instant_slash and _GameConfigScript.charge_zoom_enabled
	var rig := get_tree().get_first_node_in_group("camera_rig")
	if rig != null and rig.has_method("set_charge_zoom"):
		rig.call("set_charge_zoom", on)


## ⏱ Overcharge fizzle — the charge was held past the grace window. Waste
## the slash, hide the arrow, and lock all charging for OVERCHARGE_LOCKOUT
## seconds (handled by the COOLDOWN state ticking _cooldown_t down).
func _fizzle_charge() -> void:
	_apply_charge_zoom(false)
	_charge_t = 0.0
	_overcharge_t = 0.0
	_cooldown_t = data.overcharge_lockout
	if _aim_arrow != null:
		_aim_arrow.hide_arrow()
	if _sprite_rig != null:
		_sprite_rig.set_state(SpriteRig.State.IDLE)
	var rig := get_tree().get_first_node_in_group("camera_rig")
	if rig != null and rig.has_method("shake"):
		rig.call("shake", 0.05, 0.12)
	_play_sfx("fizzle")
	_set_state(State.COOLDOWN)

func _fire_slash() -> void:
	# 4안 — 일섬 발동 → 게이지 0으로 리셋.
	_slash_gauge = 0.0
	var charge_frac: float = clamp(_charge_t / max(data.max_charge_time, 0.0001), 0.0, 1.0)
	# ⏱ Zen burst — when armed, this slash consumes the burst and pays
	# out wide / long / heavy. We snapshot the flag now (consume_burst
	# below clears it) so the spawned trail gets the boost too.
	var burst_active: bool = has_zen_burst
	# 사거리 — 젠 버스트 > 즉발(모드2 고정) > 차징(모드1 선형) 순.
	var slash_range: float
	if burst_active:
		slash_range = data.max_slash_range * data.zen_burst_range_mult
	elif _instant_slash:
		# 모드2 — 차징 0→1 에 따라 min ~ instant_slash_distance 로 사거리 증가.
		slash_range = lerp(data.min_slash_range, data.instant_slash_distance, charge_frac)
	else:
		slash_range = lerp(data.min_slash_range, data.max_slash_range, charge_frac)
	# 범위(Vector3) — 젠 버스트면 폭(x)만 배수로 키운다.
	var ext: Vector3 = data.slash_hit_extents
	# 레벨업 "기본 공격 범위" — 일섬 판정 박스 폭/길이가산을 배수.
	ext = Vector3(ext.x * slash_size_mult, ext.y, ext.z * slash_size_mult)
	if burst_active:
		ext = Vector3(ext.x * data.zen_burst_width_mult, ext.y, ext.z)
		if _zen_system != null and _zen_system.has_method("consume_burst"):
			_zen_system.call("consume_burst")
	_dash_start = global_position
	_dash_end = global_position + _aim_dir.normalized() * slash_range
	_dash_elapsed = 0.0
	# 돌진 속도(m/s) → 동적 대시 시간 = 거리 ÷ 속도(거리가 멀어도 체감 일정).
	_dash_dur = max(slash_range / max(data.slash_dash_speed, 0.01), 0.02)
	_set_state(State.DASHING)
	# 일섬 대시 동안 카메라가 PC 에 바짝 붙어 "함께 이동"하도록 추적 속도를 끌어올린다
	# (공격 후 따라붙는 랙이 아니라, 공격 중 같이 움직이는 이동감).
	var cam_rig := get_tree().get_first_node_in_group("camera_rig")
	if cam_rig != null and cam_rig.has_method("follow_boost"):
		cam_rig.call("follow_boost", data.slash_cam_follow_time, data.slash_cam_follow_mult)
	# 도착 지점 가시성 — 잠깐 줌아웃해 착지 주변(적)을 넓게 보여준다.
	if cam_rig != null and cam_rig.has_method("zoom_punch"):
		cam_rig.call("zoom_punch", data.slash_cam_zoom_scale, data.slash_cam_zoom_time)
	if cam_rig != null and cam_rig.has_method("set_charge_zoom"):
		cam_rig.call("set_charge_zoom", false)  # 차징 줌아웃 해제(발사로 전환)
	if _aim_arrow != null:
		_aim_arrow.hide_arrow()
	# 일섬은 _aim_dir(마우스)로 나가지만, 캐릭터 스프라이트 방향은 WASD 그대로 둔다.
	if _sprite_rig != null:
		_sprite_rig.set_state(SpriteRig.State.ATTACK)
	# Spawn slash trail at the start of the dash.
	_spawn_slash_attack(_dash_start, _dash_end, ext, burst_active)
	# ⏱ Perfect-charge zen reward — full charge (>= 0.9 of max) feeds
	# the meter. Burst slashes don't double-dip (they consumed the meter).
	# 즉발 에임은 차징이 없으므로 퍼펙트 차징 보상에서 제외(공짜 Zen 방지).
	if not burst_active and not _is_instant_aim() and _zen_system != null \
			and charge_frac >= data.perfect_charge_threshold and _zen_system.has_method("add"):
		_zen_system.call("add", 1)
	# M7 — slash SFX cue. SoundManager silently no-ops if no .ogg yet.
	if Engine.has_singleton("SoundManager") or _has_sound_manager():
		_play_sfx("burst_slash" if burst_active else "slash")
	slash_started.emit()
	# 모드2(즉발 일섬) — 자원 방식에 따라: 고정 쿨다운(락 세팅) 또는 열기(누적+탈진).
	if _instant_slash:
		if _is_cooldown_resource():
			_slash_fixed_cd_t = max(data.slash_fixed_cooldown, 0.0)
		else:
			_add_heat()

func _update_dash(delta: float) -> void:
	_dash_elapsed += delta
	var t: float = clamp(_dash_elapsed / max(_dash_dur, 0.0001), 0.0, 1.0)
	# Smooth easing (ease-out)
	var eased: float = 1.0 - pow(1.0 - t, 2.0)
	global_position = _dash_start.lerp(_dash_end, eased)
	# Dust trails the dash for a chunky burst-line read.
	if _dust_emitter != null:
		_dust_emitter.emitting = true
	if t >= 1.0:
		# 착지 회복 유예 — 도착 지점에서 적 충돌/탄에 즉시 피격되는 불쾌감 방지.
		_slash_grace_t = max(_slash_grace_t, data.slash_post_grace)
		if has_rare_circular_slash:
			rare_circular_slash_requested.emit(global_position, rare_circular_slash_radius, attack_power)
			_post_slash_recovery_t = maxf(rare_circular_slash_recovery, 0.01)
			_set_state(State.RECOVERING)
		else:
			_complete_slash_action()


func _update_post_slash_recovery(delta: float) -> void:
	_post_slash_recovery_t -= delta
	velocity = Vector3.ZERO
	move_and_slide()
	if _dust_emitter != null:
		_dust_emitter.emitting = false
	if _post_slash_recovery_t <= 0.0:
		_complete_slash_action()


func _complete_slash_action() -> void:
	_post_slash_recovery_t = 0.0
	_cooldown_t = data.slash_cooldown
	slash_finished.emit()
	_set_state(State.COOLDOWN if data.slash_cooldown > 0.0 else State.IDLE)
	# Multistrike — schedule a second hit-trail along the same line,
	# 0.18s after the slash action completes. Followup spawns the trail
	# only (no dash, no charging) so it reads as a quick echo strike.
	if has_multistrike and not _is_multistrike_followup:
		get_tree().create_timer(0.18).timeout.connect(_fire_multistrike_followup)

func _spawn_slash_attack(start: Vector3, end: Vector3, extents: Vector3 = Vector3.ZERO, burst: bool = false) -> void:
	var attack: SlashAttack
	if slash_attack_scene != null:
		attack = slash_attack_scene.instantiate() as SlashAttack
	else:
		attack = SlashAttack.new()
	var host := _effect_host()
	if host == null:
		attack.queue_free()
		return
	host.add_child(attack)
	var ext: Vector3 = extents if extents.length_squared() > 0.0001 else data.slash_hit_extents
	attack.configure(start, end, ext)
	attack.lifetime = data.slash_hit_lifetime
	attack.attack_power = attack_power
	# ⏱ Zen burst payload — SlashAttack._resolve_boss_damage checks this
	# meta and returns 5 (vs. 1 / 3) when set. Cheap to carry on the
	# node; auto-frees with the attack.
	if burst:
		attack.set_meta("zen_burst", true)
		# Visual polish — gold + emission so the burst reads as special.
		if attack.has_method("set_burst_visual"):
			attack.call("set_burst_visual")


## Multistrike followup — spawn a shorter trail along the last aim
## direction, no dash. Guarded by `_is_multistrike_followup` so the
## extra trail can't itself trigger another followup recursively.
func _fire_multistrike_followup() -> void:
	if not is_inside_tree():
		return
	_is_multistrike_followup = true
	var start: Vector3 = global_position
	var end: Vector3 = global_position + _aim_dir.normalized() * (data.max_slash_range * 0.7)
	_spawn_slash_attack(start, end)
	_is_multistrike_followup = false

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

func take_hit(amount: int = 1, do_knockback: bool = true) -> void:
	# ⏱ Perfect dodge — an attack arrived during the early window of an
	# evade. Reward fires BEFORE the is_invincible early-return swallows
	# the hit. Latched per evade so multiple attacks only reward once.
	if _state == State.EVADING and not _perfect_dodge_fired \
			and _evade_elapsed <= data.perfect_dodge_window:
		_perfect_dodge_fired = true
		perfect_dodge.emit()
		if _zen_system != null and _zen_system.has_method("add"):
			_zen_system.call("add", 1)
		add_slash_gauge(data.slash_gauge_on_perfect_dodge)  # 4안 — 저스트 회피 → 게이지
		_play_sfx("perfect_dodge")
		var pd_rig := get_tree().get_first_node_in_group("camera_rig")
		if pd_rig != null and pd_rig.has_method("nudge_lag"):
			pd_rig.call("nudge_lag", 0.25, 0.3)
	# Invincible for the duration of the iaido slash (DASHING), during a
	# Shift-evade (EVADING), and for HIT_IFRAME seconds after the previous
	# damage landed.
	if is_invincible():
		return
	# 회피율(레벨업) — 무적과 별개로 확률 회피. 성공 시 피해 없이 흘린다.
	if dodge_chance > 0.0 and randf() < dodge_chance:
		if _sprite_rig != null and _sprite_rig.has_method("flash"):
			_sprite_rig.call("flash", 0.12)
		_play_sfx("dodge")
		return
	# Shield absorb — yellow elite charges. Consume one charge, skip
	# damage, still trigger i-frame + a softer shake so the absorb reads
	# as a defensive "ting" instead of a free pass.
	if shield_charges > 0:
		shield_charges -= 1
		var sh_iframe: float = data.hit_iframe + iframe_bonus
		_iframe_t = sh_iframe
		if _sprite_rig != null and _sprite_rig.has_method("start_iframe_blink"):
			_sprite_rig.call("start_iframe_blink", sh_iframe)
		var sh_rig := get_tree().get_first_node_in_group("camera_rig")
		if sh_rig != null and sh_rig.has_method("shake"):
			sh_rig.call("shake", 0.04, 0.1)
		_play_sfx("shield")
		return
	# ⏱ Zen meter drains on damage so "perfect play sustained" matters.
	if _zen_system != null and _zen_system.has_method("drain_on_hit"):
		_zen_system.call("drain_on_hit")
	_play_sfx("hit")
	if _health != null:
		_health.take_damage(amount)
	# Hit feedback — i-frame + strobe blink + camera shake. Runs even if
	# the hit was fatal (the strobe blends naturally into the death fade).
	var total_iframe: float = data.hit_iframe + iframe_bonus
	_iframe_t = total_iframe
	if _sprite_rig != null and _sprite_rig.has_method("start_iframe_blink"):
		_sprite_rig.call("start_iframe_blink", total_iframe)
	# 4안 — 추가 피격 플래시(머티리얼 over-bright) + 주변 적 넉백.
	if _sprite_rig != null and _sprite_rig.has_method("flash"):
		_sprite_rig.call("flash", 0.2)
	# 접촉 피해(모드2)는 넉백을 일으키지 않는다(서로 안 밀림). 그 외 피격은 기존대로.
	if do_knockback:
		_knockback_nearby_enemies()
	var rig := get_tree().get_first_node_in_group("camera_rig")
	if rig != null and rig.has_method("shake"):
		rig.call("shake", 0.1, 0.2)

## 밸런싱 아레나 무적 토글(ArenaDebug 패널) — 켜면 절대 안 죽는다(관찰용).
var god_mode: bool = false
## 레벨업 "경험치 자석" 카드 — ExpGem 자석 반경 배수(런마다 1.0 리셋).
var exp_magnet_mult: float = 1.0
## 레벨업 "질풍" 카드 — 이동속도 배수(런타임, 런마다 1.0 리셋 — 공유 PlayerData 변형 방지).
var move_speed_mult: float = 1.0

func is_invincible() -> bool:
	return god_mode or _state == State.DASHING or _state == State.EVADING or _iframe_t > 0.0 or _slash_grace_t > 0.0

## LB 공격(일섬 대시) 중인가.
func is_slashing() -> bool:
	return _state == State.DASHING

## 슬래시 대시 또는 착지 직후 유예(slash_post_grace) 동안 젬 강흡인 상태.
## ExpGem 이 is_slashing 대신 이 게터를 우선 사용(grace 동안도 ×3 흡인 유지).
func is_slash_vacuuming() -> bool:
	return _state == State.DASHING or _slash_grace_t > 0.0


## 아레나 — 회피 스택 즉시 가득.
func refill_evade() -> void:
	if data != null:
		_evade_stacks = data.evade_max_stacks
		_evade_refill_t = 0.0


## 레벨업 등에서 호출 — duration 만큼 무적 + 깜빡임(기존 iframe 보다 길면 갱신).
## tree.paused 중엔 _iframe_t 가 안 닳으므로, 카드 고르고 재개하면 그대로 무적이 남는다.
func grant_iframe(duration: float) -> void:
	_iframe_t = maxf(_iframe_t, duration)
	if _sprite_rig != null and _sprite_rig.has_method("start_iframe_blink"):
		_sprite_rig.call("start_iframe_blink", duration)

## --- Shift evade dash ---

func _check_evade_start() -> void:
	if _evade_cd > 0.0:
		return
	if _evade_stacks <= 0:
		return  # 스택 소진 — 리필 대기 중(차오르는 데 evade_refill_time 초)
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
	# 스택 1 소비 — 부족해지면 _physics_process 의 charge 리필이 한 칸씩 채운다
	# (한 칸당 evade_refill_time 초).
	_evade_stacks -= 1
	_perfect_dodge_fired = false  # ⏱ fresh evade — re-arm the perfect-dodge reward
	_set_state(State.EVADING)
	if _sprite_rig != null:
		_sprite_rig.set_facing_vec(dir)
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

## 이어서 하기(사망 화면) — 같은 노드를 되살린다: 풀 HP + 2초 무적 + 스프라이트 복원.
## 사망 시 노드가 free 되기 전(트리 정지 중)이라 같은 PC 를 그대로 살려 진행 유지.
func revive() -> void:
	if _health != null:
		_health.hp = _health.max_hp
		_health.damaged.emit(0)
	_iframe_t = 2.0
	if _sprite_rig != null and _sprite_rig.has_method("revive_reset"):
		_sprite_rig.call("revive_reset")
	if _sprite_rig != null and _sprite_rig.has_method("start_iframe_blink"):
		_sprite_rig.call("start_iframe_blink", 2.0)
	_set_state(State.IDLE)


func _on_died() -> void:
	# Phoenix — one-shot revival: full HP, 2s of i-frame, skip the
	# death.emit / sprite tween entirely. _phoenix_used latches so a
	# second death plays out normally.
	if has_phoenix and not _phoenix_used:
		_phoenix_used = true
		if _health != null:
			_health.hp = _health.max_hp
			# damaged(0) repaints the HpBar3D without going through
			# take_damage (which would no-op on hp==0 path).
			_health.damaged.emit(0)
		_iframe_t = 2.0
		if _sprite_rig != null and _sprite_rig.has_method("start_iframe_blink"):
			_sprite_rig.call("start_iframe_blink", 2.0)
		return
	# Tell Main FIRST so GameOverScreen + SaveSystem fire with the PC
	# node still alive (Main reads kill count / level off live state).
	# The 0.5s death tween runs in parallel — the screen pops up while
	# the sprite is still fading, which reads as a clean transition.
	died.emit()
	if _sprite_rig != null:
		_sprite_rig.play_death_then_free(self, 0.5)
	else:
		queue_free()


## Callback the Boss fires when a parry resolves. Centralizes any
## parry-triggered card effects (Counter Step today; Zen meter feeds
## off the same hook).
func on_parry_success() -> void:
	if has_counter_step:
		counter_step_until_msec = Time.get_ticks_msec() + 1000
	if _zen_system != null and _zen_system.has_method("add"):
		_zen_system.call("add", 1)
	_heat = 0.0  # 패리 성공 → 열기 즉시 0%
	_play_sfx("parry")


## 주술사 장판(SorcererZone)이 PC 가 장판 안에 있는 동안 매 프레임 호출 — 이동 감속.
## 짧은 duration 으로 갱신만 하므로 장판을 벗어나면 곧 풀린다(자연 만료).
func apply_zone_slow(duration: float, mult: float) -> void:
	_zone_slow_t = maxf(_zone_slow_t, duration)
	_zone_slow_mult = clampf(mult, 0.1, 1.0)


## Wired by Main / Testplay after building ZenSystem. Holds the ref so
## on_parry_success / _fire_slash can poke it without a group lookup
## per call.
func bind_zen_system(zs: Node) -> void:
	_zen_system = zs


# ══════════════ 기본 공격 — 근접 부채꼴 스윙 (LB) ══════════════

## 매 프레임 — LB 홀드 중이면 melee_cooldown 간격으로 스윙(이동 중에도 가능).
func _update_melee(delta: float) -> void:
	# 모드2(즉발 일섬)에서는 LB 가 일섬에 쓰이므로 근접 스윙을 끈다.
	if _instant_slash:
		return
	if _melee_cd > 0.0:
		_melee_cd -= delta
	# 차징(일섬)/대시/후속베기/회피 중엔 기본 공격 억제.
	if _state == State.AIMING or _state == State.DASHING \
			or _state == State.RECOVERING or _state == State.EVADING:
		return
	if Input.is_action_pressed("fire") and _melee_cd <= 0.0:
		if _is_pointer_over_ui():
			return
		_do_melee_swing()


## (2) LB 근접 스윙 — 커서 방향 전방 부채꼴 안의 적을 타격. (4) 이동을 막지
## 않으므로 걸으면서 휘두를 수 있다. 데미지는 적 HealthComponent 에 직접
## (보스는 패리 없이 칩 데미지). 모션은 추후 — 임시 부채 VFX 만 띄운다.
func _do_melee_swing() -> void:
	var dir := _mouse_to_world_dir()
	if dir.length() < 0.01:
		dir = _aim_dir
	dir = dir.normalized()
	_aim_dir = dir
	_melee_cd = data.melee_cooldown
	# 근접 스윙은 dir(마우스)로 나가지만, 캐릭터 방향은 WASD 그대로 둔다.
	var half := deg_to_rad(data.melee_angle_deg) * 0.5
	var r2 := data.melee_range * data.melee_range
	var hit_any := false
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node3D):
			continue
		if "_dead" in e and e._dead:
			continue
		var to_e: Vector3 = (e as Node3D).global_position - global_position
		to_e.y = 0.0
		if to_e.length_squared() > r2:
			continue
		# 부채꼴 각도 체크(중심 = 커서 방향).
		if to_e.length() > 0.01:
			var ang := acos(clamp(dir.dot(to_e.normalized()), -1.0, 1.0))
			if ang > half:
				continue
		var hp := (e as Node3D).get_node_or_null("HealthComponent")
		if hp != null and hp is HealthComponent:
			(hp as HealthComponent).take_damage(data.melee_damage + (attack_power - 1))
			hit_any = true
	# 발사체(적 화살)도 부채 안에 들어오면 격추한다.
	for p in get_tree().get_nodes_in_group("enemy_projectiles"):
		if not is_instance_valid(p) or not (p is Node3D):
			continue
		var to_p: Vector3 = (p as Node3D).global_position - global_position
		to_p.y = 0.0
		if to_p.length_squared() > r2:
			continue
		if to_p.length() > 0.01:
			var ang_p := acos(clamp(dir.dot(to_p.normalized()), -1.0, 1.0))
			if ang_p > half:
				continue
		if p.has_method("take_hit"):
			p.call("take_hit")
	_spawn_melee_swing(dir)
	_play_sfx("melee")
	# 타격감 — 스윙마다 약한 카메라 흔들림 + 적중 시 극소량 히트스탑(역경직).
	var rig := get_tree().get_first_node_in_group("camera_rig")
	if rig != null:
		if rig.has_method("shake"):
			rig.call("shake", data.melee_shake_amp, data.melee_shake_dur)
		if hit_any and rig.has_method("hitstop"):
			rig.call("hitstop", data.melee_hitstop_scale, data.melee_hitstop_dur)


## 임시 스윙 VFX — 커서 방향으로 부채 플래시(모션 추후 교체).
func _spawn_melee_swing(dir: Vector3) -> void:
	if melee_swing_scene == null:
		return
	var fx := melee_swing_scene.instantiate()
	var host := _effect_host()
	if host == null:
		fx.queue_free()
		return
	host.add_child(fx)
	if fx.has_method("configure"):
		fx.call("configure", global_position, dir, data.melee_range, data.melee_angle_deg)


# ══════════════ 4안 — 일섬 게이지 ══════════════

## Add to the slash gauge (×gain mult), clamped to max. Called from Main
## on kill / gem pickup and from take_hit on perfect dodge.
func add_slash_gauge(amount: float) -> void:
	# 모드2(즉발 일섬)는 일섬 게이지를 쓰지 않는다 — 처치/젬/저스트회피와 무관.
	if _instant_slash:
		return
	if amount <= 0.0:
		return
	_slash_gauge = min(_slash_gauge + amount * slash_gauge_gain_mult, data.slash_gauge_max)


## Convenience hooks Main / Testplay call so they don't have to read the
## PC's PlayerData for the per-source gauge amounts.
func gain_gauge_on_kill() -> void:
	add_slash_gauge(data.slash_gauge_on_kill)

func gain_gauge_on_gem() -> void:
	add_slash_gauge(data.slash_gauge_on_gem)


# ══════════════ 4안 — 피격 넉백 ══════════════

## Shove every nearby non-boss enemy away from the PC when struck. Direct
## position push (enemies' chase re-converges over the i-frame window).
func _knockback_nearby_enemies() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node3D):
			continue
		if e.is_in_group("boss"):
			continue  # bosses don't get shoved
		var to_e: Vector3 = (e as Node3D).global_position - global_position
		to_e.y = 0.0
		var d: float = to_e.length()
		if d < data.knockback_radius and d > 0.01:
			# 거리 감쇠된 밀침 속도로 스무스 넉백(적의 Knockback 컴포넌트가 감쇠 처리).
			var spd: float = data.knockback_force * (1.0 - d / data.knockback_radius)
			if e.has_method("apply_knockback"):
				e.call("apply_knockback", to_e.normalized(), spd)


## 게임 시작2 — NPC 몸에 닿으면 HP 감소(서로 밀림 없음 · take_hit 의 iframe 이 쿨다운).
## 접촉 피해는 넉백을 일으키지 않는다(do_knockback=false). 무적/대시/회피 중엔 스킵.
func _check_contact_damage() -> void:
	# ESC 토글 — 충돌 피해 OFF 면 접촉 피해 없음.
	if not _GameConfigScript.contact_damage_enabled:
		return
	if is_invincible():
		return
	var r2: float = data.contact_radius * data.contact_radius
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node3D):
			continue
		if "_dead" in e and e._dead:
			continue
		var to_e: Vector3 = (e as Node3D).global_position - global_position
		to_e.y = 0.0
		if to_e.length_squared() <= r2:
			take_hit(data.contact_damage, false)
			return


# ══════════════ 4안 — HUD getters (Main reads these) ══════════════

func get_hp() -> int:
	return _health.hp if _health != null else 0

func get_max_hp() -> int:
	return _health.max_hp if _health != null else 0

func slash_gauge_frac() -> float:
	return clamp(_slash_gauge / max(data.slash_gauge_max, 1.0), 0.0, 1.0)

func is_slash_ready() -> bool:
	return _slash_gauge >= data.slash_gauge_max

# ── 회피 스택 getters (머리 위 DodgeStackBar3D 가 읽음) ──
func get_evade_stacks() -> int:
	return _evade_stacks

func get_max_evade_stacks() -> int:
	return data.evade_max_stacks

## 충전 중인 다음 스택의 진행도 0→1 (가득이면 1.0).
func evade_refill_frac() -> float:
	if _evade_stacks >= data.evade_max_stacks:
		return 1.0
	return clamp(1.0 - _evade_refill_t / max(data.evade_refill_time * evade_refill_mult, 0.01), 0.0, 1.0)


# ────── M7 sound hook helpers ──────
# Cheap wrappers around the SoundManager Autoload. Guards keep these
# safe in scenes that haven't booted the autoload yet (Testplay run
# from F6 doesn't bypass it, but the guard costs nothing).

func _has_sound_manager() -> bool:
	# Autoload nodes live as children of /root. Look up by name.
	var root := get_tree().root if get_tree() != null else null
	if root == null:
		return false
	return root.has_node("SoundManager")


func _play_sfx(name: String) -> void:
	if not _has_sound_manager():
		return
	var sm := get_tree().root.get_node("SoundManager")
	if sm != null and sm.has_method("play_sfx"):
		sm.call("play_sfx", name)

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
