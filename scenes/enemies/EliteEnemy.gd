class_name EliteEnemy
extends CharacterBody3D

## Elite enemy: square (cube) silhouette, slightly larger than regular mobs.
## Carries an `effect_type` (1/2/3/4) that determines BOTH the death payload
## AND the hit-points required to kill it — heavier payloads need more hits:
##
##   type 1 = Explosion             →  1 HP (cheapest, smallest payoff)
##   type 2 = Bonus PC action       →  3 HP
##   type 3 = Bullet-time monochrome →  5 HP (hardest, biggest payoff)
##   type 4 = PC shield charge      →  7 HP (M6, defensive payoff)
##
## Movement is a chaser with a Boid-style separation force so elites don't
## clump on top of each other (which would let one slash kill two and stack
## two unrelated death payloads in the same frame). Separation only applies
## between elites; regular mobs swarm as before.
##
## The head-icon Label3D shows "hits remaining" — it updates each time the
## elite is damaged. Its color encodes effect_type (orange / ice / violet).

@export var effect_type: int = 1
@export var move_speed: float = 2.2
@export var detection_range: float = 16.0
@export var attack_range: float = 1.6
@export var attack_cooldown: float = 1.2
@export var max_hp: int = 3  # overwritten in _ready based on effect_type

## Boid-style separation: avoid other elites within this radius.
@export var separation_radius: float = 1.6
## How strongly separation pushes vs. PC chase (1.0 = equal weight).
@export var separation_weight: float = 1.8

## ── 경직(아머 게이지) ── 엘리트는 데미지 4 누적되면 경직. 0 = 아머 없음. enemy.csv 로 조절.
@export var armor_max: int = 4
@export var stagger_duration: float = 0.4

@export var number_label_path: NodePath
@export var mesh_path: NodePath

## Fan-telegraph tuning. The elite hits harder than a regular melee mob
## (wider arc, slightly larger reach) but the same 1 damage on connect.
@export var attack_damage: int = 1
@export var fan_radius: float = 2.0
@export var fan_angle_deg: float = 80.0
## Shared FanTelegraph PackedScene wired in EliteEnemy.tscn.
@export var telegraph_scene: PackedScene

## 데이터 관리 로더 (preload + 정적 호출 — 헤드리스 class_name 캐시 안전).
const _CombatDataScript := preload("res://scripts/managers/CombatData.gd")
## 스무스 넉백 컴포넌트(피격/피탄 시 부드럽게 밀림).
const _KnockbackScript := preload("res://scripts/components/Knockback.gd")
## 머리 위 HP+아머 바(코드 인스턴스 — .tscn 수정 불필요).
const _HpBar3DScene := preload("res://scenes/ui/HpBar3D.tscn")

## Multiplier injected by bullet-time. 1.0 = normal, 0.25 = slow.
var time_scale_mult: float = 1.0

var _player: Node3D
var _health: HealthComponent
var _attack_cd: float = 0.0
var _dead: bool = false
## True from telegraph spawn until the FanTelegraph self-frees — keeps us
## rooted and prevents a second telegraph stacking on the first.
var _attacking: bool = false
var _label: Label3D
var _sprite: Sprite3D
## 스무스 넉백 상태(피격/피탄 시 밀림).
var _kb = _KnockbackScript.new()

func _ready() -> void:
	add_to_group("enemies")
	add_to_group("elites")
	# Opt-in to the melee category — drives the shared FanTelegraph attack.
	add_to_group("melee_enemies")
	collision_layer = 1 << 2  # Enemy
	collision_mask = (1 << 0) | (1 << 1)  # World + Player — PC 가 밀침(자기 빠져나감). PC 는 안 막힘.

	# 데이터 관리 — enemy_combat.json(엘리트) 행동 파라미터 적용. HP 는 미적용
	# (아래 _hp_for_type 의 effect_type 표가 관리).
	_CombatDataScript.apply_to_enemy(self, "elite")

	# Effect_type dictates HP — stronger payload, more hits to kill.
	max_hp = _hp_for_type(effect_type)

	_health = get_node_or_null("HealthComponent") as HealthComponent
	if _health != null:
		_health.setup(max_hp)
		_health.setup_armor(armor_max, stagger_duration)
		_health.died.connect(_on_died)
		_health.damaged.connect(_on_damaged)
		# 머리 위 HP+아머 바(코드 인스턴스 — .tscn 수정 불필요).
		var bar := _HpBar3DScene.instantiate()
		if "follow_offset" in bar:
			bar.follow_offset = Vector3(0, 1.7, 0)
		add_child(bar)
		if bar.has_method("attach_health"):
			bar.call("attach_health", _health)

	_label = get_node_or_null(number_label_path) as Label3D
	if _label != null:
		# Label shows "hits remaining" — starts at max_hp, color tags effect_type.
		_label.text = str(max_hp)
		_label.modulate = _color_for_type(effect_type)

	# 해골 스프라이트 — 타입색으로 틴트(빨강/초록/파랑/노랑)해 실루엣과 라벨색을
	# 일치시킨다. 알파 안전(d3d12): transparent + ALPHA_CUT_DISCARD + NEAREST.
	_sprite = get_node_or_null(mesh_path) as Sprite3D
	if _sprite != null:
		_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_sprite.shaded = false
		_sprite.transparent = true
		_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		_sprite.alpha_scissor_threshold = 0.5
		_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_sprite.modulate = _color_for_type(effect_type)

	_player = get_tree().get_first_node_in_group("player")

