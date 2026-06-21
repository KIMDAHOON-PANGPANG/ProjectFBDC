extends Node

## 해상도 / 전체화면 설정 관리 — Autoload(/root/SettingsManager).
## user://settings.cfg 에 저장·로드. class_name 없이 preload+덕타이핑 접근.

const _PATH := "user://settings.cfg"

const RESOLUTIONS := [
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
	Vector2i(2560, 1080),
	Vector2i(3440, 1440),
]
const RES_LABELS := [
	"1920 x 1080 (16:9)",
	"2560 x 1440 (16:9)",
	"3840 x 2160 (16:9)",
	"2560 x 1080 (21:9)",
	"3440 x 1440 (21:9)",
]

var res_index: int = 0
var fullscreen: bool = false


func _ready() -> void:
	load_settings()
	apply()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_PATH) != OK:
		return
	res_index = clamp(int(cfg.get_value("display", "res_index", 0)), 0, RESOLUTIONS.size() - 1)
	fullscreen = bool(cfg.get_value("display", "fullscreen", false))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "res_index", res_index)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.save(_PATH)


func apply() -> void:
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var sz: Vector2i = RESOLUTIONS[clamp(res_index, 0, RESOLUTIONS.size() - 1)]
		DisplayServer.window_set_size(sz)
		var screen := DisplayServer.window_get_current_screen()
		var scr_sz := DisplayServer.screen_get_size(screen)
		DisplayServer.window_set_position(
			DisplayServer.screen_get_position(screen) + (scr_sz - sz) / 2
		)


func set_resolution(idx: int) -> void:
	res_index = clamp(idx, 0, RESOLUTIONS.size() - 1)
	save_settings()
	apply()


func set_fullscreen(on: bool) -> void:
	fullscreen = on
	save_settings()
	apply()
