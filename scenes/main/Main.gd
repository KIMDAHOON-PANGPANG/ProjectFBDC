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
## 슬래머(걸어와 2초 힘주기 → 광역 원형 슬램, 2방컷). MeleeEnemy behavior=SLAMMER.
@export var slammer_enemy_scene: PackedScene
@export var elite_enemy_scene: PackedScene
## 주술사(마법사) 엘리트 — 싱글톤. PC 주변 장판 흩뿌림 + 추격 시 텔레포트.
@export var sorcerer_enemy_scene: PackedScene
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
const _GameConfigScript := preload("res://scripts/managers/GameConfig.gd")
const _PauseOverlayScene := preload("res://scenes/ui/PauseOverlay.tscn")
const _PlayerHudScene := preload("res://scenes/ui/PlayerHud.gd")
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
const _SkillViewerScript := preload("res://scenes/ui/SkillViewer.gd")
var _elite_effect_service: Node
var _bullet_time_service: Node
var _skill_viewer: CanvasLayer
## 현재 런에서 선택한 카드 목록 [{id, name}, ...].
var _selected_cards: Array = []
var _exp_system: Node
var _exp_bar: CanvasLayer
var _wave_mgr: Node
## ⏱ Zen meter (M4 후속 도입). Tracks consecutive perfect inputs and
## arms a "burst" flag on the PC for the next slash. HUD label below
## reads its `zen` / `max_zen` properties.
var _zen_system: Node
var _zen_label: Label
# 하단 중앙 PC HUD (초상화 + HP 바 + 스택 + 레벨 뱃지). PlayerHud 컴포넌트.
var _player_hud: Control
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
	_play_log("세션 시작 — 챕터 %d" % _current_chapter)


## 플레이 로그 한 줄 — PlayLogger 자동로드가 있으면 기록(없으면 무시).
func _play_log(text: String) -> void:
	var pl = get_node_or_null("/root/PlayLogger")
	if pl != null and pl.has_method("event"):
		pl.call("event", text)


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

# ── ESC 개발 오버레이 / 웨이브 비율 프리셋 ──
# preset=1(근접 밀리): 근접90 / 원거리5 / 엘리트5
const _P1_MELEE: float = 0.90
const _P1_RANGED: float = 0.05
const _P1_ELITE: float = 0.05
# preset=2(일섬): 원거리60 / 근접35 / 엘리트5 · 총인구 ×0.2
const _P2_RANGED: float = 0.60
const _P2_MELEE: float = 0.35
const _P2_ELITE: float = 0.05
## 일섬 프리셋에서 PC 동선 방해용 근접몹 최소 인원(포위감). floor 3으로 낮춤.
const _PRESET2_MELEE_FLOOR: int = 3
## 근접 스폰 중 슬래머(내려찍기) 비율.
const _SLAMMER_RATIO: float = 0.3
## 주술사 단일 스폰 굴림 확률(없을 때만 — ~20틱 내 등장).
const _SORCERER_CHANCE: float = 0.05
## 0=곡선(기본) · 1=근접 웨이브 · 2=원거리 웨이브. ESC 툴 에디터(PauseOverlay)가 토글.
var _wave_preset: int = 0

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
	_apply_level_hp_scaling(inst)


## 레벨 스케일링 — 다중타 위협(엘리트/주술사/슬래머/보스)만 레벨당 +1 HP.
## 공격력 카드("참격 강화")를 안 찍으면 이들이 점점 안 죽는 리밸런스(잡몹/궁수=한 방 유지).
func _apply_level_hp_scaling(inst: Node) -> void:
	if inst == null or not is_instance_valid(inst):
		return
	var is_threat: bool = inst.is_in_group("elites") or inst.is_in_group("boss")
	if not is_threat and "behavior" in inst and int(inst.behavior) == 2:  # SLAMMER
		is_threat = true
	if not is_threat:
		return
	var lv: int = (_exp_system.level if _exp_system != null else 1)
	var bonus: int = max(0, lv - 1)
	if bonus <= 0:
		return
	var hc = inst.get_node_or_null("HealthComponent")
	if hc != null and hc.has_method("add_max_hp"):
		hc.add_max_hp(bonus)

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

