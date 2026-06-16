extends Node3D

## 열관리(Heat) 게이지 — "게임 시작 2"(즉발 일섬) 모드에서만 머리 위에 뜨는
## 가로 바. 부모(Player)의 is_instant_slash_mode / get_heat_frac / is_overheated
## 를 덕타이핑으로 읽는다. 모드1 이면 숨긴다.
##
## DodgeStackBar3D 와 동일한 top_level 추적 + 노드 단위 빌보드. Player.tscn 의
## 자식으로 넣으면 Main/Testplay 양쪽에 자동 반영.

@export var follow_offset: Vector3 = Vector3(0, 2.42, 0)  # 회피 스택바(2.16) 위
@export var bar_width: float = 0.62
@export var bar_height: float = 0.1
@export var bg_color: Color = Color(0.08, 0.06, 0.05, 0.85)
@export var border_color: Color = Color(0.0, 0.0, 0.0, 0.92)
## 열 낮음(주황) → 높음(빨강)으로 보간. 탈진 시 회색.
@export var cool_color: Color = Color(0.95, 0.62, 0.18, 1.0)
@export var hot_color: Color = Color(0.95, 0.2, 0.12, 1.0)
@export var overheat_color: Color = Color(0.55, 0.55, 0.62, 1.0)

var _follow: Node3D
var _fill_carrier: Node3D
var _fill_mat: StandardMaterial3D


func _ready() -> void:
	top_level = true
	var p := get_parent()
	if p is Node3D:
		_follow = p
	_build()
	visible = false


func _process(_delta: float) -> void:
	_update()

func _physics_process(_delta: float) -> void:
	_update()


func _update() -> void:
	if _follow == null or not is_instance_valid(_follow):
		return
	# 즉발 일섬 모드가 아니면 숨긴다(모드1 에선 열 개념 없음).
	if not _follow.has_method("is_instant_slash_mode") or not bool(_follow.call("is_instant_slash_mode")):
		visible = false
		return
	visible = true
	_sync_to_target()
	var frac: float = 0.0
	if _follow.has_method("get_heat_frac"):
		frac = clamp(float(_follow.call("get_heat_frac")), 0.0, 1.0)
	var over: bool = _follow.has_method("is_overheated") and bool(_follow.call("is_overheated"))
	if over:
		# 탈진 — 가득 찬 회색 바.
		_fill_carrier.scale = Vector3(1.0, 1.0, 1.0)
		_fill_mat.albedo_color = overheat_color
	else:
		_fill_carrier.scale = Vector3(max(frac, 0.0001), 1.0, 1.0)
		_fill_mat.albedo_color = cool_color.lerp(hot_color, frac)


func _sync_to_target() -> void:
	if _follow == null or not is_instance_valid(_follow):
		return
	global_position = _follow.global_position + follow_offset
	_face_camera()

func _face_camera() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var cam := vp.get_camera_3d()
	if cam == null:
		return
	global_basis = cam.global_basis.orthonormalized()


func _build() -> void:
	add_child(_rect(bar_width + 0.04, bar_height + 0.04, border_color, Vector3(0, 0, -0.004)))  # 테두리
	add_child(_rect(bar_width, bar_height, bg_color, Vector3(0, 0, -0.002)))                    # 배경
	# fill 캐리어 — 좌측 모서리에 원점, fill 의 좌측 모서리를 원점에 맞춰 scale.x 가
	# 곧 채움 비율(좌→우로 차오름).
	_fill_carrier = Node3D.new()
	_fill_carrier.position = Vector3(-bar_width * 0.5, 0, 0)
	add_child(_fill_carrier)
	var fill := _rect(bar_width, bar_height, cool_color, Vector3(bar_width * 0.5, 0, 0))
	_fill_mat = fill.material_override
	_fill_carrier.add_child(fill)


func _rect(w: float, h: float, col: Color, pos: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	m.mesh = q
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = col
	mat.no_depth_test = true
	m.material_override = mat
	m.position = pos
	return m
