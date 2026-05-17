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
@export var elite_enemy_scene: PackedScene
@export var camera_scene: PackedScene

@export_group("Effects")
@export var explosion_burst_scene: PackedScene
@export var circular_slash_scene: PackedScene

@export_group("UI / Chapter")
@export var exp_bar_scene: PackedScene
@export var level_up_screen_scene: PackedScene
@export var chapter_clear_screen_scene: PackedScene
@export var boss_scene: PackedScene
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
# Whether a type-2 elite died this frame and is waiting for the next
# Player.slash_finished to fire the bonus circular slash.
var _pending_circular_slash: bool = false
# Active bullet-time tween so retriggering can cancel cleanly.
var _bullettime_tween: Tween
# Tracks whether bullet-time is currently dilating world speed. Newly spawned
# enemies / freshly fired arrows read this on creation so they don't run at
# full speed while the world is supposed to be slow.
var _bullettime_active: bool = false

# --- Chapter / EXP / HUD ---
# Note: explicit preloads (avoid relying on class_name cache, which doesn't
# refresh under --headless without a prior editor run).
const _ExpSystemScript := preload("res://scripts/managers/ExpSystem.gd")
const _UpgradeSystemScript := preload("res://scripts/managers/UpgradeSystem.gd")
const _WaveManagerScript := preload("res://scripts/managers/WaveManager.gd")
const _InfiniteGroundScript := preload("res://scripts/managers/InfiniteGround.gd")
var _exp_system: Node
var _exp_bar: CanvasLayer
var _wave_mgr: Node
var _chapter_cleared: bool = false

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
	if _bullettime_active and "time_scale_mult" in inst:
		inst.time_scale_mult = bullettime_slow_factor
	_enemies_root.add_child(inst)
	if inst is Node3D:
		(inst as Node3D).global_position = _pick_offscreen_spawn(r_min, r_max)
	_wire_enemy_lifecycle(inst)

## Spawn an elite with a pre-set effect_type. The effect_type must be
## written BEFORE add_child so the elite's _ready() picks it up to label
## the head-icon.
func _spawn_one_elite(scene: PackedScene, r_min: float, r_max: float, effect_type: int) -> void:
	if scene == null:
		return
	var inst := scene.instantiate()
	if "effect_type" in inst:
		inst.effect_type = effect_type
	if _bullettime_active and "time_scale_mult" in inst:
		inst.time_scale_mult = bullettime_slow_factor
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
	var amount := 1  # regular LV1 melee/ranged
	if enemy is EliteEnemy:
		var t: int = enemy.effect_type
		match t:
			1: amount = 3
			2: amount = 5
			3: amount = 10
			_: amount = 3
	elif "_lv" in enemy and enemy._lv >= 2:
		amount = 2
	_exp_system.add_exp(amount)

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

	# Wave manager — drives the population-curve drip + chapter beats.
	_wave_mgr = _WaveManagerScript.new()
	_wave_mgr.name = "WaveManager"
	_wave_mgr.request_spawn_cb = Callable(self, "_request_spawn")
	_wave_mgr.count_alive_cb   = Callable(self, "_count_alive_mobs")
	_wave_mgr.spawn_elites_cb  = Callable(self, "_chapter_spawn_elites")
	_wave_mgr.spawn_boss_cb    = Callable(self, "_chapter_spawn_boss")
	add_child(_wave_mgr)

## --- Chapter 1 wave handlers ---

## WaveManager calls this once per drip tick (1.0s). Choose mob type by
## a fixed 5:1 melee:ranged ratio; melee uses LV2 data once `lv >= 2`.
## Ranged mobs stay LV1 (no LV2 ranged data resource yet).
func _request_spawn(lv: int) -> void:
	var spawn_ranged: bool = randf() < 0.16  # ≈ 1/6 → 5:1 ratio
	if spawn_ranged:
		_spawn_one(ranged_enemy_scene, ranged_spawn_min_radius, ranged_spawn_max_radius)
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

## One-shot at t=120 — boss spawns off-screen so it stomps in visibly.
func _chapter_spawn_boss() -> void:
	if boss_scene == null:
		return
	var boss := boss_scene.instantiate()
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
	if _bullettime_active and "time_scale_mult" in inst:
		inst.time_scale_mult = bullettime_slow_factor
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
	# Pause world progression and show the clear screen.
	tree.paused = true
	var clear := chapter_clear_screen_scene.instantiate() as CanvasLayer
	add_child(clear)

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

## Called by EliteEnemy._on_died(). Routes to the matching payload.
func trigger_elite_effect(effect_type: int, pos: Vector3) -> void:
	match effect_type:
		1:
			_spawn_explosion(pos)
		2:
			_queue_circular_slash_after_slash()
		3:
			_start_bullettime(bullettime_duration)