func _physics_process(delta: float) -> void:
	if _dead:
		return
	# Bullet-time: slow our perception of time uniformly.
	delta *= time_scale_mult
	if _attack_cd > 0.0:
		_attack_cd -= delta
	# 스무스 넉백 — 피탄/피격 시 부드럽게 밀고 감쇠.
	_kb.integrate(self, delta)
	# 경직(아머 소거) 중 — 이동/공격 정지.
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

	# Rooted during the wind-up: don't blend separation either, the
	# telegraph's position/direction is already locked.
	if _attacking:
		velocity = Vector3.ZERO
		move_and_slide()
		return

	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()

	# Separation is always computed — applies even when out of detection range,
	# so two elites that happen to spawn on top of each other will drift apart
	# instead of staying coincident.
	var sep := _compute_separation()

	if dist <= attack_range:
		# In melee: stop and start the telegraphed swing. Skip separation
		# here so we don't drift back out of attack_range mid-swing.
		velocity = Vector3.ZERO
		if _attack_cd <= 0.0:
			_begin_telegraph(to_player)
		move_and_slide()
		return

	# No detection_range gate — elites always close on the PC. (The
	# separation Boid still kicks in via the blended chase below; we
	# removed the dedicated "out of range, separation-only" branch.)

	# Chase direction toward player, blended with the Boid-style separation
	# vector so elites don't collapse to the same point on the way in.
	var chase_dir := to_player.normalized()
	var blended := chase_dir + sep * separation_weight
	var final_dir: Vector3
	if blended.length() > 0.001:
		final_dir = blended.normalized()
	else:
		final_dir = chase_dir
	velocity.x = final_dir.x * move_speed * time_scale_mult
	velocity.z = final_dir.z * move_speed * time_scale_mult
	velocity.y = 0.0
	move_and_slide()

## Replaces the legacy direct-take_hit attack with the shared fan
## telegraph. Position + facing snap to "now" at spawn; damage resolves
## ~0.5s later when the sweep crosses the PC's location.
func _begin_telegraph(to_player_xz: Vector3) -> void:
	if telegraph_scene == null:
		# No scene wired — eat the cooldown and stay rooted so we don't
		# spam attempts every frame, but skip the damage entirely.
		_attack_cd = attack_cooldown
		return
	var fan := telegraph_scene.instantiate()
	var host := _effect_host()
	if host == null:
		fan.queue_free()
		_attack_cd = attack_cooldown
		return
	host.add_child(fan)
	if fan.has_method("configure"):
		fan.call("configure", global_position, to_player_xz,
			fan_radius, fan_angle_deg, attack_damage, 0.5, 0.15)
	if fan.has_signal("tree_exited"):
		fan.tree_exited.connect(_on_telegraph_done, CONNECT_ONE_SHOT)
	_attacking = true
	# Cooldown covers wind-up + sweep + a recovery breath.
	_attack_cd = attack_cooldown + 0.5

func _on_telegraph_done() -> void:
	_attacking = false

## Called by SlashAttack when this enemy's body overlaps the slash volume.
## Unlike regular mobs (which take 999 damage), elites take 1 damage per
## slash — so a type-1 dies in 1 hit, type-2 in 3, type-3 in 5.
## 피격(플레이어 AOE)/피탄(비도) 시 외부에서 호출 — 스무스 넉백 시작.
func apply_knockback(dir: Vector3, speed: float) -> void:
	_kb.push(dir, speed)

