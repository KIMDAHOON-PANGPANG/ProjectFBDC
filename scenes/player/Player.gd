class_name Player
extends CharacterBody3D

## Player samurai. Movement: WASD on XZ plane.
## Attack: hold LMB to charge an aim arrow (length grows w/ charge), release to
## perform an iaijutsu slash — dashes through enemies along the arrow and spawns
## a damage trail that kills everything in its width.

signal slash_started
signal slash_finished
## Emitted when the PC's HP hits 0 — Main listens to trigger the
## GameOverScreen + SaveSystem.record_death. Fires BEFORE the sprite-rig
## death animation removes the node, so listeners can still read the
## final position / stats.
signal died
## ⏱ Perfect dodge (M3 후속) — emitted when an attack is avoided during
## the early window of a Shift-evade. Main / Testplay connect this to
## BulletTimeService.start(short) for a self-bullet-time reward.
signal perfect_dodge

enum State { IDLE, AIMING, DASHING, COOLDOWN, EVADING }

@export var data: PlayerData
@export var slash_attack_scene: PackedScene
## 4안 — 비도 투사체 씬 (기본 공격). Player.tscn에 Kunai.tscn 주입.
@export var kunai_scene: PackedScene
@export var aim_arrow_path: NodePath
@export var sprite_rig_path: NodePath

var _state: int = State.IDLE
var _charge_t: float = 0.0
var _aim_dir: Vector3 = Vector3(1, 0, 0)
var _cooldown_t: float = 0.0
var _dash_start: Vector3
var _dash_end: Vector3
var _dash_elapsed: float = 0.0
var _aim_arrow: AimArrow
var _sprite_rig: SpriteRig
var _health: HealthComponent
## Foot-dust emitter — toggled on while WASD-moving / dashing / evading
## so the player has a clear "I am moving" cue even on an empty plane
## (the grid ground gives world-scrolling, this gives self-motion).
var _dust_emitter: CPUParticles3D

# Shift-dash (evade) state.
var _evade_dir: Vector3 = Vector3.ZERO
var _evade_start: Vector3
var _evade_end: Vector3
var _evade_elapsed: float = 0.0
var _evade_cd: float = 0.0

# Post-hit i-frame timer. While > 0, take_hit is suppressed. 4안 — 0.5s
# (사용자 지정). iframe_bonus(메타)가 더해지지만 메타 효과는 현재 초기화됨.
const HIT_IFRAME: float = 0.5
var _iframe_t: float = 0.0

# ── 4안 — 비도(Kunai) 기본 공격 상태 ──
## Current magazine ammo. Empties → reload.
var _ammo: int = 5
## Reload countdown. > 0 means reloading (fire suppressed).
var _reload_t: float = 0.0
## Per-shot cooldown countdown.
var _fire_cd: float = 0.0
## Auto-aim toggle (SPACE). When ON, fire targets the nearest enemy in
## `autoaim_radius` instead of the mouse.
var _autoaim: bool = false

# ── 4안 — 일섬 게이지 ──
## Fills from kills / gem pickups / perfect dodges. Slash (right-click)
## only fires at full, then resets to 0.
var _slash_gauge: float = 0.0
## Gauge gain multiplier — raised by the "기 충전" level-up card.
var slash_gauge_gain_mult: float = 1.0

## 4안 — knockback on hit: shove nearby enemies away when the PC is struck.
const KNOCKBACK_RADIUS: float = 4.0
const KNOCKBACK_FORCE: float = 5.0

## ⏱ Perfect dodge (M3 후속). If an attack would have hit within
## PERFECT_DODGE_WINDOW seconds of the evade STARTING, it counts as a
## perfect dodge → emit `perfect_dodge` (Main turns it into a short
## self-bullet-time) + Zen +1. `_perfect_dodge_fired` latches per evade
## so a flurry of attacks in one window only rewards once.
const PERFECT_DODGE_WINDOW: float = 0.12
var _perfect_dodge_fired: bool = false

