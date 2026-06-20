extends Node3D

## 주술사(Sorcerer)가 PC 주변에 흩뿌리는 보라색 원형 장판(LoL 모르가나 W 느낌).
## 2단계: ① 전조(precursor) — 흐릿한 원이 중심→바깥으로 점점 채워지며 "곧 깔린다"를 예고
##        ② 발동(active) — 진한 장판 + 안좋은 기운이 솔솔 올라오는 입자(더미 연출) + PC 감속
## 데미지는 없음(순수 동선 방해). 단일 포인트 체크(Area3D 미사용 — Jolt 경고 회피).
## class_name 없이 preload + 덕타이핑으로 인스턴스(헤드리스 캐시 안전).

@export var radius: float = 2.0
@export var duration: float = 3.0           # 발동(진한 장판) 지속
@export var slow_mult: float = 0.45
@export var precursor_time: float = 2.0     # 전조(흐릿하게 채워지는) 시간
@export var precursor_color: Color = Color(0.6, 0.35, 1.0, 0.14)  # 흐릿
@export var active_color: Color = Color(0.5, 0.15, 0.85, 0.44)    # 진한
@export var ground_y_offset: float = 0.06
@export var fade_time: float = 0.45

var _disc: MeshInstance3D
var _mat: StandardMaterial3D
var _aura: CPUParticles3D
var _t: float = 0.0
var _active: bool = false
var _dying: bool = false
var _player: Node3D


## 호출부(Sorcerer)가 중심/반경/지속/감속/전조시간을 정하고 add 한다.
func configure(center_pos: Vector3, p_radius: float, p_duration: float, p_slow: float, p_precursor: float) -> void:
	radius = maxf(p_radius, 0.2)
	duration = maxf(p_duration, 0.2)
	slow_mult = clampf(p_slow, 0.1, 1.0)
	precursor_time = maxf(p_precursor, 0.0)
	global_position = Vector3(center_pos.x, center_pos.y + ground_y_offset, center_pos.z)
	if _disc != null:
		_disc.mesh = _make_disc_mesh(radius)


func _ready() -> void:
	_disc = MeshInstance3D.new()
	_mat = _make_mat(precursor_color)
	_disc.material_override = _mat
	_disc.mesh = _make_disc_mesh(radius)
	add_child(_disc)
	# 전조 — 중심에서 바깥으로 흐릿하게 점점 채워진다(scale 0→1).
	if precursor_time > 0.01:
		_disc.scale = Vector3(0.02, 1.0, 0.02)
		var t := create_tween()
		t.tween_property(_disc, "scale", Vector3(1, 1, 1), precursor_time).set_ease(Tween.EASE_IN)
	else:
		_disc.scale = Vector3(1, 1, 1)
	_player = get_tree().get_first_node_in_group("player")


func _process(delta: float) -> void:
	if _dying:
		return
	_t += delta
	if not _active:
		if _t >= precursor_time:
			_activate()
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	# 발동 중 — PC 가 장판 안이면 매 프레임 짧게 감속 갱신(벗어나면 곧 자연 만료).
	if _player != null and is_instance_valid(_player) and _player.has_method("apply_zone_slow"):
		var d: Vector3 = (_player as Node3D).global_position - global_position
		d.y = 0.0
		if d.length() <= radius:
			_player.call("apply_zone_slow", 0.15, slow_mult)
	if _t >= precursor_time + duration:
		_fade_and_free()


## 전조 → 발동: 진한 색으로 전환 + 살짝 펄스 + 솟아오르는 기운 입자.
func _activate() -> void:
	_active = true
	_disc.scale = Vector3(1, 1, 1)
	if _mat != null:
		_mat.albedo_color = active_color
	var t := create_tween()
	t.tween_property(_disc, "scale", Vector3(1.08, 1.0, 1.08), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_disc, "scale", Vector3(1, 1, 1), 0.18)
	_spawn_aura()


## "안좋은 기운이 솔솔 올라온다" — 보라 입자가 장판 바닥에서 천천히 상승(더미 연출).
func _spawn_aura() -> void:
	_aura = CPUParticles3D.new()
	add_child(_aura)
	_aura.amount = 22
	_aura.lifetime = 1.6
	_aura.local_coords = false
	_aura.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_aura.emission_box_extents = Vector3(radius * 0.85, 0.04, radius * 0.85)
	_aura.direction = Vector3(0, 1, 0)
	_aura.spread = 16.0
	_aura.initial_velocity_min = 0.4
	_aura.initial_velocity_max = 1.1
	_aura.gravity = Vector3(0, 0.5, 0)   # 약하게 위로(솔솔)
	_aura.scale_amount_min = 0.05
	_aura.scale_amount_max = 0.13
	var grad := Gradient.new()
	grad.set_color(0, Color(0.7, 0.45, 1.0, 0.0))
	grad.set_color(1, Color(0.55, 0.2, 0.95, 0.0))
	# 가운데서 잠깐 보였다 사라지게 — 알파 램프(0→불투명→0)는 별도 곡선이 필요하므로
	# 간단히 시작 알파를 약간 주고 끝을 0 으로(올라가며 페이드).
	grad.set_color(0, Color(0.72, 0.45, 1.0, 0.55))
	grad.set_color(1, Color(0.55, 0.2, 0.95, 0.0))
	_aura.color_ramp = grad
	var qm := QuadMesh.new()
	qm.size = Vector2(0.16, 0.16)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.25, 0.9)
	mat.emission_energy_multiplier = 1.2
	qm.material = mat
	_aura.mesh = qm
	_aura.emitting = true


func _fade_and_free() -> void:
	if _dying:
		return
	_dying = true
	if _aura != null:
		_aura.emitting = false
	var t := create_tween()
	if _mat != null:
		t.tween_property(_mat, "albedo_color:a", 0.0, fade_time)
	t.tween_callback(queue_free)


func _make_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = c
	return m


## 평평한 원판(triangle fan, 로컬 XZ 평면).
func _make_disc_mesh(r: float) -> ArrayMesh:
	var segments: int = 32
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
