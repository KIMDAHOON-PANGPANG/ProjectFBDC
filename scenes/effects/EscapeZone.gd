extends Node3D

## 탈출 불가구역 — PC 만 경계 안으로 클램프(몹은 자유 출입).
## 보스가 경계 밖에 boss_escape_delay 초 이상 있으면 구역 중앙으로 강제 텔레포트.
## 코드 인라인 노드(MeshInstance3D)로 구성 — .tscn 없음.

@export var half_extent: float = 12.5
@export var boss_escape_delay: float = 3.0
@export var boss_teleport_margin: float = 1.5
@export var zone_color: Color = Color(0.95, 0.18, 0.14, 0.22)

var _center: Vector3 = Vector3.ZERO
var _decal: MeshInstance3D
var _mat: StandardMaterial3D
var _boss_out_t: Dictionary = {}


func _ready() -> void:
	add_to_group("escape_zones")
	_decal = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 0.06, 1.0)
	_decal.mesh = box
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = zone_color
	_mat.emission_enabled = true
	_mat.emission = Color(zone_color.r, zone_color.g, zone_color.b)
	_mat.emission_energy_multiplier = 1.0
	_mat.no_depth_test = true
	_decal.material_override = _mat
	add_child(_decal)
	_decal.scale = Vector3(half_extent * 2.0, 1.0, half_extent * 2.0)


func setup(center: Vector3) -> void:
	_center = Vector3(center.x, 0.07, center.z)
	global_position = _center
	_boss_out_t.clear()


func _physics_process(delta: float) -> void:
	# (A) PC 클램프 — player 그룹만, 몹은 클램프 안 함.
	for p in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(p) or not (p is Node3D):
			continue
		var gp: Vector3 = (p as Node3D).global_position
		var cx: float = clampf(gp.x, _center.x - half_extent, _center.x + half_extent)
		var cz: float = clampf(gp.z, _center.z - half_extent, _center.z + half_extent)
		if cx != gp.x or cz != gp.z:
			(p as Node3D).global_position = Vector3(cx, gp.y, cz)

	# (B) 보스 텔레포트 — boss 그룹이 N초 이상 경계 밖이면 중앙으로 강제 복귀.
	for b in get_tree().get_nodes_in_group("boss"):
		if not is_instance_valid(b) or not (b is Node3D):
			continue
		if "_dead" in b and b._dead:
			_boss_out_t.erase(b.get_instance_id())
			continue
		var bp: Vector3 = (b as Node3D).global_position
		var outside: bool = absf(bp.x - _center.x) > half_extent or absf(bp.z - _center.z) > half_extent
		var bid: int = b.get_instance_id()
		if outside:
			_boss_out_t[bid] = float(_boss_out_t.get(bid, 0.0)) + delta
			if _boss_out_t[bid] >= boss_escape_delay:
				(b as Node3D).global_position = Vector3(_center.x, bp.y, _center.z)
				_boss_out_t[bid] = 0.0
		else:
			_boss_out_t.erase(bid)