## ⏱ Charge grade (M3 후속). Charge time maps to grades:
##   Quick  (0   ~ 0.3 frac) — short range, fast recovery
##   Mid    (0.3 ~ 0.9)      — linear range (existing behaviour)
##   Perfect(>= 0.9)         — max range + Zen +1 (reward, in _fire_slash)
## Holding PAST max_charge_time accumulates _overcharge_t; once it
## exceeds OVERCHARGE_GRACE the charge FIZZLES — the slash is wasted and
## all charging is locked for 1s. Punishes holding the button "just in
## case", which the linear ramp alone never discouraged.
const OVERCHARGE_GRACE: float = 0.45
const OVERCHARGE_LOCKOUT: float = 1.0
var _overcharge_t: float = 0.0

## ⏱ Perfect-parry chain reward — Boss._on_parried stamps this with
## `Time.get_ticks_msec() + window_ms`. SlashAttack reads it while
## resolving boss damage: if `Time.get_ticks_msec() <= parry_boost_until_msec`
## the next boss hit deals 3 instead of 1. No active timer or clear path
## is needed — natural expiry handles dropoff.
var parry_boost_until_msec: int = 0

## M4 meta passive — `MetaProgressionSystem.apply_to` adds owned levels
## of the "인내" passive here. take_hit uses `HIT_IFRAME + iframe_bonus`.
var iframe_bonus: float = 0.0

## M6 — yellow elite (effect_type 4) charges this on death. Each charge
## absorbs one hit's damage in `take_hit` (i-frame still triggers so the
## PC isn't immediately re-hit). No upper cap — stacks if multiple
## yellow elites die before any hit lands.
var shield_charges: int = 0

## ⏱ Zen meter integration (M4 후속). ZenSystem manages the counter +
## arms `has_zen_burst` when full. `_fire_slash` consumes the burst on
## the next slash → width × 3, range = max × 1.5, 5 dmg to bosses.
var _zen_system: Node
var has_zen_burst: bool = false

# --- M3 card flags ---
# All cards are single-pick: re-rolling the same one is a no-op until
# M5's unlock system removes already-owned cards from the draw pool.

## Multistrike — every slash auto-fires a smaller followup hit-trail
## 0.18s later (no second dash, just an extra SlashAttack volume).
var has_multistrike: bool = false
## Internal guard — set TRUE while the multistrike followup is spawning
## so the followup itself doesn't recursively schedule another one.
var _is_multistrike_followup: bool = false

## Echo — Main listens for slash_finished and spawns a CircularSlash at
## the PC's foot 0.3s after every slash. Cheap & visual, no PC state.
var has_echo: bool = false

## Vampire — Main's award_exp_for_kill rolls vampire_chance on every
## kill and heals 1 HP on success.
var has_vampire: bool = false
var vampire_chance: float = 0.0

## Phoenix — one free revive from HP 0 → full HP + 2s i-frame.
var has_phoenix: bool = false
var _phoenix_used: bool = false

## ⏱ Counter Step — Boss.on_parry_success() stamps `counter_step_until_msec`;
## while now <= stamp, move speed multiplier is +50%.
var has_counter_step: bool = false
var counter_step_until_msec: int = 0

## ⏱ Parry Master — informational flag (UpgradeSystem mutates Boss
## export values directly on pick + Boss._ready picks up future bosses).
var has_parry_master: bool = false

func _ready() -> void:
	if data == null:
		data = PlayerData.new()
	if data.visuals == null:
		data.visuals = CharacterVisuals.new()
		data.visuals.placeholder_tint = Color(0.85, 0.9, 1.0)

	collision_layer = 1 << 1  # Player
	collision_mask = (1 << 0) | (1 << 2)  # World + Enemy (block on enemies optional; we still pass over)

	_aim_arrow = get_node_or_null(aim_arrow_path) as AimArrow
	_sprite_rig = get_node_or_null(sprite_rig_path) as SpriteRig
	if _sprite_rig != null:
		_sprite_rig.fallback_color = Color(0.85, 0.9, 1.0)
		_sprite_rig.set_visuals(data.visuals)

	_ammo = data.max_ammo  # 4안 — start with a full magazine

	_health = get_node_or_null("HealthComponent") as HealthComponent
	if _health != null:
		_health.setup(data.max_hp)
		_health.died.connect(_on_died)
		# Wire the floating head-bar to the same HealthComponent.
		var hpbar := get_node_or_null("HpBar3D")
		if hpbar != null and hpbar.has_method("attach_health"):
			hpbar.call("attach_health", _health)

	_build_dust_emitter()

