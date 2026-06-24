extends CharacterBody3D

## 주술사(마법사) 엘리트 — 단일(싱글톤) 출현. 넓은 시야로 PC 를 보면 PC 주변 360° 에
## 보라색 장판(SorcererZone)을 흩뿌려 동선을 방해(LoL 모르가나 W). 5방컷. PC 가 가까이
## 쫓아오면 화면 반대편 끝으로 텔레포트(20초 쿨). class_name 없이 씬/덕타이핑으로 사용.

@export var effect_type: int = 0  # 죽어도 엘리트 페이로드 트리거 안 함(0)
@export var max_hp: int = 5
@export var move_speed: float = 1.6
## 시야 — PC 가 이 거리 안이면 "본다"(장판 시전 가능).
@export var vision_range: float = 14.0
## 장판 시전 파라미터(enemy.csv 106).
@export var zone_count: int = 3
@export var zone_radius: float = 2.0
@export var zone_spread: float = 2.6   # PC 중심에서 각 장판 중심까지 거리
@export var zone_duration: float = 3.0
@export var zone_slow_mult: float = 0.45
## 장판 전조(흐릿하게 채워지는) 시간 — 이 시간 후에 진한 장판이 발동한다.
@export var zone_precursor: float = 2.0
@export var cast_cooldown: float = 4.5
## 텔레포트 — PC 가 teleport_range 안에 들어오면 teleport_dist 만큼 반대편으로 점멸.
@export var teleport_cooldown: float = 20.0
@export var teleport_range: float = 4.0
@export var teleport_dist: float = 14.0
## 유령 활주 속도(유닛/초) — 점멸 대신 반투명 유령으로 이 속도로 미끄러져 이동.
@export var phase_speed: float = 16.0
## 카이팅 선호 거리 폭(너무 가까우면 물러나고 멀면 접근, 시야 유지).
@export var keep_band: float = 1.2
@export var armor_max: int = 0
@export var stagger_duration: float = 0.4

@export var number_label_path: NodePath
@export var mesh_path: NodePath

const _CombatDataScript := preload("res://scripts/managers/CombatData.gd")
const _KnockbackScript := preload("res://scripts/components/Knockback.gd")
const _HpBar3DScene := preload("res://scenes/ui/HpBar3D.tscn")
const _ZoneScript := preload("res://scenes/effects/SorcererZone.gd")
## 머리 위 상태(버프/디버프) 아이콘 스트립(공용 — 표식 등 폴링 표시).
const _StatusStripScript := preload("res://scenes/ui/StatusIconStrip3D.gd")
const _HOLRIM_COLOR := Color(1.0, 0.37, 0.69)
const _HOLRIM_CAP := 8.0

const _TINT := Color(0.62, 0.32, 1.0)  # 보라 — 마법사

var time_scale_mult: float = 1.0
var _player: Node3D
var _health: HealthComponent
var _label: Label3D
var _sprite: Sprite3D
var _dead: bool = false
var _cast_cd: float = 1.5      # 첫 시전까지 약간 텀
var _teleport_cd: float = 0.0
var _phasing: bool = false
var _phase_target: Vector3 = Vector3.ZERO
var _kb = _KnockbackScript.new()
## 머리 위 상태 아이콘 스트립(표식/버프 폴링 표시). _ready 에서 인스턴스.
var _status_strip: Node = null
## 카메라 rig(시야 게이트) — _ready 에서 lookup. 없으면 폴백 true(시야 안 취급).
var _cam: Node
## 진행 중 트윈 핸들 — 사망 시 명시 kill(사망 페이드 알파 경합 제거).
var _cast_tween: Tween
var _phase_tween: Tween
var _flash_tween: Tween


