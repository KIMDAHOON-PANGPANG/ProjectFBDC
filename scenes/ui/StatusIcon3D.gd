extends MeshInstance3D

## 공용 상태 아이콘(3D) — 작은 quad + radial 게이지 셰이더(status_radial_3d.gdshader).
## class_name 없음 — StatusIconStrip3D 가 preload + .new() 로 인스턴스, set_data 덕타이핑.
##
## 데이터 모델(set_data 인자 Dictionary):
##   value : float 0~1   — 게이지 채움/소진 비율
##   mode  : int         — 0=FILL_UP(누적·차오름) / 1=DEPLETE(지속·줄어듦)
##   color : Color       — 틴트(아이콘/심볼/ring 색)
##   icon  : Texture2D   — 중심 아이콘(null 이면 단색 심볼 플레이스홀더)
##
## 빌보드는 부모 StatusIconStrip3D 가 노드 단위로 처리(HpBar3D 동일 패턴) — 머티리얼
## 빌보드는 OFF. render_priority 110 = HpBar3D fill(102) 위로 그려 가려지지 않음.

const _SHADER := preload("res://scenes/ui/status_radial_3d.gdshader")

const SIZE: float = 0.34

var _mat: ShaderMaterial


func _ready() -> void:
	_build()


func _build() -> void:
	if _mat != null:
		return
	var qm := QuadMesh.new()
	qm.size = Vector2(SIZE, SIZE)
	mesh = qm
	_mat = ShaderMaterial.new()
	_mat.shader = _SHADER
	_mat.render_priority = 110
	material_override = _mat
	# 기본값(아이콘 없는 핑크 플레이스홀더).
	_mat.set_shader_parameter("value", 0.0)
	_mat.set_shader_parameter("mode", 0)
	_mat.set_shader_parameter("tint", Color(1.0, 0.37, 0.69, 1.0))
	_mat.set_shader_parameter("has_icon", false)


## 셰이더 uniform 갱신. 매 프레임 호출돼도 set_shader_parameter 만 한다(노드 생성 X).
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
