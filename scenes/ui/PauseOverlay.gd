extends CanvasLayer

## ESC 일시정지 메뉴 + 툴 에디터 팝업.
## process_mode = ALWAYS 라 tree.paused(게임 시간 정지) 중에도 ESC 입력/버튼이 동작한다
## — Main 은 paused 면 입력을 못 받으므로 ESC 소유를 이 노드로 옮겼다.
##   ESC       → 열기(게임 정지 + 화면 어둡게) / 닫기(재개)
##   툴 에디터  → 개발용 툴 패널(웨이브 비율 프리셋 + 옵션 토글)을 따로 팝업
## 프리셋/토글은 GameConfig(static) 만 만지고 씬을 리로드하므로 Main 의존 없이 자족적이다
## (리로드된 Main 이 _apply_wave_preset 로 GameConfig.wave_preset 을 적용).

const _GameConfigScript := preload("res://scripts/managers/GameConfig.gd")
const _CombatDataScript := preload("res://scripts/managers/CombatData.gd")

var _dim: ColorRect
var _menu: VBoxContainer
var _tools: VBoxContainer
var _zoom_btn: Button
var _contact_btn: Button
var _resource_btn: Button
var _aim_btn: Button
## 몬스터 리스트(검색 에디터) 패널 + 검색창 + 필터용 행 캐시.
var _monsters: VBoxContainer
var _mon_search: LineEdit
var _mon_rows: Array = []


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
	_monsters.visible = false

func _resume() -> void:
	visible = false
	_tools.visible = false
	_monsters.visible = false
	get_tree().paused = false

func _open_tools() -> void:
	_menu.visible = false
	_monsters.visible = false
	_tools.visible = true
	_refresh_toggles()

func _close_tools() -> void:
	_tools.visible = false
	_menu.visible = true

func _open_monsters() -> void:
	_menu.visible = false
	_tools.visible = false
	_monsters.visible = true

func _close_monsters() -> void:
	_monsters.visible = false
	_menu.visible = true


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
	_refresh_toggles()

func _on_set_resource() -> void:
	_GameConfigScript.slash_resource_mode = 1 - _GameConfigScript.slash_resource_mode
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_set_aim() -> void:
	_GameConfigScript.slash_aim_mode = 1 - _GameConfigScript.slash_aim_mode
	get_tree().paused = false
	get_tree().reload_current_scene()

func _refresh_toggles() -> void:
	if _zoom_btn != null:
		_zoom_btn.text = "LB 차징 줌아웃: " + ("ON" if _GameConfigScript.charge_zoom_enabled else "OFF")
	if _contact_btn != null:
		_contact_btn.text = "몬스터 충돌 피해: " + ("ON" if _GameConfigScript.contact_damage_enabled else "OFF")
	if _resource_btn != null:
		var rm: int = _GameConfigScript.slash_resource_mode
		_resource_btn.text = "[PLACEHOLDER] 일섬 자원: " + ("열기" if rm == 0 else "쿨다운")
	if _aim_btn != null:
		var am: int = _GameConfigScript.slash_aim_mode
		_aim_btn.text = "[PLACEHOLDER] 일섬 에임: " + ("차징" if am == 0 else "즉발")

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
	_menu.add_child(_btn("몬스터 리스트", _open_monsters))
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
	_tools.add_child(_btn("닫기", _close_tools))
	_refresh_toggles()
	_tools.visible = false

	_build_monsters()


## 몬스터 리스트 — enemy.csv 의 display_name/concept/color/icon 을 읽어 검색 가능한 카드 목록.
## 좌상단 패널 · 검색창(이름/컨셉 필터) · 스크롤 카드(틴트 아이콘 + 이름 + 컨셉 + 컬러 스와치).
func _build_monsters() -> void:
	_monsters = VBoxContainer.new()
	_monsters.add_theme_constant_override("separation", 8)
	_monsters.position = Vector2(24, 70)
	_monsters.custom_minimum_size = Vector2(470, 0)
	add_child(_monsters)
	_monsters.add_child(_title("── 몬스터 리스트 (검색) ──"))
	_mon_search = LineEdit.new()
	_mon_search.placeholder_text = "이름 / 컨셉 검색…"
	_mon_search.custom_minimum_size = Vector2(450, 34)
	_mon_search.add_theme_font_size_override("font_size", 15)
	_mon_search.text_changed.connect(_filter_monsters)
	_monsters.add_child(_mon_search)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(450, 380)
	_monsters.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for row in _CombatDataScript.all_enemy_rows():
		var nm: String = String(row.get("display_name", "")).strip_edges()
		if nm == "":
			continue
		var concept: String = String(row.get("concept", ""))
		var card := _make_monster_card(String(row.get("id", "")), nm, concept,
			String(row.get("color", "")), String(row.get("icon", "")))
		list.add_child(card)
		_mon_rows.append({"node": card, "q": (nm + " " + concept).to_lower()})
	_monsters.add_child(_btn("닫기", _close_monsters))
	_monsters.visible = false


func _make_monster_card(id_s: String, name_s: String, concept_s: String, color_s: String, icon_s: String) -> Control:
	var col := Color(0.82, 0.82, 0.85)
	if color_s != "" and Color.html_is_valid(color_s):
		col = Color.html(color_s)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.12, 0.16, 0.96)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	panel.add_child(hb)
	# 아이콘(틴트 = 인게임 컬러).
	var tex := TextureRect.new()
	tex.custom_minimum_size = Vector2(52, 52)
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if icon_s != "" and ResourceLoader.exists(icon_s):
		tex.texture = load(icon_s)
	tex.modulate = col
	hb.add_child(tex)
	# 이름 + 컨셉.
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nm := Label.new()
	nm.text = "#%s  %s" % [id_s, name_s]
	nm.add_theme_color_override("font_color", col)
	nm.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	nm.add_theme_constant_override("outline_size", 4)
	nm.add_theme_font_size_override("font_size", 17)
	vb.add_child(nm)
	var cc := Label.new()
	cc.text = concept_s
	cc.add_theme_color_override("font_color", Color(0.82, 0.85, 0.92))
	cc.add_theme_font_size_override("font_size", 12)
	cc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cc.custom_minimum_size = Vector2(330, 0)
	vb.add_child(cc)
	hb.add_child(vb)
	# 컬러 스와치.
	var sw := ColorRect.new()
	sw.color = col
	sw.custom_minimum_size = Vector2(16, 0)
	sw.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hb.add_child(sw)
	return panel


func _filter_monsters(query: String) -> void:
	var q: String = query.to_lower().strip_edges()
	for r in _mon_rows:
		var n = r["node"]
		if is_instance_valid(n):
			n.visible = q == "" or (String(r["q"]).find(q) >= 0)


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
