class_name Testplay
extends Node3D

## Practice-mode arena. Identical combat / progression surface as Main
## (EXP, level-up, elite effect payloads, bullet-time) but with all
## auto-spawn / chapter / wave systems stripped out, replaced by a
## right-side button panel for on-demand mob/elite/boss spawns.
##
## Run with F6 (Run Current Scene) in the editor. `project.godot`'s
## `main_scene` stays on Main.tscn so F5 still runs the real game.
##
## Maintenance contract:
##   When a system is added to Main.gd's combat / progression flow, it
##   should ALSO be added here (per user request — practice mode must
##   stay in sync). The duplication is deliberate for now; a shared
##   "ArenaServices" extraction is on the refactor backlog.

@export var player_scene: PackedScene
@export var melee_enemy_scene: PackedScene
@export var slammer_enemy_scene: PackedScene
@export var elite_enemy_scene: PackedScene
@export var sorcerer_enemy_scene: PackedScene
@export var boss_scene: PackedScene
## Optional second boss — when wired, the right-side panel adds a
## separate button for it. Left null means only one "보스" button shows.
@export var boss_scene_2: PackedScene
## Optional third boss (Ch3). Same convention as boss_scene_2.
@export var boss_scene_3: PackedScene
@export var camera_scene: PackedScene

@export_group("Effects")
@export var explosion_burst_scene: PackedScene
@export var circular_slash_scene: PackedScene
## EXP gem dropped from corpses (mirror of Main) — magnets to PC, credits
## EXP on pickup. Wired in Testplay.tscn.
@export var exp_gem_scene: PackedScene

@export_group("UI / Chapter")
@export var exp_bar_scene: PackedScene
@export var level_up_screen_scene: PackedScene

@export_group("Arena")
@export var ground_size: float = 60.0
@export var ground_color: Color = Color(0.34, 0.45, 0.28)

@export_group("Spawning")
@export var spawn_min_radius: float = 6.0
@export var spawn_max_radius: float = 10.0
## How many regular mobs the "general 10" button spawns.
@export var regular_mob_count: int = 10

@export_group("Bullet-time")
@export var bullettime_slow_factor: float = 0.25
@export var bullettime_duration: float = 3.0

const _NORMAL_SATURATION: float = 1.12

# --- Chapter / EXP scripts (preload to dodge class_name cache misses
# in --headless runs, same as Main.gd) ---
const _ExpSystemScript := preload("res://scripts/managers/ExpSystem.gd")
const _UpgradeSystemScript := preload("res://scripts/managers/UpgradeSystem.gd")
const _InfiniteGroundScript := preload("res://scripts/managers/InfiniteGround.gd")
# M8 refactor — same shared services as Main, so the debug arena runs
# identical elite-payload + bullet-time code instead of mirrored copies.
const _EliteEffectServiceScript := preload("res://scripts/managers/EliteEffectService.gd")
const _BulletTimeServiceScript := preload("res://scripts/managers/BulletTimeService.gd")
const _BoonSystemScript := preload("res://scripts/managers/BoonSystem.gd")
const _EscapeZoneScript := preload("res://scenes/effects/EscapeZone.gd")

var _player: Node
var _camera: HD2DCamera
var _enemies_root: Node3D
var _exp_bar: CanvasLayer
var _exp_system: Node
var _player_hud: Control
const _PlayerHudScene := preload("res://scenes/ui/PlayerHud.gd")
const _GameConfigScript := preload("res://scripts/managers/GameConfig.gd")
const _SkillViewerScript := preload("res://scenes/ui/SkillViewer.gd")
var _world_env: WorldEnvironment
var _elite_effect_service: Node
var _bullet_time_service: Node
var _skill_viewer: CanvasLayer
var _escape_zone: Node3D = null
## 현재 런에서 선택한 카드 목록 [{id, name}, ...].
var _selected_cards: Array = []
## 레벨업 시 뽑힌 권속 카드 목록 — _on_upgrade_card_selected 에서 rarity 조회용.
var _pending_boon_cards: Array = []
var _arena_start_msec: int = 0

