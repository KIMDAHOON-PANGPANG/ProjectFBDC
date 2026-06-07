extends Node3D

## 근접 기본 공격 스윙 VFX(임시) — 커서 방향 전방 부채꼴이 짧게 번쩍이고 사라진다.
## 데미지 판정은 Player._do_melee_swing 이 처리하고, 이건 시각 피드백만. 모션은
## 추후 교체. Player._spawn_melee_swing 이 add_child 후 configure 호출.

var _mat: StandardMaterial3D


func configure(pos: Vector3, dir: Vector3, p_range: float, p_angle_deg: float) -> void:
	global_position = Vector3(pos.x, pos.y + 0.06, pos.z)
	var d := dir
	d.y = 0.0
	if d.length() < 0.001:
		d = Vector3(1, 0, 0)
	# 로컬 +X 가 커서 방향(SlashAttack/FanTelegraph 와 같은 yaw 규약).
	rotation = Vector3(0.0, atan2(-d.z, d.x), 0.0)
	_build(max(p_range, 0.1), clampf(p_angle_deg, 5.0, 350.0))


func _build(r: float, angle_deg: float) -> void:
	var half: float = deg_to_rad(angle_deg) * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg: int = 20
	for i in seg:
		var a0: float = lerp(-half, half, float(i) / float(seg))
		var a1: float = lerp(-half, half, float(i + 1) / float(seg))
		var v0 := Vector3(cos(a0) * r, 0.0, sin(a0) * r)
		var v1 := Vector3(cos(a1) * r, 0.0, sin(a1) * r)
		st.set_normal(Vector3.UP); st.add_vertex(Vector3.ZERO)
		st.set_normal(Vector3.UP); st.add_vertex(v1)
		st.set_normal(Vector3.UP); st.add_vertex(v0)
	var arr := ArrayMesh.new()
	st.commit(arr)
	var mesh := MeshInstance3D.new()
	mesh.mesh = arr
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.albedo_color = Color(1.0, 0.9, 0.1, 0.55)  # 노란 판정 범위(모션 없는 더미)
	_mat.emission_enabled = true
	_mat.emission = Color(1.0, 0.85, 0.1)
	_mat.emission_energy_multiplier = 1.8
	mesh.material_override = _mat
	add_child(mesh)
	# 판정 범위를 잠깐 보여준 뒤 페이드아웃(모션 추후 교체).
	var t := create_tween()
	t.tween_property(_mat, "albedo_color:a", 0.0, 0.22)
	t.tween_callback(queue_free)
