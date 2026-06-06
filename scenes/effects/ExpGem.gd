extends Node3D

## EXP gem dropped from an enemy corpse (Vampire-Survivors style pickup).
## Magnets toward the PC once inside `magnet_radius`, collected on contact
## (`pickup_radius`). On collect it calls `current_scene.collect_exp_gem(value)`
## so Main / Testplay credit the ExpSystem (same dispatch pattern as
## `trigger_elite_effect`).
##
## Design: an enemy kill now pays a small INSTANT exp (bar nudges) plus
## this gem carrying the bulk — so picking gems up is the real reward,
## and ignoring them costs you. The PC's slash-dash sweeps gems up as a
## side effect of moving through the corpse pile, which feels great.

@export var magnet_radius: float = 4.0
@export var pickup_radius: float = 0.8
@export var magnet_speed: float = 14.0
## Despawn if never collected so abandoned gems don't pile up forever.
@export var lifetime: float = 30.0

var exp_value: int = 1
var _player: Node3D
var _collected: bool = false
var _mesh: MeshInstance3D
var _age: float = 0.0


## Set BEFORE add_child so _ready's visual build reads the right size/color.
func configure(value: int) -> void:
	exp_value = max(1, value)


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	_build_visual()


func _build_visual() -> void:
	_mesh = MeshInstance3D.new()
	var quad := QuadMesh.new()
	# Bigger gem for a fatter payout (capped so elites don't dominate).
	var s: float = 0.28 + min(exp_value, 10) * 0.03
	quad.size = Vector2(s, s)
	_mesh.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.no_depth_test = true
	# Small gems green, big (elite) gems gold — reads value at a glance.
	var col: Color = Color(0.4, 1.0, 0.5) if exp_value < 5 else Color(1.0, 0.85, 0.3)
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 2.2
	_mesh.material_override = mat
	_mesh.position = Vector3(0, 0.5, 0)
	add_child(_mesh)


func _process(delta: float) -> void:
	if _collected:
		return
	_age += delta
	if _age >= lifetime:
		queue_free()
		return
	# Gentle bob so the gem reads as a live pickup, not ground litter.
	if _mesh != null:
		_mesh.position.y = 0.5 + sin(_age * 4.0) * 0.08
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		return
	var to_pc: Vector3 = _player.global_position - global_position
	to_pc.y = 0.0
	var dist: float = to_pc.length()
	if dist <= pickup_radius:
		_collect()
		return
	if dist <= magnet_radius:
		# Accelerate as it nears the PC — snappy "vacuum" feel.
		var speed: float = magnet_speed * (1.0 - dist / magnet_radius) + 3.0
		global_position += to_pc.normalized() * speed * delta


func _collect() -> void:
	if _collected:
		return
	_collected = true
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("collect_exp_gem"):
		scene.call("collect_exp_gem", exp_value)
	queue_free()
