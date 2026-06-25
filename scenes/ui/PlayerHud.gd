extends Control

## 하단 중앙 PC HUD — 초상화(PC 얼굴 크롭) + HP 바 + 열기(=일섬) 5스택 + 회피 2스택 + 레벨 뱃지.
## class_name 없음(헤드리스 캐시 회피) — Main/Testplay 가 preload+new 로 인스턴스 후 exp_system 주입.
## PC 는 그룹("player")으로 자가 탐색, 매 프레임 게터를 덕타이핑으로 읽어 갱신.

const _PORTRAIT_TEX := preload("res://market/Adventurer 2D Top-Down/Sprites/IDLE/idle_down.png")
const _FACE_REGION := Rect2(22, 2, 52, 52)  # idle_down 프레임0(96x80) 머리/어깨 크롭

const _HEAT_STACKS := 5
const _HP_FULL := Color(0.86, 0.17, 0.16)
const _HP_BG := Color(0.10, 0.04, 0.04, 0.92)
const _HEAT_LOW := Color(1.0, 0.62, 0.12)
const _HEAT_HIGH := Color(1.0, 0.22, 0.12)
const _HEAT_OFF := Color(0.26, 0.22, 0.20, 0.85)
const _HEAT_OVER := Color(0.5, 0.5, 0.5, 0.8)
const _DODGE_ON := Color(0.40, 0.85, 1.0)
const _DODGE_OFF := Color(0.20, 0.28, 0.32, 0.85)
const _FRAME := Color(0.85, 0.78, 0.55)
const _PANEL := Color(0.07, 0.07, 0.09, 0.86)

const _HP_X := 106.0
const _HP_W := 372.0

## 공용 상태 아이콘(2D) — 적 머리 스트립과 같은 radial 셰이더 데이터 모델 공유.
const _StatusIcon2DScript := preload("res://scenes/ui/StatusIcon2D.gd")

const _SHEATHE_READY := Color(0.95, 0.82, 0.35)
const _SHEATHE_COOL := Color(0.45, 0.40, 0.30, 0.9)
const _SHEATHE_PIE := Color(0.02, 0.02, 0.03, 0.78)
## 버프/디버프 스트립 아이콘 간격(px).
const _STATUS_SPACING := 34.0

## Main/Testplay 가 주입 — 레벨 뱃지용(ExpSystem 노드, .level).
var exp_system: Node = null

var _player: Node = null
var _hp_fill: ColorRect
var _hp_label: Label
var _heat_pips: Array = []
var _dodge_pips: Array = []
var _dodge_fills: Array = []
var _level_label: Label
## PC 버프/디버프 스트립(2D) — 빈 컨테이너 스캐폴드. set_status/clear_status 로 채운다.
## 현재 PC 지속버프 없음 → 빈 상태로도 패널이 깨지지 않게 컨테이너만 존재.
var _status_strip_2d: Control = null
## key(String) -> StatusIcon2D(Control)
var _status_icons_2d: Dictionary = {}
var _sheathe_clock: Control = null


func _ready() -> void:
	_build()
	set_process(true)