func _ready() -> void:
	_arena_start_msec = Time.get_ticks_msec()
	_warm_placeholder_cache()
	_build_environment()
	_build_lighting()
	_enemies_root = Node3D.new()
	_enemies_root.name = "Enemies"
	add_child(_enemies_root)
	# PC spawns BEFORE the ground because InfiniteGround needs a target
	# node to follow. (Main.gd has the same dependency; it just happens
	# to spawn the PC inside _warm_placeholder_cache there, masking the
	# ordering — we keep the spawn explicit here.)
	_spawn_player()
	_build_ground()
	_spawn_camera()
	_build_chapter_systems()
	_build_help_label()
	# 밸런싱 아레나 디버그 패널(F1 토글) — 무적/배속/스탯주입/PC 라이브 튜닝/TTK readout.
	var arena = preload("res://scenes/ui/ArenaDebug.gd").new()
	add_child(arena)
	arena.call("setup", _player, _exp_system, self)

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("restart"):
		get_tree().reload_current_scene()
		return
	# HP/열기/회피/레벨은 PlayerHud 가 자가 갱신(PC 게터 덕타이핑).

## --- Procedural arena (mirrors Main; intentional duplication so this
## scene stays independent of Main's chapter coupling) ---

func _warm_placeholder_cache() -> void:
	PlaceholderSprite.make(Color(0.7, 0.85, 1.0))   # player
	PlaceholderSprite.make(Color(1.0, 0.45, 0.4))   # melee
	PlaceholderSprite.make(Color(1.0, 0.75, 0.25))  # ranged (unused here but kept warm)

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
	env.tonemap_mode = Environment.TONE_MAPPER_REINHARDT
	env.adjustment_enabled = true
	env.adjustment_saturation = _NORMAL_SATURATION
	we.environment = env
	add_child(we)
	# Stored so bullet-time can pulse saturation on the live env.
	_world_env = we

func _build_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(40.0), 0.0)
	sun.light_energy = 1.4
	sun.shadow_enabled = false
	sun.light_color = Color(1.0, 0.96, 0.88)
	add_child(sun)

## PC-following infinite ground — mirrors Main's `_build_ground`. See
## InfiniteGround.gd for the why (one big PC-following plane + world-
## space noise texture beats a chunk grid for this single-biome arena).
func _build_ground() -> void:
	var ig := _InfiniteGroundScript.new()
	ig.name = "InfiniteGround"
	ig.ground_color = ground_color
	add_child(ig)
	if _player != null and _player is Node3D:
		ig.set_target(_player as Node3D)

func _spawn_player() -> void:
	if player_scene == null:
		push_error("Testplay.player_scene not set")
		return
	_player = player_scene.instantiate()
	_player.add_to_group("player")
	add_child(_player)
	(_player as Node3D).global_position = Vector3.ZERO
	# Debug arena: no GameOverScreen, no SaveSystem write — those would
	# pollute the player's real best-records. Instead we auto-reload 1s
	# after death so the next test cycle starts clean. (See Main.gd for
	# the production death flow.)
	if _player.has_signal("died"):
		_player.died.connect(_on_player_died_testplay)
	# ⏱ Perfect dodge → self-bullet-time (mirror of Main).
	if _player.has_signal("perfect_dodge"):
		_player.perfect_dodge.connect(_on_player_perfect_dodge)


func _on_player_perfect_dodge() -> void:
	if _bullet_time_service != null:
		_bullet_time_service.start(0.5)


func _on_player_died_testplay() -> void:
	if not is_inside_tree():
		return
	get_tree().create_timer(1.0).timeout.connect(_reload_testplay)


func _reload_testplay() -> void:
	var tree := get_tree()
	if tree != null:
		tree.reload_current_scene()

func _spawn_camera() -> void:
	if camera_scene == null:
		push_error("Testplay.camera_scene not set")
		return
	_camera = camera_scene.instantiate() as HD2DCamera
	add_child(_camera)
	if _player != null:
		_camera.set_target(_player as Node3D)

## --- Chapter / EXP / upgrade systems (mirrors Main, NO WaveManager) ---

func _build_chapter_systems() -> void:
	_exp_system = _ExpSystemScript.new()
	_exp_system.name = "ExpSystem"
	add_child(_exp_system)
	_exp_system.leveled_up.connect(_on_leveled_up)
	if _player_hud != null:
		_player_hud.exp_system = _exp_system  # 하단 HUD 레벨 뱃지 소스
	if exp_bar_scene != null:
		_exp_bar = exp_bar_scene.instantiate() as CanvasLayer
		add_child(_exp_bar)
		if _exp_bar.has_method("set_exp_source"):
			_exp_bar.call("set_exp_source", _exp_system)

	# M8 — shared bullet-time + elite-effect services (mirror Main).
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

