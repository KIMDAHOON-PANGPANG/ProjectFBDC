class_name HealthComponent
extends Node

signal damaged(amount: int)
signal died
## 아머(경직 게이지)가 전부 깎여 경직에 들어가는 순간 1회 발신. duration=경직 시간.
signal staggered(duration: float)
## 아머 값/최대가 바뀔 때(피격·경직 시작·회복) — HpBar3D 가 파란 아머 칸을 갱신.
signal armor_changed

@export var max_hp: int = 1
## 아머(경직 게이지) 최대치. 0 = 아머 없음(경직 미적용 — 잡몹처럼 한 방 처치).
## 피격마다 데미지만큼 깎이고 0이 되면 경직, 경직이 끝나면 max 로 회복한다.
@export var armor_max: int = 0
## 아머가 0이 됐을 때 들어가는 경직(행동 불가) 시간(초).
@export var stagger_duration: float = 0.4

var hp: int
var armor: int = 0
var _staggered: bool = false
var _stagger_t: float = 0.0

func _ready() -> void:
	hp = max_hp
	armor = armor_max

func setup(new_max: int) -> void:
	max_hp = new_max
	hp = new_max

## 레벨 스케일링 — 스폰 직후 최대 HP 를 extra 만큼 올린다(현재 hp 도 함께 상승).
## Main 이 다중타 위협(엘리트/주술사/슬래머/보스)에 레벨당 +1 적용하는 데 쓴다.
func add_max_hp(extra: int) -> void:
	if extra <= 0:
		return
	max_hp += extra
	hp += extra

## 아머/경직 셋업 — 적 _ready 에서 HP setup 직후 호출(CombatData 가 채운 값 사용).
func setup_armor(new_armor_max: int, new_stagger_duration: float) -> void:
	armor_max = max(new_armor_max, 0)
	armor = armor_max
	stagger_duration = max(new_stagger_duration, 0.05)
	_staggered = false
	_stagger_t = 0.0
	armor_changed.emit()

func take_damage(amount: int = 1) -> void:
	if hp <= 0:
		return
	hp -= amount
	damaged.emit(amount)
	if hp <= 0:
		died.emit()
		return
	# 아머(경직) 처리 — 살아 있을 때만(사망이 경직보다 우선). 아머가 있으면 데미지
	# 만큼 깎고, 0이 되면 경직 진입. 경직 중 추가타는 타이머를 재충전하지 않는다.
	if armor_max > 0 and not _staggered:
		armor -= amount
		if armor <= 0:
			armor = 0
			_staggered = true
			_stagger_t = stagger_duration
			staggered.emit(stagger_duration)
		armor_changed.emit()

func is_alive() -> bool:
	return hp > 0


## Restore `amount` HP up to `max_hp`. Pure no-op if currently dead — we
## don't resurrect via heal (Player.gd's Phoenix path resets hp directly).
## Emits `damaged(0)` so the HpBar3D / HUD refresh on heal (the bar
## listens for damaged to repaint; passing 0 reuses that path without
## adding a parallel `healed` signal).
func heal(amount: int) -> void:
	if hp <= 0:
		return
	if amount <= 0:
		return
	hp = min(hp + amount, max_hp)
	damaged.emit(0)


## 적이 매 프레임(스케일된 delta) 호출 — 경직 타이머 진행, 끝나면 아머 가득 회복.
## 사망 시 적이 physics 를 끄면 호출이 멈추므로 경직도 진행되지 않는다.
func tick_stagger(delta: float) -> void:
	if not _staggered:
		return
	_stagger_t -= delta
	if _stagger_t <= 0.0:
		_staggered = false
		_stagger_t = 0.0
		armor = armor_max  # 경직 종료 → 아머 재충전
		armor_changed.emit()

func is_staggered() -> bool:
	return _staggered

func has_armor_gauge() -> bool:
	return armor_max > 0

func armor_frac() -> float:
	if armor_max <= 0:
		return 0.0
	return clamp(float(armor) / float(armor_max), 0.0, 1.0)

## 사망 시 호출 — 경직 상태 즉시 해제(사망이 경직보다 우선).
func clear_stagger() -> void:
	_staggered = false
	_stagger_t = 0.0

## 외부(마취 비도 AOE)에서 강제 경직(스턴) — 아머와 무관하게 duration 초 정지.
## 적의 _physics_process 가 is_staggered() 로 멈추고 tick_stagger 가 타이머를 깎는다.
## 기존 경직보다 길면 연장(짧으면 유지). 사망한 대상엔 무효.
func force_stagger(duration: float) -> void:
	if hp <= 0 or duration <= 0.0:
		return
	_staggered = true
	_stagger_t = max(_stagger_t, duration)
	staggered.emit(duration)
