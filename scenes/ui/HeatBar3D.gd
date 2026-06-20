extends Node3D

## 열관리 스택 — "게임 시작 2"(즉발 일섬) 모드에서만 머리 위에 뜨는 5칸 스택.
## 연속 게이지가 아니라 5개 칸(pip)으로 이산화: 켜진 칸 수 = ceil(get_heat_frac × 5).
## 칸 색은 낮음(주황)→높음(빨강) 보간, 탈진(is_overheated) 시 전부 회색.
## 부모(Player)의 is_instant_slash_mode / get_heat_frac / is_overheated 를 덕타이핑.
##
## top_level 추적 + 노드 단위 빌보드. Player.tscn 자식으로 넣으면 Main/Testplay 자동 반영.

@export var follow_offset: Vector3 = Vector3(0, 2.42, 0)  # 회피 스택바(2.16) 위
@export var bar_width: float = 0.66
@export var bar_height: float = 0.13
@export var bg_color: Color = Color(0.08, 0.06, 0.05, 0.85)
@export var border_color: Color = Color(0.0, 0.0, 0.0, 0.92)
## 열 낮음(주황) → 높음(빨강)으로 칸 색 보간. 탈진 시 회색, 미점등 칸은 empty.
@export var cool_color: Color = Color(0.95, 0.62, 0.18, 1.0)
@export var hot_color: Color = Color(0.95, 0.2, 0.12, 1.0)
@export var overheat_color: Color = Color(0.55, 0.55, 0.62, 1.0)
@export var empty_color: Color = Color(0.22, 0.16, 0.13, 0.7)

const PIPS: int = 5

var _follow: Node3D
var _pips: Array = []  # MeshInstance3D × 5


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
	# 켜진 칸 수 = ceil(frac × 5). 첫 일섬(10%)에도 1칸이 켜지도록 ceil.
	var lit: int = int(ceil(frac * float(PIPS)))
	for i in PIPS:
		var mat := (_pips[i] as MeshInstance3D).material_override as StandardMaterial3D
		if mat == null:
			continue
		if over:
			mat.albedo_color = overheat_color
		elif i < lit:
			mat.albedo_color = cool_color.lerp(hot_color, float(i + 1) / float(PIPS))
		else:
			mat.albedo_color = empty_color


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
	add_child(_rect(bar_width, bar_height, bg_color, Vector3(0, 0, -0.002), 101))                    # 배경
	# 5칸 pip — 균등 간격 + 작은 갭. 좌→우로 채워진다.
	var gap: float = 0.018
	var pw: float = (bar_width - gap * float(PIPS - 1)) / float(PIPS)
	var x0: float = -bar_width * 0.5 + pw * 0.5
	for i in PIPS:
		var pip := _rect(pw * 0.9, bar_height * 0.72, empty_color, Vector3(x0 + float(i) * (pw + gap), 0, 0.0), 102)
		add_child(pip)
		_pips.append(pip)


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
	# 바 내부 레이어 차등(테두리<배경<pip) → no_depth_test 라도 pip 이 배경에 안 가려짐. 100+ 라 VFX(0) 위.
	mat.render_priority = priority
	m.material_override = mat
	m.position = pos
	return m
