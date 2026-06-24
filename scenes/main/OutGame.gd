extends Control

## Main menu — the new `project.godot/run/main_scene`. Routes the player
## into a run (Main.tscn) or into the meta upgrade panel. Built procedurally
## (no .tscn nodes) so future polish iterations can swap visuals without
## touching script wiring.

const _MetaScript := preload("res://scripts/managers/MetaProgressionSystem.gd")
const _SaveScript := preload("res://scripts/managers/SaveSystem.gd")
## 시작 버튼이 고른 컨트롤 모드를 인게임으로 넘기는 전역 플래그.
const _GameConfig := preload("res://scripts/managers/GameConfig.gd")
const _BuildConfigScript := preload("res://scripts/resources/BuildConfig.gd")
const _BUILD_CONFIG := "res://resources/build_config.tres"
const _MAIN_PATH := "res://scenes/main/Main.tscn"
const _META_MENU_PATH := "res://scenes/ui/MetaMenu.tscn"
const _SettingsPanelScene := preload("res://scenes/ui/SettingsPanel.tscn")

var _souls_label: Label
var _best_label: Label
var _settings_panel


func _ready() -> void:
	# Cover the whole viewport regardless of resolution.
	anchor_right = 1.0
	anchor_bottom = 1.0
	_build()
	get_viewport().size_changed.connect(_refresh_labels)


func _build() -> void:
	# Background — flat dark with a faint red wash (samurai blood-mood).
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.07, 0.08, 1.0)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var center := VBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.anchor_left = 0.5
	center.anchor_right = 0.5
	center.anchor_top = 0.5
	center.anchor_bottom = 0.5
	center.offset_left = -260.0
	center.offset_right = 260.0
	center.offset_top = -250.0
	center.offset_bottom = 250.0
	center.add_theme_constant_override("separation", 18)
	add_child(center)

	var title := Label.new()
	title.text = "⚔️  프로젝트 일섬뱀서"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2, 1.0))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	title.add_theme_constant_override("outline_size", 6)
	title.add_theme_font_size_override("font_size", 48)
	center.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "한 손으로 30분, 한 챕터로 영원히 살아남는 사무라이"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7))
	subtitle.add_theme_font_size_override("font_size", 14)
	center.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 24)
	center.add_child(spacer)

	_souls_label = Label.new()
	_souls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_souls_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	_souls_label.add_theme_font_size_override("font_size", 22)
	center.add_child(_souls_label)

	_best_label = Label.new()
	_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_best_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	_best_label.add_theme_font_size_override("font_size", 12)
	center.add_child(_best_label)

	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 18)
	center.add_child(spacer2)

	if _is_release_build():
		# 빌드 EXE — 게임 시작 단일 진입(빌드 매니저가 구운 모드/토글 적용). 사망 화면 "이어서 하기"는 유지.
		center.add_child(_make_button("게임 시작", _on_release_start))
		center.add_child(_make_button("설정", _on_settings_pressed))
		center.add_child(_make_button("종료", _on_quit_pressed))
	else:
		# 에디터/개발 — 전체 메뉴.
		center.add_child(_make_button("게임 시작", _on_start2_pressed))
		center.add_child(_make_button("밸런싱 아레나 (F1 패널)", _on_arena_pressed))
		center.add_child(_make_button("영구강화 (혼)", _on_meta_pressed))
		center.add_child(_make_button("설정", _on_settings_pressed))
		center.add_child(_make_button("종료", _on_quit_pressed))

	_refresh_labels()


