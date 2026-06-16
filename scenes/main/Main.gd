class_name Main
extends Node3D

## Greybox arena bootstrap.
## - Builds ground / lighting / environment procedurally so the scene file
##   stays minimal and easy to inspect.
## - Spawns the player + an enemy wave around the origin.
## - 'R' to restart.

@export var player_scene: PackedScene
@export var melee_enemy_scene: PackedScene
@export var ranged_enemy_scene: PackedScene
## 베리에이션2 — 리프(곡선 점프 슬램) 전용 근접몹. 1분대부터 ~10% 등장.
@export var leaper_enemy_scene: PackedScene
@export var elite_enemy_scene: PackedScene
@export var camera_scene: PackedScene

@export_group("Effects")
@export var explosion_burst_scene: PackedScene
@export var circular_slash_scene: PackedScene
## EXP gem dropped from enemy corpses — magnets to the PC, credits EXP on
## pickup. See ExpGem.gd. Wired in Main.tscn.
@export var exp_gem_scene: PackedScene

@export_group("UI / Chapter")
@export var exp_bar_scene: PackedScene
@export var level_up_screen_scene: PackedScene
@export var chapter_clear_screen_scene: PackedScene
## PC death overlay — instantiated from `_on_player_died` once the PC's
## HP hits 0. Same CanvasLayer pattern as the clear screen.
@export var game_over_screen_scene: PackedScene
## Default / fallback boss — kept for back-compat when `boss_scenes` is
## empty. New chapter slots should use `boss_scenes[chapter_idx]`.
@export var boss_scene: PackedScene
## Per-chapter wave curves. Length = chapter count. `chapter_curves[0]` is
## Chapter 1 (so the user-facing chapter id is `index + 1`). Main injects
## the active one into WaveManager via `set_curve` on chapter entry.
@export var chapter_curves: Array[WaveCurve] = []
## Per-chapter boss PackedScenes. Same indexing as `chapter_curves`. If
## an entry is null or the array is shorter than the chapter index, we
## fall back to `boss_scene`.
@export var boss_scenes: Array[PackedScene] = []
## LV2 melee data resource — assigned in editor (MeleeEnemyDataLv2.tres).
@export var melee_enemy_data_lv2: EnemyData

@export_group("Arena")
@export var ground_size: float = 60.0
@export var ground_color: Color = Color(0.34, 0.45, 0.28)
@export var path_color: Color = Color(0.45, 0.4, 0.32)

@export_group("Spawning")
@export var melee_count: int = 15
@export var ranged_count: int = 4
@export var elite_count: int = 3
@export var melee_spawn_min_radius: float = 6.0
@export var melee_spawn_max_radius: float = 12.0
@export var ranged_spawn_min_radius: float = 10.0
@export var ranged_spawn_max_radius: float = 18.0
@export var elite_spawn_min_radius: float = 8.0
@export var elite_spawn_max_radius: float = 14.0
@export var respawn_delay: float = 3.0

@export_group("Bullet-time")
@export var bullettime_slow_factor: float = 0.25
@export var bullettime_duration: float = 3.0

const _NORMAL_SATURATION: float = 1.12

var _player: Node
var _camera: HD2DCamera
var _enemies_root: Node3D
# Legacy auto-respawn flags — unused in chapter mode but kept so the old
# `_warm_placeholder_cache` signature stays stable for downstream tools.
var _wave_active: bool = false
var _respawn_timer: float = 0.0
var _info_label: Label
var _kill_label: Label
var _kill_count: int = 0

# Stored reference so bullet-time can toggle saturation on the live env.
var _world_env: WorldEnvironment

# --- Chapter / EXP / HUD ---
# Note: explicit preloads (avoid relying on class_name cache, which doesn't
# refresh under --headless without a prior editor run).
const _ExpSystemScript := preload("res://scripts/managers/ExpSystem.gd")
const _UpgradeSystemScript := preload("res://scripts/managers/UpgradeSystem.gd")
const _WaveManagerScript := preload("res://scripts/managers/WaveManager.gd")
const _InfiniteGroundScript := preload("res://scripts/managers/InfiniteGround.gd")
const _SaveSystemScript := preload("res://scripts/managers/SaveSystem.gd")
const _MetaScript := preload("res://scripts/managers/MetaProgressionSystem.gd")
const _ZenSystemScript := preload("res://scripts/managers/ZenSystem.gd")
# Refactor pass (M8) — elite payloads + bullet-time pulled into shared
# service nodes so Main + Testplay run identical code instead of mirrored
# copies. Main keeps a thin `trigger_elite_effect` delegate (EliteEnemy
# calls it on current_scene) and queries `_bullet_time_service.is_active()`
# from the spawn helpers.
const _EliteEffectServiceScript := preload("res://scripts/managers/EliteEffectService.gd")
const _BulletTimeServiceScript := preload("res://scripts/managers/BulletTimeService.gd")
var _elite_effect_service: Node
var _bullet_time_service: Node
var _exp_system: Node
var _exp_bar: CanvasLayer
var _wave_mgr: Node
## ⏱ Zen meter (M4 후속 도입). Tracks consecutive perfect inputs and
## arms a "burst" flag on the PC for the next slash. HUD label below
## reads its `zen` / `max_zen` properties.
var _zen_system: Node
var _zen_label: Label
# 4안 HUD — 좌상단 HP 칸 / 하단 일섬 게이지 / 탄약·리로드 텍스트.
var _hp_box: HBoxContainer
var _hp_cells: Array = []
var _slash_gauge_bg: ColorRect
var _slash_gauge_bar: ColorRect
var _slash_gauge_label: Label
const _HP_FULL := Color(0.85, 0.15, 0.15)
const _HP_EMPTY := Color(0.22, 0.08, 0.08)
const _SLASH_GAUGE_W := 280.0
const _SLASH_GAUGE_H := 22.0
## 일섬 게이지 채움색 — 충전 중(시안) / READY(골드).
const _SLASH_GAUGE_FILL := Color(0.3, 0.7, 1.0, 0.9)
const _SLASH_GAUGE_FILL_READY := Color(1.0, 0.82, 0.2, 0.95)
var _chapter_cleared: bool = false
## Wall-clock ticks at the moment WaveManager started — used to compute
## the run's elapsed time for the result screen + SaveSystem record.
var _chapter_start_msec: int = 0
## Once-per-run guard: a PC dying mid-slash could in theory emit `died`
## twice (HealthComponent guards against negative HP, but signal wiring
## changes might break that). Keeps the overlay from double-spawning.
var _game_over_shown: bool = false
## Chapter id used for SaveSystem section keys. Stays 1 until M2's
## WaveCurve / chapter selection lands.
var _current_chapter: int = 1

