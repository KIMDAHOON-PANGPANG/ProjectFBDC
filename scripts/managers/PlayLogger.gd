extends Node

## 플레이 로그 — 게임 진행을 사람이 읽는 텍스트 파일로 기록. Autoload(project.godot).
## 빌드 EXE: exe 폴더 옆 playlog_<날짜>.txt / 에디터: user://playlog_<날짜>.txt.
## build_config.play_logging 으로 on/off. Main 이 주요 이벤트마다 event() 호출.

const _BUILD_CONFIG := "res://resources/build_config.tres"

var _file: FileAccess = null
var _path: String = ""


func _ready() -> void:
	var enabled := true
	if ResourceLoader.exists(_BUILD_CONFIG):
		var cfg = load(_BUILD_CONFIG)
		if cfg != null and "play_logging" in cfg:
			enabled = bool(cfg.play_logging)
	if enabled:
		_open()


func _open() -> void:
	var ts := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var base := "user://"
	if not OS.has_feature("editor"):
		# 빌드 EXE — 실행 파일 폴더 옆에 기록(뽑기 쉽게).
		base = OS.get_executable_path().get_base_dir() + "/"
	_path = base + "playlog_" + ts + ".txt"
	_file = FileAccess.open(_path, FileAccess.WRITE)
	if _file == null:
		# 폴더 쓰기 실패(권한 등) → user:// 로 폴백.
		_path = "user://playlog_" + ts + ".txt"
		_file = FileAccess.open(_path, FileAccess.WRITE)
	if _file != null:
		_file.store_line("=== ProjectFBDC 플레이 로그 ===")
		_file.store_line("시작: " + Time.get_datetime_string_from_system())
		_file.flush()
		print("[PlayLogger] 로그: ", ProjectSettings.globalize_path(_path))


## 한 줄 이벤트 기록(시각 prefix). Main 등에서 호출.
func event(text: String) -> void:
	if _file == null:
		return
	_file.store_line("[%s] %s" % [Time.get_time_string_from_system(), text])
	_file.flush()


## 절대 경로(globalize) — 디버그/표시용.
func log_path() -> String:
	if _path == "":
		return ""
	return ProjectSettings.globalize_path(_path)


func _exit_tree() -> void:
	if _file != null:
		_file.store_line("종료: " + Time.get_datetime_string_from_system())
		_file.close()
		_file = null