func _physics_process(delta: float) -> void:
	# 4안 — 비도 발사 / 리로드 / 자동조준 토글은 state 무관 (매 프레임).
	# DASHING/EVADING 중엔 발사만 _update_kunai 내부에서 억제.
	_update_kunai(delta)
	# Evade cooldown ticks independently of state so it counts down during
	# slash / cooldown / etc.
	if _evade_cd > 0.0:
		_evade_cd -= delta
	if _iframe_t > 0.0:
		_iframe_t -= delta
	match _state:
		State.IDLE:
			_handle_move(delta)
			_check_attack_start()
			_check_evade_start()
			if _cooldown_t > 0.0:
				_cooldown_t -= delta
		State.AIMING:
			velocity = Vector3.ZERO
			move_and_slide()
			_update_aim(delta)
			_check_attack_release()
		State.DASHING:
			_update_dash(delta)
		State.COOLDOWN:
			_handle_move(delta)
			_check_evade_start()
			_cooldown_t -= delta
			if _cooldown_t <= 0.0:
				_set_state(State.IDLE)
		State.EVADING:
			_update_evade(delta)

func _handle_move(delta: float) -> void:
	var input := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	var dir := Vector3(input.x, 0.0, input.y)
	if dir.length() > 1.0:
		dir = dir.normalized()
	# ⏱ Counter Step — +50% speed window after a successful parry.
	# Natural expiry, no clear path needed.
	var speed_mult: float = 1.0
	if has_counter_step and Time.get_ticks_msec() <= counter_step_until_msec:
		speed_mult = 1.5
	velocity.x = dir.x * data.move_speed * speed_mult
	velocity.z = dir.z * data.move_speed * speed_mult
	velocity.y = 0.0
	move_and_slide()
	var moving: bool = dir.length_squared() > 0.01
	if _sprite_rig != null:
		if moving:
			_sprite_rig.set_state(SpriteRig.State.WALK)
			_sprite_rig.set_facing(dir.x)
		else:
			_sprite_rig.set_state(SpriteRig.State.IDLE)
	# Dust kicks on whenever we're actually moving — gives a visible
	# self-motion cue on top of the world-anchored grid ground.
	if _dust_emitter != null:
		_dust_emitter.emitting = moving

func _check_attack_start() -> void:
	# 4안 — 일섬은 우클릭("slash") + 게이지 100%일 때만 시작.
	if Input.is_action_just_pressed("slash") and _cooldown_t <= 0.0:
		# Suppress when the click was on a UI control (level-up cards etc.).
		if _is_pointer_over_ui():
			return
		# Gate on a full slash gauge.
		if _slash_gauge < data.slash_gauge_max:
			return
		_set_state(State.AIMING)
		_charge_t = 0.0
		_overcharge_t = 0.0  # ⏱ fresh charge — clear any prior overcharge
		if _aim_arrow != null:
			_aim_arrow.show_arrow()
			_aim_arrow.set_charge(0.0)

func _is_pointer_over_ui() -> bool:
	var vp := get_viewport()
	if vp == null:
		return false
	return vp.gui_get_hovered_control() != null

func _check_attack_release() -> void:
	if not Input.is_action_pressed("slash"):
		_fire_slash()

func _update_aim(delta: float) -> void:
	_charge_t = min(_charge_t + delta, data.max_charge_time)
	# ⏱ Overcharge — once fully charged, holding longer accumulates toward
	# a fizzle. Auto-releases into a 1s lockout so holding "just in case"
	# is actively punished.
	if _charge_t >= data.max_charge_time:
		_overcharge_t += delta
		if _overcharge_t >= OVERCHARGE_GRACE:
			_fizzle_charge()
			return
	var dir := _mouse_to_world_dir()
	if dir.length_squared() > 0.0001:
		_aim_dir = dir
	if _aim_arrow != null:
		var charge_frac: float = _charge_t / max(data.max_charge_time, 0.0001)
		_aim_arrow.set_charge(charge_frac)
		_aim_arrow.aim_at_direction(_aim_dir)
	if _sprite_rig != null:
		_sprite_rig.set_facing(_aim_dir.x)
		_sprite_rig.set_state(SpriteRig.State.IDLE)


