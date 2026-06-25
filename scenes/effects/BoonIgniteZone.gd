extends Node3D

## 도깨비 금줄(IGNITE_ZONE) 결계 — 도깨비 권능. 금황 결계존: 내부 적 지속 점화 도트 +
## 테두리에서 주기적으로 혼불(BoonFoxfire) 1발을 최근접 적에게 발사.
## class_name 없음 — BoonExecutor 가 preload + .new() 로 인스턴스, init_zone 덕타이핑.
## 그룹 boon_fx_zone + duration 자체 만료로 누수 방지.

const GOLD := Color(1.0, 0.76, 0.2)
const _FoxfireScript := preload("res://scenes/effects/BoonFoxfire.gd")

var _radius: float = 3.0
var _duration: float = 4.0
var _dot_interval: float = 0.5
var _dot_damage: int = 1
var _foxfire_interval: float = 0.8
var _foxfire_speed: float = 12.0
var _t: float = 0.0
var _dot_t: float = 0.0
var _fox_t: float = 0.0
var _dying: bool = false
var _mat: StandardMaterial3D
var _proj_group: String = "boon_proj"
var _proj_cap: int = 24
## 틴트 — 기본 금황(도깨비). params.tint(Color) 로 저승사자 보라(등불/결계) 등 주입.
var _tint: Color = GOLD


func init_zone(center: Vector3, params: Dictionary, proj_group: String, proj_cap: int) -> void:
	_radius = maxf(float(params.get("radius", 3.0)), 0.5)
	_duration = maxf(float(params.get("duration", 4.0)), 0.5)
	_dot_interval = maxf(float(params.get("dot_interval", 0.5)), 0.1)
	_dot_damage = int(params.get("dot_damage", 1))
	_foxfire_interval = maxf(float(params.get("foxfire_interval", 0.8)), 0.2)
	_foxfire_speed = float(params.get("foxfire_speed", 12.0))
	if params.get("tint") is Color:
		_tint = params.get("tint")
	_proj_group = proj_group
	_proj_cap = proj_cap
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
	_mat.albedo_color = Color(_tint.r, _tint.g, _tint.b, 0.32)
	_mat.emission_enabled = true
	_mat.emission = _tint
	_mat.emission_energy_multiplier = 1.5
	mi.material_override = _mat
	add_child(mi)
	mi.scale = Vector3(0.05, 1.0, 0.05)
	var t := create_tween()
	t.tween_property(mi, "scale", Vector3(1, 1, 1), 0.2).set_ease(Tween.EASE_OUT)
	# 테두리 링(가는 금줄 느낌).
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = _radius - 0.08
	tm.outer_radius = _radius
	ring.mesh = tm
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.albedo_color = Color(_tint.r, _tint.g, _tint.b, 0.7)
	rmat.emission_enabled = true
	rmat.emission = _tint
	rmat.emission_energy_multiplier = 2.2
	ring.material_override = rmat
	ring.position.y = 0.02
	add_child(ring)


func _process(delta: float) -> void:
	if _dying:
		return
	_t += delta
	# 점화 도트.
	_dot_t -= delta
	if _dot_t <= 0.0:
		_dot_t = _dot_interval
		_apply_dot()
	# 테두리 혼불 발사.
	_fox_t -= delta
	if _fox_t <= 0.0:
		_fox_t = _foxfire_interval
		_fire_foxfire()
	if _t >= _duration:
		_fade()


func _apply_dot() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node3D) or e.is_in_group("boss"):
			continue
		var to_e: Vector3 = (e as Node3D).global_position - global_position
		to_e.y = 0.0
		if to_e.length() <= _radius:
			if e.has_method("take_hit"):
				e.call("take_hit", _dot_damage)


func _fire_foxfire() -> void:
	var tgt := _nearest_enemy()
	var host := get_parent()
	if host == null:
		return
	if get_tree().get_nodes_in_group(_proj_group).size() >= _proj_cap:
		return
	# 테두리 한 점에서 발사(랜덤 각).
	var ang := randf() * TAU
	var edge: Vector3 = global_position + Vector3(cos(ang) * _radius, 0.9, sin(ang) * _radius)
	var fire_dir := Vector3(1, 0, 0)
	if tgt != null and is_instance_valid(tgt) and tgt is Node3D:
		var to_t: Vector3 = (tgt as Node3D).global_position - edge
		to_t.y = 0.0
		if to_t.length_squared() > 0.0001:
			fire_dir = to_t.normalized()
	var pr := _FoxfireScript.new() as Node3D
	pr.add_to_group(_proj_group)
	host.add_child(pr)
	pr.call("init_proj", edge, fire_dir, {
		"speed": _foxfire_speed, "damage": 1, "radius": 0.8, "tint": _tint,
	}, true, tgt)


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
