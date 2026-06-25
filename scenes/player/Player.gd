class_name Player
extends CharacterBody3D

## Player samurai. Movement: WASD on XZ plane.
## Attack: hold LMB to charge an aim arrow (length grows w/ charge), release to
## perform an iaijutsu slash — dashes through enemies along the arrow and spawns
## a damage trail that kills everything in its width.

signal slash_started
signal slash_finished
## Emitted when the PC's HP hits 0 — Main listens to trigger the
## GameOverScreen + SaveSystem.record_death. Fires BEFORE the sprite-rig
## death animation removes the node, so listeners can still read the
## final position / stats.
signal died
## ⏱ Perfect dodge (M3 후속) — emitted when an attack is avoided during
## the early window of a Shift-evade. Main / Testplay connect this to
## BulletTimeService.start(short) for a self-bullet-time reward.
signal perfect_dodge

enum State { IDLE, AIMING, DASHING, COOLDOWN, EVADING }

## 데이터 관리 로더 — pc_combat.json 값을 PlayerData 에 적용. class_name 캐시
## 미스를 피하려 preload + 정적 호출(헤드리스 안전).
const _CombatDataScript := preload("res://scripts/managers/CombatData.gd")
## 메인 메뉴에서 고른 컨트롤 모드(즉발 일섬 여부)를 씬 전환 너머로 읽는다.
const _GameConfigScript := preload("res://scripts/managers/GameConfig.gd")
## 은혜=트리거×컴포넌트 이벤트 키 참조.
const _TriggerBusScript := preload("res://scripts/managers/TriggerBus.gd")
## 권속 은혜 데이터 조회(by_id/params_for 정적 호출).
const _BoonSystemScript := preload("res://scripts/managers/BoonSystem.gd")
## 권속 은혜 효과 실행기 — _ready 에서 코드 인스턴스로 add_child.
const _BoonExecutorScript := preload("res://scripts/managers/BoonExecutor.gd")
## 머리 위 상태 아이콘 스트립(굶주림 표시 — 적과 동일 공용 컴포넌트).
const _StatusStripScript := preload("res://scenes/ui/StatusIconStrip3D.gd")

# ── 납도(On_Sheathe) — RB 로 거둬 표식 정산(1차값 코드 상수, 공유 .tres 변형 금지) ──
## 정산 반경(m) — 이 안의 표식 적만 거둔다. BoonExecutor 도 동일값 보유(정산 주체).
const _SHEATHE_RANGE := 5.0
## 미만 표식 정산 데미지 단가(표식 1개당). 만개=처형(보스 제외).
const _SHEATHE_DMG := 2
const _SHEATHE_MARK_CAP := 5
## 거둔 표식 총합당 열 환급(%) — 음수 가산으로 식힘.
const _SHEATHE_HEAT_REFUND_PER_MARK := 0.08
## 거둔 표식 총합당 HP 미세 회복(반올림).
const _SHEATHE_HP_PER_MARK := 0.4

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
## 돌진 시간(초) — _fire_slash 에서 거리 ÷ slash_dash_speed 로 매번 갱신.
var _dash_dur: float = 0.12
## 일섬 대시 종료 후 복원할 collision_layer 기본값(_ready 에서 모드별로 캐시).
var _collision_layer_default: int = 1 << 1
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
## 납도(RB) 쿨다운 잔여(초) — 연타 방지. _physics_process 가 깎는다.
var _sheathe_cd_t: float = 0.0
## 회피 스택 — _ready 에서 data.evade_max_stacks 로 채움. 대시마다 1 소비,
## 전부(0) 소진되면 _evade_refill_t(=evade_refill_time) 후 한 번에 가득 찬다.
var _evade_stacks: int = 2
var _evade_refill_t: float = 0.0
## On_Slash_Right_After_Dash 판정용 — 회피 종료 시각(ms). 초기값은 충분히 과거.
var _last_evade_end_msec: int = -100000
## On_Dash_Pass_Enemy 중복 방지 캐시 — 회피 시작 시 clear, 회피 중 적 instance_id 기록.
var _dash_passed: Dictionary = {}

# Post-hit i-frame timer. While > 0, take_hit is suppressed. 4안 — 0.5s.
# 값은 data.hit_iframe 으로 이관(CombatData/pc_combat.json 구동). iframe_bonus
# (메타)가 더해지지만 메타 효과는 현재 초기화됨.
var _iframe_t: float = 0.0

# 일섬(대시) 직후 짧은 회복 무적. > 0 동안 is_invincible() 이 참 → 착지 지점에서 적
# 충돌(접촉피해)/탄에 즉시 피격되는 불쾌감을 막는다. data.slash_post_grace 로 세팅.
var _slash_grace_t: float = 0.0

## 기본 공격력 = 일섬이 잡몹(다중타 몹)에 주는 데미지. _ready 에서
## data.slash_base_damage + slash_damage_bonus 로 세팅(ArenaDebug 슬라이더가 이후 덮어쓸 수
## 있음). 보스는 별도(boss_slash_damage_normal). SlashAttack/EliteEffectService/CircularSlash/
## balance_sim/ArenaDebug 가 읽으므로 변수 보존.
var attack_power: int = 1
## 스킬 카드용 런타임 일섬 데미지 보너스(런마다 _ready 재인스턴스로 0 리셋). 공유 .tres 변형
## 금지 원칙에 맞춰 인스턴스 변수로만 누적한다 — attack_power = slash_base_damage + 이 값.
var slash_damage_bonus: int = 0

## 권속 은혜 장착 목록(런타임 — 런마다 _ready 에서 리셋). 각 원소 = {id, rarity, components, params}.
var active_boons: Array = []
## 권속 은혜 효과 실행기 노드 참조.
var _boon_executor: Node = null
## 마지막 일섬 착지 시각(ms) — 거합(IAIDO_PERFECT) perfect 윈도우 판정용. 0=아직 없음.
var last_slash_end_msec: int = 0
## 머리 위 상태 아이콘 스트립(굶주림 등) — _ready 에서 코드 인스턴스.
var _status_strip: Node = null

# ── 구미낙화(SLASH_FAN) — 풀차지 일섬 부채 폭 확장 일회성 보너스(BoonExecutor 가 세팅) ──
## On_Slash_Charged 시 BoonExecutor 가 세팅 → 다음 _fire_slash 가 폭 확장에 소비 후 1.0 리셋.
var boon_slash_fan_width_mult: float = 1.0
var boon_slash_fan_arc_bonus: float = 0.0

# ── 납도류(M9-S4) 런타임 보너스(런마다 _ready 재인스턴스로 리셋 — 공유 .tres 미변형) ──
## 일섬연장(SLASH_EXTEND) — 패시브 일섬 사거리/폭 배수(_fire_slash 가 매 발사 적용). 1.0=무효.
var boon_slash_range_mult: float = 1.0
var boon_slash_width_mult: float = 1.0
## 역수(IAIDO_HASTE) — 납도 성공 직후 다음 일섬까지 충전/쿨 가속 + 대시 거리 가산.
## _t > 0 동안 충전·쿨 ×(1+_charge_mult), 일섬 발사 시 소멸. dash_bonus 는 영구(런타임).
var boon_haste_t: float = 0.0
var boon_haste_charge_mult: float = 0.0
var boon_dash_dist_bonus: float = 0.0
## 회피 스택 충전 시간 배수(중립 base 스탯, 기본 1.0). 작을수록 빨리 충전.
var evade_refill_mult: float = 1.0
# ── M9-S7 baseline④: 거합 추격 윈도우(코드 상수·항상 on) ──
## 추격 윈도우 잔여(초). 납도가 처치를 내면 open_sheathe_follow 가 0.4 로 세팅, _physics_process 가 깎음.
## > 0 동안 RB(slash) 재입력 시 납도 쿨 무시하고 즉시 추격 납도 1회.
var _sheathe_follow_t: float = 0.0
## 추격 1회 cap — 추격 납도가 또 추격 윈도우를 열지 못하게(open_sheathe_follow 가 used 면 return).
## 일반 납도 시작 시에만 false 로 리셋. ★무한 추격 방지.
var _sheathe_follow_used: bool = false
# ── M9-S7 폭심 충전(EPICENTER_OVERCHARGE): 다음 일섬 1발 대버스트 예약(런타임 변수·런마다 리셋) ──
## 예약된 다음 일섬 사거리/폭 배수 + 열 환급 비율. _fire_slash 가 1발 소비 후 즉시 1.0/0 리셋.
var boon_next_slash_range_mult: float = 1.0
var boon_next_slash_width_mult: float = 1.0
var boon_next_slash_heat_refund: float = 0.0
## 예약 윈도우 잔여(초). > 0 일 때만 예약 적용. 만료 시 예약 소멸(배수 리셋).
var _next_burst_t: float = 0.0
## 주술사 장판(SorcererZone) 안에 있는 동안 이동 감속. _zone_slow_t > 0 이면 _handle_move 적용.
var _zone_slow_t: float = 0.0
var _zone_slow_mult: float = 1.0

# ── M9-S9 정기흡수(SPIRIT_STACK): PC 내부 자원 — 납도 처치마다 +1, 스택당 일섬/납도 미세 강화 ──
## ★전부 런타임 인스턴스 변수(_ready 리셋). 공유 .tres 미변형 — 적 직접 안 죽임(0뎀).
## 만스택(_spirit_max) 도달 시 _spirit_release_pending=true → 다음 납도가 '정기 해방' 대정산 후 0 리셋.
var _spirit_stacks: int = 0
var _spirit_per_stack: float = 0.0
var _spirit_max: int = 8
var _spirit_release_mult: float = 2.0
var _spirit_release_pending: bool = false

