class_name FanTelegraph
extends Node3D

## Shared melee-attack telegraph for every monster in the "melee_enemies"
## group. A flat red fan decal stand-in pops up at the attacker's feet
## locked to the PC's direction at spawn, holds for `telegraph_time`
## seconds (the player's reaction window), then a thin line sweeps across
## the fan over `sweep_time` seconds as a placeholder for the eventual
## swing animation. At the moment the sweep starts, the PC is point-
## checked against the fan sector and takes damage if inside.
##
## Why a single point-check instead of an Area3D damage window:
##   Spawning many short-lived Area3Ds (one per monster swing in a packed
##   wave) triggered a non-deterministic Jolt ref-count underflow warning
##   on free. The point-check is mechanically equivalent for a 0.15s
##   sweep — the PC's i-frame already gates repeat hits, and the real
##   animation system will resolve damage at a single hit-frame anyway.
##
## Why "spawn-and-forget" instead of parented to the attacker:
##   The attacker may die or move during the wind-up. By detaching the
##   telegraph (added to current_scene, not to the attacker), the on-
##   ground commitment is preserved — the PC can punish the wind-up by
##   killing the attacker mid-telegraph and the fan still resolves
##   visually, but with no damage (because the PC has rolled out of the
##   sector by sweep time). This matches the Nioh / God-of-War design
##   intent the user called out.
##
## Reuses patterns from:
##   - AimLaser (timer-driven phase transition)
##   - CircularSlash (flat ground decal stand-in, hold + fade lifecycle)
##   - SlashAttack (yaw via atan2(-dz, dx) so local +X faces the target)

## 윈드업(전조)이 끝나 데미지가 발동하는 바로 그 순간 발신 — 공격자(MeleeEnemy CHASER)가
## 이 시점에 스트라이크 프레임(휘두름)으로 전환해 "휘두름 + 히트"가 동시에 보이게 한다.
## 연결 안 한 공격자(엘리트 = 애니 없는 raw Sprite, 캔슬 시)에겐 무해.
signal swing

@export var radius: float = 1.8
@export var angle_deg: float = 70.0
@export var damage: int = 1
@export var telegraph_time: float = 0.5
@export var sweep_time: float = 0.15

@export var decal_color: Color = Color(0.95, 0.15, 0.15, 0.6)
@export var sweep_color: Color = Color(1.0, 0.95, 0.85, 1.0)
## Lift off the ground plane so the decal doesn't z-fight with the floor.
@export var ground_y_offset: float = 0.04

# Decal mesh: a flat horizontal triangle-fan sector in the local +X/+Z
# plane. The fan opens symmetrically around local +X (the "face direction"
# we get from `configure`'s yaw rotation).
var _decal: MeshInstance3D
var _decal_mat: StandardMaterial3D

# A thin radial line that pivots from the fan's left edge to its right
# edge during the sweep phase, hinting at the swing arc the real anim
# will eventually fill in.
var _sweep_line: MeshInstance3D
var _sweep_mat: StandardMaterial3D

var _half_angle_rad: float = 0.0
var _consumed: bool = false

func _ready() -> void:
	_half_angle_rad = deg_to_rad(angle_deg) * 0.5
	_build_decal()
	_build_sweep_line()
	# Fade the decal in fast for a sharp pop, so the wind-up reads as a
	# distinct event rather than something that was always there.
	if _decal_mat != null:
		var target_a := decal_color.a
		_decal_mat.albedo_color = Color(decal_color.r, decal_color.g, decal_color.b, 0.0)
		var t := create_tween()
		t.tween_property(_decal_mat, "albedo_color:a", target_a, 0.08)
	get_tree().create_timer(telegraph_time).timeout.connect(_begin_sweep)

## Caller sets position/orientation + per-attacker tuning, then adds us
## to the scene. Works whether called before or after add_to_tree (the
## relevant geometry rebuild happens in _ready or here, whichever fires
## later). Matches the SlashAttack.configure pre/post-tree pattern.
func configure(spawn_pos: Vector3, face_dir: Vector3, p_radius: float,
		p_angle_deg: float, p_damage: int, p_telegraph_time: float,
		p_sweep_time: float) -> void:
	radius = max(p_radius, 0.1)
	angle_deg = clamp(p_angle_deg, 5.0, 350.0)
	damage = max(p_damage, 0)
	telegraph_time = max(p_telegraph_time, 0.01)
	sweep_time = max(p_sweep_time, 0.01)
	global_position = Vector3(spawn_pos.x, spawn_pos.y + ground_y_offset, spawn_pos.z)
	var dir: Vector3 = face_dir
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = Vector3(1, 0, 0)
	# Same yaw convention as SlashAttack: local +X faces the target.
	var yaw: float = atan2(-dir.z, dir.x)
	rotation = Vector3(0.0, yaw, 0.0)
	_half_angle_rad = deg_to_rad(angle_deg) * 0.5
	# If _ready already ran, geometry was sized to whatever exports were
	# set at instantiate-time — rebuild with the configured numbers now.
	if _decal != null:
		_rebuild_decal_mesh()
	if _sweep_line != null:
		_rebuild_sweep_mesh()

