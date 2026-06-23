class_name CircularSlash
extends Area3D

## Cylindrical AoE used as the bonus PC action when a type-2 elite dies.
## Visual is a flat ground disc that grows from 0 → radius, mimicking a decal
## (the project doesn't have a real decal texture yet — this is the dummy
## stand-in the design called for).

@export var radius: float = 2.5
@export var ring_color: Color = Color(0.8, 0.95, 1.0, 0.85)
@export var hold_time: float = 0.12
@export var fade_time: float = 0.55
@export var attack_power: int = 1

var _shape: CollisionShape3D
var _cyl_shape: CylinderShape3D
var _disc: MeshInstance3D


func configure(new_radius: float = -1.0, new_attack_power: int = 1, new_ring_color: Color = Color(0.8, 0.95, 1.0, 0.85)) -> void:
	if new_radius > 0.0:
		radius = new_radius
	attack_power = maxi(new_attack_power, 1)
	ring_color = new_ring_color
	if _cyl_shape != null:
		_cyl_shape.radius = radius
	if _disc != null:
		var mesh := _disc.mesh as CylinderMesh
		if mesh != null:
			mesh.top_radius = radius
			mesh.bottom_radius = radius
		var mat := _disc.material_override as StandardMaterial3D
		if mat != null:
			mat.albedo_color = ring_color

func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 1 << 2  # Enemy

	_cyl_shape = CylinderShape3D.new()
	_cyl_shape.radius = radius
	_cyl_shape.height = 1.2
	_shape = CollisionShape3D.new()
	_shape.shape = _cyl_shape
	_shape.transform.origin = Vector3(0, 0.6, 0)
	add_child(_shape)

	# Flat disc decal stand-in.
	_disc = MeshInstance3D.new()
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = radius
	disc_mesh.bottom_radius = radius
	disc_mesh.height = 0.05
	disc_mesh.radial_segments = 48
	_disc.mesh = disc_mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = ring_color
	_disc.material_override = mat
	_disc.transform.origin = Vector3(0, 0.04, 0)
	_disc.scale = Vector3(0.05, 1.0, 0.05)
	add_child(_disc)

	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

	call_deferred("_do_initial_sweep")

	# Grow the disc to full radius almost instantly for a sharp slash read.
	var grow := create_tween()
	grow.tween_property(_disc, "scale", Vector3(1.0, 1.0, 1.0), 0.1)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

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
			target.call("take_hit", attack_power)
			return
		target = target.get_parent()

func _disable_collision() -> void:
	monitoring = false
	if _shape != null:
		_shape.disabled = true

func _fade_and_free() -> void:
	var mat := _disc.material_override as StandardMaterial3D
	if mat == null:
		queue_free()
		return
	var t := create_tween()
	t.tween_property(mat, "albedo_color:a", 0.0, 0.4)
	t.tween_callback(queue_free)