## ⏱ Overcharge fizzle — the charge was held past the grace window. Waste
## the slash, hide the arrow, and lock all charging for OVERCHARGE_LOCKOUT
## seconds (handled by the COOLDOWN state ticking _cooldown_t down).
func _fizzle_charge() -> void:
	_charge_t = 0.0
	_overcharge_t = 0.0
	_cooldown_t = OVERCHARGE_LOCKOUT
	if _aim_arrow != null:
		_aim_arrow.hide_arrow()
	if _sprite_rig != null:
		_sprite_rig.set_state(SpriteRig.State.IDLE)
	var rig := get_tree().get_first_node_in_group("camera_rig")
	if rig != null and rig.has_method("shake"):
		rig.call("shake", 0.05, 0.12)
	_play_sfx("fizzle")
	_set_state(State.COOLDOWN)

func _fire_slash() -> void:
	# 4안 — 일섬 발동 → 게이지 0으로 리셋.
	_slash_gauge = 0.0
	var charge_frac: float = clamp(_charge_t / max(data.max_charge_time, 0.0001), 0.0, 1.0)
	# ⏱ Zen burst — when armed, this slash consumes the burst and pays
	# out wide / long / heavy. We snapshot the flag now (consume_burst
	# below clears it) so the spawned trail gets the boost too.
	var burst_active: bool = has_zen_burst
	var slash_range: float = lerp(data.min_slash_range, data.max_slash_range, charge_frac)
	var slash_width_now: float = data.slash_width
	if burst_active:
		slash_range = data.max_slash_range * 1.5
		slash_width_now = data.slash_width * 3.0
		if _zen_system != null and _zen_system.has_method("consume_burst"):
			_zen_system.call("consume_burst")
	_dash_start = global_position
	_dash_end = global_position + _aim_dir.normalized() * slash_range
	_dash_elapsed = 0.0
	_set_state(State.DASHING)
	if _aim_arrow != null:
		_aim_arrow.hide_arrow()
	if _sprite_rig != null:
		_sprite_rig.set_state(SpriteRig.State.ATTACK)
		_sprite_rig.set_facing(_aim_dir.x)
	# Spawn slash trail at the start of the dash.
	_spawn_slash_attack(_dash_start, _dash_end, slash_width_now, burst_active)
	# ⏱ Perfect-charge zen reward — full charge (>= 0.9 of max) feeds
	# the meter. Burst slashes don't double-dip (they consumed the meter).
	if not burst_active and _zen_system != null and charge_frac >= 0.9 \
			and _zen_system.has_method("add"):
		_zen_system.call("add", 1)
	# M7 — slash SFX cue. SoundManager silently no-ops if no .ogg yet.
	if Engine.has_singleton("SoundManager") or _has_sound_manager():
		_play_sfx("burst_slash" if burst_active else "slash")
	slash_started.emit()

func _update_dash(delta: float) -> void:
	_dash_elapsed += delta
	var t: float = clamp(_dash_elapsed / max(data.dash_duration, 0.0001), 0.0, 1.0)
	# Smooth easing (ease-out)
	var eased: float = 1.0 - pow(1.0 - t, 2.0)
	global_position = _dash_start.lerp(_dash_end, eased)
	# Dust trails the dash for a chunky burst-line read.
	if _dust_emitter != null:
		_dust_emitter.emitting = true
	if t >= 1.0:
		_cooldown_t = data.slash_cooldown
		slash_finished.emit()
		_set_state(State.COOLDOWN if data.slash_cooldown > 0.0 else State.IDLE)
		# Multistrike — schedule a second hit-trail along the same line,
		# 0.18s after the dash lands. Followup spawns the trail only
		# (no dash, no charging) so it reads as a quick echo strike.
		if has_multistrike and not _is_multistrike_followup:
			get_tree().create_timer(0.18).timeout.connect(_fire_multistrike_followup)

