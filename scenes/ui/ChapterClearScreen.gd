extends CanvasLayer

## Chapter-clear celebration screen — minimal placeholder for the out-of-game
## flow. Shows "Chapter X Cleared!" with a "Next" button that re-loads the
## current scene (since there is no chapter 2 yet).

@export var bg_color: Color = Color(0, 0, 0, 0.7)
@export var title_color: Color = Color(1.0, 0.85, 0.2, 1.0)

var _root: ColorRect
var _title: Label
var _next_btn: Button

func _ready() -> void:
	layer = 250  # Above everything.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	get_viewport().size_changed.connect(_layout)
	_layout()

func _build() -> void:
	_root = ColorRect.new()
	_root.color = bg_color
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	_title = Label.new()
	_title.text = "Chapter 1 Cleared!"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_color", title_color)
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_title.add_theme_constant_override("outline_size", 6)
	_title.add_theme_font_size_override("font_size", 56)
	add_child(_title)

	_next_btn = Button.new()
	_next_btn.text = "Next  →"
	_next_btn.custom_minimum_size = Vector2(220, 60)
	_next_btn.add_theme_font_size_override("font_size", 24)
	_next_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	_next_btn.pressed.connect(_on_next_pressed)
	add_child(_next_btn)

func _layout() -> void:
	var vp: Vector2i = get_viewport().get_visible_rect().size
	var w := float(vp.x)
	var h := float(vp.y)
	_root.position = Vector2.ZERO
	_root.size = Vector2(w, h)
	_title.position = Vector2(0, h * 0.35)
	_title.size = Vector2(w, 80)
	_next_btn.position = Vector2((w - 220.0) * 0.5, h * 0.55)

func _on_next_pressed() -> void:
	# Placeholder — no chapter 2 yet. Just restart Chapter 1.
	var tree := get_tree()
	if tree == null:
		return
	tree.paused = false
	tree.reload_current_scene()
