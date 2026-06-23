extends CanvasLayer

## ESC 일시정지 메뉴 + 툴 에디터 팝업.
## process_mode = ALWAYS 라 tree.paused(게임 시간 정지) 중에도 ESC 입력/버튼이 동작한다
## — Main 은 paused 면 입력을 못 받으므로 ESC 소유를 이 노드로 옮겼다.
##   ESC       → 열기(게임 정지 + 화면 어둡게) / 닫기(재개)
##   툴 에디터  → 개발용 툴 패널(웨이브 비율 프리셋 + 옵션 토글)을 따로 팝업
## 프리셋/토글은 GameConfig(static) 만 만지고 씬을 리로드하므로 Main 의존 없이 자족적이다
## (리로드된 Main 이 _apply_wave_preset 로 GameConfig.wave_preset 을 적용).

const _GameConfigScript := preload("res://scripts/managers/GameConfig.gd")
const _SettingsPanelScene := preload("res://scenes/ui/SettingsPanel.tscn")

var _dim: ColorRect
var _menu: VBoxContainer
var _tools: VBoxContainer
var _zoom_btn: Button
var _contact_btn: Button
var _resource_btn: Button
var _aim_btn: Button
var _overheat_slow_btn: Button
var _settings_panel


func _ready() -> void:
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_toggle()
		get_viewport().set_input_as_handled()


func _toggle() -> void:
	if visible:
		_resume()
	else:
		_pause()

func _pause() -> void:
	get_tree().paused = true
	visible = true
	_menu.visible = true
	_tools.visible = false

func _resume() -> void:
	visible = false
	_tools.visible = false
	get_tree().paused = false

func _open_tools() -> void:
	_menu.visible = false
	_tools.visible = true
	_refresh_toggles()

func _close_tools() -> void:
	_tools.visible = false
	_menu.visible = true

func _open_settings() -> void:
	if _settings_panel != null and _settings_panel.has_method("open"):
		_settings_panel.call("open")

func _on_main_menu() -> void:
	get_tree().paused = false
	var st = get_node_or_null("/root/SceneTransition")
	if st != null and st.has_method("change_scene"):
		st.call("change_scene", "res://scenes/main/OutGame.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/main/OutGame.tscn")


## 모드 선택 = 컨트롤(밀리/일섬) + 웨이브 구성을 GameConfig 에 저장 후 씬 리로드(재시작).
## 리로드된 Main 이 instant_slash_mode(Player) + wave_preset(_apply_wave_preset) 적용.
func _set_mode(instant: bool, wave: int) -> void:
	_GameConfigScript.instant_slash_mode = instant
	_GameConfigScript.wave_preset = wave
	_GameConfigScript.contact_damage_enabled = false
	_GameConfigScript.charge_zoom_enabled = instant   # 카메라 줌 — 밀리 모드만 OFF, 일섬은 ON
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_toggle(key: String) -> void:
	if key == "charge_zoom":
		_GameConfigScript.charge_zoom_enabled = not _GameConfigScript.charge_zoom_enabled
	elif key == "contact_dmg":
		_GameConfigScript.contact_damage_enabled = not _GameConfigScript.contact_damage_enabled
	elif key == "overheat_slow":
		_GameConfigScript.overheat_move_slow_enabled = not _GameConfigScript.overheat_move_slow_enabled
	_refresh_toggles()

func _on_set_resource() -> void:
	_GameConfigScript.slash_resource_mode = 1 - _GameConfigScript.slash_resource_mode
	_refresh_toggles()

func _on_set_aim() -> void:
	_GameConfigScript.slash_aim_mode = 1 - _GameConfigScript.slash_aim_mode
	_refresh_toggles()

func _refresh_toggles() -> void:
	if _zoom_btn != null:
		_zoom_btn.text = "LB 차징 줌아웃: " + ("ON" if _GameConfigScript.charge_zoom_enabled else "OFF")
	if _contact_btn != null:
		_contact_btn.text = "몬스터 충돌 피해: " + ("ON" if _GameConfigScript.contact_damage_enabled else "OFF")
	if _resource_btn != null:
		var rm: int = _GameConfigScript.slash_resource_mode
		_resource_btn.text = "일섬 자원: " + ("열기" if rm == 0 else "쿨다운")
	if _aim_btn != null:
		var am: int = _GameConfigScript.slash_aim_mode
		_aim_btn.text = "일섬 에임: " + ("차징" if am == 0 else "즉발")
	if _overheat_slow_btn != null:
		_overheat_slow_btn.text = "탈진 이동 감속: " + ("ON" if _GameConfigScript.overheat_move_slow_enabled else "OFF")

