extends Node

# 은혜=트리거×컴포넌트 토대. 구독자는 S4~S5에서 연결.
# 발행 지점만 코어에 배선. 구독자 0이면 emit 은 무해.
# ctx 표준 필드: source(Player) / target(적 노드) / position(Vector3) /
#   charge_frac(일섬 차징 비율) / is_perfect(퍼펙트 닷지 여부).

# ── 이벤트 키 상수 ──
const ON_SLASH_START           := "On_Slash_Start"
const ON_SLASH_END             := "On_Slash_End"
const ON_SLASH_HIT             := "On_Slash_Hit"
const ON_DASH_START            := "On_Dash_Start"
## 회피(대시) '종료' 1회 — t>=1.0 도달 시. ON_DASH_START(시작)와 명확히 구분.
## Player._update_dash 가 emit. 현재 BoonExecutor 구독자 없음(회피-종료 발밑 광역 보은용 예약 키).
const ON_DASH                  := "On_Dash"
const ON_DASH_PASS_ENEMY       := "On_Dash_Pass_Enemy"
const ON_JUST_DODGE            := "On_Just_Dodge"
const ON_SLASH_RIGHT_AFTER_DASH := "On_Slash_Right_After_Dash"
const ON_KILL_VIA_SLASH        := "On_Kill_via_Slash"
const ON_HIT_MARKED_ENEMY      := "On_Hit_Marked_Enemy"
## 표식(slash_mark/참)이 cap(만개)에 도달하는 '전이 순간' 1회. SlashAttack 이 cur<cap → nv==cap
## 전이에서 emit(매 적중 재발화 금지). 현재 BoonExecutor 구독자 없음(만개 전이 보은용 예약 키) —
## 만개 처형은 납도 정산(_settle_enemy)이 marks==cap 으로 판정하므로 이 키 없이도 동작.
const ON_MARK_FULL             := "On_Mark_Full"
## 납도(RB) — slash_mark 정산 트리거. Player._do_sheathe 가 emit, BoonExecutor._on_sheathe 가 구독.
const ON_SHEATHE               := "On_Sheathe"
## 납도 정산(_settle_enemy)이 적을 '죽인' 순간 1회 — epicenter 도미노/baseline 6종 트리거.
## BoonExecutor._settle_enemy 가 take_hit 직후 사망 판정 시 emit(연쇄 중 _in_cascade 면 재발 금지=무한연쇄 차단).
## 일섬 본체 킬(On_Kill_via_Slash)과는 별개 — 납도 정산 사망만 쏨.
const ON_SHEATHE_KILL          := "On_Sheathe_Kill"
# 아래 2종: 결계 기하 판정 후행 — 상수만 정의, emit 금지.
const ON_LINE_INTERSECTION     := "On_Line_Intersection"
const ON_ENCLOSE_AREA          := "On_Enclose_Area"

var _subs: Dictionary = {}

func subscribe(event: String, cb: Callable) -> void:
	if not _subs.has(event):
		_subs[event] = []
	if not _subs[event].has(cb):
		_subs[event].append(cb)

func unsubscribe(event: String, cb: Callable) -> void:
	if _subs.has(event):
		_subs[event].erase(cb)

func emit(event: String, ctx: Dictionary = {}) -> void:
	var arr = _subs.get(event, null)
	if arr == null:
		return
	for cb in arr.duplicate():
		if cb.is_valid():
			cb.call(ctx)
