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
@export var elite_enemy_scene: PackedScene
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

# 일섬 게이지 바 (Main 미러). 화면 하단 중앙 0~100% 바.
const _SLASH_GAUGE_W := 280.0
const _SLASH_GAUGE_H := 22.0
const _SLASH_GAUGE_FILL := Color(0.3, 0.7, 1.0, 0.9)
const _SLASH_GAUGE_FILL_READY := Color(1.0, 0.82, 0.2, 0.95)

# 좌상단 칸 단위 HP (Main 미러). 빨강=남은 칸, 어두운색=잃은 칸.
const _HP_FULL := Color(0.85, 0.15, 0.15)
const _HP_EMPTY := Color(0.22, 0.08, 0.08)

# --- Chapter / EXP scripts (preload to dodge class_name cache misses
# in --headless runs, same as Main.gd) ---
const _ExpSystemScript := preload("res://scripts/managers/ExpSystem.gd")
const _UpgradeSystemScript := preload("res://scripts/managers/UpgradeSystem.gd")
const _InfiniteGroundScript := preload("res://scripts/managers/InfiniteGround.gd")
const _ZenSystemScript := preload("res://scripts/managers/ZenSystem.gd")
# M8 refactor — same shared services as Main, so the debug arena runs
# identical elite-payload + bullet-time code instead of mirrored copies.
const _EliteEffectServiceScript := preload("res://scripts/managers/EliteEffectService.gd")
const _BulletTimeServiceScript := preload("res://scripts/managers/BulletTimeService.gd")

var _player: Node
var _camera: HD2DCamera
var _enemies_root: Node3D
var _exp_bar: CanvasLayer
var _exp_system: Node
var _world_env: WorldEnvironment
var _elite_effect_service: Node
var _bullet_time_service: Node
# 일섬 게이지 바 (Main HUD 미러).
var _slash_gauge_bg: ColorRect
var _slash_gauge_bar: ColorRect
var _slash_gauge_label: Label
# 좌상단 칸 단위 HP (Main HUD 미러).
var _hp_box: HBoxContainer
var _hp_cells: Array = []
# 장탄수(비도) 텍스트 (Main HUD 미러).
var _ammo_label: Label

func _ready() -> void:
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
	_build_button_panel()
	_build_help_label()

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("restart"):
		get_tree().reload_current_scene()
		return
	_refresh_hp_cells()
	_refresh_ammo()
	_refresh_slash_gauge()

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
	# Echo card mirror (same as Main) — keeps testplay reaching feature
	# parity for card testing.
	if _player.has_signal("slash_finished"):
		_player.slash_finished.connect(_on_player_slash_finished)
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
	if exp_bar_scene != null:
		_exp_bar = exp_bar_scene.instantiate() as CanvasLayer
		add_child(_exp_bar)
		if _exp_bar.has_method("set_exp_source"):
			_exp_bar.call("set_exp_source", _exp_system)

	# ⏱ Testplay mirrors the ZenSystem wire-up so perfect parries /
	# charges on the debug arena feed the burst just like in Main.
	var zs := _ZenSystemScript.new()
	zs.name = "ZenSystem"
	add_child(zs)
	if _player != null and is_instance_valid(_player):
		zs.bind(_player)
	if _player != null and "bind_zen_system" in _player:
		_player.call("bind_zen_system", zs)

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
	# Mirror of Main — small instant EXP + gem drop carrying the bulk.
	_exp_system.add_exp(1)
	_drop_exp_gem(enemy, base)
	# Vampire card mirror — Testplay supports card testing too.
	_try_vampire_heal()
	# 4안 — 처치 시 일섬 게이지 (mirror).
	if _player != null and is_instance_valid(_player) and _player.has_method("gain_gauge_on_kill"):
		_player.call("gain_gauge_on_kill")


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

func _spawn_elite(effect_type: int) -> void:
	if elite_enemy_scene == null:
		return
	var inst := elite_enemy_scene.instantiate()
	if "effect_type" in inst:
		inst.effect_type = effect_type
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
		{"label": "엘리트 1 (폭발)", "cb": Callable(self, "_on_spawn_elite_1")},
		{"label": "엘리트 2 (보너스 슬래시)", "cb": Callable(self, "_on_spawn_elite_2")},
		{"label": "엘리트 3 (불릿타임)", "cb": Callable(self, "_on_spawn_elite_3")},
		{"label": "엘리트 4 (보호막)", "cb": Callable(self, "_on_spawn_elite_4")},
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
	# that the PC reads. The PC's `_check_attack_start` separately calls
	# `gui_get_hovered_control()` to swallow clicks landing on UI.
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	return btn