## Hook a freshly spawned enemy into the bookkeeping pipeline so its
## death awards EXP, matching Main's flow.
func _wire_enemy_lifecycle(inst: Node) -> void:
	if inst == null:
		return
	if inst.has_signal("tree_exited"):
		inst.tree_exited.connect(_on_enemy_freed_with_ref.bind(inst))
	_apply_time_hp_scaling(inst)


## ⏱ 시간 HP 스케일 (Main 미러) — 아레나 잡몹(근접/리퍼/궁수)도 경과 시간대로 단단해진다.
## 시간원은 _arena_elapsed_seconds(). 공식·대상 가드는 Main._apply_time_hp_scaling 과 동일.
## 엘리트/보스/슬래머는 제외(아레나엔 레벨 스케일이 없지만 위협군은 시간 스케일도 미적용 — 일관).
func _apply_time_hp_scaling(inst: Node) -> void:
	if inst == null or not is_instance_valid(inst):
		return
	var is_threat: bool = inst.is_in_group("elites") or inst.is_in_group("boss")
	if not is_threat and "behavior" in inst and int(inst.behavior) == 2:  # SLAMMER
		is_threat = true
	if is_threat:
		return
	if not inst.is_in_group("enemies"):
		return
	var extra: int = _time_hp_extra(_arena_elapsed_seconds())
	if extra <= 0:
		return
	var hc = inst.get_node_or_null("HealthComponent")
	if hc != null and hc.has_method("add_max_hp"):
		hc.add_max_hp(extra)


## 시간(초) → 잡몹 추가 HP 단계 (Main 미러). 60s 미만=0, 이후 1분당 +1, 상한 +4.
func _time_hp_extra(t: float) -> int:
	if t < 60.0:
		return 0
	return min(int(t / 60.0), 4)

func _on_enemy_freed_with_ref(enemy: Node) -> void:
	# Same shutdown-safety as Main: during scene reload the tree may be
	# tearing down and downstream EXP logic would NPE.
	if not is_inside_tree():
		return
	award_exp_for_kill(enemy)

## Mirrors Main.award_exp_for_kill — Elite payouts (3/5/10 by type) plus
## the LV2 melee bump (2 EXP). Testplay can't spawn LV2 melee through a
## button, but we keep the `_lv` check for parity with future tweaks.
func award_exp_for_kill(enemy: Node) -> void:
	if _exp_system == null:
		return
	var base := 1
	if "_lv" in enemy and enemy._lv >= 2:
		base = 2
	# Mirror of Main — 처치 즉시 EXP 0(젬을 주워야 EXP). add_exp(0)은 no-op.
	_exp_system.add_exp(0)
	_drop_exp_gem(enemy, base)
	# 4안 — 처치 시 일섬 게이지 (mirror).
	if _player != null and is_instance_valid(_player) and _player.has_method("gain_gauge_on_kill"):
		_player.call("gain_gauge_on_kill")
	# 잡몹 처치 시 열기 -5(엘리트/보스 제외) — Main 미러.
	var is_minor: bool = not (enemy.is_in_group("elites") or enemy.is_in_group("boss"))
	if is_minor and _player != null and is_instance_valid(_player) and _player.has_method("add_heat"):
		_player.call("add_heat", -5.0)
	# ★엘리트 처치 보상 — PC 레벨 1 상승(다음 임계까지 즉시 부여). Main 미러.
	if ("is_star_elite" in enemy and enemy.is_star_elite) and _exp_system != null:
		var need: int = max(1, _exp_system.threshold - _exp_system.current_exp)
		_exp_system.add_exp(need)


func _drop_exp_gem(enemy: Node, value: int) -> void:
	if exp_gem_scene == null or enemy == null or not is_instance_valid(enemy):
		_exp_system.add_exp(value)
		return
	# death_position captured at _on_died (tree_exited reads as origin).
	var pos: Vector3
	if enemy.has_meta("death_position"):
		pos = enemy.get_meta("death_position")
	elif enemy is Node3D and enemy.is_inside_tree():
		pos = (enemy as Node3D).global_position
	else:
		_exp_system.add_exp(value)
		return
	var gem := exp_gem_scene.instantiate()
	if gem.has_method("configure"):
		gem.call("configure", value)
	add_child(gem)
	(gem as Node3D).global_position = Vector3(pos.x, 0.3, pos.z)


