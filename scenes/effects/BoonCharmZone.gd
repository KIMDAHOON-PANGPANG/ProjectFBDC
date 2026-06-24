extends Node3D

## 매혹파열(CHARM_ZONE) 결계 — 구미호 권능. 핑크 디스크 + 약한 인력 → 재타격 파열.
## class_name 없음 — BoonExecutor 가 preload + .new() 로 인스턴스, init_zone/burst 덕타이핑.
## 그룹 boon_fx_zone + duration 자체 만료로 누수 방지.

const PINK := Color(1.0, 0.37, 0.69)

var _radius: float = 2.0
var _duration: float = 3.0
var _pull: float = 1.5
var _burst_kb: float = 8.0
var _burst_radius: float = 3.0
var _t: float = 0.0
var _dying: bool = false
var _mat: StandardMaterial3D
var _player: Node = null


func init_zone(center: Vector3, params: Dictionary, player: Node) -> void:
	_radius = maxf(float(params.get("radius", 2.0)), 0.3)
	_duration = maxf(float(params.get("duration", 3.0)), 0.3)
	_pull = float(params.get("pull", 1.5))
	_burst_kb = float(params.get("burst_knockback", 8.0))
	_burst_radius = maxf(float(params.get("burst_radius", 3.0)), 0.3)
	_player = player
	global_position = Vector3(center.x, center.y + 0.06, center.z)
	_build_disc()


func _build_disc() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Disc"
	mi.mesh = _disc_mesh(_radius)
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.albedo_color = Color(PINK.r, PINK.g, PINK.b, 0.36)
	_mat.emission_enabled = true
	_mat.emission = PINK
	_mat.emission_energy_multiplier = 1.4
	mi.material_override = _mat
	add_child(mi)
	mi.scale = Vector3(0.05, 1.0, 0.05)
	var t := create_tween()
	t.tween_property(mi, "scale", Vector3(1, 1, 1), 0.2).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	if _dying:
		return
	_t += delta
	# 인력 — 반경 안 적을 중심으로 약하게 끌어당김(보스 제외).
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node3D):
			continue
		if e.is_in_group("boss"):
			continue
		var to_c: Vector3 = global_position - (e as Node3D).global_position
		to_c.y = 0.0
		var d: float = to_c.length()
		if d <= _radius and d > 0.05:
			if e.has_method("apply_knockback"):
				e.call("apply_knockback", to_c.normalized(), _pull)
	if _t >= _duration:
		_fade()


## 재타격 파열 — 반경 안 적을 바깥으로 강하게 밀치고 버스트.
func burst() -> void:
	if _dying:
		return
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node3D):
			continue
		if e.is_in_group("boss"):
			continue
		var out: Vector3 = (e as Node3D).global_position - global_position
		out.y = 0.0
		if out.length() <= _burst_radius and out.length() > 0.05:
			if e.has_method("apply_knockback"):
				e.call("apply_knockback", out.normalized(), _burst_kb)
	_burst_particles()
	_fade()


func _burst_particles() -> void:
	var p := CPUParticles3D.new()
	add_child(p)
	p.one_shot = true
	p.emitting = true
	p.amount = 24
	p.lifetime = 0.5
	p.explosiveness = 1.0
	p.direction = Vector3(0, 1, 0)
	p.spread = 180.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 7.0
	p.gravity = Vector3(0, -3.0, 0)
	p.scale_amount_min = 0.06
	p.scale_amount_max = 0.15
	var qm := QuadMesh.new()
	qm.size = Vector2(0.2, 0.2)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = Color(PINK.r, PINK.g, PINK.b, 0.95)
	m.emission_enabled = true
	m.emission = PINK
	m.emission_energy_multiplier = 2.2
	qm.material = m
	p.mesh = qm


func _fade() -> void:
	if _dying:
		return
	_dying = true
	if _mat != null:
		var t := create_tween()
		t.tween_property(_mat, "albedo_color:a", 0.0, 0.3)
		t.tween_callback(queue_free)
	else:
		queue_free()


func _disc_mesh(r: float) -> ArrayMesh:
	var segments: int = 28
	var arr := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segments:
		var a0: float = TAU * float(i) / float(segments)
		var a1: float = TAU * float(i + 1) / float(segments)
		var v0 := Vector3(cos(a0) * r, 0.0, sin(a0) * r)
		var v1 := Vector3(cos(a1) * r, 0.0, sin(a1) * r)
		st.set_normal(Vector3.UP); st.add_vertex(Vector3.ZERO)
		st.set_normal(Vector3.UP); st.add_vertex(v1)
		st.set_normal(Vector3.UP); st.add_vertex(v0)
	st.commit(arr)
	return arr
