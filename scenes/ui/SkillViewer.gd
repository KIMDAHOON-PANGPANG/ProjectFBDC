extends CanvasLayer

## 현재 런 카드 목록 반투명 오버레이. Tab 토글 · 정지 없음.
## Main/Testplay 가 _on_upgrade_card_selected 마다 refresh(cards) 호출.
## layer=70 < PauseOverlay 80 — ESC 메뉴가 위에 그려짐.

const _BoonSystem := preload("res://scripts/managers/BoonSystem.gd")

const TYPE_ORDER: Array = ["질주", "공격", "타격", "소환", "권능", "패시브"]
const TYPE_ICONS := {
	"질주": "»",
	"공격": "⚔",
	"타격": "✦",
	"소환": "◈",
	"패시브": "●",
	"권능": "◎",
}

var _panel: PanelContainer
var _list: VBoxContainer
var _tooltip: PanelContainer
var _tooltip_label: Label


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
	_panel.custom_minimum_size = Vector2(300, 0)
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

	_tooltip = PanelContainer.new()
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(0.05, 0.05, 0.08, 0.92)
	tsb.set_corner_radius_all(6)
	tsb.set_content_margin_all(8)
	_tooltip.add_theme_stylebox_override("panel", tsb)
	_tooltip.process_mode = Node.PROCESS_MODE_ALWAYS
	_tooltip.visible = false
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_label = Label.new()
	_tooltip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tooltip_label.custom_minimum_size = Vector2(0, 0)
	_tooltip_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_tooltip_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_tooltip_label.add_theme_constant_override("outline_size", 3)
	_tooltip_label.add_theme_font_size_override("font_size", 13)
	_tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.add_child(_tooltip_label)
	add_child(_tooltip)


func _notification(what: int) -> void:
	if what == NOTIFICATION_READY:
		# 뷰포트 너비에 맞춰 패널을 우상단에 배치.
		var vw: float = get_viewport().get_visible_rect().size.x
		if _panel != null:
			_panel.position.x = vw - _panel.custom_minimum_size.x - 20.0


## 카드 목록 갱신 — cards: Array of {id, name, skill_type, desc, yokai, rarity}. 타입 행 레이아웃으로 재빌드.
func refresh(cards: Array) -> void:
	if _list == null:
		return
	for child in _list.get_children():
		child.queue_free()

	# 타입별 집계.
	var by_type: Dictionary = {}
	for card in cards:
		var st: String = String(card.get("skill_type", ""))
		if not st in TYPE_ORDER:
			st = "패시브"
		if not by_type.has(st):
			by_type[st] = []
		by_type[st].append(card)

	# TYPE_ORDER 순서로 각 타입 1행 생성.
	for t in TYPE_ORDER:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_list.add_child(row)

		# 좌측 타입 뱃지.
		var badge := Label.new()
		badge.text = String(TYPE_ICONS.get(t, "")) + " " + t
		badge.custom_minimum_size = Vector2(64, 0)
		badge.add_theme_font_size_override("font_size", 13)
		badge.add_theme_color_override("font_color", Color(0.85, 0.88, 1.0))
		badge.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		badge.add_theme_constant_override("outline_size", 3)
		row.add_child(badge)

		# 우측 소켓 컨테이너.
		var sockets := HBoxContainer.new()
		sockets.add_theme_constant_override("separation", 4)
		row.add_child(sockets)

		var list_for_type: Array = by_type.get(t, [])

		if list_for_type.is_empty():
			# 빈 타입 — 흐린 빈 소켓 1개.
			var empty_sock := _make_socket(Color(0.25, 0.25, 0.3, 0.5), "", "")
			sockets.add_child(empty_sock)
		else:
			# 같은 id 기준 중복 집계(등장 순서 보존).
			var counts: Dictionary = {}
			var order: Array = []
			for card in list_for_type:
				var cid: String = String(card.get("id", ""))
				if not counts.has(cid):
					counts[cid] = {"card": card, "n": 0}
					order.append(cid)
				counts[cid]["n"] += 1

			for cid in order:
				var c: Dictionary = counts[cid]["card"]
				var n: int = int(counts[cid]["n"])
				var kc: Color = _BoonSystem.yokai_color(String(c.get("yokai", "")))
				var sym: String = String(TYPE_ICONS.get(t, ""))
				var sock_sym: String = sym if n <= 1 else ("%s×%d" % [sym, n])
				var tip: String = String(c.get("name", "")) + " — " + String(c.get("desc", ""))
				var sock := _make_socket(kc, sock_sym, tip)
				sockets.add_child(sock)


func _make_socket(bg: Color, sym: String, tip: String) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(2)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(26, 26)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	if tip != "":
		p.mouse_entered.connect(_on_socket_hover.bind(tip))
		p.mouse_exited.connect(_on_socket_unhover)

	var l := Label.new()
	l.text = sym
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)

	return p


func _on_socket_hover(tip: String) -> void:
	if _tooltip == null or _tooltip_label == null:
		return
	_tooltip_label.custom_minimum_size.x = 304.0
	_tooltip_label.text = tip
	_tooltip.visible = true
	_update_tooltip_pos()


func _on_socket_unhover() -> void:
	if _tooltip != null:
		_tooltip.visible = false


func _update_tooltip_pos() -> void:
	if _tooltip == null:
		return
	var mp: Vector2 = get_viewport().get_mouse_position()
	var pos: Vector2 = mp + Vector2(16, 16)
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var ts: Vector2 = _tooltip.size
	pos.x = min(pos.x, vp.x - ts.x - 8.0)
	pos.y = min(pos.y, vp.y - ts.y - 8.0)
	pos.x = max(pos.x, 8.0)
	pos.y = max(pos.y, 8.0)
	_tooltip.position = pos


func _process(_delta: float) -> void:
	if _tooltip != null and _tooltip.visible:
		_update_tooltip_pos()
