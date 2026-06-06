class_name LeapTelegraph
extends Node3D

## 근접 몬스터 리프(내려찍기) 어택의 빨간 원형 데칼 텔레그래프.
## 착지 지점에 빨간 원형 위험 구역(zone)을 깔고, 그 위로 안쪽 채움(fill)이
## windup 동안 0→꽉참 으로 커진다. fill 이 가장자리에 닿는 순간(=몬스터 착지)
## 원 반경 안의 PC 를 포인트 체크해 데미지를 준다. FanTelegraph 와 동일한
## "spawn-and-forget" 패턴 — 몬스터가 죽거나 움직여도 바닥 약속은 유지된다.
##
## 데미지 판정 방식은 FanTelegraph 와 동일하게 단일 포인트 체크(Area3D 미사용 —
## Jolt ref-count 경고 회피).

@export var radius: float = 2.2
@export var damage: int = 1
## 데칼 등장 → 슬램까지 시간(초). 몬스터 리프 이동 시간과 맞춘다.
@export var windup: float = 0.7
@export var zone_color: Color = Color(0.92, 0.15, 0.15, 0.34)
@export var fill_color: Color = Color(1.0, 0.32, 0.2, 0.55)
@export var ground_y_offset: float = 0.05

var _zone: MeshInstance3D
var _fill: MeshInstance3D
var _fill_mat: StandardMaterial3D
var _zone_mat: StandardMaterial3D
var _consumed: bool = false


## 호출부가 위치/반경/데미지/윈드업을 정하고 add 한다. (pre/post tree 모두 안전.)
func configure(center_pos: Vector3, p_radius: float, p_damage: int, p_windup: float) -> void:
	radius = max(p_radius, 0.1)
	damage = max(p_damage, 0)
	windup = max(p_windup, 0.05)
	global_position = Vector3(center_pos.x, center_pos.y + ground_y_offset, center_pos.z)
	if _zone != null:
		_zone.mesh = _make_disc_mesh(radius)
	if _fill != null:
		_fill.mesh = _make_disc_mesh(radius)


func _ready() -> void:
	_zone = MeshInstance3D.new()
	_zone_mat = _make_mat(zone_color)
	_zone.material_override = _zone_mat
	_zone.mesh = _make_disc_mesh(radius)
	add_child(_zone)

	_fill = MeshInstance3D.new()
	_fill_mat = _make_mat(fill_color)
	_fill.material_override = _fill_mat
	_fill.mesh = _make_disc_mesh(radius)
	_fill.position = Vector3(0, 0.01, 0)
	_fill.scale = Vector3(0.001, 1.0, 0.001)
	add_child(_fill)

	# fill 이 windup 동안 0 → 1 로 커지며 "슬램 임박"을 알린다.
	var t := create_tween()
	t.tween_property(_fill, "scale", Vector3(1.0, 1.0, 1.0), windup)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	get_tree().create_timer(windup).timeout.connect(_slam)


func _make_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = c
	return m


## 평평한 원판(triangle fan, 로컬 XZ 평면). FanTelegraph 의 부채 빌더를 360°로.
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


func _slam() -> void:
	if _consumed:
		return
	# 착지 순간 데미지 판정 (반경 안의 PC). FanTelegraph 와 같은 단일 포인트 체크.
	var tree := get_tree()
	if tree != null:
		var pc := tree.get_first_node_in_group("player")
		if pc != null and is_instance_valid(pc) and pc is Node3D and pc.has_method("take_hit"):
			var d: Vector3 = (pc as Node3D).global_position - global_position
			d.y = 0.0
			if d.length() <= radius:
				pc.call("take_hit", damage)
	# 슬램 플래시 — 잠깐 밝게 부풀렸다 페이드.
	if _fill_mat != null:
		_fill_mat.albedo_color = Color(1.0, 0.95, 0.85, 0.85)
	var ft := create_tween()
	ft.set_parallel(true)
	if _fill != null:
		ft.tween_property(_fill, "scale", Vector3(1.15, 1.0, 1.15), 0.08)
	_fade_and_free()


## 리프 도중 몬스터가 죽으면 호출 — 데미지 없이 사라진다.
func cancel() -> void:
	if _consumed:
		return
	_consumed = true
	var t := create_tween()
	t.set_parallel(true)
	if _zone_mat != null:
		t.tween_property(_zone_mat, "albedo_color:a", 0.0, 0.12)
	if _fill_mat != null:
		t.tween_property(_fill_mat, "albedo_color:a", 0.0, 0.12)
	t.chain().tween_callback(queue_free)


func _fade_and_free() -> void:
	if _consumed:
		return
	_consumed = true
	var t := create_tween()
	t.set_parallel(true)
	if _zone_mat != null:
		t.tween_property(_zone_mat, "albedo_color:a", 0.0, 0.18)
	if _fill_mat != null:
		t.tween_property(_fill_mat, "albedo_color:a", 0.0, 0.18)
	t.chain().tween_callback(queue_free)