func _ready() -> void:
	add_to_group("enemies")
	add_to_group("elites")
	add_to_group("sorcerers")  # 싱글톤 캡(Main._alive_sorcerer_count)
	collision_layer = 1 << 2  # Enemy
	collision_mask = (1 << 0) | (1 << 1)  # World + Player

	# 데이터 — enemy.csv(106) 시야/장판/텔레포트/HP 적용.
	_CombatDataScript.apply_to_enemy(self, "sorcerer")

	_health = get_node_or_null("HealthComponent") as HealthComponent
	if _health != null:
		_health.setup(max_hp)
		_health.setup_armor(armor_max, stagger_duration)
		_health.died.connect(_on_died)
		_health.damaged.connect(_on_damaged)
		var bar := _HpBar3DScene.instantiate()
		if "follow_offset" in bar:
			bar.follow_offset = Vector3(0, 1.7, 0)
		add_child(bar)
		if bar.has_method("attach_health"):
			bar.call("attach_health", _health)

	# 머리 위 상태 아이콘 스트립 — HP 바(1.7) 위.
	var strip := _StatusStripScript.new()
	if "follow_offset" in strip:
		strip.follow_offset = Vector3(0, 2.25, 0)
	add_child(strip)
	_status_strip = strip

	_label = get_node_or_null(number_label_path) as Label3D
	if _label != null:
		_label.text = str(max_hp)
		_label.modulate = _TINT

	_sprite = get_node_or_null(mesh_path) as Sprite3D
	if _sprite != null:
		_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_sprite.shaded = false
		_sprite.transparent = true
		_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		_sprite.alpha_scissor_threshold = 0.5
		_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_sprite.modulate = _TINT

	_player = get_tree().get_first_node_in_group("player")
	_cam = get_tree().get_first_node_in_group("camera_rig")


## PC 카메라 프러스텀(시야) 안에 있는지 — 폴백(카메라 없음)은 true.
func _is_visible_now() -> bool:
	if _cam == null or not is_instance_valid(_cam):
		_cam = get_tree().get_first_node_in_group("camera_rig")
	if _cam == null:
		return true
	if not _cam.has_method("is_world_pos_visible"):
		return true
	return bool(_cam.call("is_world_pos_visible", global_position))


## 방어(도주/텔레포트) 패턴 발동 가능 — HP 30% 이하부터만 도주한다.
func _is_defensive() -> bool:
	if _health == null:
		return false
	return float(_health.hp) <= float(max_hp) * 0.3


## 머리 위 상태 아이콘 폴링 — 적 meta(holrim_marks 등)를 매 프레임 읽어 스트립 갱신.
func _poll_status() -> void:
	if _status_strip == null or not is_instance_valid(_status_strip):
		return
	var marks := int(get_meta("holrim_marks", 0))
	if marks > 0:
		_status_strip.call("set_status", "holrim", {
			"value": clampf(float(marks) / _HOLRIM_CAP, 0.0, 1.0),
			"mode": 0,
			"color": _HOLRIM_COLOR,
			"icon": null,
		})
	else:
		_status_strip.call("clear_status", "holrim")


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_poll_status()
	delta *= time_scale_mult
	if _cast_cd > 0.0:
		_cast_cd -= delta
	if _teleport_cd > 0.0:
		_teleport_cd -= delta
	# 유령 활주 중 — 반투명으로 목표까지 미끄러져 이동. 그 외 AI/넉백/스태거 정지.
	if _phasing:
		_update_phase(delta)
		return
	_kb.integrate(self, delta)
	if _health != null:
		_health.tick_stagger(delta)
		if _health.is_staggered():
			velocity = Vector3.ZERO
			move_and_slide()
			return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		velocity = Vector3.ZERO
		move_and_slide()
		return

	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()

	var visible_now: bool = _is_visible_now()

	# 방어 패턴(도주/텔레포트) — HP 30% 이하 + PC 가 너무 가까이 + 쿨 차면 발동.
	# (첫 피격 즉시 발동 X — HP 가 충분하면 도주 안 하고 시전·카이팅만.)
	if dist <= teleport_range and _teleport_cd <= 0.0 and _is_defensive():
		_begin_phase()
		return

	# 시야 안 + 시전 쿨 차면 → PC 주변 360° 장판 흩뿌리기. 시야 밖이면 시전 스킵(쿨 미소비).
	if visible_now and dist <= vision_range and _cast_cd <= 0.0:
		_do_cast()
		_cast_cd = cast_cooldown

	# 이동 — 시야 밖이면 화면 안으로 복귀(PC 방향 강제), 시야 안이면 선호 거리 카이팅.
	var dir := to_player.normalized() if dist > 0.001 else Vector3.ZERO
	var move := Vector3.ZERO
	if not visible_now:
		# 카메라 시야를 벗어났다 → PC 쪽으로 다가가 화면 안으로 복귀.
		move = dir
	else:
		# 카이팅 — 선호 거리 유지(너무 가까우면 물러나고 멀면 접근).
		var keep: float = teleport_range + 4.0
		if dist < keep - keep_band:
			move = -dir
		elif dist > keep + keep_band:
			move = dir
	velocity.x = move.x * move_speed * time_scale_mult
	velocity.z = move.z * move_speed * time_scale_mult
	velocity.y = 0.0
	move_and_slide()