func _spawn_slash_attack(start: Vector3, end: Vector3, width: float = -1.0, burst: bool = false) -> void:
	var attack: SlashAttack
	if slash_attack_scene != null:
		attack = slash_attack_scene.instantiate() as SlashAttack
	else:
		attack = SlashAttack.new()
	get_tree().current_scene.add_child(attack)
	var w: float = width if width > 0.0 else data.slash_width
	attack.configure(start, end, w)
	attack.lifetime = data.slash_hit_lifetime
	# ⏱ Zen burst payload — SlashAttack._resolve_boss_damage checks this
	# meta and returns 5 (vs. 1 / 3) when set. Cheap to carry on the
	# node; auto-frees with the attack.
	if burst:
		attack.set_meta("zen_burst", true)
		# Visual polish — gold + emission so the burst reads as special.
		if attack.has_method("set_burst_visual"):
			attack.call("set_burst_visual")


## Multistrike followup — spawn a shorter trail along the last aim
## direction, no dash. Guarded by `_is_multistrike_followup` so the
## extra trail can't itself trigger another followup recursively.
func _fire_multistrike_followup() -> void:
	if not is_inside_tree():
		return
	_is_multistrike_followup = true
	var start: Vector3 = global_position
	var end: Vector3 = global_position + _aim_dir.normalized() * (data.max_slash_range * 0.7)
	_spawn_slash_attack(start, end)
	_is_multistrike_followup = false

func _set_state(s: int) -> void:
	_state = s

func _mouse_to_world_dir() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return _aim_dir
	var mouse := get_viewport().get_mouse_position()
	var origin: Vector3 = cam.project_ray_origin(mouse)
	var normal: Vector3 = cam.project_ray_normal(mouse)
	# Intersect with the horizontal plane at player's Y.
	if abs(normal.y) < 0.0001:
		return _aim_dir
	var t: float = (global_position.y - origin.y) / normal.y
	if t < 0.0:
		return _aim_dir
	var hit: Vector3 = origin + normal * t
	var dir: Vector3 = Vector3(hit.x - global_position.x, 0.0, hit.z - global_position.z)
	if dir.length_squared() < 0.0001:
		return _aim_dir
	return dir.normalized()

func take_hit(amount: int = 1) -> void:
	# ⏱ Perfect dodge — an attack arrived during the early window of an
	# evade. Reward fires BEFORE the is_invincible early-return swallows
	# the hit. Latched per evade so multiple attacks only reward once.
	if _state == State.EVADING and not _perfect_dodge_fired \
			and _evade_elapsed <= PERFECT_DODGE_WINDOW:
		_perfect_dodge_fired = true
		perfect_dodge.emit()
		if _zen_system != null and _zen_system.has_method("add"):
			_zen_system.call("add", 1)
		add_slash_gauge(data.slash_gauge_on_perfect_dodge)  # 4안 — 저스트 회피 → 게이지
		_play_sfx("perfect_dodge")
		var pd_rig := get_tree().get_first_node_in_group("camera_rig")
		if pd_rig != null and pd_rig.has_method("nudge_lag"):
			pd_rig.call("nudge_lag", 0.25, 0.3)
	# Invincible for the duration of the iaido slash (DASHING), during a
	# Shift-evade (EVADING), and for HIT_IFRAME seconds after the previous
	# damage landed.
	if is_invincible():
		return
	# Shield absorb — yellow elite charges. Consume one charge, skip
	# damage, still trigger i-frame + a softer shake so the absorb reads
	# as a defensive "ting" instead of a free pass.
	if shield_charges > 0:
		shield_charges -= 1
		var sh_iframe: float = HIT_IFRAME + iframe_bonus
		_iframe_t = sh_iframe
		if _sprite_rig != null and _sprite_rig.has_method("start_iframe_blink"):
			_sprite_rig.call("start_iframe_blink", sh_iframe)
		var sh_rig := get_tree().get_first_node_in_group("camera_rig")
		if sh_rig != null and sh_rig.has_method("shake"):
			sh_rig.call("shake", 0.04, 0.1)
		_play_sfx("shield")
		return
	# ⏱ Zen meter drains on damage so "perfect play sustained" matters.
	if _zen_system != null and _zen_system.has_method("drain_on_hit"):
		_zen_system.call("drain_on_hit")
	_play_sfx("hit")
	if _health != null:
		_health.take_damage(amount)
	# Hit feedback — i-frame + strobe blink + camera shake. Runs even if
	# the hit was fatal (the strobe blends naturally into the death fade).
	var total_iframe: float = HIT_IFRAME + iframe_bonus
	_iframe_t = total_iframe
	if _sprite_rig != null and _sprite_rig.has_method("start_iframe_blink"):
		_sprite_rig.call("start_iframe_blink", total_iframe)
	# 4안 — 추가 피격 플래시(머티리얼 over-bright) + 주변 적 넉백.
	if _sprite_rig != null and _sprite_rig.has_method("flash"):
		_sprite_rig.call("flash", 0.2)
	_knockback_nearby_enemies()
	var rig := get_tree().get_first_node_in_group("camera_rig")
	if rig != null and rig.has_method("shake"):
		rig.call("shake", 0.1, 0.2)