func _ready() -> void:
	_warm_placeholder_cache()
	_build_environment()
	_build_ground()
	_build_lighting()
	_build_hud()
	_build_chapter_systems()


## Pre-build the placeholder textures used by every entity so the first spawn
## frame doesn't hitch on image generation. Cheap (a few ms one-time).
func _warm_placeholder_cache() -> void:
	PlaceholderSprite.make(Color(0.7, 0.85, 1.0))   # player
	PlaceholderSprite.make(Color(1.0, 0.45, 0.4))   # melee LV1
	PlaceholderSprite.make(Color(0.7, 0.25, 0.2))   # melee LV2 (darker red)
	PlaceholderSprite.make(Color(1.0, 0.75, 0.25))  # ranged
	PlaceholderSprite.make_projectile(Color(1.0, 0.95, 0.6))

	_enemies_root = Node3D.new()
	_enemies_root.name = "Enemies"
	add_child(_enemies_root)

	_spawn_player()
	_spawn_camera()
	# Chapter wave schedule kicks in from `_build_chapter_systems` — no
	# immediate wave here. WaveManager fires t=0 "base" milestone on its
	# first process tick to spawn the initial set.

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("restart"):
		get_tree().reload_current_scene()
		return
	_update_hud()

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_horizon_color = Color(0.78, 0.85, 0.95)
	psm.sky_top_color = Color(0.45, 0.7, 0.92)
	psm.ground_bottom_color = Color(0.25, 0.32, 0.22)
	psm.ground_horizon_color = Color(0.78, 0.85, 0.95)
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	# Reinhardt is cheaper than Filmic and visually fine for greybox.
	env.tonemap_mode = Environment.TONE_MAPPER_REINHARDT
	# Glow / SSAO / SSIL are the big-ticket post-effects; leave them all off.
	env.glow_enabled = false
	env.ssao_enabled = false
	env.ssil_enabled = false
	env.sdfgi_enabled = false
	env.volumetric_fog_enabled = false
	env.adjustment_enabled = true
	env.adjustment_saturation = _NORMAL_SATURATION
	we.environment = env
	add_child(we)
	_world_env = we

func _build_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(40.0), 0.0)
	sun.light_energy = 1.4
	# Shadows on a sun with many alpha-discard sprites are expensive AND look
	# odd on billboarded quads. Drop them; ambient + saturation reads fine.
	sun.shadow_enabled = false
	sun.light_color = Color(1.0, 0.96, 0.88)
	add_child(sun)

## Replaced the fixed-size ground (60×60 with corner props) with a
## PC-following InfiniteGround so the player can WASD in any direction
## without ever hitting the edge of the world. World-fixed props were
## removed in the same pass — with the ground scrolling around the PC,
## a prop placed at world position (8, 0, -2) would just drift off
## into nothing as soon as the PC moved. When chunk-based decoration
## lands, props come back as per-chunk procedural spawns.
func _build_ground() -> void:
	var ig := _InfiniteGroundScript.new()
	ig.name = "InfiniteGround"
	ig.ground_color = ground_color
	add_child(ig)
	if _player != null and _player is Node3D:
		ig.set_target(_player as Node3D)

func _spawn_player() -> void:
	if player_scene == null:
		push_error("Main.player_scene not set")
		return
	_player = player_scene.instantiate()
	_player.add_to_group("player")
	add_child(_player)
	(_player as Node3D).global_position = Vector3(0, 0, 0)
	# Hook the death signal so we can pop GameOverScreen + record stats.
	# `has_signal` guard keeps Main forward-compatible if Player.gd ever
	# loses the signal (it shouldn't, but defensive wiring is cheap).
	if _player.has_signal("died"):
		_player.died.connect(_on_player_died)
	# Echo card — listen for every completed slash; if the PC owns the
	# card, drop a CircularSlash at their foot 0.3s later. Main owns
	# the effect scene reference so we wire here rather than from
	# inside Player.gd.
	if _player.has_signal("slash_finished"):
		_player.slash_finished.connect(_on_player_slash_finished)
	# ⏱ Perfect dodge → short self-bullet-time (M3 후속). The service
	# isn't built until _build_chapter_systems, so we route through a
	# handler that defers to it (the PC can't dodge before then anyway).
	if _player.has_signal("perfect_dodge"):
		_player.perfect_dodge.connect(_on_player_perfect_dodge)

## ⏱ Perfect dodge reward — a short self-bullet-time through the same
## service the elite-3 effect uses, just a tighter window so it reads as
## a reactive "close call" slow rather than the big elite payoff.
func _on_player_perfect_dodge() -> void:
	if _bullet_time_service != null:
		_bullet_time_service.start(0.5)

func _spawn_camera() -> void:
	if camera_scene == null:
		push_error("Main.camera_scene not set")
		return
	_camera = camera_scene.instantiate() as HD2DCamera
	add_child(_camera)
	if _player != null:
		_camera.set_target(_player as Node3D)

func _spawn_wave() -> void:
	_wave_active = true
	for i in range(melee_count):
		_spawn_one(melee_enemy_scene, melee_spawn_min_radius, melee_spawn_max_radius)
	for i in range(ranged_count):
		_spawn_one(ranged_enemy_scene, ranged_spawn_min_radius, ranged_spawn_max_radius)
	# Elites: one of each effect type per wave (1=explode, 2=bonus, 3=bullet-time).
	for i in range(elite_count):
		var effect_type: int = (i % 3) + 1
		_spawn_one_elite(elite_enemy_scene, elite_spawn_min_radius, elite_spawn_max_radius, effect_type)

func _spawn_one(scene: PackedScene, r_min: float, r_max: float) -> void:
	if scene == null:
		return
	var inst := scene.instantiate()
	# If bullet-time is currently active, new spawns inherit the slow too
	# so the world stays consistently dilated.
	_inherit_bullettime(inst)
	_enemies_root.add_child(inst)
	if inst is Node3D:
		(inst as Node3D).global_position = _pick_offscreen_spawn(r_min, r_max)
	_wire_enemy_lifecycle(inst)


## Apply the current bullet-time slow to a freshly spawned node if the
## world is dilated right now. Replaces the inline `_bullettime_active`
## check that used to live in every spawn helper (pre-M8 refactor).
func _inherit_bullettime(inst: Node) -> void:
	if _bullet_time_service == null or not _bullet_time_service.is_active():
		return
	if "time_scale_mult" in inst:
		inst.time_scale_mult = _bullet_time_service.current_slow_factor()

