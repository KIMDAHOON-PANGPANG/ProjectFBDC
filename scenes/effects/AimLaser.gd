class_name AimLaser
extends Node3D

## 원거리 적의 사격 텔레그래프 (가시성 우선).
## PC 로 향하는 흰색 더미 라인이 연결되고, 그 라인이 **중심부에서 바깥으로** 빨간색으로
## 0→100% 차오른다. 100% 도달 순간 흰 플래시가 번쩍하고 곧바로 화살이 발사된다.
## (이전: 흰→빨강 2단계 phase. 지금: 연속 fill + flash 로 "차오름"이 한눈에 읽힘.)
##
## 모든 원거리 적/보스/터렛이 재사용하는 공유 컴포넌트. 호출 측(RangedEnemy):
##     var laser = aim_laser_scene.instantiate()
##     scene.add_child(laser)
##     laser.configure(shooter, target, arrow_scene, arrow_speed)

## 라인이 100% 차오르기까지(=발사까지) 걸리는 시간(초). 이 동안 PC 가 피할 수 있다.
@export var lock_duration: float = 1.0
## 100% 도달 후 발사 직전 흰 플래시 지속(초).
@export var flash_duration: float = 0.09

@export var beam_thickness: float = 0.05
## 빨강 fill 이 흰 라인보다 굵은 배수(흰 라인 위로 확실히 덮여 보이게).
@export var fill_thickness_mult: float = 1.5

## 흰색 더미 라인 색 — 차오르는 동안 항상 흰색 유지.
@export var aim_color: Color = Color(1.0, 1.0, 1.0, 0.5)
## 중심에서 바깥으로 차오르는 빨강 fill 색.
@export var fill_color: Color = Color(1.0, 0.18, 0.18, 0.95)
## 100% 순간 플래시 색(흰 번쩍).
@export var flash_color: Color = Color(1.0, 1.0, 1.0, 1.0)

@export var aim_emission_energy: float = 0.4
@export var fill_emission_energy: float = 1.7

var _shooter: Node3D
var _target: Node3D
var _arrow_scene: PackedScene
var _arrow_speed: float = 13.2
var _elapsed: float = 0.0
var _consumed: bool = false
## < 0 이면 아직 차오르는 중. >= 0 이면 100% 도달 후 플래시 경과 시간.
var _flash_t: float = -1.0
var _beam: MeshInstance3D            # 흰 더미 라인(풀 길이)
var _fill: MeshInstance3D            # 빨강 fill(중심→바깥)
var _fill_mat: StandardMaterial3D
var _last_dir: Vector3 = Vector3(1, 0, 0)


func configure(shooter: Node3D, target: Node3D, arrow_scene: PackedScene, arrow_speed: float) -> void:
	_shooter = shooter
	_target = target
	_arrow_scene = arrow_scene
	_arrow_speed = arrow_speed


func _ready() -> void:
	add_to_group("aim_lasers")
	# 흰 더미 라인 — 항상 흰색, 풀 길이. 부모 원점(=PC↔적 중점)에 중심을 둔다.
	_beam = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.0, beam_thickness, beam_thickness)
	_beam.mesh = box
	var wm := StandardMaterial3D.new()
	wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.emission_enabled = true
	wm.albedo_color = aim_color
	wm.emission = aim_color
	wm.emission_energy_multiplier = aim_emission_energy
	_beam.material_override = wm
	add_child(_beam)
	# 빨강 fill — 중심(부모 원점)에서 바깥으로 대칭으로 차오른다. 흰 라인 위에 그려지게
	# no_depth_test + 약간 굵게. 시작은 길이 0(거의).
	_fill = MeshInstance3D.new()
	var fbox := BoxMesh.new()
	var ft: float = beam_thickness * fill_thickness_mult
	fbox.size = Vector3(1.0, ft, ft)
	_fill.mesh = fbox
	_fill_mat = StandardMaterial3D.new()
	_fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fill_mat.emission_enabled = true
	_fill_mat.no_depth_test = true
	_fill_mat.albedo_color = fill_color
	_fill_mat.emission = fill_color
	_fill_mat.emission_energy_multiplier = fill_emission_energy
	_fill.material_override = _fill_mat
	_fill.scale = Vector3(0.001, 1.0, 1.0)
	add_child(_fill)


func _process(delta: float) -> void:
	if _consumed:
		return
	if _shooter == null or not is_instance_valid(_shooter):
		queue_free()
		return
	if _target == null or not is_instance_valid(_target):
		queue_free()
		return

	# 위치/회전/길이 — PC 를 향해 추적. 중점에 배치, local +X 가 PC 를 향함.
	var from: Vector3 = (_shooter as Node3D).global_position + Vector3(0, 0.6, 0)
	var to: Vector3 = (_target as Node3D).global_position + Vector3(0, 0.6, 0)
	var diff: Vector3 = to - from
	var len: float = max(diff.length(), 0.01)
	_last_dir = diff.normalized()
	global_position = (from + to) * 0.5
	var yaw: float = atan2(-diff.z, diff.x)
	rotation = Vector3(0.0, yaw, 0.0)
	_beam.scale = Vector3(len, 1.0, 1.0)  # 흰 라인은 항상 풀 길이.

	_elapsed += delta

	if _flash_t < 0.0:
		# 차오르는 중 — 빨강 fill 이 **몬스터 쪽 끝(local -X)에서 PC(+X)** 로 차오른다.
		# (이전: 중심에서 좌우 대칭 → "흩어짐". 이제 시작점=몬스터, 끝=PC 로 방향성.)
		var ratio: float = clamp(_elapsed / max(lock_duration, 0.0001), 0.0, 1.0)
		var fill_len: float = max(len * ratio, 0.001)
		_fill.position = Vector3(-len * 0.5 + fill_len * 0.5, 0.0, 0.0)
		_fill.scale = Vector3(fill_len, 1.0, 1.0)
		if ratio >= 1.0:
			# 100% — 라인 전체가 흰색으로 순간 번쩍(플래시) 후 발사.
			_flash_t = 0.0
			_fill.position = Vector3.ZERO
			_fill.scale = Vector3(len, 1.0, 1.0)
			_fill_mat.albedo_color = flash_color
			_fill_mat.emission = flash_color
			_fill_mat.emission_energy_multiplier = 3.5
	else:
		_flash_t += delta
		if _flash_t >= flash_duration:
			_fire_arrow(from)


func _fire_arrow(from: Vector3) -> void:
	if _consumed:
		return
	_consumed = true
	if _arrow_scene != null:
		var arrow = _arrow_scene.instantiate()
		# Speed override + bullet-time inheritance (shooter carries the slow).
		arrow.speed = _arrow_speed
		if _shooter and "time_scale_mult" in _shooter and "time_scale_mult" in arrow:
			arrow.time_scale_mult = _shooter.time_scale_mult
		# Host = active scene; during a scene reload current_scene is briefly
		# null, so fall back to our parent / tree root rather than crashing.
		var tree := get_tree()
		var host: Node = null
		if tree != null:
			host = tree.current_scene if tree.current_scene != null else (get_parent() if get_parent() != null else tree.root)
		if host == null:
			arrow.queue_free()
			queue_free()
			return
		host.add_child(arrow)
		if arrow.has_method("launch"):
			arrow.call("launch", _last_dir, from + _last_dir * 0.5)
	queue_free()


## 호환용 — fill 이 절반 이상 찼으면 "곧 발사" 단계로 본다(이전 red phase 대체).
func is_in_red_phase() -> bool:
	return _elapsed >= lock_duration * 0.5
