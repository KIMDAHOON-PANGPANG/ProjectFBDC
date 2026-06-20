extends CanvasLayer

## PC death screen — shows run stats + NEW! badges over any peak the
## death just beat (yes, you can beat your best kill count by dying
## further into the chapter than you've ever survived a clear of).
##
## Wired by Main: when Player.died fires, Main pauses the tree, spawns
## this screen via `game_over_screen_scene`, calls `configure(result,
## best, beat)`. Retry button reloads the scene; Quit exits the app.
## Identical structure to ChapterClearScreen so future ArenaServices
## extraction can share a base class.

signal retry_pressed
signal quit_pressed
## 이어서 하기 — 진행(레벨/카드/스탯) 유지하고 같은 PC 부활. Main 이 받아 revive + 재개.
signal continue_pressed

@export var bg_color: Color = Color(0, 0, 0, 0.78)
@export var title_color: Color = Color(0.88, 0.22, 0.22, 1.0)

var _root: ColorRect
var _title: Label
var _stats_box: VBoxContainer
var _retry_btn: Button
var _quit_btn: Button
var _continue_btn: Button
var _result: Dictionary = {}
var _best: Dictionary = {}
var _beat: Dictionary = {}


func _ready() -> void:
	layer = 250  # Above HUD, level-up screen, everything.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	get_viewport().size_changed.connect(_layout)
	_layout()
	_refresh_stats()


## Called by Main right after `add_child` so the screen can render the
## actual run stats. Safe to call before `_ready` — the values are
## stashed and picked up on the first `_refresh_stats`.
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
	_title.text = "쓰러졌다."
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_color", title_color)
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_title.add_theme_constant_override("outline_size", 6)
	_title.add_theme_font_size_override("font_size", 56)
	add_child(_title)

	_stats_box = VBoxContainer.new()
	_stats_box.add_theme_constant_override("separation", 6)
	add_child(_stats_box)

	_continue_btn = _make_btn("이어서 하기", _on_continue_pressed)
	add_child(_continue_btn)
	_retry_btn = _make_btn("다시 도전", _on_retry_pressed)
	add_child(_retry_btn)
	_quit_btn = _make_btn("메뉴로", _on_quit_pressed)
	add_child(_quit_btn)


func _make_btn(label: String, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(200, 50)
	btn.add_theme_font_size_override("font_size", 22)
	btn.process_mode = Node.PROCESS_MODE_ALWAYS
	btn.pressed.connect(cb)
	return btn


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
	# 이어서 하기 | 다시 도전 | 메뉴로 — 3개 가로 중앙 정렬.
	var btn_w: float = 200.0
	var gap: float = 14.0
	var row_w: float = btn_w * 3.0 + gap * 2.0
	var left_x: float = (w - row_w) * 0.5
	var by: float = h * 0.72
	_continue_btn.position = Vector2(left_x, by)
	_retry_btn.position = Vector2(left_x + btn_w + gap, by)
	_quit_btn.position = Vector2(left_x + (btn_w + gap) * 2.0, by)


func _refresh_stats() -> void:
	if _stats_box == null:
		return
	for c in _stats_box.get_children():
		c.queue_free()
	var time := float(_result.get("time", 0.0))
	var kills := int(_result.get("kills", 0))
	var level := int(_result.get("level", 1))
	_stats_box.add_child(_stat_row("생존 시간", _format_time(time), false))
	_stats_box.add_child(_stat_row("처치 수", str(kills), bool(_beat.get("kills", false))))
	_stats_box.add_child(_stat_row("도달 레벨", "Lv %d" % level, bool(_beat.get("level", false))))
	var souls_val := int(_result.get("souls", 0))
	if souls_val > 0:
		_stats_box.add_child(_stat_row("적립 혼", "+%d" % souls_val, false))
	var gold_val := int(_result.get("gold", 0))
	if gold_val > 0:
		_stats_box.add_child(_stat_row("획득 골드", "+%d" % gold_val, false))
	# Best-record line below the stat rows — only show if there's at
	# least one previous attempt to compare against.
	if not _best.is_empty() and int(_best.get("best_kills", 0)) > 0:
		var best_label := Label.new()
		var bk := int(_best.get("best_kills", 0))
		var bl := int(_best.get("best_level", 1))
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


func _on_retry_pressed() -> void:
	retry_pressed.emit()
	var tree := get_tree()
	if tree == null:
		return
	tree.paused = false
	tree.reload_current_scene()


## 이어서 하기 — Main 이 PC 를 revive + 재개한다. 화면은 스스로 닫는다.
func _on_continue_pressed() -> void:
	continue_pressed.emit()
	queue_free()


func _on_quit_pressed() -> void:
	# M4 — "Quit" 라벨이 "메뉴로"로 바뀜. 실제 OutGame으로 라우팅.
	# 진짜 종료는 OutGame의 "종료" 버튼에서 처리.
	quit_pressed.emit()
	var tree := get_tree()
	if tree == null:
		return
	tree.paused = false
	tree.change_scene_to_file("res://scenes/main/OutGame.tscn")
