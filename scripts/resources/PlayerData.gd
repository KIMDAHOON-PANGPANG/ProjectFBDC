class_name PlayerData
extends Resource

## Player tunables - swap a resource for fast iteration.

@export var move_speed: float = 5.0
## 자연수 HP — 근접 일반 몹 공격력(1)의 10배. 피격마다 공격력만큼 감소. 레벨업 "강건"으로 +1.
@export var max_hp: int = 10

## --- Iaijutsu Slash tunables ---
## Time (sec) the dash takes from start to end.
@export var dash_duration: float = 0.12

## Minimum / maximum slash distance based on charge time.
@export var min_slash_range: float = 3.0
@export var max_slash_range: float = 11.0

## Time (sec) of holding LMB to reach max_slash_range.
## Tuned 20% snappier from the original 0.9s — the bar reaches max
## reach noticeably sooner, which improves the feel of "tap-and-go"
## short slashes without changing the max-range commitment.
@export var max_charge_time: float = 0.72

## 일섬 충전(공격 길이) 속도 배수. 1.0 = 기본, 0.5 = 50% 느림(요청 기본값).
## `_update_aim` 에서 _charge_t 누적(delta)에 곱한다 — 작을수록 길이가 천천히 차오른다.
## 실제 풀차징 시간 = max_charge_time / charge_speed_mult (예: 0.72 / 0.5 = 1.44s).
## LB 롱프레스(모드2 즉발 일섬) · RB 차징(모드1) 양쪽 충전에 공통 적용.
@export var charge_speed_mult: float = 0.5

## Width of the slash hitbox along the path (in world units).
@export var slash_width: float = 1.4

## Lifetime of the slash hit-trail (sec). Enemies inside during this window die.
@export var slash_hit_lifetime: float = 0.18

## Cooldown after a slash, in seconds. 0 = no cooldown.
@export var slash_cooldown: float = 0.15

## D-3 — 일섬 자원 방식 "쿨다운"(GameConfig.slash_resource_mode==1) 전용 재발사 쿨다운(초).
## 열기(Heat) 시스템을 완전히 대체하는 고정 쿨다운으로, 이 동안 LB 일섬이 막힌다.
## 미세 post-slash 락(slash_cooldown 0.15~0.3)과 별개의 "발사 자원" 쿨이라 1.2~1.5s 권장.
## PlayerHud 의 열기 5스택 UI 가 이 쿨의 차오름(0→1, 1=발사가능)을 표시한다.
@export var slash_fixed_cooldown: float = 1.3

# ── 일섬 돌진/범위 (기획 튜닝) ──
## 돌진 속도 (m/s) — 일섬 대시가 1초에 전진하는 거리. 기획 친화 단위.
## 캐릭터 이동(5 m/s) 대비 거합 대시는 보통 40~80. 대시 시간 = 거리 ÷ 속도라
## 거리가 멀어도 체감 속도가 일정하다. (dash_duration 은 폴백으로만 남김)
@export var slash_dash_speed: float = 55.0
## 모드2(게임 시작 2) 일섬의 풀차지 사거리 (m). 차징 0→1 에 따라 min_slash_range
## ~ 이 값으로 늘어난다(AimArrow 가 시각화). 모드1 의 max_slash_range 와 독립.
@export var instant_slash_distance: float = 5.5
## 모드2 — 최대 차지 도달 후 자동 발사까지 버틸 수 있는 오버차지 시간(초).
## 이 안에 버튼을 떼면 그때 발사, 넘기면 강제 발사된다(모드1 fizzle 과 달리 불발 아님).
@export var instant_overcharge_hold: float = 2.0
## 일섬 타격 범위 (m) — x=폭(좌우), y=높이(상하), z=전방 길이 가산(돌진 거리에
## 더해지는 추가 판정 길이; 0 이면 돌진 경로 그대로). 박스 판정 크기.
@export var slash_hit_extents: Vector3 = Vector3(1.4, 1.0, 0.0)
## 일섬 대시 시 카메라가 "공격과 함께 같이 이동"하도록 — follow_boost(시간, 배수).
## HD2DCamera follow_speed_xz 에 배수(>1)를 곱해 대시 동안 PC 에 바짝 붙여 함께
## 움직인다(공격 후 따라붙는 느낌이 아니라 공격 중 이동감). mult↑ 일수록 더 밀착.
@export var slash_cam_follow_time: float = 0.25
@export var slash_cam_follow_mult: float = 3.0

