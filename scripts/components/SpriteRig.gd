class_name SpriteRig
extends Node3D

## HD-2D 캐릭터용 Sprite3D 래퍼 — 2가지 모드:
##   (A) 애니메이션 시트 모드: `sheet`(예: market/Sword/Sword.png) 지정 시 프레임 범위 기반
##       애니메이션 재생. set_state(IDLE/WALK/ATTACK/HURT/DEATH) 가 해당 프레임 범위를 돌린다.
##       move_anim(Walk/Run/Run2)·attack_anim(근접27-34/원거리34-40/돌진41-46)·프레임별 fps 를
##       몬스터별로 설정(데이터 드리블). 색은 tint(틴트)로 베리에이션.
##   (B) 레거시 모드: sheet 미지정 시 기존 CharacterVisuals 텍스처 스왑 동작(미마이그레이션 적 호환).
## API(set_state/set_facing/flash/start_iframe_blink/play_death_then_free)는 두 모드 공통.

enum State { IDLE, WALK, ATTACK, HURT, DEATH }

## 리컬러 셰이더 — 어두운 시트(Sword)도 tint 색으로 베리에이션. material_override 로 적용.
const _RECOLOR_SHADER := preload("res://shaders/monster_recolor.gdshader")

@export var sprite_3d_path: NodePath
# ── 레거시(CharacterVisuals) ──
@export var visuals: CharacterVisuals
@export var fallback_color: Color = Color(0.85, 0.85, 0.85)

# ── 애니메이션 시트 모드 ──
@export_group("Animated Sheet (Sword.png 류)")
## 지정하면 시트 애니메이션 모드. 비우면 레거시 모드.
@export var sheet: Texture2D
@export var sheet_hframes: int = 14
@export var sheet_vframes: int = 8
@export var tint: Color = Color.WHITE
@export var sheet_pixel_size: float = 0.03
## 이동 애니: 0=Walk(일반) / 1=Run / 2=Run2 (엘리트·보스는 Run/Run2 분배).
@export_enum("Walk", "Run", "Run2") var move_anim: int = 0
## 공격 애니: 0=근접 27-34 / 1=원거리 34-40 / 2=돌진 41-46 / 3=없음.
@export_enum("Melee 27-34", "Ranged 34-40", "Charge 41-46", "None") var attack_anim: int = 0
@export var idle_fps: float = 6.0
@export var move_fps: float = 9.0
@export var attack_fps: float = 12.0
@export var hit_fps: float = 12.0
@export var death_fps: float = 10.0

# ⚠ 시트 레이아웃 = 태그별 행(좌측 정렬). 그래서 Godot Sprite3D 프레임 인덱스(=row*14+col)는
# aseprite 글로벌 인덱스와 다르다. 행: 0=Idle 1=Run 2=Run2 3=Walk 4=Attack(14) 5=AttackCombo(8)
# 6=Hit(2) 7=Death(11). (PNG 14열×8행, 픽셀 content 분석으로 확정.)
const _IDLE := Vector2i(0, 6)         # row0
const _RUN := Vector2i(14, 17)        # row1
const _RUN2 := Vector2i(28, 35)       # row2
const _WALK := Vector2i(42, 48)       # row3
const _ATK_MELEE := Vector2i(64, 65)  # 글로벌 34-35: 34=윈드업(데칼+고정) / 35=스트라이크(타격). attack_fps 낮춰 34 를 ~1초 유지.
const _ATK_RANGED := Vector2i(64, 70) # row4 끝~row5 (글로벌 34-40)
const _CHARGE := Vector2i(71, 76)     # row5 AttackCombo 中 (글로벌 41-46)
const _HIT := Vector2i(84, 85)        # row6
const _DEATH := Vector2i(98, 108)     # row7
## 캐릭터가 128px 프레임의 좌측(cx≈29)에 그려져 있어 origin 에 맞추는 가로 보정(px).
const _CHAR_OFFSET_X: float = 36.0

var _sprite: Sprite3D
var _state: int = State.IDLE
var _facing_right: bool = true
var _base_modulate: Color = Color.WHITE
var _blink_tween: Tween
var _animated: bool = false

# 현재 재생 중인 애니 구간.
var _from: int = 0
var _to: int = 6
var _fps: float = 6.0
var _loop: bool = true
var _anim_t: float = 0.0
var _done: bool = false   # 원샷 완료(마지막 프레임 hold)
## 애니 재생 배속(불릿타임 등). 적이 매 프레임 갱신.
var time_scale_mult: float = 1.0


