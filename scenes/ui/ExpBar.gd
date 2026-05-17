class_name ExpBar
extends CanvasLayer

## Top-of-screen full-width EXP bar.
##   - Thick horizontal ProgressBar pinned to top edge, stretches viewport width.
##   - Center label shows the chapter timer as MM:SS.
##   - Subscribes to ExpSystem.exp_changed to update fill.
##
## All public hooks (`set_exp_source`, `set_elapsed`) are pull-style so the
## owner (Main) decides when to wire things up.

@export var bar_height: int = 22
@export var bg_color: Color = Color(0.08, 0.08, 0.1, 0.85)
@export var fill_color: Color = Color(0.35, 0.85, 1.0, 1.0)
@export var border_color: Color = Color(0, 0, 0, 0.9)

var _bg: ColorRect
var _fill: ColorRect
var _timer_label: Label
# Plain Node — caller may pass an ExpSystem-like duck-typed source.
var _exp_source: Node
var _elapsed: float = 0.0
var _viewport_w: float = 0.0
var _progress_cached: float = 0.0

func _ready() -> void:
	layer = 100  # Draw above HUD.
	_build()
	get_viewport().size_changed.connect(_layout)
	_layout()

func _build() -> void:
	_bg = ColorRect.new()
	_bg.color = bg_color
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	_fill = ColorRect.new()
	_fill.color = fill_color
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fill)

	_timer_label = Label.new()
	_timer_label.text = "00:00"
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_timer_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_timer_label.add_theme_color_override("font_outline_color", border_color)
	_timer_label.add_theme_constant_override("outline_size", 4)
	_timer_label.add_theme_font_size_override("font_size", 16)
	_timer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_timer_label)

func _layout() -> void:
	var vp_size: Vector2i = get_viewport().get_visible_rect().size
	_viewport_w = float(vp_size.x)
	# BG spans entire top edge.
	_bg.position = Vector2(0, 0)
	_bg.size = Vector2(_viewport_w, float(bar_height))
	# Fill width updates in _refresh_fill.
	_fill.position = Vector2(0, 0)
	_fill.size = Vector2(_viewport_w * _progress_cached, float(bar_height))
	# Timer label centered horizontally + vertically over the bar.
	_timer_label.position = Vector2(0, 0)
	_timer_label.size = Vector2(_viewport_w, float(bar_height))

func _process(delta: float) -> void:
	# Chapter timer only advances while not paused. _process is gated by the
	# CanvasLayer's process_mode; we want this UI itself to keep updating
	# even during pause for cosmetic reasons, but the elapsed time should
	# freeze. The owner can opt out by not feeding deltas in paused state.
	var tree := get_tree()
	if tree != null and not tree.paused:
		_elapsed += delta
	_update_timer_text()

func _update_timer_text() -> void:
	var total: int = int(_elapsed)
	var mm: int = total / 60
	var ss: int = total % 60
	_timer_label.text = "%02d:%02d" % [mm, ss]

func set_exp_source(src: Node) -> void:
	_exp_source = src
	if _exp_source != null and _exp_source.has_signal("exp_changed"):
		_exp_source.exp_changed.connect(_on_exp_changed)
		if _exp_source.has_method("progress"):
			_refresh_fill(_exp_source.call("progress"))

func _on_exp_changed(_cur: int, _thr: int) -> void:
	if _exp_source == null or not _exp_source.has_method("progress"):
		return
	_refresh_fill(_exp_source.call("progress"))

func _refresh_fill(p: float) -> void:
	_progress_cached = clamp(p, 0.0, 1.0)
	_fill.size = Vector2(_viewport_w * _progress_cached, float(bar_height))

func elapsed_seconds() -> float:
	return _elapsed
