class_name HD2DCamera
extends Node3D

## HD-2D style camera rig (Octopath Traveler look).
##
## How it works:
##   This Node3D follows the target on XZ (and Y) every frame. The Camera3D
##   sits at a fixed local offset (height + back distance) and is pre-rotated
##   once to look at the rig's origin. Because the rig translates with the
##   target, the camera-to-target relative geometry never changes.

@export var target_path: NodePath

@export_group("Framing")
## Local offset of the camera from the target (Y = height, Z = back distance).
## Tightened (~0.65×) for the chapter system — narrower view so off-screen
## spawns are meaningfully off-screen.
@export var offset: Vector3 = Vector3(0.0, 10.4, 9.1)
@export var fov: float = 38.0

@export_group("Follow")
@export var follow_speed_xz: float = 7.0
@export var follow_speed_y: float = 5.0
## LB(모드2 일섬) 차징 동안 카메라가 서서히 빠지는 줌아웃 — 최대 배수(cap)와 속도(/초).
@export var charge_zoom_max: float = 1.4
@export var charge_zoom_rate: float = 2.0

var _cam: Camera3D
var _target: Node3D
# Lag-nudge state. While >0 the follow speed is multiplied by `_lag_factor`,
# producing a brief "camera trails the player" feel after big PC actions.
var _lag_timer: float = 0.0
var _lag_factor: float = 1.0
## Follow-boost state. While >0 the xz follow speed is multiplied UP by
## `_boost_mult` (>1) so the camera sticks tight to the PC and moves WITH it
## — used by the slash dash for a "공격과 함께 이동" feel (not a post-action lag).
var _boost_timer: float = 0.0
var _boost_mult: float = 1.0
var _base_follow_xz: float
# Shake state — Camera3D is offset by a random vector that decays toward 0
# over `_shake_total` seconds. Pure visual; doesn't move the rig itself.
var _shake_t: float = 0.0
var _shake_total: float = 0.0
var _shake_amp: float = 0.0
# When true, decay uses pow(decay, 2.0) (ease-out): sharp impact, fast
# fall-off — ZZZ-style "critical hit" feel reserved for parries. Flipped
# by shake_curve(...). shake(...) resets to false for the linear feel.
var _shake_use_curve: bool = false
var _cam_base_origin: Vector3
# Zoom-punch state — temporarily scales the camera's local offset (dolly out,
# >1) then eases back over `_zoom_total` seconds. Used by the slash to widen the
# view at the landing so the destination enemies are readable.
var _zoom_t: float = 0.0
var _zoom_total: float = 0.0
var _zoom_scale_target: float = 1.0
# Sheathe zoom-IN state — 줌인=로컬 오프셋 축소(가까이), zoom_punch(dolly-out, >1)의 반대 방향.
# 별도 상태로 유지하고 _update_cam_local 에서 base 에 곱으로만 합성(섞지 말 것).
var _zin_t: float = 0.0
var _zin_total: float = 0.0
var _zin_scale_target: float = 1.0
# LB 차징 줌아웃(ESC 토글) — active 동안 base origin 을 charge_zoom_max 로 서서히
# 밀어냈다가(최대값 cap), 해제 시 1.0 으로 복귀. zoom_punch 와 max 로 합쳐진다.
var _charge_zoom: float = 1.0
var _charge_zoom_active: bool = false
## 히트스탑 재진입 가드(겹쳐서 Engine.time_scale 이 꼬이지 않게).
var _hitstop_active: bool = false

func _ready() -> void:
	add_to_group("camera_rig")  # Player/other systems look up the rig via this group.
	_cam = get_node_or_null("Camera3D") as Camera3D
	if _cam == null:
		_cam = Camera3D.new()
		_cam.name = "Camera3D"
		add_child(_cam)
	_apply_framing()
	_base_follow_xz = follow_speed_xz
	_target = get_node_or_null(target_path) as Node3D
	if _target != null:
		global_position = _target.global_position

func set_target(t: Node3D) -> void:
	_target = t
	if _target != null:
		global_position = _target.global_position

func _apply_framing() -> void:
	_cam.fov = fov
	_cam.near = 0.5
	_cam.far = 200.0
	# Place the camera at the offset, pointing at the rig's origin.
	# We compute the rotation locally so subsequent translations of the rig
	# carry the orientation along unchanged.
	var t := Transform3D.IDENTITY
	t.origin = offset
	t = t.looking_at(Vector3.ZERO, Vector3.UP)
	_cam.transform = t
	_cam_base_origin = _cam.transform.origin

