class_name Boss
extends CharacterBody3D

## Chapter 1 final boss. A big square cube with 15 HP. Slow chaser whose
## attacks open with a ZZZ-style "critical hit" signal at its head:
##   • YELLOW (70%) — PC's slash, well-timed to land in a tight ~0.3s
##     window around the sweep moment, parries the attack. The boss
##     cancels mid-swing, takes no damage from the parry hit itself,
##     enters a 1s BLOCKED stun, then resumes the attack cycle. A short,
##     punchy curve-decay camera shake sells the parry impact.
##   • RED (30%) — unparryable. The PC must dodge; slashing through
##     deals normal damage but does NOT cancel the swing.
##
## The "critical hit" pattern is a BOSS-ONLY rule (mobs / elites never
## fire BossSignal). Adding a new boss = copy this Boss script's signal
## + parry flow; staying in the `"boss"` group keeps any shared
## owner-level logic (e.g. chapter clear) working.
##
## Owner (Main) listens for `boss_defeated` to invoke the chapter-clear flow.

signal boss_defeated

## Attack-type enum used by the critical-hit signal. Picked at attack start.
enum AttackType { YELLOW, RED }

@export var move_speed: float = 1.5
@export var detection_range: float = 30.0
@export var attack_range: float = 2.4
@export var attack_cooldown: float = 1.6
@export var max_hp: int = 15

@export var number_label_path: NodePath
@export var mesh_path: NodePath

## Fan-telegraph tuning. Boss is a wide, hard-hitting swing — bigger arc
## and reach than mobs, 2 damage on connect (same as the legacy attack).
@export var attack_damage: int = 2
@export var fan_radius: float = 3.0
@export var fan_angle_deg: float = 90.0
## Shared FanTelegraph PackedScene wired in Boss.tscn.
@export var telegraph_scene: PackedScene

@export_group("Critical Attack")
## Floating YELLOW/RED icon spawned at the boss's head during a wind-up.
@export var boss_signal_scene: PackedScene
## Chance an attack rolls YELLOW (parryable). User-tuned baseline 0.7.
@export var parry_yellow_ratio: float = 0.7
## When true, a fraction `white_ratio` of attacks roll WHITE instead of
## YELLOW/RED. WHITE behaves like RED (no parry, must dodge) but signals
## a future "grab pattern" — currently a visual-only distinction so
## Chapter 2's boss reads differently. PURPLE / GREEN added in M6 for
## Boss 3 (also RED semantics, visual only — real grab/AoE/multi-hit
## mechanics are post-M6).
@export var enable_white_signal: bool = false
@export var white_ratio: float = 0.0
## M6 — PURPLE: 광역 텔레그래프 (현재 RED 의미, 시각만 보라). Boss 3 도입.
@export var enable_purple_signal: bool = false
@export var purple_ratio: float = 0.0
## M6 — GREEN: 다단히트 (현재 RED 의미, 시각만 녹색). Boss 3 도입.
@export var enable_green_signal: bool = false
@export var green_ratio: float = 0.0
@export_group("Parry Reward")
## ⏱ Perfect-parry chain reward window. A successful parry sets the PC's
## `parry_boost_until_msec` to `now + parry_boost_window_ms`; the next
## SlashAttack that lands on the boss in that window deals
## `parry_boost_dmg` instead of the normal 1.
@export var parry_boost_window_ms: int = 1000
@export var parry_boost_dmg: int = 3
## Parry window opens this long BEFORE the sweep starts (i.e. at
## telegraph_time - parry_window_pre_sweep), and stays open until
## parry_window_post_sweep seconds AFTER the sweep starts.
@export var parry_window_pre_sweep: float = 0.2
@export var parry_window_post_sweep: float = 0.1
## How long the boss is rooted/locked after a successful parry.
@export var block_duration: float = 1.0
## Camera shake on successful parry — strong + short ease-out curve.
@export var parry_shake_amp: float = 0.5
@export var parry_shake_dur: float = 0.3
## Constants for the FanTelegraph timings (must match `_begin_telegraph`'s
## configure call). Pulled out so the parry timer math can reference them.
const _FAN_TELEGRAPH_TIME: float = 0.5
const _FAN_SWEEP_TIME: float = 0.2

