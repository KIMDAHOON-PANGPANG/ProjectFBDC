extends Node3D

## 난장도깨비패(SUMMON_CLONE) 도깨비 분신 — 도깨비 소환. 금황 반투명 구체 분신.
## PC 곁을 따라다니다(오프셋 유지) 주기적으로 PC 조준 방향으로 베어 근처 적을 타격.
## class_name 없음 — BoonExecutor 가 preload + .new() 로 인스턴스, init_clone 덕타이핑.
## 그룹 boon_clone + lifetime 으로 누수 방지(스폰 측 동시 상한도 적용).

const GOLD := Color(1.0, 0.76, 0.2)

var _player: Node = null
var _lifetime: float = 6.0
var _range: float = 3.0
var _damage: int = 1
var _offset: Vector3 = Vector3(1.2, 0.9, 0.0)
var _t: float = 0.0
var _slash_cd: float = 0.0
var _slash_interval: float = 1.0
var _dead: bool = false
var _mat: StandardMaterial3D


func init_clone(player: Node, params: Dictionary, slot_angle: float) -> void:
	_player = player
	_lifetime = maxf(float(params.get("lifetime", 6.0)), 0.5)
	_range = maxf(float(params.get("range", 3.0)), 0.5)
	_damage = int(params.get("damage", 1))
	# 분신마다 PC 주변 다른 각도에 자리잡음.
	var r := 1.3
	_offset = Vector3(cos(slot_angle) * r, 0.9, sin(slot_angle) * r)
	if _player is Node3D:
		global_position = (_player as Node3D).global_position + _offset
	_build_visual()


func _build_visual() -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.28
	sm.height = 0.56
	mi.mesh = sm
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.55)
	_mat.emission_enabled = true
	_mat.emission = GOLD
	_mat.emission_energy_multiplier = 2.0
	mi.material_override = _mat
	add_child(mi)


func _process(delta: float) -> void:
	if _dead:
		return
	if _player == null or not is_instance_valid(_player) or not (_player is Node3D):
		queue_free()
		return
	_t += delta
	if _t >= _lifetime:
		_fade()
		return
	# PC 따라붙기(부드럽게).
	var want: Vector3 = (_player as Node3D).global_position + _offset
	global_position = global_position.lerp(want, clampf(delta * 8.0, 0.0, 1.0))
	# 주기적 베기.
	_slash_cd -= delta
	if _slash_cd <= 0.0:
		_slash_cd = _slash_interval
		_do_slash()


func _do_slash() -> void:
	# PC 조준 방향(_aim_dir)으로 전방 부채 베기 — 사거리·반경 안 적 타격.
	var aim: Vector3 = Vector3(1, 0, 0)
	var av = _player.get("_aim_dir")
	if av is Vector3 and (av as Vector3).length_squared() > 0.0001:
		aim = (av as Vector3).normalized()
	var origin: Vector3 = global_position
	var hit_any := false
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node3D) or e.is_in_group("boss"):
			continue
		var to_e: Vector3 = (e as Node3D).global_position - origin
		to_e.y = 0.0
		var d: float = to_e.length()
		if d > _range or d < 0.05:
			continue
		# 전방 반각 ~70도 안만.
		if aim.dot(to_e.normalized()) < 0.34:
			continue
		if e.has_method("take_hit"):
			e.call("take_hit", _damage)
			hit_any = true
	_spawn_slash_vfx(origin, aim)
	if not hit_any:
		pass


func _spawn_slash_vfx(origin: Vector3, aim: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(_range, 0.06, 0.5)
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.6)
	m.emission_enabled = true
	m.emission = GOLD
	m.emission_energy_multiplier = 2.2
	mi.material_override = m
	add_child(mi)
	mi.position = aim * (_range * 0.5)
	mi.position.y = 0.0
	mi.rotation = Vector3(0.0, atan2(-aim.z, aim.x), 0.0)
	var t := mi.create_tween()
	t.tween_property(m, "albedo_color:a", 0.0, 0.18)
	t.tween_callback(mi.queue_free)


func _fade() -> void:
	if _dead:
		return
	_dead = true
	if _mat != null:
		var t := create_tween()
		t.tween_property(_mat, "albedo_color:a", 0.0, 0.25)
		t.tween_callback(queue_free)
	else:
		queue_free()