## PC 주변 360° 에 zone_count 개의 장판을 균등+지터 각도로 흩뿌린다.
func _do_cast() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var scene := get_tree().current_scene
	if scene == null:
		return  # 안전 가드(헤드리스/씬 전환 중 등 current_scene 없을 때).
	var base: Vector3 = (_player as Node3D).global_position
	var start_ang: float = randf() * TAU
	var n: int = max(1, zone_count)
	for i in n:
		var ang: float = start_ang + TAU * float(i) / float(n) + randf_range(-0.45, 0.45)
		var off := Vector3(cos(ang), 0.0, sin(ang)) * zone_spread
		var z = _ZoneScript.new()
		scene.add_child(z)
		if z.has_method("configure"):
			z.call("configure", base + off, zone_radius, zone_duration, zone_slow_mult, zone_precursor)
	# 시전 연출 — 보라 섬광(잠깐 밝게).
	if _sprite != null:
		var orig: Color = _sprite.modulate
		if _cast_tween != null and _cast_tween.is_valid():
			_cast_tween.kill()
		_cast_tween = create_tween()
		_cast_tween.tween_property(_sprite, "modulate", Color(2.0, 1.6, 2.5, orig.a), 0.06)
		_cast_tween.tween_property(_sprite, "modulate", orig, 0.16)


## 점멸 대신 — 반투명 유령이 되어 화면 반대편 끝까지 phase_speed 로 스르르 미끄러진다.
## (사라지지 않고 활주 경로가 보여 PC 가 어디로 가는지 추적 가능.)
func _begin_phase() -> void:
	# 도주 목적지 — PC 반대(뒤·화면 밖)로 가지 않고, PC 를 향한 측면 원호로 비껴
	# 빠져 화면 안에 머무른다. 단 PC 와 너무 가까워지지 않게 최소 거리(keep) 보정.
	var dest: Vector3 = global_position
	if _player != null and is_instance_valid(_player):
		var pc: Vector3 = (_player as Node3D).global_position
		var to_pc := pc - global_position
		to_pc.y = 0.0
		var fwd := to_pc.normalized() if to_pc.length() > 0.1 else Vector3(1, 0, 0)
		# 측면(±90°) 벡터 — PC 와의 현재 좌/우 부호로 화면 안쪽을 택한다.
		var side := Vector3(fwd.z, 0.0, -fwd.x)
		var rel := global_position - pc
		if Vector3(rel.x, 0.0, rel.z).dot(side) < 0.0:
			side = -side
		# 측면 위주 + PC 쪽 성분 살짝 섞기(화면 안쪽으로 비껴 빠짐).
		var move_dir := (side + fwd * 0.4).normalized()
		dest = global_position + move_dir * teleport_dist
		# PC 로부터 최소 keep 이상 떨어지게 보정(너무 붙지 않게).
		var keep: float = teleport_range + 4.0
		var dp := dest - pc
		dp.y = 0.0
		if dp.length() < keep:
			var push := dp.normalized() if dp.length() > 0.01 else fwd
			dest = pc + push * keep
	_phase_target = Vector3(dest.x, global_position.y, dest.z)
	_phasing = true
	_teleport_cd = teleport_cooldown
	# 유령 — 충돌 끄기(PC/적이 통과). 종료 시 Enemy 레이어로 복원.
	collision_layer = 0
	velocity = Vector3.ZERO
	# 반투명으로 스르르 페이드(유령화).
	if _sprite != null:
		if _phase_tween != null and _phase_tween.is_valid():
			_phase_tween.kill()
		_phase_tween = create_tween()
		_phase_tween.tween_property(_sprite, "modulate:a", 0.32, 0.22)


