class_name ReloadBar3D
extends Node3D

## 비도(Kunai) 리로드 진행바 — 캐릭터 머리 위에 떠 있는 월드 공간 게이지.
## 리로드 중일 때만 보이고, 0→1로 차오른다. 차오름이 끝나면 자동으로 숨는다.
##
## 동작 / 빌보드 방식은 [HpBar3D]와 동일하게 맞췄다:
##   - top_level = true 로 부모 트랜스폼 상속을 끊고, 매 프레임 부모(Player)
##     위치 + follow_offset 으로 직접 위치를 박는다 (대시/넉백 시 한 프레임
##     끌림 없음).
##   - 카메라를 향하도록 NODE 단위로 회전(메시별 빌보드 X). 채워지는 막대의
##     왼쪽 모서리가 BG 왼쪽 모서리에 항상 붙어 있게 하기 위함 — HpBar3D
##     주석 참고.
##
## 리로드 상태는 부모(Player)의 is_reloading() / reload_frac() 를 덕타이핑으로
## 읽는다. Player.tscn 의 자식으로 넣기만 하면 별도 배선이 필요 없다. Main /
## Testplay 둘 다 Player.tscn 을 인스턴스하므로 양쪽에 자동 반영된다.

@export var width: float = 0.6
@export var height: float = 0.06
@export var bg_color: Color = Color(0.07, 0.07, 0.09, 0.9)
## 앰버 톤 — "장전 중" 느낌. HP바(빨강)와 색으로 구분된다.
@export var fill_color: Color = Color(0.95, 0.82, 0.25, 1.0)
@export var border_color: Color = Color(0.0, 0.0, 0.0, 0.95)
## HP바(y≈1.9) 바로 위에 자리하도록 한 단 높게.
@export var follow_offset: Vector3 = Vector3(0, 2.18, 0)

var _bg: MeshInstance3D
var _fill: MeshInstance3D
var _fill_carrier: Node3D
var _border: MeshInstance3D
# 매 프레임 위에 따라붙는 대상. 기본값 = 부모(Player).
var _follow_target: Node3D

func _ready() -> void:
	_build()
	_refresh(0.0)
	# 부모 트랜스폼 상속을 끊고 위치를 직접 구동.
	top_level = true
	var p := get_parent()
	if p is Node3D:
		_follow_target = p
	# 리로드 중이 아니면 숨김 상태로 시작.
	visible = false
	_sync_to_target()

func _process(_delta: float) -> void:
	_update_state()

## 물리 스텝에서도 갱신 — Player 가 움직이는 그 틱에 같이 따라붙게 한다
## (대시/넉백 시 한 렌더 프레임 끌림 방지). HpBar3D 와 동일.
func _physics_process(_delta: float) -> void:
	_update_state()

func _update_state() -> void:
	if _follow_target == null or not is_instance_valid(_follow_target):
		visible = false
		return
	var reloading: bool = false
	if _follow_target.has_method("is_reloading"):
		reloading = bool(_follow_target.call("is_reloading"))
	visible = reloading
	if not reloading:
		return
	_sync_to_target()
	var frac: float = 1.0
	if _follow_target.has_method("reload_frac"):
		frac = float(_follow_target.call("reload_frac"))
	_refresh(frac)

func _sync_to_target() -> void:
	if _follow_target == null or not is_instance_valid(_follow_target):
		return
	global_position = _follow_target.global_position + follow_offset
	_face_camera()

## 카메라의 전체 방향을 그대로 복사해 막대가 매 프레임 카메라에 정면으로
## 마주보게 한다. (노드 단위인 이유 / 풀 빌보드인 이유는 HpBar3D 참고.)
func _face_camera() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var cam := vp.get_camera_3d()
	if cam == null:
		return
	global_basis = cam.global_basis.orthonormalized()

func _build() -> void:
	# 테두리 (뒤에, 약간 크게).
	_border = MeshInstance3D.new()
	var bm := QuadMesh.new()
	bm.size = Vector2(width + 0.04, height + 0.04)
	_border.mesh = bm
	_border.material_override = _make_unshaded(border_color)
	_border.position = Vector3(0, 0, -0.003)
	add_child(_border)

	# 배경 판.
	_bg = MeshInstance3D.new()
	var bgm := QuadMesh.new()
	bgm.size = Vector2(width, height)
	_bg.mesh = bgm
	_bg.material_override = _make_unshaded(bg_color)
	add_child(_bg)

	# 채움: BG 왼쪽 모서리에 고정된 캐리어(Node3D)에 quad 를 담는다. quad 중심을
	# 캐리어 안에서 +width/2 에 두어 quad 왼쪽 모서리가 캐리어 원점(=BG 왼쪽
	# 모서리)에 일치. 캐리어 scale.x 가 곧 진행률 (위치 보정 불필요).
	_fill_carrier = Node3D.new()
	_fill_carrier.position = Vector3(-width * 0.5, 0, 0.003)
	add_child(_fill_carrier)

	_fill = MeshInstance3D.new()
	var fm := QuadMesh.new()
	fm.size = Vector2(width, height)
	_fill.mesh = fm
	_fill.material_override = _make_unshaded(fill_color)
	_fill.position = Vector3(width * 0.5, 0, 0)
	_fill_carrier.add_child(_fill)

func _make_unshaded(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	return mat

## 0→1 진행률로 채움 막대 너비만 스케일. 캐리어 원점은 BG 왼쪽에 고정.
func _refresh(ratio: float) -> void:
	ratio = clamp(ratio, 0.0, 1.0)
	if _fill_carrier != null:
		_fill_carrier.scale = Vector3(max(ratio, 0.0001), 1.0, 1.0)
