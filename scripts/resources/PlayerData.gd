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

@export_group("Evade Dash")
## Distance covered by a Shift-dash, in world units.
@export var evade_distance: float = 3.5
## Time to traverse the dash distance (seconds).
@export var evade_duration: float = 0.18
## Cooldown between dashes (seconds).
@export var evade_cooldown: float = 0.7

# ── 4안 — 비도(Kunai) 기본 공격 ──
@export_group("Kunai (기본 공격)")
## Ammo per magazine. Empties → auto-reload.
@export var max_ammo: int = 5
## Reload duration (sec) once the magazine empties.
@export var reload_time: float = 1.5
## Min interval between shots (sec).
@export var fire_cooldown: float = 0.25
## Damage per kunai (raised by the "예리한 비도" level-up).
@export var kunai_damage: int = 1
## Projectile speed (units/sec).
@export var kunai_speed: float = 20.0
## Kunai despawn time (sec).
@export var kunai_lifetime: float = 1.5
## Auto-aim lock-on radius (units). SPACE toggles auto-aim; the nearest
## enemy inside this circle is targeted (ties broken randomly).
@export var autoaim_radius: float = 12.0

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
## 피격 넉백 반경 / 세기. 기존 Player.KNOCKBACK_RADIUS / KNOCKBACK_FORCE.
@export var knockback_radius: float = 4.0
@export var knockback_force: float = 5.0
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

@export var visuals: CharacterVisuals