## --- Edge-band spawn (초반 가시성 핵심) ---
## 카메라 footprint(offset 0,10.4,9.1 / fov 38°)은 PC 기준 방향별 가시 반경이
## 크게 다르다: 뒤(+Z)≈5, 옆≈8.5, 앞(-Z)≈9, 앞 대각 코너≈12.5. 따라서 고정 반경
## 6~12 스폰은 "앞쪽은 화면 안→거부→폴백 17유닛(너무 멈)" / "뒤쪽은 화면 밖이지만
## 대시 중 안 보임" 이 된다. → 방향별로 프러스텀 경계를 직접 찾아(이진탐색) 그 바로
## 바깥(_EDGE_BUFFER)에 놓으면 어느 방향이든 "화면 가장자리 바로 밖"이 되어 1~2초 내
## 걸어 들어온다. 카메라 파라미터가 바뀌어도 자동 추종(하드코딩 반경 아님).
## 화면 안에서 절대 안 생김(pop-in 금지) = edge + buffer 이므로 항상 프러스텀 밖.
const _EDGE_BUFFER: float = 1.6        # 가시 경계로부터 바깥으로 띄우는 여유(유닛)
const _EDGE_SEARCH_MAX: float = 26.0   # 경계 이진탐색 상한(이 안에서 경계를 못 찾으면 그대로 사용)
const _EDGE_SEARCH_ITERS: int = 9      # 이진탐색 반복(2^9 → ~0.05유닛 정밀도)
## 게임 시작/floor(화면 빔) 시 진행/정면 쪽에 우선 시드할 마릿수.
const _SEED_COUNT: int = 2

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

	# 3) Walk sectors emptiest-first; for each, take up to 3 random picks in
	# [r_min,r_max]. Accept the first that's already off-screen (작은 반경 우선
	# → 가까이 = 빨리 걸어 들어옴). 헤드리스면 첫 픽 채택.
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

	# 4) 모든 랜덤 픽이 화면 안이었다(앞/대각 방향 = 가시 반경이 r_max 보다 큼). 옛날엔
	# r_max+5(17유닛) 고정 폴백으로 멀리 던져 "초반 텅 빔" 의 원흉이었다. 이제는 가장
	# 비어있는 섹터 각도로 "프러스텀 경계 바로 밖"(edge + buffer)에 놓아 가장자리에서
	# 곧장 걸어 들어오게 한다(방향별 경계 자동 산출 → 멀리 안 감, pop-in 없음).
	var fb_idx: int = order[0][1]
	var fb_ang: float = float(fb_idx) * sector_span + randf() * sector_span
	return _edge_spawn_at(anchor, fb_ang)

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
	var center_angle: float = atan2(vel.z, vel.x)
	var half_cone: float = deg_to_rad(_PATH_WALL_CONE_DEG)
	var angle: float = center_angle + randf_range(-half_cone, half_cone)
	# 진행방향 ±cone 안 "화면 가장자리 바로 밖"에 놓는다. 옛날엔 lead anchor(10유닛 앞)
	# + radius 14~22 = 24~32유닛 앞이라 대시해도 한참 뒤에야 마주쳤다(초반/대시 공백 원흉).
	# edge+buffer 면 대시 진행방향 화면 끝에서 곧장 등장 → "앞에 적이 보임" 충족, 멀리 안 감.
	return _edge_spawn_at(pc_pos, angle)

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