func is_invincible() -> bool:
	return _state == State.DASHING or _state == State.EVADING or _iframe_t > 0.0

## --- Shift evade dash ---

func _check_evade_start() -> void:
	if _evade_cd > 0.0:
		return
	if not Input.is_action_just_pressed("dash"):
		return
	# Direction priority: current WASD input, else last aim direction, else
	# +X. This means a stationary PC dashes forward (toward last facing).
	var input := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	var dir := Vector3(input.x, 0.0, input.y)
	if dir.length() < 0.01:
		dir = _aim_dir
	if dir.length() < 0.01:
		dir = Vector3(1, 0, 0)
	dir = dir.normalized()
	_evade_dir = dir
	_evade_start = global_position
	_evade_end = global_position + dir * data.evade_distance
	_evade_elapsed = 0.0
	_evade_cd = data.evade_cooldown
	_perfect_dodge_fired = false  # ⏱ fresh evade — re-arm the perfect-dodge reward
	_set_state(State.EVADING)
	if _sprite_rig != null:
		_sprite_rig.set_facing(dir.x)
	# Nudge the camera so it trails the dash briefly.
	var rig := get_tree().get_first_node_in_group("camera_rig")
	if rig != null and rig.has_method("nudge_lag"):
		rig.call("nudge_lag", 0.35, 0.4)

func _update_evade(delta: float) -> void:
	_evade_elapsed += delta
	var t: float = clamp(_evade_elapsed / max(data.evade_duration, 0.0001), 0.0, 1.0)
	# Ease-out: feels snappy at start, settles smoothly at end.
	var eased: float = 1.0 - pow(1.0 - t, 2.0)
	global_position = _evade_start.lerp(_evade_end, eased)
	# Evade kicks the dust trail on too — gives the i-frame dash a
	# satisfying afterimage even on a flat plane.
	if _dust_emitter != null:
		_dust_emitter.emitting = true
	if t >= 1.0:
		_set_state(State.IDLE)

func _on_died() -> void:
	# Phoenix — one-shot revival: full HP, 2s of i-frame, skip the
	# death.emit / sprite tween entirely. _phoenix_used latches so a
	# second death plays out normally.
	if has_phoenix and not _phoenix_used:
		_phoenix_used = true
		if _health != null:
			_health.hp = _health.max_hp
			# damaged(0) repaints the HpBar3D without going through
			# take_damage (which would no-op on hp==0 path).
			_health.damaged.emit(0)
		_iframe_t = 2.0
		if _sprite_rig != null and _sprite_rig.has_method("start_iframe_blink"):
			_sprite_rig.call("start_iframe_blink", 2.0)
		return
	# Tell Main FIRST so GameOverScreen + SaveSystem fire with the PC
	# node still alive (Main reads kill count / level off live state).
	# The 0.5s death tween runs in parallel — the screen pops up while
	# the sprite is still fading, which reads as a clean transition.
	died.emit()
	if _sprite_rig != null:
		_sprite_rig.play_death_then_free(self, 0.5)
	else:
		queue_free()