## 유령 활주 한 프레임 — 목표까지 직접 이동(충돌 무시), 도착하면 종료.
func _update_phase(delta: float) -> void:
	var to_target := _phase_target - global_position
	to_target.y = 0.0
	var d := to_target.length()
	if d <= 0.25:
		_end_phase()
		return
	var step: float = phase_speed * delta   # delta 는 이미 time_scale_mult 반영됨.
	var mv := to_target.normalized() * minf(step, d)
	global_position += Vector3(mv.x, 0.0, mv.z)
	velocity = Vector3.ZERO


## 활주 종료 — 충돌 복원 + 다시 또렷하게(불투명).
func _end_phase() -> void:
	_phasing = false
	collision_layer = 1 << 2  # Enemy — 활주 끝나면 다시 피격/충돌 가능.
	if _sprite != null:
		if _phase_tween != null and _phase_tween.is_valid():
			_phase_tween.kill()
		_phase_tween = create_tween()
		_phase_tween.tween_property(_sprite, "modulate:a", _TINT.a, 0.22)


func apply_knockback(dir: Vector3, speed: float) -> void:
	_kb.push(dir, speed)


## SlashAttack/스윙이 호출(argless) — 엘리트처럼 1뎀씩(5방컷).
func take_hit(amount: int = 1) -> void:
	if _dead:
		return
	if _health != null:
		_health.take_damage(amount)


func _on_damaged(_amount: int) -> void:
	if _label != null and _health != null:
		_label.text = str(max(_health.hp, 0))
	if _sprite == null or _health == null or _health.hp <= 0:
		return
	var orig: Color = _sprite.modulate
	var flash := Color(2.5, 2.5, 2.5, orig.a)
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(_sprite, "modulate", flash, 0.04)
	_flash_tween.tween_property(_sprite, "modulate", orig, 0.12)


func _on_died() -> void:
	if _dead:
		return
	_dead = true
	_kb.vel = Vector3.ZERO
	# 진행 중 트윈(시전 섬광 / 유령 페이드 / 피격 플래시)을 명시 kill — 사망 페이드
	# 알파와 경합하지 않게(밝기/알파가 도로 복원되며 시체가 깜빡이는 것 방지).
	for h in [_cast_tween, _phase_tween, _flash_tween]:
		if h != null and h.is_valid():
			h.kill()
	if _health != null:
		_health.clear_stagger()
	set_meta("death_position", global_position)
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 0
	var duration := 0.45
	var t := create_tween()
	t.set_parallel(true)
	if _sprite != null:
		t.tween_property(_sprite, "modulate:a", 0.0, duration)
	if _label != null:
		t.tween_property(_label, "modulate:a", 0.0, duration)
	t.tween_property(self, "position:y", position.y - 0.6, duration)
	t.chain().tween_callback(_safe_free)
	# Backup free — the fade tween stalls under tree.paused (level-up) or a
	# strong time-scale, which would otherwise strand a faded, collision-off
	# body with its HP bar floating. Scene-timer past the tween duration
	# guarantees the free; _safe_free de-dupes the race.
	var tree := get_tree()
	if tree != null:
		tree.create_timer(duration + 0.2).timeout.connect(_safe_free)


## Free exactly once — death tween callback and backup timer may race.
func _safe_free() -> void:
	if is_instance_valid(self) and not is_queued_for_deletion():
		queue_free()
