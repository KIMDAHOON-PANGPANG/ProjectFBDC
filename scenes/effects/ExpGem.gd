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

# 자석 반경 축소(사용자 밸런스) — 사실상 붙어야 먹힘. 슬래시 대시로 젬 위를
# 지나가며 줍는 플레이를 유도.
# 자석 권역 — PC 가 다가오면 졸졸 따라붙어 빨려든다(이지인 가속 커브).
@export var magnet_radius: float = 1.75   # -50% (사용자 너프 — 일반 이동으로 가까이 가서 줍게)
@export var pickup_radius: float = 0.6
@export var magnet_speed: float = 18.0
## 자석 가속 램프(초) — magnet_min_speed→magnet_speed 로 이 시간에 걸쳐 이지인.
@export var magnet_ramp: float = 0.35
## 램프 시작 속도(졸졸 시작) — 0이면 움직이는 PC 를 못 따라가므로 최소값 유지.
@export var magnet_min_speed: float = 3.0
## 일섬 킬로 떨어진(또는 일섬이 스친) 젬을 예약하는 넉넉한 반경 — 일반 자석(magnet_radius)보다 크게.
## PC 가 이미 지나가도 슬래시-킬 젬을 잡아 예약.
@export var slash_reserve_radius: float = 4.0
## 일섬 도중 바닥의 기존 젬도 이 반경 안을 PC 가 스치면 예약(쓸어담는 느낌).
## slash_reserve_radius 와 동일 기본값으로 두되 분리해 튜닝 가능.
@export var slash_sweep_radius: float = 4.0
# 라이프타임 없음 — 줍기 전까진 사라지지 않는다(요청).

var exp_value: int = 1
var _player: Node3D
var _collected: bool = false
var _mesh: MeshInstance3D
var _age: float = 0.0
## 자석 권역 안에 머문 시간 — 호밍 속도 이지인 램프용.
var _home_t: float = 0.0
## 일섬(대시+착지유예) 중 자석 권역을 스쳐 "예약된" 젬. 일섬 종료 후엔 권역 밖이어도
## PC 로 졸졸 따라와 수집된다(뒤늦게 따라와 먹히는 연출).
var _reserved: bool = false
## reserved 시각 표시(살짝 떠오름)용 — _build_visual 에서 머티리얼 참조 보관.
var _mat: StandardMaterial3D
var _reserved_visualized: bool = false
## 스폰 직후 1회 셀프예약 판정을 수행했는지(매 프레임 재판정 방지).
var _spawn_reserve_checked: bool = false


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
	_mat = mat
	_mesh.material_override = mat
	_mesh.position = Vector3(0, 0.5, 0)
	add_child(_mesh)


func _process(delta: float) -> void:
	if _collected:
		return
	_age += delta
	# Gentle bob so the gem reads as a live pickup, not ground litter.
	# reserved 젬은 살짝 떠올라(+0.12) "따라올 준비"를 시각적으로 알린다.
	if _mesh != null:
		var bob_base: float = 0.62 if _reserved else 0.5
		_mesh.position.y = bob_base + sin(_age * 4.0) * 0.08
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		return
	# 일섬(슬래시 대시 + 착지 유예) 여부.
	var in_slash: bool = false
	if _player.has_method("is_slash_vacuuming"):
		in_slash = bool(_player.call("is_slash_vacuuming"))
	elif _player.has_method("is_slashing"):
		in_slash = bool(_player.call("is_slashing"))

	var to_pc: Vector3 = _player.global_position - global_position
	to_pc.y = 0.0
	var dist: float = to_pc.length()
	# 레벨업 "경험치 자석" 카드 — PC.exp_magnet_mult 로 자석 반경 확대.
	var eff_magnet: float = magnet_radius
	if "exp_magnet_mult" in _player:
		eff_magnet *= maxf(0.1, float(_player.exp_magnet_mult))

	# 스폰 직후 1회: 이 젬이 일섬(대시+착지유예) 도중에 떨어졌다면(=슬래시가 죽인 적의 젬),
	# PC 는 이미 대시로 지나가 magnet_radius 밖이다. 넉넉한 slash_reserve_radius 안이면 즉시 예약해
	# 일섬 종료 후 따라와 먹히게 한다. 너무 먼 젬까지 예약하지 않도록 반경으로 게이트.
	if not _spawn_reserve_checked:
		_spawn_reserve_checked = true
		if in_slash and not _reserved and dist <= slash_reserve_radius:
			_set_reserved()

	# 일섬 중 '차단'은 최초 예약 1회만 — 아직 미예약 젬만 즉시수집 대신 예약하고 대기한다.
	# 이미 예약된 젬은 이 블록을 건너뛰어, 일섬 중이라도 아래 호밍/수집으로 따라와 먹힌다(요청).
	if in_slash and not _reserved:
		_home_t = 0.0
		# 일섬이 스친 바닥 젬 + 슬래시-킬로 방금 떨어진 젬을 넉넉한 반경으로 예약(쓸어담는 느낌).
		# magnet_radius(1.75)는 빠른 대시가 지나간 뒤라 거의 못 잡으므로 전용 sweep 반경 사용.
		if dist <= maxf(eff_magnet, slash_sweep_radius):
			_set_reserved()
		return

	# 비일섬: 이미 예약된 젬은 권역 밖이어도 PC 로 호밍해 따라가 수집된다.
	if _reserved:
		if dist <= pickup_radius:
			_collect()
			return
		_home_t += delta
		var rk: float = clamp(_home_t / max(magnet_ramp, 0.0001), 0.0, 1.0)
		var rspeed: float = lerp(magnet_min_speed, magnet_speed, rk * rk)
		global_position += to_pc.normalized() * rspeed * delta
		return

	# 일반(비예약) 수집 — 기존 로직 그대로.
	if dist <= pickup_radius:
		_collect()
		return
	if dist <= eff_magnet:
		# 자석 권역 진입 — 호밍 시간 누적. 속도는 이지인(졸졸→빨라짐) 커브로 램프하고
		# PC 를 매 프레임 재추적하므로, 움직이는 PC 뒤를 졸졸 따라붙어 빨려든다.
		_home_t += delta
		var k: float = clamp(_home_t / max(magnet_ramp, 0.0001), 0.0, 1.0)
		var speed: float = lerp(magnet_min_speed, magnet_speed, k * k)  # ease-in
		global_position += to_pc.normalized() * speed * delta
	else:
		_home_t = 0.0  # 권역 벗어나면 램프 리셋


## 일섬 중 권역에 스친 젬을 예약 상태로 — 마킹 + 가벼운 시각 강조(emission 한 번 올림).
func _set_reserved() -> void:
	_reserved = true
	if not _reserved_visualized and _mat != null:
		_reserved_visualized = true
		_mat.emission_energy_multiplier = 3.2


func _collect() -> void:
	if _collected:
		return
	_collected = true
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("collect_exp_gem"):
		scene.call("collect_exp_gem", exp_value)
	queue_free()
