class_name PlaceholderSprite
extends RefCounted

## Generates a simple greybox sprite at runtime.
## Replace real sprites by setting CharacterVisuals.idle / etc. in the inspector
## or via .tres resources -- this helper is only used when no texture is set.
##
## All generated textures are cached by their (color, outline) key so the
## per-frame cost is zero once each unique color has been seen once.

const SIZE := 32

static var _cache_body: Dictionary = {}
static var _cache_arrow: Dictionary = {}
static var _cache_projectile: Dictionary = {}


static func make(color: Color, outline: Color = Color(0, 0, 0, 0.85)) -> Texture2D:
	var key := _key2(color, outline)
	var hit = _cache_body.get(key)
	if hit != null:
		return hit
	var tex := _build_body(color, outline)
	_cache_body[key] = tex
	return tex


static func make_arrow(color: Color = Color(1, 1, 1, 0.85)) -> Texture2D:
	var key := _key1(color)
	var hit = _cache_arrow.get(key)
	if hit != null:
		return hit
	var tex := _build_arrow(color)
	_cache_arrow[key] = tex
	return tex


static func make_projectile(color: Color = Color(1, 1, 0.8, 1.0)) -> Texture2D:
	var key := _key1(color)
	var hit = _cache_projectile.get(key)
	if hit != null:
		return hit
	var tex := _build_projectile(color)
	_cache_projectile[key] = tex
	return tex


static func _key1(c: Color) -> String:
	return "%x" % c.to_rgba32()


static func _key2(a: Color, b: Color) -> String:
	return "%x_%x" % [a.to_rgba32(), b.to_rgba32()]


static func _build_body(color: Color, outline: Color) -> Texture2D:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Body: head circle + torso rect
	var head_radius := 4
	var head_cx := SIZE / 2
	var head_cy := 8
	for y in range(SIZE):
		for x in range(SIZE):
			var draw := false
			var dx_h := x - head_cx
			var dy_h := y - head_cy
			if dx_h * dx_h + dy_h * dy_h <= head_radius * head_radius:
				draw = true
			if x >= 10 and x < SIZE - 10 and y >= 13 and y < SIZE - 4:
				draw = true
			if draw:
				img.set_pixel(x, y, color)

	# Outline pass
	var outlined := img.duplicate() as Image
	for y in range(SIZE):
		for x in range(SIZE):
			if img.get_pixel(x, y).a > 0.0:
				continue
			var has_neighbor := false
			for ox in [-1, 0, 1]:
				for oy in [-1, 0, 1]:
					var nx: int = x + int(ox)
					var ny: int = y + int(oy)
					if nx < 0 or ny < 0 or nx >= SIZE or ny >= SIZE:
						continue
					if img.get_pixel(nx, ny).a > 0.0:
						has_neighbor = true
						break
				if has_neighbor:
					break
			if has_neighbor:
				outlined.set_pixel(x, y, outline)
	return ImageTexture.create_from_image(outlined)


static func _build_arrow(color: Color) -> Texture2D:
	var w := 128
	var h := 32
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var shaft_h := h / 3
	for x in range(int(w * 0.7)):
		for y in range(int((h - shaft_h) / 2), int((h + shaft_h) / 2)):
			img.set_pixel(x, y, color)
	var head_start := int(w * 0.65)
	for x in range(head_start, w):
		var t := float(x - head_start) / float(w - head_start)
		var half := int((1.0 - t) * (h / 2 - 1))
		for y in range(h / 2 - half, h / 2 + half + 1):
			img.set_pixel(x, y, color)
	return ImageTexture.create_from_image(img)


static func _build_projectile(color: Color) -> Texture2D:
	# Arrowhead silhouette — wide at the tail, pointy on +X. Looks like a
	# squashed cone when billboarded toward the camera. Bigger total
	# dimensions than the old diamond so the projectile actually reads
	# in-game.
	var w := 20
	var h := 10
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in range(w):
		# t = 0 at the wide tail (left), 1 at the sharp tip (right).
		var t := float(x) / float(w - 1)
		# Linear taper from full half-height to 0.
		var half := int(round((1.0 - t) * float(h) / 2.0))
		# Clamp y range to [0, h). At t=0 the symmetric range would
		# otherwise overshoot h by one pixel.
		var y_start: int = max(0, h / 2 - half)
		var y_end: int = min(h, h / 2 + half + 1)
		for y in range(y_start, y_end):
			img.set_pixel(x, y, color)
	return ImageTexture.create_from_image(img)