func take_hit(amount: int = 1) -> void:
	if _dead:
		return
	if _health != null:
		_health.take_damage(amount)

func _on_damaged(_amount: int) -> void:
	# Always refresh the head-icon to show hits remaining — even on the
	# lethal hit, so the player briefly sees "0" before the fade-out.
	if _label != null and _health != null:
		_label.text = str(max(_health.hp, 0))
	# Visual feedback per hit: brief flash on the cube.
	# Skip on lethal hit — the death fade owns the material from there, and
	# our flash tween would fight its alpha tween.
	if _sprite == null or _health == null:
		return
	if _health.hp <= 0:
		return
	var original: Color = _sprite.modulate
	# 과하게 밝게 번쩍 → 원래 타입색으로 복귀(알파 유지).
	var flash: Color = Color(2.5, 2.5, 2.5, original.a)
	var t := create_tween()
	t.tween_property(_sprite, "modulate", flash, 0.04)
	t.tween_property(_sprite, "modulate", original, 0.12)

func _on_died() -> void:
	if _dead:
		return
	_dead = true
	# 사망 시 넉백/경직 즉시 정지 — 밀리던 중이라도 그 자리에서 죽는다(요청).
	_kb.vel = Vector3.ZERO
	if _health != null:
		_health.clear_stagger()
	# Stash death position for the EXP gem drop (tree_exited is too late).
	set_meta("death_position", global_position)
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 0

	# Notify Main to fire the special payload at this position.
	var main := get_tree().current_scene
	if main != null and main.has_method("trigger_elite_effect"):
		main.call("trigger_elite_effect", effect_type, global_position)

	_play_death_fade()

func _play_death_fade() -> void:
	# Sink + fade the cube + label, then free.
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
	# strong time-scale, which would otherwise strand a collision-disabled,
	# faded body with its HP bar hanging in the air. A scene-timer past the
	# tween duration guarantees the free; _safe_free de-dupes the race.
	var tree := get_tree()
	if tree != null:
		tree.create_timer(duration + 0.2).timeout.connect(_safe_free)


## Free exactly once — death tween callback and backup timer may race.
func _safe_free() -> void:
	if is_instance_valid(self) and not is_queued_for_deletion():
		queue_free()

## World node to parent spawned effects under. Active scene normally; falls
## back to parent / tree root during a scene reload (current_scene null).
func _effect_host() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	if tree.current_scene != null:
		return tree.current_scene
	var p := get_parent()
	if p != null:
		return p
	return tree.root

## RGB by effect_type — used for BOTH cube body albedo and head label modulate
## so the silhouette and the icon read the same color at a glance.
func _color_for_type(t: int) -> Color:
	match t:
		1:
			return Color(0.90, 0.18, 0.18)  # Red    — Explosion
		2:
			return Color(0.18, 0.75, 0.22)  # Green  — Bonus action
		3:
			return Color(0.22, 0.38, 0.95)  # Blue   — Bullet-time
		4:
			return Color(0.98, 0.85, 0.25)  # Yellow — PC shield (M6)
	return Color(1, 1, 1)

## Hit-points required to kill an elite of the given effect_type.
## Stronger payload → more hits, so accidental "two payloads in one slash"
## becomes effectively impossible without deliberate setup.
func _hp_for_type(t: int) -> int:
	match t:
		1:
			return 2  # 폭발 — 가장 약함(머리 숫자 제거 → HP 바로 표시)
		2:
			return 3  # 보너스 액션
		3:
			return 4  # 불릿타임
		4:
			return 5  # 보호막 — 가장 단단
	return 3

## Local separation: scan the "elites" group, sum up repulsion vectors from
## any sibling within `separation_radius`. Linear falloff (closer = stronger).
## Cheap — n=3 elites means 9 pair checks per physics frame.
func _compute_separation() -> Vector3:
	var avoid := Vector3.ZERO
	for other in get_tree().get_nodes_in_group("elites"):
		if other == self or not is_instance_valid(other):
			continue
		var n3 := other as Node3D
		if n3 == null:
			continue
		var d: Vector3 = global_position - n3.global_position
		d.y = 0.0
		var dist := d.length()
		if dist < separation_radius and dist > 0.01:
			avoid += d.normalized() * (1.0 - dist / separation_radius)
	return avoid