## Spawn an elite with a pre-set effect_type. The effect_type must be
## written BEFORE add_child so the elite's _ready() picks it up to label
## the head-icon.
func _spawn_one_elite(scene: PackedScene, r_min: float, r_max: float, effect_type: int) -> void:
	if scene == null:
		return
	var inst := scene.instantiate()
	if "effect_type" in inst:
		inst.effect_type = effect_type
	_inherit_bullettime(inst)
	_enemies_root.add_child(inst)
	if inst is Node3D:
		(inst as Node3D).global_position = _pick_offscreen_spawn(r_min, r_max)
	_wire_enemy_lifecycle(inst)

## Hook a freshly spawned enemy into the bookkeeping pipeline:
##   - tree_exited bumps kill count AND awards EXP.
## We bind the instance into the callback so the EXP system can read its type.
func _wire_enemy_lifecycle(inst: Node) -> void:
	if inst == null:
		return
	if inst.has_signal("tree_exited"):
		inst.tree_exited.connect(_on_enemy_freed_with_ref.bind(inst))

## Number of angular sectors used by the STATIONARY-mode spawn picker.
## 12 = 30° slices, enough for an even ring around a standing PC.
const _SPAWN_SECTOR_COUNT: int = 12

## --- Sprint-aware surround spawn (option C) ---
## When the PC has real velocity (above _SPAWN_VEL_THRESHOLD), the
## picker switches from the sector-fill ring to a 70/30 split between
## a forward "path wall" cone and a tight ring around the PC. See each
## helper's docstring for the math.

## Below this speed, the PC counts as "stationary" and we use the
## legacy sector picker (preserves the standing-still ring distribution).
const _SPAWN_VEL_THRESHOLD: float = 1.0
## In motion mode: roll vs this to choose path-wall vs tight-ring.
const _PATH_WALL_PROBABILITY: float = 0.7
## Path-wall cone half-angle around the PC's velocity direction.
## ±60° → a 120° forward arc, wide enough to feel natural without
## bleeding into "behind the PC".
const _PATH_WALL_CONE_DEG: float = 60.0
## Seconds of velocity used to lead the path-wall anchor in front of
## the PC. 2.0s × move_speed=5 = 10 units ahead of where the PC is now.
const _PATH_WALL_LEAD_TIME: float = 2.0
## Spawn radius range from the leading anchor — keeps the wall a few
## seconds of travel ahead so the PC actually runs INTO it.
const _PATH_WALL_RADIUS_MIN: float = 14.0
const _PATH_WALL_RADIUS_MAX: float = 22.0
## Tight-ring radius: closer than the path wall but outside the PC's
## slash range (max 11) so a single slash can't sweep the ring clean.
const _TIGHT_RING_RADIUS_MIN: float = 6.0
const _TIGHT_RING_RADIUS_MAX: float = 10.0
## Beyond this XZ distance from the PC, an enemy doesn't count toward
## WaveManager's alive cap — it's "trailing" and effectively out of the
## fight. The wave manager will spawn replacements to keep pressure on
## the PC's local bubble. The trailing enemy isn't despawned; it keeps
## chasing, and once it closes back inside the radius it counts again.
const _BUDGET_CULL_DISTANCE: float = 30.0

## Pick a spawn position around the PC within [r_min, r_max], biased toward
## whichever angular direction currently has the FEWEST enemies. This
## defeats the "PC runs one way forever and slashes the chasing line" cheese
## — as soon as the PC bolts in a direction, that direction's sector goes
## empty and the next drip lands AHEAD of them, forcing engagement.
##
## All candidate positions still get a frustum check so spawns feel like
## they materialize off-screen, never pop in front of the camera.
## Spawn-position dispatcher. Two modes:
##   - PC stationary (velocity below threshold) → legacy 12-sector
##     even-ring picker (`_pick_sector_spawn`). Preserves the surround
##     behaviour the user already liked when standing still.
##   - PC moving → 70/30 split between a path-wall (forward cone,
##     leading anchor) and a tight ring around the PC. The path wall
##     puts enemies in the PC's path so a sprint actually runs INTO
##     them; the tight ring keeps a visible flank presence so the
##     player still reads as surrounded.
## The signature stays (r_min, r_max) so existing callers (`_spawn_one`,
## `_chapter_spawn_boss`, etc.) don't change. r_min/r_max are honored
## by the sector picker; the path-wall / tight-ring branches use their
## own tuned radii (see _PATH_WALL_* / _TIGHT_RING_* consts).
func _pick_offscreen_spawn(r_min: float, r_max: float) -> Vector3:
	var pv: Vector3 = Vector3.ZERO
	if _player != null and is_instance_valid(_player) and _player is CharacterBody3D:
		pv = (_player as CharacterBody3D).velocity
		pv.y = 0.0
	if pv.length() < _SPAWN_VEL_THRESHOLD:
		return _pick_sector_spawn(r_min, r_max)
	if randf() < _PATH_WALL_PROBABILITY:
		return _pick_path_wall_spawn(pv)
	return _pick_tight_ring_spawn()

## Legacy 12-sector picker — used when the PC isn't moving. Counts how
## many live enemies sit in each 30° sector around the PC, then drops
## a spawn into the emptiest sector at a random radius in [r_min,r_max].
## Off-screen check via the camera rig so the spawn pops outside the
## frustum, then a fallback at extended radius if every sector pick
## happened to land on-screen.
func _pick_sector_spawn(r_min: float, r_max: float) -> Vector3:
	var rig := get_tree().get_first_node_in_group("camera_rig")
	var anchor: Vector3 = Vector3.ZERO
	if _player != null and is_instance_valid(_player):
		anchor = (_player as Node3D).global_position

	# 1) Count live enemies in each angular sector around the PC.
	var counts: PackedInt32Array
	counts.resize(_SPAWN_SECTOR_COUNT)
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		if "_dead" in e and e._dead:
			continue
		var diff: Vector3 = (e as Node3D).global_position - anchor
		var ang: float = atan2(diff.z, diff.x)
		if ang < 0.0:
			ang += TAU
		var sec: int = int(ang / (TAU / float(_SPAWN_SECTOR_COUNT))) % _SPAWN_SECTOR_COUNT
		counts[sec] += 1

	# 2) Sort sectors by count ascending (emptiest first). Ties broken by
	# random shuffle so the spawn doesn't always land in the same sector.
	var order: Array = []
	for i in _SPAWN_SECTOR_COUNT:
		order.append([counts[i], i])
	order.shuffle()  # tie-break randomization
	order.sort_custom(func(a, b): return a[0] < b[0])

	# 3) Walk sectors emptiest-first; for each, take up to 3 random picks.
	# Accept the first off-screen pick.
	var sector_span: float = TAU / float(_SPAWN_SECTOR_COUNT)
	for entry in order:
		var sec_idx: int = entry[1]
		var sec_start: float = float(sec_idx) * sector_span
		for attempt in 3:
			var ang_pick: float = sec_start + randf() * sector_span
			var radius: float = lerp(r_min, r_max, randf())
			var pos := anchor + Vector3(cos(ang_pick) * radius, 0.0, sin(ang_pick) * radius)
			if rig == null or not rig.has_method("is_world_pos_visible"):
				return pos  # headless: accept the first pick from the emptiest sector
			if not rig.call("is_world_pos_visible", pos + Vector3(0, 0.6, 0)):
				return pos

	# 4) Fallback: emptiest sector at extended radius, accept on-screen.
	var fb_idx: int = order[0][1]
	var fb_ang: float = float(fb_idx) * sector_span + randf() * sector_span
	var fb_radius: float = r_max + 5.0
	return anchor + Vector3(cos(fb_ang) * fb_radius, 0.0, sin(fb_ang) * fb_radius)

