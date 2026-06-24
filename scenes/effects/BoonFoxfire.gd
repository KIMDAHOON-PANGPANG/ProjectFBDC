extends Node3D

## 여우불세례(HOMING_PROJECTILE) / 혼불난무(RADIAL_BURST) 공용 발사체 — 구미호.
## 핑크 구체. homing=true 면 표식 만개 적(seed) 우선 호밍, false 면 직진(방사).
## 충돌 시 적 격추 + 폭발 후 free. class_name 없음 — preload + .new() + init_proj 덕타이핑.
## ⚠ Arrow(EnemyArrow)는 enemy_projectiles 그룹·PC 타격이라 재사용 불가 → 자체 인라인 노드.
## 그룹 boon_proj + lifetime 으로 누수 방지(스폰 측 동시 상한도 적용).

const PINK := Color(1.0, 0.37, 0.69)

var _speed: float = 11.0
var _damage: int = 1
var _radius: float = 0.9
var _homing: bool = true
var _dir: Vector3 = Vector3.FORWARD
var _t: float = 0.0
var _lifetime: float = 3.0
var _dead: bool = false
var _seed: Node = null
## 틴트(요괴/카드별) — 기본 핑크(구미호). params.tint(Color) 로 도깨비 금황 등 주입.
var _tint: Color = PINK
## 적중 시 적에 부여할 meta 키(빈문자=없음). 도깨비불 일섬 → "dokebi_ember"(CHAIN_BURST 연계).
var _ember_meta: String = ""


func init_proj(pos: Vector3, fire_dir: Vector3, params: Dictionary, homing: bool, seed_target) -> void:
	_speed = float(params.get("speed", 11.0))
	_damage = int(params.get("damage", 1))
	_radius = maxf(float(params.get("radius", 0.9)), 0.3)
	_homing = homing
	_seed = seed_target
	if params.get("tint") is Color:
		_tint = params.get("tint")
	_ember_meta = String(params.get("ember_meta", ""))
	var fd := Vector3(fire_dir.x, 0.0, fire_dir.z)
	if fd.length_squared() < 0.0001:
		fd = Vector3(1, 0, 0)
	_dir = fd.normalized()
	global_position = pos
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = _tint
	m.emission_enabled = true
	m.emission = _tint
	m.emission_energy_multiplier = 3.0
	mi.material_override = m
	add_child(mi)


func _process(delta: float) -> void:
	if _dead:
		return
	_t += delta
	if _t >= _lifetime:
		queue_free()
		return
	if _homing:
		var tgt := _target()
		if tgt != null:
			var to_t: Vector3 = (tgt as Node3D).global_position + Vector3(0, 0.9, 0) - global_position
			to_t.y = 0.0
			if to_t.length() > 0.01:
				_dir = _dir.lerp(to_t.normalized(), clampf(delta * 6.0, 0.0, 1.0)).normalized()
	global_position += _dir * _speed * delta
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node3D) or e.is_in_group("boss"):
			continue
		var d: float = ((e as Node3D).global_position - global_position).length()
		if d <= _radius:
			_explode(e)
			return


func _target() -> Node:
	if _seed != null and is_instance_valid(_seed) and (_seed is Node3D) and not (_seed as Node).is_in_group("boss"):
		return _seed
	var best: Node = null
	var best_d: float = 99999.0
	var marked_best: Node = null
	var marked_d: float = 99999.0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node3D) or e.is_in_group("boss"):
			continue
		var dd: float = ((e as Node3D).global_position - global_position).length()
		if int(e.get_meta("holrim_marks", 0)) > 0 and dd < marked_d:
			marked_d = dd
			marked_best = e
		if dd < best_d:
			best_d = dd
			best = e
	return marked_best if marked_best != null else best


func _explode(tgt: Node) -> void:
	if _dead:
		return
	_dead = true
	if tgt != null and is_instance_valid(tgt) and tgt.has_method("take_hit") and not tgt.is_in_group("boss"):
		tgt.call("take_hit", _damage)
		# 도깨비불 표식 — CHAIN_BURST(옮겨붙기) 연계용. 살아남은 적에 불씨 도장.
		if _ember_meta != "" and is_instance_valid(tgt):
			tgt.set_meta(_ember_meta, true)
	var host := get_parent()
	if host != null:
		var p := CPUParticles3D.new()
		host.add_child(p)
		p.global_position = global_position
		p.one_shot = true
		p.emitting = true
		p.amount = 16
		p.lifetime = 0.4
		p.explosiveness = 1.0
		p.direction = Vector3(0, 1, 0)
		p.spread = 180.0
		p.initial_velocity_min = 2.5
		p.initial_velocity_max = 5.0
		p.gravity = Vector3(0, -2.5, 0)
		p.scale_amount_min = 0.06
		p.scale_amount_max = 0.13
		var qm := QuadMesh.new()
		qm.size = Vector2(0.16, 0.16)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.albedo_color = Color(_tint.r, _tint.g, _tint.b, 0.95)
		m.emission_enabled = true
		m.emission = _tint
		m.emission_energy_multiplier = 2.4
		qm.material = m
		p.mesh = qm
		var tree := p.get_tree()
		if tree != null:
			tree.create_timer(0.7).timeout.connect(p.queue_free)
	queue_free()