# ── M9-S10 연격류(STYLE_NUKI): LB 연타 control mechanic ──
## ★전부 런타임 인스턴스 변수(_ready 리셋). 공유 .tres 미변형. 연타 윈도우는 _nuki_active(속발 보유) 게이트라
##   미보유(납도류 등)면 전부 no-op — 기존 일섬 거동 그대로(회귀 0).
## 속발(STYLE_NUKI) 카드 보유 여부 — add_boon 에서 감지해 세팅. true 일 때만 연타 윈도우/가속/리듬 동작.
var _nuki_active: bool = false
## 재입력 윈도우 잔여(초). 일섬 발도 직후 nuki_window 로 열림, _physics_process 가 깎음.
## > 0 동안 LB(fire) 재입력이면 추가 일섬(콤보+1)을 즉발. 만료/미입력 시 콤보 0 리셋.
var _nuki_window_t: float = 0.0
## 이번 윈도우 총 길이(초) — sweet spot(후반 sweet_frac 구간) 판정 기준(잔여/총길이 비율).
var _nuki_window_total: float = 0.0
## 현재 콤보 타수(0=콤보 없음, 1=첫 일섬, 2=2타…). _nuki_max 도달 시 윈도우 안 열고 마무리.
var _nuki_combo: int = 0
## 가속 티어(0~max_tier). 스윗 스폿 퍼펙트 연타마다 +1, 콤보 끊김 시 0(연쇄가락 보존 예외).
var _nuki_accel_tier: int = 0
## 리듬 게이지(퍼펙트 연속 카운트) — need 도달 시 충전 상태(윈도우 폭↑·마무리 회수 가중). 끊기면 0.
var _nuki_rhythm: int = 0
## 이번 콤보가 낸 처치 수(연쇄가락 — 2명+ 처치 시 가속 티어 보존). 새 콤보 시작 시 0.
var _nuki_combo_kills: int = 0
# 속발 params(런마다 add_boon 에서 세팅 — 보유 시. 코드 1차값 기본).
var _nuki_window_base: float = 0.32     # nuki_window
var _nuki_max: int = 3                  # 콤보 상한(삼절연격으로 확장)
var _nuki_sweet_frac: float = 0.4       # 윈도우 후반 sweet spot 비율
var _nuki_retap_charge_frac: float = 0.7  # 연타 일섬 충전 프랙(숏 발도 = 풀차지 미만 즉발)
# 박자가속(NUKI_ACCEL) params — 보유 시 add_boon 에서 세팅(미보유면 가속 0).
var _nuki_accel_has: bool = false
var _nuki_accel_haste: float = 0.0
var _nuki_accel_dash: float = 0.0
var _nuki_accel_max_tier: int = 0
# 연참의박(NUKI_RHYTHM) params — 보유 시 세팅.
var _nuki_rhythm_has: bool = false
var _nuki_rhythm_need: int = 3
var _nuki_rhythm_window_bonus: float = 0.0
var _nuki_rhythm_settle_mult: float = 1.0
# 납도결산(NUKI_SETTLE) — 연타 마지막 타가 자동 납도 정산(ON_SHEATHE)을 발동.
var _nuki_settle_has: bool = false
## 연격 마무리 정산 1회 환급 부스트(리듬 충전 시 _nuki_rhythm_settle_mult). _sheathe_restore 가 소비 후 1.0 리셋.
var _nuki_settle_refund_boost: float = 1.0
# 연쇄가락(NUKI_CADENCE) — 한 콤보 kills_need 처치 시 가속 티어 보존.
var _nuki_cadence_has: bool = false
var _nuki_cadence_kills_need: int = 2

# ── M9-S11 충전류(STYLE_CHARGE): LB 충전→풀차지 관통 control mechanic ──
## ★전부 런타임 인스턴스 변수(_ready 리셋). 공유 .tres 미변형. 모든 분기는 _charge_active(일도양단 보유) 게이트라
##   미보유(납도/연격/무스타일)면 전부 no-op — 기존 일섬/연타 거동 그대로(회귀 0).
## 일도양단(STYLE_CHARGE) 카드 보유 여부 — add_boon 에서 감지해 세팅. true 일 때만 차징 경로 강제.
var _charge_active: bool = false
## 충전 티어 경계(약/중/풀) — frac<lo=0(약), <hi=1(중), 그 외=2(풀).
var _charge_tier_lo: float = 0.4
var _charge_tier_hi: float = 0.85
## 풀차지 관통 일섬 배수(꿰뚫는일직선 SLASH_EXTEND 와 별개 — 충전류 자체 보너스). 1.0=무효.
var _charge_pierce_range_mult: float = 1.0
var _charge_pierce_width_mult: float = 1.0
var _charge_dash_speed_mult: float = 1.0
## 티어별 표식 깊이 — base + per_tier×tier. _fire_slash 가 산출해 _charge_pending_mark_depth 로 다음 1발에 주입.
var _charge_mark_depth_base: int = 1
var _charge_mark_depth_per_tier: int = 0
## 심호흡(CHARGE_HASTE) — 차징 가속 배수(_update_aim charge_mult 에 곱). 0=무효.
var _charge_haste_mult: float = 0.0
## 발도완극(CHARGE_PERFECT) — 풀차지 후 오버차지 자동발사 윈도우 연장(퍼펙트 릴리즈) + 깊이/사거리 보강.
var _charge_perfect_has: bool = false
var _charge_perfect_window: float = 0.0
## 다음 일섬 1발에 주입할 표식 깊이(SlashAttack.charge_mark_depth). _fire_slash 가 세팅·소비(1발 한정).
var _charge_pending_mark_depth: int = 0
## 발도회천(CHARGE_DASH_CANCEL) — 차징 중 회피 시 재차지 가속/대시 가산. 보유 시 add_boon 에서 세팅.
var _charge_dash_cancel_has: bool = false
var _charge_dash_cancel_haste: float = 0.0
var _charge_dash_cancel_dash: float = 0.0

## M8 — 컨트롤은 일섬 단일로 통합됐다. 이 플래그는 항상 true 로 고정(_ready 에서
## 세팅). 수십 개 분기·게터(is_instant_slash_mode, add_heat/add_slash_gauge 가드,
## _is_cooldown_resource 등)가 이 변수를 읽으므로 변수 자체는 보존한다. 옛 근접
## 밀리(LB 스윙·RB 게이지 일섬) 경로는 전면 삭제됐다.
var _instant_slash: bool = true

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

## M4 meta passive — `MetaProgressionSystem.apply_to` adds owned levels
## of the "인내" passive here. take_hit uses `HIT_IFRAME + iframe_bonus`.
var iframe_bonus: float = 0.0

## M6 — yellow elite (effect_type 4) charges this on death. Each charge
## absorbs one hit's damage in `take_hit` (i-frame still triggers so the
## PC isn't immediately re-hit). No upper cap — stacks if multiple
## yellow elites die before any hit lands.
var shield_charges: int = 0

# --- M3 card flags 제거됨 (M8 S1) · 젠/패리 제거됨 (M8 S3a) ---
# Multistrike/Echo/Vampire/Phoenix/Counter Step/Parry Master/월영 원무 등
# 레거시 스킬 빌드 효과는 전면 철거. 젠(Zen) 버스트·저스트 패리(RMB) 코어도
# 권속 은혜가 인게임 액티브 깊이를 대체하면서 철거. 회피/퍼펙트닷지·일섬 게이지·
# 열관리·shield_charges 같은 코어 전투 시스템은 보존(아래에 그대로 남아 있음).