## Path-wall spawn — drops the enemy a couple of seconds in front of
## the PC, anywhere inside a ±60° cone around their movement direction.
## With move_speed=5 and lead_time=2.0 the anchor is 10 units ahead;
## radii 14~22 from there means spawns are 24~32 units in front of the
## PC's current position when shot straight forward, or 14~22 units
## "ahead and to the side" at cone edges. Frustum check skipped — the
## point is to put bodies in the PC's path, even if a sliver is
## briefly visible at the screen edge.
func _pick_path_wall_spawn(vel: Vector3) -> Vector3:
	var pc_pos: Vector3 = (_player as Node3D).global_position if _player != null else Vector3.ZERO
	var anchor: Vector3 = pc_pos + vel * _PATH_WALL_LEAD_TIME
	var center_angle: float = atan2(vel.z, vel.x)
	var half_cone: float = deg_to_rad(_PATH_WALL_CONE_DEG)
	var angle: float = center_angle + randf_range(-half_cone, half_cone)
	var radius: float = lerp(_PATH_WALL_RADIUS_MIN, _PATH_WALL_RADIUS_MAX, randf())
	return anchor + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)

## Tight-ring spawn — drops the enemy in a small ring around the PC's
## current position, any direction. Radius is just outside the slash
## range so a single slash can't sweep the whole ring. Frustum check
## skipped because the whole point is "right next to the PC", which
## by definition is on screen.
func _pick_tight_ring_spawn() -> Vector3:
	var pc_pos: Vector3 = (_player as Node3D).global_position if _player != null else Vector3.ZERO
	var angle: float = randf() * TAU
	var radius: float = lerp(_TIGHT_RING_RADIUS_MIN, _TIGHT_RING_RADIUS_MAX, randf())
	return pc_pos + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)

func _on_enemy_freed_with_ref(enemy: Node) -> void:
	# Guard: during scene shutdown (quit / reload) Main itself may already
	# be detaching, in which case get_tree() returns null and downstream
	# pause/EXP logic blows up. Skip cleanly.
	if not is_inside_tree():
		return
	_kill_count += 1
	award_exp_for_kill(enemy)

func _on_enemy_freed() -> void:
	_kill_count += 1

## Award EXP for a kill. Caller passes the dying enemy node so we can read
## any per-enemy hint (EliteEnemy.effect_type → bigger reward, LV2 mob → 2,
## otherwise 1). Boss handled separately.
func award_exp_for_kill(enemy: Node) -> void:
	if _exp_system == null:
		return
	var base := 1  # regular LV1 melee/ranged
	if enemy is EliteEnemy:
		var t: int = enemy.effect_type
		match t:
			1: base = 3
			2: base = 5
			3: base = 10
			4: base = 8
			_: base = 3
	elif "_lv" in enemy and enemy._lv >= 2:
		base = 2
	# 처치 직접 EXP 는 거의 0(EXP_INSTANT_ON_KILL). 대부분의 EXP 는 떨어진 젬을
	# 주워야 들어온다 — 적을 죽이는 것만으로는 레벨이 거의 안 오른다.
	_exp_system.add_exp(EXP_INSTANT_ON_KILL)
	_drop_exp_gem(enemy, base)
	# Vampire card — roll on every kill (boss/elite/mob alike). Heal is
	# bounded by max_hp inside HealthComponent.heal.
	_try_vampire_heal()
	# 4안 — 처치 시 일섬 게이지 충전.
	if _player != null and is_instance_valid(_player) and _player.has_method("gain_gauge_on_kill"):
		_player.call("gain_gauge_on_kill")


## 처치 즉시 EXP — 0(사용자 밸런스). 적을 죽이는 것만으로는 거의 차지 않고,
## 떨어진 EXP 젬(오브젝트)을 주워야 레벨이 오른다. add_exp(0)은 no-op.
const EXP_INSTANT_ON_KILL := 0


## Drop an EXP gem carrying `value` at the dying enemy's position. The PC
## magnets it in (ExpGem.gd) and `collect_exp_gem` credits the value.
## `tree_exited` fires just before the node frees, so its global_position
## is still readable here. Falls back to immediate EXP if no gem scene
## is wired (clean-tscn safety).
func _drop_exp_gem(enemy: Node, value: int) -> void:
	if exp_gem_scene == null or enemy == null or not is_instance_valid(enemy):
		_exp_system.add_exp(value)
		return
	# Use the position captured at _on_died (set_meta). Reading
	# global_position here would give origin — tree_exited fires after the
	# node has detached, so its world transform is already gone, dropping
	# every gem at the map center.
	var pos: Vector3
	if enemy.has_meta("death_position"):
		pos = enemy.get_meta("death_position")
	elif enemy is Node3D and enemy.is_inside_tree():
		pos = (enemy as Node3D).global_position
	else:
		# No captured position and the node already left the tree (scene
		# teardown / forced free) — credit EXP without a gem, no error.
		_exp_system.add_exp(value)
		return
	var gem := exp_gem_scene.instantiate()
	if gem.has_method("configure"):
		gem.call("configure", value)
	add_child(gem)
	(gem as Node3D).global_position = Vector3(pos.x, 0.3, pos.z)


## Called by ExpGem.gd when the PC picks it up. Credits the carried EXP.
func collect_exp_gem(value: int) -> void:
	if _exp_system != null:
		_exp_system.add_exp(value)
	# 4안 — 젬 획득 시 일섬 게이지 충전.
	if _player != null and is_instance_valid(_player) and _player.has_method("gain_gauge_on_gem"):
		_player.call("gain_gauge_on_gem")


## Vampire card hook — `has_vampire` + `vampire_chance` live on the PC.
## We read them via duck-typed `in` checks so cards stay self-contained
## (no exhaustive type imports in Main).
func _try_vampire_heal() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if not ("has_vampire" in _player) or not _player.has_vampire:
		return
	var chance: float = 0.15
	if "vampire_chance" in _player:
		chance = _player.vampire_chance
	if randf() >= chance:
		return
	var hp_comp := _player.get_node_or_null("HealthComponent") as HealthComponent
	if hp_comp != null:
		hp_comp.heal(1)