func _process(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	# Resolve the effective xz follow speed (with optional lag nudge).
	var xz_speed := _base_follow_xz
	if _lag_timer > 0.0:
		_lag_timer -= delta
		xz_speed = _base_follow_xz * _lag_factor
		if _lag_timer <= 0.0:
			_lag_factor = 1.0
	# 일섬 대시 — 추적 속도를 끌어올려 카메라가 PC 에 바짝 붙어 함께 이동.
	if _boost_timer > 0.0:
		_boost_timer -= delta
		xz_speed = max(xz_speed, _base_follow_xz * _boost_mult)
		if _boost_timer <= 0.0:
			_boost_mult = 1.0
	var tp := _target.global_position
	var p := global_position
	var ax: float = clamp(xz_speed * delta, 0.0, 1.0)
	var ay: float = clamp(follow_speed_y * delta, 0.0, 1.0)
	p.x = lerp(p.x, tp.x, ax)
	p.z = lerp(p.z, tp.z, ax)
	p.y = lerp(p.y, tp.y, ay)
	global_position = p
	_update_cam_local(delta)

## Combined camera-local update: zoom-punch (dolly out, eased back) baked into
## the base origin, plus a decaying random shake offset on top. Both leave the
## follow rig untouched — only the Camera3D's local position moves. Shake decay
## is linear by default; shake_curve(...) flips it to ease-out (pow(decay, 2)).
func _update_cam_local(delta: float) -> void:
	if _cam == null:
		return
	# Zoom punch — base origin scaled out by an eased factor that returns to 1.0.
	var zoom: float = 1.0
	if _zoom_t > 0.0:
		_zoom_t -= delta
		var zf: float = clamp(_zoom_t / max(_zoom_total, 0.0001), 0.0, 1.0)
		zoom = lerp(1.0, _zoom_scale_target, zf)
		if _zoom_t <= 0.0:
			_zoom_scale_target = 1.0
	# LB 차징 줌아웃(토글) — active 동안 charge_zoom_max 로 서서히 빠졌다가 복귀.
	var ct: float = charge_zoom_max if _charge_zoom_active else 1.0
	_charge_zoom = move_toward(_charge_zoom, ct, charge_zoom_rate * delta)
	zoom = max(zoom, _charge_zoom)
	# 납도 줌인 — 오프셋을 _zin_scale_target(<=1)로 축소(가까이) 후 1.0 으로 복귀.
	# zoom 은 >=1 dolly-out, zin 은 <=1 dolly-in 이라 곱으로 합성(동시 발동 시 상쇄).
	var zin: float = 1.0
	if _zin_t > 0.0:
		_zin_t -= delta
		var zif: float = clamp(_zin_t / max(_zin_total, 0.0001), 0.0, 1.0)
		zin = lerp(1.0, _zin_scale_target, zif)
		if _zin_t <= 0.0:
			_zin_scale_target = 1.0
	var base: Vector3 = _cam_base_origin * zoom * zin
	# Shake offset on top of the (possibly zoomed) base.
	var off := Vector3.ZERO
	if _shake_t > 0.0:
		_shake_t -= delta
		var decay: float = clamp(_shake_t / max(_shake_total, 0.0001), 0.0, 1.0)
		if _shake_use_curve:
			decay = pow(decay, 2.0)
		off = Vector3(
			randf_range(-1.0, 1.0) * _shake_amp * decay,
			randf_range(-1.0, 1.0) * _shake_amp * decay * 0.5,
			randf_range(-1.0, 1.0) * _shake_amp * decay,
		)
	_cam.position = base + off

## Trigger a brief camera shake. `amplitude` is in world units (mild ≈ 0.08,
## sharp ≈ 0.25, screen-rattle ≈ 0.5). `duration` in seconds.
## Re-calling layers naturally — the new shake just replaces the in-flight
## one with its own (usually fresh, larger) decay. Linear fall-off.
func shake(amplitude: float, duration: float) -> void:
	_shake_amp = max(_shake_amp, amplitude)  # don't downgrade a louder shake
	_shake_t = max(_shake_t, duration)
	_shake_total = _shake_t
	_shake_use_curve = false

## ZZZ-style "critical impact" variant — same amplitude/duration semantics
## as shake() but with an ease-out fall-off (pow(decay, 2)) for that
## hard-front, fast-tail feel. Reserved for parry/finisher beats where the
## linear shake reads too "buzzy".
func shake_curve(amplitude: float, duration: float) -> void:
	_shake_amp = max(_shake_amp, amplitude)
	_shake_t = max(_shake_t, duration)
	_shake_total = _shake_t
	_shake_use_curve = true

## Briefly reduce the xz follow speed so the camera trails the player after
## a big action (dash). Call from PC code with e.g. (0.35, 0.4) → for 0.35s
## follow speed is 40% of normal, then snaps back.
func nudge_lag(duration: float, factor: float) -> void:
	_lag_timer = max(_lag_timer, duration)
	_lag_factor = clamp(factor, 0.05, 1.0)

## 일섬 대시처럼 "공격과 함께 카메라가 같이 이동"하는 느낌을 주려고, duration 동안
## xz 추적 속도를 mult 배(>1)로 끌어올려 PC 에 바짝 붙여 함께 움직이게 한다. 끝나면 복귀.
func follow_boost(duration: float, mult: float) -> void:
	_boost_timer = max(_boost_timer, duration)
	_boost_mult = max(_boost_mult, max(mult, 1.0))

## 일섬 직후 도착 지점 가시성 — 카메라를 잠깐 뒤로 빼(줌아웃) 착지 주변을 넓게
## 보여준다. scale(>1)배로 로컬 오프셋을 늘렸다가 duration 동안 1.0 으로 복귀.
func zoom_punch(scale: float, duration: float) -> void:
	if duration <= 0.0:
		return
	_zoom_scale_target = max(_zoom_scale_target, max(scale, 1.0))
	_zoom_t = max(_zoom_t, duration)
	_zoom_total = _zoom_t

## 납도 줌인 — 카메라가 PC 쪽으로 확 당겨졌다(줌인) 부드럽게 복귀.
## 줌인=로컬 오프셋 축소(가까이)로, zoom_punch(줌아웃)의 반대 방향. scale 은 1.0 미만.
## 더 가까운(작은) 값 우선(punch 의 max 와 대칭으로 min 사용).
func sheathe_zoom_in(scale: float, duration: float) -> void:
	if duration <= 0.0:
		return
	var s := clampf(scale, 0.3, 1.0)
	_zin_scale_target = min(_zin_scale_target, s)
	_zin_t = max(_zin_t, duration)
	_zin_total = _zin_t

## LB 차징 줌아웃 토글 — active=true 면 매 프레임 charge_zoom_max 로 서서히 빠지고,
## false 면 1.0 으로 복귀(_update_cam_local 의 move_toward). Player 가 차징 중 호출.
func set_charge_zoom(active: bool) -> void:
	_charge_zoom_active = active

## 극소량 히트스탑 — Engine.time_scale 을 잠깐 낮췄다 복구해 타격감(역경직)을 준다.
## BulletTime(per-enemy time_scale_mult)과 독립이라 충돌하지 않는다. 복구 타이머는
## ignore_time_scale 로 실시간 동작(time_scale=0 이어도 깨어남). 카메라가 PC 보다
## 오래 살아남고 _exit_tree 에서 강제 정상화하므로 time_scale 이 멈춘 채 방치될 일이 없다.
func hitstop(scale: float, duration: float) -> void:
	if _hitstop_active or duration <= 0.0:
		return
	_hitstop_active = true
	Engine.time_scale = clampf(scale, 0.0, 1.0)
	var t := get_tree().create_timer(duration, true, false, true)  # ignore_time_scale
	t.timeout.connect(_end_hitstop)

func _end_hitstop() -> void:
	Engine.time_scale = 1.0
	_hitstop_active = false

func _exit_tree() -> void:
	# 씬 종료 중 히트스탑이 걸려 있었어도 time_scale 을 반드시 정상화.
	if not is_equal_approx(Engine.time_scale, 1.0):
		Engine.time_scale = 1.0
	_hitstop_active = false

## Whether a world position falls inside the active camera's frustum.
## Used by spawners to keep spawns off-screen and by ranged enemies to
## suppress AIM when the PC isn't visible.
func is_world_pos_visible(world_pos: Vector3) -> bool:
	if _cam == null:
		return false
	return _cam.is_position_in_frustum(world_pos)
