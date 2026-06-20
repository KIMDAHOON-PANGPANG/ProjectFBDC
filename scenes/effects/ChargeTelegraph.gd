extends Node3D

## 보스 돌진 텔레그래프 — 보스 발치에서 PC 방향으로 길게 뻗는 직사각형 데칼(돌진 레인).
## 호밍 동안 보스가 매 프레임 set_lane() 으로 방향을 갱신(PC 추적), lock() 시 색이
## 진해지며 고정된다. 이 노드는 순수 비주얼 — 보스가 소유·구동하고 돌진 끝나면 free.

@export var homing_color: Color = Color(0.95, 0.25, 0.2, 0.32)  # 호밍(연한 빨강)
@export var lock_color: Color = Color(1.0, 0.32, 0.16, 0.72)    # 고정(진한 빨강)

var _decal: MeshInstance3D
var _mat: StandardMaterial3D


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


## 호밍 종료 — 색을 진하게 고정(곧 돌진).
func lock() -> void:
	if _mat == null:
		return
	_mat.albedo_color = lock_color
	_mat.emission = Color(lock_color.r, lock_color.g, lock_color.b)
	_mat.emission_energy_multiplier = 2.2
