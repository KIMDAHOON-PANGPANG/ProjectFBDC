class_name EnemyArrow
extends Area3D

## Enemy arrow projectile. Travels in a straight line, damages player on hit,
## frees itself on world or player contact, or after max_lifetime.

@export var speed: float = 11.0
@export var damage: int = 1
@export var max_lifetime: float = 4.0
@export var fallback_color: Color = Color(1.0, 0.95, 0.6)

## Multiplier injected by bullet-time. 1.0 = normal, 0.25 = slow.
var time_scale_mult: float = 1.0

var _dir: Vector3 = Vector3.FORWARD
var _life: float = 0.0
var _consumed: bool = false

func _ready() -> void:
	collision_layer = 1 << 4  # EnemyAttack
	collision_mask = (1 << 0) | (1 << 1)  # World + Player
	monitoring = true

	if get_node_or_null("CollisionShape3D") == null:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(0.4, 0.2, 0.2)
		cs.shape = sh
		add_child(cs)

	if get_node_or_null("ArrowMesh") == null:
		# Replaced the BILLBOARD_FIXED_Y Sprite3D with an actual 3D mesh
		# because the billboard locked the sprite's wide axis to the
		# camera plane regardless of flight direction — the arrow
		# always looked like it was pointing at the viewer instead of
		# along its trajectory. A long BoxMesh along local +X reads
		# correctly once `launch()` sets rotation.y to the flight yaw.
		var mi := MeshInstance3D.new()
		mi.name = "ArrowMesh"
		var box := BoxMesh.new()
		# Long along +X (forward), thin on Y/Z so it reads as a shaft.
		box.size = Vector3(0.6, 0.08, 0.1)
		mi.mesh = box
		# Shift up so the shaft sits ~chest-high on the PC instead of
		# clipping the ground plane.
		mi.position = Vector3(0.0, 0.6, 0.0)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = fallback_color
		mi.material_override = mat
		add_child(mi)

	body_entered.connect(_on_hit)
	area_entered.connect(_on_hit)

func launch(direction: Vector3, from: Vector3) -> void:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3(1, 0, 0)
	_dir = flat.normalized()
	global_position = from
	# Align local +X with direction so the sprite reads as flying forward.
	var yaw := atan2(-_dir.z, _dir.x)
	rotation = Vector3(0.0, yaw, 0.0)

func _physics_process(delta: float) -> void:
	if _consumed:
		return
	# Bullet-time also drags arrows mid-flight, so the player can dodge in slow-mo.
	delta *= time_scale_mult
	_life += delta
	if _life >= max_lifetime:
		queue_free()
		return
	global_position += _dir * speed * delta

func _on_hit(node: Node) -> void:
	if _consumed:
		return
	# Ignore the spawner enemy and other enemies
	if node is MeleeEnemy or node is RangedEnemy:
		return
	if node.has_method("take_hit") and node.is_in_group("player"):
		node.call("take_hit", damage)
		_consumed = true
		queue_free()
		return
	# Treat anything else as world / wall
	if node is StaticBody3D or node is CharacterBody3D:
		# If it's the player CharacterBody3D it should be in 'player' group above
		_consumed = true
		queue_free()