func _build() -> void:
	# 화면 하단 중앙 고정.
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -242.0
	offset_right = 242.0
	offset_top = -112.0
	offset_bottom = -12.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel := ColorRect.new()
	panel.color = _PANEL
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	# --- 초상화(방패형 프레임 + PC 얼굴 크롭) ---
	var frame := ColorRect.new()
	frame.color = _FRAME
	frame.position = Vector2(6, 6)
	frame.size = Vector2(88, 88)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	var pbg := ColorRect.new()
	pbg.color = Color(0.05, 0.06, 0.10)
	pbg.position = Vector2(10, 10)
	pbg.size = Vector2(80, 80)
	pbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pbg)
	var face := TextureRect.new()
	var atlas := AtlasTexture.new()
	atlas.atlas = _PORTRAIT_TEX
	atlas.region = _FACE_REGION
	face.texture = atlas
	face.position = Vector2(10, 10)
	face.size = Vector2(80, 80)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	face.clip_contents = true
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(face)

	# --- 레벨 뱃지(파란 다이아) ---
	var badge := Control.new()
	badge.position = Vector2(2, 66)
	badge.size = Vector2(36, 36)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(badge)
	var dia := ColorRect.new()
	dia.color = Color(0.16, 0.45, 0.92)
	dia.size = Vector2(24, 24)
	dia.position = Vector2(6, 6)
	dia.pivot_offset = Vector2(12, 12)
	dia.rotation = deg_to_rad(45.0)
	dia.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(dia)
	_level_label = Label.new()
	_level_label.text = "1"
	_level_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_style_label(_level_label, 15)
	badge.add_child(_level_label)

	# --- HP 바(빨강 + "cur/max") ---
	var hpbg := ColorRect.new()
	hpbg.color = _HP_BG
	hpbg.position = Vector2(_HP_X, 8)
	hpbg.size = Vector2(_HP_W, 28)
	hpbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hpbg)
	_hp_fill = ColorRect.new()
	_hp_fill.color = _HP_FULL
	_hp_fill.position = Vector2(_HP_X + 2, 10)
	_hp_fill.size = Vector2(_HP_W - 4, 24)
	_hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hp_fill)
	_hp_label = Label.new()
	_hp_label.text = "10 / 10"
	_hp_label.position = Vector2(_HP_X, 8)
	_hp_label.size = Vector2(_HP_W, 28)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_style_label(_hp_label, 16)
	add_child(_hp_label)

	# --- 열기(=일섬) 5스택 ---
	var heat_lbl := Label.new()
	heat_lbl.text = "열기"
	heat_lbl.position = Vector2(_HP_X, 44)
	heat_lbl.size = Vector2(34, 20)
	heat_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_style_label(heat_lbl, 13)
	add_child(heat_lbl)
	var heat_x := _HP_X + 38.0
	for i in _HEAT_STACKS:
		var pip := ColorRect.new()
		pip.color = _HEAT_OFF
		pip.position = Vector2(heat_x + i * 30.0, 46)
		pip.size = Vector2(26, 16)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(pip)
		_heat_pips.append(pip)

	# --- 회피 2스택 ---
	var dodge_lbl := Label.new()
	dodge_lbl.text = "회피"
	dodge_lbl.position = Vector2(heat_x + _HEAT_STACKS * 30.0 + 6.0, 44)
	dodge_lbl.size = Vector2(34, 20)
	dodge_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_style_label(dodge_lbl, 13)
	add_child(dodge_lbl)
	var dodge_x := heat_x + _HEAT_STACKS * 30.0 + 44.0
	for i in 2:
		var pip := ColorRect.new()
		pip.color = _DODGE_OFF
		pip.position = Vector2(dodge_x + i * 30.0, 46)
		pip.size = Vector2(26, 16)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(pip)
		_dodge_pips.append(pip)
		# 충전 게이지 — 칸 안에서 아래→위로 차오름(꽉=가득 / 충전중=부분 / 빈칸=0).
		var fill := ColorRect.new()
		fill.color = _DODGE_ON
		fill.position = Vector2(dodge_x + i * 30.0, 62)  # 바닥(46+16)에서 위로 자람
		fill.size = Vector2(26, 0)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(fill)
		_dodge_fills.append(fill)

	# --- 납도(RB) 쿨다운 클록 (MOBA 스킬버튼식 시계방향) ---
	var clock_x := dodge_x + 2 * 30.0 + 14.0
	_sheathe_clock = _SheatheClock.new()
	_sheathe_clock.position = Vector2(clock_x, 18.0)
	_sheathe_clock.size = Vector2(48, 48)
	_sheathe_clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheathe_clock.set("ready_col", _SHEATHE_READY)
	_sheathe_clock.set("cool_col", _SHEATHE_COOL)
	_sheathe_clock.set("pie_col", _SHEATHE_PIE)
	add_child(_sheathe_clock)

	# --- 버프/디버프 상태 스트립(스캐폴드) ---
	# 패널 위쪽(HP 바 상단 바깥)에 좌→우 배치되는 빈 컨테이너. PC 지속버프가 생기면
	# set_status(key, {...}) 로 즉시 아이콘이 뜨도록 공용 StatusIcon2D 를 재활용한다.
	# 현재 버프 없음 → 아이콘 0개라 보이지 않지만 컨테이너는 항상 존재(레이아웃 안전).
	_status_strip_2d = Control.new()
	_status_strip_2d.position = Vector2(_HP_X, -34.0)
	_status_strip_2d.size = Vector2(_HP_W, 30.0)
	_status_strip_2d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status_strip_2d)


## PC 상태 아이콘을 만들거나 갱신한다(공용 데이터 모델). d = {value, mode, color, icon}.
## 향후 PC 지속버프/디버프가 생기면 이 메서드로 즉시 표시된다(스캐폴드 노출).
func set_status(key: String, d: Dictionary) -> void:
	if _status_strip_2d == null:
		return
	var icon = _status_icons_2d.get(key, null)
	if icon == null or not is_instance_valid(icon):
		icon = _StatusIcon2DScript.new()
		_status_strip_2d.add_child(icon)
		_status_icons_2d[key] = icon
		_relayout_status()
	icon.call("set_data", d)


## key 상태 아이콘 제거.
func clear_status(key: String) -> void:
	var icon = _status_icons_2d.get(key, null)
	if icon != null and is_instance_valid(icon):
		icon.queue_free()
	if _status_icons_2d.has(key):
		_status_icons_2d.erase(key)
		_relayout_status()