func _ready() -> void:
	if data == null:
		data = PlayerData.new()
	if data.visuals == null:
		data.visuals = CharacterVisuals.new()
		data.visuals.placeholder_tint = Color(0.85, 0.9, 1.0)

	# 데이터 관리 — pc_combat.json 값으로 PlayerData 를 덮어쓴다(파일/값 없으면
	# 기존 기본값 유지). max_hp 등을 읽기 전에 적용해야 반영됨.
	_CombatDataScript.apply_to_player(self)

	# 일섬 잡몹 데미지 = data.slash_base_damage + 런타임 보너스(스킬 카드). data 가 그
	# export 를 가질 때만 적용(구버전 .tres 대비), 없으면 기존 attack_power(1) 유지.
	# ArenaDebug 슬라이더(1~10)가 이후 attack_power 를 직접 덮어쓸 수 있다.
	if "slash_base_damage" in data:
		attack_power = int(data.slash_base_damage) + slash_damage_bonus

	# M8 — 컨트롤은 일섬 단일. 항상 true 로 고정.
	_instant_slash = true

	# 일섬 단일 — NPC 와 서로 밀리지 않게 PC 레이어를 비운다(적이 PC 를 못 밀침).
	# 대신 접촉 시 _check_contact_damage 로 HP 감소. 일섬 대시 중 적 관통도 이 0 이 전제.
	collision_layer = 0
	# 비대칭 충돌 — PC 는 World 만 마스크해 몬스터에 막히거나 밀리지 않는다(몬스터는
	# PC 를 못 민다). 대신 각 몬스터가 Player 를 마스크해 PC 와 겹치면 스스로 옆으로
	# 빠져나가므로, PC 가 군중을 헤집고 지나가면 몬스터가 밀려난다. 한 방향
	# 디펜트레이션이라 예전의 상호 "쭉 밀림" 끼임 버그는 재발하지 않는다.
	collision_mask = (1 << 0)  # World only (몬스터에 안 막힘 = PC 불가침)
	# 대시 종료/사망 시 복원할 기본 레이어를 캐시(일섬 단일=0).
	_collision_layer_default = collision_layer

	_aim_arrow = get_node_or_null(aim_arrow_path) as AimArrow
	if _aim_arrow != null and data != null:
		if "min_slash_range" in data:
			_aim_arrow.min_length = data.min_slash_range
		if "instant_slash_distance" in data:
			_aim_arrow.max_length = data.instant_slash_distance
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

	active_boons.clear()
	# M9-S9 정기흡수 런타임 자원 리셋(런마다 0부터 — 공유 .tres 미변형).
	_spirit_stacks = 0
	_spirit_release_pending = false
	# M9-S10 연격류 런타임 리셋(런마다 — 속발 미보유면 _nuki_active=false 로 비활성).
	_nuki_active = false
	_nuki_window_t = 0.0
	_nuki_combo = 0
	_nuki_accel_tier = 0
	_nuki_rhythm = 0
	_nuki_combo_kills = 0
	_nuki_accel_has = false
	_nuki_rhythm_has = false
	_nuki_settle_has = false
	_nuki_cadence_has = false
	# M9-S11 충전류 런타임 리셋(런마다 — 일도양단 미보유면 _charge_active=false 로 비활성, 기존 경로 회귀 0).
	_charge_active = false
	_charge_pending_mark_depth = 0
	_charge_perfect_has = false
	_charge_mark_depth_per_tier = 0
	_boon_executor = _BoonExecutorScript.new()
	_boon_executor.name = "BoonExecutor"
	add_child(_boon_executor)
	_boon_executor.call("setup", self)

	# 머리 위 상태 아이콘 스트립(굶주림 등) — 적과 동일 공용 컴포넌트. 머리 위(y≈2.0).
	var strip := _StatusStripScript.new()
	strip.name = "StatusIconStrip3D"
	if "follow_offset" in strip:
		strip.follow_offset = Vector3(0, 2.0, 0)
	add_child(strip)
	_status_strip = strip

func _physics_process(delta: float) -> void:
	# 열관리(일섬 단일) — 탈진 타이머 + 지수 감소.
	_update_heat(delta)
	# 몬스터 몸 접촉 시 HP 감소(무적/대시 중 스킵). contact_damage_enabled 토글이 게이트.
	_check_contact_damage()
	# 연속 대시 사이 최소 간격.
	if _evade_cd > 0.0:
		_evade_cd -= delta
	# 납도(RB) 쿨다운.
	if _sheathe_cd_t > 0.0:
		_sheathe_cd_t -= delta
	# M9-S7 거합 추격 윈도우 — 미입력 시 시간 경과로 닫힘(자동 발동 0). _sheathe_follow_used 는
	# 다음 일반 납도 시작 시 리셋(추격 1회 cap 유지).
	if _sheathe_follow_t > 0.0:
		_sheathe_follow_t -= delta
	# M9-S10 연격류 연타 윈도우 — 미입력 시 시간 경과로 닫힘. 닫히면 콤보 마무리(자동 정산+리셋).
	# ★_nuki_active(속발 보유) 일 때만 윈도우가 열려 있으므로, 미보유면 항상 0 = no-op(회귀 0).
	if _nuki_window_t > 0.0:
		_nuki_window_t -= delta
		if _nuki_window_t <= 0.0:
			_nuki_window_t = 0.0
			_nuki_end_combo()
	# M9-S7 폭심 충전 예약 윈도우 — 만료 시 예약 소멸(다음 일섬에 적용 안 됨).
	if _next_burst_t > 0.0:
		_next_burst_t -= delta
		if _next_burst_t <= 0.0:
			_next_burst_t = 0.0
			boon_next_slash_range_mult = 1.0
			boon_next_slash_width_mult = 1.0
			boon_next_slash_heat_refund = 0.0
	# 역수(IAIDO_HASTE) 윈도우 타이머 — 다음 일섬 발사 또는 시간 경과로 종료.
	if boon_haste_t > 0.0:
		boon_haste_t -= delta
	# 쿨 가속 — 역수 윈도우 중이면 쿨다운이 ×(1+haste) 속도로 닳는다.
	var _cd_step: float = delta * (1.0 + boon_haste_charge_mult) if boon_haste_t > 0.0 else delta
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
	if _zone_slow_t > 0.0:
		_zone_slow_t -= delta
	match _state:
		State.IDLE:
			_handle_move(delta)
			_check_nuki_retap()
			_check_instant_slash()
			_check_sheathe()
			_check_evade_start()
			if _cooldown_t > 0.0:
				_cooldown_t -= _cd_step
		State.AIMING:
			# 일섬 단일 — 차징하며 이동 가능.
			_handle_move(delta)
			# M9-S11 발도회천(CHARGE_DASH_CANCEL) — 충전류 활성 시 차징 중 회피 입력이면 차지 버리고 회피(우선 체크).
			# 회피로 전환되면 이번 프레임 _update_aim/release 는 스킵(상태가 EVADING 으로 바뀜).
			if _charge_active and _check_charge_dash_cancel():
				return
			_update_aim(delta)
			_check_attack_release()
		State.DASHING:
			_update_dash(delta)
		State.COOLDOWN:
			_handle_move(delta)
			_check_nuki_retap()
			_check_sheathe()
			_check_evade_start()
			_cooldown_t -= _cd_step
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
	var speed_mult: float = 1.0
	# 열관리 — 탈진(오버히트) 중 이동 감속(토글). 기본 패널티는 발사 봉인만이며,
	# 이동 감속은 GameConfig.overheat_move_slow_enabled 가 켜진 경우에만 적용.
	if _overheated and _GameConfigScript.overheat_move_slow_enabled:
		speed_mult *= data.heat_overheat_move_mult
	# 주술사 장판(SorcererZone) 안에 있는 동안 이동 감속 — PC 동선 방해.
	if _zone_slow_t > 0.0:
		speed_mult *= _zone_slow_mult
	# (3) 사격 중 이동 감속 기믹 제거 — 이동은 항상 정상 속도.
	velocity.x = dir.x * data.move_speed * speed_mult
	velocity.z = dir.z * data.move_speed * speed_mult
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

## D-3 — 일섬 자원 방식. 0=열기(Heat) / 1=고정 쿨다운.
func _is_cooldown_resource() -> bool:
	return _GameConfigScript.slash_resource_mode == 1

## D-3 — 일섬 에임 방식. 0=차징 / 1=즉발(LB 누르는 즉시 풀거리 발사).
func _is_instant_aim() -> bool:
	return _GameConfigScript.slash_aim_mode == 1

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
		# M9-S11 충전류 — 일도양단 보유 시 GameConfig.slash_aim_mode 무관하게 차징 경로 강제(즉발 스킵).
		if _is_instant_aim() and not _charge_active:
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
		if _sprite_rig != null and _sprite_rig.has_method("set_charge_glow"):
			_sprite_rig.call("set_charge_glow", false)
		if _aim_arrow != null:
			_aim_arrow.show_arrow()
			_aim_arrow.set_charge(0.0)


# ══════════════ 납도(On_Sheathe) — RB 로 표식 정산 ══════════════

## RB(slash 액션) 입력 체크 — 쿨/UI 가드 통과 시 _do_sheathe. IDLE/COOLDOWN 에서만 호출됨
## (AIMING 차징·DASHING·EVADING 보호). LB(fire)=일섬과 분리된 입력이라 충돌 없음.
func _check_sheathe() -> void:
	# ── M9-S7 거합 추격 윈도우 — 처치 직후 짧은 윈도우 안 RB 재입력이면 쿨 무시 즉시 추격 납도 1회. ──
	# ★_sheathe_follow_used=true 세팅 → 이 추격 납도가 일으킨 처치로 open_sheathe_follow 가 또 호출돼도
	#   used 라 재오픈 거부 = 추격 1회 cap(무한 추격 방지). 일반 납도 경로에서만 used 가 false 로 리셋된다.
	if _sheathe_follow_t > 0.0 and Input.is_action_just_pressed("slash") and not _is_pointer_over_ui():
		_sheathe_follow_used = true
		_sheathe_follow_t = 0.0
		_sheathe_cd_t = 0.0  # 쿨 무시(추격 바이패스).
		_do_sheathe()
		return
	if _sheathe_cd_t > 0.0:
		return
	if not Input.is_action_just_pressed("slash"):
		return
	if _is_pointer_over_ui():
		return
	# 일반(추격 아닌) 납도 시작 — 추격 1회 cap 리셋(이 납도가 처치를 내면 다시 추격 윈도우를 열 수 있게).
	_sheathe_follow_used = false
	_do_sheathe()


