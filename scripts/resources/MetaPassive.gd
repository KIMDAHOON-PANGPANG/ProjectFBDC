class_name MetaPassive
extends Resource

## A permanent meta upgrade purchased with 혼(souls) between runs. Lives
## as one `.tres` per upgrade under `resources/meta/passives/`.
## `MetaProgressionSystem` loads them all on first access and applies any
## non-zero level to the PC at the start of a run.
##
## Cost curve is linear-per-level: cost(level) = cost_base * (level + 1).
## Effect is multiplied by the player's current level in that passive:
## a "+5% slash width per level" with level 3 applies a flat +15%.

## Stable ID used for save lookup. NEVER rename — that's the breaking
## change for existing save files.
@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var max_level: int = 5

## Cost of buying the 1st level. cost_at(level) = cost_base * (level + 1).
@export var cost_base: int = 5

## How `MetaProgressionSystem._apply_effect` interprets `effect_per_level`.
## Recognised kinds (M4 1차):
##   "hp"             — flat HP +N
##   "move_speed"     — multiplier (1.0 + N) on PlayerData.move_speed
##   "slash_width"    — multiplier (1.0 + N) on slash_width
##   "exp_gain"       — multiplier (1.0 + N) on ExpSystem.gain_multiplier
##   "evade_cooldown" — multiplier (1.0 - N) on evade_cooldown (cap floored
##                     inside _apply_effect)
##   "iframe_extra"   — flat seconds added to Player.HIT_IFRAME usage
## Stubbed (defined here, no apply yet — slated for M4 후속):
##   "free_card"      — N free card picks at run start
@export var effect_kind: String = ""

## Numeric value applied per level. Magnitude depends on effect_kind:
## - "hp"             → integer (rounded). e.g. 1.0 = +1 HP per level.
## - multiplier kinds → fractional. e.g. 0.05 = +5% per level.
## - "iframe_extra"   → seconds. e.g. 0.1 = +0.1s per level.
@export var effect_per_level: float = 1.0


## Cost to advance FROM `current_level` to `current_level + 1`. Bound to
## max_level by `MetaProgressionSystem.can_upgrade`.
func cost_at(current_level: int) -> int:
	return cost_base * (current_level + 1)
