extends Node3D

const _PlayerScene := preload("res://scenes/player/Player.tscn")
const _CameraScene := preload("res://scenes/main/HD2DCamera.tscn")
const _MeleeScene := preload("res://scenes/enemies/MeleeEnemy.tscn")
const _InfiniteGroundScript := preload("res://scripts/managers/InfiniteGround.gd")
const _AimCursorScene := preload("res://scenes/ui/AimCursor.tscn")
const _GameConfig := preload("res://scripts/managers/GameConfig.gd")
const _TriggerBusScript := preload("res://scripts/managers/TriggerBus.gd")

enum Step { STEP_SLASH, STEP_DODGE, STEP_SHEATHE, DONE }

const _SLASH_GOAL := 3
const _DODGE_GOAL := 2

var _player
var _camera
var _ui: CanvasLayer
var _label: Label
var _step: int = Step.STEP_SLASH
var _slash_kills: int = 0
var _dodge_count: int = 0
var _done_btn: Button
var _tb: Node
var _dummy


func _ready() -> void:
	_player = _PlayerScene.instantiate()
	_player.add_to_group("player")
	add_child(_player)
	(_player as Node3D).global_position = Vector3.ZERO

	if "god_mode" in _player:
		_player.god_mode = true

	var ig := _InfiniteGroundScript.new()
	ig.name = "InfiniteGround"
	add_child(ig)
	if _player is Node3D:
		ig.set_target(_player as Node3D)

	_camera = _CameraScene.instantiate()
	add_child(_camera)
	if _camera.has_method("set_target"):
		_camera.set_target(_player as Node3D)

	add_child(_AimCursorScene.instantiate())

	_build_ui()

	_tb = get_node_or_null("/root/TriggerBus")
	if _tb != null and _tb.has_method("subscribe"):
		_tb.call("subscribe", _TriggerBusScript.ON_KILL_VIA_SLASH, _on_slash_kill)
		_tb.call("subscribe", _TriggerBusScript.ON_DASH_START, _on_dash_start)
		_tb.call("subscribe", _TriggerBusScript.ON_SHEATHE_KILL, _on_sheathe_kill)

	_enter_step(Step.STEP_SLASH)


func _exit_tree() -> void:
	if _tb != null and _tb.has_method("unsubscribe"):
		_tb.call("unsubscribe", _TriggerBusScript.ON_KILL_VIA_SLASH, _on_slash_kill)
		_tb.call("unsubscribe", _TriggerBusScript.ON_DASH_START, _on_dash_start)
		_tb.call("unsubscribe", _TriggerBusScript.ON_SHEATHE_KILL, _on_sheathe_kill)


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)

	_label = Label.new()
	_label.anchor_left = 0.0
	_label.anchor_right = 1.0
	_label.anchor_top = 0.0
	_label.offset_top = 60.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 30)
	_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_label.add_theme_constant_override("outline_size", 6)
	_ui.add_child(_label)

	var hint := Label.new()
	hint.anchor_left = 0.0
	hint.anchor_right = 1.0
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_top = -40.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	hint.text = "ESC — 메인으로 돌아가기"
	_ui.add_child(hint)


func _enter_step(s: int) -> void:
	_step = s
	match s:
		Step.STEP_SLASH:
			_label.text = "LB(좌클릭)으로 일섬을 날려 적을 베세요 (%d/%d)" % [_slash_kills, _SLASH_GOAL]
			_spawn_dummy(1)
		Step.STEP_DODGE:
			_label.text = "SPACE 로 굴러 회피하세요 (%d/%d)" % [_dodge_count, _DODGE_GOAL]
		Step.STEP_SHEATHE:
			_label.text = "일섬으로 적 머리 위 표식(청백)을 쌓고 → 우클릭(납도)으로 거두세요!"
			# 훈련용 허수아비 — 일섬 누적뎀(2/타)으론 천천히만 닳아(15타) 표식 만개(5타) 전에 안 죽음.
			# → 플레이어가 표식 쌓고 납도(RB)로 거두는 흐름을 자연히 익힌다.
			_spawn_dummy(30)
		Step.DONE:
			_enter_done()


func _spawn_dummy(hp: int) -> void:
	_dummy = _MeleeScene.instantiate()
	add_child(_dummy)
	(_dummy as Node3D).global_position = (_player as Node3D).global_position + Vector3(0, 0, -6)
	var hc = _dummy.get_node_or_null("HealthComponent")
	if hc != null and hc.has_method("setup"):
		hc.setup(hp)


func _on_slash_kill(_ctx: Dictionary) -> void:
	if not is_inside_tree():
		return
	if _step != Step.STEP_SLASH:
		return
	_slash_kills += 1
	if _slash_kills >= _SLASH_GOAL:
		_enter_step(Step.STEP_DODGE)
	else:
		_refresh_label_slash()
		_spawn_dummy(1)


func _on_dash_start(_ctx: Dictionary) -> void:
	if not is_inside_tree():
		return
	if _step != Step.STEP_DODGE:
		return
	_dodge_count += 1
	if _dodge_count >= _DODGE_GOAL:
		_enter_step(Step.STEP_SHEATHE)
	else:
		_label.text = "SPACE 로 굴러 회피하세요 (%d/%d)" % [_dodge_count, _DODGE_GOAL]


func _on_sheathe_kill(_ctx: Dictionary) -> void:
	if not is_inside_tree():
		return
	if _step != Step.STEP_SHEATHE:
		return
	_enter_step(Step.DONE)


func _refresh_label_slash() -> void:
	_label.text = "LB(좌클릭)으로 일섬을 날려 적을 베세요 (%d/%d)" % [_slash_kills, _SLASH_GOAL]


func _enter_done() -> void:
	_label.text = "튜토리얼 완료!"

	_done_btn = Button.new()
	_done_btn.text = "게임 시작"
	_done_btn.custom_minimum_size = Vector2(280, 56)
	_done_btn.anchor_left = 0.5
	_done_btn.anchor_right = 0.5
	_done_btn.anchor_top = 0.6
	_done_btn.offset_left = -140.0
	_done_btn.add_theme_font_size_override("font_size", 22)
	_done_btn.pressed.connect(_start_real_game)
	_ui.add_child(_done_btn)


func _start_real_game() -> void:
	_GameConfig.wave_preset = 0
	_GameConfig.contact_damage_enabled = false
	_GameConfig.charge_zoom_enabled = true
	_GameConfig.slash_resource_mode = 0
	_GameConfig.slash_aim_mode = 1

	var st = get_node_or_null("/root/SceneTransition")
	if st != null and st.has_method("change_scene"):
		st.call("change_scene", "res://scenes/main/Main.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/main/Main.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://scenes/main/OutGame.tscn")
