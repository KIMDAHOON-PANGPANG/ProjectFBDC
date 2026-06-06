extends Control

## Card-unlock screen (M5) — list every locked card with its 혼 cost and
## an "해금" button. Initial cards are listed for completeness but
## flagged "기본 풀" and have no button. Once unlocked, a card joins
## UpgradeSystem.draw's available pool on the next level-up.
##
## Pattern mirrors MetaMenu — flat Control, procedural rows, refresh on
## every unlock. ScrollContainer wraps the rows so the 13-card list
## fits any window size without manual wrap.

const _MetaScript := preload("res://scripts/managers/MetaProgressionSystem.gd")
const _UpgradeScript := preload("res://scripts/managers/UpgradeSystem.gd")
const _OUTGAME_PATH := "res://scenes/main/OutGame.tscn"

var _souls_label: Label
var _rows: Array[Control] = []


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	_build()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.07, 0.08, 1.0)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var outer := VBoxContainer.new()
	outer.anchor_left = 0.5
	outer.anchor_right = 0.5
	outer.anchor_top = 0.0
	outer.anchor_bottom = 1.0
	outer.offset_left = -360.0
	outer.offset_right = 360.0
	outer.offset_top = 32.0
	outer.offset_bottom = -32.0
	outer.add_theme_constant_override("separation", 10)
	add_child(outer)

	var title := Label.new()
	title.text = "카드 해금 — 새 카드를 풀에 추가한다"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2, 1.0))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	title.add_theme_constant_override("outline_size", 4)
	title.add_theme_font_size_override("font_size", 26)
	outer.add_child(title)

	_souls_label = Label.new()
	_souls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_souls_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	_souls_label.add_theme_font_size_override("font_size", 18)
	outer.add_child(_souls_label)

	# Scrollable card list — 13 rows comfortably fits 720p once you
	# scroll. Mouse-wheel works out of the box.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)

	for card in _UpgradeScript.CARDS:
		var row := _build_row(card)
		_rows.append(row)
		list.add_child(row)

	outer.add_child(_make_back_button())

	_refresh()


func _build_row(card: Dictionary) -> Control:
	var row := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.13, 0.16, 1.0)
	style.border_color = Color(0.3, 0.3, 0.4, 1.0)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	row.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	row.add_child(hbox)

	var info_box := VBoxContainer.new()
	info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_box)

	var name_label := Label.new()
	name_label.text = String(card.get("name", "?"))
	name_label.add_theme_color_override("font_color", Color(1, 1, 1))
	name_label.add_theme_font_size_override("font_size", 17)
	info_box.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = String(card.get("desc", ""))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	desc_label.add_theme_font_size_override("font_size", 13)
	info_box.add_child(desc_label)

	var status_label := Label.new()
	status_label.name = "StatusLabel"
	status_label.add_theme_font_size_override("font_size", 12)
	info_box.add_child(status_label)

	var btn := Button.new()
	btn.name = "UnlockButton"
	btn.custom_minimum_size = Vector2(120, 50)
	btn.add_theme_font_size_override("font_size", 15)
	btn.pressed.connect(_on_unlock_pressed.bind(String(card.get("id", ""))))
	hbox.add_child(btn)

	row.set_meta("card_id", String(card.get("id", "")))
	return row


func _make_back_button() -> Button:
	var btn := Button.new()
	btn.text = "← 뒤로"
	btn.custom_minimum_size = Vector2(120, 44)
	btn.add_theme_font_size_override("font_size", 16)
	btn.pressed.connect(_on_back_pressed)
	return btn


func _refresh() -> void:
	_souls_label.text = "혼: %d" % _MetaScript.souls()
	for row in _rows:
		var id: String = row.get_meta("card_id", "")
		var card: Variant = _UpgradeScript.card_by_id(id)
		if card == null:
			continue
		var initial: bool = bool(card.get("initial", false))
		var cost: int = int(card.get("unlock_cost", 0))
		var unlocked: bool = initial or _MetaScript.is_card_unlocked(id)
		var status := row.find_child("StatusLabel", true, false) as Label
		var btn := row.find_child("UnlockButton", true, false) as Button
		if initial:
			if status != null:
				status.text = "기본 풀 (시작부터 사용 가능)"
				status.add_theme_color_override("font_color", Color(0.55, 0.85, 0.55))
			if btn != null:
				btn.text = "기본"
				btn.disabled = true
		elif unlocked:
			if status != null:
				status.text = "해금됨"
				status.add_theme_color_override("font_color", Color(0.55, 0.85, 0.55))
			if btn != null:
				btn.text = "해금됨"
				btn.disabled = true
		else:
			if status != null:
				status.text = "잠김 · 비용 %d 혼" % cost
				status.add_theme_color_override("font_color", Color(0.85, 0.65, 0.55))
			if btn != null:
				if _MetaScript.souls() >= cost:
					btn.text = "해금"
					btn.disabled = false
				else:
					btn.text = "혼 부족"
					btn.disabled = true


func _on_unlock_pressed(card_id: String) -> void:
	var card: Variant = _UpgradeScript.card_by_id(card_id)
	if card == null:
		return
	var cost: int = int(card.get("unlock_cost", 0))
	if _MetaScript.unlock_card(card_id, cost):
		_refresh()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(_OUTGAME_PATH)
