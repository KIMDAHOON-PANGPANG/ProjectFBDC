extends Control

## 공용 상태 아이콘(2D) — radial 게이지 셰이더(status_radial_2d.gdshader)를 입힌 작은 Control.
## class_name 없음 — PlayerHud 가 preload + .new() 로 인스턴스, set_data 덕타이핑.
## StatusIcon3D 와 동일한 데이터 모델({value, mode, color, icon}) 공유.

const _SHADER := preload("res://scenes/ui/status_radial_2d.gdshader")

const SIZE: float = 30.0

var _rect: ColorRect
var _mat: ShaderMaterial


func _ready() -> void:
	_build()


func _build() -> void:
	if _mat != null:
		return
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect = ColorRect.new()
	_rect.color = Color(1, 1, 1, 1)
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = _SHADER
	_rect.material = _mat
	add_child(_rect)
	_mat.set_shader_parameter("value", 0.0)
	_mat.set_shader_parameter("mode", 0)
	_mat.set_shader_parameter("tint", Color(1.0, 0.37, 0.69, 1.0))
	_mat.set_shader_parameter("has_icon", false)


## 셰이더 uniform 갱신. d = {value, mode, color, icon}.
func set_data(d: Dictionary) -> void:
	if _mat == null:
		_build()
	var v: float = clampf(float(d.get("value", 0.0)), 0.0, 1.0)
	var m: int = int(d.get("mode", 0))
	var c = d.get("color", Color(1.0, 0.37, 0.69, 1.0))
	if not (c is Color):
		c = Color(1.0, 0.37, 0.69, 1.0)
	var icon = d.get("icon", null)
	_mat.set_shader_parameter("value", v)
	_mat.set_shader_parameter("mode", m)
	_mat.set_shader_parameter("tint", c)
	if icon != null and icon is Texture2D:
		_mat.set_shader_parameter("icon_tex", icon)
		_mat.set_shader_parameter("has_icon", true)
	else:
		_mat.set_shader_parameter("has_icon", false)