## 살아있는 아이콘을 좌→우 가로 배치.
func _relayout_status() -> void:
	var i := 0
	for k in _status_icons_2d.keys():
		var ic = _status_icons_2d[k]
		if ic != null and is_instance_valid(ic):
			(ic as Control).position = Vector2(float(i) * _STATUS_SPACING, 0.0)
			i += 1


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return
	# HP
	var cur := 0
	var mx := 1
	if _player.has_method("get_hp"):
		cur = int(_player.call("get_hp"))
	if _player.has_method("get_max_hp"):
		mx = max(1, int(_player.call("get_max_hp")))
	if _hp_fill != null:
		_hp_fill.size.x = (_HP_W - 4.0) * clampf(float(cur) / float(mx), 0.0, 1.0)
	if _hp_label != null:
		_hp_label.text = "%d / %d" % [max(cur, 0), mx]
	# 열기(=일섬 자원) 스택
	var res := _slash_resource_frac()
	var lit := int(ceil(res * float(_HEAT_STACKS)))
	var over: bool = _player.has_method("is_overheated") and bool(_player.call("is_overheated"))
	for i in _heat_pips.size():
		if over:
			_heat_pips[i].color = _HEAT_OVER
		elif i < lit:
			_heat_pips[i].color = _HEAT_LOW.lerp(_HEAT_HIGH, float(i) / float(max(_HEAT_STACKS - 1, 1)))
		else:
			_heat_pips[i].color = _HEAT_OFF
	# 회피 스택 — 꽉 찬 칸=가득 / 충전 중 칸=evade_refill_frac 만큼 아래→위로 차오름 / 빈칸=0.
	var ev := 0
	if _player.has_method("get_evade_stacks"):
		ev = int(_player.call("get_evade_stacks"))
	var refill := 0.0
	if _player.has_method("evade_refill_frac"):
		refill = clampf(float(_player.call("evade_refill_frac")), 0.0, 1.0)
	for i in _dodge_fills.size():
		var h := 0.0
		if i < ev:
			h = 16.0
		elif i == ev:
			h = refill * 16.0
		_dodge_fills[i].size.y = h
		_dodge_fills[i].position.y = 46.0 + (16.0 - h)
	# 레벨 뱃지
	if _level_label != null and exp_system != null and is_instance_valid(exp_system) and "level" in exp_system:
		_level_label.text = str(exp_system.level)
	# 버프/디버프 스트립 폴링(스캐폴드) — 현재 PC 지속버프 없음이라 set_status 미호출.
	# PC 표식/버프가 생기면 여기서 _player meta 등을 읽어 set_status 로 채운다.


## 열기(모드2) 또는 일섬 게이지(모드1) — 같은 자원이라 한 스택으로 표현.
func _slash_resource_frac() -> float:
	if _player == null:
		return 0.0
	if _player.has_method("is_instant_slash_mode") and bool(_player.call("is_instant_slash_mode")):
		if _player.has_method("get_heat_frac"):
			return float(_player.call("get_heat_frac"))
		return 0.0
	if _player.has_method("slash_gauge_frac"):
		return float(_player.call("slash_gauge_frac"))
	return 0.0


func _style_label(l: Label, sz: int) -> void:
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_font_size_override("font_size", sz)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE


class _SheatheClock extends Control:
	var player: Node = null
	var ready_col: Color
	var cool_col: Color
	var pie_col: Color
	func _ready() -> void:
		set_process(true)
	func _process(_d: float) -> void:
		queue_redraw()
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 2.0
		var p := get_parent()
		if player == null and p != null:
			player = p.get("_player")
		var frac := 0.0
		var rdy := true
		if player != null and is_instance_valid(player):
			if player.has_method("get_sheathe_cooldown_frac"):
				frac = clampf(float(player.call("get_sheathe_cooldown_frac")), 0.0, 1.0)
			if player.has_method("is_sheathe_ready"):
				rdy = bool(player.call("is_sheathe_ready"))
		# 베이스 원(어두운 배경)
		draw_circle(c, r, Color(0.06, 0.06, 0.09, 0.92))
		# 납(納) 글리프
		var font := ThemeDB.fallback_font
		var fs := 22
		var glyph := "納"
		var tw := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var gcol := (Color(1, 1, 1) if rdy else Color(0.6, 0.6, 0.65))
		draw_string(font, c - tw * 0.5 + Vector2(0, fs * 0.36), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, gcol)
		# 시계방향 쿨다운 파이 — 12시(-90°) 기준 시계방향으로 frac 만큼 덮음.
		if frac > 0.001:
			var pts: PackedVector2Array = [c]
			var start := -PI * 0.5
			var steps := 48
			for i in steps + 1:
				var a := start + (TAU * frac) * (float(i) / float(steps))
				pts.append(c + Vector2(cos(a), sin(a)) * r)
			draw_colored_polygon(pts, pie_col)
		# 테두리 — 준비됨이면 금색 강조, 쿨 중이면 어둠.
		draw_arc(c, r, 0.0, TAU, 48, (ready_col if rdy else cool_col), (3.0 if rdy else 2.0), true)