func _spawn_explosion(pos: Vector3) -> void:
	if explosion_burst_scene == null:
		return
	var burst := explosion_burst_scene.instantiate() as Node3D
	add_child(burst)
	burst.global_position = pos

func _spawn_circular_slash(pos: Vector3) -> void:
	if circular_slash_scene == null:
		return
	var slash := circular_slash_scene.instantiate() as Node3D
	add_child(slash)
	slash.global_position = pos

## A type-2 elite died. If the player is still in their iaido dash, wait
## for slash_finished; otherwise the slash already ended, fire immediately
## at the player's current position.
func _queue_circular_slash_after_slash() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if _pending_circular_slash:
		return  # already queued
	# Player has signal `slash_finished`. State.DASHING == 2 (from Player.State).
	var is_dashing: bool = false
	if "_state" in _player:
		is_dashing = _player._state == 2  # State.DASHING
	if is_dashing and _player.has_signal("slash_finished"):
		_pending_circular_slash = true
		_player.slash_finished.connect(_on_pending_slash_finished, CONNECT_ONE_SHOT)
		# Safety: if Player dies before slash_finished fires (CONNECT_ONE_SHOT
		# auto-disconnects on emit; but on emitter free the callback never
		# runs and the flag would stay stuck forever, blocking future type-2
		# effects). Force-clear after a short window.
		get_tree().create_timer(1.5).timeout.connect(_clear_pending_circular_slash)
	else:
		_spawn_circular_slash((_player as Node3D).global_position)

func _on_pending_slash_finished() -> void:
	_pending_circular_slash = false
	if _player == null or not is_instance_valid(_player):
		return
	_spawn_circular_slash((_player as Node3D).global_position)

func _clear_pending_circular_slash() -> void:
	# No-op if the signal already cleared us — this is just a watchdog.
	_pending_circular_slash = false

## --- Bullet-time / monochrome ---

func _start_bullettime(duration: float) -> void:
	if _world_env == null:
		return
	_bullettime_active = true
	# Slow all current enemies (and any arrows in flight).
	for e in get_tree().get_nodes_in_group("enemies"):
		if "time_scale_mult" in e:
			e.time_scale_mult = bullettime_slow_factor
	# Arrows aren't in a group — scan our direct children for any in flight.
	_apply_slow_to_loose_arrows(bullettime_slow_factor)

	# Tween saturation: snap to 0 fast, hold, then ease back to normal.
	if _bullettime_tween != null and _bullettime_tween.is_valid():
		_bullettime_tween.kill()
	var env := _world_env.environment
	_bullettime_tween = create_tween()
	_bullettime_tween.tween_property(env, "adjustment_saturation", 0.0, 0.15)
	_bullettime_tween.tween_interval(max(duration - 0.45, 0.05))
	_bullettime_tween.tween_property(env, "adjustment_saturation", _NORMAL_SATURATION, 0.3)
	_bullettime_tween.tween_callback(_end_bullettime)

func _end_bullettime() -> void:
	_bullettime_active = false
	for e in get_tree().get_nodes_in_group("enemies"):
		if "time_scale_mult" in e:
			e.time_scale_mult = 1.0
	_apply_slow_to_loose_arrows(1.0)

func _apply_slow_to_loose_arrows(factor: float) -> void:
	# Arrows are spawned as direct children of the current scene (us),
	# not under _enemies_root. Walk our children to grab any.
	for child in get_children():
		if child is EnemyArrow and "time_scale_mult" in child:
			child.time_scale_mult = factor

func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "HUD"
	add_child(canvas)
	var vbox := VBoxContainer.new()
	vbox.position = Vector2(20, 16)
	vbox.add_theme_constant_override("separation", 4)
	canvas.add_child(vbox)

	# (HP text label removed — the PC now wears a floating HpBar3D over its
	#  head, so the corner text became redundant.)

	_kill_label = Label.new()
	_kill_label.text = "Kills: 0"
	_kill_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_kill_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_kill_label.add_theme_constant_override("outline_size", 4)
	_kill_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_kill_label)

	_info_label = Label.new()
	_info_label.text = "WASD : move    LMB(hold): aim slash    R: restart"
	_info_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_info_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_info_label.add_theme_constant_override("outline_size", 4)
	_info_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_info_label)

func _update_hud() -> void:
	if _player == null or not is_instance_valid(_player):
		# PC freed — no live HP to read; the floating bar disappeared with it.
		return
	_kill_label.text = "Kills: %d" % _kill_count
