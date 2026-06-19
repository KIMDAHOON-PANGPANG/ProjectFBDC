extends Sprite3D

## 게임 시작2 PC 도트 스프라이트 — Adventurer 2D Top-Down 에셋(8프레임 96×80 스트립,
## 4방향 down/left/right/up)을 hframes 로 애니메이션한다. 적이 쓰는 SpriteRig 는
## 그대로 두고, PC 만 이 컴포넌트를 쓴다. SpriteRig 와 동일한 API
## (set_state/set_facing/flash/start_iframe_blink/play_death_then_free/set_visuals)
## 를 노출해 Player.gd 가 거의 그대로 호출한다. 4방향은 set_facing_vec(Vector3) 사용.
##
## 알파 안전(d3d12) — godot-pixel-sprite-alpha 스킬: transparent=true + ALPHA_CUT_DISCARD
## + NEAREST 필터. import 쪽은 PC.png.import 설정(lossless·no-mipmap·compress_to=0) 복제.

# Player.gd 가 SpriteRig.State.X(int) 를 그대로 넘기므로 같은 순서/값으로 맞춘다.
enum State { IDLE, WALK, ATTACK, HURT, DEATH }

const FRAMES: int = 8
const _SP := "res://market/Adventurer 2D Top-Down/Sprites/"
# idle / run / attack2 × 4방향. 각 8프레임 96×80 가로 스트립.
const SHEETS := {
	"idle": {
		"down": preload("res://market/Adventurer 2D Top-Down/Sprites/IDLE/idle_down.png"),
		"left": preload("res://market/Adventurer 2D Top-Down/Sprites/IDLE/idle_left.png"),
		"right": preload("res://market/Adventurer 2D Top-Down/Sprites/IDLE/idle_right.png"),
		"up": preload("res://market/Adventurer 2D Top-Down/Sprites/IDLE/idle_up.png"),
	},
	"run": {
		"down": preload("res://market/Adventurer 2D Top-Down/Sprites/RUN/run_down.png"),
		"left": preload("res://market/Adventurer 2D Top-Down/Sprites/RUN/run_left.png"),
		"right": preload("res://market/Adventurer 2D Top-Down/Sprites/RUN/run_right.png"),
		"up": preload("res://market/Adventurer 2D Top-Down/Sprites/RUN/run_up.png"),
	},
	"attack2": {
		"down": preload("res://market/Adventurer 2D Top-Down/Sprites/ATTACK 2/attack2_down.png"),
		"left": preload("res://market/Adventurer 2D Top-Down/Sprites/ATTACK 2/attack2_left.png"),
		"right": preload("res://market/Adventurer 2D Top-Down/Sprites/ATTACK 2/attack2_right.png"),
		"up": preload("res://market/Adventurer 2D Top-Down/Sprites/ATTACK 2/attack2_up.png"),
	},
}

## 프레임 재생 속도(초당 프레임). 데이터처럼 인스펙터에서 조절.
@export var idle_fps: float = 8.0
@export var run_fps: float = 12.0
## 공격(attack2)은 일섬 대시 동안 1회 재생. 8프레임이라 20fps ≈ 0.4s.
@export var attack_fps: float = 20.0
## 96×80 프레임 기준 픽셀 크기(작을수록 작게 보임). 발 위치/크기 튜닝용.
@export var pixel_size_v: float = 0.02

var _state: int = State.IDLE
var _dir: String = "down"
var _frame_t: float = 0.0
var _base_modulate: Color = Color.WHITE
var _blink_tween: Tween
## SpriteRig API 호환(미사용) — Player.gd 가 `_sprite_rig.fallback_color = ...` 를 호출.
var fallback_color: Color = Color.WHITE


func _ready() -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	shaded = false
	transparent = true
	alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	alpha_scissor_threshold = 0.5
	no_depth_test = false
	double_sided = false
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	pixel_size = pixel_size_v
	hframes = FRAMES
	vframes = 1
	_base_modulate = modulate
	frame = 0
	_apply_sheet()