## 주어진 각도(XZ 평면, atan2(z,x) 규약)로 PC(anchor)에서 뻗어 카메라 프러스텀 경계까지의
## 반경을 이진탐색으로 찾는다. 경계 = "마지막으로 화면 안인 반경". 헤드리스/카메라 없으면
## 보수적 기본값(11)을 돌려준다. 반환값 + _EDGE_BUFFER 가 "가장자리 바로 밖" 스폰 반경.
func _frustum_edge_radius(anchor: Vector3, angle: float) -> float:
	var rig := get_tree().get_first_node_in_group("camera_rig")
	if rig == null or not rig.has_method("is_world_pos_visible"):
		return 11.0  # 헤드리스/카메라 미존재 — 보수적 중간값
	var dir := Vector3(cos(angle), 0.0, sin(angle))
	var probe := func(r: float) -> bool:
		return bool(rig.call("is_world_pos_visible", anchor + dir * r + Vector3(0, 0.6, 0)))
	# 안쪽(보임)에서 시작해 바깥(안 보임)을 찾는다. 시작점이 이미 안 보이면 경계≈0.
	var lo: float = 0.0
	var hi: float = _EDGE_SEARCH_MAX
	if not probe.call(lo):
		return 0.0  # PC 바로 옆도 화면 밖(이례적) — 경계 0 취급
	if probe.call(hi):
		return hi   # 상한까지 전부 화면 안(이례적 광각) — 상한 반환
	for _i in _EDGE_SEARCH_ITERS:
		var mid: float = (lo + hi) * 0.5
		if probe.call(mid):
			lo = mid
		else:
			hi = mid
	return hi  # hi = 첫 화면 밖 반경(경계 바로 바깥)

## 지정 각도로 "화면 가장자리 바로 밖"(경계 + 버퍼) 위치를 돌려준다. pop-in 없음.
func _edge_spawn_at(anchor: Vector3, angle: float) -> Vector3:
	var r: float = _frustum_edge_radius(anchor, angle) + _EDGE_BUFFER
	return anchor + Vector3(cos(angle) * r, 0.0, sin(angle) * r)

## 게임 시작/floor 용 — PC 진행방향(정지 시 카메라 정면 = -Z) 쪽 ±cone 안 가장자리 밖.
## 대시 중에도 "앞에 적이 보이게" + 뒤 유기 최소화.
func _edge_spawn_forward() -> Vector3:
	var anchor: Vector3 = Vector3.ZERO
	if _player != null and is_instance_valid(_player):
		anchor = (_player as Node3D).global_position
	# 진행방향: 속도가 있으면 그쪽, 없으면 카메라 정면(-Z, atan2 규약 = +π/2 의 -방향).
	var fwd: float = deg_to_rad(-90.0)  # -Z (atan2(z=-1,x=0) = -90°) = 카메라가 보는 정면
	if _player != null and is_instance_valid(_player) and _player is CharacterBody3D:
		var v: Vector3 = (_player as CharacterBody3D).velocity
		v.y = 0.0
		if v.length() >= _SPAWN_VEL_THRESHOLD:
			fwd = atan2(v.z, v.x)
	var angle: float = fwd + deg_to_rad(randf_range(-50.0, 50.0))
	return _edge_spawn_at(anchor, angle)

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
	# 잡몹 처치 시 열기 -5(엘리트/보스 제외) — 연속 처치로 열기 감소.
	var is_minor: bool = not (enemy.is_in_group("elites") or enemy.is_in_group("boss"))
	if is_minor and _player != null and is_instance_valid(_player) and _player.has_method("add_heat"):
		_player.call("add_heat", -5.0)


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
	if _player_hud != null:
		_player_hud.exp_system = _exp_system  # 하단 HUD 레벨 뱃지 소스

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
	_apply_wave_preset()  # ESC 프리셋(원거리=인원 1/10) 적용 — 리로드 너머 GameConfig 로 유지.
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

	# 초반 시드 — 0초부터 1~2마리가 화면 가장자리 바로 밖에 등장해 곧장 걸어 들어온다.
	# 카메라 rig 가 첫 프레임에 PC 위치로 스냅한 뒤(_ready) 프러스텀이 안정되도록 한 틱
	# 미뤄 호출. WaveManager floor 와 별개로 "시작하자마자 텅 빔" 을 확실히 제거.
	call_deferred("_seed_initial_mobs")

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
	# ESC 비율 프리셋이 켜져 있으면 곡선 대신 프리셋 비율(근접/원거리/엘리트)로 스폰.
	if _wave_preset != 0:
		_request_spawn_preset(lv)
		return
	# 주술사(싱글톤) — 없으면 낮은 확률로 1마리.
	if _try_spawn_sorcerer():
		return
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
	# 리퍼는 동시 생존 3마리까지만 — 이미 3마리면 스폰 금지(일반 근접으로 대체).
	if leaper_enemy_scene != null and roll < rr + lr and _alive_leaper_count() < 3:
		_spawn_one(leaper_enemy_scene, melee_spawn_min_radius, melee_spawn_max_radius)
		return
	_spawn_melee_or_slammer(lv)