func _ready() -> void:
	if sprite_3d_path.is_empty():
		_sprite = _find_sprite()
	else:
		_sprite = get_node_or_null(sprite_3d_path) as Sprite3D
	if _sprite == null:
		return
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.shaded = false
	# transparent=true: d3d12 에서 일부 픽셀아트가 투명 RGB 를 흰색 불투명으로 렌더하는 버그 회피.
	_sprite.transparent = true
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_sprite.alpha_scissor_threshold = 0.5
	_sprite.no_depth_test = false
	_sprite.double_sided = false
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

	_animated = sheet != null
	if _animated:
		_sprite.texture = sheet
		_sprite.hframes = sheet_hframes
		_sprite.vframes = sheet_vframes
		_sprite.pixel_size = sheet_pixel_size
		_sprite.offset = Vector2(_CHAR_OFFSET_X, 0.0)  # 좌측 캐릭터를 origin 에 정렬
		# 리컬러 셰이더 — 어두운 몸도 tint 색으로 보이게(베리에이션). 플래시/블링크/페이드는
		# modulate(=셰이더 COLOR)로 유지하므로 base_modulate 는 흰색.
		var sm := ShaderMaterial.new()
		sm.shader = _RECOLOR_SHADER
		sm.set_shader_parameter("albedo", sheet)
		sm.set_shader_parameter("tint", tint)
		_sprite.material_override = sm
		_sprite.modulate = Color.WHITE
		_base_modulate = Color.WHITE
		set_process(true)
		_state = -1
		set_state(State.IDLE)
	else:
		_apply_visuals()
		set_process(false)
		_state = -1
		set_state(State.IDLE)


func _process(delta: float) -> void:
	if not _animated or _sprite == null:
		return
	_anim_t += delta * maxf(time_scale_mult, 0.0) * _fps
	var span: int = _to - _from + 1
	if span <= 0:
		return
	var idx: int = int(_anim_t)
	if _loop:
		_sprite.frame = _from + (idx % span)
	else:
		if idx >= span:
			_sprite.frame = _to  # 마지막 프레임 hold
			_done = true
		else:
			_sprite.frame = _from + idx


# ── 상태 ──
func set_state(s: int) -> void:
	if _state == s:
		return
	_state = s
	if _animated:
		_play_state(s)
	else:
		_refresh_texture()


func _play_state(s: int) -> void:
	match s:
		State.IDLE:
			_set_anim(_IDLE, idle_fps, true)
		State.WALK:
			_set_anim(_move_range(), move_fps, true)
		State.ATTACK:
			_set_anim(_attack_range(), attack_fps, false)
		State.HURT:
			_set_anim(_HIT, hit_fps, false)
		State.DEATH:
			_set_anim(_DEATH, death_fps, false)


func _set_anim(r: Vector2i, fps: float, loop: bool) -> void:
	_from = r.x
	_to = r.y
	_fps = maxf(fps, 0.1)
	_loop = loop
	_anim_t = 0.0
	_done = false
	if _sprite != null:
		_sprite.frame = _from


func _move_range() -> Vector2i:
	match move_anim:
		1: return _RUN
		2: return _RUN2
		_: return _WALK


func _attack_range() -> Vector2i:
	match attack_anim:
		1: return _ATK_RANGED
		2: return _CHARGE
		3: return _IDLE  # None — idle 유지
		_: return _ATK_MELEE


## 슬래머 "힘주기" 전용 — slam_windup 길이에 맞춰 공격 윈드업/스트라이크 두 프레임을
## 저 fps 로 왕복 루프해 정지처럼 보이지 않게(살아있는 힘주기 진동) 재생한다. 고정 길이
## 애니인 일반 ATTACK(1회) 과 달리, 데칼 fill·쿨다운 시간과 시각이 일치한다.
func play_slam_windup(windup: float) -> void:
	if not _animated or _sprite == null:
		return
	_state = State.ATTACK
	_from = _ATK_MELEE.x
	_to = _ATK_MELEE.y
	_loop = true
	# 두 프레임(34 윈드업 ↔ 35 스트라이크) 왕복이 windup 동안 천천히 돌게 fps 조절.
	_fps = max(2.0 / maxf(windup, 0.1), 0.5)
	_anim_t = 0.0
	_done = false
	_sprite.frame = _from


## 슬램 임팩트 — 스트라이크 프레임(35) 고정.
func play_slam_strike() -> void:
	if not _animated or _sprite == null:
		return
	_state = State.ATTACK
	_from = _ATK_MELEE.y
	_to = _ATK_MELEE.y
	_loop = false
	_done = true
	_anim_t = 0.0
	_sprite.frame = _ATK_MELEE.y


## 피격 모션 1회(48-49). 적 피격 시 호출 — 끝나면 다음 set_state 가 복귀시킴.
func play_hit() -> void:
	if not _animated:
		flash(0.18)
		return
	_state = State.HURT
	_set_anim(_HIT, hit_fps, false)