## M9-S7 거합 추격 윈도우 오픈 — BoonExecutor 가 ON_SHEATHE_KILL(처치) 발생 납도 끝에서 1회 호출.
## 이미 이번 추격 체인에서 한 번 열었으면(used) 재오픈 금지 → 추격은 연속 1회만(무한 방지).
## 미입력 시 _sheathe_follow_t 가 _physics_process 에서 0 으로 닳아 윈도우가 자동으로 닫힌다(자동 발동 0).
func open_sheathe_follow() -> void:
	if _sheathe_follow_used:
		return
	_sheathe_follow_t = 0.4
	# 칼집 금빛 잔광 더미(선택) — 기존 섬광 재사용.
	_spawn_sheathe_flash()


## 납도 발동 — 짧은 거두기 모션 + 칼집 섬광 더미연출 + ON_SHEATHE 발행(BoonExecutor 가 정산).
## 표식 적이 없으면 정산은 BoonExecutor 쪽에서 자연히 no-op(헛납도) — 모션만 남는다.
func _do_sheathe() -> void:
	_sheathe_cd_t = maxf(data.sheathe_cooldown, 0.001)
	# 거두기 모션 — attack1 1회 재생(없으면 flash 폴백).
	if _sprite_rig != null and _sprite_rig.has_method("play_oneshot"):
		_sprite_rig.call("play_oneshot", "attack1", 0.2)
	elif _sprite_rig != null and _sprite_rig.has_method("flash"):
		_sprite_rig.call("flash", 0.15)
	_spawn_sheathe_flash()
	_play_sfx("slash")
	var tb := _trigger_bus()
	if tb != null:
		tb.call("emit", _TriggerBusScript.ON_SHEATHE, {"source": self, "position": global_position})


## HUD 납도 쿨다운 클록용 — 1=방금 거둠(쿨 가득) / 0=준비됨.
func get_sheathe_cooldown_frac() -> float:
	return clampf(_sheathe_cd_t / maxf(data.sheathe_cooldown, 0.001), 0.0, 1.0)


## 납도 준비 완료 여부(쿨 0 이하).
func is_sheathe_ready() -> bool:
	return _sheathe_cd_t <= 0.0


## 납도 정산 자원 환급(BoonExecutor 가 거둔 표식 총합으로 호출). 음수 열 가산 + HP 미세 회복.
## 표식 0이면 호출되지 않는다(헛납도 = 자원 변화 없음).
## heat_extra_per/hp_extra_per = 환원(SHEATHE_REFUND) marks당 추가 환급. refund_mult = 거합/환원 곱.
## 디폴트 인자 = 베이스 납도(은혜 없을 때) 호환.
func _sheathe_restore(total_marks: int, heat_extra_per: float = 0.0, hp_extra_per: float = 0.0, refund_mult: float = 1.0) -> void:
	if total_marks <= 0:
		return
	# M9-S9 정기흡수 '정기 해방' — 만스택(_spirit_release_pending) 도달 후 이 납도 정산이 ×release_mult 대정산.
	# ★1회만(pending 소비) + 스택 0 리셋. release_mult 는 refund_mult 와 곱해 열/HP 환급 모두 증폭.
	var release: float = 1.0
	if _spirit_release_pending:
		release = _spirit_release_mult
		_spirit_release_pending = false
		_spirit_stacks = 0
	# M9-S10 연격 마무리 리듬 부스트 — 1회 소비(연격류 자동 정산에서만 >1.0).
	var nuki_boost: float = _nuki_settle_refund_boost
	_nuki_settle_refund_boost = 1.0
	var heat_per: float = (_SHEATHE_HEAT_REFUND_PER_MARK + heat_extra_per) * float(total_marks) * refund_mult * release * nuki_boost
	_refund_heat(heat_per)
	var hp_per: float = (_SHEATHE_HP_PER_MARK + hp_extra_per) * float(total_marks) * refund_mult * release * nuki_boost
	var hp_amt: int = int(round(hp_per))
	if hp_amt > 0 and _health != null:
		_health.heal(hp_amt)


## M9-S7 폭심 충전(EPICENTER_OVERCHARGE) — BoonExecutor 가 납도 처형 시 호출. 다음 일섬 '1발'에만
## 적용될 사거리/폭 배수 + 열 환급을 예약(누적 아님 — 세팅/최댓값). _fire_slash 가 1발 소비 후 즉시 리셋.
## window(s) 안에 발사 안 하면 _physics_process 가 예약 소멸. 공유 .tres 미변형(런타임 인스턴스 변수).
func reserve_next_slash_burst(range_mult: float, width_mult: float, heat_refund: float, window: float) -> void:
	boon_next_slash_range_mult = max(1.0, range_mult)
	boon_next_slash_width_mult = max(1.0, width_mult)
	boon_next_slash_heat_refund = max(0.0, heat_refund)
	_next_burst_t = max(window, 0.1)


## 거합(IAIDO_PERFECT) perfect 판정용 — 마지막 일섬 착지 시각(ms). 0=아직 일섬 착지 없음.
func get_last_slash_end_msec() -> int:
	return last_slash_end_msec


## 열 환급(음수 경로) — add_heat 는 가산 전용이라 별도. 탈진 상태는 건드리지 않는다
## (탈진은 _update_heat 의 자체 타이머로 풀림). 쿨다운 자원 모드면 열 개념 없어 no-op.
func _refund_heat(amount: float) -> void:
	if not _instant_slash or _overheated:
		return
	if _is_cooldown_resource():
		return
	_heat = clamp(_heat - amount, 0.0, data.heat_overheat_threshold)


## 칼집 섬광 더미연출 — 청백 톤 가벼운 연출(과한 신규 노드 금지). 스프라이트 flash +
## 카메라 미세 쉐이크로 '거뒀다' 손맛만 준다.
func _spawn_sheathe_flash() -> void:
	if _sprite_rig != null and _sprite_rig.has_method("flash"):
		_sprite_rig.call("flash", 0.12)
	var rig := get_tree().get_first_node_in_group("camera_rig")
	if rig != null and rig.has_method("shake"):
		rig.call("shake", 0.05, 0.12)


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
			# 역수(IAIDO_HASTE) — 윈도우 중이면 고정 쿨도 ×(1+haste) 가속.
			_slash_fixed_cd_t -= delta * (1.0 + boon_haste_charge_mult) if boon_haste_t > 0.0 else delta
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
	if since > max(0.0, data.heat_decay_delay):
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
	_overheat_t = max(0.5, data.heat_overheat_duration)
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
	# 일섬 단일 — LB(fire) 홀드 차징. 버튼을 떼면 발사.
	if not Input.is_action_pressed("fire"):
		_fire_slash()

func _update_aim(delta: float) -> void:
	# 충전 속도 배수 — charge_speed_mult(기본 0.5)만큼 천천히 차오른다(데이터 제어).
	# 역수(IAIDO_HASTE) 윈도우 중이면 충전 가속 ×(1+haste).
	var charge_mult: float = data.charge_speed_mult
	if boon_haste_t > 0.0:
		charge_mult *= (1.0 + boon_haste_charge_mult)
	# M9-S11 심호흡(CHARGE_HASTE) — 충전류 활성 시 차징 가속(미보유면 0 = 무효).
	if _charge_active and _charge_haste_mult > 0.0:
		charge_mult *= (1.0 + _charge_haste_mult)
	_charge_t = min(_charge_t + delta * charge_mult, data.max_charge_time)
	# 최대 차지 도달 후 오버차지 누적 — instant_overcharge_hold 초 버틴 뒤 자동 발사.
	if _charge_t >= data.max_charge_time:
		_overcharge_t += delta
		if _sprite_rig != null and _sprite_rig.has_method("set_charge_glow"):
			_sprite_rig.call("set_charge_glow", true)
		# M9-S11 발도완극(CHARGE_PERFECT) — 충전류+퍼펙트 보유 시 자동발사 임계를 윈도우만큼 연장(퍼펙트 릴리즈 여유).
		var auto_hold: float = data.instant_overcharge_hold
		if _charge_active and _charge_perfect_has:
			auto_hold = max(auto_hold, _charge_perfect_window)
		if _overcharge_t >= auto_hold:
			_fire_slash()
			return
	var dir := _mouse_to_world_dir()
	if dir.length_squared() > 0.0001:
		_aim_dir = dir
	if _aim_arrow != null:
		var charge_frac: float = _charge_t / max(data.max_charge_time, 0.0001)
		_aim_arrow.set_charge(charge_frac)
		_aim_arrow.aim_at_direction(_aim_dir)
	# 캐릭터 방향은 마우스에 동기화하지 않는다(공격 방향만 _aim_dir 로 추적). 이동하며
	# 차징하므로 _handle_move 가 방향/걷기 애니를 정한다.
	# LB 차징 줌아웃(ESC 토글) — 차징 동안 카메라가 서서히 빠진다(최대값 cap).
	_apply_charge_zoom(true)


## LB 차징 줌아웃(ESC 토글) — 차징 중 카메라를 서서히 빼고, 비활성/꺼짐이면 복귀.
func _apply_charge_zoom(active: bool) -> void:
	var on: bool = active and _instant_slash and _GameConfigScript.charge_zoom_enabled
	var rig := get_tree().get_first_node_in_group("camera_rig")
	if rig != null and rig.has_method("set_charge_zoom"):
		rig.call("set_charge_zoom", on)


