class_name SpriteRig
extends Node3D

## Sprite3D wrapper for HD-2D characters.
## Applies a CharacterVisuals resource (sprite textures + pixel size).
## Handles state-driven texture swaps and horizontal flipping by facing.

enum State { IDLE, WALK, ATTACK, HURT, DEATH }

@export var sprite_3d_path: NodePath
@export var visuals: CharacterVisuals
@export var fallback_color: Color = Color(0.85, 0.85, 0.85)

var _sprite: Sprite3D
var _state: int = State.IDLE
var _facing_right: bool = true
# Cached resting modulate so flash() can always tween back to the same base
# regardless of whether a previous flash tween is still in flight.
var _base_modulate: Color = Color.WHITE
# Currently-running blink tween, so a new hit can cancel it cleanly.
var _blink_tween: Tween

func _ready() -> void:
	if sprite_3d_path.is_empty():
		_sprite = _find_sprite()
	else:
		_sprite = get_node(sprite_3d_path) as Sprite3D
	if _sprite == null:
		return
	_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_sprite.shaded = false
	# Why transparent=true here: opaque + ALPHA_CUT_DISCARD is cheaper, but on
	# d3d12 backends some imported pixel-art textures end up rendering their
	# fully-transparent RGB as opaque white. Enabling the transparent pass
	# guarantees alpha is honoured regardless of import-time channel handling.
	_sprite.transparent = true
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_sprite.alpha_scissor_threshold = 0.5
	_sprite.no_depth_test = false
	_sprite.double_sided = false
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_apply_visuals()
	_state = -1  # force first refresh
	set_state(State.IDLE)

func set_visuals(v: CharacterVisuals) -> void:
	visuals = v
	_apply_visuals()
	_refresh_texture()

func _apply_visuals() -> void:
	if _sprite == null:
		return
	if visuals != null:
		_sprite.pixel_size = visuals.pixel_size
		_sprite.modulate = visuals.placeholder_tint
	else:
		_sprite.pixel_size = 0.02
		_sprite.modulate = Color.WHITE
	_base_modulate = _sprite.modulate

func _find_sprite() -> Sprite3D:
	for child in get_children():
		if child is Sprite3D:
			return child
	return null

func set_state(s: int) -> void:
	if _state == s:
		return
	_state = s
	_refresh_texture()

func set_facing(dir_x: float) -> void:
	if visuals != null and not visuals.flip_h_on_facing:
		return
	if abs(dir_x) < 0.01:
		return
	_facing_right = dir_x > 0.0
	if _sprite != null:
		var art_faces_right: bool = visuals == null or visuals.default_facing_right
		# When the source PNG already faces right, "facing right" = no flip.
		# When the source PNG faces left, invert so the visible direction
		# matches movement.
		_sprite.flip_h = (not _facing_right) if art_faces_right else _facing_right

func _refresh_texture() -> void:
	if _sprite == null:
		return
	var tex: Texture2D = null
	if visuals != null:
		match _state:
			State.IDLE: tex = visuals.idle
			State.WALK: tex = visuals.walk if visuals.walk else visuals.idle
			State.ATTACK: tex = visuals.attack if visuals.attack else visuals.idle
			State.HURT: tex = visuals.hurt if visuals.hurt else visuals.idle
			State.DEATH: tex = visuals.death if visuals.death else visuals.idle
	if tex == null:
		tex = PlaceholderSprite.make(fallback_color)
	_sprite.texture = tex

## Brief over-bright flash on the sprite to telegraph a hit. Caller decides
## the duration — typical hit feedback is ~0.16s total.
## Implementation: tween modulate up to a super-white, then back to the
## cached `_base_modulate`. Always restoring to the cached resting tint
## means overlapping flashes don't drift the sprite brighter and brighter.
func flash(duration: float = 0.16) -> void:
	if _sprite == null:
		return
	var bright: Color = Color(3.0, 3.0, 3.0, _base_modulate.a)
	var t := create_tween()
	t.tween_property(_sprite, "modulate", bright, duration * 0.2)
	t.tween_property(_sprite, "modulate", _base_modulate, duration * 0.8)

## Strobe the sprite for the duration to visualise an active i-frame.
## Alternates between a BRIGHT over-bright modulate (opaque) and an
## INVISIBLE state (modulate alpha = 0, which is below the sprite's
## ALPHA_CUT_DISCARD threshold so the whole sprite drops out).
##
## Using alpha-toggle on top of brightness gives a strong, unmistakeable
## "I'm invincible" read — this replaces the over-bright-only flash, which
## was nearly invisible because Sprite3D modulate channels >1.0 get
## clamped at presentation time and the PC's resting tint is already
## close to white.
##
## Cancels any in-flight blink so back-to-back hits don't compound.
func start_iframe_blink(duration: float = 1.0) -> void:
	if _sprite == null:
		return
	if _blink_tween != null and _blink_tween.is_valid():
		_blink_tween.kill()
	# Bright "on" phase — over-bright + fully opaque. Reads as a flash.
	var bright: Color = Color(2.5, 2.5, 2.5, 1.0)
	# Invisible "off" phase — alpha 0 falls below the sprite's scissor
	# threshold (0.5) and the whole sprite gets discarded for that frame.
	var invisible: Color = Color(_base_modulate.r, _base_modulate.g, _base_modulate.b, 0.0)
	var half_cycle: float = 0.08
	var cycles: int = max(int(duration / (half_cycle * 2.0)), 1)
	_blink_tween = create_tween()
	for i in cycles:
		_blink_tween.tween_property(_sprite, "modulate", bright, half_cycle)
		_blink_tween.tween_property(_sprite, "modulate", invisible, half_cycle)
	# Hard restore at the end — guarantees the PC is visible after.
	_blink_tween.tween_callback(_restore_base_modulate)

func _restore_base_modulate() -> void:
	if _sprite != null:
		_sprite.modulate = _base_modulate

func play_death_then_free(parent_to_free: Node, duration: float = 0.45) -> void:
	set_state(State.DEATH)
	if _sprite == null:
		parent_to_free.queue_free()
		return
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(_sprite, "modulate:a", 0.0, duration)
	t.tween_property(self, "position:y", position.y + 0.6, duration)
	t.tween_property(self, "rotation:z", deg_to_rad(35.0 if _facing_right else -35.0), duration)
	t.chain().tween_callback(parent_to_free.queue_free)