## Boss body footprint half-size on XZ (BoxShape3D in Boss.tscn is 2.1
## cube, half = 1.05). The PC's iaido dash uses direct global_position
## assignment which bypasses physics — if the dash terminates inside
## the boss body the PC gets wedged, since neither side's CharacterBody
## solver can push them out from full overlap. We snap the PC to the
## nearest face each tick when overlap is detected.
const _BOSS_HALF_XZ: float = 1.05
## PC capsule radius (Player.tscn: CapsuleShape3D radius = 0.35).
const _PC_RADIUS: float = 0.35
## Slack added on top so the eject lands clearly outside the body —
## previously 0.05 was too tight and floating-point noise caused the
## eject to retrigger every tick. 0.25 = unambiguous clearance.
const _EJECT_SLACK: float = 0.25
## PC State.DASHING enum value (Player.gd:13). Hard-coded to avoid a
## cross-script dependency for one constant.
const _PC_STATE_DASHING: int = 2

var time_scale_mult: float = 1.0

var _player: Node3D
var _health: HealthComponent
var _attack_cd: float = 0.0
var _dead: bool = false
## True from telegraph spawn until the FanTelegraph self-frees — keeps
## the boss rooted and prevents double-queuing a wind-up.
var _attacking: bool = false
## Current attack's critical-hit type. Only meaningful while _attacking.
var _attack_type: int = AttackType.YELLOW
## M6 — visual override for the head icon. 0 = standard YELLOW/RED, 1 =
## WHITE (Boss 2), 2 = PURPLE (Boss 3 광역), 3 = GREEN (Boss 3 다단).
## Override types all carry RED semantics today (no parry, must dodge).
## Cleared at the start of every telegraph in `_begin_telegraph`.
var _color_override: int = 0
## True only during the short parry window (yellow attacks only). When
## true, an incoming take_hit triggers _on_parried instead of damage.
var _parry_open: bool = false
## True for `block_duration` seconds after a successful parry. While set,
## the boss is rooted, can't attack, and the next-attack cooldown is
## already advancing so it resumes naturally on _end_block.
var _blocked: bool = false
## In-flight effect references — used by the parry path to cancel/free
## them the instant a parry resolves so the wind-up disappears on cue.
var _active_telegraph: Node = null
var _active_signal: Node = null
var _label: Label3D
var _mesh: MeshInstance3D

func _ready() -> void:
	add_to_group("enemies")
	add_to_group("boss")
	# This boss is a melee-style brawler — opt-in to the shared melee
	# telegraph attack. A future ranged boss simply leaves this line out.
	add_to_group("melee_enemies")
	collision_layer = 1 << 2  # Enemy
	collision_mask = (1 << 0) | (1 << 1)  # World + Player (bump only, no damage)

	_health = get_node_or_null("HealthComponent") as HealthComponent
	if _health != null:
		_health.setup(max_hp)
		_health.died.connect(_on_died)
		_health.damaged.connect(_on_damaged)

	_label = get_node_or_null(number_label_path) as Label3D
	if _label != null:
		_label.text = str(max_hp)

	_mesh = get_node_or_null(mesh_path) as MeshInstance3D
	# Duplicate material so flashes don't leak (defensive — there's only one
	# boss but the pattern stays consistent with EliteEnemy).
	if _mesh != null:
		var src_mat := _mesh.get_surface_override_material(0)
		if src_mat != null:
			_mesh.set_surface_override_material(0, src_mat.duplicate())

	_player = get_tree().get_first_node_in_group("player")

	# Parry Master card was picked BEFORE this boss spawned — pick up
	# the boosted window + counter damage here so per-chapter boss
	# rolls inherit the player's accumulated upgrades.
	if _player != null and "has_parry_master" in _player and _player.has_parry_master:
		parry_window_pre_sweep += 0.05
		parry_window_post_sweep += 0.05
		parry_boost_dmg += 1