func _fire_slash() -> void:
	if _sprite_rig != null and _sprite_rig.has_method("set_charge_glow"):
		_sprite_rig.call("set_charge_glow", false)
	# 4안 — 일섬 발동 → 게이지 0으로 리셋.
	_slash_gauge = 0.0
	var charge_frac: float = clamp(_charge_t / max(data.max_charge_time, 0.0001), 0.0, 1.0)
	# ── M9-S11 충전류(일도양단) — 티어 산출 → 다음 일섬 1발 표식 깊이 예약 + 풀차지 관통 배수. ──
	# ★_charge_active 미보유면 전부 스킵(1발 깊이 0·배수 1.0 = 기존 거동, 회귀 0).
	if _charge_active:
		var tier: int = 0 if charge_frac < _charge_tier_lo else (1 if charge_frac < _charge_tier_hi else 2)
		# 퍼펙트 릴리즈 판정 — 풀차지(tier2)에서 오버차지가 윈도우 안(아직 자동발사 임계 미만)인 릴리즈.
		var was_perfect: bool = _charge_perfect_has and charge_frac >= 1.0
		_charge_pending_mark_depth = _charge_mark_depth_base + _charge_mark_depth_per_tier * tier
		if was_perfect:
			_charge_pending_mark_depth += 1
	# 구미낙화(SLASH_FAN) — 풀차지면 ON_SLASH_CHARGED 를 *먼저* 발행해 BoonExecutor 가
	# 부채 폭 확장 플래그를 세팅하게 하고, 같은 일섬이 그 플래그를 ext 에 소비한다.
	var _tb_charged := _trigger_bus()
	if charge_frac >= 1.0 and _tb_charged != null:
		_tb_charged.call("emit", _TriggerBusScript.ON_SLASH_CHARGED, {"source": self, "position": global_position, "charge_frac": charge_frac})
	# 사거리 — 차징 0→1 에 따라 min ~ instant_slash_distance 로 풀차지 사거리 증가.
	var slash_range: float = lerp(data.min_slash_range, data.instant_slash_distance, charge_frac)
	# 일섬연장(SLASH_EXTEND) — 패시브 사거리 배수(공유 .tres 미변형, 런타임 변수).
	slash_range *= boon_slash_range_mult
	# M9-S11 충전류 — 풀차지 관통 사거리 배수(충전류 자체 보너스, SLASH_EXTEND 와 곱셈 누적). 미보유=1.0.
	if _charge_active:
		slash_range *= _charge_pierce_range_mult
	# M9-S7 폭심 충전(EPICENTER_OVERCHARGE) — 예약된 다음 일섬 1발이면 사거리 대버스트.
	var burst_active: bool = _next_burst_t > 0.0
	if burst_active:
		slash_range *= boon_next_slash_range_mult
	var ext: Vector3 = data.slash_hit_extents
	# 일섬연장(SLASH_EXTEND) — 패시브 폭/관통 배수. x=폭, z=전방 길이 가산 모두 확장.
	if boon_slash_width_mult > 1.0:
		ext = Vector3(ext.x * boon_slash_width_mult, ext.y, ext.z * boon_slash_width_mult)
	# M9-S11 충전류 — 풀차지 관통 폭 배수(충전류 자체 보너스, 곱셈 누적). 미보유=1.0.
	if _charge_active and _charge_pierce_width_mult > 1.0:
		ext = Vector3(ext.x * _charge_pierce_width_mult, ext.y, ext.z * _charge_pierce_width_mult)
	# M9-S7 폭심 충전 — 예약된 다음 일섬 1발이면 폭 대버스트(x=폭, z=전방 길이 모두 확장).
	if burst_active and boon_next_slash_width_mult > 1.0:
		ext = Vector3(ext.x * boon_next_slash_width_mult, ext.y, ext.z * boon_next_slash_width_mult)
	# 직전(또는 방금 발행된 ON_SLASH_CHARGED)에서 세팅된 부채 폭 확장 보너스를 이번 일섬에 소비.
	# 공유 PlayerData.tres 를 변형하지 않도록 로컬 복사본의 x(폭)만 키운다(런마다 리셋되는 런타임 변수).
	if boon_slash_fan_width_mult > 1.0:
		ext = Vector3(ext.x * boon_slash_fan_width_mult, ext.y, ext.z + boon_slash_fan_arc_bonus)
		boon_slash_fan_width_mult = 1.0
		boon_slash_fan_arc_bonus = 0.0
	# 역수(IAIDO_HASTE) — 다음 일섬을 소비하면 가속 윈도우 종료.
	boon_haste_t = 0.0
	_dash_start = global_position
	_dash_end = global_position + _aim_dir.normalized() * slash_range
	_dash_elapsed = 0.0
	# 돌진 속도(m/s) → 동적 대시 시간 = 거리 ÷ 속도(거리가 멀어도 체감 일정).
	# M9-S11 충전류 — 풀차지 관통은 대시 속도 ×_charge_dash_speed_mult(빠른 관통). 미보유=1.0.
	var dash_speed: float = data.slash_dash_speed
	if _charge_active:
		dash_speed *= _charge_dash_speed_mult
	_dash_dur = max(slash_range / max(dash_speed, 0.01), 0.02)
	# 일섬 대시 중 적 관통 — PC 를 Player 레이어에서 빼 적의 디펜트레이션 솔버가
	# 대시를 막지 못하게(종료 시 _complete_slash_action 에서 복원).
	collision_layer = 0
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
	_spawn_slash_attack(_dash_start, _dash_end, ext)
	# M7 — slash SFX cue. SoundManager silently no-ops if no .ogg yet.
	if Engine.has_singleton("SoundManager") or _has_sound_manager():
		_play_sfx("slash")
	slash_started.emit()
	var _tb := _trigger_bus()
	if _tb != null:
		_tb.call("emit", _TriggerBusScript.ON_SLASH_START, {"source": self, "position": global_position, "charge_frac": charge_frac})
		# ON_SLASH_CHARGED 는 위에서 이미 발행됨(SLASH_FAN 동일-일섬 적용 위해 spawn 전).
		if Time.get_ticks_msec() - _last_evade_end_msec <= 500:
			_tb.call("emit", _TriggerBusScript.ON_SLASH_RIGHT_AFTER_DASH, {"source": self, "position": global_position})
	# 일섬 자원 처리 — 고정 쿨다운(락 세팅) 또는 열기(누적+탈진).
	if _is_cooldown_resource():
		_slash_fixed_cd_t = max(data.slash_fixed_cooldown, 0.0)
	else:
		_add_heat()
	# M9-S7 폭심 충전 — 예약 버스트 1발 소비. 열 환급(_add_heat 후 적용 — 누적 열을 일부 식힘) +
	# 즉시 리셋(다음 일섬은 무효, 1발만 적용). 누적 금지.
	if burst_active:
		if boon_next_slash_heat_refund > 0.0:
			_refund_heat(data.heat_overheat_threshold * boon_next_slash_heat_refund)
		boon_next_slash_range_mult = 1.0
		boon_next_slash_width_mult = 1.0
		boon_next_slash_heat_refund = 0.0
		_next_burst_t = 0.0

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
		# 일섬 착지 시각 기록 — 거합(IAIDO_PERFECT) perfect 윈도우 기준점.
		last_slash_end_msec = Time.get_ticks_msec()
		_complete_slash_action()


func _complete_slash_action() -> void:
	# 대시 종료 — 콜리전 레이어 복원(일섬 단일=0, 적 관통/비충돌 유지).
	collision_layer = _collision_layer_default
	_cooldown_t = data.slash_cooldown
	slash_finished.emit()
	var _tb_end := _trigger_bus()
	if _tb_end != null:
		_tb_end.call("emit", _TriggerBusScript.ON_SLASH_END, {"source": self, "position": global_position})
	# M9-S10 연격류 — 이 일섬 직후 재입력 윈도우를 연다(콤보 상한 미달일 때만). 미보유면 no-op.
	_nuki_open_window()
	_set_state(State.COOLDOWN if data.slash_cooldown > 0.0 else State.IDLE)


# ══════════════ M9-S10 연격류(STYLE_NUKI) — LB 연타 control mechanic ══════════════

## 일섬 발도 직후 호출(_complete_slash_action) — 재입력 윈도우를 연다.
## ★_nuki_active(속발 보유) 일 때만 동작. 콤보 상한(_nuki_max) 도달이면 윈도우 안 열고 콤보 마무리.
## 콤보가 0이면 이 일섬이 새 콤보의 1타 — 콤보=1·처치카운트 리셋(연쇄가락 보존이 아니면 티어도 0).
func _nuki_open_window() -> void:
	if not _nuki_active:
		return
	# 새 콤보 시작(이 일섬이 첫 타) — 콤보/처치 카운트 초기화. 가속 티어는 연쇄가락 보존분만 유지.
	if _nuki_combo <= 0:
		_nuki_combo = 1
		_nuki_combo_kills = 0
	# 콤보 상한 도달 — 더 못 잇는다. 마무리(자동 정산+리셋).
	if _nuki_combo >= _nuki_max:
		_nuki_end_combo()
		return
	# 윈도우 길이 = base + 리듬 충전 보너스(연참의박 need 도달 시 폭↑).
	var win: float = _nuki_window_base
	if _nuki_rhythm_has and _nuki_rhythm >= _nuki_rhythm_need:
		win += _nuki_rhythm_window_bonus
	_nuki_window_total = max(win, 0.05)
	_nuki_window_t = _nuki_window_total