## Echo card hook — every Player.slash_finished fires this. We queue a
## CircularSlash 0.3s later at the PC's current foot position if the
## card was picked.
func _on_player_slash_finished() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if not ("has_echo" in _player) or not _player.has_echo:
		return
	get_tree().create_timer(0.3).timeout.connect(_spawn_echo_circular_at_player)


func _spawn_echo_circular_at_player() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if not is_inside_tree():
		return
	if _elite_effect_service != null:
		_elite_effect_service.spawn_circular_slash((_player as Node3D).global_position)

func _build_chapter_systems() -> void:
	# EXP system as a child node so its lifetime tracks the scene.
	_exp_system = _ExpSystemScript.new()
	_exp_system.name = "ExpSystem"
	add_child(_exp_system)
	_exp_system.leveled_up.connect(_on_leveled_up)

	# Top-of-screen EXP bar + timer.
	if exp_bar_scene != null:
		_exp_bar = exp_bar_scene.instantiate() as CanvasLayer
		add_child(_exp_bar)
		if _exp_bar.has_method("set_exp_source"):
			_exp_bar.call("set_exp_source", _exp_system)

	# Refactor (M8) — bullet-time + elite-effect services. Created before
	# WaveManager so the first spawn frame can already query bullet-time
	# state, and EliteEnemy._on_died finds trigger_elite_effect live.
	_bullet_time_service = _BulletTimeServiceScript.new()
	_bullet_time_service.name = "BulletTimeService"
	_bullet_time_service.slow_factor = bullettime_slow_factor
	_bullet_time_service.duration = bullettime_duration
	add_child(_bullet_time_service)
	_bullet_time_service.setup(_world_env)

	_elite_effect_service = _EliteEffectServiceScript.new()
	_elite_effect_service.name = "EliteEffectService"
	_elite_effect_service.explosion_burst_scene = explosion_burst_scene
	_elite_effect_service.circular_slash_scene = circular_slash_scene
	add_child(_elite_effect_service)
	_elite_effect_service.setup(_player, _bullet_time_service)

	# Wave manager — drives the population-curve drip + chapter beats.
	_wave_mgr = _WaveManagerScript.new()
	_wave_mgr.name = "WaveManager"
	_wave_mgr.request_spawn_cb = Callable(self, "_request_spawn")
	_wave_mgr.count_alive_cb   = Callable(self, "_count_alive_mobs")
	_wave_mgr.spawn_elites_cb  = Callable(self, "_chapter_spawn_elites")
	_wave_mgr.spawn_boss_cb    = Callable(self, "_chapter_spawn_boss")
	# Inject the active chapter's WaveCurve. WaveManager's _process gates
	# on `curve != null` so a missing setup just stalls the spawner — the
	# push_warning gives the editor configuration error a single chance
	# to surface.
	var curve_idx: int = _current_chapter - 1
	if curve_idx >= 0 and curve_idx < chapter_curves.size() and chapter_curves[curve_idx] != null:
		_wave_mgr.set_curve(chapter_curves[curve_idx])
	else:
		push_warning("Main: no chapter_curves[%d] — WaveManager idle" % curve_idx)
	add_child(_wave_mgr)

	# Anchor the chapter timer at the moment WaveManager goes live so the
	# result-screen "클리어 시간" reads as time-since-first-spawn rather
	# than time-since-_ready (which includes the bootstrap frame).
	_chapter_start_msec = Time.get_ticks_msec()

	# M4 — apply permanent meta passives to the live PC + ExpSystem
	# RIGHT AFTER they're built, before the first physics tick. Owned
	# passive levels mutate PlayerData.move_speed / slash_width /
	# HealthComponent.max_hp / ExpSystem.gain_multiplier / etc.
	if _player != null and is_instance_valid(_player):
		_MetaScript.apply_to(_player, _exp_system)

	# ⏱ Zen meter — drives the perfect-input → burst slash reward loop.
	# Attached as a child so it lives only as long as the run does.
	_zen_system = _ZenSystemScript.new()
	_zen_system.name = "ZenSystem"
	add_child(_zen_system)
	if _player != null and is_instance_valid(_player):
		_zen_system.bind(_player)
	if _player != null and "bind_zen_system" in _player:
		_player.call("bind_zen_system", _zen_system)
	if _zen_system.has_signal("zen_changed"):
		_zen_system.zen_changed.connect(_on_zen_changed)

	# M6 — chapter-specific sky / ambient tint so each chapter reads as
	# a distinct biome at a glance. Runs after the WorldEnvironment has
	# been built in _build_environment.
	_apply_chapter_visuals()

## --- Chapter 1 wave handlers ---

## WaveManager calls this once per drip tick (1.0s). Choose mob type by
## the curve's ranged_ratio (Ch1 = 0.16 ≈ 5:1; Ch2 bumps to 0.2). Melee
## uses LV2 data once `lv >= 2`. Ranged mobs stay LV1 (no LV2 ranged
## data resource yet).
func _request_spawn(lv: int) -> void:
	var rr: float = 0.0
	var lr: float = 0.0
	if _wave_mgr != null:
		if _wave_mgr.has_method("ranged_ratio"):
			rr = float(_wave_mgr.call("ranged_ratio"))
		if _wave_mgr.has_method("leaper_ratio"):
			lr = float(_wave_mgr.call("leaper_ratio"))
	var roll: float = randf()
	# 원거리(2분대~) → 리퍼(1분대~, ≈10%) → 일반 근접 순으로 확률 분배.
	if roll < rr:
		_spawn_one(ranged_enemy_scene, ranged_spawn_min_radius, ranged_spawn_max_radius)
		return
	if leaper_enemy_scene != null and roll < rr + lr:
		_spawn_one(leaper_enemy_scene, melee_spawn_min_radius, melee_spawn_max_radius)
		return
	if lv >= 2:
		_spawn_one_lv2(melee_enemy_scene, melee_spawn_min_radius, melee_spawn_max_radius)
	else:
		_spawn_one(melee_enemy_scene, melee_spawn_min_radius, melee_spawn_max_radius)