func _physics_process(delta: float) -> void:
	if _dead:
		return
	delta *= time_scale_mult
	if _attack_cd > 0.0:
		_attack_cd -= delta

	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		velocity = Vector3.ZERO
		move_and_slide()
		return

	# Eject the PC from inside the boss body if the iaido dash dropped
	# them in there. Runs every tick (cheap; just bounds checks) so the
	# PC can't get stuck during attack / chase / block alike.
	_eject_overlapping_player()

	# Post-parry stun: locked in place, no actions, no attacks. The
	# block_duration timer flips _blocked back off so the next tick
	# resumes normal chase/attack flow.
	if _blocked:
		velocity = Vector3.ZERO
		move_and_slide()
		return

	# Rooted during the wind-up: stand still and let the FanTelegraph
	# resolve. Position/direction were locked when the telegraph spawned.
	if _attacking:
		velocity = Vector3.ZERO
		move_and_slide()
		return

	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()

	if dist <= attack_range:
		velocity = Vector3.ZERO
		if _attack_cd <= 0.0:
			_begin_telegraph(to_player)
		move_and_slide()
		return

	# No detection_range gate — the boss always closes on the PC, so the
	# player can't kite indefinitely by sprinting away. Boss movement is
	# slow enough on its own (move_speed = 1.5) that this stays fair.

	var dir := to_player.normalized()
	velocity.x = dir.x * move_speed * time_scale_mult
	velocity.z = dir.z * move_speed * time_scale_mult
	velocity.y = 0.0
	move_and_slide()

## Spawn the shared melee FanTelegraph at the boss's feet AND a
## BossSignal (YELLOW or RED) above its head. The boss commits to
## position + direction NOW; damage resolves ~0.5s later when the sweep
## crosses the PC. On YELLOW attacks a 0.3s parry window opens around
## the sweep moment — see _on_parried for what parrying does.
func _begin_telegraph(to_player_xz: Vector3) -> void:
	if telegraph_scene == null:
		_attack_cd = attack_cooldown
		return
	# Pick this swing's critical-hit color. Override family rolls first
	# (WHITE / PURPLE / GREEN — all RED semantics, visual only), in
	# probability order; whatever probability mass is left flows to the
	# standard YELLOW/RED split. Single `randf()` keeps the distribution
	# clean without compounding rolls.
	_color_override = 0
	var roll: float = randf()
	var consumed: float = 0.0
	if enable_white_signal and roll < consumed + white_ratio:
		_color_override = 1
		_attack_type = AttackType.RED
	consumed += (white_ratio if enable_white_signal else 0.0)
	if _color_override == 0 and enable_purple_signal and roll < consumed + purple_ratio:
		_color_override = 2
		_attack_type = AttackType.RED
	consumed += (purple_ratio if enable_purple_signal else 0.0)
	if _color_override == 0 and enable_green_signal and roll < consumed + green_ratio:
		_color_override = 3
		_attack_type = AttackType.RED
	consumed += (green_ratio if enable_green_signal else 0.0)
	if _color_override == 0:
		# Standard split over the remaining probability mass.
		var remaining: float = max(1.0 - consumed, 0.01)
		var split_roll: float = (roll - consumed) / remaining
		_attack_type = AttackType.YELLOW if split_roll < parry_yellow_ratio else AttackType.RED

	# Floating head-icon — visible the whole wind-up, plus a brief grace
	# so it doesn't pop out the same frame the sweep ends. cancel() on
	# parry trims it immediately.
	if boss_signal_scene != null:
		var signal_node := boss_signal_scene.instantiate()
		get_tree().current_scene.add_child(signal_node)
		if signal_node.has_method("configure"):
			var color: Color = _signal_color_for(_attack_type)
			var lifetime: float = _FAN_TELEGRAPH_TIME + _FAN_SWEEP_TIME + 0.1
			signal_node.call("configure", self, color, lifetime, 3.4)
		_active_signal = signal_node

	# post-M6 — color override morphs the swing's payload, not just the
	# head-icon color:
	#   WHITE  (잡기)  = double damage (single big hit)
	#   PURPLE (광역)  = ×1.5 radius, ×1.3 angle (wide AoE)
	#   GREEN  (다단)  = standard fan + scheduled followup sweep
	# GREEN's followup is fired below after the first fan spawns.
	var fan_radius_now: float = fan_radius
	var fan_angle_now: float = fan_angle_deg
	var dmg_now: int = attack_damage
	match _color_override:
		1:
			dmg_now = attack_damage * 2
		2:
			fan_radius_now = fan_radius * 1.5
			fan_angle_now = fan_angle_deg * 1.3
		# GREEN's first swing is normal — followup is the second hit.

	var fan := telegraph_scene.instantiate()
	get_tree().current_scene.add_child(fan)
	if fan.has_method("configure"):
		# Boss uses a slightly longer sweep so the wider swing reads.
		fan.call("configure", global_position, to_player_xz,
			fan_radius_now, fan_angle_now, dmg_now,
			_FAN_TELEGRAPH_TIME, _FAN_SWEEP_TIME)
	if fan.has_signal("tree_exited"):
		fan.tree_exited.connect(_on_telegraph_done, CONNECT_ONE_SHOT)
	_active_telegraph = fan

	# GREEN — schedule a second sweep 0.35s after the first one finishes.
	# Position + direction snapshotted at telegraph time; the followup
	# doesn't re-aim because the player would already be reacting to the
	# first swing.
	if _color_override == 3:
		var followup_pos: Vector3 = global_position
		var followup_dir: Vector3 = to_player_xz
		var followup_delay: float = _FAN_TELEGRAPH_TIME + _FAN_SWEEP_TIME + 0.35
		get_tree().create_timer(followup_delay).timeout.connect(
			_spawn_green_followup.bind(followup_pos, followup_dir))

	_attacking = true
	_attack_cd = attack_cooldown + 0.5

	# YELLOW only: schedule the parry window to open right before the
	# sweep moment and close shortly after. RED attacks skip this — they
	# can't be parried, only dodged.
	if _attack_type == AttackType.YELLOW:
		var open_delay: float = max(_FAN_TELEGRAPH_TIME - parry_window_pre_sweep, 0.0)
		var window_len: float = parry_window_pre_sweep + parry_window_post_sweep
		get_tree().create_timer(open_delay).timeout.connect(_open_parry_window)
		get_tree().create_timer(open_delay + window_len).timeout.connect(_close_parry_window)

