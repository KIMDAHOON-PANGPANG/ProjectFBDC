@tool
extends EditorPlugin

## 빌드 매니저 — 게임 모드/토글을 build_config.tres 에 굽고 EXE 를 익스포트한다.
## 진입: 프로젝트(Project) > 도구(Tools) > "빌드 매니저 (EXE 빌드)".
## 빌드 EXE 의 OutGame 이 build_config 를 읽어 "게임 시작" 단일 메뉴로 진입(에디터는 개발 메뉴).

const _BuildConfigScript := preload("res://scripts/resources/BuildConfig.gd")
const _CONFIG_PATH := "res://resources/build_config.tres"
const _EXPORT_PRESET := "Windows Desktop"
const _OUT_EXE := "res://build/windows/ProjectFBDC.exe"
const _MENU := "빌드 매니저 (EXE 빌드)"

var _win: Window
var _mode_opt: OptionButton
var _resource_opt: OptionButton
var _aim_opt: OptionButton
var _contact_chk: CheckBox
var _zoom_chk: CheckBox
var _log_chk: CheckBox
var _overheat_slow_chk: CheckBox
var _name_edit: LineEdit
var _status: Label
var _build_btn: Button
var _progress: ProgressBar


func _enter_tree() -> void:
	add_tool_menu_item(_MENU, _open_window)


func _exit_tree() -> void:
	remove_tool_menu_item(_MENU)
	if _win != null and is_instance_valid(_win):
		_win.queue_free()
		_win = null


func _open_window() -> void:
	if _win != null and is_instance_valid(_win):
		_load_into_ui()
		_win.popup_centered(Vector2i(430, 540))
		return
	var base: Control = EditorInterface.get_base_control()
	if base == null:
		push_warning("빌드 매니저: 에디터 base control 없음")
		return
	_win = Window.new()
	_win.title = "빌드 매니저 — 모드/토글 + EXE 빌드"
	_win.min_size = Vector2i(390, 480)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_win.add_child(margin)
	_build_ui(margin)
	base.add_child(_win)
	_win.close_requested.connect(_win.hide)
	_load_into_ui()
	_win.popup_centered(Vector2i(430, 540))


func _build_ui(parent: Control) -> void:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 9)
	parent.add_child(vb)

	var title := Label.new()
	title.text = "빌드 구성"
	title.add_theme_font_size_override("font_size", 16)
	vb.add_child(title)

	vb.add_child(_label("게임 모드"))
	_mode_opt = OptionButton.new()
	_mode_opt.add_item("기본 일섬 웨이브", 0)
	_mode_opt.add_item("근접 몹 일섬", 1)
	_mode_opt.add_item("원거리 몹 일섬", 2)
	vb.add_child(_mode_opt)

	vb.add_child(_label("일섬 자원"))
	_resource_opt = OptionButton.new()
	_resource_opt.add_item("열기", 0)
	_resource_opt.add_item("쿨다운", 1)
	vb.add_child(_resource_opt)

	vb.add_child(_label("일섬 조작"))
	_aim_opt = OptionButton.new()
	_aim_opt.add_item("충전", 0)
	_aim_opt.add_item("즉발", 1)
	vb.add_child(_aim_opt)

	_contact_chk = CheckBox.new()
	_contact_chk.text = "몬스터 충돌 피해"
	vb.add_child(_contact_chk)

	_zoom_chk = CheckBox.new()
	_zoom_chk.text = "카메라 줌인/줌아웃"
	vb.add_child(_zoom_chk)

	_overheat_slow_chk = CheckBox.new()
	_overheat_slow_chk.text = "탈진 시 이동 감속"
	vb.add_child(_overheat_slow_chk)

	_log_chk = CheckBox.new()
	_log_chk.text = "플레이 로그 기록 (EXE 옆 .txt)"
	vb.add_child(_log_chk)

	vb.add_child(_label("ZIP 파일명 (마지막 _m숫자 만 고치면 됨 — 자동 +1)"))
	_name_edit = LineEdit.new()
	vb.add_child(_name_edit)

	vb.add_child(HSeparator.new())

	var save_btn := Button.new()
	save_btn.text = "설정 저장"
	save_btn.pressed.connect(_save_config)
	vb.add_child(save_btn)

	_build_btn = Button.new()
	_build_btn.text = "▶ 빌드 + ZIP (설정 저장 + 익스포트 + 압축)"
	_build_btn.add_theme_color_override("font_color", Color(0.6, 1, 0.6))
	_build_btn.pressed.connect(_do_build)
	vb.add_child(_build_btn)

	_progress = ProgressBar.new()
	_progress.min_value = 0.0
	_progress.max_value = 100.0
	_progress.value = 0.0
	_progress.custom_minimum_size = Vector2(0, 18)
	_progress.visible = false
	vb.add_child(_progress)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 70)
	_status.add_theme_color_override("font_color", Color(0.7, 0.85, 1))
	vb.add_child(_status)

	var note := Label.new()
	note.text = "※ 에디터(F5/F6)는 항상 개발 메뉴. 빌드된 EXE 만 '게임 시작' 단일 메뉴로 이 설정을 적용해 진행됩니다. 사망 화면 '이어서 하기'는 유지(테스트용)."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	note.add_theme_font_size_override("font_size", 11)
	vb.add_child(note)