# ── 접촉 피해 (게임 시작2 전용) ──
# 모드2 는 PC 레이어를 비워 NPC 와 서로 밀리지 않는다(Player._ready). 대신 NPC 몸에
# 닿으면 아래 값으로 HP 가 깎여 "닿으면 아프다"는 위협을 만든다.
@export_group("Contact Damage (게임 시작2)")
## NPC 몸과 접촉 시 HP 감소량. 피격 iframe(hit_iframe)이 연속 피해 쿨다운 역할.
@export var contact_damage: int = 1
## 접촉 판정 반경(m, PC 중심↔적 중심). PC 캡슐(≈0.5) + 적 캡슐 근사.
@export var contact_radius: float = 0.95

@export_group("Evade Dash")
## Distance covered by a Shift-dash, in world units. (CSV: evade_distance)
@export var evade_distance: float = 2.5
## Time to traverse the dash distance (seconds).
@export var evade_duration: float = 0.18
## 연속 대시 사이 최소 간격(초) — 스택이 남아도 이만큼 텀을 둔다. (CSV: evade_cooldown)
@export var evade_cooldown: float = 0.25
## 회피 스택 수(연속으로 쓸 수 있는 대시 횟수). (CSV: evade_max_stacks)
@export var evade_max_stacks: int = 2
## 스택을 전부 소진하면 가득(=max) 차기까지 걸리는 시간(초). (CSV: evade_refill_time)
@export var evade_refill_time: float = 5.0

# ── M8 — 근접 기본 공격(부채꼴 스윙) 제거됨 ──
# 컨트롤이 LB=일섬 단일로 통합되며 melee_range/angle/cooldown/damage/shake/hitstop
# @export 와 Player 의 _do_melee_swing 경로가 전면 삭제됐다.

# ── 4안 — 일섬 게이지 ──
@export_group("Slash Gauge (일섬)")
## Gauge fills to this; slash only fires at full, then resets to 0.
@export var slash_gauge_max: float = 100.0
## Gauge gained per kill / gem pickup / perfect dodge. Tuned so ~30s of
## play earns one slash.
@export var slash_gauge_on_kill: float = 4.0
@export var slash_gauge_on_gem: float = 2.0
@export var slash_gauge_on_perfect_dodge: float = 20.0

