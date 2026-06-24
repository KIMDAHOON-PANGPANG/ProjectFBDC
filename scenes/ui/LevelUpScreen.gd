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

@export var overlay_color: Color = Color(0, 0, 0, 0.55)
@export var card_size: Vector2 = Vector2(220, 280)
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
## Each entry: { id, name, desc }.
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
	var name_str := String(card_dict.get("name", "?"))
	var rarity_label := String(card_dict.get("rarity_label", ""))
	var yokai := String(card_dict.get("yokai", ""))
	var desc_str := String(card_dict.get("desc", ""))
	btn.text = "%s\n[%s · %s]\n\n%s" % [name_str, rarity_label, yokai, desc_str]
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	btn.add_theme_color_override("font_color_hover", Color(1, 1, 1, 1))
	btn.add_theme_font_size_override("font_size", 16)
	var style := StyleBoxFlat.new()
	style.bg_color = rare_card_bg if is_rare else card_bg
	if is_rare:
		style.border_color = rare_card_border
		style.border_width_left = 2
		style.border_width_right = 2
		style.border_width_top = 2
		style.border_width_bottom = 2
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	btn.add_theme_stylebox_override("normal", style)
	var hover_style := style.duplicate() as StyleBoxFlat
	hover_style.bg_color = rare_card_hover if is_rare else card_hover
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.add_theme_stylebox_override("pressed", hover_style)
	btn.pressed.connect(_on_card_pressed.bind(index))
	return btn

func _layout() -> void:
	var vp: Vector2i = get_viewport().get_visible_rect().size
	var w := float(vp.x)
	var h := float(vp.y)
	_overlay.position = Vector2.ZERO
	_overlay.size = Vector2(w, h)
	# Center 3 cards horizontally.
	var n := _cards_root.get_child_count()
	var total_w: float = n * card_size.x + (n - 1) * card_gap if n > 0 else 0.0
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
