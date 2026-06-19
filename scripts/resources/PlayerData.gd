class_name PlayerData
extends Resource

## Player tunables - swap a resource for fast iteration.

@export var move_speed: float = 5.0
## 4안 — 칸 단위 HP. 초기 3칸. 레벨업 "강건"으로 +1.
@export var max_hp: int = 3

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

# ── 일섬 돌진/범위 (기획 튜닝) ──
## 돌진 속도 (m/s) — 일섬 대시가 1초에 전진하는 거리. 기획 친화 단위.
## 캐릭터 이동(5 m/s) 대비 거합 대시는 보통 40~80. 대시 시간 = 거리 ÷ 속도라
## 거리가 멀어도 체감 속도가 일정하다. (dash_duration 은 폴백으로만 남김)
@export var slash_dash_speed: float = 55.0
## 모드2(게임 시작 2) 일섬의 풀차지 사거리 (m). 차징 0→1 에 따라 min_slash_range
## ~ 이 값으로 늘어난다(AimArrow 가 시각화). 모드1 의 max_slash_range 와 독립.
@export var instant_slash_distance: float = 11.0
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

# ── 4안 — 비도(Kunai) 기본 공격 ──
@export_group("Kunai (기본 공격)")
## Ammo per magazine. Empties → auto-reload.
@export var max_ammo: int = 5
## Reload duration (sec) once the magazine empties.
@export var reload_time: float = 1.5
## Min interval between shots (sec).
@export var fire_cooldown: float = 0.25
## 수동 조준 비도 데미지 — 초반 밸런스 기준 잡몹(HP 2) 한 방. (CSV: kunai_damage)
@export var kunai_damage: int = 2
## 자동락온(SPACE ON) 비도 데미지 — 더 낮아 한 방에 안 죽음. (CSV: kunai_autoaim_damage)
@export var kunai_autoaim_damage: int = 1
## 자동락온 시 투사체 속도 배수(더 느림). (CSV: kunai_autoaim_speed_mult)
@export var kunai_autoaim_speed_mult: float = 0.6
## Projectile speed (units/sec). (CSV: kunai_speed)
@export var kunai_speed: float = 6.5
## 비도 피탄 시 적이 밀려나는 속도(유닛/초, 스무스 감쇠). (CSV: kunai_knockback)
@export var kunai_knockback: float = 7.0
## Kunai despawn time (sec).
@export var kunai_lifetime: float = 2.0
## Auto-aim lock-on radius (units). SPACE toggles auto-aim; the nearest
## enemy inside this circle is targeted (ties broken randomly).
@export var autoaim_radius: float = 9.0
## 이동 중 발사 시 탄도 분산 각도(±도). 멈춰서 쏘면 분산 없음. (CSV: kunai_move_spread_deg)
@export var kunai_move_spread_deg: float = 8.0
## LB 사격/장전 중 이동속도 배수(0.5 = 50% 감속). 기본 이동 시엔 1.0. (CSV: kunai_fire_move_mult)
## ⚠ 비도(원거리) 제거로 현재 미사용 — 추후 정리 대상.
@export var kunai_fire_move_mult: float = 0.5

# ── 근접 기본 공격 (Death Must Die 식 부채꼴 스윙) — 비도(원거리) 대체 ──
@export_group("Melee (기본 공격)")
## 스윙 사거리(유닛). (CSV: melee_range)
@export var melee_range: float = 2.5
## 부채꼴 각도(도) — 커서 방향 ±angle/2. (CSV: melee_angle_deg)
@export var melee_angle_deg: float = 100.0
## 스윙 간격(초) = 공격 속도(LB 홀드 시 이 간격으로 연속 스윙). (CSV: melee_cooldown)
@export var melee_cooldown: float = 0.35
## 스윙당 데미지(잡몹 HP 2 → 2면 한 방). 보스는 패리 없이 칩 데미지. (CSV: melee_damage)
@export var melee_damage: int = 2
## 스윙마다 카메라 미세 흔들림(타격감). amp=세기(유닛, 매우 약하게), dur=시간(초). (CSV: melee_shake_amp/dur)
@export var melee_shake_amp: float = 0.04
@export var melee_shake_dur: float = 0.08
## 적 적중 시 극소량 히트스탑(역경직). scale=느려지는 배수(0~1, 작을수록 강함), dur=시간(초). (CSV: melee_hitstop_scale/dur)
@export var melee_hitstop_scale: float = 0.05
@export var melee_hitstop_dur: float = 0.045

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
## 젠 버스트 일섬 강화 배수. 기존 _fire_slash 의 ×3 / ×1.5 리터럴.
@export var zen_burst_width_mult: float = 3.0
@export var zen_burst_range_mult: float = 1.5
## 일섬이 보스에게 주는 데미지(일반/패리보상/젠버스트). 기존 SlashAttack 의 1/3/5.
@export var boss_slash_damage_normal: int = 1
@export var boss_slash_damage_parry: int = 3
@export var boss_slash_damage_zen: int = 5

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

# ── 마취 비도 (Tranq Dart) — "게임 시작 2" 우클릭(RMB). 곡사로 날아가 착탄 범위
# 안의 적을 스턴(마취)시킨다. 하데스 캐스트(1/1)식 — 쿨다운으로 충전 회복. ──
@export_group("Tranq Dart (마취 비도 · 게임 시작2 RMB)")
## 적 마취(스턴) 지속 시간(초). 범위 내 모든 적이 이 시간만큼 정지.
@export var tranq_stun_duration: float = 3.0
## 재사용 대기(초) — 1/1 충전이 회복되는 시간.
@export var tranq_cooldown: float = 6.0
## 착탄 범위 반경(m) — 이 안의 적이 스턴.
@export var tranq_radius: float = 3.0
## 곡사 사거리(m) — 커서 방향으로 이만큼 떨어진 지점에 떨어진다.
@export var tranq_range: float = 9.0
## 곡사 포물선 정점 높이(m).
@export var tranq_arc_height: float = 3.5
## 비행 시간(초) — 던져서 착탄까지.
@export var tranq_travel_time: float = 0.6

@export var visuals: CharacterVisuals
