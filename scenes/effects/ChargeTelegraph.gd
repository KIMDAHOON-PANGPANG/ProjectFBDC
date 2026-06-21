extends Node3D

## 보스 돌진 텔레그래프 — 보스 발치에서 PC 방향으로 길게 뻗는 직사각형 데칼(돌진 레인).
## 호밍 동안 보스가 매 프레임 set_lane() 으로 방향을 갱신(PC 추적), lock() 시 색이
## 진해지며 고정된다. 이 노드는 순수 비주얼 — 보스가 소유·구동하고 돌진 끝나면 free.

@export var homing_color: Color = Color(0.95, 0.25, 0.2, 0.32)  # 호밍(연한 빨강 — 베이스 레인)
@export var lock_color: Color = Color(1.0, 0.32, 0.16, 0.72)    # 고정(진한 빨강)
## fill(차오름) 색 — 베이스 레인 위로 보스 중심→끝으로 채워지는 진한 빨강.
@export var fill_color: Color = Color(1.0, 0.4, 0.18, 0.6)

var _decal: MeshInstance3D       # 베이스 레인(전체 길이·연한 색)
var _mat: StandardMaterial3D
var _fill: MeshInstance3D        # 차오름(중심→끝, windup 진행도만큼)
var _fill_mat: StandardMaterial3D

## set_lane 가 매 프레임 갱신하는 레인 길이/폭 — set_fill 이 fill 길이 계산에 재사용.
var _lane_length: float = 1.0
var _lane_width: float = 1.0
## windup 진행도(0=전조 시작 → 1=돌진 발사 순간). Boss 가 매 프레임 갱신.
var _fill_frac: float = 0.0


func _ready() -> void:
	add_to_group("charge_telegraphs")
	_decal = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 0.06, 1.0)  # local +X=길이, +Z=폭 (set_lane 이 scale)
	_decal.mesh = box
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = homing_color
	_mat.emission_enabled = true
	_mat.emission = Color(homing_color.r, homing_color.g, homing_color.b)
	_mat.emission_energy_multiplier = 1.0
	_mat.no_depth_test = true
	_decal.material_override = _mat
	add_child(_decal)

	# fill — 베이스 레인 위에 살짝 띄워 중심(보스 발치)에서 끝쪽으로 차오른다.
	_fill = MeshInstance3D.new()
	var fbox := BoxMesh.new()
	fbox.size = Vector3(1.0, 0.06, 1.0)
	_fill.mesh = fbox
	_fill_mat = StandardMaterial3D.new()
	_fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fill_mat.albedo_color = fill_color
	_fill_mat.emission_enabled = true
	_fill_mat.emission = Color(fill_color.r, fill_color.g, fill_color.b)
	_fill_mat.emission_energy_multiplier = 1.6
	_fill_mat.no_depth_test = true
	_fill.material_override = _fill_mat
	add_child(_fill)
	_apply_fill()


## 레인 배치 — origin(보스 발치)에서 dir 방향으로 length 만큼, width 폭. 바닥에 납작.
func set_lane(origin: Vector3, dir: Vector3, width: float, length: float) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3(1, 0, 0)
	flat = flat.normalized()
	# 레인 중심 = origin + 진행방향 × 길이/2. 살짝 띄워 z-fighting 방지.
	global_position = Vector3(origin.x, 0.07, origin.z) + flat * (length * 0.5)
	var yaw := atan2(-flat.z, flat.x)
	rotation = Vector3(0.0, yaw, 0.0)
	_decal.scale = Vector3(length, 1.0, width)
	_lane_length = length
	_lane_width = width
	# 레인이 매 프레임 재배치/재조준되므로 fill 도 같이 갱신(호밍 추종).
	_apply_fill()


## windup 진행도(0~1)를 받아 fill 이 중심→끝으로 차오르는 비율을 정한다.
## Boss 가 _state_windup 에서 매 프레임 호출(전조 시작 0% → 발사 순간 100%).
func set_fill(frac: float) -> void:
	_fill_frac = clampf(frac, 0.0, 1.0)
	_apply_fill()


## fill 박스를 레인의 보스쪽 끝(local −X)에서 길이×frac 만큼 차지하도록 배치.
## 레인 부모 좌표: 중심=원점, +X=진행방향. 보스 발치는 local x = −length/2.
func _apply_fill() -> void:
	if _fill == null:
		return
	var fill_len: float = maxf(_lane_length * _fill_frac, 0.0001)
	_fill.scale = Vector3(fill_len, 1.0, _lane_width)
	# 보스쪽 끝(−length/2)에 정렬 → 중심으로 자라 보이게 fill 중심을 −length/2 + fill_len/2.
	_fill.position = Vector3(-_lane_length * 0.5 + fill_len * 0.5, 0.02, 0.0)


## 호밍 종료 — 색을 진하게 고정(곧 돌진). fill 도 꽉 채운다.
func lock() -> void:
	if _mat != null:
		_mat.albedo_color = lock_color
		_mat.emission = Color(lock_color.r, lock_color.g, lock_color.b)
		_mat.emission_energy_multiplier = 2.2
	_fill_frac = 1.0
	_apply_fill()