func collect_exp_gem(value: int) -> void:
	if _exp_system != null:
		_exp_system.add_exp(value)
	# 4안 — 젬 획득 시 일섬 게이지 (mirror).
	if _player != null and is_instance_valid(_player) and _player.has_method("gain_gauge_on_gem"):
		_player.call("gain_gauge_on_gem")


func _arena_elapsed_seconds() -> float:
	if _arena_start_msec <= 0:
		return 0.0
	return float(Time.get_ticks_msec() - _arena_start_msec) / 1000.0


func _on_leveled_up(_new_level: int) -> void:
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
	# Draw boon cards — if the pool is empty, skip the overlay entirely
	# (tree stays unpaused, level already incremented by ExpSystem).
	var owned: Array = []
	if _player != null and is_instance_valid(_player):
		for b in _player.get("active_boons"):
			owned.append(b.get("id", ""))
	var cards: Array = _BoonSystemScript.draw_boons(3, _new_level, owned)
	if cards.is_empty():
		return
	_pending_boon_cards = cards
	tree.paused = true
	var screen := level_up_screen_scene.instantiate() as CanvasLayer
	if screen == null:
		tree.paused = false
		return
	add_child(screen)
	if screen.has_method("show_cards"):
		screen.call("show_cards", cards)
	if screen.has_signal("card_selected"):
		screen.card_selected.connect(_on_upgrade_card_selected, CONNECT_ONE_SHOT)

func _on_upgrade_card_selected(card_id: String) -> void:
	# 선택된 권속 카드의 rarity 조회 후 add_boon 호출.
	var card: Dictionary = {}
	for c in _pending_boon_cards:
		if c.get("id", "") == card_id:
			card = c
			break
	if not card.is_empty() and _player != null and is_instance_valid(_player):
		_player.call("add_boon", card_id, String(card.get("rarity", "chosim")))
	var tree := get_tree()
	if tree != null:
		tree.paused = false
	# 레벨업 직후 — 자기 중심 원형으로 적을 약하게 밀어낸다(피해 없음) + 링 연출.
	if _player != null and is_instance_valid(_player) and _player.has_method("levelup_pushback"):
		_player.call("levelup_pushback")
	# 카드 기록 — Main 미러.
	var card_name: String = (String(card.get("name", card_id)) if not card.is_empty() else card_id)
	_selected_cards.append({"id": card_id, "name": card_name})
	if _skill_viewer != null and _skill_viewer.has_method("refresh"):
		_skill_viewer.call("refresh", _selected_cards)

## --- Elite death payloads (M8 — delegate to shared service) ---

## EliteEnemy._on_died calls this on the current scene. Thin delegate to
## EliteEffectService, identical to Main's now (single source of truth).
func trigger_elite_effect(effect_type: int, pos: Vector3) -> void:
	if _elite_effect_service != null:
		_elite_effect_service.trigger(effect_type, pos)

## Apply current bullet-time slow to a freshly spawned node (mirror of
## Main._inherit_bullettime — shared service, identical behaviour).
func _inherit_bullettime(inst: Node) -> void:
	if _bullet_time_service == null or not _bullet_time_service.is_active():
		return
	if "time_scale_mult" in inst:
		inst.time_scale_mult = _bullet_time_service.current_slow_factor()

## --- Spawn helpers ---

## Random spawn position around the PC — simpler than Main's offscreen
## frustum logic. For test mode it's fine if a click drops a mob into
## the visible frame.
func _pick_random_spawn() -> Vector3:
	var anchor: Vector3 = Vector3.ZERO
	if _player != null and is_instance_valid(_player):
		anchor = (_player as Node3D).global_position
	var ang: float = randf() * TAU
	var r: float = lerp(spawn_min_radius, spawn_max_radius, randf())
	return anchor + Vector3(cos(ang) * r, 0.0, sin(ang) * r)

func _spawn_mob(scene: PackedScene) -> void:
	if scene == null:
		return
	var inst := scene.instantiate()
	# Inherit bullet-time if it's currently active, parity with Main.
	_inherit_bullettime(inst)
	_enemies_root.add_child(inst)
	if inst is Node3D:
		(inst as Node3D).global_position = _pick_random_spawn()
	_wire_enemy_lifecycle(inst)