# ── 4안 — 전투 상수 이관 (Player.gd const → 데이터) ──
# CombatData(pc_combat.json) 가 이 값들을 덮어쓴다. 기본값은 기존 코드 상수와
# 동일하므로 JSON/로더가 없어도 동작 불변.
@export_group("Combat Tuning (이관)")
## 피격 후 무적 시간(초). 요청: 1초. 이 동안 플래시 머티리얼 깜빡임으로 무적 표시.
@export var hit_iframe: float = 1.0
## 레벨업 시 부여되는 무적 시간(초). 일시정지 중엔 안 닳아 카드 고르고 재개하면 이만큼 무적.
@export var levelup_iframe: float = 1.0
## 일섬(대시) 직후 짧은 회복 무적(초) — 착지 지점에서 적 충돌/탄에 즉시 피격되는
## 불쾌감을 막는다. is_invincible 에 포함(접촉피해/피탄 공통). 0 = 끔.
@export var slash_post_grace: float = 0.4
## 일섬 직후 도착 지점 가시성 — 카메라를 잠깐 뒤로 빼(줌아웃) 착지 주변을 넓게 보여준다.
## scale=거리 배수(>1, 1.18=18% 줌아웃), time=유지 시간(초). HD2DCamera.zoom_punch.
@export var slash_cam_zoom_scale: float = 1.18
@export var slash_cam_zoom_time: float = 0.45
## 피격/피탄 넉백 — 반경(AOE) / 최대 밀침 속도(유닛/초). 적의 Knockback 컴포넌트가
## 이 속도로 밀려난 뒤 부드럽게(스무스) 감쇠하며 멈춘다. (예전: 즉시 위치 이동)
@export var knockback_radius: float = 4.0
@export var knockback_force: float = 12.0
## 저스트 회피 판정 창(초). 기존 Player.PERFECT_DODGE_WINDOW.
@export var perfect_dodge_window: float = 0.12
## 오버차지 유예 / 불발 잠금(초). 기존 Player.OVERCHARGE_GRACE / OVERCHARGE_LOCKOUT.
@export var overcharge_grace: float = 0.45
@export var overcharge_lockout: float = 1.0
## 퍼펙트 차징 판정 비율(0~1). 기존 _fire_slash 의 0.9 리터럴.
@export var perfect_charge_threshold: float = 0.9
## 일섬이 보스에게 주는 데미지(일반). 젠/패리 보정은 M8 S3a 에서 제거됨.
@export var boss_slash_damage_normal: int = 1
## 일섬이 잡몹(다중타 몹)에 주는 기본 데미지(자연수). 몹 HP 스케일과 함께 밸런싱한다.
## 보스는 위 boss_slash_damage_normal 로 별도. 발사체 격추는 원샷(데미지 무관).
## player_data.tres 가 이 값을 set 하지 않으면 기본값(2)을 사용한다(고아 속성 없음).
@export var slash_base_damage: int = 2

# ── 열관리(Heat) — "게임 시작 2"(즉발 일섬) 모드 전용. 럼블 열관리 게이지식. ──
# 일섬(평타)마다 열이 오르고, 직전 일섬 후 combo_window 초 이내면 combo_mult
# 배 더 오른다. 100% 도달 시 overheat_duration 초 탈진(이동 감소 + 발사 봉인),
# 끝나면 0 으로. 마지막 일섬 후 decay_delay 초가 지나면 지수적으로 식는다.
@export_group("Heat (즉발 일섬 열관리)")
## 일섬 1발당 기본 열 획득(%). 첫발 10 + 연타 15×6 = 7발째 정확히 100%.
@export var heat_gain_base: float = 10.0
## 직전 일섬 후 이 시간(초) 이내에 또 쏘면 연타로 간주 → combo_mult 적용.
@export var heat_combo_window: float = 7.0
## 연타 시 열 획득 배수(1.5 = +50%).
@export var heat_combo_mult: float = 1.5
## 탈진 임계(%) — 이 값에 닿으면 탈진.
@export var heat_overheat_threshold: float = 100.0
## 탈진 지속(초). 이 동안 이동 감소 + 일섬 발사 불가, 끝나면 열 0.
@export var heat_overheat_duration: float = 5.0
## 탈진 중 이동속도 배수(0.5 = 50% 감소).
@export var heat_overheat_move_mult: float = 0.5
## 마지막 일섬 후 열이 식기 시작하기까지의 유예(초).
@export var heat_decay_delay: float = 4.0
## 지수 감소 계수 k (per second). H *= e^(-k·dt). 클수록 빨리 식음.
@export var heat_decay_rate: float = 1.0

# ── 레벨업 넉백 (Level-up Pushback) — 카드 선택 직후 자기 중심 원형으로 적을
# 약하게 밀어낸다(피해 없음). ──
@export_group("Level-up Pushback (레벨업 원형 넉백)")
## 밀어내는 반경(m).
@export var levelup_push_radius: float = 5.0
## 넉백 속도(유닛/초). 약하게(요청) — 적 Knockback 이 이 속도로 밀렸다 감쇠.
@export var levelup_push_speed: float = 6.0

@export var visuals: CharacterVisuals
