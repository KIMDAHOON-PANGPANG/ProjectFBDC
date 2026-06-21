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
## True once we've ever locked onto a valid follow target. Gate for the
## orphan self-free safety net: a bar that NEVER had a target (e.g. built
## standalone in a tool) must not self-destruct, but a bar that HAD one and
## then lost it (parent freed / detached) is an orphan and removes itself so
## a stranded full-HP bar can never linger over an absent sprite.
var _had_target: bool = false
## 다층 방어 C — 추적 몹의 렌더 노드(SpriteRig 또는 Sprite3D). 처음 한 번 찾아 캐시.
## 이게 "안 보이는" 상태면 바도 숨긴다(스프라이트 없는 허공 바 원천 차단).
var _target_render: Node = null
var _render_searched: bool = false
## owner died 로 영구 숨김됐는지 — 이 경우 렌더 복귀해도 다시 보이게 하지 않는다.
var _owner_dead: bool = false
## PC 바 등 추적 대상이 "player" 그룹이면 가시성 자동관리에서 제외(PC 바는 항상
## visible=false 유지가 정책이라 우리가 건드리면 안 됨).
var _is_player_target: bool = false

func _ready() -> void:
	_build()
	_refresh(1.0, 0.0, 1.0)
	# Detach from parent transform inheritance and drive position ourselves.
	top_level = true
	# Default follow target = our parent (typical Player.tscn setup).
	var p := get_parent()
	if p is Node3D:
		_follow_target = p
		_had_target = true
		_is_player_target = (p as Node).is_in_group("player")
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
	# Orphan safety net: if we once had a valid target and it's now gone
	# (freed / detached from the tree), remove ourselves. This guarantees a
	# stranded full-HP bar can never hang in the air over a missing sprite,
	# regardless of which upstream path failed to clean us up. The PC bar's
	# target (Player) stays valid for the whole run, so it is never affected
	# — judged purely on target validity, never on `visible` (the PC bar is
	# hidden via visible=false yet must persist).
	var lost: bool = _follow_target == null \
		or not is_instance_valid(_follow_target) \
		or not (_follow_target as Node).is_inside_tree()
	if lost:
		if _had_target and not is_queued_for_deletion():
			queue_free()
		return
	global_position = _follow_target.global_position + follow_offset
	_face_camera()
	# 다층 방어 C — PC 바가 아닌(=몹) 바는, 추적 몹이 사망 처리됐거나 그 몹의
	# 스프라이트가 실제로 안 보이는 상태면 바도 숨긴다. 스프라이트 없는 허공/땅의
	# 풀HP 바가 어떤 원인으로도 노출되지 않게 하는 최종 게이트. PC 바(player 타겟)는
	# 정책상 항상 visible=false 라 절대 손대지 않는다.
	if not _is_player_target:
		_update_render_gate()

## 다층 방어 C — 추적 몹의 렌더 가시성에 따라 바 자신의 visible 을 끈다/켠다.
## `_on_owner_died()` 가 영구 숨김(`_owner_dead`)한 바는 다시 켜지 않는다(사망 우선).
func _update_render_gate() -> void:
	if _owner_dead:
		visible = false
		return
	# 추적 몹이 _dead 플래그를 들고 있으면(사망 페이드 중) 숨긴다.
	if "_dead" in _follow_target and _follow_target._dead == true:
		visible = false
		return
	var rendering: bool = _is_target_rendering()
	# 안 보이는 몹 위엔 바도 숨김. 다시 보이면(블링크 종료 등) 복원.
	visible = rendering

## 추적 몹의 스프라이트가 실제로 화면에 보일 상태인가. SpriteRig 가 있으면 그
## `is_sprite_rendering()` 질의(애니메이션 시트/셰이더 modulate 까지 반영), 없으면
## 자식 Sprite3D 를 직접 검사(엘리트/보스의 "Visual" 노드). 둘 다 없으면 보임 취급
## (예외 케이스에서 바를 과하게 숨기지 않도록 — 다른 안전망이 있다).
func _is_target_rendering() -> bool:
	if not _render_searched:
		_render_searched = true
		_target_render = _find_render_node(_follow_target)
	var r := _target_render
	if r == null or not is_instance_valid(r):
		# 캐시가 무효화됐으면 한 번 더 찾는다(노드 교체 등 드문 경우).
		_target_render = _find_render_node(_follow_target)
		r = _target_render
	if r == null:
		return true
	if r.has_method("is_sprite_rendering"):
		return bool(r.call("is_sprite_rendering"))
	# 순수 Sprite3D — modulate alpha / visible / texture 직접 검사.
	if r is Sprite3D:
		var s := r as Sprite3D
		if not s.visible:
			return false
		if s.modulate.a < 0.04:
			return false
		if s.texture == null:
			return false
		return true
	# VisualInstance3D 등 — visible 만 확인.
	if r is Node3D:
		return (r as Node3D).visible
	return true