func _spawn_star_elite() -> void:
	var scene: PackedScene = load("res://scenes/enemies/RangedEnemy.tscn")
	var inst := scene.instantiate()
	if "is_star_elite" in inst:
		inst.is_star_elite = true
	_inherit_bullettime(inst)
	_enemies_root.add_child(inst)
	if inst is Node3D:
		(inst as Node3D).global_position = _pick_random_spawn()
	_wire_enemy_lifecycle(inst)

func _spawn_boss() -> void:
	_spawn_boss_scene(boss_scene)


func _spawn_boss_2() -> void:
	_spawn_boss_scene(boss_scene_2)


func _spawn_boss_3() -> void:
	_spawn_boss_scene(boss_scene_3)


func _spawn_boss_scene(scene: PackedScene) -> void:
	if scene == null:
		return
	var inst := scene.instantiate()
	_enemies_root.add_child(inst)
	if inst is Node3D:
		(inst as Node3D).global_position = _pick_random_spawn()
	_wire_enemy_lifecycle(inst)

## --- UI: right-side button panel ---

func _build_button_panel() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "TestplayPanel"
	canvas.layer = 50  # Above HUD basics, below modal screens.
	add_child(canvas)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	canvas.add_child(vbox)

	# Anchor to the right edge with a fixed offset.
	var vp_size: Vector2i = get_viewport().get_visible_rect().size
	var panel_w: float = 220.0
	var x: float = float(vp_size.x) - panel_w - 20.0
	var y: float = 80.0
	vbox.position = Vector2(x, y)
	vbox.size = Vector2(panel_w, 0)

	var buttons: Array = [
		{"label": "일반 몹 10마리", "cb": Callable(self, "_on_spawn_regular_10")},
		{"label": "내려찍기 슬래머", "cb": Callable(self, "_on_spawn_slammer")},
		{"label": "주술사 (마법사)", "cb": Callable(self, "_on_spawn_sorcerer")},
		{"label": "은혜:천호낙인(유니크)", "cb": Callable(self, "_on_boon_gumiho_mark")},
		{"label": "은혜:월하정기흡(유니크)", "cb": Callable(self, "_on_boon_gumiho_lifesteal")},
		{"label": "은혜:매혹파열(유니크)", "cb": Callable(self, "_on_boon_gumiho_charm")},
		{"label": "은혜:야호분혼(유니크)", "cb": Callable(self, "_on_boon_gumiho_summon")},
		{"label": "은혜:여우불세례(유니크)", "cb": Callable(self, "_on_boon_gumiho_foxfire")},
		{"label": "은혜:구미낙화(유니크)", "cb": Callable(self, "_on_boon_gumiho_slashfan")},
		{"label": "은혜:혼불난무(유니크)", "cb": Callable(self, "_on_boon_gumiho_radial")},
		{"label": "보스 1 (Ch1)", "cb": Callable(self, "_on_spawn_boss")},
	]
	# Bosses 2/3 only show if their scenes are wired — keeps the panel
	# uncluttered while early chapters are still the focus.
	if boss_scene_2 != null:
		buttons.append({"label": "보스 2 (Ch2)", "cb": Callable(self, "_on_spawn_boss_2")})
	if boss_scene_3 != null:
		buttons.append({"label": "보스 3 (Ch3)", "cb": Callable(self, "_on_spawn_boss_3")})
	for entry in buttons:
		vbox.add_child(_make_button(entry["label"], entry["cb"], panel_w))

func _make_button(label: String, cb: Callable, width: float) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(width, 44)
	btn.add_theme_font_size_override("font_size", 15)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	btn.add_theme_color_override("font_color_hover", Color(1, 1, 1, 1))
	# Card-style background, copied from LevelUpScreen for visual parity.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.18, 0.22, 0.92)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", style)
	var hover_style := style.duplicate() as StyleBoxFlat
	hover_style.bg_color = Color(0.28, 0.32, 0.42, 0.96)
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.add_theme_stylebox_override("pressed", hover_style)
	btn.pressed.connect(cb)
	# MOUSE_FILTER_STOP keeps the click from reaching anything below the
	# button in the UI tree, but it does NOT stop the global Input poll
	# that the PC reads. The PC's `_check_instant_slash` separately calls
	# `gui_get_hovered_control()` to swallow clicks landing on UI.
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	return btn

