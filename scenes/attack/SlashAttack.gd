class_name SlashAttack
extends Area3D

const _TriggerBusScript := preload("res://scripts/managers/TriggerBus.gd")

## Hit-trail spawned along the dash path. Any enemy whose hurtbox overlaps
## this volume during its lifetime takes lethal damage (death anim).
## After lifetime expires, the visual fades out and the node frees itself.

signal hit_enemy(enemy: Node)

@export var lifetime: float = 0.18
@export var fade_after: float = 0.35
@export var color: Color = Color(1.0, 0.9, 0.5, 0.85)

## 기본 공격력(레벨업 "참격 강화" 카드). Player 가 스폰 시 주입 — 다중타 적/보스에
## 이 값만큼 데미지(잡몹/리퍼는 한 방 처치 유지). 보스는 보스데미지 + (이 값 - 1).
var attack_power: int = 1
## ⏱ 적중 시 미세 히트스탑("탁탁 걸리는" 손맛) — 쓸고 지날 때 적마다 잠깐 멈칫. scale=느려지는 배수, dur=시간(초).
@export var hit_hitstop_scale: float = 0.45
@export var hit_hitstop_dur: float = 0.03
var _length: float = 1.0
var _width: float = 1.4
## 범위 Vector3 분해 — _width=x(폭) · _height=y(높이) · _len_pad=z(전방 길이 가산).
var _height: float = 1.0
var _len_pad: float = 0.0
var _visual: MeshInstance3D
var _shape: CollisionShape3D
var _box_shape: BoxShape3D

func _ready() -> void:
	monitoring = true
	monitorable = false
	# Detect enemies on layer 3 (Enemy) + 적 발사체(EnemyAttack, layer 5) 격추용.
	collision_layer = 0
	collision_mask = (1 << 2) | (1 << 4)

	_box_shape = BoxShape3D.new()
	_shape = CollisionShape3D.new()
	_shape.shape = _box_shape
	add_child(_shape)

	_visual = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	_visual.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color
	# Visual polish — a soft emission so the trail reads as a bright
	# blade-flash against the ground rather than a flat decal. Cheap on
	# the mobile renderer (no glow post-process; emission just lifts the
	# unshaded albedo).
	mat.emission_enabled = true
	mat.emission = Color(color.r, color.g, color.b)
	mat.emission_energy_multiplier = 1.3
	_visual.material_override = mat
	add_child(_visual)

	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

	# Damage everything inside on spawn + a brief window after
	call_deferred("_do_initial_sweep")
	get_tree().create_timer(lifetime).timeout.connect(_disable_collision)
	get_tree().create_timer(fade_after).timeout.connect(_fade_and_free)

## Call BEFORE adding to the tree (or right after) to configure dimensions.
## extents = 타격 박스 범위(m): x=폭 / y=높이 / z=전방 길이 가산.
func configure(start_pos: Vector3, end_pos: Vector3, extents: Vector3) -> void:
	var mid := (start_pos + end_pos) * 0.5
	var dir := end_pos - start_pos
	var length := dir.length()
	if length < 0.01:
		length = 0.01
	_length = length
	_width = max(extents.x, 0.1)
	_height = max(extents.y, 0.1)
	_len_pad = max(extents.z, 0.0)
	global_position = Vector3(mid.x, mid.y + 0.1, mid.z)
	var yaw := atan2(-dir.z, dir.x)
	rotation = Vector3(0.0, yaw, 0.0)
	# Update sizes (shape may not exist yet if _ready hasn't fired)
	if _box_shape == null:
		# Defer until after _ready
		call_deferred("_apply_size")
	else:
		_apply_size()

func _apply_size() -> void:
	# 판정 박스: 길이(돌진 + 전방 가산) × 높이 × 폭. 시각은 바닥 데칼이라 y 납작.
	_box_shape.size = Vector3(_length + _len_pad, _height, _width)
	_visual.scale = Vector3(_length + _len_pad, 0.04, _width)


func _do_initial_sweep() -> void:
	for body in get_overlapping_bodies():
		_try_kill(body)
	for area in get_overlapping_areas():
		_try_kill(area)

func _on_body_entered(body: Node) -> void:
	_try_kill(body)

func _on_area_entered(area: Area3D) -> void:
	_try_kill(area)

