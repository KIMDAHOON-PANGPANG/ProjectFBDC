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
@export var camera_scene: PackedScene

@export_group("Effects")
@export var explosion_burst_scene: PackedScene
@export var circular_slash_scene: PackedScene

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

var _player: Node
var _camera: HD2DCamera
var _enemies_root: Node3D
var _exp_bar: CanvasLayer
var _exp_system: Node
var _world_env: WorldEnvironment

# Type-2 elite "bonus action" — same handshake as Main: wait for the
# next slash_finished before firing the bonus CircularSlash at the PC.
var _pending_circular_slash: bool = false

# Bullet-time machinery — toggles env saturation + every-enemy time_scale.
var _bullettime_tween: Tween
var _bullettime_active: bool = false

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
	var amount := 1
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

## --- Elite death payloads (mirror Main) ---

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

func _queue_circular_slash_after_slash() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if _pending_circular_slash:
		return
	var is_dashing: bool = false
	if "_state" in _player:
		is_dashing = _player._state == 2  # Player.State.DASHING
	if is_dashing and _player.has_signal("slash_finished"):
		_pending_circular_slash = true
		_player.slash_finished.connect(_on_pending_slash_finished, CONNECT_ONE_SHOT)
		get_tree().create_timer(1.5).timeout.connect(_clear_pending_circular_slash)
	else:
		_spawn_circular_slash((_player as Node3D).global_position)

func _on_pending_slash_finished() -> void:
	_pending_circular_slash = false
	if _player == null or not is_instance_valid(_player):
		return
	_spawn_circular_slash((_player as Node3D).global_position)

func _clear_pending_circular_slash() -> void:
	_pending_circular_slash = false

## --- Bullet-time / monochrome (mirror Main) ---

func _start_bullettime(duration: float) -> void:
	if _world_env == null:
		return
	_bullettime_active = true
	for e in get_tree().get_nodes_in_group("enemies"):
		if "time_scale_mult" in e:
			e.time_scale_mult = bullettime_slow_factor
	_apply_slow_to_loose_arrows(bullettime_slow_factor)
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
	for child in get_children():
		if child is EnemyArrow and "time_scale_mult" in child:
			child.time_scale_mult = factor

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
	if _bullettime_active and "time_scale_mult" in inst:
		inst.time_scale_mult = bullettime_slow_factor
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
	if _bullettime_active and "time_scale_mult" in inst:
		inst.time_scale_mult = bullettime_slow_factor
	_enemies_root.add_child(inst)
	if inst is Node3D:
		(inst as Node3D).global_position = _pick_random_spawn()
	_wire_enemy_lifecycle(inst)

func _spawn_boss() -> void:
	if boss_scene == null:
		return
	var inst := boss_scene.instantiate()
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
		{"label": "보스", "cb": Callable(self, "_on_spawn_boss")},
	]
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
	label.text = "Testplay  |  WASD: move  LMB(hold): aim slash  R: restart"
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_font_size_override("font_size", 16)
	label.position = Vector2(20, 16)
	canvas.add_child(label)

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

func _on_spawn_boss() -> void:
	_spawn_boss()