func _signal_color_for(t: int) -> Color:
	match _color_override:
		1:
			return Color(0.97, 0.97, 1.0, 1.0)   # WHITE — 잡기 (시각만)
		2:
			return Color(0.78, 0.42, 0.95, 1.0)  # PURPLE — 광역 (시각만)
		3:
			return Color(0.42, 0.92, 0.45, 1.0)  # GREEN — 다단 (시각만)
	if t == AttackType.YELLOW:
		return Color(1.0, 0.85, 0.15, 1.0)
	return Color(0.95, 0.15, 0.15, 1.0)

func _open_parry_window() -> void:
	if _dead or _blocked or not _attacking:
		return
	if _attack_type != AttackType.YELLOW:
		return
	_parry_open = true

func _close_parry_window() -> void:
	_parry_open = false

func _on_telegraph_done() -> void:
	_attacking = false
	_active_telegraph = null
	# If the signal is still around (lifetime tail), let it self-fade.


## GREEN signal followup — spawn a second fan at the snapshotted
## position/direction. Uses a faster telegraph so the second hit reads
## as a quick chain rather than a separate attack.
func _spawn_green_followup(pos: Vector3, dir: Vector3) -> void:
	if _dead:
		return
	if telegraph_scene == null:
		return
	var fan := telegraph_scene.instantiate()
	get_tree().current_scene.add_child(fan)
	if fan.has_method("configure"):
		fan.call("configure", pos, dir,
			fan_radius, fan_angle_deg, attack_damage,
			_FAN_TELEGRAPH_TIME * 0.5, _FAN_SWEEP_TIME)

## take_hit fires when SlashAttack's volume overlaps the boss. During an
## open YELLOW parry window this is a parry — cancel the swing instead
## of taking damage. Otherwise normal damage path. `amount` defaults to 1
## so legacy callers (every non-boss take_hit was 1-shot lethal) keep
## working; SlashAttack passes 3 during the post-parry chain window.
func take_hit(amount: int = 1) -> void:
	if _dead:
		return
	if _parry_open and _attack_type == AttackType.YELLOW:
		_on_parried()
		return
	if _health != null:
		_health.take_damage(amount)

