class_name HpBar3D
extends Node3D

## Floating HP bar that sits over an entity's head in world space.
##
## Structure:
##   HpBar3D  (top-level: positioned each frame from `_follow_target`,
##             and yaw-rotated each frame to face the camera)
##   ├ Border  (slightly larger black quad, behind)
##   ├ Bg      (dark plate, middle)
##   └ FillCarrier (Node3D pinned to the BG's LEFT edge)
##       └ Fill (red quad whose local origin is at the left edge)
##
## Why top-level + manual follow instead of plain parent-child inheritance:
##   - Parent-child transform inheritance had visible one-frame lag in some
##     scenarios — the PC body would move (dash, physics push) and the bar
##     would briefly trail. Marking the bar `top_level = true` and pinning
##     its global_position from the target's global_position in _process
##     guarantees the bar is wherever the PC actually is, with zero drift.
##
## Why we rotate the NODE to face the camera (instead of using
## BILLBOARD_FIXED_Y on each mesh material):
##   - Material-level billboarding rotates every mesh around its OWN
##     center. The fill quad's effective center walks leftward as HP
##     drops (the carrier-scale trick deliberately welds the quad's left
##     edge to the BG's left edge — see `_build`). So once HP < 100% the
##     BG/Border meshes and the Fill mesh end up with DIFFERENT rotation
##     pivots. Any non-zero camera yaw — e.g. the post-hit camera shake
##     jiggling the X position right when HP changes — then visually
##     slides the fill out from under the BG, and the fill appears to
##     "shove left out of the frame" on damage. Rotating the parent node
##     once means every quad shares the same pivot, so left edges stay
##     welded regardless of camera angle or current HP ratio.
##   - We use FULL billboarding (mirror the camera's basis, including
##     pitch), not yaw-only. A yaw-only approach makes the bar visibly
##     tilt/skew whenever A/D movement opens an angle between the PC and
##     the lagging camera rig — the bar reads as a parallelogram instead
##     of a rectangle. Full billboarding keeps the bar's silhouette
##     perfectly rectangular regardless of how the camera and PC offset
##     drift apart frame-to-frame.
##
## Color is a solid red (no green-to-red lerp); per user balance request.

@export var width: float = 0.6
@export var height: float = 0.08
@export var bg_color: Color = Color(0.07, 0.07, 0.09, 0.9)
@export var fill_color: Color = Color(0.92, 0.18, 0.22, 1.0)
@export var border_color: Color = Color(0.0, 0.0, 0.0, 0.95)
## 아머(경직 게이지) 칸 색 — HP 우측에 표시되는 파란 게이지(armor_max>0 일 때만).
@export var armor_color: Color = Color(0.25, 0.55, 1.0, 1.0)
## World-space offset above the follow target. Default = head height of the
## PC capsule (1.4 cap + a bit of headroom).
@export var follow_offset: Vector3 = Vector3(0, 1.9, 0)

var _bg: MeshInstance3D
var _fill: MeshInstance3D
var _fill_carrier: Node3D
var _armor_fill: MeshInstance3D
var _armor_carrier: Node3D
var _border: MeshInstance3D
var _hp: HealthComponent
# Node we glue ourselves above every frame. Defaults to our parent.
var _follow_target: Node3D

func _ready() -> void:
	_build()
	_refresh(1.0, 0.0, 1.0)
	# Detach from parent transform inheritance and drive position ourselves.
	top_level = true
	# Default follow target = our parent (typical Player.tscn setup).
	var p := get_parent()
	if p is Node3D:
		_follow_target = p
	# Snap to target immediately so the bar isn't at world origin for one
	# frame before _process catches up.
	_sync_to_target()

func _process(_delta: float) -> void:
	_sync_to_target()

## Also sync during the physics step so we follow the PC the SAME tick it
## moves. Without this, fast moves (Shift-dash, knockback) leave the bar
## one render frame behind because _process runs before the next physics
## tick's _physics_process moves the PC.
func _physics_process(_delta: float) -> void:
	_sync_to_target()

func _sync_to_target() -> void:
	if _follow_target == null or not is_instance_valid(_follow_target):
		return
	global_position = _follow_target.global_position + follow_offset
	_face_camera()

## Mirror the camera's full orientation so the bar is plane-on to the
## camera every frame. See class doc for why this is node-level (not
## per-mesh) and why it's full billboarding (not yaw-only).
func _face_camera() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var cam := vp.get_camera_3d()
	if cam == null:
		return
	# Copy only rotation; orthonormalize so any non-uniform camera scale
	# can't bleed into the bar's size. Translation was already pinned by
	# the caller, so we replace only the basis.
	global_basis = cam.global_basis.orthonormalized()

## Optional override — useful if the bar should follow some node other than
## its parent (e.g. an offset socket on a complex rig).
func set_follow_target(node: Node3D) -> void:
	_follow_target = node
	_sync_to_target()

