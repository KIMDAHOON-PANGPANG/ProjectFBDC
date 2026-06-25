extends Node3D

## 익사한동무(SUMMON_DROWNED) 익사령 — 물귀신 소환. 물빛 부유 구체.
## 정지/완보로 부유하며 jet_interval 마다 최근접 적에 물줄기(즉시 레이 take_hit + 젖음) 발사.
## pulse_pull 로 주변 적을 약하게 끌어들임. lifetime 후 자가 free.
## class_name 없음 — BoonExecutor 가 preload + .new() 로 인스턴스, init_drowned 덕타이핑.
## ⚠ 적 대상 전용(보스 제외) · PC 무관 · 그룹 boon_spirit + lifetime 으로 누수 방지.

const WATER := Color(0.184, 0.624, 0.878)

var _lifetime: float = 5.0
var _jet_interval: float = 1.0
var _jet_speed: float = 14.0
var _jet_damage: int = 1
var _pulse_pull: float = 1.5
var _wet_add: int = 1
var _pull_radius: float = 4.0
var _jet_range: float = 9.0
var _tint: Color = WATER

var _t: float = 0.0
var _jet_t: float = 0.0
var _dead: bool = false
var _bob_phase: float = 0.0
var _base_y: float = 0.0


func init_drowned(pos: Vector3, params: Dictionary) -> void:
	_lifetime = float(params.get("lifetime", 5.0))
	_jet_interval = maxf(float(params.get("jet_interval", 1.0)), 0.2)
	_jet_speed = float(params.get("jet_speed", 14.0))
	_jet_damage = int(params.get("jet_damage", 1))
	_pulse_pull = float(params.get("pulse_pull", 1.5))
	_wet_add = int(params.get("wet_add", 1))
	if params.get("tint") is Color:
		_tint = params.get("tint")
	global_position = pos
	_base_y = pos.y
	_bob_phase = randf() * TAU
	_jet_t = _jet_interval * 0.5
	_build_visual()


func _build_visual() -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.22
	sm.height = 0.44
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(_tint.r, _tint.g, _tint.b, 0.85)
	m.emission_enabled = true
	m.emission = _tint
	m.emission_energy_multiplier = 2.6
	mi.material_override = m
	add_child(mi)
	var trail := CPUParticles3D.new()
	trail.amount = 12
	trail.lifetime = 0.5
	trail.local_coords = false
	trail.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	trail.emission_sphere_radius = 0.14
	trail.direction = Vector3(0, 1, 0)
	trail.spread = 20.0
	trail.initial_velocity_min = 0.1
	trail.initial_velocity_max = 0.4
	trail.gravity = Vector3(0, 0.3, 0)
	trail.scale_amount_min = 0.05
	trail.scale_amount_max = 0.1
	var tq := QuadMesh.new()
	tq.size = Vector2(0.12, 0.12)
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	tm.albedo_color = Color(_tint.r, _tint.g, _tint.b, 0.55)
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
	# 부유 — 제자리 위아래 bob.
	_bob_phase += delta * 2.0
	global_position.y = _base_y + sin(_bob_phase) * 0.15
	# 약 인력 펄스 — 반경 안 적을 살짝 끌어들임(보스 제외).
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node3D) or e.is_in_group("boss"):
			continue
		var to_c: Vector3 = global_position - (e as Node3D).global_position
		to_c.y = 0.0
		var d: float = to_c.length()
		if d <= _pull_radius and d > 0.05:
			if e.has_method("apply_knockback"):
				e.call("apply_knockback", to_c.normalized(), _pulse_pull)
	# 물줄기 발사.
	_jet_t -= delta
	if _jet_t <= 0.0:
		_jet_t = _jet_interval
		_fire_jet()


func _fire_jet() -> void:
	var tgt := _nearest_enemy()
	if tgt == null:
		return
	# 즉시 레이 — 사거리 내면 적중(미니 발사체 대신 즉발, 누수 0).
	var d: float = ((tgt as Node3D).global_position - global_position).length()
	if d > _jet_range:
		return
	if tgt.has_method("take_hit") and not tgt.is_in_group("boss"):
		tgt.call("take_hit", _jet_damage)
		var cur := int(tgt.get_meta("wet_marks", 0))
		tgt.set_meta("wet_marks", cur + _wet_add)
	_spawn_jet_beam((tgt as Node3D).global_position + Vector3(0, 0.6, 0))


## 물줄기 연출 — 익사령 → 적 물빛 라인(짧은 페이드).
func _spawn_jet_beam(to_pos: Vector3) -> void:
	var host := get_parent()
	if host == null:
		return
	var a: Vector3 = global_position
	var diff := to_pos - a
	var length := diff.length()
	if length < 0.1:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(length, 0.07, 0.07)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(_tint.r, _tint.g, _tint.b, 0.8)
	mat.emission_enabled = true
	mat.emission = _tint
	mat.emission_energy_multiplier = 2.4
	mi.material_override = mat
	host.add_child(mi)
	mi.global_position = (a + to_pos) * 0.5
	var yaw := atan2(-diff.z, diff.x)
	mi.rotation = Vector3(0.0, yaw, 0.0)
	var t := mi.create_tween()
	t.tween_property(mat, "albedo_color:a", 0.0, 0.25)
	t.tween_callback(mi.queue_free)


func _nearest_enemy() -> Node:
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
