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

## Main/Testplay 가 주입 — 레벨 뱃지용(ExpSystem 노드, .level).
var exp_system: Node = null

var _player: Node = null
var _hp_fill: ColorRect
var _hp_label: Label
var _heat_pips: Array = []
var _heat_fills: Array = []
var _dodge_pips: Array = []
var _dodge_fills: Array = []
var _level_label: Label


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
		var fill := ColorRect.new()
		fill.color = _HEAT_OVER
		fill.position = Vector2(heat_x + i * 30.0, 62)
		fill.size = Vector2(26, 0)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(fill)
		_heat_fills.append(fill)

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
	var over: bool = _player.has_method("is_overheated") and bool(_player.call("is_overheated"))
	if over:
		var ofrac := 0.0
		if _player.has_method("get_overheat_frac"):
			ofrac = clampf(float(_player.call("get_overheat_frac")), 0.0, 1.0)
		var gray := ofrac * float(_HEAT_STACKS)
		for i in _heat_fills.size():
			_heat_pips[i].color = _HEAT_OFF
			var gh := 0.0
			if i < int(floor(gray)):
				gh = 16.0
			elif i == int(floor(gray)):
				gh = (gray - floor(gray)) * 16.0
			_heat_fills[i].color = _HEAT_OVER
			_heat_fills[i].size.y = gh
			_heat_fills[i].position.y = 46.0 + (16.0 - gh)
	else:
		var res := _slash_resource_frac()
		var lit := int(ceil(res * float(_HEAT_STACKS)))
		for i in _heat_pips.size():
			_heat_fills[i].size.y = 0.0
			if i < lit:
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