## 살아있는(죽는 중 제외) 리퍼 수 — 동시 3마리 스폰 캡("leapers" 그룹 질의).
func _alive_leaper_count() -> int:
	var n: int = 0
	for e in get_tree().get_nodes_in_group("leapers"):
		if is_instance_valid(e) and not ("_dead" in e and e._dead):
			n += 1
	return n


## 살아있는 근접몹(잡몹+슬래머, 엘리트 제외) 수 — 원거리 프리셋 바닥 유지용.
func _alive_melee_count() -> int:
	var n: int = 0
	for e in get_tree().get_nodes_in_group("melee_enemies"):
		if is_instance_valid(e) and not ("_dead" in e and e._dead) and not e.is_in_group("elites"):
			n += 1
	return n


## 살아있는 주술사 수 — 동시 최대 1마리(싱글톤) 캡("sorcerers" 그룹 질의).
func _alive_sorcerer_count() -> int:
	var n: int = 0
	for e in get_tree().get_nodes_in_group("sorcerers"):
		if is_instance_valid(e) and not ("_dead" in e and e._dead):
			n += 1
	return n


## 주술사가 없을 때만 낮은 확률로 1마리 스폰(싱글톤). 스폰했으면 true.
func _try_spawn_sorcerer() -> bool:
	if sorcerer_enemy_scene == null or _alive_sorcerer_count() >= 1:
		return false
	if randf() >= _SORCERER_CHANCE:
		return false
	_spawn_sorcerer()
	return true


func _spawn_sorcerer() -> void:
	if sorcerer_enemy_scene == null or _alive_sorcerer_count() >= 1:
		return
	var inst := sorcerer_enemy_scene.instantiate()
	_inherit_bullettime(inst)
	_enemies_root.add_child(inst)
	if inst is Node3D:
		(inst as Node3D).global_position = _pick_offscreen_spawn(elite_spawn_min_radius, elite_spawn_max_radius)
	_wire_enemy_lifecycle(inst)


## 근접 스폰 — 일부(약 30%)는 슬래머(내려찍기)로 회피 압박을 섞는다.
func _spawn_melee_or_slammer(lv: int) -> void:
	# 슬래머 비율 — 웨이브 곡선의 시간 게이트(slammer_start_time) 적용. 스토리보드: ~40s 부터.
	var sr: float = _SLAMMER_RATIO
	if _wave_mgr != null and _wave_mgr.has_method("slammer_ratio"):
		sr = float(_wave_mgr.call("slammer_ratio"))
	if slammer_enemy_scene != null and randf() < sr:
		_spawn_one(slammer_enemy_scene, melee_spawn_min_radius, melee_spawn_max_radius)
		return
	if lv >= 2:
		_spawn_one_lv2(melee_enemy_scene, melee_spawn_min_radius, melee_spawn_max_radius)
	else:
		_spawn_one(melee_enemy_scene, melee_spawn_min_radius, melee_spawn_max_radius)


