extends Area3D

## 비도(Kunai) — 4안 기본 공격 투사체. 사무라이가 짧은 비도를 던진다.
## 직진하다 적(HealthComponent)에 닿으면 데미지를 주고 소멸. lifetime이
## 지나면 자동 소멸. Player가 instantiate → configure → 현재 씬에 add.

var direction: Vector3 = Vector3(1, 0, 0)
var speed: float = 20.0
var damage: int = 1
var lifetime: float = 1.5
var _age: float = 0.0


## Set BEFORE add_child (or right after) — _ready reads direction for yaw.
func configure(dir: Vector3, spd: float, dmg: int, life: float) -> void:
	direction = dir.normalized() if dir.length() > 0.01 else Vector3(1, 0, 0)
	speed = spd
	damage = max(1, dmg)
	lifetime = max(0.1, life)


func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 1 << 2  # Enemy layer
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.3
	shape.shape = sphere
	shape.position = Vector3(0, 0.5, 0)
	add_child(shape)
	_build_visual()
	body_entered.connect(_on_hit)
	area_entered.connect(_on_hit)


func _build_visual() -> void:
	var mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.55, 0.16)
	mesh.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Color(0.9, 0.95, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.7, 0.82, 1.0)
	mat.emission_energy_multiplier = 2.0
	mesh.material_override = mat
	mesh.position = Vector3(0, 0.5, 0)
	add_child(mesh)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return
	global_position += direction * speed * delta


## On contact, walk up to the entity carrying a HealthComponent and deal
## `damage`. Goes through HealthComponent directly (not take_hit) — the
## kunai is ranged chip damage, not the melee slash, so it skips the
## parry / telegraph-cancel logic on take_hit. Death position is still
## captured by the enemy's own _on_died for the EXP gem.
func _on_hit(node: Node) -> void:
	var target: Node = node
	while target != null:
		var hp := target.get_node_or_null("HealthComponent")
		if hp != null and hp is HealthComponent:
			(hp as HealthComponent).take_damage(damage)
			queue_free()
			return
		target = target.get_parent()