## Callback the Boss fires when a parry resolves. Centralizes any
## parry-triggered card effects (Counter Step today; Zen meter feeds
## off the same hook).
func on_parry_success() -> void:
	if has_counter_step:
		counter_step_until_msec = Time.get_ticks_msec() + 1000
	if _zen_system != null and _zen_system.has_method("add"):
		_zen_system.call("add", 1)
	_play_sfx("parry")


## Wired by Main / Testplay after building ZenSystem. Holds the ref so
## on_parry_success / _fire_slash can poke it without a group lookup
## per call.
func bind_zen_system(zs: Node) -> void:
	_zen_system = zs


# ══════════════ 4안 — 비도(Kunai) 기본 공격 ══════════════

## Per-frame: toggle auto-aim, tick reload/cooldown, fire while held.
func _update_kunai(delta: float) -> void:
	if Input.is_action_just_pressed("autoaim"):
		_autoaim = not _autoaim
	if _fire_cd > 0.0:
		_fire_cd -= delta
	if _reload_t > 0.0:
		_reload_t -= delta
		if _reload_t <= 0.0:
			_ammo = data.max_ammo  # reload complete
		return  # no firing mid-reload
	# Slash dash / evade take priority — don't throw kunai then.
	if _state == State.DASHING or _state == State.EVADING:
		return
	if Input.is_action_pressed("fire") and _fire_cd <= 0.0 and _ammo > 0:
		if _is_pointer_over_ui():
			return
		_fire_kunai()


func _fire_kunai() -> void:
	if kunai_scene == null:
		return
	# Direction: auto-aim → nearest enemy in radius; else mouse.
	var dir: Vector3
	if _autoaim:
		var target := _lock_on_target()
		if target != null:
			dir = target.global_position - global_position
			dir.y = 0.0
			dir = dir.normalized() if dir.length() > 0.01 else _mouse_to_world_dir()
		else:
			dir = _mouse_to_world_dir()
	else:
		dir = _mouse_to_world_dir()
	if dir.length() < 0.01:
		dir = _aim_dir
	_aim_dir = dir
	var kunai := kunai_scene.instantiate()
	if kunai.has_method("configure"):
		kunai.call("configure", dir, data.kunai_speed, data.kunai_damage, data.kunai_lifetime)
	get_tree().current_scene.add_child(kunai)
	(kunai as Node3D).global_position = global_position + dir * 0.6
	_ammo -= 1
	_fire_cd = data.fire_cooldown
	if _sprite_rig != null:
		_sprite_rig.set_facing(dir.x)
	_play_sfx("kunai")
	if _ammo <= 0:
		_reload_t = data.reload_time  # auto-reload when emptied


## Nearest live enemy within `autoaim_radius` (XZ). Distance ties resolve
## randomly per the design (5안-style fairness).
func _lock_on_target() -> Node3D:
	var r2: float = data.autoaim_radius * data.autoaim_radius
	var best_d2: float = INF
	var ties: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node3D):
			continue
		if "_dead" in e and e._dead:
			continue
		var to_e: Vector3 = (e as Node3D).global_position - global_position
		to_e.y = 0.0
		var d2: float = to_e.length_squared()
		if d2 > r2:
			continue
		if d2 < best_d2 - 0.04:
			best_d2 = d2
			ties = [e]
		elif absf(d2 - best_d2) <= 0.04:
			ties.append(e)
	if ties.is_empty():
		return null
	return ties[randi() % ties.size()] as Node3D


# ══════════════ 4안 — 일섬 게이지 ══════════════

## Add to the slash gauge (×gain mult), clamped to max. Called from Main
## on kill / gem pickup and from take_hit on perfect dodge.
func add_slash_gauge(amount: float) -> void:
	if amount <= 0.0:
		return
	_slash_gauge = min(_slash_gauge + amount * slash_gauge_gain_mult, data.slash_gauge_max)


## Convenience hooks Main / Testplay call so they don't have to read the
## PC's PlayerData for the per-source gauge amounts.
func gain_gauge_on_kill() -> void:
	add_slash_gauge(data.slash_gauge_on_kill)

func gain_gauge_on_gem() -> void:
	add_slash_gauge(data.slash_gauge_on_gem)