func _build() -> void:
	# Border (drawn behind, slightly larger). One-time geometry.
	_border = MeshInstance3D.new()
	var bm := QuadMesh.new()
	bm.size = Vector2(width + 0.04, height + 0.04)
	_border.mesh = bm
	_border.material_override = _make_unshaded(border_color)
	_border.position = Vector3(0, 0, -0.003)
	add_child(_border)

	# Background plate.
	_bg = MeshInstance3D.new()
	var bgm := QuadMesh.new()
	bgm.size = Vector2(width, height)
	_bg.mesh = bgm
	_bg.material_override = _make_unshaded(bg_color)
	add_child(_bg)

	# Fill: a Node3D carrier pinned to the BG's LEFT edge, holding a quad
	# whose center sits at +width/2 inside the carrier (i.e. quad's LEFT
	# edge == carrier origin). Carrier scale.x then == fill ratio without
	# any position juggling.
	_fill_carrier = Node3D.new()
	_fill_carrier.position = Vector3(-width * 0.5, 0, 0.003)
	add_child(_fill_carrier)

	_fill = MeshInstance3D.new()
	var fm := QuadMesh.new()
	fm.size = Vector2(width, height)
	_fill.mesh = fm
	_fill.material_override = _make_unshaded(fill_color)
	# Place the quad center at +width/2 inside the carrier so the quad's
	# LEFT edge coincides with the carrier origin (which is at the BG's
	# left edge). Now scaling the carrier just clips the right side.
	_fill.position = Vector3(width * 0.5, 0, 0)
	_fill_carrier.add_child(_fill)

	# 아머(파란) 칸 — HP 존 경계에서 시작해 오른쪽으로 채워진다. 위치/스케일은
	# refresh() 가 armor_max 에 맞춰 매번 갱신(armor_max=0 이면 숨겨 PC 바엔 영향 없음).
	_armor_carrier = Node3D.new()
	_armor_carrier.position = Vector3(width * 0.5, 0, 0.004)
	_armor_carrier.visible = false
	add_child(_armor_carrier)
	_armor_fill = MeshInstance3D.new()
	var am := QuadMesh.new()
	am.size = Vector2(width, height)
	_armor_fill.mesh = am
	_armor_fill.material_override = _make_unshaded(armor_color)
	_armor_fill.position = Vector3(width * 0.5, 0, 0)
	_armor_carrier.add_child(_armor_fill)

func _make_unshaded(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# No material-level billboard — the parent node faces the camera in
	# _face_camera(). Per-mesh billboarding rotates each mesh around its
	# own center, which makes the fill drift left of the BG once HP drops.
	mat.no_depth_test = true
	return mat

## Connect to a HealthComponent so we auto-refresh on damage/heal events.
func attach_health(hp: HealthComponent) -> void:
	if _hp != null:
		if _hp.damaged.is_connected(_on_damaged):
			_hp.damaged.disconnect(_on_damaged)
		if _hp.has_signal("armor_changed") and _hp.armor_changed.is_connected(_on_damaged):
			_hp.armor_changed.disconnect(_on_damaged)
	_hp = hp
	if _hp != null:
		_hp.damaged.connect(_on_damaged)
		if _hp.has_signal("armor_changed"):
			_hp.armor_changed.connect(_on_damaged)
		refresh()

# damaged(amount) 와 armor_changed() 양쪽에 연결 — 기본값 0 으로 0인자 시그널도 수용.
func _on_damaged(_amount: int = 0) -> void:
	refresh()

func refresh() -> void:
	if _hp == null:
		_refresh(1.0, 0.0, 1.0)
		return
	var hp_ratio: float = float(_hp.hp) / float(max(_hp.max_hp, 1))
	var armor_max: int = 0
	if "armor_max" in _hp:
		armor_max = int(_hp.armor_max)
	var armor_ratio: float = 0.0
	if armor_max > 0 and "armor" in _hp:
		armor_ratio = clamp(float(_hp.armor) / float(armor_max), 0.0, 1.0)
	# HP 존이 차지하는 폭 비율 = max_hp / (max_hp + armor_max). armor_max=0 이면 1.0(전폭 HP).
	var total: float = float(max(_hp.max_hp, 1) + armor_max)
	var hp_zone: float = float(max(_hp.max_hp, 1)) / total
	_refresh(hp_ratio, armor_ratio, hp_zone)

func _refresh(hp_ratio: float, armor_ratio: float, hp_zone: float) -> void:
	hp_ratio = clamp(hp_ratio, 0.0, 1.0)
	armor_ratio = clamp(armor_ratio, 0.0, 1.0)
	hp_zone = clamp(hp_zone, 0.0, 1.0)
	if _fill_carrier != null:
		# HP 는 [bar 왼쪽 ~ hp_zone] 구간을 hp_ratio 만큼 채운다(왼쪽 고정 스케일).
		_fill_carrier.scale = Vector3(max(hp_zone * hp_ratio, 0.0001), 1.0, 1.0)
	if _armor_carrier != null:
		var armor_zone: float = 1.0 - hp_zone
		if armor_zone <= 0.0001:
			_armor_carrier.visible = false
		else:
			_armor_carrier.visible = true
			# 아머 칸: HP 존 경계에서 시작해 오른쪽으로 armor_ratio 만큼 채운다.
			_armor_carrier.position = Vector3(-width * 0.5 + hp_zone * width, 0, 0.004)
			_armor_carrier.scale = Vector3(max(armor_zone * armor_ratio, 0.0001), 1.0, 1.0)
