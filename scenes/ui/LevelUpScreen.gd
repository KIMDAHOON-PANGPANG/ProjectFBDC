extends CanvasLayer

## Vampire-Survivors-style level-up screen.
##   - Dark translucent overlay over the world
##   - 3 cards centered horizontally
##   - Click a card → emit `card_selected(id)` and queue_free the overlay
##
## The owner (Main) is expected to pause the SceneTree before showing this
## and unpause after the signal. We set our own `process_mode = ALWAYS`
## so the click handlers keep working while the rest of the game is paused.

signal card_selected(card_id: String)

const _BoonSystem := preload("res://scripts/managers/BoonSystem.gd")

const TYPE_ICONS := {
	"질주": "»",
	"공격": "⚔",
	"타격": "✦",
	"소환": "◈",
	"패시브": "●",
	"권능": "◎",
}

const TYPE_TOOLTIPS := {
	"질주": "질주 — 회피(대시)에 얹는 효과",
	"공격": "공격 — 기본 공격(LB) 강화",
	"타격": "타격 — LB를 N회 적중해야 발동",
	"소환": "소환 — 처치 시 확률로 PC를 돕는 AI 소환",
	"패시브": "패시브 — 상시 효과",
	"권능": "권능 — 오라(주변 범위 지속)",
}

@export var overlay_color: Color = Color(0, 0, 0, 0.55)
@export var card_size: Vector2 = Vector2(240, 300)
@export var card_gap: float = 24.0
@export var card_bg: Color = Color(0.18, 0.18, 0.22, 1.0)
@export var card_hover: Color = Color(0.28, 0.32, 0.42, 1.0)
@export var rare_card_bg: Color = Color(0.25, 0.12, 0.38, 1.0)
@export var rare_card_hover: Color = Color(0.38, 0.18, 0.56, 1.0)
@export var rare_card_border: Color = Color(0.78, 0.45, 1.0, 1.0)

var _overlay: ColorRect
var _cards_root: Control
var _cards_data: Array = []

func _ready() -> void:
	layer = 200  # Above ExpBar.
	process_mode = Node.PROCESS_MODE_ALWAYS  # Keep working while tree is paused.
	_build_overlay()
	get_viewport().size_changed.connect(_layout)

func _build_overlay() -> void:
	_overlay = ColorRect.new()
	_overlay.color = overlay_color
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)
	_cards_root = Control.new()
	_cards_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cards_root)

## Owner calls this after instantiating, with the 3 cards to display.
## Each entry: { id, name, desc, yokai, skill_type, rarity, rarity_label }.
func show_cards(cards: Array) -> void:
	_cards_data = cards
	# Clear any previous cards (defensive — usually we're fresh).
	for c in _cards_root.get_children():
		c.queue_free()
	for i in range(cards.size()):
		var card_dict = cards[i]
		var btn := _build_card_button(card_dict, i)
		_cards_root.add_child(btn)
	_layout()

func _build_card_button(card_dict: Dictionary, index: int) -> Button:
	var btn := Button.new()
	var rar := String(card_dict.get("rarity", ""))
	var is_rare := rar in ["uniq", "legend", "master"]
	btn.custom_minimum_size = card_size
	btn.size = card_size
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.process_mode = Node.PROCESS_MODE_ALWAYS
	btn.text = ""
	btn.clip_contents = true

	var name_str := String(card_dict.get("name", "?"))
	var rarity_label := String(card_dict.get("rarity_label", ""))
	var yokai := String(card_dict.get("yokai", ""))
	var desc_str := String(card_dict.get("desc", ""))
	var sk := String(card_dict.get("skill_type", ""))

	var key_col: Color = _BoonSystem.yokai_color(yokai)

	# border width by rarity (등급=굵기, 색과 분리)
	var border_w: int = 2
	if rar == "master" or rar == "legend":
		border_w = 4
	elif rar == "uniq":
		border_w = 3

	var style := StyleBoxFlat.new()
	style.bg_color = rare_card_bg if is_rare else card_bg
	style.border_color = key_col
	style.border_width_left = border_w
	style.border_width_right = border_w
	style.border_width_top = border_w
	style.border_width_bottom = border_w
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	btn.add_theme_stylebox_override("normal", style)

	var hover_style := style.duplicate() as StyleBoxFlat
	hover_style.bg_color = rare_card_hover if is_rare else card_hover
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.add_theme_stylebox_override("pressed", hover_style)

	# 카드명 Label (귀신 키컬러)
	var name_lbl := Label.new()
	name_lbl.text = name_str
	name_lbl.add_theme_color_override("font_color", key_col)
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.position = Vector2(8, 10)
	name_lbl.size = Vector2(card_size.x - 16, 30)
	btn.add_child(name_lbl)

	# 등급 뱃지 Label (회백색 — 귀신색과 분리)
	var rar_lbl := Label.new()
	rar_lbl.text = rarity_label
	rar_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	rar_lbl.add_theme_font_size_override("font_size", 12)
	rar_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rar_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rar_lbl.position = Vector2(8, 42)
	rar_lbl.size = Vector2(card_size.x - 16, 18)
	btn.add_child(rar_lbl)

	# 설명 Label (autowrap 핵심, 하단 타입칸 44px 공간 확보)
	var desc_lbl := Label.new()
	desc_lbl.text = desc_str
	desc_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	desc_lbl.add_theme_font_size_override("font_size", 14)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desc_lbl.position = Vector2(12, 72)
	desc_lbl.size = Vector2(card_size.x - 24, card_size.y - 72 - 44)
	btn.add_child(desc_lbl)

	# 타입 칸/아이콘+타입명 + 툴팁 (우하단)
	var box_text: String = sk
	if TYPE_ICONS.has(sk):
		box_text = String(TYPE_ICONS[sk]) + " " + sk
	var type_box := Panel.new()
	type_box.custom_minimum_size = Vector2(78, 26)
	type_box.size = Vector2(78, 26)
	type_box.position = Vector2(card_size.x - (78 + 8), card_size.y - 34)
	type_box.mouse_filter = Control.MOUSE_FILTER_STOP
	type_box.tooltip_text = TYPE_TOOLTIPS.get(sk, sk)

	var icon_lbl := Label.new()
	icon_lbl.text = box_text
	icon_lbl.add_theme_font_size_override("font_size", 12)
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_lbl.position = Vector2.ZERO
	icon_lbl.size = Vector2(78, 26)
	type_box.add_child(icon_lbl)
	btn.add_child(type_box)

	btn.pressed.connect(_on_card_pressed.bind(index))
	return btn

func _layout() -> void:
	var vp: Vector2i = get_viewport().get_visible_rect().size
	var w := float(vp.x)
	var h := float(vp.y)
	_overlay.position = Vector2.ZERO
	_overlay.size = Vector2(w, h)
	# Center cards horizontally.
	var n := _cards_root.get_child_count()
	if n <= 0:
		return
	var total_w: float = n * card_size.x + (n - 1) * card_gap
	var start_x: float = (w - total_w) * 0.5
	var y: float = (h - card_size.y) * 0.5
	for i in range(n):
		var c := _cards_root.get_child(i) as Control
		c.position = Vector2(start_x + i * (card_size.x + card_gap), y)

func _on_card_pressed(index: int) -> void:
	if index < 0 or index >= _cards_data.size():
		return
	var id: String = _cards_data[index].get("id", "")
	card_selected.emit(id)
	queue_free()