# ── 방향 플립 ──
func set_facing(dir_x: float) -> void:
	if not _animated and visuals != null and not visuals.flip_h_on_facing:
		return
	if abs(dir_x) < 0.01:
		return
	_facing_right = dir_x > 0.0
	if _sprite != null:
		var art_faces_right: bool = _animated or visuals == null or visuals.default_facing_right
		_sprite.flip_h = (not _facing_right) if art_faces_right else _facing_right
		if _animated:
			# 플립하면 캐릭터가 프레임 우측으로 가므로 보정 부호도 뒤집어 origin 유지.
			_sprite.offset.x = (-_CHAR_OFFSET_X if _sprite.flip_h else _CHAR_OFFSET_X)


# ── 레거시(CharacterVisuals) ──
func set_visuals(v: CharacterVisuals) -> void:
	visuals = v
	if _animated:
		return  # 시트 모드에선 무시(틴트만 유효).
	_apply_visuals()
	_refresh_texture()

func _apply_visuals() -> void:
	if _sprite == null:
		return
	if visuals != null:
		_sprite.pixel_size = visuals.pixel_size
		_sprite.modulate = visuals.placeholder_tint
	else:
		_sprite.pixel_size = 0.02
		_sprite.modulate = Color.WHITE
	_base_modulate = _sprite.modulate

func _find_sprite() -> Sprite3D:
	for child in get_children():
		if child is Sprite3D:
			return child
	return null

func _refresh_texture() -> void:
	if _sprite == null:
		return
	var tex: Texture2D = null
	if visuals != null:
		match _state:
			State.IDLE: tex = visuals.idle
			State.WALK: tex = visuals.walk if visuals.walk else visuals.idle
			State.ATTACK: tex = visuals.attack if visuals.attack else visuals.idle
			State.HURT: tex = visuals.hurt if visuals.hurt else visuals.idle
			State.DEATH: tex = visuals.death if visuals.death else visuals.idle
	if tex == null:
		tex = PlaceholderSprite.make(fallback_color)
	_sprite.texture = tex


# ── 피격/무적 연출(두 모드 공통, modulate 기반) ──
func flash(duration: float = 0.16) -> void:
	if _sprite == null:
		return
	var bright: Color = Color(3.0, 3.0, 3.0, _base_modulate.a)
	var t := create_tween()
	t.tween_property(_sprite, "modulate", bright, duration * 0.2)
	t.tween_property(_sprite, "modulate", _base_modulate, duration * 0.8)

func start_iframe_blink(duration: float = 1.0) -> void:
	if _sprite == null:
		return
	if _blink_tween != null and _blink_tween.is_valid():
		_blink_tween.kill()
	var bright: Color = Color(2.5, 2.5, 2.5, 1.0)
	var invisible: Color = Color(_base_modulate.r, _base_modulate.g, _base_modulate.b, 0.0)
	var half_cycle: float = 0.08
	var cycles: int = max(int(duration / (half_cycle * 2.0)), 1)
	_blink_tween = create_tween()
	for i in cycles:
		_blink_tween.tween_property(_sprite, "modulate", bright, half_cycle)
		_blink_tween.tween_property(_sprite, "modulate", invisible, half_cycle)
	_blink_tween.tween_callback(_restore_base_modulate)

func _restore_base_modulate() -> void:
	if _sprite != null:
		_sprite.modulate = _base_modulate

func play_death_then_free(parent_to_free: Node, duration: float = 0.45) -> void:
	set_state(State.DEATH)
	# Kill any in-flight blink tween first — its callback restores
	# _base_modulate (alpha 1) and would fight / undo the death fade, and a
	# blink killed mid-cycle could otherwise leave the sprite stuck invisible
	# on a still-living-looking body.
	if _blink_tween != null and _blink_tween.is_valid():
		_blink_tween.kill()
	if _sprite == null:
		_safe_free(parent_to_free)
		return
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(_sprite, "modulate:a", 0.0, duration)
	t.tween_property(self, "position:y", position.y + 0.6, duration)
	t.tween_property(self, "rotation:z", deg_to_rad(35.0 if _facing_right else -35.0), duration)
	t.chain().tween_callback(_safe_free.bind(parent_to_free))
	# Backup free path: the tween above can stall if the SceneTree is paused
	# (level-up screen) or heavily time-scaled (bullet-time / hitstop) right
	# as the enemy dies — leaving a collision-disabled, faded body that never
	# frees while its HP bar lingers. A scene-timer firing slightly after the
	# tween's nominal duration guarantees the node still dies. Whichever path
	# fires first frees it; _safe_free guards against the double free.
	if is_inside_tree():
		var tree := get_tree()
		if tree != null:
			tree.create_timer(duration + 0.2).timeout.connect(_safe_free.bind(parent_to_free))


## Free `node` exactly once — both the death tween's chained callback and the
## backup scene-timer point here, and either may win the race. The validity +
## queued-for-deletion guard makes the loser a no-op.
func _safe_free(node: Node) -> void:
	if is_instance_valid(node) and not node.is_queued_for_deletion():
		node.queue_free()
