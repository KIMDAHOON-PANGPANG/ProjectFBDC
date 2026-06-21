extends CanvasLayer

## 해상도 / 전체화면 설정 패널 — CanvasLayer(layer=90, ALWAYS).
## SettingsManager autoload(/root/SettingsManager) 에 덕타이핑으로 접근.
## 스크립트가 _build 로 절차 생성 — .tscn 에 자식 노드 없음.

var _res_opt: OptionButton = null
var _fullscreen_cb: CheckBox = null


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false


func open() -> void:
	visible = true
	_sync_widgets()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := VBoxContainer.new()
	center.add_theme_constant_override("separation", 16)
	center.custom_minimum_size = Vector2(360, 0)
	center.anchor_left = 0.5
	center.anchor_top = 0.5
	center.anchor_right = 0.5
	center.anchor_bottom = 0.5
	center.offset_left = -180.0
	center.offset_right = 180.0
	center.offset_top = -140.0
	center.offset_bottom = 140.0
	add_child(center)

	var title := _title("설정")
	center.add_child(title)

	# 해상도 행
	var res_hb := HBoxContainer.new()
	res_hb.add_theme_constant_override("separation", 12)
	var res_lbl := _info("해상도")
	res_hb.add_child(res_lbl)
	_res_opt = OptionButton.new()
	_res_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sm = get_node_or_null("/root/SettingsManager")
	if sm != null:
		for i in sm.RES_LABELS.size():
			_res_opt.add_item(sm.RES_LABELS[i], i)
		_res_opt.item_selected.connect(func(idx): sm.set_resolution(idx))
	center.add_child(res_hb)
	res_hb.add_child(_res_opt)

	# 전체화면 행
	var fs_hb := HBoxContainer.new()
	fs_hb.add_theme_constant_override("separation", 12)
	fs_hb.add_child(_info("전체화면"))
	_fullscreen_cb = CheckBox.new()
	if sm != null:
		_fullscreen_cb.toggled.connect(func(on): sm.set_fullscreen(on))
	fs_hb.add_child(_fullscreen_cb)
	center.add_child(fs_hb)

	# 닫기 버튼
	center.add_child(_btn("닫기", func(): visible = false))


func _sync_widgets() -> void:
	var sm = get_node_or_null("/root/SettingsManager")
	if sm == null:
		return
	if _res_opt != null:
		_res_opt.select(sm.res_index)
	if _fullscreen_cb != null:
		_fullscreen_cb.set_pressed_no_signal(sm.fullscreen)


func _title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(1, 0.95, 0.6))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_font_size_override("font_size", 22)
	return l


func _info(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.85, 0.9, 1))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_font_size_override("font_size", 15)
	l.custom_minimum_size = Vector2(100, 0)
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
