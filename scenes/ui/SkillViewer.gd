extends CanvasLayer

## 현재 런 카드 목록 반투명 오버레이. Tab 토글 · 정지 없음.
## Main/Testplay 가 _on_upgrade_card_selected 마다 refresh(cards) 호출.
## layer=70 < PauseOverlay 80 — ESC 메뉴가 위에 그려짐.

var _panel: PanelContainer
var _list: VBoxContainer


func _ready() -> void:
	layer = 70
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		visible = not visible
		get_viewport().set_input_as_handled()


func _build() -> void:
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.12, 0.82)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", sb)
	# 우상단 고정 — 앵커 대신 position 지정(CanvasLayer 자식은 Control 좌표 사용).
	_panel.position = Vector2(0, 60)
	_panel.custom_minimum_size = Vector2(220, 0)
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	# CanvasLayer 는 Control 앵커를 무시하므로, 뷰포트 크기에 맞춰 x 를 _ready 에서 정렬.
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = "카드 빌드 [TAB]"
	title.add_theme_color_override("font_color", Color(1.0, 0.95, 0.55))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	title.add_theme_constant_override("outline_size", 4)
	title.add_theme_font_size_override("font_size", 15)
	vbox.add_child(title)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	vbox.add_child(_list)


func _notification(what: int) -> void:
	if what == NOTIFICATION_READY:
		# 뷰포트 너비에 맞춰 패널을 우상단에 배치.
		var vw: float = get_viewport().get_visible_rect().size.x
		if _panel != null:
			_panel.position.x = vw - _panel.custom_minimum_size.x - 20.0


## 카드 목록 갱신 — cards: Array of {id, name}. 이름 기준 집계 후 재빌드.
func refresh(cards: Array) -> void:
	if _list == null:
		return
	for child in _list.get_children():
		child.queue_free()
	if cards.is_empty():
		var empty := Label.new()
		empty.text = "(없음)"
		empty.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		empty.add_theme_font_size_override("font_size", 13)
		_list.add_child(empty)
		return
	# 이름 기준 집계.
	var counts: Dictionary = {}
	for card in cards:
		var nm: String = String(card.get("name", card.get("id", "?")))
		counts[nm] = int(counts.get(nm, 0)) + 1
	for nm in counts:
		var row := Label.new()
		var cnt: int = int(counts[nm])
		row.text = "%s%s" % [nm, (" ×%d" % cnt if cnt > 1 else "")]
		row.add_theme_color_override("font_color", Color(0.9, 0.92, 1.0))
		row.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		row.add_theme_constant_override("outline_size", 3)
		row.add_theme_font_size_override("font_size", 13)
		_list.add_child(row)
