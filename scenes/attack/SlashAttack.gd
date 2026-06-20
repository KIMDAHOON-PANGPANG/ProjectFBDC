class_name SlashAttack
extends Area3D

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


## Visual polish — repaint as a Zen-burst slash (gold + strong emission)
## so the full-width burst reads as a special strike, not just a wider
## normal slash. Called by Player._spawn_slash_attack after add_child
## (so `_visual` exists) when the burst flag is set.
func set_burst_visual() -> void:
	if _visual == null:
		return
	var mat := _visual.material_override as StandardMaterial3D
	if mat == null:
		return
	mat.albedo_color = Color(1.0, 0.85, 0.3, 0.92)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.25)
	mat.emission_energy_multiplier = 2.4

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
			# Only the boss take_hit accepts an amount — mobs/elites are
			# 1-shot lethal so passing an arg would either be ignored or
			# (worse) shift their argless signature. Branch on group.
			if target.is_in_group("boss"):
				target.call("take_hit", _resolve_boss_damage() + (attack_power - 1))
			else:
				target.call("take_hit", attack_power)
			hit_enemy.emit(target)
			return
		var hp := target.get_node_or_null("HealthComponent")
		if hp != null and hp is HealthComponent:
			(hp as HealthComponent).take_damage(999)
			hit_enemy.emit(target)
			return
		target = target.get_parent()


## ⏱ Damage resolver for boss hits. Two boost paths can apply:
##   1. Zen burst — slash was spawned with `zen_burst` meta → 5 dmg
##      (highest priority; consumed by Player._fire_slash on spawn).
##   2. Perfect-parry chain — PC's `parry_boost_until_msec` still in
##      the future → 3 dmg (M2).
## Otherwise the normal 1 dmg. We resolve here so neither Boss nor
## Player need to know the multiplier values.
func _resolve_boss_damage() -> int:
	# 데미지 값은 PC 의 PlayerData(boss_slash_damage_*)에서 읽는다 — CombatData/
	# pc_combat.json 가 구동. data 가 없으면 기존 1/3/5 로 폴백.
	var pc := get_tree().get_first_node_in_group("player")
	var dmg_normal: int = 1
	var dmg_parry: int = 3
	var dmg_zen: int = 5
	if pc != null and is_instance_valid(pc) and "data" in pc and pc.data != null:
		var d = pc.data
		if "boss_slash_damage_normal" in d:
			dmg_normal = d.boss_slash_damage_normal
		if "boss_slash_damage_parry" in d:
			dmg_parry = d.boss_slash_damage_parry
		if "boss_slash_damage_zen" in d:
			dmg_zen = d.boss_slash_damage_zen
	# Zen burst takes precedence over the parry boost.
	if has_meta("zen_burst") and bool(get_meta("zen_burst", false)):
		return dmg_zen
	if pc == null or not is_instance_valid(pc):
		return dmg_normal
	if not ("parry_boost_until_msec" in pc):
		return dmg_normal
	if Time.get_ticks_msec() > pc.parry_boost_until_msec:
		return dmg_normal
	return dmg_parry

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