func _on_parried() -> void:
	_parry_open = false
	# Kill the in-flight wind-up so the swing visually aborts mid-arc.
	if _active_telegraph != null and is_instance_valid(_active_telegraph):
		_active_telegraph.queue_free()
	_active_telegraph = null
	if _active_signal != null and is_instance_valid(_active_signal) \
			and _active_signal.has_method("cancel"):
		_active_signal.call("cancel")
	_active_signal = null
	# Curve-decay shake — punchy front, fast tail.
	var rig := get_tree().get_first_node_in_group("camera_rig")
	if rig != null and rig.has_method("shake_curve"):
		rig.call("shake_curve", parry_shake_amp, parry_shake_dur)
	# Drop attack lock and enter block stun. Attack cooldown gets set to
	# the block duration so the next attack can't fire before the stun
	# wears off (and naturally fires soon after we wake up).
	_attacking = false
	_blocked = true
	_attack_cd = block_duration
	get_tree().create_timer(block_duration).timeout.connect(_end_block)
	# ⏱ Perfect-parry chain — open a short reward window where the next
	# slash on this (or any) boss deals `parry_boost_dmg` instead of 1.
	# SlashAttack reads `parry_boost_until_msec` off the player group;
	# we stamp it here and let it expire naturally without explicit clear.
	if _player != null and is_instance_valid(_player) \
			and "parry_boost_until_msec" in _player:
		_player.parry_boost_until_msec = Time.get_ticks_msec() + parry_boost_window_ms
	# Notify the PC so parry-triggered cards (Counter Step today; Zen
	# meter / etc. later) can branch off a single integration point.
	if _player != null and is_instance_valid(_player) \
			and _player.has_method("on_parry_success"):
		_player.on_parry_success()

func _end_block() -> void:
	# Defensive: if the boss died mid-block, just stay dead.
	if _dead:
		return
	_blocked = false

## If the PC's XZ position is inside our extended footprint (boss half-
## size + PC radius + slack), snap them outward along the axis with the
## smallest penetration. Box-vs-circle eject — picks the nearest face
## rather than crossing a corner. Direct global_position assignment is
## the only thing that reliably works against an iaido dash that
## teleported them in here, since neither character body can solve out
## from full inside-overlap.
##
## We deliberately SKIP the eject while the PC is mid-dash. The dash
## sets global_position via a frame-by-frame lerp; ejecting at the same
## time means we push the PC off the dash path, then the dash's next
## frame snaps them back inside, then we push again — a tug-of-war
## that reads visually as the PC "sliding endlessly" alongside us.
## Letting the dash complete first and ejecting on the next tick gives
## a single clean snap to the boss's surface.
func _eject_overlapping_player() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var pc := _player as CharacterBody3D
	if pc == null:
		return
	if "_state" in _player and _player._state == _PC_STATE_DASHING:
		return  # Dash overrides position; eject would fight it.
	var dx: float = pc.global_position.x - global_position.x
	var dz: float = pc.global_position.z - global_position.z
	var bound: float = _BOSS_HALF_XZ + _PC_RADIUS + _EJECT_SLACK
	if absf(dx) >= bound or absf(dz) >= bound:
		return  # Not inside the extended footprint — nothing to do.
	var push_x: float = bound - absf(dx)
	var push_z: float = bound - absf(dz)
	if push_x <= push_z:
		var sx: float = 1.0 if dx >= 0.0 else -1.0
		pc.global_position.x += sx * push_x
	else:
		var sz: float = 1.0 if dz >= 0.0 else -1.0
		pc.global_position.z += sz * push_z

func _on_damaged(_amount: int) -> void:
	if _label != null and _health != null:
		_label.text = str(max(_health.hp, 0))
	# Brief white flash on hit (skip lethal hit to avoid fighting death anim).
	if _mesh == null or _health == null or _health.hp <= 0:
		return
	var mat := _mesh.get_surface_override_material(0) as StandardMaterial3D
	if mat == null:
		return
	var original: Color = mat.albedo_color
	var flash: Color = Color(1.0, 1.0, 1.0, original.a)
	var t := create_tween()
	t.tween_property(mat, "albedo_color", flash, 0.04)
	t.tween_property(mat, "albedo_color", original, 0.14)

func _on_died() -> void:
	if _dead:
		return
	_dead = true
	# Stash death position for the EXP gem drop (tree_exited is too late).
	set_meta("death_position", global_position)
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 0
	boss_defeated.emit()
	_play_death_fade()

func _play_death_fade() -> void:
	var duration := 0.9
	var t := create_tween()
	t.set_parallel(true)
	if _mesh != null:
		var mat := _mesh.get_surface_override_material(0) as StandardMaterial3D
		if mat != null:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			t.tween_property(mat, "albedo_color:a", 0.0, duration)
	if _label != null:
		t.tween_property(_label, "modulate:a", 0.0, duration)
	t.tween_property(self, "position:y", position.y - 1.0, duration)
	t.chain().tween_callback(queue_free)
