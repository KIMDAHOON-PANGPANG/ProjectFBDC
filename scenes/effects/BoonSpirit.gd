extends Node3D

## 야호분혼(SUMMON_SPIRIT) 분혼 정령 — 구미호 소환. 핑크 구체 + 트레일.
## 표식(holrim_marks>0) 적을 우선 호밍·충돌 격추, 없으면 최근접 적. 수명 후 자가 free.
## class_name 없음 — BoonExecutor 가 preload + .new() 로 인스턴스, init_spirit 덕타이핑.
## 그룹 boon_spirit + lifetime 으로 누수 방지(스폰 측 동시 상한도 적용).

const PINK := Color(1.0, 0.37, 0.69)

var _speed: float = 7.0
var _lifetime: float = 5.0
var _radius: float = 0.9
var _t: float = 0.0
var _dead: bool = false


func init_spirit(pos: Vector3, params: Dictionary) -> void:
	_speed = float(params.get("speed", 7.0))
	_lifetime = float(params.get("lifetime", 5.0))
	_radius = maxf(float(params.get("radius", 0.9)), 0.3)
	global_position = pos
	_build_visual()


func _build_visual() -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.18
	sm.height = 0.36
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = PINK
	m.emission_enabled = true
	m.emission = PINK
	m.emission_energy_multiplier = 2.5
	mi.material_override = m
	add_child(mi)
	var trail := CPUParticles3D.new()
	trail.amount = 14
	trail.lifetime = 0.4
	trail.local_coords = false
	trail.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	trail.emission_sphere_radius = 0.1
	trail.direction = Vector3(0, 1, 0)
	trail.spread = 30.0
	trail.initial_velocity_min = 0.1
	trail.initial_velocity_max = 0.4
	trail.gravity = Vector3.ZERO
	trail.scale_amount_min = 0.05
	trail.scale_amount_max = 0.1
	var tq := QuadMesh.new()
	tq.size = Vector2(0.12, 0.12)
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	tm.albedo_color = Color(PINK.r, PINK.g, PINK.b, 0.7)
	tm.emission_enabled = true
	tm.emission = PINK
	tm.emission_energy_multiplier = 1.8
	tq.material = tm
	trail.mesh = tq
	trail.emitting = true
	add_child(trail)


func _process(delta: float) -> void:
	if _dead:
		return
	_t += delta
	if _t >= _lifetime:
		queue_free()
		return
	var tgt := _find_marked()
	if tgt == null:
		tgt = _find_nearest()
	if tgt == null:
		return
	var to_t: Vector3 = (tgt as Node3D).global_position + Vector3(0, 0.9, 0) - global_position
	var d: float = to_t.length()
	if d <= _radius:
		_hit(tgt)
		return
	global_position += to_t.normalized() * _speed * delta


func _hit(tgt: Node) -> void:
	if _dead:
		return
	_dead = true
	if tgt != null and is_instance_valid(tgt) and tgt.has_method("take_hit") and not tgt.is_in_group("boss"):
		tgt.call("take_hit", 1)
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
	p.gravity = Vector3(0, -2.0, 0)
	p.scale_amount_min = 0.05
	p.scale_amount_max = 0.12
	var qm := QuadMesh.new()
	qm.size = Vector2(0.15, 0.15)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = Color(PINK.r, PINK.g, PINK.b, 0.9)
	m.emission_enabled = true
	m.emission = PINK
	m.emission_energy_multiplier = 2.0
	qm.material = m
	p.mesh = qm
	var tree := p.get_tree()
	if tree != null:
		tree.create_timer(0.7).timeout.connect(p.queue_free)


func _find_marked() -> Node:
	var best: Node = null
	var best_d: float = 99999.0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node3D) or e.is_in_group("boss"):
			continue
		if int(e.get_meta("holrim_marks", 0)) <= 0:
			continue
		var d: float = ((e as Node3D).global_position - global_position).length()
		if d < best_d:
			best_d = d
			best = e
	return best


func _find_nearest() -> Node:
	var best: Node = null
	var best_d: float = 99999.0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node3D) or e.is_in_group("boss"):
			continue
		var d: float = ((e as Node3D).global_position - global_position).length()
		if d < best_d:
			best_d = d
			best = e
	return best
