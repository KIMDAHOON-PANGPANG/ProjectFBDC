extends Node3D

## 회피(대시) 스택 표시 — 캐릭터 머리 위 HP바보다 한 단 위. 작은 사각형이 스택
## 수만큼 구분되어, 사용 가능한 칸은 채워지고 소비되면 빈다. 충전 중인 칸은
## 아래에서 위로 한 칸씩 차오른다(부분 채움 = evade_refill_frac).
##
## HpBar3D 와 동일한 top_level 추적 + 노드 단위 빌보드. 부모(Player)의
## get_evade_stacks / get_max_evade_stacks / evade_refill_frac 를 덕타이핑으로 읽음.
## Player.tscn 의 자식으로 넣으면 Main/Testplay 양쪽 자동 반영.

@export var follow_offset: Vector3 = Vector3(0, 2.16, 0)  # HP바(1.9) 위
@export var cell_size: float = 0.16
@export var cell_gap: float = 0.07
@export var bg_color: Color = Color(0.08, 0.08, 0.1, 0.85)
@export var fill_color: Color = Color(0.45, 0.85, 1.0, 1.0)  # 시안(회피 가능)
@export var border_color: Color = Color(0.0, 0.0, 0.0, 0.92)

var _follow: Node3D
var _fill_carriers: Array = []   # 각 칸의 fill 캐리어(scale.y 로 차오름)
var _built_max: int = -1


func _ready() -> void:
	top_level = true
	var p := get_parent()
	if p is Node3D:
		_follow = p
	_sync_to_target()


func _process(_delta: float) -> void:
	_update()

func _physics_process(_delta: float) -> void:
	_update()


func _update() -> void:
	if _follow == null or not is_instance_valid(_follow) or not _follow.has_method("get_evade_stacks"):
		return
	var maxs: int = 2
	if _follow.has_method("get_max_evade_stacks"):
		maxs = max(1, int(_follow.call("get_max_evade_stacks")))
	if maxs != _built_max:
		_rebuild(maxs)
	_sync_to_target()
	var stacks: int = int(_follow.call("get_evade_stacks"))
	var frac: float = 1.0
	if _follow.has_method("evade_refill_frac"):
		frac = float(_follow.call("evade_refill_frac"))
	for i in _fill_carriers.size():
		var f: float
		if i < stacks:
			f = 1.0
		elif i == stacks:
			f = frac  # 충전 중인 칸
		else:
			f = 0.0
		_fill_carriers[i].scale = Vector3(1.0, max(f, 0.0001), 1.0)


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


func _rebuild(maxs: int) -> void:
	for c in get_children():
		c.queue_free()
	_fill_carriers.clear()
	_built_max = maxs
	var total_w: float = maxs * cell_size + (maxs - 1) * cell_gap
	var start_x: float = -total_w * 0.5
	for i in maxs:
		var cx: float = start_x + i * (cell_size + cell_gap) + cell_size * 0.5
		add_child(_quad(cell_size + 0.03, border_color, Vector3(cx, 0, -0.004)))  # 테두리
		add_child(_quad(cell_size, bg_color, Vector3(cx, 0, -0.002)))             # 배경
		# fill 캐리어 — 칸 하단에 원점, fill quad 의 하단 모서리를 원점에 맞춰
		# scale.y 가 곧 채움 비율(아래→위로 차오름).
		var carrier := Node3D.new()
		carrier.position = Vector3(cx, -cell_size * 0.5, 0)
		add_child(carrier)
		var fill := _quad(cell_size, fill_color, Vector3(0, cell_size * 0.5, 0))
		carrier.add_child(fill)
		_fill_carriers.append(carrier)


func _quad(size: float, col: Color, pos: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	m.mesh = q
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = col
	mat.no_depth_test = true
	m.material_override = mat
	m.position = pos
	return m
