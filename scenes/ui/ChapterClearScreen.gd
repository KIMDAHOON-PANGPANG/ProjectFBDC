extends CanvasLayer

## Chapter-clear celebration screen — shows run stats with NEW! badges
## over any best-record beaten this run. Next button currently re-loads
## the scene (chapter 2 routing arrives with M2).
##
## Main wires this up by:
##   1. Instantiate via `chapter_clear_screen_scene`.
##   2. `configure(result, best, beat)` so the stat rows can NEW! the
##      fields that this run improved.
##   3. `add_child` — _ready picks up the configured values.

signal next_pressed

@export var bg_color: Color = Color(0, 0, 0, 0.7)
@export var title_color: Color = Color(1.0, 0.85, 0.2, 1.0)

var _root: ColorRect
var _title: Label
var _stats_box: VBoxContainer
var _next_btn: Button
var _menu_btn: Button
var _result: Dictionary = {}
var _best: Dictionary = {}
var _beat: Dictionary = {}


func _ready() -> void:
	layer = 250  # Above everything.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	get_viewport().size_changed.connect(_layout)
	_layout()
	_refresh_stats()


## Called by Main right after instantiating so the screen renders the
## actual stats + NEW! badges. Safe to call before `_ready`.
func configure(result: Dictionary, best: Dictionary = {}, beat: Dictionary = {}) -> void:
	_result = result
	_best = best
	_beat = beat
	if is_inside_tree():
		_refresh_stats()


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

	_stats_box = VBoxContainer.new()
	_stats_box.add_theme_constant_override("separation", 6)
	add_child(_stats_box)

	_next_btn = Button.new()
	_next_btn.text = "Next  →"
	_next_btn.custom_minimum_size = Vector2(220, 60)
	_next_btn.add_theme_font_size_override("font_size", 24)
	_next_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	_next_btn.pressed.connect(_on_next_pressed)
	add_child(_next_btn)

	_menu_btn = Button.new()
	_menu_btn.text = "메뉴로"
	_menu_btn.custom_minimum_size = Vector2(160, 44)
	_menu_btn.add_theme_font_size_override("font_size", 18)
	_menu_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	_menu_btn.pressed.connect(_on_menu_pressed)
	add_child(_menu_btn)


func _layout() -> void:
	var vp: Vector2i = get_viewport().get_visible_rect().size
	var w := float(vp.x)
	var h := float(vp.y)
	_root.position = Vector2.ZERO
	_root.size = Vector2(w, h)
	_title.position = Vector2(0, h * 0.22)
	_title.size = Vector2(w, 80)
	_stats_box.position = Vector2((w - 360.0) * 0.5, h * 0.4)
	_stats_box.size = Vector2(360.0, 0.0)
	_next_btn.position = Vector2((w - 220.0) * 0.5, h * 0.7)
	_menu_btn.position = Vector2((w - 160.0) * 0.5, h * 0.7 + 70.0)


func _refresh_stats() -> void:
	if _stats_box == null:
		return
	for c in _stats_box.get_children():
		c.queue_free()
	var time := float(_result.get("time", 0.0))
	var kills := int(_result.get("kills", 0))
	var level := int(_result.get("level", 1))
	_stats_box.add_child(_stat_row("클리어 시간", _format_time(time), bool(_beat.get("time", false))))
	_stats_box.add_child(_stat_row("처치 수", str(kills), bool(_beat.get("kills", false))))
	_stats_box.add_child(_stat_row("도달 레벨", "Lv %d" % level, bool(_beat.get("level", false))))
	# M4 — souls earned this run (always shown, no NEW! since "more
	# souls" is the whole point of every run).
	var souls_val := int(_result.get("souls", 0))
	if souls_val > 0:
		_stats_box.add_child(_stat_row("적립 혼", "+%d" % souls_val, false))
	# Basic gold currency earned this run (kills + time).
	var gold_val := int(_result.get("gold", 0))
	if gold_val > 0:
		_stats_box.add_child(_stat_row("획득 골드", "+%d" % gold_val, false))
	# Show previous best as a small line below the stat rows.
	if not _best.is_empty():
		var best_label := Label.new()
		var bt := float(_best.get("best_time", -1.0))
		var bk := int(_best.get("best_kills", 0))
		var bl := int(_best.get("best_level", 1))
		if bt > 0.0:
			best_label.text = "  best: %s · %d kills · Lv %d" % [_format_time(bt), bk, bl]
		else:
			best_label.text = "  best: %d kills · Lv %d" % [bk, bl]
		best_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
		best_label.add_theme_font_size_override("font_size", 13)
		_stats_box.add_child(best_label)


func _stat_row(label: String, value: String, beat: bool) -> Control:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	var l := Label.new()
	l.text = label
	l.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	l.add_theme_font_size_override("font_size", 18)
	l.custom_minimum_size = Vector2(140, 0)
	hbox.add_child(l)
	var v := Label.new()
	v.text = value
	v.add_theme_color_override("font_color", Color(1, 1, 1))
	v.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	v.add_theme_constant_override("outline_size", 3)
	v.add_theme_font_size_override("font_size", 20)
	hbox.add_child(v)
	if beat:
		var b := Label.new()
		b.text = "  NEW!"
		b.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		b.add_theme_color_override("font_outline_color", Color(0.4, 0.2, 0, 1))
		b.add_theme_constant_override("outline_size", 3)
		b.add_theme_font_size_override("font_size", 16)
		hbox.add_child(b)
	return hbox


func _format_time(t: float) -> String:
	var total := int(t)
	var sec := total % 60
	var minutes := total / 60
	return "%d:%02d" % [minutes, sec]


func _on_next_pressed() -> void:
	# Main listens for `next_pressed` to decide between advancing to the
	# next chapter or reloading (final chapter case). We just unpause and
	# self-free; routing decisions live in Main._on_chapter_next_pressed.
	next_pressed.emit()
	var tree := get_tree()
	if tree != null:
		tree.paused = false
	queue_free()


func _on_menu_pressed() -> void:
	# Back to OutGame — souls already credited by Main when we were
	# instantiated, so the player sees the new balance immediately.
	var tree := get_tree()
	if tree == null:
		return
	tree.paused = false
	tree.change_scene_to_file("res://scenes/main/OutGame.tscn")