## ESC 패널 프리셋 스폰 — 근접/원거리/엘리트 비율(+엘리트 랜덤 효과 1~4) + 주술사 싱글톤.
func _request_spawn_preset(lv: int) -> void:
	# 주술사(싱글톤) — 없으면 낮은 확률로 1마리.
	if _try_spawn_sorcerer():
		return
	if _wave_preset == 2:
		# 일섬 웨이브(원거리60·근접35·엘리트5) — 근접 최소 3마리 바닥 유지.
		if _alive_melee_count() < _PRESET2_MELEE_FLOOR:
			_spawn_melee_or_slammer(lv)
			return
		var r2: float = randf()
		if ranged_enemy_scene != null and r2 < _P2_RANGED:
			_spawn_one(ranged_enemy_scene, ranged_spawn_min_radius, ranged_spawn_max_radius)
			return
		if elite_enemy_scene != null and r2 < _P2_RANGED + _P2_ELITE:
			_spawn_one_elite(elite_enemy_scene, elite_spawn_min_radius, elite_spawn_max_radius, randi_range(1, 4))
			return
		_spawn_melee_or_slammer(lv)
		return
	# 프리셋 1(근접 밀리: 근접90·원거리5·엘리트5) 또는 기타.
	var roll: float = randf()
	if ranged_enemy_scene != null and roll < _P1_RANGED:
		_spawn_one(ranged_enemy_scene, ranged_spawn_min_radius, ranged_spawn_max_radius)
		return
	if elite_enemy_scene != null and roll < _P1_RANGED + _P1_ELITE:
		_spawn_one_elite(elite_enemy_scene, elite_spawn_min_radius, elite_spawn_max_radius, randi_range(1, 4))
		return
	_spawn_melee_or_slammer(lv)


## GameConfig 의 웨이브 프리셋을 현재 인스턴스에 반영 — _wave_mgr 인원 배수.
## wave_mgr 생성 직후 호출. (ESC 메뉴/툴 에디터 UI 는 scenes/ui/PauseOverlay.gd 로 분리.)
func _apply_wave_preset() -> void:
	_wave_preset = _GameConfigScript.wave_preset
	if _wave_mgr != null:
		if _wave_preset == 2:
			_wave_mgr.target_mult = 0.2    # 일섬 웨이브 — 총 인구 대폭 감소(총수 적고 원거리 비중↑)
			_wave_mgr.min_target = 3        # 바닥 3(초반 가볍게 시작)
		else:
			_wave_mgr.target_mult = 1.0
			_wave_mgr.min_target = 0


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

## 초반 시드 — 챕터 시작 직후 _SEED_COUNT 마리를 진행/정면 쪽 화면 가장자리 바로 밖에
## 놓는다. _spawn_one 의 일반 경로를 타되 위치만 forward-edge 로 덮어써 종류/수명/배선은
## 동일하게 유지. 카메라가 아직 없거나(헤드리스 부팅 등) PC 가 없으면 조용히 스킵.
func _seed_initial_mobs() -> void:
	if not is_inside_tree():
		return
	if melee_enemy_scene == null:
		return
	if _player == null or not is_instance_valid(_player):
		return
	for i in _SEED_COUNT:
		var inst := melee_enemy_scene.instantiate()
		_inherit_bullettime(inst)
		_enemies_root.add_child(inst)
		if inst is Node3D:
			(inst as Node3D).global_position = _edge_spawn_forward()
		_wire_enemy_lifecycle(inst)

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
	_play_log("챕터 %d 클리어 (보스 처치)" % _current_chapter)
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
	_apply_wave_preset()  # ESC 프리셋 — 챕터 전환 후에도 유지.
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
	_play_log("사망 — 시간 %.0fs · 처치 %d · Lv %d" % [elapsed_sec, _kill_count, pc_level])
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
	if over.has_signal("continue_pressed"):
		over.continue_pressed.connect(_on_player_continue)
	if over.has_method("configure"):
		over.call("configure", stats, best, beat)


## 사망 화면 "이어서 하기" — 같은 PC 를 부활시키고 재개(진행/적/웨이브 그대로 유지).
func _on_player_continue() -> void:
	_game_over_shown = false
	if _player != null and is_instance_valid(_player) and _player.has_method("revive"):
		_player.call("revive")
	var tree := get_tree()
	if tree != null:
		tree.paused = false


## Wall-clock seconds since WaveManager started. Centralised so the
## clear / death paths can't drift out of sync on the formula.
func _elapsed_seconds() -> float:
	if _chapter_start_msec <= 0:
		return 0.0
	return float(Time.get_ticks_msec() - _chapter_start_msec) / 1000.0

