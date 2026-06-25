class_name AimArrow
extends Node3D

## Ground-projected aim arrow. Grows in length while LMB is held, points
## along the slash direction. Sized so the visible tip == the actual slash range.

@export var min_length: float = 3.0
@export var max_length: float = 5.5
@export var width: float = 1.2
@export var color_min: Color = Color(1.0, 1.0, 1.0, 0.55)
@export var color_max: Color = Color(1.0, 0.45, 0.25, 0.95)
@export var ground_offset: float = 0.05

var _shaft: MeshInstance3D
var _head: MeshInstance3D
var _material: StandardMaterial3D
var _current_length: float = 0.0

func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.albedo_color = color_min
	_material.no_depth_test = false

	# Shaft: rectangle in XZ plane, pivot at left edge so it extends along +X
	# from origin to (length, 0, 0)
	_shaft = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 0.02, width * 0.5)
	_shaft.mesh = box
	_shaft.material_override = _material
	add_child(_shaft)

	# Head: another box, larger Z, placed at tip
	_head = MeshInstance3D.new()
	var head_box := BoxMesh.new()
	head_box.size = Vector3(0.8, 0.02, width)
	_head.mesh = head_box
	_head.material_override = _material
	add_child(_head)

	set_length(min_length)
	visible = false

## Sets the arrow visual to the given world-space length, growing from origin
## (player position) along local +X axis.
func set_length(length: float) -> void:
	_current_length = length
	var shaft_len: float = max(length - 0.7, 0.05)
	_shaft.scale = Vector3(shaft_len, 1.0, 1.0)
	_shaft.position = Vector3(shaft_len * 0.5, ground_offset, 0.0)
	_head.position = Vector3(shaft_len + 0.3, ground_offset, 0.0)

## Sets visual based on charge fraction 0..1 (lerps color and length).
func set_charge(t: float) -> void:
	t = clamp(t, 0.0, 1.0)
	var length: float = lerp(min_length, max_length, t)
	set_length(length)
	_material.albedo_color = color_min.lerp(color_max, t)

## Aims along the given direction in world space (XZ plane).
func aim_at_direction(dir: Vector3) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		return
	flat = flat.normalized()
	# Arrow points along local +X. We want local +X to align with `flat`.
	# Yaw such that basis.x == flat.
	var yaw := atan2(-flat.z, flat.x)
	rotation = Vector3(0.0, yaw, 0.0)

func show_arrow() -> void:
	visible = true

func hide_arrow() -> void:
	visible = false