## 추적 몹 서브트리에서 렌더 노드를 찾는다(우선순위: SpriteRig > Sprite3D).
func _find_render_node(root_node: Node) -> Node:
	if root_node == null:
		return null
	# 1순위: is_sprite_rendering 을 제공하는 노드(SpriteRig).
	var rig := _find_with_method(root_node)
	if rig != null:
		return rig
	# 2순위: 첫 Sprite3D.
	return _find_sprite3d(root_node)

func _find_with_method(n: Node) -> Node:
	if n.has_method("is_sprite_rendering"):
		return n
	for c in n.get_children():
		var r := _find_with_method(c)
		if r != null:
			return r
	return null

func _find_sprite3d(n: Node) -> Node:
	if n is Sprite3D:
		return n
	for c in n.get_children():
		var r := _find_sprite3d(c)
		if r != null:
			return r
	return null

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

func _build() -> void:
	# Border (drawn behind, slightly larger). One-time geometry.
	_border = MeshInstance3D.new()
	var bm := QuadMesh.new()
	bm.size = Vector2(width + 0.04, height + 0.04)
	_border.mesh = bm
	_border.material_override = _make_unshaded(border_color, 100)
	_border.position = Vector3(0, 0, -0.003)
	add_child(_border)

	# Background plate.
	_bg = MeshInstance3D.new()
	var bgm := QuadMesh.new()
	bgm.size = Vector2(width, height)
	_bg.mesh = bgm
	_bg.material_override = _make_unshaded(bg_color, 101)
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
	_fill.material_override = _make_unshaded(fill_color, 102)
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
	_armor_fill.material_override = _make_unshaded(armor_color, 103)
	_armor_fill.position = Vector3(width * 0.5, 0, 0)
	_armor_carrier.add_child(_armor_fill)

func _make_unshaded(color: Color, priority: int = 100) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# No material-level billboard — the parent node faces the camera in
	# _face_camera(). Per-mesh billboarding rotates each mesh around its
	# own center, which makes the fill drift left of the BG once HP drops.
	mat.no_depth_test = true
	# 같은 바 내부도 레이어별 우선순위 차등(테두리<배경<HP<아머) → no_depth_test 라도
	# 빨강 HP fill 이 검은 배경에 안 가려진다. 100+ 라 VFX/지오메트리(0) 보다 항상 위.
	mat.render_priority = priority
	return mat

## Connect to a HealthComponent so we auto-refresh on damage/heal events.
func attach_health(hp: HealthComponent) -> void:
	if _hp != null:
		if _hp.damaged.is_connected(_on_damaged):
			_hp.damaged.disconnect(_on_damaged)
		if _hp.has_signal("armor_changed") and _hp.armor_changed.is_connected(_on_damaged):
			_hp.armor_changed.disconnect(_on_damaged)
		if _hp.has_signal("died") and _hp.died.is_connected(_on_owner_died):
			_hp.died.disconnect(_on_owner_died)
	_hp = hp
	if _hp != null:
		_hp.damaged.connect(_on_damaged)
		if _hp.has_signal("armor_changed"):
			_hp.armor_changed.connect(_on_damaged)
		# Hide the bar the instant the owner dies — the enemy then plays a
		# fade/sink death animation for up to ~0.9s before it frees, and we
		# don't want a (now mostly-empty) bar hanging over a vanishing
		# sprite for that window. The bar still frees with its parent at the
		# end of that animation; this just blanks it immediately. PC's
		# HealthComponent never emits `died` while the run continues.
		if _hp.has_signal("died"):
			_hp.died.connect(_on_owner_died)
		refresh()

# damaged(amount) 와 armor_changed() 양쪽에 연결 — 기본값 0 으로 0인자 시그널도 수용.
func _on_damaged(_amount: int = 0) -> void:
	refresh()

## Owner died — blank the bar immediately so the death fade/sink plays with
## no leftover bar floating over the disappearing sprite. The node still
## frees together with its parent enemy at the end of that animation.
func _on_owner_died() -> void:
	_owner_dead = true
	visible = false

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
