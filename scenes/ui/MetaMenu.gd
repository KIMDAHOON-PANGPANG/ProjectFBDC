extends Control

## Meta upgrade panel — 혼 잔액 + 7종 패시브 강화 카드. Each row shows
## the passive name, description, current level / max, next-level cost,
## and an "강화" button. Clicking spends 혼 and bumps the level.
##
## Wired by OutGame: `change_scene_to_file("res://scenes/ui/MetaMenu.tscn")`.
## "뒤로" returns to OutGame.

const _MetaScript := preload("res://scripts/managers/MetaProgressionSystem.gd")
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

	var v := VBoxContainer.new()
	v.anchor_left = 0.5
	v.anchor_right = 0.5
	v.anchor_top = 0.0
	v.anchor_bottom = 1.0
	v.offset_left = -340.0
	v.offset_right = 340.0
	v.offset_top = 40.0
	v.offset_bottom = -40.0
	v.add_theme_constant_override("separation", 12)
	add_child(v)

	var title := Label.new()
	title.text = "영구강화 — 혼으로 시작 능력을 키운다"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2, 1.0))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	title.add_theme_constant_override("outline_size", 4)
	title.add_theme_font_size_override("font_size", 28)
	v.add_child(title)

	_souls_label = Label.new()
	_souls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_souls_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	_souls_label.add_theme_font_size_override("font_size", 20)
	v.add_child(_souls_label)

	# Build a row per passive.
	for passive in _MetaScript.all_passives():
		var row := _build_row(passive)
		_rows.append(row)
		v.add_child(row)

	v.add_child(_make_back_button())

	_refresh()


func _build_row(passive: MetaPassive) -> Control:
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
	name_label.text = passive.display_name
	name_label.add_theme_color_override("font_color", Color(1, 1, 1))
	name_label.add_theme_font_size_override("font_size", 18)
	info_box.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = passive.description
	desc_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	desc_label.add_theme_font_size_override("font_size", 13)
	info_box.add_child(desc_label)

	var stats_label := Label.new()
	stats_label.name = "StatsLabel"
	stats_label.add_theme_color_override("font_color", Color(0.85, 0.8, 0.6))
	stats_label.add_theme_font_size_override("font_size", 13)
	info_box.add_child(stats_label)

	var btn := Button.new()
	btn.name = "UpgradeButton"
	btn.text = "강화"
	btn.custom_minimum_size = Vector2(110, 50)
	btn.add_theme_font_size_override("font_size", 16)
	btn.pressed.connect(_on_upgrade_pressed.bind(passive.id))
	hbox.add_child(btn)

	row.set_meta("passive_id", passive.id)
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
		var id: String = row.get_meta("passive_id", "")
		var passive := _MetaScript.passive_by_id(id)
		if passive == null:
			continue
		var lvl := _MetaScript.passive_level(id)
		var stats := row.find_child("StatsLabel", true, false) as Label
		var btn := row.find_child("UpgradeButton", true, false) as Button
		if stats != null:
			if lvl >= passive.max_level:
				stats.text = "MAX (%d / %d)" % [lvl, passive.max_level]
			else:
				stats.text = "Lv %d / %d  ·  다음 %d 혼" % [lvl, passive.max_level, passive.cost_at(lvl)]
		if btn != null:
			if lvl >= passive.max_level:
				btn.text = "MAX"
				btn.disabled = true
			elif not _MetaScript.can_upgrade(id):
				btn.text = "혼 부족"
				btn.disabled = true
			else:
				btn.text = "강화"
				btn.disabled = false


func _on_upgrade_pressed(passive_id: String) -> void:
	if _MetaScript.upgrade(passive_id):
		_refresh()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(_OUTGAME_PATH)
