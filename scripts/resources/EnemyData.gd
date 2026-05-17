class_name EnemyData
extends Resource

## Per-enemy tunables. Swap a resource file in the inspector to retune
## an enemy without touching code.

enum EnemyType { MELEE, RANGED }

@export var type: EnemyType = EnemyType.MELEE
@export var max_hp: int = 1
@export var move_speed: float = 2.5

## Distance at which the enemy starts engaging the player.
@export var detection_range: float = 14.0

## --- Melee tunables ---
@export var melee_attack_range: float = 1.2
@export var melee_attack_cooldown: float = 1.0

## --- Ranged tunables ---
@export var ranged_attack_range: float = 8.0
@export var ranged_attack_cooldown: float = 1.6
## Preferred stand-off distance from the player.
@export var ranged_keep_distance: float = 6.0
@export var arrow_speed: float = 13.2  # 20% faster than legacy 11.0 baseline.
@export var arrow_scene: PackedScene

## Visuals resource for sprite swapping.
@export var visuals: CharacterVisuals