func _build_decal() -> void:
	_decal = MeshInstance3D.new()
	_decal.name = "Decal"
	_decal_mat = StandardMaterial3D.new()
	_decal_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_decal_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_decal_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_decal_mat.albedo_color = decal_color
	_decal.material_override = _decal_mat
	_rebuild_decal_mesh()
	add_child(_decal)

func _rebuild_decal_mesh() -> void:
	# Triangle fan: center vertex + N+1 perimeter vertices over the arc.
	# 24 segments is plenty for angles up to ~150°; tiny mesh, negligible
	# cost per instantiate.
	var segments: int = 24
	var arr := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half: float = _half_angle_rad
	for i in segments:
		var t0: float = float(i) / float(segments)
		var t1: float = float(i + 1) / float(segments)
		var a0: float = lerp(-half, half, t0)
		var a1: float = lerp(-half, half, t1)
		var v0 := Vector3(cos(a0) * radius, 0.0, sin(a0) * radius)
		var v1 := Vector3(cos(a1) * radius, 0.0, sin(a1) * radius)
		# CULL_DISABLED on the material means winding direction doesn't
		# affect visibility — we set the normal explicitly to +Y so lit
		# shaders (none here, but defensively) would still light it right.
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3.ZERO)
		st.set_normal(Vector3.UP)
		st.add_vertex(v1)
		st.set_normal(Vector3.UP)
		st.add_vertex(v0)
	st.commit(arr)
	_decal.mesh = arr

func _build_sweep_line() -> void:
	_sweep_line = MeshInstance3D.new()
	_sweep_line.name = "SweepLine"
	_sweep_mat = StandardMaterial3D.new()
	_sweep_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_sweep_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_sweep_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_sweep_mat.albedo_color = sweep_color
	_sweep_line.material_override = _sweep_mat
	_sweep_line.visible = false
	_rebuild_sweep_mesh()
	add_child(_sweep_line)

func _rebuild_sweep_mesh() -> void:
	# A thin BoxMesh laid along local +X. The whole MeshInstance gets
	# offset so its inner edge sits at the pivot (telegraph origin); then
	# rotating the node around Y sweeps the bar like a clock hand.
	var box := BoxMesh.new()
	box.size = Vector3(radius, 0.04, 0.08)
	_sweep_line.mesh = box
	_sweep_line.position = Vector3(radius * 0.5, ground_y_offset + 0.01, 0.0)

func _begin_sweep() -> void:
	if _consumed:
		return
	# 히트 타이밍 = 스트라이크 시점. 공격자가 이 순간 휘두름 프레임으로 전환하도록 신호
	# (데미지 점검과 같은 프레임 → 휘두름과 히트가 정확히 일치). 캔슬되면 안 울린다.
	swing.emit()
	# 35프레임(스트라이크) 시점 데미지 점검(점-판정). 흰 스윕 라인은 제거 — 스프라이트
	# 공격 모션(34 윈드업→35 스트라이크)이 스윙을 표현하므로 흰 선이 불필요.
	_try_damage_player_now()
	var off_t := create_tween()
	off_t.tween_interval(0.08)
	off_t.tween_callback(_fade_and_free)

func _try_damage_player_now() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var pc := tree.get_first_node_in_group("player")
	if pc == null or not is_instance_valid(pc):
		return
	if not (pc is Node3D):
		return
	if not pc.has_method("take_hit"):
		return
	var pos: Vector3 = (pc as Node3D).global_position
	if _in_fan_radius(pos) and _in_fan_angle(pos):
		pc.call("take_hit", damage)

func _in_fan_radius(target_global_pos: Vector3) -> bool:
	var local := to_local(target_global_pos)
	local.y = 0.0
	return local.length_squared() <= radius * radius

func _in_fan_angle(target_global_pos: Vector3) -> bool:
	# Project target into our local XZ plane and check the angle from +X.
	var local := to_local(target_global_pos)
	local.y = 0.0
	if local.length_squared() < 0.0001:
		return true  # standing on the pivot — definitely hit
	var ang := atan2(local.z, local.x)
	return absf(ang) <= _half_angle_rad

## ⏱ Preemptive-slash cancel (M3 후속). An attacker that dies mid-wind-up
## calls this so the pending sweep deals NO damage and the decal fades
## out early. Sets `_consumed` first so a racing `_begin_sweep` /
## `_fade_and_free` no-op. Does its own fade (can't reuse _fade_and_free
## — that early-returns on `_consumed`).
func cancel() -> void:
	if _consumed:
		return
	_consumed = true
	var t := create_tween()
	t.set_parallel(true)
	if _decal_mat != null:
		t.tween_property(_decal_mat, "albedo_color:a", 0.0, 0.12)
	if _sweep_mat != null:
		t.tween_property(_sweep_mat, "albedo_color:a", 0.0, 0.12)
	t.chain().tween_callback(queue_free)


func _fade_and_free() -> void:
	if _consumed:
		return
	_consumed = true
	var t := create_tween()
	t.set_parallel(true)
	if _decal_mat != null:
		t.tween_property(_decal_mat, "albedo_color:a", 0.0, 0.2)
	if _sweep_mat != null:
		t.tween_property(_sweep_mat, "albedo_color:a", 0.0, 0.2)
	t.chain().tween_callback(queue_free)
