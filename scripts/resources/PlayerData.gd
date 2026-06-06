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

@export var visuals: CharacterVisuals
