class_name ExplosionBurst
extends Area3D

## Spherical AoE that triggers on spawn. Calls `take_hit()` on every enemy
## inside the sphere, then fades its visual and self-frees.
##
## Tuned so the diameter is roughly 5x the player capsule diameter (0.7),
## i.e. radius ≈ 1.75 → diameter 3.5. Configurable via `radius`.

@export var radius: float = 1.75
@export var color: Color = Color(1.0, 0.65, 0.15, 0.9)
@export var hold_time: float = 0.06
@export var fade_time: float = 0.4

var _shape: CollisionShape3D
var _sphere_shape: SphereShape3D
var _visual: MeshInstance3D

func _ready() -> void:
	monitoring = true
	# Deferred — this Area3D spawns from inside EliteEnemy's `died` signal
	# handler (EliteEnemy._on_died → Main.trigger_elite_effect →
	# _spawn_explosion → add_child → _ready). Godot 4.x blocks direct
	# `monitorable` writes during a signal in/out phase; set_deferred
	# pushes the property change to the next idle frame, which is when
	# the area would have been picked up anyway.
	set_deferred("monitorable", false)
	collision_layer = 0
	collision_mask = 1 << 2  # Enemy layer

	_sphere_shape = SphereShape3D.new()
	_sphere_shape.radius = radius
	_shape = CollisionShape3D.new()
	_shape.shape = _sphere_shape
	# Lift slightly so the sphere center sits roughly chest-high.
	_shape.transform.origin = Vector3(0, 0.5, 0)
	add_child(_shape)

	_visual = MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 24
	mesh.rings = 12
	_visual.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	mat.albedo_color = color
	_visual.material_override = mat
	_visual.transform.origin = Vector3(0, 0.5, 0)
	add_child(_visual)

	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

	# Sweep everyone already inside right now, then leave detection on
	# briefly so an enemy that enters during the hold window also dies.
	call_deferred("_do_initial_sweep")
	get_tree().create_timer(hold_time).timeout.connect(_disable_collision)
	get_tree().create_timer(fade_time).timeout.connect(_fade_and_free)

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
	while target != null:
		if target.has_method("take_hit") and target.is_in_group("enemies"):
			target.call("take_hit")
			return
		target = target.get_parent()

func _disable_collision() -> void:
	monitoring = false
	if _shape != null:
		_shape.disabled = true

func _fade_and_free() -> void:
	var mat := _visual.material_override as StandardMaterial3D
	if mat == null:
		queue_free()
		return
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(mat, "albedo_color:a", 0.0, 0.35)
	t.tween_property(_visual, "scale", Vector3(1.4, 1.4, 1.4), 0.35)
	t.chain().tween_callback(queue_free)
