extends Node3D

## 수장의올가미(WATER_GRAB) 물올가미 발사체 — 물귀신 권능.
## 가장 먼 적(seed)을 향해 날아가 적중하면 그 적을 PC 앞으로 견인 + 짧은 속박 + 젖음 부여.
## class_name 없음 — BoonExecutor 가 preload + .new() 로 인스턴스, init_grab 덕타이핑.
## ⚠ 적 대상 전용(보스 제외) · PC 는 절대 안 때림 · 그룹 boon_proj + lifetime 으로 누수 방지.

const WATER := Color(0.184, 0.624, 0.878)

var _speed: float = 18.0
var _radius: float = 1.1
var _pull_to_pc: float = 12.0
var _root_duration: float = 1.0
var _wet_add: int = 1
var _tint: Color = WATER

var _player: Node = null
var _seed: Node = null
var _dir: Vector3 = Vector3.FORWARD
var _t: float = 0.0
var _lifetime: float = 2.5
## 단계: 0=비행(적 향함) / 1=견인(PC 앞으로 끌기) / 2=완료.
var _phase: int = 0
var _grabbed: Node = null
var _pull_t: float = 0.0
var _dead: bool = false


func init_grab(pos: Vector3, fire_dir: Vector3, params: Dictionary, player: Node, seed_target) -> void:
	_speed = float(params.get("speed", 18.0))
	_radius = maxf(float(params.get("radius", 1.1)), 0.4)
	_pull_to_pc = float(params.get("pull_to_pc", 12.0))
	_root_duration = float(params.get("root_duration", 1.0))
	_wet_add = int(params.get("wet_add", 1))
	if params.get("tint") is Color:
		_tint = params.get("tint")
	_player = player
	_seed = seed_target
	var fd := Vector3(fire_dir.x, 0.0, fire_dir.z)
	if fd.length_squared() < 0.0001:
		fd = Vector3(1, 0, 0)
	_dir = fd.normalized()
	global_position = pos
	_build_visual()


func _build_visual() -> void:
	# 물올가미 헤드 — 작은 물구체 + 트레일.
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.18
	sm.height = 0.36
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = _tint
	m.emission_enabled = true
	m.emission = _tint
	m.emission_energy_multiplier = 3.0
	mi.material_override = m
	add_child(mi)
	var trail := CPUParticles3D.new()
	trail.amount = 12
	trail.lifetime = 0.35
	trail.local_coords = false
	trail.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	trail.emission_sphere_radius = 0.1
	trail.direction = Vector3(0, 1, 0)
	trail.spread = 25.0
	trail.initial_velocity_min = 0.1
	trail.initial_velocity_max = 0.3
	trail.gravity = Vector3.ZERO
	trail.scale_amount_min = 0.05
	trail.scale_amount_max = 0.1
	var tq := QuadMesh.new()
	tq.size = Vector2(0.12, 0.12)
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	tm.albedo_color = Color(_tint.r, _tint.g, _tint.b, 0.7)
	tm.emission_enabled = true
	tm.emission = _tint
	tm.emission_energy_multiplier = 1.6
	tq.material = tm
	trail.mesh = tq
	trail.emitting = true
	add_child(trail)


func _process(delta: float) -> void:
	if _dead or not is_inside_tree():
		return
	_t += delta
	if _t >= _lifetime:
		queue_free()
		return
	if _phase == 0:
		_fly(delta)
	elif _phase == 1:
		_drag(delta)


func _fly(delta: float) -> void:
	# 시드 적을 향해 호밍.
	var tgt := _resolve_target()
	if tgt != null:
		var to_t: Vector3 = (tgt as Node3D).global_position + Vector3(0, 0.6, 0) - global_position
		to_t.y = 0.0
		if to_t.length() > 0.01:
			_dir = _dir.lerp(to_t.normalized(), clampf(delta * 7.0, 0.0, 1.0)).normalized()
	global_position += _dir * _speed * delta
	# 충돌 검사 — 보스 제외, PC 무관(enemies 그룹만).
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node3D) or e.is_in_group("boss"):
			continue
		var d: float = ((e as Node3D).global_position - global_position).length()
		if d <= _radius:
			_grab(e)
			return


func _grab(e: Node) -> void:
	_grabbed = e
	_phase = 1
	_pull_t = 0.0
	# 젖음 부여.
	var cur := int(e.get_meta("wet_marks", 0))
	e.set_meta("wet_marks", cur + _wet_add)


func _drag(delta: float) -> void:
	if _grabbed == null or not is_instance_valid(_grabbed) or not (_grabbed is Node3D):
		_dead = true
		queue_free()
		return
	if _player == null or not is_instance_valid(_player) or not (_player is Node3D):
		_dead = true
		queue_free()
		return
	_pull_t += delta
	# PC 앞쪽 1.5m 지점으로 견인.
	var pc: Node3D = _player as Node3D
	var aim := Vector3(1, 0, 0)
	var av = _player.get("_aim_dir")
	if av is Vector3 and (av as Vector3).length_squared() > 0.0001:
		aim = (av as Vector3).normalized()
	var dest: Vector3 = pc.global_position + aim * 1.5
	var eg: Node3D = _grabbed as Node3D
	var to_d: Vector3 = dest - eg.global_position
	to_d.y = 0.0
	# apply_knockback 로 PC 쪽으로 강하게 끌어당김(매프레임 갱신 = 견인).
	if to_d.length() > 0.2 and _grabbed.has_method("apply_knockback"):
		_grabbed.call("apply_knockback", to_d.normalized(), _pull_to_pc)
	# 헤드를 적에 붙여 연출.
	global_position = eg.global_position + Vector3(0, 0.6, 0)
	# 견인 후 속박 적용 + 종료(약 0.4s 끌기).
	if _pull_t >= 0.4:
		_grabbed.set_meta("boon_root_until_msec", Time.get_ticks_msec() + int(_root_duration * 1000.0))
		_dead = true
		_burst()
		queue_free()


func _burst() -> void:
	var host := get_parent()
	if host == null:
		return
	var p := CPUParticles3D.new()
	host.add_child(p)
	p.global_position = global_position
	p.one_shot = true
	p.emitting = true
	p.amount = 14
	p.lifetime = 0.4
	p.explosiveness = 1.0
	p.direction = Vector3(0, 1, 0)
	p.spread = 180.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.0
	p.gravity = Vector3(0, -3.0, 0)
	p.scale_amount_min = 0.05
	p.scale_amount_max = 0.12
	var qm := QuadMesh.new()
	qm.size = Vector2(0.15, 0.15)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = Color(_tint.r, _tint.g, _tint.b, 0.9)
	m.emission_enabled = true
	m.emission = _tint
	m.emission_energy_multiplier = 2.0
	qm.material = m
	p.mesh = qm
	var tree := p.get_tree()
	if tree != null:
		tree.create_timer(0.7).timeout.connect(p.queue_free)


func _resolve_target() -> Node:
	if _seed != null and is_instance_valid(_seed) and (_seed is Node3D) and not (_seed as Node).is_in_group("boss"):
		return _seed
	# 시드 소실 시 가장 먼 적 재탐색(원래 의도 = 먼 적 견인).
	var best: Node = null
	var best_d: float = -1.0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node3D) or e.is_in_group("boss"):
			continue
		var d: float = ((e as Node3D).global_position - global_position).length()
		if d > best_d:
			best_d = d
			best = e
	return best