func _try_kill(node: Node) -> void:
	# 적 발사체는 격추만 한다(적 처치/보스 데미지로 치지 않음 — hit_enemy 미발생).
	var pr := node
	while pr != null:
		if pr.is_in_group("enemy_projectiles"):
			if pr.has_method("take_hit"):
				pr.call("take_hit")
			return
		pr = pr.get_parent()
	var target: Node = node
	# Walk up to find an entity with a HealthComponent or a `take_hit` method
	while target != null:
		if target.has_method("take_hit"):
			# 보스는 boss_slash_damage_normal 만(잡몹 attack_power 스케일과 디커플링).
			# 잡몹/엘리트/주술사는 attack_power 만큼 — HP 스케일과 함께 다중타로 처치된다.
			if target.is_in_group("boss"):
				target.call("take_hit", _resolve_boss_damage())
			else:
				target.call("take_hit", attack_power)
				_slash_hitstop()  # 잡몹/엘리트 쓸고 갈 때 탁탁 걸리는 미세 히트스탑
			hit_enemy.emit(target)
			_emit_slash_hit(target)
			return
		var hp := target.get_node_or_null("HealthComponent")
		if hp != null and hp is HealthComponent:
			(hp as HealthComponent).take_damage(max(attack_power, 1))
			_slash_hitstop()
			hit_enemy.emit(target)
			_emit_slash_hit(target)
			return
		target = target.get_parent()


func _trigger_bus() -> Node:
	return get_node_or_null("/root/TriggerBus")

func _emit_slash_hit(target: Node) -> void:
	var tb := _trigger_bus()
	if tb == null:
		return
	var pos: Vector3 = (target as Node3D).global_position if (target is Node3D) else global_position
	var src := get_tree().get_first_node_in_group("player")
	var ctx := {"target": target, "position": pos, "source": src}
	# On_Slash_Hit 은 적중마다(표식 누적·도깨비 ember 등). On_Kill_via_Slash 는 이 적중으로
	# 실제 사망(HP<=0 / _dead)한 경우에만 — HP>1 몹은 다중타라 처치 시 1회만 흡혈/연쇄 발동.
	tb.call("emit", _TriggerBusScript.ON_SLASH_HIT, ctx)
	if _target_is_dead(target):
		tb.call("emit", _TriggerBusScript.ON_KILL_VIA_SLASH, ctx)
	# TODO(S5): 표식 도입 후 target 이 마크됐으면 ON_HIT_MARKED_ENEMY emit. 현재 표식 시스템 없어 미발행.


## take_hit/take_damage 직후 이 적이 실제 사망했는지 — HealthComponent(hp<=0) 우선,
## 없으면 적 노드의 _dead 플래그(보스 take_hit→_on_died 동기 호출 포함)로 판정. 둘 다
## 없으면 false(보수적). On_Kill_via_Slash 사망 게이트 전용.
func _target_is_dead(target: Node) -> bool:
	if target == null or not is_instance_valid(target):
		return true
	var hp := target.get_node_or_null("HealthComponent")
	if hp != null and hp is HealthComponent:
		return (hp as HealthComponent).hp <= 0
	if "_dead" in target:
		return bool(target._dead)
	return false

## ⏱ 적중 미세 히트스탑 — 카메라 rig 의 hitstop 을 짧게 호출. 적 연속 적중이면 갱신되며 "탁탁".
func _slash_hitstop() -> void:
	if hit_hitstop_dur <= 0.0:
		return
	var rig := get_tree().get_first_node_in_group("camera_rig")
	if rig != null and rig.has_method("hitstop"):
		rig.call("hitstop", hit_hitstop_scale, hit_hitstop_dur)


## 보스 적중 데미지 — PC 의 PlayerData(boss_slash_damage_normal)에서 읽는다.
## (젠 버스트 / 퍼펙트 패리 보정은 M8 S3a 에서 제거됨 — 일반 데미지만.)
func _resolve_boss_damage() -> int:
	var pc := get_tree().get_first_node_in_group("player")
	var dmg_normal: int = 1
	if pc != null and is_instance_valid(pc) and "data" in pc and pc.data != null:
		var d = pc.data
		if "boss_slash_damage_normal" in d:
			dmg_normal = d.boss_slash_damage_normal
	return dmg_normal

func _disable_collision() -> void:
	monitoring = false
	_shape.disabled = true

func _fade_and_free() -> void:
	var mat := _visual.material_override as StandardMaterial3D
	if mat != null:
		var t := create_tween()
		t.tween_property(mat, "albedo_color:a", 0.0, 0.2)
		t.tween_callback(queue_free)
	else:
		queue_free()