## Live mob count consumed by WaveManager for the deficit calculation.
## Excludes the boss (its own `boss` group) so jam keeps spawning around it.
## Also skips dying/dead instances so we don't over-spawn while a fade tween
## is still running.
##
## Distance gate (option-C budget recovery):
##   An enemy that's trailing more than _BUDGET_CULL_DISTANCE behind the
##   PC doesn't count toward the alive cap. It's still alive and still
##   chasing — but for the purposes of "is the PC's local bubble full?",
##   it's effectively absent. This lets WaveManager keep spawning fresh
##   enemies inside the PC's bubble instead of stalling on the cap once
##   the player sprints away from a horde.
func _count_alive_mobs() -> int:
	var n: int = 0
	var pc_pos: Vector3 = Vector3.ZERO
	var pc_valid: bool = _player != null and is_instance_valid(_player)
	if pc_valid:
		pc_pos = (_player as Node3D).global_position
	var cull_d2: float = _BUDGET_CULL_DISTANCE * _BUDGET_CULL_DISTANCE
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		if e.is_in_group("boss"):
			continue
		if "_dead" in e and e._dead:
			continue
		if pc_valid:
			var d: Vector3 = (e as Node3D).global_position - pc_pos
			d.y = 0.0
			if d.length_squared() > cull_d2:
				continue  # trailing far behind — not in the PC's bubble.
		n += 1
	return n

## One-shot at t=60 — three elites (types 1/2/3), reuses existing system.
func _chapter_spawn_elites() -> void:
	for i in range(elite_count):
		var effect_type: int = (i % 3) + 1
		_spawn_one_elite(elite_enemy_scene, elite_spawn_min_radius, elite_spawn_max_radius, effect_type)

## One-shot at curve.boss_time — boss spawns off-screen so it stomps in
## visibly. Picks the chapter-specific boss from `boss_scenes` first,
## falls back to the legacy single `boss_scene` if not wired.
func _chapter_spawn_boss() -> void:
	var idx: int = _current_chapter - 1
	var scene: PackedScene = boss_scene
	if idx >= 0 and idx < boss_scenes.size() and boss_scenes[idx] != null:
		scene = boss_scenes[idx]
	if scene == null:
		push_warning("Main: no boss scene for chapter %d" % _current_chapter)
		return
	var boss := scene.instantiate()
	_enemies_root.add_child(boss)
	if boss is Node3D:
		(boss as Node3D).global_position = _pick_offscreen_spawn(10.0, 14.0)
	if boss.has_signal("boss_defeated"):
		boss.boss_defeated.connect(_on_boss_defeated)
	_wire_enemy_lifecycle(boss)

## Spawn a melee mob as LV2 — overrides data with the LV2 resource (HP 2)
## and tags _lv so EXP awards 2 instead of 1.
func _spawn_one_lv2(scene: PackedScene, r_min: float, r_max: float) -> void:
	if scene == null:
		return
	var inst := scene.instantiate()
	if "data" in inst and melee_enemy_data_lv2 != null:
		inst.data = melee_enemy_data_lv2
	if "_lv" in inst:
		inst._lv = 2
	_inherit_bullettime(inst)
	_enemies_root.add_child(inst)
	if inst is Node3D:
		(inst as Node3D).global_position = _pick_offscreen_spawn(r_min, r_max)
	_wire_enemy_lifecycle(inst)

func _on_boss_defeated() -> void:
	if _chapter_cleared:
		return
	_chapter_cleared = true
	if chapter_clear_screen_scene == null:
		return
	var tree := get_tree()
	if tree == null:
		return
	# Capture stats off live state BEFORE the save call so the file and
	# the result screen agree (kill count / level can't legally change
	# between the two reads, but the order is documented).
	var elapsed_sec: float = _elapsed_seconds()
	var pc_level: int = (_exp_system.level if _exp_system != null else 1)
	var stats := {"time": elapsed_sec, "kills": _kill_count, "level": pc_level}
	var beat: Dictionary = _SaveSystemScript.record_clear(_current_chapter, elapsed_sec, _kill_count, pc_level)
	var best: Dictionary = _SaveSystemScript.best_for(_current_chapter)
	# M4 — credit souls for the clear. Stash on stats so the screen can
	# show "+N 혼" alongside the time/kills/level rows.
	var souls_earned: int = _MetaScript.record_clear_reward(_current_chapter, elapsed_sec, _kill_count, pc_level)
	stats["souls"] = souls_earned
	# Basic gold currency — auto-awarded from kills + survival time.
	stats["gold"] = _MetaScript.record_gold_reward(_kill_count, elapsed_sec)
	# Pause world progression and show the clear screen.
	tree.paused = true
	var clear := chapter_clear_screen_scene.instantiate() as CanvasLayer
	add_child(clear)
	if clear.has_method("configure"):
		clear.call("configure", stats, best, beat)
	# `next_pressed` lets Main decide between advancing to the next
	# chapter and reloading the scene (final chapter case). The screen
	# self-frees after emitting; CONNECT_ONE_SHOT keeps a double-click
	# from firing twice during the fade-out.
	if clear.has_signal("next_pressed"):
		clear.next_pressed.connect(_on_chapter_next_pressed, CONNECT_ONE_SHOT)


## ChapterClearScreen.next_pressed handler — advance to the next chapter
## in-place if one exists, otherwise reload the current scene (Ch1
## restart placeholder until the OutGame menu lands in M4).
func _on_chapter_next_pressed() -> void:
	if _current_chapter < chapter_curves.size():
		_advance_chapter()
	else:
		var tree := get_tree()
		if tree != null:
			tree.paused = false
			tree.reload_current_scene()


## In-place chapter switch. Wipes the arena (enemies / loose effects),
## bumps `_current_chapter`, rebuilds WaveManager with the new curve,
## and resets the chapter clock. Keeps the PC's HP / EXP / card build
## intact — that persistence across chapters is the whole point of the
## meta loop.
func _advance_chapter() -> void:
	# 1) Wipe live combat surface. We free instead of group-walking
	# `enemies` exhaustively because boss/elite payloads (CircularSlash,
	# ExplosionBurst, etc.) sit outside that group as direct scene
	# children — easier to nuke the whole container + scan for stray
	# effect nodes.
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e):
			e.queue_free()
	# Loose arrows / effects parented to the scene root.
	for child in get_children():
		if child is EnemyArrow:
			child.queue_free()

	# 2) Stop any in-flight bullet-time (cancel resets saturation too).
	if _bullet_time_service != null:
		_bullet_time_service.cancel()

	# 3) Tear down WaveManager so the new chapter's curve+timers start
	# clean. (We could call set_curve and reset state in-place, but a
	# fresh instance is cheaper to reason about — same pattern Main uses
	# at boot.)
	if _wave_mgr != null and is_instance_valid(_wave_mgr):
		_wave_mgr.queue_free()
	_wave_mgr = null

	# 4) Reset chapter state.
	_current_chapter += 1
	_chapter_cleared = false
	_kill_count = 0
	_kill_label.text = "Kills: 0"

	# 5) Rebuild WaveManager with the new curve. Inlined instead of
	# calling _build_chapter_systems wholesale so we don't recreate the
	# ExpSystem (PC keeps their level/EXP between chapters).
	_wave_mgr = _WaveManagerScript.new()
	_wave_mgr.name = "WaveManager"
	_wave_mgr.request_spawn_cb = Callable(self, "_request_spawn")
	_wave_mgr.count_alive_cb   = Callable(self, "_count_alive_mobs")
	_wave_mgr.spawn_elites_cb  = Callable(self, "_chapter_spawn_elites")
	_wave_mgr.spawn_boss_cb    = Callable(self, "_chapter_spawn_boss")
	var curve_idx: int = _current_chapter - 1
	if curve_idx >= 0 and curve_idx < chapter_curves.size() and chapter_curves[curve_idx] != null:
		_wave_mgr.set_curve(chapter_curves[curve_idx])
	add_child(_wave_mgr)

	# 6) Anchor the new chapter's clock + resume.
	_chapter_start_msec = Time.get_ticks_msec()
	# M6 — refresh the sky/ambient for the new chapter.
	_apply_chapter_visuals()
	var tree := get_tree()
	if tree != null:
		tree.paused = false