func _build_help_label() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "TestplayHelp"
	add_child(canvas)
	var label := Label.new()
	# 컨트롤 안내 — 일섬 단일(LB 롱프레스 차징·발사). Main 미러.
	label.text = "Testplay  |  WASD: 이동  LMB(hold): 일섬 차징·발사  SPACE: 회피  R: 재시작"
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_font_size_override("font_size", 16)
	# HP 칸(20,16)이 좌상단을 차지하므로 도움말은 한 줄 아래로.
	label.position = Vector2(20, 50)
	canvas.add_child(label)
	# 하단 중앙 PC HUD(초상화 + HP + 열기/일섬 스택 + 회피 스택 + 레벨). exp_system 은 아레나 셋업에서 주입.
	_player_hud = _PlayerHudScene.new()
	canvas.add_child(_player_hud)
	# 카드 빌드 뷰어 — Tab 토글 오버레이(layer=70, 정지 없음).
	_skill_viewer = _SkillViewerScript.new()
	add_child(_skill_viewer)

## --- Button callbacks ---

## 아레나 패널(ArenaDebug) — 종류 kind 를 count 마리 스폰(수량 지정).
func arena_spawn(kind: String, count: int) -> void:
	var n: int = clampi(count, 1, 50)
	var scene: PackedScene = null
	match kind:
		"mob": scene = melee_enemy_scene
		"leaper": scene = load("res://scenes/enemies/Leaper.tscn")
		"slammer": scene = slammer_enemy_scene
		"ranged": scene = load("res://scenes/enemies/RangedEnemy.tscn")
		"sorcerer": scene = sorcerer_enemy_scene
	for i in n:
		match kind:
			"boss1": _spawn_boss()
			"boss2": _spawn_boss_2()
			"boss3": _spawn_boss_3()
			"star_elite": _spawn_star_elite()
			_:
				if scene != null:
					_spawn_mob(scene)


## 아레나 웨이브 — "웨이브 시작" 버튼이 토글. 정지 상태로 시작, 누르면 chapter_1 곡선으로 자동 스폰.
var _wave_mgr: Node = null
var _wave_running: bool = false

func toggle_wave() -> bool:
	if _wave_mgr == null:
		_wave_mgr = preload("res://scripts/managers/WaveManager.gd").new()
		_wave_mgr.name = "ArenaWave"
		add_child(_wave_mgr)
		_wave_mgr.request_spawn_cb = Callable(self, "_wave_spawn")
		_wave_mgr.count_alive_cb = Callable(self, "_wave_count_alive")
	_wave_running = not _wave_running
	if _wave_running:
		_wave_mgr.set_curve(load("res://resources/chapters/chapter_1.tres"))  # 시계 리셋
	_wave_mgr.enabled = _wave_running
	return _wave_running

func _wave_spawn(_lv: int) -> void:
	var rc = (_wave_mgr.curve if (_wave_mgr != null and "curve" in _wave_mgr) else null)
	# 스폰 로스터(배열)가 채워져 있으면 Main 과 동일 경로 — 비어있으면 레거시 폴백.
	if rc != null and rc.has_method("has_roster") and bool(rc.call("has_roster")):
		_wave_spawn_roster(rc)
		return
	var r: float = 0.0
	if _wave_mgr != null and _wave_mgr.has_method("ranged_ratio"):
		r = float(_wave_mgr.call("ranged_ratio"))
	if randf() < r:
		_spawn_mob(load("res://scenes/enemies/RangedEnemy.tscn"))
	else:
		_spawn_mob(melee_enemy_scene)


## 로스터(배열) 기반 종류 선택 — Main._request_spawn_roster 미러.
## Testplay 환경(lv2/슬래머비율 미적용)이라 key→scene 만 고르고 _spawn_mob.
func _wave_spawn_roster(rc) -> void:
	var t: float = (float(_wave_mgr.call("elapsed")) if _wave_mgr.has_method("elapsed") else 0.0)
	# 주술사 — 활성 엔트리 + 싱글톤(동시 1마리) 굴림.
	if rc.has_method("sorcerer_entry_active_at") and bool(rc.call("sorcerer_entry_active_at", t)):
		var sc: float = 0.05
		if rc.has_method("sorcerer_chance_at"):
			sc = float(rc.call("sorcerer_chance_at", t, 0.05))
		if sorcerer_enemy_scene != null and _wave_alive_sorcerer_count() < 1 and randf() < sc:
			_spawn_mob(sorcerer_enemy_scene)
			return
	var key: String = ""
	if rc.has_method("roster_pick_key"):
		key = str(rc.call("roster_pick_key", t, randf()))
	match key:
		"ranged":
			_spawn_mob(load("res://scenes/enemies/RangedEnemy.tscn"))
		"leaper":
			if _wave_alive_leaper_count() < 3:
				_spawn_mob(load("res://scenes/enemies/Leaper.tscn"))
			else:
				_spawn_mob(melee_enemy_scene)
		"slammer":
			_spawn_mob(slammer_enemy_scene)
		_:
			_spawn_mob(melee_enemy_scene)


