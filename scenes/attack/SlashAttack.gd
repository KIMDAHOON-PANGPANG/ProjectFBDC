class_name SlashAttack
extends Area3D

## Hit-trail spawned along the dash path. Any enemy whose hurtbox overlaps
## this volume during its lifetime takes lethal damage (death anim).
## After lifetime expires, the visual fades out and the node frees itself.

signal hit_enemy(enemy: Node)

@export var lifetime: float = 0.18
@export var fade_after: float = 0.35
@export var color: Color = Color(1.0, 0.9, 0.5, 0.85)

var _length: float = 1.0
var _width: float = 1.4
var _visual: MeshInstance3D
var _shape: CollisionShape3D
var _box_shape: BoxShape3D

func _ready() -> void:
	monitoring = true
	monitorable = false
	# Detect enemies on layer 3 (Enemy)
	collision_layer = 0
	collision_mask = 1 << 2  # layer 3

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
	_visual.material_override = mat
	add_child(_visual)

	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

	# Damage everything inside on spawn + a brief window after
	call_deferred("_do_initial_sweep")
	get_tree().create_timer(lifetime).timeout.connect(_disable_collision)
	get_tree().create_timer(fade_after).timeout.connect(_fade_and_free)

## Call BEFORE adding to the tree (or right after) to configure dimensions.
func configure(start_pos: Vector3, end_pos: Vector3, width: float) -> void:
	var mid := (start_pos + end_pos) * 0.5
	var dir := end_pos - start_pos
	var length := dir.length()
	if length < 0.01:
		length = 0.01
	_length = length
	_width = max(width, 0.1)
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
	_box_shape.size = Vector3(_length, 1.0, _width)
	_visual.scale = Vector3(_length, 0.04, _width)

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
	var target: Node = node
	# Walk up to find an entity with a HealthComponent or a `take_hit` method
	while target != null:
		if target.has_method("take_hit"):
			target.call("take_hit")
			hit_enemy.emit(target)
			return
		var hp := target.get_node_or_null("HealthComponent")
		if hp != null and hp is HealthComponent:
			(hp as HealthComponent).take_damage(999)
			hit_enemy.emit(target)
			return
		target = target.get_parent()

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
