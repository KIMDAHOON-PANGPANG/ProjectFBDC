class_name MonsterCollision
extends RefCounted

## Shared collision sizing standard for every monster type.
##
## Single source of truth for the "monster hitbox is X% smaller than the
## visual" policy. Every enemy scene (MeleeEnemy / RangedEnemy / EliteEnemy
## / Boss) has its CollisionShape3D pre-baked with a base size; this module
## documents the agreed-upon scale and offers helpers to apply it at
## runtime if a future enemy wants to size dynamically.
##
## Why a module instead of just constants in .tscn:
##   - One place to bump the policy when balance shifts.
##   - Helpers let a future Boss variant scale procedurally (e.g. boss
##     phase-2 grows the hitbox by 10%) without rewriting all scenes.

## Global hitbox shrink relative to the visual silhouette. 0.7 = 30% smaller.
## Lowered from the original 1.0 to give the player breathing room when
## weaving between mobs in a packed crowd.
const HITBOX_SCALE: float = 0.7

## Apply HITBOX_SCALE to a CapsuleShape3D given base (un-scaled) dimensions.
static func apply_capsule(shape: CapsuleShape3D, base_radius: float, base_height: float) -> void:
	if shape == null:
		return
	shape.radius = base_radius * HITBOX_SCALE
	shape.height = base_height * HITBOX_SCALE

## Apply HITBOX_SCALE to a BoxShape3D given a base size vector.
static func apply_box(shape: BoxShape3D, base_size: Vector3) -> void:
	if shape == null:
		return
	shape.size = base_size * HITBOX_SCALE