func _process(delta: float) -> void:
	var fps: float = idle_fps
	match _state:
		State.WALK: fps = run_fps
		State.ATTACK: fps = attack_fps
	_frame_t += delta * fps
	while _frame_t >= 1.0:
		_frame_t -= 1.0
		if _state == State.ATTACK:
			# 공격은 마지막 프레임에서 정지(1회 재생) — 대시 동안 일섬 연출.
			if frame < FRAMES - 1:
				frame += 1
		else:
			frame = (frame + 1) % FRAMES  # idle/run 루프


# ── SpriteRig 호환 API ──────────────────────────────────────────────

func set_visuals(_v) -> void:
	pass  # PC 는 위 SHEETS 를 쓰므로 CharacterVisuals 무시(호환용 no-op).

func set_state(s: int) -> void:
	if _state == s:
		return
	_state = s
	_frame_t = 0.0
	frame = 0
	_apply_sheet()

## 2방향(좌우) 호환 — 가능하면 set_facing_vec 를 쓴다.
func set_facing(dir_x: float) -> void:
	if absf(dir_x) < 0.01:
		return
	_set_dir("right" if dir_x > 0.0 else "left")

## 4방향 — 커서/이동 방향 벡터로 down/up/left/right 선택. (+z=화면 아래, -z=위)
func set_facing_vec(v: Vector3) -> void:
	if absf(v.x) < 0.001 and absf(v.z) < 0.001:
		return
	if absf(v.x) >= absf(v.z):
		_set_dir("right" if v.x > 0.0 else "left")
	else:
		_set_dir("down" if v.z > 0.0 else "up")

func _set_dir(d: String) -> void:
	if d == _dir:
		return
	_dir = d
	_apply_sheet()

func _anim_for_state() -> String:
	match _state:
		State.WALK: return "run"
		State.ATTACK: return "attack2"
		_: return "idle"  # IDLE/HURT/DEATH → idle 시트(죽음은 아래 트윈)

func _apply_sheet() -> void:
	var anim: String = _anim_for_state()
	var d: String = _dir if (SHEETS[anim] as Dictionary).has(_dir) else "down"
	texture = SHEETS[anim][d]


## 피격 텔레그래프 — 잠깐 과하게 밝아졌다 복귀.
func flash(duration: float = 0.16) -> void:
	var bright: Color = Color(3.0, 3.0, 3.0, _base_modulate.a)
	var t := create_tween()
	t.tween_property(self, "modulate", bright, duration * 0.2)
	t.tween_property(self, "modulate", _base_modulate, duration * 0.8)


## i-frame 깜빡임 — 밝게/투명 교차로 무적을 시각화.
func start_iframe_blink(duration: float = 1.0) -> void:
	if _blink_tween != null and _blink_tween.is_valid():
		_blink_tween.kill()
	var bright: Color = Color(2.5, 2.5, 2.5, 1.0)
	var invisible: Color = Color(_base_modulate.r, _base_modulate.g, _base_modulate.b, 0.0)
	var half_cycle: float = 0.08
	var cycles: int = max(int(duration / (half_cycle * 2.0)), 1)
	_blink_tween = create_tween()
	for i in cycles:
		_blink_tween.tween_property(self, "modulate", bright, half_cycle)
		_blink_tween.tween_property(self, "modulate", invisible, half_cycle)
	_blink_tween.tween_callback(_restore_base_modulate)

func _restore_base_modulate() -> void:
	modulate = _base_modulate


func play_death_then_free(parent_to_free: Node, duration: float = 0.45) -> void:
	set_state(State.DEATH)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(self, "modulate:a", 0.0, duration)
	t.tween_property(self, "position:y", position.y + 0.6, duration)
	t.tween_property(self, "rotation:z", deg_to_rad(35.0 if _dir != "left" else -35.0), duration)
	t.chain().tween_callback(parent_to_free.queue_free)