func _label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	return l


func _load_cfg() -> Resource:
	if ResourceLoader.exists(_CONFIG_PATH):
		var c = load(_CONFIG_PATH)
		if c != null:
			return c
	return _BuildConfigScript.new()


func _load_into_ui() -> void:
	var c = _load_cfg()
	if _mode_opt != null:
		_mode_opt.select(clampi(int(c.game_mode), 0, 2))
	if _resource_opt != null:
		var resource_mode: int = (int(c.slash_resource_mode) if "slash_resource_mode" in c else 0)
		_resource_opt.select(clampi(resource_mode, 0, 1))
	if _aim_opt != null:
		var aim_mode: int = (int(c.slash_aim_mode) if "slash_aim_mode" in c else 1)
		_aim_opt.select(clampi(aim_mode, 0, 1))
	if _contact_chk != null:
		_contact_chk.button_pressed = bool(c.contact_damage)
	if _zoom_chk != null:
		_zoom_chk.button_pressed = bool(c.charge_zoom)
	if _overheat_slow_chk != null:
		_overheat_slow_chk.button_pressed = (bool(c.overheat_move_slow) if "overheat_move_slow" in c else false)
	if _log_chk != null:
		_log_chk.button_pressed = bool(c.play_logging)
	if _name_edit != null and _name_edit.text.strip_edges() == "":
		_name_edit.text = _detect_next_name()


func _save_config() -> void:
	var c = _load_cfg()
	c.game_mode = (_mode_opt.get_selected_id() if _mode_opt != null else 1)
	c.slash_resource_mode = (_resource_opt.get_selected_id() if _resource_opt != null else 0)
	c.slash_aim_mode = (_aim_opt.get_selected_id() if _aim_opt != null else 1)
	c.contact_damage = (_contact_chk.button_pressed if _contact_chk != null else false)
	c.charge_zoom = (_zoom_chk.button_pressed if _zoom_chk != null else true)
	c.overheat_move_slow = (_overheat_slow_chk.button_pressed if _overheat_slow_chk != null else false)
	c.play_logging = (_log_chk.button_pressed if _log_chk != null else true)
	var err := ResourceSaver.save(c, _CONFIG_PATH)
	if _status != null:
		_status.text = ("설정 저장됨 (build_config.tres)" if err == OK else "저장 실패: %d" % err)