func _wave_alive_sorcerer_count() -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("sorcerers"):
		if is_instance_valid(e) and not ("_dead" in e and e._dead):
			n += 1
	return n


func _wave_alive_leaper_count() -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("leapers"):
		if is_instance_valid(e) and not ("_dead" in e and e._dead):
			n += 1
	return n

func _wave_count_alive() -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not e.is_in_group("boss"):
			n += 1
	return n


## 아레나 — 웨이브 시계 점프(스토리보드 페이즈 빨리 테스트).
func arena_wave_jump(secs: float) -> void:
	if _wave_mgr != null and _wave_mgr.has_method("force_time"):
		var t: float = secs
		if _wave_mgr.has_method("elapsed"):
			t += float(_wave_mgr.call("elapsed"))
		_wave_mgr.call("force_time", t)

## 아레나 readout 용 — 현재 웨이브 시간/목표 인원.
func arena_wave_info() -> String:
	if _wave_mgr == null or not _wave_running:
		return "웨이브: 정지"
	var t: float = (float(_wave_mgr.call("elapsed")) if _wave_mgr.has_method("elapsed") else 0.0)
	var tg: int = (int(_wave_mgr.call("current_target")) if _wave_mgr.has_method("current_target") else 0)
	return "웨이브: %.0fs · 목표 %d" % [t, tg]


func arena_toggle_escape_zone() -> bool:
	if _escape_zone != null and is_instance_valid(_escape_zone):
		_escape_zone.queue_free()
		_escape_zone = null
		return false
	_escape_zone = _EscapeZoneScript.new()
	_escape_zone.name = "EscapeZone"
	add_child(_escape_zone)
	var c: Vector3 = (_player.global_position if _player != null and is_instance_valid(_player) else Vector3.ZERO)
	_escape_zone.call("setup", c)
	return true


func _on_spawn_regular_10() -> void:
	for i in range(regular_mob_count):
		_spawn_mob(melee_enemy_scene)

func _on_spawn_slammer() -> void:
	_spawn_mob(slammer_enemy_scene)


func _on_spawn_sorcerer() -> void:
	_spawn_mob(sorcerer_enemy_scene)


func _on_spawn_boss() -> void:
	_spawn_boss()


func _on_spawn_boss_2() -> void:
	_spawn_boss_2()


func _on_spawn_boss_3() -> void:
	_spawn_boss_3()


func _on_boon_gumiho_mark() -> void:
	if not is_instance_valid(_player):
		return
	if _player.has_method("add_boon"):
		_player.call("add_boon", "gumiho_mark", "uniq")


func _on_boon_gumiho_lifesteal() -> void:
	if not is_instance_valid(_player):
		return
	if _player.has_method("add_boon"):
		_player.call("add_boon", "gumiho_lifesteal", "uniq")


func _on_boon_gumiho_charm() -> void:
	if not is_instance_valid(_player):
		return
	if _player.has_method("add_boon"):
		_player.call("add_boon", "gumiho_charm", "uniq")


func _on_boon_gumiho_summon() -> void:
	if not is_instance_valid(_player):
		return
	if _player.has_method("add_boon"):
		_player.call("add_boon", "gumiho_summon", "uniq")


func _on_boon_gumiho_foxfire() -> void:
	if not is_instance_valid(_player):
		return
	if _player.has_method("add_boon"):
		_player.call("add_boon", "gumiho_foxfire", "uniq")


func _on_boon_gumiho_slashfan() -> void:
	if not is_instance_valid(_player):
		return
	if _player.has_method("add_boon"):
		_player.call("add_boon", "gumiho_slashfan", "uniq")


func _on_boon_gumiho_radial() -> void:
	if not is_instance_valid(_player):
		return
	if _player.has_method("add_boon"):
		_player.call("add_boon", "gumiho_radial", "uniq")
