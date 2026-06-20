extends CanvasLayer

## 씬 전환 셰이더 연출 — Autoload. change_scene(path) 호출 시 화면을 셰이더로 덮었다가
## 씬 전환 후 다시 걷어낸다(UI 이동 연출). market/OutGameUi/shader 의 transition.gdshader 사용
## (안정적 위치 res://shaders/ 로 복사). 그라디언트=대각선 와이프, 셰이프=노이즈 디졸브 엣지.

const _SHADER := preload("res://shaders/transition.gdshader")

var _rect: ColorRect
var _mat: ShaderMaterial
var _busy: bool = false


func _ready() -> void:
	layer = 200  # HUD/오버레이보다 위
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = _SHADER
	_mat.set_shader_parameter("base_color", Color(0.05, 0.05, 0.07, 1.0))
	_mat.set_shader_parameter("width", 0.45)
	_mat.set_shader_parameter("gradient_texture", _make_gradient())
	_mat.set_shader_parameter("gradient_fixed", false)
	_mat.set_shader_parameter("shape_texture", _make_shape())
	_mat.set_shader_parameter("shape_tiling", 10.0)
	_mat.set_shader_parameter("shape_rotation", 0.0)
	_mat.set_shader_parameter("shape_scroll", Vector2.ZERO)
	_mat.set_shader_parameter("shape_feathering", 0.3)
	_mat.set_shader_parameter("shape_treshold", 1.0)
	_mat.set_shader_parameter("factor", 0.0)
	_rect.material = _mat
	_rect.visible = false
	add_child(_rect)
	var vp := get_viewport()
	if vp != null:
		vp.size_changed.connect(_update_res)


func _update_res() -> void:
	if _rect != null and _mat != null:
		_mat.set_shader_parameter("node_resolution", _rect.size)


## 셰이더 연출로 씬 전환 — 덮기 → change_scene → 걷어내기. 어디서든 호출(autoload).
func change_scene(path: String, dur: float = 0.35) -> void:
	if _busy:
		return
	_busy = true
	_rect.visible = true
	_rect.size = get_viewport().get_visible_rect().size
	_mat.set_shader_parameter("node_resolution", _rect.size)
	await _tween_factor(0.0, 1.0, dur)   # 덮기
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame
	await _tween_factor(1.0, 0.0, dur)   # 걷어내기
	_rect.visible = false
	_busy = false


func _tween_factor(from: float, to: float, dur: float) -> void:
	_mat.set_shader_parameter("factor", from)
	var t := create_tween()
	t.tween_method(_set_factor, from, to, dur)
	await t.finished

func _set_factor(v: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("factor", v)


func _make_gradient() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color.BLACK)
	g.set_color(1, Color.WHITE)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_LINEAR
	gt.fill_from = Vector2(0.0, 0.0)
	gt.fill_to = Vector2(1.0, 1.0)
	gt.width = 256
	gt.height = 256
	return gt

func _make_shape() -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = 0.04
	var nt := NoiseTexture2D.new()
	nt.noise = n
	nt.width = 128
	nt.height = 128
	nt.seamless = true
	return nt