## 연타 윈도우 재입력 체크 — IDLE/COOLDOWN 에서 매 프레임. 윈도우가 열려 있고 콤보 상한 미달이면
## 쿨다운 게이트를 무시하고(연타 윈도우 자체가 페이스 제한) LB 재입력 시 즉발 연격. 탈진 중엔 봉인.
## ★_nuki_active(속발 보유) 게이트라 미보유면 항상 즉시 return = 회귀 0.
func _check_nuki_retap() -> void:
	if not _nuki_active:
		return
	if _nuki_window_t <= 0.0 or _nuki_combo >= _nuki_max:
		return
	if _overheated:
		return  # 탈진 중엔 연타도 봉인.
	if not Input.is_action_just_pressed("fire"):
		return
	if _is_pointer_over_ui():
		return
	_nuki_retap()


## 윈도우 열린 중 LB 재입력 — 콤보+1, sweet spot 판정으로 가속 티어/리듬 갱신 후 즉발 일섬.
## 충전 단계(AIMING) 없이 숏 발도(retap_charge_frac 의 충전 프랙)로 즉시 _fire_slash.
func _nuki_retap() -> void:
	# sweet spot = 윈도우 후반 sweet_frac 구간(잔여/총 ≤ sweet_frac).
	var frac_left: float = _nuki_window_t / max(_nuki_window_total, 0.0001)
	var is_sweet: bool = frac_left <= _nuki_sweet_frac
	_nuki_combo += 1
	if is_sweet:
		# 퍼펙트 연타 — 가속 티어 +1(max), 리듬 +1, 다음 발도 가속(역수 haste 변수 재사용).
		if _nuki_accel_has:
			_nuki_accel_tier = min(_nuki_accel_tier + 1, max(_nuki_accel_max_tier, 0))
			apply_iaido_haste(_nuki_accel_haste * float(_nuki_accel_tier), _nuki_accel_dash * float(_nuki_accel_tier))
		if _nuki_rhythm_has:
			_nuki_rhythm += 1
	else:
		# 일반 적중 — 콤보만 유지, 티어 가산 없음. 퍼펙트 사슬 끊김 → 리듬 식음.
		if _nuki_rhythm_has:
			_nuki_rhythm = 0
	# 윈도우는 닫고(이 입력 소비) — 발도 후 _nuki_open_window 가 다시 연다.
	_nuki_window_t = 0.0
	# 숏 발도 — 충전 프랙을 retap_charge_frac 로 세팅해 즉발(풀차지 미만 = 더 빠른 발도).
	_charge_t = data.max_charge_time * clampf(_nuki_retap_charge_frac, 0.1, 1.0)
	_overcharge_t = 0.0
	_fire_slash()


## 콤보 종료 — 윈도우 만료/상한 도달 시. 납도결산 보유면 자동 납도 정산(ON_SHEATHE) 1회 발동.
## 그 후 콤보/티어 리셋(연쇄가락 — 이번 콤보 2명+ 처치 시 가속 티어 보존). ★자율 킬 없음(정산은 기존 _on_sheathe 경로 재사용).
func _nuki_end_combo() -> void:
	if _nuki_combo <= 0:
		return
	# 납도결산 — 연타 마지막 타 직후 자동 납도 정산(표식 적 거둠). 기존 ON_SHEATHE 경로 재사용(_in_cascade 가드 포함).
	if _nuki_settle_has:
		# 리듬 충전(need 도달) 중이면 이 마무리 정산 환급을 settle_mult 만큼 가중(1회 소비).
		if _nuki_rhythm_has and _nuki_rhythm >= _nuki_rhythm_need:
			_nuki_settle_refund_boost = max(1.0, _nuki_rhythm_settle_mult)
		var tb := _trigger_bus()
		if tb != null:
			tb.call("emit", _TriggerBusScript.ON_SHEATHE, {"source": self, "position": global_position})
	# 연쇄가락 — 이번 콤보가 kills_need 이상 처치했으면 가속 티어 보존, 아니면 0.
	if not (_nuki_cadence_has and _nuki_combo_kills >= _nuki_cadence_kills_need):
		_nuki_accel_tier = 0
	_nuki_combo = 0
	_nuki_combo_kills = 0


## BoonExecutor/킬 배선 — 연격류 콤보 중 처치가 일어날 때 호출(연쇄가락 처치 카운트).
func nuki_note_kill() -> void:
	if _nuki_active and _nuki_combo > 0:
		_nuki_combo_kills += 1


# 연격류 getter(HUD/디버그용).
func is_nuki_active() -> bool:
	return _nuki_active

func get_nuki_combo() -> int:
	return _nuki_combo

func get_nuki_accel_tier() -> int:
	return _nuki_accel_tier

func _spawn_slash_attack(start: Vector3, end: Vector3, extents: Vector3 = Vector3.ZERO) -> void:
	_spawn_slash_attack_node(start, end, extents)


## _spawn_slash_attack 의 노드 반환 변형 — 참향(mark_only) 등 스폰 후 플래그를 세팅해야 하는
## 경로에서 사용. 스폰/구성은 동일, 생성된 SlashAttack 를 반환(실패 시 null).
func _spawn_slash_attack_node(start: Vector3, end: Vector3, extents: Vector3 = Vector3.ZERO) -> SlashAttack:
	var attack: SlashAttack
	if slash_attack_scene != null:
		attack = slash_attack_scene.instantiate() as SlashAttack
	else:
		attack = SlashAttack.new()
	var host := _effect_host()
	if host == null:
		attack.queue_free()
		return null
	host.add_child(attack)
	var ext: Vector3 = extents if extents.length_squared() > 0.0001 else data.slash_hit_extents
	attack.configure(start, end, ext)
	attack.lifetime = data.slash_hit_lifetime
	# M9-S9 정기흡수: 스택당 일섬 피해 +per_stack%. (spawn_echo_slash 의 mark_only 경로는 호출 후
	# attack_power=0 으로 덮으므로 영향 없음 — 0 유지.) ★런타임 변수만, 공유 .tres 미변형.
	var spirit_mult: float = 1.0 + _spirit_per_stack * float(_spirit_stacks)
	attack.attack_power = int(round(float(attack_power) * spirit_mult))
	# M9-S11 충전류 — 예약된 표식 깊이를 이 일섬 본체에 주입(SlashAttack 가 적중마다 1+depth 누적).
	# ★1발 한정 소비 — 주입 후 즉시 0 리셋(finisher/echo 재호출에 안 묻음). 참향(mark_only) 경로는 호출 후
	#   attack_power=0 으로 덮지만 깊이 0 이라 무관. 미보유(_charge_pending_mark_depth==0)면 set 안 함(기존 +1).
	if _charge_pending_mark_depth > 0:
		attack.set("charge_mark_depth", _charge_pending_mark_depth)
		_charge_pending_mark_depth = 0
	return attack

## 거합일도(IAIDO_FINISHER) — BoonExecutor 가 거합+만개 처형 시 호출. 마지막 일섬 방향(_aim_dir)으로
## 추가 일섬 본체를 count 줄 발사한다. 본체는 SlashAttack 라 _try_kill(데미지)·_apply_slash_mark(새 표식)
## 가 그대로 돌아 — 보스에 표식 재충전 + 잡몹 처치를 일으킨다. 공유 .tres 미변형(로컬 ext 만 확장).
func spawn_finisher_slash(count: int = 1) -> void:
	if count <= 0:
		return
	var dir: Vector3 = _aim_dir.normalized()
	if dir.length_squared() < 0.0001:
		dir = Vector3(1, 0, 0)
	var rng: float = data.instant_slash_distance * boon_slash_range_mult
	var ext: Vector3 = data.slash_hit_extents
	if boon_slash_width_mult > 1.0:
		ext = Vector3(ext.x * boon_slash_width_mult, ext.y, ext.z * boon_slash_width_mult)
	for _i in range(count):
		var s: Vector3 = global_position
		var e: Vector3 = global_position + dir * rng
		_spawn_slash_attack(s, e, ext)


## 참향(잔향 일섬, baseline) — BoonExecutor 가 ON_SHEATHE_KILL 시 호출. spawn_finisher_slash 변형으로
## 데미지/킬 없이 표식만 새기는 SlashAttack 1줄을 발사한다(mark_only). 방향 = _aim_dir(없으면
## epicenter 최근접 '미표식' 적 방향). 공유 .tres 미변형 — 로컬 ext/플래그만.
func spawn_echo_slash(epicenter: Vector3 = Vector3.INF) -> void:
	var dir: Vector3 = _aim_dir.normalized()
	if dir.length_squared() < 0.0001:
		dir = Vector3(1, 0, 0)
	# epicenter 가 주어졌으면 거기서 최근접 미표식 적 방향으로 보정(없으면 _aim_dir 유지).
	if epicenter.x != INF:
		var best: Node3D = null
		var best_d: float = INF
		for e in get_tree().get_nodes_in_group("enemies"):
			if e == null or not is_instance_valid(e) or not (e is Node3D):
				continue
			if int(e.get_meta("slash_mark", 0)) > 0:
				continue
			var d: float = (e as Node3D).global_position.distance_to(epicenter)
			if d < best_d:
				best_d = d
				best = e as Node3D
		if best != null:
			var to_e: Vector3 = best.global_position - global_position
			to_e.y = 0.0
			if to_e.length_squared() > 0.0001:
				dir = to_e.normalized()
	var rng: float = data.instant_slash_distance * boon_slash_range_mult
	var ext: Vector3 = data.slash_hit_extents
	if boon_slash_width_mult > 1.0:
		ext = Vector3(ext.x * boon_slash_width_mult, ext.y, ext.z * boon_slash_width_mult)
	var attack := _spawn_slash_attack_node(global_position, global_position + dir * rng, ext)
	if attack != null:
		attack.mark_only = true
		attack.attack_power = 0


