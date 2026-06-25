extends Node3D

## 발목잡는손(GRASP_ROOT) 물손 연출 — 물귀신 속박. 비주얼 전용(속박/젖음은 BoonExecutor 가 처리).
## PC 발밑에 물빛 디스크가 퍼지고 상승 파티클(솟구치는 손)이 솟는다. 0.6s 후 자가 free.
## class_name 없음 — BoonExecutor 가 preload + .new() 로 인스턴스, init_grasp 덕타이핑.

const WATER := Color(0.184, 0.624, 0.878)

var _radius: float = 3.0
var _tint: Color = WATER


func init_grasp(pos: Vector3, radius: float, tint = null) -> void:
	_radius = maxf(radius, 0.5)
	if tint is Color:
		_tint = tint
	global_position = Vector3(pos.x, pos.y + 0.06, pos.z)
	_build()


func _build() -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _disc_mesh(_radius)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(_tint.r, _tint.g, _tint.b, 0.42)
	mat.emission_enabled = true
	mat.emission = _tint
	mat.emission_energy_multiplier = 1.5
	mi.material_override = mat
	add_child(mi)
	mi.scale = Vector3(0.1, 1.0, 0.1)
	var t := mi.create_tween()
	t.set_parallel(true)
	t.tween_property(mi, "scale", Vector3(1, 1, 1), 0.16).set_ease(Tween.EASE_OUT)
	t.chain().tween_property(mat, "albedo_color:a", 0.0, 0.34)
	# 솟구치는 물손 — 상승 파티클(여러 갈래).
	var p := CPUParticles3D.new()
	add_child(p)
	p.one_shot = true
	p.emitting = true
	p.amount = 26
	p.lifetime = 0.55
	p.explosiveness = 0.6
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_radius = _radius * 0.7
	p.emission_ring_inner_radius = 0.2
	p.emission_ring_height = 0.1
	p.emission_ring_axis = Vector3(0, 1, 0)
	p.direction = Vector3(0, 1, 0)
	p.spread = 12.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 5.5
	p.gravity = Vector3(0, -6.0, 0)
	p.scale_amount_min = 0.07
	p.scale_amount_max = 0.16
	var qm := QuadMesh.new()
	qm.size = Vector2(0.18, 0.18)
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	pm.albedo_color = Color(_tint.r, _tint.g, _tint.b, 0.9)
	pm.emission_enabled = true
	pm.emission = _tint
	pm.emission_energy_multiplier = 2.0
	qm.material = pm
	p.mesh = qm
	var tree := get_tree()
	if tree != null:
		tree.create_timer(0.7).timeout.connect(queue_free)


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