func _build_help_label() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "TestplayHelp"
	add_child(canvas)
	var label := Label.new()
	label.text = "Testplay  |  WASD: 이동  LMB: 비도  RMB(hold): 일섬(게이지 100%)  SPACE: 자동조준  R: 재시작"
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_font_size_override("font_size", 16)
	# HP 칸(20,16) + 장탄수(20,46)이 좌상단을 차지하므로 도움말은 더 아래로.
	label.position = Vector2(20, 72)
	canvas.add_child(label)
	_build_hp_cells(canvas)
	_build_ammo_label(canvas)
	_build_slash_gauge(canvas)

## 장탄수(비도) 텍스트 (Main._build_hud 의 _ammo_label 미러).
func _build_ammo_label(canvas: CanvasLayer) -> void:
	_ammo_label = Label.new()
	_ammo_label.text = "비도: - / -"
	_ammo_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_ammo_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_ammo_label.add_theme_constant_override("outline_size", 4)
	_ammo_label.add_theme_font_size_override("font_size", 16)
	_ammo_label.position = Vector2(20, 46)
	canvas.add_child(_ammo_label)

## 장탄수 갱신 (Main._refresh_ammo 미러).
func _refresh_ammo() -> void:
	if _ammo_label == null or _player == null or not is_instance_valid(_player):
		return
	if not _player.has_method("get_ammo"):
		return
	var reloading: bool = _player.has_method("is_reloading") and bool(_player.call("is_reloading"))
	if reloading:
		_ammo_label.text = "비도: 리로드 중…"
		_ammo_label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.25))
	else:
		var ammo: int = int(_player.call("get_ammo"))
		var maxa: int = int(_player.call("get_max_ammo")) if _player.has_method("get_max_ammo") else ammo
		_ammo_label.text = "비도: %d / %d" % [ammo, maxa]
		_ammo_label.add_theme_color_override("font_color", Color(1, 1, 1))

## 좌상단 칸 단위 HP (Main._build_hud 의 _hp_box 미러). 빈 컨테이너만 만들고
## `_refresh_hp_cells` 가 매 프레임 채운다.
func _build_hp_cells(canvas: CanvasLayer) -> void:
	_hp_box = HBoxContainer.new()
	_hp_box.add_theme_constant_override("separation", 5)
	_hp_box.position = Vector2(20, 16)
	canvas.add_child(_hp_box)

## 좌상단 칸 단위 HP 갱신 (Main._refresh_hp_cells 미러).
func _refresh_hp_cells() -> void:
	if _hp_box == null or _player == null or not is_instance_valid(_player):
		return
	if not _player.has_method("get_hp"):
		return
	var max_hp: int = 3
	if _player.has_method("get_max_hp"):
		max_hp = max(1, int(_player.call("get_max_hp")))
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

## 일섬 게이지 바 (Main._build_slash_gauge 미러). 화면 하단 중앙 0~100% 바.
func _build_slash_gauge(canvas: CanvasLayer) -> void:
	_slash_gauge_bg = ColorRect.new()
	_slash_gauge_bg.color = Color(0.07, 0.07, 0.09, 0.85)
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

## 매 프레임 일섬 게이지 바 갱신 (Main._refresh_slash_gauge 미러).
func _refresh_slash_gauge() -> void:
	if _slash_gauge_bar == null or _player == null or not is_instance_valid(_player):
		return
	if not _player.has_method("slash_gauge_frac"):
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

## --- Button callbacks ---

func _on_spawn_regular_10() -> void:
	for i in range(regular_mob_count):
		_spawn_mob(melee_enemy_scene)

func _on_spawn_elite_1() -> void:
	_spawn_elite(1)

func _on_spawn_elite_2() -> void:
	_spawn_elite(2)

func _on_spawn_elite_3() -> void:
	_spawn_elite(3)


func _on_spawn_elite_4() -> void:
	_spawn_elite(4)


func _on_spawn_boss() -> void:
	_spawn_boss()


func _on_spawn_boss_2() -> void:
	_spawn_boss_2()


func _on_spawn_boss_3() -> void:
	_spawn_boss_3()
