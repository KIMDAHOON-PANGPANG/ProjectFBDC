class_name CharacterVisuals
extends Resource

## Holds swappable sprite textures for a character.
## Drop this resource on any unit; swap any texture in the inspector and
## the unit picks it up at runtime without code changes.

@export var idle: Texture2D
@export var walk: Texture2D
@export var attack: Texture2D
@export var death: Texture2D
@export var hurt: Texture2D

## Pixel size for the Sprite3D (smaller = sharper at HD-2D distance).
@export var pixel_size: float = 0.02

## Default tint applied to placeholder textures when no sprite is set.
@export var placeholder_tint: Color = Color.WHITE

## When true, sprite flips horizontally based on facing direction.
@export var flip_h_on_facing: bool = true

## Direction the source PNG art is drawn facing. When false, SpriteRig inverts
## the flip so the sprite faces movement direction correctly.
@export var default_facing_right: bool = true