## M6 — Chapter-specific environment tint. Reuses the ProceduralSkyMaterial
## from _build_environment, just adjusts colors + ambient energy per chapter.
## Defaults (Ch1) match the original _build_environment values.
func _apply_chapter_visuals() -> void:
	if _world_env == null or _world_env.environment == null:
		return
	var env: Environment = _world_env.environment
	var sky_mat := env.sky.sky_material as ProceduralSkyMaterial if env.sky != null else null
	match _current_chapter:
		1:
			if sky_mat != null:
				sky_mat.sky_horizon_color = Color(0.78, 0.85, 0.95)
				sky_mat.sky_top_color = Color(0.45, 0.7, 0.92)
				sky_mat.ground_bottom_color = Color(0.25, 0.32, 0.22)
				sky_mat.ground_horizon_color = Color(0.78, 0.85, 0.95)
			env.ambient_light_energy = 0.75
		2:
			# Ch2 — golden / dusk: hotter, lower sun feel.
			if sky_mat != null:
				sky_mat.sky_horizon_color = Color(0.92, 0.68, 0.48)
				sky_mat.sky_top_color = Color(0.65, 0.42, 0.55)
				sky_mat.ground_bottom_color = Color(0.32, 0.22, 0.18)
				sky_mat.ground_horizon_color = Color(0.85, 0.55, 0.42)
			env.ambient_light_energy = 0.65
		3:
			# Ch3 — twilight / night: darkest reading.
			if sky_mat != null:
				sky_mat.sky_horizon_color = Color(0.32, 0.25, 0.42)
				sky_mat.sky_top_color = Color(0.12, 0.1, 0.22)
				sky_mat.ground_bottom_color = Color(0.1, 0.1, 0.15)
				sky_mat.ground_horizon_color = Color(0.3, 0.22, 0.35)
			env.ambient_light_energy = 0.45


## Player.died handler — pause the world, record the death, show the
## GameOverScreen overlay with run stats + NEW! badges if the death
## beat any peak (yes, you can die further than you've ever cleared
## and that legitimately bumps best_kills / best_level).
func _on_player_died() -> void:
	if _game_over_shown:
		return
	_game_over_shown = true
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	var elapsed_sec: float = _elapsed_seconds()
	var pc_level: int = (_exp_system.level if _exp_system != null else 1)
	var stats := {"time": elapsed_sec, "kills": _kill_count, "level": pc_level}
	var beat: Dictionary = _SaveSystemScript.record_death(_current_chapter, elapsed_sec, _kill_count, pc_level)
	var best: Dictionary = _SaveSystemScript.best_for(_current_chapter)
	# M4 — death consolation 혼. Smaller than a clear but never zero so
	# every attempt feeds the meta loop.
	var souls_earned: int = _MetaScript.record_death_reward(_current_chapter, elapsed_sec, _kill_count, pc_level)
	stats["souls"] = souls_earned
	# Basic gold currency — auto-awarded from kills + survival time (death too).
	stats["gold"] = _MetaScript.record_gold_reward(_kill_count, elapsed_sec)
	tree.paused = true
	if game_over_screen_scene == null:
		# Fallback for runs where the export wasn't wired — log so the
		# editor link-up gets noticed but don't crash; the PC death
		# tween still finishes and R reloads. Future-proof against a
		# clean-tscn run.
		push_warning("Main.game_over_screen_scene not set — GameOver UI skipped")
		return
	var over := game_over_screen_scene.instantiate() as CanvasLayer
	add_child(over)
	if over.has_method("configure"):
		over.call("configure", stats, best, beat)


## Wall-clock seconds since WaveManager started. Centralised so the
## clear / death paths can't drift out of sync on the formula.
func _elapsed_seconds() -> float:
	if _chapter_start_msec <= 0:
		return 0.0
	return float(Time.get_ticks_msec() - _chapter_start_msec) / 1000.0

## ExpSystem fired leveled_up → pause world, show 3 upgrade cards, wait for
## a pick, apply it, then resume.
func _on_leveled_up(_new_level: int) -> void:
	if level_up_screen_scene == null:
		return
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	tree.paused = true
	var screen := level_up_screen_scene.instantiate() as CanvasLayer
	if screen == null:
		tree.paused = false
		return
	# UpgradeSystem is a RefCounted static class — call statically via preload.
	var cards: Array = _UpgradeSystemScript.draw(3)
	add_child(screen)
	if screen.has_method("show_cards"):
		screen.call("show_cards", cards)
	if screen.has_signal("card_selected"):
		screen.card_selected.connect(_on_upgrade_card_selected, CONNECT_ONE_SHOT)

func _on_upgrade_card_selected(card_id: String) -> void:
	_UpgradeSystemScript.apply(card_id, _player, _exp_system)
	var tree := get_tree()
	if tree != null:
		tree.paused = false

## --- Elite death payloads ---

## Called by EliteEnemy._on_died() on the current scene. Thin delegate
## to the shared EliteEffectService (M8 refactor — the payload bodies
## now live in scripts/managers/EliteEffectService.gd, identical for
## Main + Testplay). Bullet-time (type 3) routes through that service
## into BulletTimeService.
func trigger_elite_effect(effect_type: int, pos: Vector3) -> void:
	if _elite_effect_service != null:
		_elite_effect_service.trigger(effect_type, pos)

