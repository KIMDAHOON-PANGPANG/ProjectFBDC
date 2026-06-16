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
## 피격 후 무적 시간(초). 기존 Player.HIT_IFRAME.
@export var hit_iframe: float = 0.5
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

@export var visuals: CharacterVisuals
