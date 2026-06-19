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
## 일섬으로 되받아쳤는지 — true 면 팩션이 Enemy 타격(PC 제외)으로 바뀐다.
var _reflected: bool = false

func _ready() -> void:
	collision_layer = 1 << 4  # EnemyAttack
	collision_mask = (1 << 0) | (1 << 1)  # World + Player
	monitoring = true
	# PC 의 공격(근접 부채 / 슬래시)에 맞으면 사라지도록 그룹 등록 — take_hit 으로 격추.
	add_to_group("enemy_projectiles")

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

## PC 의 공격(근접 부채/슬래시)이 호출 — 발사체는 HP 없이 한 방에 격추(소멸).
func take_hit(_amount: int = 0) -> void:
	if _consumed:
		return
	_consumed = true
	queue_free()

## ⏱ 일섬이 격추 대신 호출 — 탄을 날아온 방향의 반대로 되받아쳐 적을 맞힌다.
## 팩션을 PlayerAttack(layer) + Enemy(mask) 로 바꿔 PC 는 다시 맞지 않는다.
## 비관통: _on_hit 에서 첫 적 명중 시 소멸. enemy_projectiles 그룹에서 빠져
## 일섬에 재반사되지 않는다.
func reflect() -> void:
	if _consumed or _reflected:
		return
	_reflected = true
	_dir = -_dir
	var yaw := atan2(-_dir.z, _dir.x)
	rotation = Vector3(0.0, yaw, 0.0)
	speed *= 1.5  # 되받아치는 손맛 — 약간 더 빠르게.
	collision_layer = 1 << 3              # PlayerAttack
	collision_mask = (1 << 0) | (1 << 2)  # World + Enemy (Player 제외 → PC 안 맞음)
	remove_from_group("enemy_projectiles")
	# 시각 — 청록으로 바꿔 "되받아친 탄" 가독성.
	var mi := get_node_or_null("ArrowMesh") as MeshInstance3D
	if mi != null and mi.material_override is StandardMaterial3D:
		var m := mi.material_override as StandardMaterial3D
		m.albedo_color = Color(0.5, 1.0, 1.0)
		m.emission_enabled = true
		m.emission = Color(0.4, 0.95, 1.0)
		m.emission_energy_multiplier = 1.8

func _on_hit(node: Node) -> void:
	if _consumed:
		return
	if _reflected:
		# 반사된 탄 — 적만 타격(PC 는 mask 제외라 애초에 트리거 안 됨). 비관통.
		var t: Node = node
		while t != null:
			if t.is_in_group("enemies") or t.is_in_group("boss"):
				if t.has_method("take_hit"):
					if t.is_in_group("boss"):
						t.call("take_hit", 1)
					else:
						t.call("take_hit")
				_consumed = true
				queue_free()
				return
			t = t.get_parent()
		if node is StaticBody3D:  # 벽/월드면 소멸.
			_consumed = true
			queue_free()
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