func _refresh_labels() -> void:
	if _souls_label != null:
		_souls_label.text = "혼: %d      골드: %d" % [_MetaScript.souls(), _MetaScript.gold()]
	if _best_label != null:
		var ch1 := _SaveScript.best_for(1)
		var ch2 := _SaveScript.best_for(2)
		var parts: Array[String] = []
		if not ch1.is_empty() and int(ch1.get("best_kills", 0)) > 0:
			parts.append("Ch1 best %d kills · Lv %d" % [int(ch1.get("best_kills", 0)), int(ch1.get("best_level", 1))])
		if not ch2.is_empty() and int(ch2.get("best_kills", 0)) > 0:
			parts.append("Ch2 best %d kills · Lv %d" % [int(ch2.get("best_kills", 0)), int(ch2.get("best_level", 1))])
		if parts.is_empty():
			_best_label.text = "first run — let's go."
		else:
			_best_label.text = " · ".join(parts)


func _make_button(label: String, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(360, 54)
	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_color_override("font_color", Color(1, 1, 1))
	btn.add_theme_color_override("font_color_hover", Color(1, 1, 1))
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.16, 0.2, 1.0)
	style.border_color = Color(0.4, 0.4, 0.5, 1.0)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	btn.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.28, 0.18, 0.18, 1.0)
	hover.border_color = Color(0.78, 0.3, 0.25, 1.0)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.pressed.connect(cb)
	return btn


func _on_start2_pressed() -> void:
	# 게임 시작 — 일섬 단일 컨트롤 + 기본 웨이브. 웨이브 구성 전환은 인게임 ESC 툴에서.
	_GameConfig.wave_preset = 0
	_GameConfig.contact_damage_enabled = false
	_GameConfig.charge_zoom_enabled = true   # 일섬 차징 카메라 줌 기본 ON
	_goto(_MAIN_PATH)


## 빌드 EXE 여부 — 에디터(F5/F6)면 false(개발 메뉴), 익스포트된 빌드면 true(게임시작 단일).
func _is_release_build() -> bool:
	return not OS.has_feature("editor")


## 빌드 EXE 진입 — build_config.tres 의 모드/토글을 적용하고 게임 시작.
func _on_release_start() -> void:
	var cfg = (load(_BUILD_CONFIG) if ResourceLoader.exists(_BUILD_CONFIG) else _BuildConfigScript.new())
	var mode: int = (int(cfg.game_mode) if cfg != null and "game_mode" in cfg else 1)
	_GameConfig.wave_preset = mode                        # 0/1/2 웨이브 프리셋 (일섬 단일)
	_GameConfig.slash_resource_mode = (int(cfg.slash_resource_mode) if cfg != null and "slash_resource_mode" in cfg else 0)
	_GameConfig.slash_aim_mode = (int(cfg.slash_aim_mode) if cfg != null and "slash_aim_mode" in cfg else 1)
	_GameConfig.contact_damage_enabled = (bool(cfg.contact_damage) if cfg != null and "contact_damage" in cfg else false)
	_GameConfig.charge_zoom_enabled = (bool(cfg.charge_zoom) if cfg != null and "charge_zoom" in cfg else true)
	_GameConfig.overheat_move_slow_enabled = (bool(cfg.overheat_move_slow) if cfg != null and "overheat_move_slow" in cfg else false)
	_goto(_MAIN_PATH)


## 밸런싱 전용 아레나(Testplay) 입장 — 우측 스폰 버튼 + F1 디버그 패널(무적/배속/스탯주입/TTK).
func _on_arena_pressed() -> void:
	_goto("res://scenes/main/Testplay.tscn")


func _on_meta_pressed() -> void:
	_goto(_META_MENU_PATH)


## 씬 전환 — SceneTransition 자동로드가 있으면 셰이더 연출, 없으면 즉시 전환(폴백).
func _goto(path: String) -> void:
	var st = get_node_or_null("/root/SceneTransition")
	if st != null and st.has_method("change_scene"):
		st.call("change_scene", path)
	else:
		get_tree().change_scene_to_file(path)


func _on_settings_pressed() -> void:
	if _settings_panel == null:
		_settings_panel = _SettingsPanelScene.instantiate()
		add_child(_settings_panel)
	if _settings_panel.has_method("open"):
		_settings_panel.call("open")


func _on_quit_pressed() -> void:
	get_tree().quit()
