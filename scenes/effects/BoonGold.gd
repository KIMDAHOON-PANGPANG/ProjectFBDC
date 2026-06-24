extends Node3D

## 뚝딱 금 나와라(GOLD_REFUND) 금화 — 도깨비 질주. 금황 코인이 톡 튀어나와
## PC 로 졸졸 회수 → 회수 시 열기 환급(add_heat 음수) + 소량 회복. ExpGem 자석 패턴 참고.
## class_name 없음 — BoonExecutor 가 preload + .new() 로 인스턴스, init_gold 덕타이핑.
## 그룹 boon_gold + lifetime 으로 누수 방지(스폰 측 동시 상한도 적용).

const GOLD := Color(1.0, 0.76, 0.2)

var _player: Node = null
var _heat_refund: float = 8.0
var _heal: int = 0
var _t: float = 0.0
var _lifetime: float = 8.0
var _dead: bool = false
var _vel: Vector3 = Vector3.ZERO
var _home_t: float = 0.0
var _spit_t: float = 0.0
var _spit_dur: float = 0.35
var _pickup_radius: float = 0.7
var _magnet_radius: float = 6.0


func init_gold(player: Node, origin: Vector3, params: Dictionary, spit_dir: Vector3) -> void:
	_player = player
	_heat_refund = float(params.get("heat_refund", 8.0))
	_heal = int(params.get("heal", 0))
	global_position = origin + Vector3(0, 0.5, 0)
	var sd := Vector3(spit_dir.x, 0.0, spit_dir.z)
	if sd.length_squared() < 0.0001:
		sd = Vector3(randf() - 0.5, 0.0, randf() - 0.5)
	_vel = sd.normalized() * 4.5 + Vector3(0, 4.0, 0)
	_build_visual()


func _build_visual() -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.16
	cm.bottom_radius = 0.16
	cm.height = 0.05
	mi.mesh = cm
	mi.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = GOLD
	m.emission_enabled = true
	m.emission = GOLD
	m.emission_energy_multiplier = 2.4
	mi.material_override = m
	add_child(mi)


func _process(delta: float) -> void:
	if _dead:
		return
	_t += delta
	if _t >= _lifetime:
		queue_free()
		return
	if _player == null or not is_instance_valid(_player) or not (_player is Node3D):
		queue_free()
		return
	var ppos: Vector3 = (_player as Node3D).global_position + Vector3(0, 0.5, 0)
	# 토출 단계 — 포물선으로 튀어나옴.
	if _spit_t < _spit_dur:
		_spit_t += delta
		_vel.y -= 12.0 * delta
		global_position += _vel * delta
		if global_position.y < 0.3:
			global_position.y = 0.3
		return
	# 회수 단계 — PC 로 이지인 호밍(ExpGem 식 졸졸).
	var to_p: Vector3 = ppos - global_position
	var d: float = to_p.length()
	if d <= _pickup_radius:
		_collect()
		return
	_home_t = min(_home_t + delta, 1.0)
	var spd: float = lerp(3.0, 16.0, _home_t * _home_t)
	global_position += to_p.normalized() * spd * delta


func _collect() -> void:
	if _dead:
		return
	_dead = true
	if _player != null and is_instance_valid(_player):
		# 열 환급 — add_heat 음수(즉발 일섬 모드에서만 효과, 그 외 no-op).
		if _heat_refund != 0.0 and _player.has_method("add_heat"):
			_player.call("add_heat", -_heat_refund)
		# 소량 회복.
		if _heal > 0:
			var hp := _player.get_node_or_null("HealthComponent")
			if hp != null:
				hp.call("heal", _heal)
	_spark()
	queue_free()


func _spark() -> void:
	var host := get_parent()
	if host == null:
		return
	var p := CPUParticles3D.new()
	host.add_child(p)
	p.global_position = global_position
	p.one_shot = true
	p.emitting = true
	p.amount = 8
	p.lifetime = 0.35
	p.explosiveness = 1.0
	p.direction = Vector3(0, 1, 0)
	p.spread = 180.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, -3.0, 0)
	p.scale_amount_min = 0.05
	p.scale_amount_max = 0.1
	var qm := QuadMesh.new()
	qm.size = Vector2(0.12, 0.12)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.95)
	m.emission_enabled = true
	m.emission = GOLD
	m.emission_energy_multiplier = 2.2
	qm.material = m
	p.mesh = qm
	var tree := p.get_tree()
	if tree != null:
		tree.create_timer(0.6).timeout.connect(p.queue_free)