## ExpSystem fired leveled_up → pause world, show 3 upgrade cards, wait for
## a pick, apply it, then resume.
func _on_leveled_up(_new_level: int) -> void:
	_play_log("레벨업 → Lv %d" % _new_level)
	if _player != null and is_instance_valid(_player) and _player.has_method("grant_iframe"):
		var dur: float = (_player.data.levelup_iframe if _player.data != null else 1.0)
		_player.call("grant_iframe", dur)
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
	# 레벨업 직후 — 자기 중심 원형으로 적을 약하게 밀어낸다(피해 없음) + 링 연출.
	if _player != null and is_instance_valid(_player) and _player.has_method("levelup_pushback"):
		_player.call("levelup_pushback")
	# 카드 기록 — 이름 조회 후 _selected_cards 에 추가, SkillViewer 갱신.
	var card_data = _UpgradeSystemScript.card_by_id(card_id)
	var card_name: String = (String(card_data.get("name", card_id)) if card_data != null else card_id)
	_selected_cards.append({"id": card_id, "name": card_name})
	if _skill_viewer != null and _skill_viewer.has_method("refresh"):
		_skill_viewer.call("refresh", _selected_cards)

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

	# 하단 중앙 PC HUD(초상화 + HP 바 + 열기/일섬 스택 + 회피 스택 + 레벨 뱃지).
	# PlayerHud 가 PC 게터를 매 프레임 자가 갱신 — exp_system 은 _build_chapter_systems 에서 주입.
	_player_hud = _PlayerHudScene.new()
	canvas.add_child(_player_hud)

	_kill_label = Label.new()
	_kill_label.text = "Kills: 0"
	_kill_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_kill_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_kill_label.add_theme_constant_override("outline_size", 4)
	_kill_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_kill_label)

	_info_label = Label.new()
	# 컨트롤 안내 — 모드별로 LB/RB 역할이 달라 GameConfig.instant_slash_mode 로 분기.
	if _GameConfigScript.instant_slash_mode:
		_info_label.text = "WASD: 이동   LMB(hold): 일섬 차징·발사   RMB: 패리   SPACE: 회피   R: 재시작"
	else:
		_info_label.text = "WASD: 이동   LMB: 근접 공격   RMB(hold): 일섬(게이지 100%)   SPACE: 회피   R: 재시작"
	_info_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_info_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_info_label.add_theme_constant_override("outline_size", 4)
	_info_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_info_label)

	# 현재 컨트롤 모드 표시(근접 / 거합) — GameConfig.instant_slash_mode 기준. 항상 노출.
	var mode_label := Label.new()
	var _ms: String = "근접 밀리 모드"
	if _GameConfigScript.instant_slash_mode:
		var _w: int = _GameConfigScript.wave_preset
		_ms = "근접 몬스터 일섬" if _w == 1 else ("원거리 몬스터 일섬" if _w == 2 else "일섬 (기본 웨이브)")
	mode_label.text = "모드: " + _ms
	mode_label.add_theme_color_override("font_color", Color(0.55, 0.95, 1))
	mode_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	mode_label.add_theme_constant_override("outline_size", 4)
	mode_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(mode_label)

	# ⏱ Zen meter readout — sits below the info line, refreshed by
	# `_on_zen_changed`. "BURST!" overrides the count when armed.
	_zen_label = Label.new()
	_zen_label.text = "Zen: 0 / 5"
	_zen_label.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	_zen_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_zen_label.add_theme_constant_override("outline_size", 4)
	_zen_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_zen_label)

	# ESC 일시정지 메뉴 + 툴 에디터(PauseOverlay) — process_mode ALWAYS 라 정지 중에도 동작.
	add_child(_PauseOverlayScene.instantiate())
	# 카드 빌드 뷰어 — Tab 토글 오버레이(layer=70, 정지 없음).
	_skill_viewer = _SkillViewerScript.new()
	add_child(_skill_viewer)

func _update_hud() -> void:
	if _player == null or not is_instance_valid(_player):
		# PC freed — no live HP to read; the floating bar disappeared with it.
		return
	_kill_label.text = "Kills: %d" % _kill_count
	# HP/열기/회피/레벨은 PlayerHud 가 자가 갱신(PC 게터 덕타이핑).


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
