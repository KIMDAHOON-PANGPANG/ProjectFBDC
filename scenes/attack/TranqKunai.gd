extends Node3D

## 마취 비도 — "게임 시작 2" 우클릭(RMB)으로 던지는 곡사(포물선) 투사체.
## 커서 방향 목표 지점으로 포물선을 그리며 날아가 착탄 시 범위 안의 모든 적을
## force_stagger(스턴)시킨다. 데미지는 없고 마취(정지)만. 하데스 캐스트(1/1)식.
##
## 물리 충돌 없이 시간 보간으로 이동(곡사) → 착탄 시 그룹 질의로 AOE 스턴.
## Player._fire_tranq 가 configure() 로 시작/도착/범위/스턴시간/곡사 파라미터를 넣는다.

var _start: Vector3 = Vector3.ZERO
var _end: Vector3 = Vector3.ZERO
var _t: float = 0.0
var _landed: bool = false

var travel_time: float = 0.6
var arc_height: float = 3.5
var radius: float = 3.0
var stun: float = 3.0

var _dart: MeshInstance3D


## add_child 전/직후 호출 — 시작/도착 지점(월드)과 범위/스턴/곡사 파라미터 주입.
func configure(from: Vector3, to: Vector3, p_radius: float, p_stun: float, p_arc: float, p_time: float) -> void:
	_start = from
	_end = to
	radius = max(p_radius, 0.1)
	stun = max(p_stun, 0.0)
	arc_height = p_arc
	travel_time = max(p_time, 0.05)
	# global_position 은 _ready(트리 진입 후)에서 설정 — configure 는 add_child 전에
	# 불릴 수 있어 여기서 global_* 를 만지면 !is_inside_tree 경고가 난다.


func _ready() -> void:
	add_to_group("tranq_darts")
	global_position = _start  # configure 가 미뤄둔 시작 위치를 트리 진입 후 적용.
	_dart = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.55, 0.13, 0.13)
	_dart.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.5, 0.85, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.8, 1.0)
	mat.emission_energy_multiplier = 1.8
	_dart.material_override = mat
	add_child(_dart)


func _process(delta: float) -> void:
	if _landed:
		return
	_t += delta
	var k: float = clamp(_t / travel_time, 0.0, 1.0)
	# 포물선 — 수평 보간 + sin 정점(중간에서 최고). 착탄 시 정확히 _end.
	var pos: Vector3 = _start.lerp(_end, k)
	pos.y += sin(k * PI) * arc_height
	global_position = pos
	# 진행 방향으로 다트 기울임(상승→하강 피치).
	var look: Vector3 = _end - _start
	look.y = 0.0
	if look.length_squared() > 0.0001:
		var yaw: float = atan2(-look.z, look.x)
		var pitch: float = cos(k * PI) * 0.7  # k<0.5 상승(+) → k>0.5 하강(-)
		rotation = Vector3(pitch, yaw, 0.0)
	if k >= 1.0:
		_land()


func _land() -> void:
	if _landed:
		return
	_landed = true
	global_position = Vector3(_end.x, _end.y, _end.z)
	_apply_stun()
	_spawn_aoe_vfx()
	if _dart != null:
		_dart.visible = false
	# AOE 연출이 끝난 뒤 정리.
	get_tree().create_timer(0.7).timeout.connect(queue_free)


## 착탄 범위 안의 모든 적을 스턴 — HealthComponent.force_stagger 재사용(모든 적 공통).
func _apply_stun() -> void:
	var hit := {}
	for grp in ["enemies", "boss"]:
		for e in get_tree().get_nodes_in_group(grp):
			if not is_instance_valid(e) or hit.has(e) or not (e is Node3D):
				continue
			if "_dead" in e and e._dead:
				continue
			var d: Vector3 = (e as Node3D).global_position - global_position
			d.y = 0.0
			if d.length() > radius:
				continue
			hit[e] = true
			var hc = e.get_node_or_null("HealthComponent")
			if hc != null and hc.has_method("force_stagger"):
				hc.call("force_stagger", stun)


## 바닥에 퍼지는 청록 원반 — 범위(radius)까지 커지며 페이드.
func _spawn_aoe_vfx() -> void:
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 0.06
	disc.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.4, 0.85, 1.0, 0.5)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.85, 1.0)
	mat.emission_energy_multiplier = 1.5
	disc.material_override = mat
	disc.position = Vector3(0, 0.06, 0)
	disc.scale = Vector3(0.1, 1.0, 0.1)
	add_child(disc)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(disc, "scale", Vector3(radius, 1.0, radius), 0.35)
	t.tween_property(mat, "albedo_color:a", 0.0, 0.65)