## 역수(IAIDO_HASTE) — BoonExecutor 가 납도 성공 시 호출. 다음 일섬까지 가속 윈도우 켜고
## 대시 거리 가산을 갱신(누적 아님 — 항상 최댓값으로 세팅, 런마다 리셋).
func apply_iaido_haste(haste_pct: float, dash_bonus: float) -> void:
	boon_haste_charge_mult = max(boon_haste_charge_mult, haste_pct)
	boon_dash_dist_bonus = max(boon_dash_dist_bonus, dash_bonus)
	boon_haste_t = 4.0  # 다음 일섬까지의 가속 유효 시간(넉넉히 — 일섬 발사 시 즉시 종료).


## M9-S9 정기흡수(SPIRIT_STACK) — BoonExecutor 가 납도 처치마다 호출. PC '흡수 스택' +n(잡몹1/엘리트·보스 tier_gain 가산).
## ★PC 내부 자원만 — 적 직접 안 죽임(0뎀). 해방 대기 중(_spirit_release_pending)엔 더 안 쌓는다(다음 납도 정산을 기다림).
## 만스택 도달 시 _spirit_release_pending=true → 다음 _sheathe_restore 가 '정기 해방' 대정산 후 스택 0 리셋.
func boon_add_spirit(n: int, per_stack: float, max_stack: int, release_mult: float) -> void:
	_spirit_per_stack = per_stack
	_spirit_max = max(max_stack, 1)
	_spirit_release_mult = max(release_mult, 1.0)
	if _spirit_release_pending:
		return  # 해방 예약 중엔 다음 납도에서 소비될 때까지 더 안 쌓음.
	_spirit_stacks = min(_spirit_stacks + max(n, 1), _spirit_max)
	if _spirit_stacks >= _spirit_max:
		_spirit_release_pending = true


## M9-S9 발도충전분출(GAUGE_BURST) — BoonExecutor 가 납도 처치마다 호출. 일섬 자원을 frac 만큼 분출.
## 쿨 자원 모드면 다음 일섬 쿨을 frac 비례 단축(0 클램프), 열 모드면 열을 frac 비례 환급(_refund_heat 가드).
## ★0뎀 PC 자원만(공유 .tres 미변형).
func boon_gauge_burst(frac: float) -> void:
	frac = clampf(frac, 0.0, 1.0)
	if frac <= 0.0:
		return
	if _is_cooldown_resource():
		var cd: float = max(data.slash_fixed_cooldown, 0.0001)
		_slash_fixed_cd_t = maxf(_slash_fixed_cd_t - frac * cd, 0.0)
	else:
		_refund_heat(frac * data.heat_overheat_threshold)


## 일섬연장(SLASH_EXTEND) — BoonExecutor 가 add_boon 직후 호출(패시브 재계산). 누적 아님(세팅).
func set_slash_extend(range_mult: float, width_mult: float) -> void:
	boon_slash_range_mult = max(1.0, range_mult)
	boon_slash_width_mult = max(1.0, width_mult)


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
		var _tb_jd := _trigger_bus()
		if _tb_jd != null:
			_tb_jd.call("emit", _TriggerBusScript.ON_JUST_DODGE, {"source": self, "position": global_position, "is_perfect": true})
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
## 경험치 자석 반경 배수(중립 base 스탯, 기본 1.0). ExpGem 이 읽으므로 변수는 보존.
var exp_magnet_mult: float = 1.0

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
	# 역수(IAIDO_HASTE) — 대시 거리 가산(런타임 변수, 공유 .tres 미변형).
	_evade_end = global_position + dir * (data.evade_distance + boon_dash_dist_bonus)
	_evade_elapsed = 0.0
	_evade_cd = data.evade_cooldown
	# 스택 1 소비 — 부족해지면 _physics_process 의 charge 리필이 한 칸씩 채운다
	# (한 칸당 evade_refill_time 초).
	_evade_stacks -= 1
	_perfect_dodge_fired = false  # ⏱ fresh evade — re-arm the perfect-dodge reward
	_dash_passed.clear()
	_set_state(State.EVADING)
	var _tb_dash := _trigger_bus()
	if _tb_dash != null:
		_tb_dash.call("emit", _TriggerBusScript.ON_DASH_START, {"source": self, "position": global_position})
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
	# On_Dash_Pass_Enemy 간이 판정 — 회피 중 PC 반경 1.2m 안 적을 관통하면 발행.
	var _tb_pass := _trigger_bus()
	if _tb_pass != null:
		for _e in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(_e) or not (_e is Node3D):
				continue
			var _eid: int = (_e as Node).get_instance_id()
			if _dash_passed.has(_eid):
				continue
			var _ed: Vector3 = (_e as Node3D).global_position - global_position
			_ed.y = 0.0
			if _ed.length() <= 1.2:
				_dash_passed[_eid] = true
				_tb_pass.call("emit", _TriggerBusScript.ON_DASH_PASS_ENEMY, {"source": self, "target": _e, "position": (_e as Node3D).global_position})
	if t >= 1.0:
		_last_evade_end_msec = Time.get_ticks_msec()
		# On_Dash(회피 종료) 발행 — 물귀신 발목잡는손(GRASP_ROOT) 등 발밑 광역 트리거.
		var _tb_de := _trigger_bus()
		if _tb_de != null:
			_tb_de.call("emit", _TriggerBusScript.ON_DASH, {"source": self, "position": global_position})
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
	# 안전망 — 만약 대시 도중 사망 경로로 빠지면 레이어가 0 으로 남지 않게 복원.
	collision_layer = _collision_layer_default
	# Tell Main FIRST so GameOverScreen + SaveSystem fire with the PC
	# node still alive (Main reads kill count / level off live state).
	# The 0.5s death tween runs in parallel — the screen pops up while
	# the sprite is still fading, which reads as a clean transition.
	died.emit()
	if _sprite_rig != null:
		_sprite_rig.play_death_then_free(self, 0.5)
	else:
		queue_free()


## 주술사 장판(SorcererZone)이 PC 가 장판 안에 있는 동안 매 프레임 호출 — 이동 감속.
## 짧은 duration 으로 갱신만 하므로 장판을 벗어나면 곧 풀린다(자연 만료).
func apply_zone_slow(duration: float, mult: float) -> void:
	_zone_slow_t = maxf(_zone_slow_t, duration)
	_zone_slow_mult = clampf(mult, 0.1, 1.0)


# ══════════════ 4안 — 일섬 게이지 ══════════════

## Add to the slash gauge (×gain mult), clamped to max. Called from Main
## on kill / gem pickup and from take_hit on perfect dodge.
func add_slash_gauge(amount: float) -> void:
	# 일섬 단일 모드는 일섬 게이지를 쓰지 않는다(자원=열기/쿨다운) — 처치/젬/저스트
	# 회피와 무관. _instant_slash 가 항상 참이라 항상 no-op(게터 호환 위해 변수 보존).
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

func _trigger_bus() -> Node:
	return get_node_or_null("/root/TriggerBus")

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


## 권속 은혜 장착 — BoonSystem 조회 + 등급 params 해석해 active_boons 등록. BoonExecutor 가 구독 콜백에서 읽음.
func add_boon(id: String, rarity: String) -> void:
	var b = _BoonSystemScript.by_id(id)
	if b == null:
		return
	var comps = b.get("components", [])
	var params: Dictionary = _BoonSystemScript.params_for(id, rarity, 0)
	active_boons.append({"id": id, "rarity": rarity, "components": comps, "params": params})
	# 패시브(SLASH_EXTEND 등) 효과 재계산 — BoonExecutor 가 active_boons 스캔해 런타임 보너스 갱신.
	if _boon_executor != null and is_instance_valid(_boon_executor) and _boon_executor.has_method("refresh_passives"):
		_boon_executor.call("refresh_passives")
	# M9-S10 연격류 — active_boons 스캔해 _nuki_active + 연타 params 재계산(보유 시에만 윈도우 동작).
	_nuki_refresh_from_boons()
	# M9-S11 충전류 — active_boons 스캔해 _charge_active + 충전 params 재계산(보유 시에만 차징 경로 강제).
	_charge_refresh_from_boons()