func _build() -> void:
	# 어둡게 — 전체 화면 반투명 검정(ESC 눌렀음을 시각화 + 게임 클릭 차단). 리사이즈 추종.
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.5)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	var vp: Vector2 = get_viewport().get_visible_rect().size

	# ── ESC 메뉴(중앙) — 툴 에디터 / 계속하기 ──
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 12)
	_menu.position = Vector2(vp.x * 0.5 - 160.0, vp.y * 0.5 - 90.0)
	_menu.custom_minimum_size = Vector2(320, 0)
	add_child(_menu)
	_menu.add_child(_title("⏸  일시정지"))
	_menu.add_child(_info("모드: " + _mode_name()))
	_menu.add_child(_btn("툴 에디터", _open_tools))
	_menu.add_child(_btn("설정", _open_settings))
	_menu.add_child(_btn("메인 메뉴로", _on_main_menu))
	_menu.add_child(_btn("계속하기 (ESC)", _resume))

	# ── 툴 에디터 팝업(좌상단) — 웨이브 프리셋 + 옵션 토글 ──
	_tools = VBoxContainer.new()
	_tools.add_theme_constant_override("separation", 8)
	_tools.position = Vector2(24, 80)
	_tools.custom_minimum_size = Vector2(330, 0)
	add_child(_tools)
	_tools.add_child(_title("── 툴 에디터 ──"))
	_tools.add_child(_info("현재: " + _mode_name()))
	_tools.add_child(_info("── 모드 (선택 시 재시작) ──"))
	_tools.add_child(_btn("근접 밀리 모드 (근90·원5·엘5)", _set_mode.bind(false, 0)))
	_tools.add_child(_btn("근접 몬스터 일섬 모드 (근90·원5·엘5)", _set_mode.bind(true, 1)))
	_tools.add_child(_btn("원거리 몬스터 일섬 모드 (원60·근35·엘5·총×0.2)", _set_mode.bind(true, 2)))
	_tools.add_child(_info("── 옵션 (토글) ──"))
	_zoom_btn = _btn("", _on_toggle.bind("charge_zoom"))
	_tools.add_child(_zoom_btn)
	_contact_btn = _btn("", _on_toggle.bind("contact_dmg"))
	_tools.add_child(_contact_btn)
	_resource_btn = _btn("", _on_set_resource)
	_tools.add_child(_resource_btn)
	_aim_btn = _btn("", _on_set_aim)
	_tools.add_child(_aim_btn)
	_overheat_slow_btn = _btn("", _on_toggle.bind("overheat_slow"))
	_tools.add_child(_overheat_slow_btn)
	_tools.add_child(_btn("닫기", _close_tools))
	_refresh_toggles()
	_tools.visible = false

	_settings_panel = _SettingsPanelScene.instantiate()
	add_child(_settings_panel)


## 현재 모드 이름 — 컨트롤(밀리/일섬) + 웨이브 구성 조합.
func _mode_name() -> String:
	if not _GameConfigScript.instant_slash_mode:
		return "근접 밀리 모드"
	var w: int = _GameConfigScript.wave_preset
	if w == 1:
		return "근접 몬스터 일섬 모드"
	if w == 2:
		return "원거리 몬스터 일섬 모드"
	return "일섬 모드 (기본 웨이브)"

func _title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(1, 0.95, 0.6))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_font_size_override("font_size", 18)
	return l

func _info(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.85, 0.9, 1))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_font_size_override("font_size", 14)
	return l

func _btn(text: String, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(300, 42)
	btn.add_theme_font_size_override("font_size", 15)
	btn.add_theme_color_override("font_color", Color(1, 1, 1))
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.18, 0.22, 0.96)
	style.set_corner_radius_all(6)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.28, 0.32, 0.42, 0.98)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.pressed.connect(cb)
	return btn