func _do_build() -> void:
	_save_config()
	if _build_btn != null:
		_build_btn.disabled = true
	if _progress != null:
		_progress.visible = true
		_progress.value = 0.0
	if _status != null:
		_status.text = "빌드 준비 중..."
	await get_tree().process_frame
	var proj := ProjectSettings.globalize_path("res://")
	var win_dir := ProjectSettings.globalize_path(_OUT_EXE).get_base_dir()
	var out := win_dir.path_join("ProjectFBDC.exe")
	DirAccess.make_dir_recursive_absolute(win_dir)
	# 직전 산출물 제거 → 빌드 후 파일 존재 여부로 성공 판정(비블로킹이라 exit code 대신 사용).
	if FileAccess.file_exists(out):
		DirAccess.remove_absolute(out)
	var args := PackedStringArray(["--headless", "--path", proj, "--export-debug", _EXPORT_PRESET, out])
	# 비블로킹 익스포트 — 별도 프로세스로 띄우고 폴링하며 게이지를 채운다(에디터 안 멈춤).
	var pid := OS.create_process(OS.get_executable_path(), args)
	if pid <= 0:
		if _status != null:
			_status.text = "❌ 익스포트 프로세스 시작 실패"
		_end_build()
		return
	var elapsed := 0.0
	while OS.is_process_running(pid):
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1
		# 실제 % 를 못 받으므로 점근 곡선으로 0→90% 채움(완료 시 95→100%).
		var frac := 1.0 - exp(-elapsed / 14.0)
		if _progress != null:
			_progress.value = clampf(frac * 90.0, 0.0, 90.0)
		if _status != null:
			_status.text = "빌드 중... (%.0f초) — 에디터는 계속 쓸 수 있음" % elapsed
	if not FileAccess.file_exists(out):
		if _status != null:
			_status.text = "❌ 익스포트 실패 — 출력/익스포트 템플릿 확인"
		push_warning("[BuildManager] export 실패: %s 가 생성되지 않음" % out)
		_end_build()
		return
	if _progress != null:
		_progress.value = 95.0
	if _status != null:
		_status.text = "ZIP 압축 중..."
	await get_tree().process_frame
	# ZIP 압축 — build/<파일명>.zip (내부 폴더 = 파일명).
	var base := (_name_edit.text.strip_edges() if _name_edit != null else "")
	if base == "":
		base = _detect_next_name()
	var build_root := ProjectSettings.globalize_path("res://build/")
	var zip_path := build_root.path_join(base + ".zip")
	if _zip_dir(zip_path, win_dir, base):
		if _progress != null:
			_progress.value = 100.0
		if _status != null:
			_status.text = "✅ 빌드 + ZIP 완료:\n" + zip_path
		if _name_edit != null:
			_name_edit.text = _detect_next_name()  # 다음 넘버 자동 갱신
		OS.shell_open(build_root)
	else:
		if _status != null:
			_status.text = "⚠ EXE 는 성공, ZIP 실패:\n" + out
		OS.shell_open(win_dir)
	_end_build()


## 빌드 종료 — 버튼 재활성(게이지는 마지막 상태 유지, 다음 빌드 때 0 으로 리셋).
func _end_build() -> void:
	if _build_btn != null:
		_build_btn.disabled = false


## build/ 안 기존 *_m<N>.zip 중 최대 N 을 찾아 다음 이름(+1) 제안.
func _detect_next_name() -> String:
	var build_dir := ProjectSettings.globalize_path("res://build/")
	var maxn := 0
	var dir := DirAccess.open(build_dir)
	if dir != null:
		var re := RegEx.new()
		re.compile("_m(\\d+)\\.zip$")
		dir.list_dir_begin()
		var fn := dir.get_next()
		while fn != "":
			var m := re.search(fn)
			if m != null:
				maxn = maxi(maxn, m.get_string(1).to_int())
			fn = dir.get_next()
		dir.list_dir_end()
	return "ProjectFBDC-Windows_m%d" % (maxn + 1)


## src_dir 안 파일들을 zip_path 로 압축(내부에 folder/ 하위로 담는다).
func _zip_dir(zip_path: String, src_dir: String, folder: String) -> bool:
	var zip := ZIPPacker.new()
	if zip.open(zip_path) != OK:
		return false
	var dir := DirAccess.open(src_dir)
	if dir == null:
		zip.close()
		return false
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		if not dir.current_is_dir():
			var bytes := FileAccess.get_file_as_bytes(src_dir.path_join(fn))
			zip.start_file(folder.path_join(fn))
			zip.write_file(bytes)
			zip.close_file()
		fn = dir.get_next()
	dir.list_dir_end()
	zip.close()
	return true
