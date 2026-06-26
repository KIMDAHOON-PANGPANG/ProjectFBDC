extends Node3D

## M9-T5 퍼펙트 타이밍 신호 바 — 머리 위(HeatBar3D 보다 위)에 뜨는 더미 프로그래스바.
## Player.get_timing_window() 를 폴링: active=true 일 때만 보이고, frac 으로 채움 + sweet 구간(sweet_lo~sweet_hi)을 초록 강조.
## 전 발도술 공통(거합/박자/완극). ★표시/폴링만 — 게임플레이 무영향.
## top_level 추적 + 카메라 빌보드(HeatBar3D 패턴 재사용). Player.tscn 자식 아님(코드 인스턴스) → Main/Testplay 자동 반영.

@export var follow_offset: Vector3 = Vector3(0, 2.25, 0)  # HeatBar3D(y=2.0) 보다 위(+0.25)
@export var bar_width: float = 0.66
@export var bar_height: float = 0.10
@export var bg_color: Color = Color(0.06, 0.06, 0.08, 0.85)
@export var border_color: Color = Color(0.0, 0.0, 0.0, 0.92)
@export var fill_color: Color = Color(0.85, 0.85, 0.9, 1.0)      # 윈도우 잔여 채움(밝은 회백)
@export var sweet_color: Color = Color(0.25, 0.95, 0.35, 1.0)    # 퍼펙트존 강조(초록)
@export var empty_color: Color = Color(0.18, 0.18, 0.22, 0.7)

var _follow: Node3D
var _fill: MeshInstance3D    # 잔여 채움 바
var _sweet: MeshInstance3D   # 퍼펙트존 강조 바
var _fill_mat: StandardMaterial3D
var _sweet_mat: StandardMaterial3D


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
		visible = false
		return
	if not _follow.has_method("get_timing_window"):
		visible = false
		return
	var w = _follow.call("get_timing_window")
	if not (w is Dictionary) or not bool(w.get("active", false)):
		visible = false
		return
	visible = true
	_sync_to_target()
	var frac: float = clampf(float(w.get("frac", 0.0)), 0.0, 1.0)
	var slo: float = clampf(float(w.get("sweet_lo", 0.0)), 0.0, 1.0)
	var shi: float = clampf(float(w.get("sweet_hi", 1.0)), 0.0, 1.0)
	# 잔여 채움 — 좌측 기준(0..frac). 폭=bar_width*frac, 좌측 정렬.
	var fw: float = max(bar_width * frac, 0.0001)
	var mesh := _fill.mesh as QuadMesh
	if mesh != null:
		mesh.size = Vector2(fw, bar_height)
	_fill.position = Vector3(-bar_width * 0.5 + fw * 0.5, 0, 0.001)
	# 퍼펙트존 강조 — [slo..shi] 구간을 초록으로(현재 frac 이 그 안이면 더 밝게).
	var sw: float = max(bar_width * (shi - slo), 0.0001)
	var smesh := _sweet.mesh as QuadMesh
	if smesh != null:
		smesh.size = Vector2(sw, bar_height)
	_sweet.position = Vector3(-bar_width * 0.5 + (slo + (shi - slo) * 0.5) * bar_width, 0, 0.0015)
	# frac 이 퍼펙트존 안이면 진하게(누르면 퍼펙트), 밖이면 흐리게.
	var in_sweet: bool = frac >= slo and frac <= shi
	if _sweet_mat != null:
		_sweet_mat.albedo_color = Color(sweet_color.r, sweet_color.g, sweet_color.b, 0.95 if in_sweet else 0.45)
	if _fill_mat != null:
		_fill_mat.albedo_color = fill_color


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
	add_child(_rect(bar_width + 0.04, bar_height + 0.04, border_color, Vector3(0, 0, -0.004), 100))  # 테두리
	add_child(_rect(bar_width, bar_height, empty_color, Vector3(0, 0, -0.002), 101))                 # 배경(빈 트랙)
	_sweet = _rect(bar_width, bar_height, sweet_color, Vector3(0, 0, 0.0015), 102)                    # 퍼펙트존(매 프레임 폭/색 갱신)
	_sweet_mat = _sweet.material_override as StandardMaterial3D
	add_child(_sweet)
	_fill = _rect(bar_width, bar_height, fill_color, Vector3(0, 0, 0.001), 103)                        # 잔여 채움(매 프레임 폭 갱신)
	_fill_mat = _fill.material_override as StandardMaterial3D
	add_child(_fill)


func _rect(w: float, h: float, col: Color, pos: Vector3, priority: int = 100) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	m.mesh = q
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = col
	mat.no_depth_test = true
	mat.render_priority = priority
	m.material_override = mat
	m.position = pos
	return m
