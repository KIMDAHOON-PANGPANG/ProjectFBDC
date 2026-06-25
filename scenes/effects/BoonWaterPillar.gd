extends Node3D

## 수몰(WATER_PILLAR) 물기둥 연출 — 물귀신 타격. 비주얼 전용(데미지/판정은 BoonExecutor 가 처리).
## 발밑에서 물기둥(세로 박스)이 솟구치며 상승 파티클 + 바닥 링. 0.6s 후 자가 free.
## class_name 없음 — BoonExecutor 가 preload + .new() 로 인스턴스, init_pillar 덕타이핑.

const WATER := Color(0.184, 0.624, 0.878)

var _radius: float = 1.0
var _tint: Color = WATER


func init_pillar(pos: Vector3, radius: float, tint = null) -> void:
	_radius = maxf(radius, 0.5)
	if tint is Color:
		_tint = tint
	global_position = pos
	_build()


func _build() -> void:
	# 솟구치는 물기둥 — 세로 실린더(스케일 트윈으로 솟음).
	var col := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = _radius * 0.5
	cyl.bottom_radius = _radius * 0.7
	cyl.height = 2.4
	col.mesh = cyl
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(_tint.r, _tint.g, _tint.b, 0.5)
	m.emission_enabled = true
	m.emission = _tint
	m.emission_energy_multiplier = 1.8
	col.material_override = m
	add_child(col)
	col.position = Vector3(0, 1.2, 0)
	col.scale = Vector3(0.3, 0.1, 0.3)
	var t := col.create_tween()
	t.set_parallel(true)
	t.tween_property(col, "scale", Vector3(1.0, 1.0, 1.0), 0.18).set_ease(Tween.EASE_OUT)
	t.chain().tween_property(m, "albedo_color:a", 0.0, 0.32)
	# 상승 물보라 파티클.
	var p := CPUParticles3D.new()
	add_child(p)
	p.one_shot = true
	p.emitting = true
	p.amount = 22
	p.lifetime = 0.6
	p.explosiveness = 0.7
	p.direction = Vector3(0, 1, 0)
	p.spread = 25.0
	p.initial_velocity_min = 3.5
	p.initial_velocity_max = 6.5
	p.gravity = Vector3(0, -5.0, 0)
	p.scale_amount_min = 0.06
	p.scale_amount_max = 0.14
	var qm := QuadMesh.new()
	qm.size = Vector2(0.16, 0.16)
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
	# 자가 free.
	var tree := get_tree()
	if tree != null:
		tree.create_timer(0.7).timeout.connect(queue_free)