# ══════════════ 4안 — 피격 넉백 ══════════════

## Shove every nearby non-boss enemy away from the PC when struck. Direct
## position push (enemies' chase re-converges over the i-frame window).
func _knockback_nearby_enemies() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node3D):
			continue
		if e.is_in_group("boss"):
			continue  # bosses don't get shoved
		var to_e: Vector3 = (e as Node3D).global_position - global_position
		to_e.y = 0.0
		var d: float = to_e.length()
		if d < KNOCKBACK_RADIUS and d > 0.01:
			var push: float = KNOCKBACK_FORCE * (1.0 - d / KNOCKBACK_RADIUS)
			(e as Node3D).global_position += to_e.normalized() * push


# ══════════════ 4안 — HUD getters (Main reads these) ══════════════

func get_hp() -> int:
	return _health.hp if _health != null else 0

func get_max_hp() -> int:
	return _health.max_hp if _health != null else 0

func slash_gauge_frac() -> float:
	return clamp(_slash_gauge / max(data.slash_gauge_max, 1.0), 0.0, 1.0)

func is_slash_ready() -> bool:
	return _slash_gauge >= data.slash_gauge_max

func get_ammo() -> int:
	return _ammo

func get_max_ammo() -> int:
	return data.max_ammo

func is_reloading() -> bool:
	return _reload_t > 0.0

## 0→1 reload progress (1.0 when not reloading).
func reload_frac() -> float:
	if _reload_t <= 0.0:
		return 1.0
	return clamp(1.0 - _reload_t / max(data.reload_time, 0.01), 0.0, 1.0)


# ────── M7 sound hook helpers ──────
# Cheap wrappers around the SoundManager Autoload. Guards keep these
# safe in scenes that haven't booted the autoload yet (Testplay run
# from F6 doesn't bypass it, but the guard costs nothing).

func _has_sound_manager() -> bool:
	# Autoload nodes live as children of /root. Look up by name.
	var root := get_tree().root if get_tree() != null else null
	if root == null:
		return false
	return root.has_node("SoundManager")


func _play_sfx(name: String) -> void:
	if not _has_sound_manager():
		return
	var sm := get_tree().root.get_node("SoundManager")
	if sm != null and sm.has_method("play_sfx"):
		sm.call("play_sfx", name)

## Foot-dust particle emitter. Lives as a child of the PC so it follows
## the body without any explicit position sync. We toggle `emitting`
## from movement code paths; the particles themselves are CPU-driven
## with a short lifetime (0.4s) so the trail clears quickly when the
## PC stops.
func _build_dust_emitter() -> void:
	_dust_emitter = CPUParticles3D.new()
	_dust_emitter.name = "DustEmitter"
	_dust_emitter.amount = 10
	_dust_emitter.lifetime = 0.4
	_dust_emitter.one_shot = false
	_dust_emitter.emitting = false
	_dust_emitter.explosiveness = 0.0
	_dust_emitter.local_coords = false  # particles stay in world space, trailing the PC
	_dust_emitter.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_dust_emitter.emission_sphere_radius = 0.18
	# Particles puff upward and outward with mild spread, then settle.
	_dust_emitter.direction = Vector3(0, 1, 0)
	_dust_emitter.spread = 45.0
	_dust_emitter.initial_velocity_min = 0.3
	_dust_emitter.initial_velocity_max = 0.7
	_dust_emitter.gravity = Vector3(0, -0.6, 0)
	_dust_emitter.scale_amount_min = 0.08
	_dust_emitter.scale_amount_max = 0.18
	# Visual: a tiny billboarded quad in a muted dust tone. The material
	# is set on PrimitiveMesh.material (CPUParticles3D draws each
	# particle as a copy of mesh, taking that material).
	var dust_mat := StandardMaterial3D.new()
	dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dust_mat.albedo_color = Color(0.72, 0.65, 0.55, 0.55)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.2, 0.2)
	quad.material = dust_mat
	_dust_emitter.mesh = quad
	# Sit slightly off the ground so particles emit at foot level rather
	# than from the PC's pivot (which is at root height ~0).
	_dust_emitter.position = Vector3(0, 0.08, 0)
	add_child(_dust_emitter)