## M9-S10 — active_boons 를 스캔해 연격류 런타임 상태를 재계산한다.
## STYLE_NUKI 보유 시에만 _nuki_active=true(연타 윈도우 게이트). 각 연격 카드 params 를 런타임 변수로 흡수.
## ★전부 런타임 변수만 갱신(공유 .tres 미변형). add_boon 마다 호출 — 중복 보유는 더 강한 값(max) 채택.
func _nuki_refresh_from_boons() -> void:
	# ★기본값으로 리셋 후 보유 카드로 다시 누적한다. add_boon 마다 active_boons 전체를 재스캔하므로,
	#   여기서 리셋하지 않으면 NUKI_COMBO_EXT 의 '+=' 가산이 매 픽마다 중복 누적된다(상한 폭증 버그).
	#   런마다 _ready 가 별도로 0/false 로 리셋(여긴 인게임 재계산용 베이스).
	_nuki_window_base = 0.32
	_nuki_max = 3
	_nuki_sweet_frac = 0.4
	_nuki_retap_charge_frac = 0.7
	_nuki_accel_has = false
	_nuki_accel_haste = 0.0
	_nuki_accel_dash = 0.0
	_nuki_accel_max_tier = 0
	_nuki_rhythm_has = false
	_nuki_rhythm_need = 3
	_nuki_rhythm_window_bonus = 0.0
	_nuki_rhythm_settle_mult = 1.0
	_nuki_settle_has = false
	_nuki_cadence_has = false
	_nuki_cadence_kills_need = 2
	var has_style := false
	for boon in active_boons:
		if not (boon is Dictionary):
			continue
		var comps = boon.get("components", [])
		if not (comps is Array):
			continue
		var p: Dictionary = boon.get("params", {})
		if not (p is Dictionary):
			p = {}
		for comp in comps:
			if not (comp is Dictionary):
				continue
			match String(comp.get("effect", "")):
				"STYLE_NUKI":
					has_style = true
					_nuki_window_base = max(0.1, float(p.get("nuki_window", _nuki_window_base)))
					_nuki_max = max(_nuki_max, int(p.get("nuki_max", _nuki_max)))
					_nuki_sweet_frac = clampf(float(p.get("sweet_frac", _nuki_sweet_frac)), 0.05, 0.9)
					_nuki_retap_charge_frac = clampf(float(p.get("retap_charge_frac", _nuki_retap_charge_frac)), 0.1, 1.0)
				"NUKI_COMBO_EXT":
					_nuki_max += max(0, int(p.get("max_bonus", 0)))
				"NUKI_ACCEL":
					_nuki_accel_has = true
					_nuki_accel_haste = max(_nuki_accel_haste, float(p.get("haste_pct", 0.0)))
					_nuki_accel_dash = max(_nuki_accel_dash, float(p.get("dash_bonus", 0.0)))
					_nuki_accel_max_tier = max(_nuki_accel_max_tier, int(p.get("max_tier", 2)))
				"NUKI_RHYTHM":
					_nuki_rhythm_has = true
					_nuki_rhythm_need = max(1, int(p.get("need", _nuki_rhythm_need)))
					_nuki_rhythm_window_bonus = max(_nuki_rhythm_window_bonus, float(p.get("window_bonus", 0.0)))
					_nuki_rhythm_settle_mult = max(_nuki_rhythm_settle_mult, float(p.get("settle_mult", 1.0)))
				"NUKI_SETTLE":
					_nuki_settle_has = true
				"NUKI_CADENCE":
					_nuki_cadence_has = true
					_nuki_cadence_kills_need = max(1, int(p.get("kills_need", _nuki_cadence_kills_need)))
	_nuki_active = has_style


# ══════════════ M9-S11 충전류(STYLE_CHARGE) — LB 충전→풀차지 관통 control mechanic ══════════════

## 일도양단(STYLE_CHARGE) 보유 시에만 _charge_active=true. true 면 _check_instant_slash 가
## GameConfig.slash_aim_mode 와 무관하게 차징 경로(State.AIMING)를 강제 사용한다.
## ★미보유(납도/연격/무스타일)면 _charge_active=false → 기존 일섬/연타 경로 그대로(회귀 0).
## ★_nuki_active 와 상호배타(둘 다 kind='style' 게이트 — 한 판 1 style 카드).
## 모든 충전류 분기는 if _charge_active 가드. 전부 런타임 변수(_ready 리셋, 공유 .tres 미변형).
func _charge_refresh_from_boons() -> void:
	# 기본값 리셋 후 보유 카드로 재누적(add_boon 마다 active_boons 전체 재스캔 — 중복 누적 방지).
	_charge_tier_lo = 0.4
	_charge_tier_hi = 0.85
	_charge_pierce_range_mult = 1.0
	_charge_pierce_width_mult = 1.0
	_charge_dash_speed_mult = 1.0
	_charge_mark_depth_base = 1
	_charge_mark_depth_per_tier = 0
	_charge_haste_mult = 0.0
	_charge_perfect_has = false
	_charge_perfect_window = 0.0
	_charge_dash_cancel_has = false
	_charge_dash_cancel_haste = 0.0
	_charge_dash_cancel_dash = 0.0
	var has_style := false
	for boon in active_boons:
		if not (boon is Dictionary):
			continue
		var comps = boon.get("components", [])
		if not (comps is Array):
			continue
		var p: Dictionary = boon.get("params", {})
		if not (p is Dictionary):
			p = {}
		for comp in comps:
			if not (comp is Dictionary):
				continue
			match String(comp.get("effect", "")):
				"STYLE_CHARGE":
					has_style = true
					_charge_tier_lo = clampf(float(p.get("tier_lo", _charge_tier_lo)), 0.05, 0.9)
					_charge_tier_hi = clampf(float(p.get("tier_hi", _charge_tier_hi)), _charge_tier_lo + 0.05, 0.99)
					_charge_pierce_range_mult = max(_charge_pierce_range_mult, float(p.get("pierce_range_mult", 1.0)))
					_charge_pierce_width_mult = max(_charge_pierce_width_mult, float(p.get("pierce_width_mult", 1.0)))
					_charge_dash_speed_mult = max(_charge_dash_speed_mult, float(p.get("dash_speed_mult", 1.0)))
					_charge_mark_depth_base = max(_charge_mark_depth_base, int(p.get("mark_depth_base", 1)))
				"CHARGE_HASTE":
					_charge_haste_mult = max(_charge_haste_mult, float(p.get("haste_pct", 0.0)))
				"CHARGE_PERFECT":
					_charge_perfect_has = true
					_charge_perfect_window = max(_charge_perfect_window, float(p.get("window", 0.0)))
					_charge_pierce_range_mult = max(_charge_pierce_range_mult, float(p.get("range_mult", 1.0)))
					_charge_mark_depth_per_tier += 1  # 퍼펙트 보유 시 티어당 표식 깊이 +1.
				"DEEP_CHARGE_MARK":
					_charge_mark_depth_per_tier += max(0, int(p.get("per_tier", 1)))
				"CHARGE_DASH_CANCEL":
					_charge_dash_cancel_has = true
					_charge_dash_cancel_haste = max(_charge_dash_cancel_haste, float(p.get("haste_pct", 0.0)))
					_charge_dash_cancel_dash = max(_charge_dash_cancel_dash, float(p.get("dash_bonus", 0.0)))
				# SLASH_EXTEND 는 refresh_passives(BoonExecutor) 가 set_slash_extend 로 처리 — 여기 불필요.
				# CHARGE_ALIGN/AFTERGLOW/PIERCE_REAP/THUNDER 는 BoonExecutor 에서 처리.
	_charge_active = has_style


## M9-S11 충전류 getter — HUD/디버그용(차징 UI/AimArrow 가 메인, 라벨은 최소).
func is_charge_active() -> bool:
	return _charge_active

## 현재 차징 프랙(0~1). AIMING 이 아니면 0.
func get_charge_frac() -> float:
	if _state != State.AIMING:
		return 0.0
	return clampf(_charge_t / max(data.max_charge_time, 0.0001), 0.0, 1.0)

## 현재 충전 티어(0=약·1=중·2=풀). AIMING 이 아니면 0.
func get_charge_tier() -> int:
	if _state != State.AIMING:
		return 0
	var f: float = get_charge_frac()
	if f < _charge_tier_lo:
		return 0
	if f < _charge_tier_hi:
		return 1
	return 2


## 발도회천(CHARGE_DASH_CANCEL) — 차징(AIMING) 중 회피 입력이면 차지를 버리고 회피한다.
## 회피 시작이 성공하면 재차지 가속(apply_iaido_haste 재사용)을 켜고 true 반환(이번 프레임 _update_aim/release 스킵).
## ★카드 미보유면 항상 false(회귀 0). 회피 시작 게이트(_check_evade_start)가 쿨/스택을 검사하므로
##   여기선 입력만 보고 실제 회피는 _check_evade_start 에 위임 — 회피가 못 시작되면 차징 유지.
func _check_charge_dash_cancel() -> bool:
	if not _charge_dash_cancel_has:
		return false
	if not Input.is_action_just_pressed("dash"):
		return false
	# 쿨/스택 부족이면 회피 못 함 → 차징 유지(false).
	if _evade_cd > 0.0 or _evade_stacks <= 0:
		return false
	# 차지 버림 — AIMING 상태/차지 타이머 정리 후 회피 시작.
	_charge_t = 0.0
	_overcharge_t = 0.0
	_charge_pending_mark_depth = 0
	if _aim_arrow != null:
		_aim_arrow.hide_arrow()
	if _sprite_rig != null and _sprite_rig.has_method("set_charge_glow"):
		_sprite_rig.call("set_charge_glow", false)
	var rig := get_tree().get_first_node_in_group("camera_rig")
	if rig != null and rig.has_method("set_charge_zoom"):
		rig.call("set_charge_zoom", false)
	_set_state(State.IDLE)  # _check_evade_start 가 EVADING 으로 전환.
	_check_evade_start()
	# 재차지 가속 + 대시 거리 가산(역수 윈도우 재사용 — 다음 일섬 발사 시 소멸).
	apply_iaido_haste(_charge_dash_cancel_haste, _charge_dash_cancel_dash)
	return _state == State.EVADING