func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "HUD"
	add_child(canvas)
	var vbox := VBoxContainer.new()
	vbox.position = Vector2(20, 16)
	vbox.add_theme_constant_override("separation", 4)
	canvas.add_child(vbox)

	# 4안 — 좌상단 칸 단위 HP (빨간 사각형 더미 리소스). 빈 컨테이너만 만들고,
	# 칸 수/색은 `_refresh_hp_cells` 가 매 프레임 Player.get_hp()/get_max_hp()
	# 로 갱신·재구성한다. 머리 위 HpBar3D 와 병행 표시(역할이 다름).
	_hp_box = HBoxContainer.new()
	_hp_box.add_theme_constant_override("separation", 5)
	vbox.add_child(_hp_box)

	_kill_label = Label.new()
	_kill_label.text = "Kills: 0"
	_kill_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_kill_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_kill_label.add_theme_constant_override("outline_size", 4)
	_kill_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_kill_label)

	_info_label = Label.new()
	_info_label.text = "WASD: 이동   LMB: 근접 공격   RMB(hold): 일섬(게이지 100%)   SPACE: 회피   R: 재시작"
	_info_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_info_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_info_label.add_theme_constant_override("outline_size", 4)
	_info_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_info_label)

	# ⏱ Zen meter readout — sits below the info line, refreshed by
	# `_on_zen_changed`. "BURST!" overrides the count when armed.
	_zen_label = Label.new()
	_zen_label.text = "Zen: 0 / 5"
	_zen_label.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	_zen_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_zen_label.add_theme_constant_override("outline_size", 4)
	_zen_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_zen_label)

	_build_slash_gauge(canvas)

## 일섬 게이지 바 — 화면 하단 중앙. 0~100% 로 차오르고, 100% 도달 시 골드로
## 바뀌며 "READY" 표기 (우클릭으로 일섬 발동). `_update_hud` 가 매 프레임
## `Player.slash_gauge_frac()` / `is_slash_ready()` 를 읽어 갱신한다.
## Testplay 에도 동일 코드가 미러됨 (동기화 규칙).
func _build_slash_gauge(canvas: CanvasLayer) -> void:
	_slash_gauge_bg = ColorRect.new()
	_slash_gauge_bg.color = Color(0.07, 0.07, 0.09, 0.85)
	# 하단 중앙 앵커 — 창 크기가 바뀌어도 중앙 하단에 고정.
	_slash_gauge_bg.anchor_left = 0.5
	_slash_gauge_bg.anchor_right = 0.5
	_slash_gauge_bg.anchor_top = 1.0
	_slash_gauge_bg.anchor_bottom = 1.0
	_slash_gauge_bg.offset_left = -_SLASH_GAUGE_W * 0.5
	_slash_gauge_bg.offset_right = _SLASH_GAUGE_W * 0.5
	_slash_gauge_bg.offset_top = -(_SLASH_GAUGE_H + 28.0)
	_slash_gauge_bg.offset_bottom = -28.0
	_slash_gauge_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(_slash_gauge_bg)

	_slash_gauge_bar = ColorRect.new()
	_slash_gauge_bar.color = _SLASH_GAUGE_FILL
	_slash_gauge_bar.position = Vector2(2, 2)
	_slash_gauge_bar.size = Vector2(0, _SLASH_GAUGE_H - 4.0)
	_slash_gauge_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slash_gauge_bg.add_child(_slash_gauge_bar)

	_slash_gauge_label = Label.new()
	_slash_gauge_label.text = "일섬 0%"
	_slash_gauge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_slash_gauge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_slash_gauge_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_slash_gauge_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_slash_gauge_label.add_theme_constant_override("outline_size", 4)
	_slash_gauge_label.add_theme_font_size_override("font_size", 14)
	_slash_gauge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slash_gauge_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_slash_gauge_bg.add_child(_slash_gauge_label)

func _update_hud() -> void:
	if _player == null or not is_instance_valid(_player):
		# PC freed — no live HP to read; the floating bar disappeared with it.
		return
	_kill_label.text = "Kills: %d" % _kill_count
	_refresh_hp_cells()
	_refresh_slash_gauge()

## 좌상단 칸 단위 HP 갱신. 칸 수가 바뀌면(메타 강건 등) 재구성하고, 현재 HP
## 만큼 빨강(_HP_FULL), 나머지는 어두운색(_HP_EMPTY)으로 칠한다. Testplay 에도
## 동일 코드가 미러됨 (동기화 규칙).
func _refresh_hp_cells() -> void:
	if _hp_box == null or not _player.has_method("get_hp"):
		return
	var max_hp: int = 3
	if _player.has_method("get_max_hp"):
		max_hp = max(1, int(_player.call("get_max_hp")))
	# 칸 수 불일치 시 재구성 (스폰 직후 / 메타 HP 보너스 적용 후 자가 보정).
	if _hp_cells.size() != max_hp:
		for c in _hp_cells:
			if is_instance_valid(c):
				c.queue_free()
		_hp_cells.clear()
		for i in max_hp:
			var cell := ColorRect.new()
			cell.custom_minimum_size = Vector2(26, 26)
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_hp_box.add_child(cell)
			_hp_cells.append(cell)
	var cur_hp: int = int(_player.call("get_hp"))
	for i in _hp_cells.size():
		_hp_cells[i].color = _HP_FULL if i < cur_hp else _HP_EMPTY

## 매 프레임 일섬 게이지 바 갱신. Player 의 getter 를 덕타이핑으로 읽는다.
func _refresh_slash_gauge() -> void:
	if _slash_gauge_bar == null or not _player.has_method("slash_gauge_frac"):
		return
	# 모드2(즉발 일섬)는 일섬 게이지 미사용 → 게이지바 숨김.
	if _player.has_method("is_instant_slash_mode") and bool(_player.call("is_instant_slash_mode")):
		if _slash_gauge_bg != null:
			_slash_gauge_bg.visible = false
		return
	var frac: float = clampf(_player.call("slash_gauge_frac"), 0.0, 1.0)
	_slash_gauge_bar.size = Vector2((_SLASH_GAUGE_W - 4.0) * frac, _SLASH_GAUGE_H - 4.0)
	var ready: bool = _player.has_method("is_slash_ready") and bool(_player.call("is_slash_ready"))
	if ready:
		_slash_gauge_bar.color = _SLASH_GAUGE_FILL_READY
		_slash_gauge_label.text = "⚔ 일섬 READY (RMB)"
	else:
		_slash_gauge_bar.color = _SLASH_GAUGE_FILL
		_slash_gauge_label.text = "일섬 %d%%" % int(round(frac * 100.0))


## ⏱ Zen meter HUD refresh. Connected to ZenSystem.zen_changed at
## chapter setup; updates the label or paints BURST! while the burst
## flag is armed.
func _on_zen_changed(current: int, maximum: int) -> void:
	if _zen_label == null:
		return
	if _zen_system != null and "burst_armed" in _zen_system and _zen_system.burst_armed:
		_zen_label.text = "⚡ ZEN BURST READY ⚡"
		_zen_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
	else:
		_zen_label.text = "Zen: %d / %d" % [current, maximum]
		_zen_label.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
