@tool
extends EditorPlugin

## 인하우스 밸런스 에디터 플러그인. 두 가지 진입점:
##   1) 메뉴: 프로젝트(Project) > 도구(Tools) > "밸런스 툴 (PC/몬스터)" → 별도 창으로 열림
##   2) 우측 도크 탭("밸런스 툴" — 인스펙터/그룹 탭 옆)
## Project > Project Settings > Plugins 에서 켜고 끌 수 있다.

const _DockScript := preload("res://addons/balance_tool/balance_dock.gd")
const _MENU := "밸런스 툴 (PC/몬스터)"

var _dock
var _win: Window


func _enter_tree() -> void:
	# 1) 우측 상단 도크 탭 — 인스펙터/시그널/그룹 옆에 기본 배치(엔진 기동 시).
	_dock = _DockScript.new()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)
	# 2) 메뉴 표시줄(프로젝트 > 도구)에서 창으로 열기.
	add_tool_menu_item(_MENU, _open_window)


func _exit_tree() -> void:
	remove_tool_menu_item(_MENU)
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.free()
		_dock = null
	if _win != null and is_instance_valid(_win):
		_win.queue_free()
		_win = null


## 메뉴 클릭 — 밸런스 툴을 별도 떠다니는 창으로 연다(이미 있으면 다시 띄움).
func _open_window() -> void:
	if _win != null and is_instance_valid(_win):
		_win.popup_centered(Vector2i(560, 760))
		return
	var base: Control = EditorInterface.get_base_control()
	if base == null:
		push_warning("밸런스 툴: 에디터 base control 을 찾을 수 없습니다.")
		return
	_win = Window.new()
	_win.title = "밸런스 툴 — PC / 몬스터"
	_win.min_size = Vector2i(460, 480)
	var content = _DockScript.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_win.add_child(content)
	base.add_child(_win)
	_win.close_requested.connect(_on_win_close)
	_win.popup_centered(Vector2i(560, 760))


func _on_win_close() -> void:
	if _win != null and is_instance_valid(_win):
		_win.hide()
