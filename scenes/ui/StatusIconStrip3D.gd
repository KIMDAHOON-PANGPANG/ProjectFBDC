extends Node3D

## 한 엔티티(적)의 여러 상태 아이콘을 머리 위에 가로로 배치하는 3D 컨테이너.
## class_name 없음 — 적 .gd 가 preload + .new() 로 인스턴스, set_status/clear_status 덕타이핑.
##
## HpBar3D 와 동일한 top_level 팔로우 패턴: 부모 transform 상속 대신 매 프레임
## 부모(_follow_target)의 global_position + follow_offset 로 위치를 직접 박고
## 카메라 basis 를 미러해 빌보드(아이콘 quad 들이 항상 카메라 정면).
##
## API:
##   set_status(key, d)  — key 없으면 StatusIcon3D 새로 add_child, 있으면 set_data 갱신 + 재배치
##   clear_status(key)   — key 아이콘 queue_free + 제거 + 재배치
##   has_status(key)     — bool
##
## 성능: 아이콘은 key 별 1개만 생성/재사용. 폴링 측은 매 프레임 set_status 만 호출(노드 폭증 X).

const _IconScript := preload("res://scenes/ui/StatusIcon3D.gd")

## 머리 위 오프셋 — HP 바(1.55~2.7) 위로. 적별로 _ready 에서 조정.
@export var follow_offset: Vector3 = Vector3(0, 2.2, 0)
## 아이콘 가로 간격(중앙정렬).
@export var spacing: float = 0.38

## key(String) -> StatusIcon3D(MeshInstance3D)
var _icons: Dictionary = {}
var _follow_target: Node3D = null
var _had_target: bool = false


func _ready() -> void:
	top_level = true
	var p := get_parent()
	if p is Node3D:
		_follow_target = p
		_had_target = true
	_sync_to_target()


func _process(_delta: float) -> void:
	_sync_to_target()


func _physics_process(_delta: float) -> void:
	_sync_to_target()


func _sync_to_target() -> void:
	# Orphan 안전망 — HpBar3D 와 동일. 타겟이 한 번이라도 있었는데 사라졌으면 자가 해제.
	var lost: bool = _follow_target == null \
		or not is_instance_valid(_follow_target) \
		or not (_follow_target as Node).is_inside_tree()
	if lost:
		if _had_target and not is_queued_for_deletion():
			queue_free()
		return
	global_position = _follow_target.global_position + follow_offset
	_face_camera()


func _face_camera() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var cam := vp.get_camera_3d()
	if cam == null:
		return
	global_basis = cam.global_basis.orthonormalized()


## key 상태 아이콘을 만들거나 갱신한다. d = {value, mode, color, icon}.
func set_status(key: String, d: Dictionary) -> void:
	var icon = _icons.get(key, null)
	if icon == null or not is_instance_valid(icon):
		icon = _IconScript.new()
		add_child(icon)
		_icons[key] = icon
		_relayout()
	icon.call("set_data", d)


## key 아이콘 제거.
func clear_status(key: String) -> void:
	var icon = _icons.get(key, null)
	if icon != null and is_instance_valid(icon):
		icon.queue_free()
	if _icons.has(key):
		_icons.erase(key)
		_relayout()


func has_status(key: String) -> bool:
	var icon = _icons.get(key, null)
	return icon != null and is_instance_valid(icon)


## 살아있는 아이콘을 x축으로 가로 중앙정렬 배치.
func _relayout() -> void:
	var live: Array = []
	for k in _icons.keys():
		var ic = _icons[k]
		if ic != null and is_instance_valid(ic):
			live.append(ic)
	var n: int = live.size()
	if n == 0:
		return
	var total_w: float = float(n - 1) * spacing
	var x0: float = -total_w * 0.5
	for i in n:
		(live[i] as Node3D).position = Vector3(x0 + float(i) * spacing, 0.0, 0.0)
