extends Control

## 마우스 커서를 따라가는 원형 십자선(crosshair) 에임 UI.
##
## 화면 전체를 덮는 Control 이 매 프레임 마우스 위치에 원(circle) + 십자(cross)
## + 중심점을 그린다. 클릭을 막지 않도록 mouse_filter = IGNORE, 일시정지(레벨업
## /결과 화면) 중에도 따라가도록 process_mode = ALWAYS. OS 커서는 숨기고 이
## 십자선이 그 자리를 대신한다 (씬을 떠날 때/종료 시 복원 → OutGame 메뉴·에디터
## 가 커서 없이 남지 않음).
##
## Main / Testplay 의 .tscn 에 인스턴스로 들어간다 (OutGame 메뉴는 일반 커서를
## 써야 하므로 일부러 제외). 두 씬에 같은 씬을 꽂으므로 별도 미러 코드 불필요.

## OS 하드웨어 커서를 숨기고 십자선으로 대체할지. false 면 OS 커서 위에 겹쳐 표시.
@export var hide_os_cursor: bool = true
@export var radius: float = 12.0
## 중심에서 십자 팔이 시작되는 빈 간격.
@export var gap: float = 4.0
## 원 바깥으로 더 뻗는 십자 팔 길이.
@export var arm: float = 7.0
@export var color: Color = Color(1.0, 1.0, 1.0, 0.9)
@export var shadow: Color = Color(0.0, 0.0, 0.0, 0.55)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 일시정지(레벨업/게임오버) 중에도 커서를 계속 따라가고 클릭 지점을 보여준다.
	process_mode = Node.PROCESS_MODE_ALWAYS
	if hide_os_cursor:
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)


func _exit_tree() -> void:
	# 씬 전환/종료 시 OS 커서 복원.
	if hide_os_cursor:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _process(_delta: float) -> void:
	queue_redraw()  # 매 프레임 다시 그려 커서를 따라가게 한다.


func _draw() -> void:
	var c: Vector2 = get_viewport().get_mouse_position()
	# 외곽 원 — 그림자(두껍게) → 본선(얇게) 순으로 그려 어떤 배경에서도 보이게.
	draw_arc(c, radius, 0.0, TAU, 48, shadow, 3.0, true)
	draw_arc(c, radius, 0.0, TAU, 48, color, 1.5, true)
	# 십자 4방향 — 중심 gap 부터 원 바깥(radius + arm)까지.
	for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var p1: Vector2 = c + d * gap
		var p2: Vector2 = c + d * (radius + arm)
		draw_line(p1, p2, shadow, 3.0, true)
		draw_line(p1, p2, color, 1.5, true)
	# 중심점.
	draw_circle(c, 1.5, color)
