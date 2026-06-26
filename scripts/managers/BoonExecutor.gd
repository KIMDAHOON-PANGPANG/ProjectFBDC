extends Node

## 권속 은혜 효과 실행기. Player 자식으로 add_child.
## TriggerBus 이벤트를 구독해 active_boons 의 컴포넌트 효과를 실행한다.
## class_name 금지 — const _BoonExecutorScript := preload(...) + 덕타이핑으로 참조.
##
## M9-S1: M8 요괴(5종) 콘텐츠 전면 철거. 디스패치 엔진(_for_each_effect)·구독 스켈레톤·
## 재사용 FX 헬퍼(_effect_host/_make_disc_mesh)만 보존. M9 카드/효과는 후속 스텝(S3+)에서 채움.

const _BoonSystemScript := preload("res://scripts/managers/BoonSystem.gd")
const _TriggerBusScript := preload("res://scripts/managers/TriggerBus.gd")

## 납도(On_Sheathe) 정산 — 코드 폴백값(데이터 미연결 시). M9-S13: 실제값은 PlayerData @export(sheathe_range/sheathe_dmg)
## 를 _sheathe_range()/_sheathe_dmg() 로 읽는다(authoring 읽기 — 공유 .tres 변형 금지). 미연결/구버전 Player 면 이 폴백.
const _SHEATHE_RANGE := 5.0
const _SHEATHE_DMG := 2
## M9-S12: 표식 만개 cap = 활성 스타일 cap(숏3/미들5/롱7) 단일 소스. _mark_cap() 헬퍼가 Player.get_mark_cap()
## 을 읽는다(미연결 시 5=미들·회귀 0). SlashAttack 부여 cap·적 가시화 cap 과 같은 값을 써야 '쌓이는데 안 만개' 버그가 없다.
## ★각 정산 함수는 진입 시 var cap := _mark_cap() 1회로 폴링 = 한 사이클 내 일관 cap 보장.

var _player: Node = null
var _tb: Node = null
## DEEP_MARK(심도) per_hits 게이팅용 — boon_index → 누적 적중 카운터.
var _hit_counters: Dictionary = {}
## 무납(IAIDO_CHAIN) 거합 미터 — 연속 납도 단계(0~max). _last_chain_msec 로 combo_window 판정.
var _chain_stage: int = 0
var _last_chain_msec: int = 0
## M9-S13: 무납 게이트 — _apply_iaido_chain 이 prospective 로 계산한 다음 단계/now. 실제 회수(total_marks>0)일 때만
## _commit_iaido_chain() 이 _chain_stage/_last_chain_msec 로 확정한다(헛납도면 미커밋 → 미터 정지). _pending_chain=false 면 commit no-op.
var _pending_chain: bool = false
var _pending_chain_stage: int = 0
var _pending_chain_msec: int = 0
## 블러드 FX 변주 카운터 — 정산 적마다 +1, %8 로 핏자국 텍스처 인덱스 선택.
var _blood_counter: int = 0
## 안티-보스 처형선 — 보스 HP 가 max_hp 의 이 비율 이하면 거합+만개 납도로 처형(코드 1차값).
const _BOSS_EXECUTE_THRESHOLD := 0.25

# ══════════════ M9-S6: 납도 처치 연쇄(ON_SHEATHE_KILL) — 무한연쇄 방지가 최우선 correctness ══════════════
## 연쇄(도미노/baseline 처형) 중 _settle_enemy 가 ON_SHEATHE_KILL 을 또 emit 하지 않게 막는 재진입 가드.
## true 동안 _settle_enemy 사망은 새 ON_SHEATHE_KILL 을 쏘지 않는다(=무한 재귀/스택오버플로 차단).
var _in_cascade: bool = false
## 1회 납도가 일으킨 도미노 처형 마릿수 — _CASCADE_KILL_CAP 도달 시 전파 중단. _on_sheathe 시작 시 0.
var _sheathe_kill_count: int = 0
## 연쇄(도미노)로 추가 회수된 표식 합 — 1회 납도 환급(_sheathe_restore)에 합산. _on_sheathe 시작 시 0.
var _cascade_bonus_marks: int = 0
## 체인 뎁스 cap — 1차 처형(depth0)→1뎁스→2뎁스에서 종료(이 값 미만일 때만 전파).
const _CASCADE_DEPTH_CAP := 2
## 1납도당 도미노 처형 마릿수 cap(폭주 방지 안전망).
const _CASCADE_KILL_CAP := 6
## M9-S13: 1납도당 참결(baseline 표식 파문) 발동 횟수 cap — 다중 처치(도미노) 시 표식 살포 인플레 억제(≤2).
const _BASELINE_SPREAD_CAP := 2
## 1회 납도가 일으킨 참결 발동 누계 — _on_sheathe 시작 시 0, _baseline_mark_spread 가 cap 까지만 발동.
var _baseline_spread_count: int = 0
## 연환납도 코드 1차값(boons.json chain_sheathe params 우선, 없으면 이 값).
const _CHAIN_RADIUS_DEFAULT := 3.0
const _CHAIN_COUNT_DEFAULT := 2
const _CHAIN_DEPTH_DEFAULT := 2
# ── M9-S7: 납도 연쇄 카드 1차 — 4 신규 카드 코드 1차값(boons.json params 우선, 없으면 이 값) ──
## 거합도미노(IAI_DOMINO) — 거합+만개 처형 시 주변 만개 적 일제 처형. epicenter 반경/마릿수 cap.
const _IAI_DOMINO_RADIUS_DEFAULT := 4.0
const _IAI_DOMINO_COUNT_DEFAULT := 3
## 참예수확(REAPING_CULL) — 만개 처형 시 주변 미만 표식 적 일괄 정산(marks×단가).
const _REAPING_CULL_RADIUS_DEFAULT := 2.5
const _REAPING_PER_MARK_DEFAULT := 2
## 전파인(MARK_CONTAGION) — 처형 시 최근접 표식 적 1마리에 표식 만개 전염. 1처형당 hops 홉.
const _CONTAGION_HOPS_DEFAULT := 1
# ── M9-S9: 납도 연쇄 카드 2차 — 4 신규 카드 코드 1차값(boons.json params 우선). ★전부 0뎀·take_hit 미호출 ──
## 낙화감(SLOW_FIELD) — 처치 epicenter 잔향 감속장(0뎀·수명 한정·동시≤2·집결만). ★자율 킬/영구 감속 절대 금지.
const _SLOW_FIELD_MULT_DEFAULT := 0.55
const _SLOW_FIELD_LIFETIME_DEFAULT := 1.2
const _SLOW_FIELD_RADIUS_DEFAULT := 3.0
const _SLOW_FIELD_DRIFT_DEFAULT := 0.7
## 동시 활성 감속장 캡 — 초과 시 가장 오래된 것 queue_free(무한 누적/영구 감속 차단).
const _SLOW_FIELD_MAX_ACTIVE := 2
## 적 감속 메타 단명(ms) — 매 프레임 갱신, 장 만료 시 갱신 중단 = 적 메타 자동 정상화(영구 감속 불가).
const _SLOW_FIELD_META_TTL := 150
## 산화진(SCATTER_RING) — 처치 epicenter 척력 링 + 취약표식(vuln_mark, 0뎀).
const _SCATTER_RADIUS_DEFAULT := 3.0
const _SCATTER_SPEED_DEFAULT := 6.0
const _SCATTER_VULN_DEFAULT := 1.3
## 발도충전분출(GAUGE_BURST) — 처치 시 PC 일섬 자원 분출(tier 비례, 0뎀).
const _GAUGE_BURST_BASE_DEFAULT := 0.12
const _GAUGE_BURST_PER_TIER_DEFAULT := 0.06
## 정기흡수(SPIRIT_STACK) — 처치 시 PC 흡수 스택 +1(엘리트/보스 tier_gain 가산, 0뎀).
const _SPIRIT_PER_STACK_DEFAULT := 0.02
const _SPIRIT_MAX_DEFAULT := 8
const _SPIRIT_RELEASE_DEFAULT := 2.0
const _SPIRIT_TIER_GAIN_DEFAULT := 1

## 활성 감속장(낙화감) 노드 추적 — ≤_SLOW_FIELD_MAX_ACTIVE 캡. _process 가 매 프레임 만료/감속/드리프트 처리.
## ★영구 감속 방지: 각 노드 meta('expire_msec') 지나면 free+erase, 비면 _process 즉시 return(평시 비용 0).
var _slow_fields: Array = []

# ── M9-S11 충전류(STYLE_CHARGE) 관통 처형 — 일섬 본체 적중에 편승(자동딜 아님). ★_in_cascade 가드 필수 ──
## 관통천참(PIERCE_REAP) — 풀차지 관통이 적중한 임계 깊이 이상 표식 적을 marks×per_mark 추가피해로 처형.
const _PIERCE_REAP_THRESHOLD_DEFAULT := 3
const _PIERCE_REAP_PER_MARK_DEFAULT := 3
## 천뢰관통(PIERCE_THUNDER) — 적중 적 주변 라인 인접 표식 적까지 같은 판정 흡수 처형(max_targets cap).
const _PIERCE_THUNDER_THRESHOLD_DEFAULT := 2
const _PIERCE_THUNDER_PER_MARK_DEFAULT := 3
const _PIERCE_THUNDER_RADIUS_DEFAULT := 2.5
const _PIERCE_THUNDER_MAX_TARGETS_DEFAULT := 2

# ══════════════ M9-S13: 킬 소스 계측 (주인공 규칙 검증 — 자율 FX 킬 0 확인) ══════════════
## ★설계 불변식: 모든 처치는 일섬 본체 / 납도 정산 / 연쇄 중 하나여야 한다. 자율 FX(감속장·취약표식·자원·연출)는
## take_hit 을 호출하지 않으므로 절대 죽이지 않는다 = _kills_other 0 기대. 집계/표시만 — 게임플레이 무영향.
##  · _kills_by_slash   : 일섬 본체(SlashAttack)가 적을 처치(ON_KILL_via_Slash). _on_kill_via_slash_charge 무조건 +1.
##  · _kills_by_sheathe : 납도 정산(_settle_enemy, _in_cascade==false)이 적을 처치(RB 입력 동기).
##  · _kills_by_cascade : 연쇄(_in_cascade==true 하의 _settle_enemy = 도미노/거합도미노/참예수확/참결파문/
##                        관통천참·천뢰)가 적을 처치.
##  · _kills_other      : 위 3개로 분류 안 된 처치(0 기대 — 분류 누락 감지용).
var _kills_by_slash: int = 0
var _kills_by_sheathe: int = 0
var _kills_by_cascade: int = 0
var _kills_other: int = 0


## ArenaDebug(F1 패널) 폴링용 — 킬 소스 카운터 스냅샷. 게임플레이 무영향(읽기 전용).
func get_kill_source_counts() -> Dictionary:
	return {
		"slash": _kills_by_slash,
		"sheathe": _kills_by_sheathe,
		"cascade": _kills_by_cascade,
		"other": _kills_other,
	}


## baseline 6종 코드 1차값(카드 무관 항상 on — 강한 한정자로 약하게).
const _BL_RIPPLE_RADIUS := 1.5     # 1 납도 파문 — 만개 적 1마리 흘려 처형
const _BL_MARK_RADIUS := 3.0       # 2 참결 — 표식 살포
const _BL_HEAL_RADIUS := 4.0       # 3 환혈 — PC 회복
const _BL_HEAL_TRASH := 1          # 환혈 잡몹(tier0)
const _BL_HEAL_BIG := 3            # 환혈 엘리트/보스(tier>0)
const _BL_GEM_RADIUS := 4.0        # 5 혼백 소집 — ExpGem 호밍


func setup(player: Node) -> void:
	_player = player
	_tb = get_node_or_null("/root/TriggerBus")
	if _tb == null:
		return
	# M9-S3: 납도 정산(발도/거합/환원 통합) + 일섬 적중(심도) 구독.
	_tb.call("subscribe", _TriggerBusScript.ON_SHEATHE, _on_sheathe)
	_tb.call("subscribe", _TriggerBusScript.ON_SLASH_HIT, _on_slash_hit_deepmark)
	# M9-S6: 납도 정산 사망(epicenter) → 도미노 재정렬 + baseline 6종.
	_tb.call("subscribe", _TriggerBusScript.ON_SHEATHE_KILL, _on_sheathe_kill)
	# M9-S11: 충전류 여운일섬(CHARGE_AFTERGLOW) — 일섬 처치 시 다음 차지 가속 + 자원 환급.
	_tb.call("subscribe", _TriggerBusScript.ON_KILL_VIA_SLASH, _on_kill_via_slash_charge)
	# M9-T6: 보조(support) — 회피 종료(ON_DASH) / 일섬 종료(ON_SLASH_END) 구독. Player 가 이미 양 지점 emit.
	_tb.call("subscribe", _TriggerBusScript.ON_DASH, _on_dash_support)
	_tb.call("subscribe", _TriggerBusScript.ON_SLASH_END, _on_slash_end_support)


func _exit_tree() -> void:
	if _tb != null:
		_tb.call("unsubscribe", _TriggerBusScript.ON_SHEATHE, _on_sheathe)
		_tb.call("unsubscribe", _TriggerBusScript.ON_SLASH_HIT, _on_slash_hit_deepmark)
		_tb.call("unsubscribe", _TriggerBusScript.ON_SHEATHE_KILL, _on_sheathe_kill)
		_tb.call("unsubscribe", _TriggerBusScript.ON_KILL_VIA_SLASH, _on_kill_via_slash_charge)
		_tb.call("unsubscribe", _TriggerBusScript.ON_DASH, _on_dash_support)
		_tb.call("unsubscribe", _TriggerBusScript.ON_SLASH_END, _on_slash_end_support)
	# 영구 슬로우 방지 — 셧다운 중 납도 슬로우가 걸려 있었어도 강제 정상화.
	if not is_equal_approx(Engine.time_scale, 1.0):
		Engine.time_scale = 1.0
	# M9-S9 낙화감 감속장 정리 — 셧다운 시 잔류 노드 free(누수/영구 감속 갱신원 차단). 적 메타는 150ms 단명이라 자동 정상화.
	for f in _slow_fields:
		if is_instance_valid(f):
			f.queue_free()
	_slow_fields.clear()


# ══════════════ M9-S12: 표식 만개 cap 단일 소스 ══════════════

## 활성 스타일 표식 cap — Player.get_mark_cap() 폴링(숏3/미들5/롱7). 미연결/구버전 Player 면 5(미들·회귀 0).
## ★정산 함수 진입 시 1회 호출해 지역 var cap 에 담아 쓴다(한 사이클 내 일관). SlashAttack 부여·적 가시화와 같은 값.
func _mark_cap() -> int:
	if _player != null and is_instance_valid(_player) and _player.has_method("get_mark_cap"):
		return int(_player.call("get_mark_cap"))
	return 5


## 납도 정산 사거리 — PlayerData.sheathe_range(authoring) 읽기. 미연결/구버전이면 코드 폴백(_SHEATHE_RANGE).
func _sheathe_range() -> float:
	if _player != null and is_instance_valid(_player) and "data" in _player and _player.data != null and "sheathe_range" in _player.data:
		return float(_player.data.sheathe_range)
	return _SHEATHE_RANGE


## 납도 미만 표식 단가 — PlayerData.sheathe_dmg(authoring) 읽기. 미연결/구버전이면 코드 폴백(_SHEATHE_DMG).
func _sheathe_dmg() -> int:
	if _player != null and is_instance_valid(_player) and "data" in _player and _player.data != null and "sheathe_dmg" in _player.data:
		return int(_player.data.sheathe_dmg)
	return _SHEATHE_DMG


# ══════════════ 납도(On_Sheathe) 정산 — slash_mark 거두기 ══════════════

## RB 납도 시 호출 — sheathe_range 내 slash_mark>0 적을 거둔다. 만개(>=cap, 보스 제외)=처형,
## 미만 또는 보스=marks×sheathe_dmg 피해. 정산 후 그 적 표식 0. 거둔 총합으로 PC 자원 환급.
## 표식 적 0이면 total_marks==0 → 환급 없음(헛납도 — 모션은 Player._do_sheathe 에서 이미 남).
## 죽이는 경로는 여기 take_hit 와 일섬 본체뿐 — 자율 추적·자동 정산 없음(RB 입력 동기).
func _on_sheathe(_ctx: Dictionary) -> void:
	if not is_inside_tree() or _player == null or not is_instance_valid(_player):
		return
	if not (_player is Node3D):
		return
	# M9-S6: 매 납도 1회 — 도미노 처치 카운터/환급 보너스 리셋(연쇄 cap 게이트). _in_cascade 는 항상 false 베이스.
	_sheathe_kill_count = 0
	_cascade_bonus_marks = 0
	_in_cascade = false
	# M9-S13: 참결 발동 횟수 리셋 — 이 납도가 일으킨 다중 처치에서 표식 살포를 _BASELINE_SPREAD_CAP 회로 제한.
	_baseline_spread_count = 0
	var origin: Vector3 = (_player as Node3D).global_position

	# ── 이 한 번의 납도에 적용될 배율을 active_boons 스캔으로 산출 ──
	var range_eff: float = _sheathe_range()
	var dmg_bonus: int = 0          # 발도(STYLE_IAIDO) — 표식 단가 가산
	var dmg_mult: float = 1.0       # 거합 — settle 곱
	var refund_mult: float = 1.0    # 거합/환원 — 환급 곱
	var heat_extra: float = 0.0     # 환원 — marks당 추가 열
	var hp_extra: float = 0.0       # 환원 — marks당 추가 HP
	var full_collect_mult: float = 1.0  # 환원 — 만개 회수 환급 가중
	var do_perfect_fx: bool = false

	# 발도(STYLE_IAIDO) — 회수 범위/단가 강화.
	_for_each_effect("Passive", "STYLE_IAIDO", func(_i, params):
		range_eff += float(params.get("sheathe_range_bonus", 0.0))
		dmg_bonus += int(params.get("sheathe_dmg_bonus", 0))
	)
	# 거합(IAIDO_PERFECT) — 일섬 착지 직후 perfect 윈도우 안 납도면 증폭.
	var is_perfect: bool = false
	_for_each_effect("On_Sheathe", "IAIDO_PERFECT", func(_i, params):
		var window: float = float(params.get("perfect_window", 0.25))
		if _is_perfect_sheathe(window):
			range_eff *= float(params.get("range_mult", 1.0))
			dmg_mult *= float(params.get("settle_mult", 1.0))
			refund_mult *= float(params.get("refund_mult", 1.0))
			do_perfect_fx = true
			is_perfect = true
	)
	# 환원(SHEATHE_REFUND) — 환급량 증폭 + 만개 회수 환원 가중.
	_for_each_effect("On_Sheathe", "SHEATHE_REFUND", func(_i, params):
		heat_extra += float(params.get("heat_per_mark_extra", 0.0))
		hp_extra += float(params.get("hp_per_mark_extra", 0.0))
		full_collect_mult = max(full_collect_mult, float(params.get("full_collect_mult", 1.0)))
	)
	# 무납(IAIDO_CHAIN) — 거합 미터: combo_window 안 연속 납도면 단계↑, 단계당 회수범위/환원 누진.
	# M9-S13: 미터 누진(commit)은 '실제 회수가 일어난 납도'에만 — 여기선 prospective 배율만 적용(범위/환원),
	#         실제 _chain_stage/_last_chain_msec 갱신은 아래 total_marks>0 확인 후 _commit_iaido_chain() 에서.
	#         헛납도(거둔 것 0)는 _commit 미호출 → 미터 안 오름.
	_apply_iaido_chain(func(stage_mult):
		range_eff *= stage_mult
		refund_mult *= stage_mult
	)

	# ── 1차 정산 패스: sheathe_range 내 표식 적 거두기. 처형(만개·비보스) 적은 위치 기록(도미노/피니셔). ──
	# M9-S12 cap 폴링 1회 — 이 정산 사이클 내내 같은 cap(만개 판정 일관). SlashAttack 부여 cap 과 동일.
	var cap: int = _mark_cap()
	var total_marks: int = 0
	var executed_pts: Array = []   # SHEATHE_DOMINO 전파 기점 + FINISHER 발동 게이트
	var settled: Array = []        # 이미 거둔 적(도미노 중복 방지)
	# 'enemies' 그룹에 보스 포함(Boss._ready 가 enemies+boss 둘 다 가입) — 단일 순회로 충분.
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == null or not is_instance_valid(e) or not (e is Node3D):
			continue
		var marks: int = int(e.get_meta("slash_mark", 0))
		if marks <= 0:
			continue
		if (e as Node3D).global_position.distance_to(origin) > range_eff:
			continue
		# 만개+비보스(처형) 적의 표식은 환원 full_collect_mult 로 가중해 환급에 반영.
		var is_full: bool = marks >= cap and not e.is_in_group("boss")
		if is_full:
			total_marks += int(round(float(marks) * full_collect_mult))
			executed_pts.append((e as Node3D).global_position)
		else:
			total_marks += marks
		settled.append(e)
		_settle_enemy(e, marks, dmg_mult, dmg_bonus, is_perfect)

	# ── 연환납도(SHEATHE_DOMINO) 재정렬(M9-S6): 1차 패스의 _settle_enemy 가 만개 처형 시
	# ON_SHEATHE_KILL 을 쏘고, _on_sheathe_kill 핸들러가 epicenter 기준 도미노를 reactively 수행한다.
	# 도미노로 거둔 표식 합은 _cascade_bonus_marks 로 누적돼 여기서 환급에 합산(기존 batch 호출 대체). ──
	total_marks += _cascade_bonus_marks

	# M9-S13: 무납 미터 누진 — '실제 회수가 일어난 납도'에만 commit(헛납도는 미터 정지). prospective 배율은 위에서 이미 적용됨.
	if total_marks > 0:
		_commit_iaido_chain()

	# 거둔 표식이 있으면 PC 자원 환급(열/HP — 환원·거합·미터 배율 반영).
	if total_marks > 0 and _player.has_method("_sheathe_restore"):
		_player.call("_sheathe_restore", total_marks, heat_extra, hp_extra, refund_mult)

	# 역수(IAIDO_HASTE) — 납도 성공(표식 거둠) 시 다음 일섬 가속 + 대시 거리.
	if total_marks > 0:
		_for_each_effect("On_Sheathe", "IAIDO_HASTE", func(_i, params):
			if _player.has_method("apply_iaido_haste"):
				_player.call("apply_iaido_haste", float(params.get("haste_pct", 0.0)), float(params.get("dash_bonus", 0.0)))
		)

	# M9-T6 수확의 인력(SUPPORT_SHEATHE_MAGNET, iaido) — 납도마다 epicenter 반경 젬 force_home + 일시 자석 반경↑. 0뎀.
	_support_sheathe_magnet(origin)

	# 거합일도(IAIDO_FINISHER) — 거합+만개 처형이 있었던 납도면 _aim_dir 로 추가 일섬 발사.
	if is_perfect and not executed_pts.is_empty():
		_for_each_effect("On_Sheathe", "IAIDO_FINISHER", func(_i, params):
			if _player.has_method("spawn_finisher_slash"):
				_player.call("spawn_finisher_slash", max(1, int(params.get("extra_slashes", 1))))
		)

	# 거합 성공 연출 — 흰 섬광(데미지 파이프와 독립).
	if do_perfect_fx:
		_spawn_perfect_flash(origin)
	## 납도 연출 — 거둔 게 있을 때만 슬로우+줌인(헛납도는 연출 없음). is_perfect 면 더 깊게.
	if total_marks > 0:
		_sheathe_slowmo(is_perfect)
		_sheathe_zoom(is_perfect)



## 거합 perfect 판정 — 마지막 일섬 착지 후 window(s) 이내 납도인가.
func _is_perfect_sheathe(window: float) -> bool:
	if _player == null or not _player.has_method("get_last_slash_end_msec"):
		return false
	var last: int = int(_player.call("get_last_slash_end_msec"))
	if last <= 0:
		return false
	var dt_ms: int = Time.get_ticks_msec() - last
	return dt_ms >= 0 and dt_ms <= int(round(window * 1000.0))


## 표식 적 1마리 정산 — 만개+비보스=처형(즉사), 그 외(미만 또는 보스)=marks×피해. 정산 후 표식 0.
## dmg_bonus = 발도 단가 가산, dmg_mult = 거합 정산 곱(만개 처형엔 미적용).
## is_perfect = 거합 납도 여부 — 보스 안티-보스 처형선(저HP+거합+만개) 게이트.
func _settle_enemy(e: Node, marks: int, dmg_mult: float = 1.0, dmg_bonus: int = 0, is_perfect: bool = false) -> void:
	# 블러드 FX 위치 + ON_SHEATHE_KILL epicenter — take_hit(사망 free) '직전'에 캡처.
	var blood_pos: Vector3 = (e as Node3D).global_position if e is Node3D else Vector3.ZERO
	if not e.has_method("take_hit"):
		e.set_meta("slash_mark", 0)
		return
	var is_boss: bool = e.is_in_group("boss")
	# tier 분류 — 보스2 / 엘리트1 / 잡몹0 (group 우선순위).
	var tier: int = 2 if is_boss else (1 if e.is_in_group("elites") else 0)
	# M9-S12 cap 폴링 1회 — 이 정산 1마리 내 만개 판정 일관(SlashAttack 부여 cap 과 동일).
	var cap: int = _mark_cap()
	# 만개(보스 제외) — epicenter 도미노 자격 게이트.
	var is_full: bool = marks >= cap and not is_boss
	# 처형 여부 산출 — 아래 take_hit 분기와 동일 판정(블러드 크기 결정용).
	var is_exec: bool = (marks >= cap and not is_boss) \
		or (is_boss and marks >= cap and is_perfect and _boss_below_execute_threshold(e))
	if marks >= cap and not is_boss:
		e.call("take_hit", 9999)  # 만개 처형 — 잡몹/엘리트/주술사 즉사
	elif is_boss and marks >= cap and is_perfect and _boss_below_execute_threshold(e):
		# 안티-보스 처형선 — 보스 저HP(≤threshold)에서 거합+만개 납도면 처형.
		e.call("take_hit", 9999)
	else:
		# M9-S9 산화진 취약표식(vuln_mark) — 미만/보스(처형선 미달) 단가에만 ×vuln_mult 가산(만개 9999 처형은 무관).
		var vuln: float = float(e.get_meta("vuln_mark", 1.0))
		var dmg: int = int(round(float(marks * (_sheathe_dmg() + dmg_bonus)) * dmg_mult * max(vuln, 1.0)))
		e.call("take_hit", max(dmg, 1))  # 미만 + 보스(처형선 미달) = (표식×단가)×거합×취약
	# ── take_hit '직후' 사망 판정(SlashAttack._target_is_dead 패턴 복제) ──
	var died: bool = _enemy_is_dead(e)
	# M9-S13 킬 소스 계측 — 납도 정산 사망을 분류(연쇄 중=cascade, 1차=sheathe). 집계만, 게임플레이 무영향.
	if died:
		if _in_cascade:
			_kills_by_cascade += 1
		else:
			_kills_by_sheathe += 1
	# 죽었든 살았든 표식 소거(살아남은 보스는 다시 새겨야 함).
	if is_instance_valid(e):
		e.set_meta("slash_mark", 0)
		# M9-S9 취약표식 1회 소비 — 이 납도에서만 적용(다음 납도엔 새 산화진이 다시 새겨야 함).
		if e.has_meta("vuln_mark"):
			e.remove_meta("vuln_mark")
	# 정산 적마다 블러드 터짐(처형은 크게).
	_spawn_blood(blood_pos, is_exec)
	# ★ 무한연쇄 차단: 연쇄(도미노/baseline) 중에는 ON_SHEATHE_KILL 을 재발하지 않는다.
	# 1차 정산(_in_cascade==false)이 적을 죽였을 때만 epicenter 트리거를 쏜다.
	if died and not _in_cascade and _tb != null:
		_tb.call("emit", _TriggerBusScript.ON_SHEATHE_KILL, {
			"position": blood_pos,
			"victim": e,
			"marks": marks,
			"was_full": is_full,
			"was_boss": is_boss,
			"is_perfect": is_perfect,
			"tier": tier,
			"depth": 0,
		})


## take_hit 직후 사망 판정 — HealthComponent(hp<=0) 우선, 없으면 노드 free / _dead 플래그.
## SlashAttack._target_is_dead 와 동일 의도(정산 사망 게이트 전용).
func _enemy_is_dead(e: Node) -> bool:
	if e == null or not is_instance_valid(e):
		return true
	var hc = e.get_node_or_null("HealthComponent")
	if hc != null and "hp" in hc:
		return int(hc.get("hp")) <= 0
	if "_dead" in e:
		return bool(e._dead)
	return false


## 보스 현재 HP 가 max_hp 의 처형선 비율 이하인가 — HealthComponent(hp/max_hp) 읽기. 못 읽으면 false(보수적).
func _boss_below_execute_threshold(e: Node) -> bool:
	if e == null or not is_instance_valid(e):
		return false
	var hc = e.get_node_or_null("HealthComponent")
	if hc == null:
		return false
	var mx: int = int(hc.get("max_hp")) if "max_hp" in hc else 0
	var cur: int = int(hc.get("hp")) if "hp" in hc else 0
	if mx <= 0:
		return false
	return float(cur) <= float(mx) * _BOSS_EXECUTE_THRESHOLD


# ══════════════ 심도(DEEP_MARK) — 일섬 적중 시 표식 추가 ══════════════

## On_Slash_Hit 구독 — 적중 적에 slash_mark 를 추가로 새긴다(SlashAttack 기본 +1 위에). per_hits 게이팅.
func _on_slash_hit_deepmark(ctx: Dictionary) -> void:
	if not is_inside_tree():
		return
	if not (ctx is Dictionary):
		return
	var target = ctx.get("target", null)
	if target == null or not is_instance_valid(target) or not (target is Node):
		return
	if not (target as Node).has_method("take_hit"):
		return
	_for_each_effect("On_Slash_Hit", "DEEP_MARK", func(i, params):
		var per_hits: int = max(int(params.get("per_hits", 1)), 1)
		var extra: int = max(int(params.get("extra", 1)), 0)
		var c: int = int(_hit_counters.get(i, 0)) + 1
		if c >= per_hits:
			_hit_counters[i] = 0
			if extra > 0:
				var cur: int = int((target as Node).get_meta("slash_mark", 0))
				(target as Node).set_meta("slash_mark", min(cur + extra, _mark_cap()))
		else:
			_hit_counters[i] = c
	)
	# 광인(MARK_SPREAD) — 적중 적 주변 미표식 적 1~2에 표식 1 전파(엘리트 호위 군집 번짐).
	_for_each_effect("On_Slash_Hit", "MARK_SPREAD", func(_i, params):
		_spread_marks_from(target as Node3D, int(params.get("spread_count", 1)), float(params.get("spread_radius", 2.5)))
	)
	# M9-T6 각인의 가속(SUPPORT_MARK_ACCEL) — N타마다 적중 적 표식 +extra(DEEP_MARK 엔진 재사용, per_hits 게이팅, cap 클램프). 0뎀.
	_for_each_effect("On_Slash_Hit", "SUPPORT_MARK_ACCEL", func(i, params):
		var per_hits: int = max(int(params.get("per_hits", 3)), 1)
		var extra: int = max(int(params.get("extra", 1)), 0)
		# DEEP_MARK 과 카운터 충돌 방지 — boon_index 키에 오프셋(별도 누적기). per_hits 도달 시 표식 가산.
		var key: int = i + 100000
		var c: int = int(_hit_counters.get(key, 0)) + 1
		if c >= per_hits:
			_hit_counters[key] = 0
			if extra > 0:
				var cur: int = int((target as Node).get_meta("slash_mark", 0))
				(target as Node).set_meta("slash_mark", min(cur + extra, _mark_cap()))
		else:
			_hit_counters[key] = c
	)
	# ── M9-S11 충전류 관통 처형 — 일섬 본체 적중에 편승(자동딜 아님). ★_in_cascade 가드로 ON_SHEATHE_KILL 재발 차단. ──
	_charge_pierce_reap(target as Node)
	_charge_pierce_thunder(target as Node)


## 관통천참(PIERCE_REAP) — 풀차지 관통이 적중한 적의 slash_mark 가 임계 깊이 이상이면 marks×per_mark
## 추가 피해를 take_hit 으로 가산(처형 의도). ★_in_cascade=true 로 감싸 그 사망이 ON_SHEATHE_KILL 을
## 재발하지 않게(무한연쇄 차단). 일섬 본체가 이미 1차 데미지/표식을 냈으므로 여기선 가산만.
func _charge_pierce_reap(target: Node) -> void:
	if target == null or not is_instance_valid(target) or not target.has_method("take_hit"):
		return
	var has_card: bool = false
	var threshold: int = _PIERCE_REAP_THRESHOLD_DEFAULT
	var per_mark: int = _PIERCE_REAP_PER_MARK_DEFAULT
	_for_each_effect("On_Slash_Hit", "PIERCE_REAP", func(_i, params):
		has_card = true
		threshold = min(threshold, max(1, int(params.get("threshold", _PIERCE_REAP_THRESHOLD_DEFAULT))))
		per_mark = max(per_mark, int(params.get("per_mark", _PIERCE_REAP_PER_MARK_DEFAULT)))
	)
	if not has_card:
		return
	var marks: int = int(target.get_meta("slash_mark", 0))
	if marks < threshold:
		return  # 임계 깊이 미달 — 처형 안 함(약표식 적은 일반 일섬으로만).
	# ★연쇄 진입 — take_hit 사망이 ON_SHEATHE_KILL 재발 안 함.
	var prev: bool = _in_cascade
	_in_cascade = true
	var pos: Vector3 = (target as Node3D).global_position if (target is Node3D) else Vector3.ZERO
	_spawn_perfect_flash(pos)
	target.call("take_hit", max(marks * per_mark, 1))
	# M9-S13 킬 소스 계측 — 관통천참 처형은 연쇄(cascade)로 분류. take_hit 직후 사망 판정.
	if _enemy_is_dead(target):
		_kills_by_cascade += 1
	# 살아남았으면(보스 등) 표식 0 리셋 — 이중 가산 방지.
	if is_instance_valid(target):
		target.set_meta("slash_mark", 0)
	_in_cascade = prev


## 천뢰관통(PIERCE_THUNDER) — 적중 적 주변 radius 내 라인 인접 '임계 표식·비보스' 적까지 max_targets 마리
## 같은 take_hit 판정에 흡수해 처형(marks×per_mark). ★_in_cascade=true 가드 + 마릿수 cap(무한연쇄 차단).
func _charge_pierce_thunder(target: Node) -> void:
	if target == null or not is_instance_valid(target) or not (target is Node3D):
		return
	var has_card: bool = false
	var threshold: int = _PIERCE_THUNDER_THRESHOLD_DEFAULT
	var per_mark: int = _PIERCE_THUNDER_PER_MARK_DEFAULT
	var radius: float = _PIERCE_THUNDER_RADIUS_DEFAULT
	var max_targets: int = _PIERCE_THUNDER_MAX_TARGETS_DEFAULT
	_for_each_effect("On_Slash_Hit", "PIERCE_THUNDER", func(_i, params):
		has_card = true
		threshold = min(threshold, max(1, int(params.get("threshold", _PIERCE_THUNDER_THRESHOLD_DEFAULT))))
		per_mark = max(per_mark, int(params.get("per_mark", _PIERCE_THUNDER_PER_MARK_DEFAULT)))
		radius = max(radius, float(params.get("radius", _PIERCE_THUNDER_RADIUS_DEFAULT)))
		max_targets = max(max_targets, int(params.get("max_targets", _PIERCE_THUNDER_MAX_TARGETS_DEFAULT)))
	)
	if not has_card or radius <= 0.0 or max_targets <= 0:
		return
	var origin: Vector3 = (target as Node3D).global_position
	# 후보 수집 — 적중 적 제외, radius 내 '임계 표식·비보스' 적 가까운 순(사전 수집 — take_hit 중 free 대비).
	var cands: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == null or not is_instance_valid(e) or not (e is Node3D):
			continue
		if e == target:
			continue
		if e.is_in_group("boss"):
			continue  # 보스 면역.
		if int(e.get_meta("slash_mark", 0)) < threshold:
			continue
		var d: float = (e as Node3D).global_position.distance_to(origin)
		if d > radius:
			continue
		cands.append({"e": e, "d": d})
	if cands.is_empty():
		return
	cands.sort_custom(func(a, b): return a["d"] < b["d"])
	# ★연쇄 진입 — take_hit 사망이 ON_SHEATHE_KILL 재발 안 함.
	var prev: bool = _in_cascade
	_in_cascade = true
	var hit: int = 0
	for c in cands:
		if hit >= max_targets:
			break
		var e = c["e"]
		if e == null or not is_instance_valid(e) or not e.has_method("take_hit"):
			continue
		var marks: int = int(e.get_meta("slash_mark", 0))
		if marks < threshold:
			continue
		var p: Vector3 = (e as Node3D).global_position
		_spawn_chain_arc(origin, p)  # 라인 흡수 아크(청백).
		e.call("take_hit", max(marks * per_mark, 1))
		# M9-S13 킬 소스 계측 — 천뢰관통 흡수 처형은 연쇄(cascade)로 분류.
		if _enemy_is_dead(e):
			_kills_by_cascade += 1
		if is_instance_valid(e):
			e.set_meta("slash_mark", 0)
		hit += 1
	_in_cascade = prev


## 여운일섬(CHARGE_AFTERGLOW) — 일섬 처치(ON_KILL_via_Slash) 시 다음 차지 가속 + 자원 환급.
## 충전류 Player 훅(apply_iaido_haste + boon_gauge_burst) 재사용. ★0뎀 PC 자원만(take_hit 미호출).
func _on_kill_via_slash_charge(ctx) -> void:
	if not is_inside_tree() or _player == null or not is_instance_valid(_player):
		return
	if not (ctx is Dictionary):
		return
	# M9-S13 킬 소스 계측 — 일섬 본체 처치(ON_KILL_via_Slash)는 카드 보유 무관 무조건 집계. 게임플레이 무영향.
	_kills_by_slash += 1
	var has_card: bool = false
	var haste: float = 0.0
	var dash_bonus: float = 0.0
	var gauge_frac: float = 0.0
	_for_each_effect("On_Kill_via_Slash", "CHARGE_AFTERGLOW", func(_i, params):
		has_card = true
		haste = max(haste, float(params.get("haste_pct", 0.0)))
		dash_bonus = max(dash_bonus, float(params.get("dash_bonus", 0.0)))
		gauge_frac = max(gauge_frac, float(params.get("gauge_frac", 0.0)))
	)
	# ── M9-T6: 보조 — 일섬 처치(On_Kill_via_Slash) 트리거 3종. 전부 0뎀·take_hit 미호출. ──
	# 여운/발열은 has_card 와 무관하게 자체 카드 보유로 게이트(아래 헬퍼 내부). kpos = 처치 위치(ctx.position, 사망 전 캡처).
	var kpos: Vector3 = ctx.get("position", Vector3.ZERO)
	if kpos == Vector3.ZERO and _player is Node3D:
		kpos = (_player as Node3D).global_position
	_support_kill_vent()          # 여열환수 — 열 식힘(boon_gauge_burst 소량)
	_support_kill_magnet(kpos)    # 혼불자석 — EXP젬 force_home
	_support_kill_afterglow()     # 발도의 여운 — 다음 차지 가속 + 자원 환급

	if not has_card:
		return
	if _player.has_method("apply_iaido_haste"):
		_player.call("apply_iaido_haste", haste, dash_bonus)
	if gauge_frac > 0.0 and _player.has_method("boon_gauge_burst"):
		_player.call("boon_gauge_burst", gauge_frac)
	if _player is Node3D:
		_spawn_perfect_flash((_player as Node3D).global_position)


# ══════════════ M9-T6: 보조(support) 11장 핸들러 — ★전부 0뎀·take_hit 미호출(자율 FX 킬 0) ══════════════
## 검증된 엔진 위임만: SLOW_FIELD(_spawn_slow_field) / DEEP_MARK(set_meta cap 클램프) / force_home(ExpGem) /
## boon_gauge_burst(Player 열·쿨) / CHARGE_AFTERGLOW(apply_iaido_haste + boon_gauge_burst) / 이동·자석 일시 보너스.
## ★ 어떤 핸들러도 적 take_hit 을 부르지 않는다 = ON_SHEATHE_KILL 재발 불가·_in_cascade 무관·주인공 규칙 유지.

## 회피 종료(On_Dash) — 보조 3종(질주잔영장/질주의 기/방열질주) + 충전류 질주표식(style_req=charge).
func _on_dash_support(ctx) -> void:
	if not is_inside_tree() or _player == null or not is_instance_valid(_player):
		return
	if not (ctx is Dictionary):
		return
	var pos: Vector3 = ctx.get("position", Vector3.ZERO)
	if pos == Vector3.ZERO and _player is Node3D:
		pos = (_player as Node3D).global_position
	# 1 질주잔영장(SUPPORT_DASH_FIELD) — 대시 종료 지점 소반경 흡인 감속장(SLOW_FIELD 엔진, 짧은 수명, 0뎀).
	_for_each_effect("On_Dash", "SUPPORT_DASH_FIELD", func(_i, params):
		_spawn_slow_field(pos,
			float(params.get("slow_mult", 0.6)),
			float(params.get("lifetime", 0.7)),
			float(params.get("radius", 2.0)),
			float(params.get("drift", 0.6)))
	)
	# 2 질주의 기(SUPPORT_DASH_HASTE) — 대시 후 duration 동안 이속 +move_pct(Player 일시 보너스).
	_for_each_effect("On_Dash", "SUPPORT_DASH_HASTE", func(_i, params):
		if _player.has_method("boon_add_move_speed"):
			_player.call("boon_add_move_speed", float(params.get("move_pct", 0.18)), float(params.get("duration", 2.5)))
	)
	# 3 방열질주(SUPPORT_DASH_VENT) — 대시마다 열 식힘/쿨 단축(boon_gauge_burst 위임).
	_for_each_effect("On_Dash", "SUPPORT_DASH_VENT", func(_i, params):
		if _player.has_method("boon_gauge_burst"):
			_player.call("boon_gauge_burst", float(params.get("gauge_frac", 0.08)))
	)
	# 4 질주표식(SUPPORT_DASH_MARK, charge) — 대시 경로 반경 적에 표식 +extra(set_meta cap 클램프, max_targets cap, 0뎀).
	_for_each_effect("On_Dash", "SUPPORT_DASH_MARK", func(_i, params):
		_support_dash_mark(pos,
			float(params.get("radius", 1.6)),
			max(int(params.get("extra", 1)), 0),
			max(int(params.get("max_targets", 3)), 0))
	)


## 일섬 종료(On_Slash_End) — 잔심의 호흡(SUPPORT_SLASH_VENT). 일섬 후 열 식힘/쿨 단축(boon_gauge_burst). 0뎀.
func _on_slash_end_support(ctx) -> void:
	if not is_inside_tree() or _player == null or not is_instance_valid(_player):
		return
	if not (ctx is Dictionary):
		return
	_for_each_effect("On_Slash_End", "SUPPORT_SLASH_VENT", func(_i, params):
		if _player.has_method("boon_gauge_burst"):
			_player.call("boon_gauge_burst", float(params.get("gauge_frac", 0.06)))
	)


## 집결의 잔향(SUPPORT_GATHER_FIELD) — 납도 처치 지점 흡인 감속장(SLOW_FIELD 엔진 위임, 0뎀·동시≤2).
func _support_gather_field(epicenter: Vector3) -> void:
	_for_each_effect("On_Sheathe_Kill", "SUPPORT_GATHER_FIELD", func(_i, params):
		_spawn_slow_field(epicenter,
			float(params.get("slow_mult", 0.6)),
			float(params.get("lifetime", 1.0)),
			float(params.get("radius", 2.4)),
			float(params.get("drift", 0.7)))
	)


## 여열환수(SUPPORT_KILL_VENT) — 일섬 처치마다 열 식힘(boon_gauge_burst 소량). 0뎀.
func _support_kill_vent() -> void:
	if _player == null or not is_instance_valid(_player) or not _player.has_method("boon_gauge_burst"):
		return
	var frac: float = 0.0
	_for_each_effect("On_Kill_via_Slash", "SUPPORT_KILL_VENT", func(_i, params):
		frac = max(frac, float(params.get("gauge_frac", 0.05)))
	)
	if frac > 0.0:
		_player.call("boon_gauge_burst", frac)


## 혼불자석(SUPPORT_KILL_MAGNET) — 처치 지점 반경 내 EXP젬 force_home(0뎀).
func _support_kill_magnet(epicenter: Vector3) -> void:
	var radius: float = 0.0
	_for_each_effect("On_Kill_via_Slash", "SUPPORT_KILL_MAGNET", func(_i, params):
		radius = max(radius, float(params.get("radius", 4.0)))
	)
	if radius <= 0.0:
		return
	for g in get_tree().get_nodes_in_group("exp_gems"):
		if g == null or not is_instance_valid(g) or not (g is Node3D):
			continue
		if (g as Node3D).global_position.distance_to(epicenter) > radius:
			continue
		if g.has_method("force_home"):
			g.call("force_home")


## 발도의 여운(SUPPORT_KILL_AFTERGLOW, charge) — 일섬 처치마다 다음 차지 가속 + 대시 거리 + 자원 환급(0뎀, CHARGE_AFTERGLOW 패턴).
func _support_kill_afterglow() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var has_card: bool = false
	var haste: float = 0.0
	var dash_bonus: float = 0.0
	var gauge_frac: float = 0.0
	_for_each_effect("On_Kill_via_Slash", "SUPPORT_KILL_AFTERGLOW", func(_i, params):
		has_card = true
		haste = max(haste, float(params.get("haste_pct", 0.0)))
		dash_bonus = max(dash_bonus, float(params.get("dash_bonus", 0.0)))
		gauge_frac = max(gauge_frac, float(params.get("gauge_frac", 0.0)))
	)
	if not has_card:
		return
	if _player.has_method("apply_iaido_haste"):
		_player.call("apply_iaido_haste", haste, dash_bonus)
	if gauge_frac > 0.0 and _player.has_method("boon_gauge_burst"):
		_player.call("boon_gauge_burst", gauge_frac)


## 수확의 인력(SUPPORT_SHEATHE_MAGNET, iaido) — 납도 origin 반경 젬 force_home + duration 동안 자석 반경 ×mult(0뎀).
func _support_sheathe_magnet(origin: Vector3) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var has_card: bool = false
	var radius: float = 0.0
	var magnet_mult: float = 1.0
	var duration: float = 0.0
	_for_each_effect("On_Sheathe", "SUPPORT_SHEATHE_MAGNET", func(_i, params):
		has_card = true
		radius = max(radius, float(params.get("radius", 4.0)))
		magnet_mult = max(magnet_mult, float(params.get("magnet_mult", 1.6)))
		duration = max(duration, float(params.get("duration", 2.0)))
	)
	if not has_card:
		return
	# 즉시 호밍 — origin 반경 내 젬.
	for g in get_tree().get_nodes_in_group("exp_gems"):
		if g == null or not is_instance_valid(g) or not (g is Node3D):
			continue
		if radius > 0.0 and (g as Node3D).global_position.distance_to(origin) > radius:
			continue
		if g.has_method("force_home"):
			g.call("force_home")
	# 일시 자석 반경 가산(Player 런타임 보너스 — permanent exp_magnet_mult 와 별개).
	if magnet_mult > 1.0 and duration > 0.0 and _player.has_method("boon_add_exp_magnet"):
		_player.call("boon_add_exp_magnet", magnet_mult, duration)


## 질주표식(SUPPORT_DASH_MARK, charge) — pos 반경 내 비보스 적 max_targets 마리에 표식 +extra(cap 클램프, 0뎀).
func _support_dash_mark(pos: Vector3, radius: float, extra: int, max_targets: int) -> void:
	if radius <= 0.0 or extra <= 0 or max_targets <= 0:
		return
	var cap: int = _mark_cap()
	# 가까운 순 — pos 반경 내 비보스 적 수집.
	var cands: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == null or not is_instance_valid(e) or not (e is Node3D):
			continue
		if e.is_in_group("boss"):
			continue  # 보스 표식 살포 제외(원천 인플레 방지 — 코어 보존).
		var d: float = (e as Node3D).global_position.distance_to(pos)
		if d > radius:
			continue
		cands.append({"e": e, "d": d})
	if cands.is_empty():
		return
	cands.sort_custom(func(a, b): return a["d"] < b["d"])
	var hit: int = 0
	for c in cands:
		if hit >= max_targets:
			break
		var e = c["e"]
		if e == null or not is_instance_valid(e):
			continue
		var cur: int = int(e.get_meta("slash_mark", 0))
		e.set_meta("slash_mark", min(cur + extra, cap))  # cap 클램프, 0뎀.
		hit += 1


# ══════════════ 광인(MARK_SPREAD) — 표식 전파 ══════════════

## src 주변 radius 내 '미표식'(slash_mark<=0) 적 count 마리에 표식 1 부여(0뎀). 보스 포함(표식만).
func _spread_marks_from(src: Node3D, count: int, radius: float) -> void:
	if src == null or not is_instance_valid(src) or count <= 0 or radius <= 0.0:
		return
	var origin: Vector3 = src.global_position
	var given: int = 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if given >= count:
			break
		if e == null or not is_instance_valid(e) or not (e is Node3D):
			continue
		if e == src:
			continue
		if int(e.get_meta("slash_mark", 0)) > 0:
			continue  # 이미 표식 있으면 스킵(미표식에만 전파).
		if (e as Node3D).global_position.distance_to(origin) > radius:
			continue
		e.set_meta("slash_mark", 1)
		given += 1


# ══════════════ 무납(IAIDO_CHAIN) — 거합 미터 ══════════════

## 연속 납도 단계 갱신 + 단계 보너스 적용. apply_cb.call(stage_mult) 로 회수범위/환원 곱 전달.
## combo_window 안에 다시 납도하면 단계+1(max_stage cap), 넘기면 1단으로 리셋. 단계당 per_stage 누진.
## M9-S13: prospective 계산만 — _chain_stage/_last_chain_msec 를 '여기서 쓰지 않고' 다음 단계를 _pending_* 에 담는다.
## 실제 미터 누진은 회수 확정(total_marks>0) 후 _commit_iaido_chain() 이 한다. 헛납도는 _pending 만 세팅되고 미커밋 → 미터 정지.
func _apply_iaido_chain(apply_cb: Callable) -> void:
	_pending_chain = false
	var has_chain: bool = false
	var per_stage: float = 0.0
	var max_stage: int = 0
	var window_ms: int = 0
	_for_each_effect("On_Sheathe", "IAIDO_CHAIN", func(_i, params):
		has_chain = true
		per_stage = max(per_stage, float(params.get("per_stage", 0.12)))
		max_stage = max(max_stage, int(params.get("max_stage", 4)))
		window_ms = max(window_ms, int(round(float(params.get("combo_window", 2.0)) * 1000.0)))
	)
	if not has_chain:
		return
	var now: int = Time.get_ticks_msec()
	# 다음 단계를 prospective 로 산출(미커밋) — 마지막 '회수된' 납도 기준 combo_window 판정.
	var next_stage: int
	if _last_chain_msec > 0 and (now - _last_chain_msec) <= window_ms:
		next_stage = min(_chain_stage + 1, max_stage)
	else:
		next_stage = 1  # 창 밖/첫 납도 — 1단부터 시작.
	_pending_chain = true
	_pending_chain_stage = next_stage
	_pending_chain_msec = now
	# 단계 보너스 = 1 + per_stage × (stage-1). 1단=무보너스, 단계마다 per_stage 누진. (배율은 prospective 단계로 즉시 적용.)
	var stage_mult: float = 1.0 + per_stage * float(max(next_stage - 1, 0))
	if stage_mult > 1.0:
		apply_cb.call(stage_mult)


## M9-S13: 무납 미터 확정 — 실제 회수가 있었던 납도(total_marks>0)에서만 호출. prospective 단계/시각을 미터에 커밋.
## 헛납도면 호출 안 됨 → _chain_stage/_last_chain_msec 불변(다음 회수 납도가 같은 단계 기준으로 combo 판정).
func _commit_iaido_chain() -> void:
	if not _pending_chain:
		return
	_chain_stage = _pending_chain_stage
	_last_chain_msec = _pending_chain_msec
	_pending_chain = false


# ══════════════ M9-S6: ON_SHEATHE_KILL 핸들러 — epicenter 도미노 재정렬 + baseline 6종 ══════════════

## 납도 정산 사망(epicenter) 1회마다 호출. was_full(만개 처형)이면 연환납도(카드 보유 시) 도미노를
## epicenter 기준으로 1회 전파(★_in_cascade 가드 하에 — ON_SHEATHE_KILL 재발 차단). 이어 baseline 6종
## 항상 발동(카드 무관·강한 한정자로 약하게). baseline 중 take_hit 부르는 건 납도 파문 1마리뿐.
func _on_sheathe_kill(ctx) -> void:
	if not is_inside_tree() or not (ctx is Dictionary):
		return
	var epicenter: Vector3 = ctx.get("position", Vector3.ZERO)
	var was_full: bool = bool(ctx.get("was_full", false))
	var is_perfect: bool = bool(ctx.get("is_perfect", false))
	var tier: int = int(ctx.get("tier", 0))
	var depth: int = int(ctx.get("depth", 0))
	var victim_marks: int = int(ctx.get("marks", 0))

	# ── 연환납도(SHEATHE_DOMINO) — 카드 보유 시에만, epicenter 도미노(뎁스 cap·마릿수 cap). ──
	if was_full and depth < _CASCADE_DEPTH_CAP and _sheathe_kill_count < _CASCADE_KILL_CAP:
		_cascade_domino_from(epicenter, depth, is_perfect)

	# ── M9-S7: 납도 연쇄 카드 4종(카드 보유 시에만). 전부 비재귀 뎁스1 — depth 증가 금지.
	# ★take_hit/_settle 호출 분기(거합도미노/참예수확)는 핸들러 안에서 _in_cascade=true 로 감싸
	#   ON_SHEATHE_KILL 재발(무한재귀)을 차단한다. 전파인/폭심 충전은 take_hit 미호출(set_meta/예약만). ──
	if was_full:
		_on_sheathe_kill_domino_iai(epicenter, is_perfect)   # 1 거합도미노(거합+만개 게이트는 핸들러 안)
		_on_sheathe_kill_reaping(epicenter)                  # 2 참예수확
		_on_sheathe_kill_overcharge(victim_marks)            # 3 폭심 충전
		_on_sheathe_kill_contagion(epicenter)                # 4 전파인

	# ── M9-S9: 납도 연쇄 카드 2차 4종(카드 보유 시에만). ★전부 was_full 무관 = 모든 처치에서 발동.
	#   전부 0뎀·take_hit 미호출(감속·취약표식·자원·스택만) → ON_SHEATHE_KILL 재발 불가·_in_cascade 무관·무한연쇄 불성립. ──
	_on_sheathe_kill_slow_field(epicenter)  # 1 낙화감(잔향 감속장 — 0뎀·수명 한정·동시≤2·집결만)
	_on_sheathe_kill_scatter(epicenter)     # 2 산화진(척력 링 + 취약표식 — 0뎀)
	_on_sheathe_kill_gauge(tier)            # 3 발도충전분출(PC 일섬 자원 분출 — 0뎀)
	_on_sheathe_kill_spirit(tier)           # 4 정기흡수(PC 흡수 스택 — 0뎀)

	# ── M9-T6: 보조 — 집결의 잔향(SUPPORT_GATHER_FIELD). 처치 지점 흡인 감속장(SLOW_FIELD 엔진 위임·0뎀·동시≤2). ──
	_support_gather_field(epicenter)

	# ── baseline 6종 — 항상(카드 무관). 자원 클램프는 각 호출/HealthComponent 가 보장. ──
	_baseline_ripple(epicenter)        # 1 납도 파문
	_baseline_mark_spread(epicenter, tier)  # 2 참결
	_baseline_heal(epicenter, tier)    # 3 환혈
	_baseline_heat_refund(tier)        # 4 잔열 환수
	_baseline_gem_summon(epicenter)    # 5 혼백 소집
	_baseline_echo_slash(epicenter)    # 6 참향


## 연환납도 epicenter 도미노 — epicenter 기준 chain_radius 내 'slash_mark>0' 비보스 적을
## 가까운 순 chain_count 마리 정산. ★_in_cascade=true 로 감싸 그 정산이 ON_SHEATHE_KILL 을
## 재발하지 못하게 하고(무한재귀 차단), visited 로 같은 적 재정산을 막는다. 마릿수 cap 도달 시 중단.
## chain_sheathe 카드 보유 시에만 발동(보존). epicenter→대상 청백 호 더미.
func _cascade_domino_from(epicenter: Vector3, depth: int, is_perfect: bool) -> void:
	# 카드 보유·파라미터 스캔(보유 안 하면 도미노 없음 = baseline 만).
	var has_card: bool = false
	var radius: float = _CHAIN_RADIUS_DEFAULT
	var chain_count: int = _CHAIN_COUNT_DEFAULT
	var depth_cap: int = _CHAIN_DEPTH_DEFAULT
	_for_each_effect("On_Sheathe", "SHEATHE_DOMINO", func(_i, params):
		has_card = true
		radius = max(radius, float(params.get("chain_radius", _CHAIN_RADIUS_DEFAULT)))
		chain_count = max(chain_count, int(params.get("chain_count", _CHAIN_COUNT_DEFAULT)))
		depth_cap = max(depth_cap, int(params.get("depth", _CHAIN_DEPTH_DEFAULT)))
	)
	if not has_card or radius <= 0.0:
		return
	# 뎁스 cap — depth_cap 과 전역 _CASCADE_DEPTH_CAP 중 작은 값으로(안전).
	var eff_depth_cap: int = min(depth_cap, _CASCADE_DEPTH_CAP)
	if depth >= eff_depth_cap:
		return

	# epicenter 기준 후보 수집(slash_mark>0·비보스·거리 내) → 가까운 순 정렬.
	var cands: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == null or not is_instance_valid(e) or not (e is Node3D):
			continue
		if e.is_in_group("boss"):
			continue  # 보스 만개 면역 — 전파·epicenter 자격 제외.
		if int(e.get_meta("slash_mark", 0)) <= 0:
			continue  # 표식 적만 전파(원천 금지).
		var d: float = (e as Node3D).global_position.distance_to(epicenter)
		if d > radius:
			continue
		cands.append({"e": e, "d": d})
	cands.sort_custom(func(a, b): return a["d"] < b["d"])

	# ★ 연쇄 진입 — _in_cascade=true 동안 _settle_enemy 가 ON_SHEATHE_KILL 을 재발하지 않는다.
	var prev_cascade: bool = _in_cascade
	_in_cascade = true
	var spread: int = 0
	for c in cands:
		if spread >= chain_count:
			break
		if _sheathe_kill_count >= _CASCADE_KILL_CAP:
			break
		var e = c["e"]
		if e == null or not is_instance_valid(e):
			continue
		var marks: int = int(e.get_meta("slash_mark", 0))
		if marks <= 0:
			continue  # 그새 다른 전파로 거둬졌으면 스킵(visited 대용).
		var is_full: bool = marks >= _mark_cap()
		_cascade_bonus_marks += marks
		# epicenter→대상 청백 호 더미.
		_spawn_chain_arc(epicenter, (e as Node3D).global_position)
		# 도미노 정산(연쇄 중이라 ON_SHEATHE_KILL 미발). 사망 여부로 다음 뎁스 전파를 수동 발화.
		_settle_enemy(e, marks, 1.0, 0, false)
		_sheathe_kill_count += 1
		spread += 1
		# 다음 뎁스 — 이 처형이 만개였고 cap 미만이면 재귀적으로 한 단계 더(여전히 _in_cascade 하).
		if is_full and (depth + 1) < eff_depth_cap and _sheathe_kill_count < _CASCADE_KILL_CAP:
			_cascade_domino_from((c["e"] as Node3D).global_position if is_instance_valid(c["e"]) else epicenter, depth + 1, is_perfect)
	_in_cascade = prev_cascade


# ══════════════ M9-S7: 납도 연쇄 카드 4종 — 전부 비재귀 뎁스1·_in_cascade 가드·보스 면역 ══════════════

## 1 거합도미노(IAI_DOMINO) — was_full && is_perfect(거합)일 때만 발동. epicenter iai_radius 내
## '만개(slash_mark>=cap)·비보스' 적 전원을 가까운 순 domino_count 마리까지 '한 번에' 일제 처형.
## ★도미노 재귀가 아니라 한 번에(반복문 1회). _in_cascade=true 로 감싸 각 _settle_enemy 처형이
## ON_SHEATHE_KILL 을 재발하지 않게 한다(무한연쇄 차단). _sheathe_kill_count 누적 + _CASCADE_KILL_CAP 안전망.
func _on_sheathe_kill_domino_iai(epicenter: Vector3, is_perfect: bool) -> void:
	if not is_perfect:
		return  # 거합 납도 처형에서만 발동.
	var has_card: bool = false
	var radius: float = _IAI_DOMINO_RADIUS_DEFAULT
	var count: int = _IAI_DOMINO_COUNT_DEFAULT
	_for_each_effect("On_Sheathe", "IAI_DOMINO", func(_i, params):
		has_card = true
		radius = max(radius, float(params.get("iai_radius", _IAI_DOMINO_RADIUS_DEFAULT)))
		count = max(count, int(params.get("domino_count", _IAI_DOMINO_COUNT_DEFAULT)))
	)
	if not has_card or radius <= 0.0 or count <= 0:
		return
	var cap: int = _mark_cap()  # M9-S12 만개 판정 cap 폴링 1회.
	# epicenter 기준 '만개·비보스' 후보 수집 → 가까운 순 정렬.
	var cands: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == null or not is_instance_valid(e) or not (e is Node3D):
			continue
		if e.is_in_group("boss"):
			continue  # 보스 만개 면역.
		if int(e.get_meta("slash_mark", 0)) < cap:
			continue  # 만개만.
		var d: float = (e as Node3D).global_position.distance_to(epicenter)
		if d > radius:
			continue
		cands.append({"e": e, "d": d})
	cands.sort_custom(func(a, b): return a["d"] < b["d"])
	# ★연쇄 진입 — _in_cascade=true 동안 _settle_enemy 처형이 ON_SHEATHE_KILL 재발 안 함.
	var prev: bool = _in_cascade
	_in_cascade = true
	var spread: int = 0
	for c in cands:
		if spread >= count:
			break
		if _sheathe_kill_count >= _CASCADE_KILL_CAP:
			break
		var e = c["e"]
		if e == null or not is_instance_valid(e):
			continue
		var marks: int = int(e.get_meta("slash_mark", 0))
		if marks < cap:
			continue  # 그새 다른 전파로 거둬졌으면 스킵(visited 대용).
		_cascade_bonus_marks += marks
		_spawn_perfect_flash((e as Node3D).global_position)  # 흰 섬광 재사용.
		_settle_enemy(e, marks, 1.0, 0, false)  # 만개라 9999 처형(연쇄 중 = 재발 안 함).
		_sheathe_kill_count += 1
		spread += 1
	_in_cascade = prev


## 2 참예수확(REAPING_CULL) — was_full 게이트. epicenter cull_radius 내 '미만 표식(0<marks<cap)·비보스'
## 적 전원에 marks×per_mark_dmg 피해 일괄 정산(처형 의도 아님 — 죽으면 OK, 살았으면 표식 0 리셋).
## ★_in_cascade=true 로 감싸 take_hit 사망이 ON_SHEATHE_KILL 재발 안 하게(무한연쇄 차단). 뎁스1 비재귀.
func _on_sheathe_kill_reaping(epicenter: Vector3) -> void:
	var has_card: bool = false
	var radius: float = _REAPING_CULL_RADIUS_DEFAULT
	var per_mark: int = _REAPING_PER_MARK_DEFAULT
	_for_each_effect("On_Sheathe", "REAPING_CULL", func(_i, params):
		has_card = true
		radius = max(radius, float(params.get("cull_radius", _REAPING_CULL_RADIUS_DEFAULT)))
		per_mark = max(per_mark, int(params.get("per_mark_dmg", _REAPING_PER_MARK_DEFAULT)))
	)
	if not has_card or radius <= 0.0:
		return
	var cap: int = _mark_cap()  # M9-S12 만개 판정 cap 폴링 1회.
	# 후보 수집 — 미만 표식(0<marks<cap)·비보스·반경 내. (take_hit 중 free 가능성 대비 사전 수집.)
	var targets: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == null or not is_instance_valid(e) or not (e is Node3D):
			continue
		if e.is_in_group("boss"):
			continue  # 보스 면역.
		var marks: int = int(e.get_meta("slash_mark", 0))
		if marks <= 0 or marks >= cap:
			continue  # 미만 표식만(표식0·만개 제외).
		if (e as Node3D).global_position.distance_to(epicenter) > radius:
			continue
		targets.append(e)
	if targets.is_empty():
		return
	# ★연쇄 진입 — take_hit 사망이 ON_SHEATHE_KILL 재발 안 함.
	var prev: bool = _in_cascade
	_in_cascade = true
	for e in targets:
		if e == null or not is_instance_valid(e) or not e.has_method("take_hit"):
			continue
		var marks: int = int(e.get_meta("slash_mark", 0))
		if marks <= 0 or marks >= cap:
			continue  # 그새 상태 변동 시 재확인.
		var pos: Vector3 = (e as Node3D).global_position
		_spawn_perfect_flash(pos)  # 노랑→흰 호 더미(재사용).
		e.call("take_hit", max(marks * per_mark, 1))
		# M9-S13 킬 소스 계측 — 참예수확이 미만 표식 적을 죽이면 연쇄(cascade)로 분류. take_hit 직후 사망 판정.
		if _enemy_is_dead(e):
			_kills_by_cascade += 1
		# 처형 아님 — 살아남았으면 표식 0 리셋(이중 정산 방지).
		if is_instance_valid(e):
			e.set_meta("slash_mark", 0)
	_in_cascade = prev


## 3 폭심 충전(EPICENTER_OVERCHARGE) — was_full 게이트. 죽은 적 marks 비례 무관(1차값 고정 배수)로
## Player 에 '다음 일섬 1발' 대버스트를 예약 위임(reserve_next_slash_burst). take_hit/_settle 미호출이라
## 연쇄 무관(_in_cascade 불필요). 충전 디스크 더미 = _spawn_chain_arc 재사용.
func _on_sheathe_kill_overcharge(_victim_marks: int) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if not _player.has_method("reserve_next_slash_burst"):
		return
	var has_card: bool = false
	var range_mult: float = 1.5
	var width_mult: float = 1.4
	var heat_refund: float = 0.15
	var window: float = 4.0
	_for_each_effect("On_Sheathe", "EPICENTER_OVERCHARGE", func(_i, params):
		has_card = true
		range_mult = max(range_mult, float(params.get("range_mult", 1.5)))
		width_mult = max(width_mult, float(params.get("width_mult", 1.4)))
		heat_refund = max(heat_refund, float(params.get("heat_refund", 0.15)))
		window = max(window, float(params.get("window", 4.0)))
	)
	if not has_card:
		return
	_player.call("reserve_next_slash_burst", range_mult, width_mult, heat_refund, window)
	# 충전 디스크 더미(PC 발밑 청백 디스크) — 신규 노드 없이 _spawn_chain_arc 제자리 링 재사용.
	if _player is Node3D:
		var p: Vector3 = (_player as Node3D).global_position
		_spawn_chain_arc(p, p)


## 4 전파인(MARK_CONTAGION) — was_full 게이트. epicenter 최근접 '이미 표식 있는(slash_mark>0)·비보스'
## 적을 hops 마리(각 홉 서로 다른 적, visited 중복 방지)에 표식 즉시 만개로 전염(set_meta cap). 0뎀·처형 안 함.
## take_hit 미호출이라 ON_SHEATHE_KILL 재발 불가(전염이 또 전염 안 함 — hops 루프 1회 비재귀로 뎁스≤1 보장).
func _on_sheathe_kill_contagion(epicenter: Vector3) -> void:
	var has_card: bool = false
	var hops: int = _CONTAGION_HOPS_DEFAULT
	_for_each_effect("On_Sheathe", "MARK_CONTAGION", func(_i, params):
		has_card = true
		hops = max(hops, int(params.get("hops", _CONTAGION_HOPS_DEFAULT)))
	)
	if not has_card or hops <= 0:
		return
	var cap: int = _mark_cap()  # M9-S12 만개 판정/전염 cap 폴링 1회.
	var visited: Dictionary = {}
	for _h in range(hops):
		# epicenter 최근접 미방문 '표식 있는·비보스' 적 1마리.
		var best: Node = null
		var best_d: float = INF
		for e in get_tree().get_nodes_in_group("enemies"):
			if e == null or not is_instance_valid(e) or not (e is Node3D):
				continue
			if e.is_in_group("boss"):
				continue  # 보스 면역.
			if visited.has(e.get_instance_id()):
				continue
			var marks: int = int(e.get_meta("slash_mark", 0))
			if marks <= 0 or marks >= cap:
				continue  # 표식 있는(0<marks<cap) 적만 — 표식0·이미 만개 제외.
			var d: float = (e as Node3D).global_position.distance_to(epicenter)
			if d >= best_d:
				continue
			best_d = d
			best = e
		if best == null:
			break  # 더 전염할 대상 없음.
		best.set_meta("slash_mark", cap)  # 즉시 만개 전염(0뎀, 처형 안 함).
		visited[best.get_instance_id()] = true
		_spawn_chain_arc(epicenter, (best as Node3D).global_position)  # 전염 호.


# ══════════════ M9-S9: 납도 연쇄 카드 2차 4종 — ★전부 0뎀·take_hit 미호출(무한연쇄 불성립) ══════════════

## 1 낙화감(SLOW_FIELD) — epicenter 에 잔향 감속장 노드 1개 생성(수명 lifetime, 동시 ≤_SLOW_FIELD_MAX_ACTIVE).
## ★자율-tick 경계 엄수: 적을 죽이지 않음(take_hit 미호출). _process 가 장 수명 동안만 반경 적에 감속 메타
## (TTL 150ms 단명)를 매 프레임 갱신 + epicenter 쪽 미세 드리프트(집결). 장 만료 시 free → 갱신 중단 = 적 자동 정상화.
## ★영구 감속 불가: 메타 단명 + 노드 expire_msec 수명 + 동시 ≤2 캡(초과 시 가장 오래된 것 free).
func _on_sheathe_kill_slow_field(epicenter: Vector3) -> void:
	var has_card: bool = false
	var slow_mult: float = _SLOW_FIELD_MULT_DEFAULT
	var lifetime: float = _SLOW_FIELD_LIFETIME_DEFAULT
	var radius: float = _SLOW_FIELD_RADIUS_DEFAULT
	var drift: float = _SLOW_FIELD_DRIFT_DEFAULT
	_for_each_effect("On_Sheathe", "SLOW_FIELD", func(_i, params):
		has_card = true
		# slow_mult 는 작을수록 강함 — 최솟값(가장 강한 감속) 채택. 나머지는 최댓값.
		slow_mult = min(slow_mult, float(params.get("slow_mult", _SLOW_FIELD_MULT_DEFAULT)))
		lifetime = max(lifetime, float(params.get("lifetime", _SLOW_FIELD_LIFETIME_DEFAULT)))
		radius = max(radius, float(params.get("radius", _SLOW_FIELD_RADIUS_DEFAULT)))
		drift = max(drift, float(params.get("drift", _SLOW_FIELD_DRIFT_DEFAULT)))
	)
	if not has_card or radius <= 0.0 or lifetime <= 0.0:
		return
	_spawn_slow_field(epicenter, slow_mult, lifetime, radius, drift)


## M9-T6: 재사용 감속장 엔진 — epicenter 에 흡인 감속장 1개 생성(0뎀·동시 ≤_SLOW_FIELD_MAX_ACTIVE·수명 한정).
## SLOW_FIELD(낙화감)/SUPPORT_GATHER_FIELD(집결의 잔향)/SUPPORT_DASH_FIELD(질주잔영장) 공용.
## ★take_hit 미호출 — 적을 죽이지 않음. _process 가 수명 동안 반경 적에 감속 메타(150ms 단명) + epicenter 드리프트.
func _spawn_slow_field(epicenter: Vector3, slow_mult: float, lifetime: float, radius: float, drift: float) -> void:
	if radius <= 0.0 or lifetime <= 0.0:
		return
	slow_mult = clampf(slow_mult, 0.1, 1.0)
	# ── 동시 활성 ≤_SLOW_FIELD_MAX_ACTIVE 캡 — 초과 시 가장 오래된 것 제거(무한 누적/영구 감속 차단). ──
	while _slow_fields.size() >= _SLOW_FIELD_MAX_ACTIVE:
		var old = _slow_fields.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var host := _effect_host()
	if host == null:
		return
	# 감속장 노드(시각 더미 디스크 + 파라미터 메타). _process 가 메타 읽어 반경 적 감속+드리프트.
	var field := Node3D.new()
	field.top_level = true
	field.global_position = epicenter
	field.set_meta("slow_mult", slow_mult)
	field.set_meta("radius", radius)
	field.set_meta("drift", drift)
	field.set_meta("expire_msec", Time.get_ticks_msec() + int(round(lifetime * 1000.0)))
	# 보라/청 디스크 더미(_make_disc_mesh 재사용) — scale 펄스 후 페이드(노드 free 는 _process/타이머가).
	var mi := MeshInstance3D.new()
	mi.mesh = _make_disc_mesh(radius)
	mi.position = Vector3(0, 0.05, 0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.55, 0.5, 0.9, 0.35)  # 보라/청 잔향.
	mat.emission_enabled = true
	mat.emission = Color(0.6, 0.55, 1.0)
	mat.emission_energy_multiplier = 1.2
	mi.material_override = mat
	field.add_child(mi)
	host.add_child(field)
	_slow_fields.append(field)
	# 수명 타이머 — 만료 시 free+erase(이중 안전망: _process 도 expire_msec 로 정리). ignore_time_scale 로 슬로우 중에도 진행.
	var tree := get_tree()
	if tree != null:
		tree.create_timer(lifetime, true, false, true).timeout.connect(func():
			if is_instance_valid(field):
				_slow_fields.erase(field)
				field.queue_free()
		)


## 매 프레임 — 활성 감속장 만료 정리 + 반경 적 감속 메타(TTL 단명) + epicenter 쪽 미세 드리프트(집결).
## ★평시 비용 0: _slow_fields 비면 즉시 return. ★영구 감속 불가: 적 메타는 _SLOW_FIELD_META_TTL(150ms) 단명이라
## 장이 사라져 갱신이 멈추면 적이 자동 정상화. 드리프트는 epicenter 거리>0.3 일 때만(반경 밖으로 빨림/원점 발진 방지).
func _process(delta: float) -> void:
	if not is_inside_tree() or _slow_fields.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	var expire_at: int = now + _SLOW_FIELD_META_TTL
	var i: int = _slow_fields.size() - 1
	while i >= 0:
		var field = _slow_fields[i]
		if field == null or not is_instance_valid(field):
			_slow_fields.remove_at(i)
			i -= 1
			continue
		if int(field.get_meta("expire_msec", 0)) <= now:
			_slow_fields.remove_at(i)
			field.queue_free()
			i -= 1
			continue
		var center: Vector3 = (field as Node3D).global_position
		var radius: float = float(field.get_meta("radius", _SLOW_FIELD_RADIUS_DEFAULT))
		var slow_mult: float = float(field.get_meta("slow_mult", _SLOW_FIELD_MULT_DEFAULT))
		var drift: float = float(field.get_meta("drift", _SLOW_FIELD_DRIFT_DEFAULT))
		for e in get_tree().get_nodes_in_group("enemies"):
			if e == null or not is_instance_valid(e) or not (e is Node3D):
				continue
			if e.is_in_group("boss"):
				continue  # 보스 면역(끌림/감속 없음).
			var ep: Vector3 = (e as Node3D).global_position
			var flat: Vector3 = Vector3(ep.x - center.x, 0.0, ep.z - center.z)
			var dist: float = flat.length()
			if dist > radius:
				continue
			# 감속 메타 — 단명(150ms). 적 _physics_process 가 읽어 이동속도 스케일(만료 지나면 자동 1.0).
			e.set_meta("boon_slow_until_msec", expire_at)
			e.set_meta("boon_slow_mult", slow_mult)
			# epicenter 쪽 미세 집결 드리프트 — 너무 가까우면 스킵(원점 발진/반경 밖 빨림 방지). 0뎀.
			if dist > 0.3:
				var pull: Vector3 = -flat.normalized() * drift * delta
				(e as Node3D).global_position += pull
		i -= 1


## 2 산화진(SCATTER_RING) — epicenter 바깥으로 척력 링 1회(levelup_pushback 패턴) + 취약표식(vuln_mark) 부여.
## 비보스+apply_knockback 보유 → 수평 바깥 방향 밀침. 보스는 밀침 스킵(취약표식만). ★0뎀(척력+표식만, take_hit 미호출).
## vuln_mark = _settle_enemy 가 다음 납도 정산 단가에 ×vuln_mult(1회 소비) — slash_mark 와 별개 메타.
func _on_sheathe_kill_scatter(epicenter: Vector3) -> void:
	var has_card: bool = false
	var radius: float = _SCATTER_RADIUS_DEFAULT
	var speed: float = _SCATTER_SPEED_DEFAULT
	var vuln: float = _SCATTER_VULN_DEFAULT
	_for_each_effect("On_Sheathe", "SCATTER_RING", func(_i, params):
		has_card = true
		radius = max(radius, float(params.get("push_radius", _SCATTER_RADIUS_DEFAULT)))
		speed = max(speed, float(params.get("push_speed", _SCATTER_SPEED_DEFAULT)))
		vuln = max(vuln, float(params.get("vuln_mult", _SCATTER_VULN_DEFAULT)))
	)
	if not has_card or radius <= 0.0:
		return
	var any: bool = false
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == null or not is_instance_valid(e) or not (e is Node3D):
			continue
		var to_e: Vector3 = (e as Node3D).global_position - epicenter
		to_e.y = 0.0
		if to_e.length() > radius:
			continue
		# 취약표식 부여(이미 있으면 큰 값 유지) — 0뎀.
		var cur: float = float(e.get_meta("vuln_mark", 1.0))
		e.set_meta("vuln_mark", max(cur, vuln))
		any = true
		# 비보스 + apply_knockback 보유면 바깥으로 밀침(보스는 스킵 — 취약표식만).
		if e.is_in_group("boss"):
			continue
		if to_e.length_squared() < 0.0001:
			continue
		if e.has_method("apply_knockback"):
			e.call("apply_knockback", to_e.normalized(), speed)
	if any:
		_spawn_chain_arc(epicenter, epicenter)  # 제자리 청백 링 더미.


## 3 발도충전분출(GAUGE_BURST) — 처치 시 PC 일섬 자원 분출(tier 비례). Player.boon_gauge_burst 위임(열 환급/쿨 단축).
## ★0뎀 PC 자원만(take_hit 미호출). 황금 더미 = _spawn_perfect_flash(PC 위치).
func _on_sheathe_kill_gauge(tier: int) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if not _player.has_method("boon_gauge_burst"):
		return
	var has_card: bool = false
	var base: float = _GAUGE_BURST_BASE_DEFAULT
	var per_tier: float = _GAUGE_BURST_PER_TIER_DEFAULT
	_for_each_effect("On_Sheathe", "GAUGE_BURST", func(_i, params):
		has_card = true
		base = max(base, float(params.get("base_frac", _GAUGE_BURST_BASE_DEFAULT)))
		per_tier = max(per_tier, float(params.get("per_tier_frac", _GAUGE_BURST_PER_TIER_DEFAULT)))
	)
	if not has_card:
		return
	var frac: float = base + per_tier * float(tier)
	_player.call("boon_gauge_burst", frac)
	if _player is Node3D:
		_spawn_perfect_flash((_player as Node3D).global_position)  # 황금 기류 더미(흰 섬광 재사용).


## 4 정기흡수(SPIRIT_STACK) — 처치 시 PC 흡수 스택 +n(잡몹+1, 엘리트/보스 +1+tier_gain). Player.boon_add_spirit 위임.
## ★PC 내부 자원만(0뎀·take_hit 미호출). 정기 구슬 더미 = _spawn_chain_arc(epicenter→PC, 호밍 느낌).
func _on_sheathe_kill_spirit(tier: int) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if not _player.has_method("boon_add_spirit"):
		return
	var has_card: bool = false
	var per_stack: float = _SPIRIT_PER_STACK_DEFAULT
	var max_stack: int = _SPIRIT_MAX_DEFAULT
	var release_mult: float = _SPIRIT_RELEASE_DEFAULT
	var tier_gain: int = _SPIRIT_TIER_GAIN_DEFAULT
	_for_each_effect("On_Sheathe", "SPIRIT_STACK", func(_i, params):
		has_card = true
		per_stack = max(per_stack, float(params.get("per_stack", _SPIRIT_PER_STACK_DEFAULT)))
		max_stack = max(max_stack, int(params.get("max_stack", _SPIRIT_MAX_DEFAULT)))
		release_mult = max(release_mult, float(params.get("release_mult", _SPIRIT_RELEASE_DEFAULT)))
		tier_gain = max(tier_gain, int(params.get("tier_gain", _SPIRIT_TIER_GAIN_DEFAULT)))
	)
	if not has_card:
		return
	# 잡몹(tier0) +1, 엘리트/보스(tier>0) +1+tier_gain.
	var gain: int = 1 + (tier_gain if tier > 0 else 0)
	_player.call("boon_add_spirit", gain, per_stack, max_stack, release_mult)
	# 정기 구슬 더미 — PC 발밑 제자리 청백 링(호밍 느낌, ExpGem 실제 노드 불필요).
	if _player is Node3D:
		var p: Vector3 = (_player as Node3D).global_position
		_spawn_chain_arc(p, p)


# ══════════════ M9-S6: baseline 6종 (코드 상수·항상 on·0뎀 셋업/자원) ══════════════

## 1 납도 파문 — epicenter 소반경 내 '만개(>=cap)·비보스' 1마리만 흘려 처형(비재귀 — _in_cascade 가드).
func _baseline_ripple(epicenter: Vector3) -> void:
	var target: Node = null
	var best_d: float = INF
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == null or not is_instance_valid(e) or not (e is Node3D):
			continue
		if e.is_in_group("boss"):
			continue
		if int(e.get_meta("slash_mark", 0)) < _mark_cap():
			continue  # 만개만.
		var d: float = (e as Node3D).global_position.distance_to(epicenter)
		if d > _BL_RIPPLE_RADIUS or d >= best_d:
			continue
		best_d = d
		target = e
	if target == null:
		return
	# 흰 점멸 + 처형. ★_in_cascade 로 감싸 ON_SHEATHE_KILL 재발 차단(무한연쇄 방지).
	_spawn_perfect_flash((target as Node3D).global_position)
	var prev: bool = _in_cascade
	_in_cascade = true
	var marks: int = int(target.get_meta("slash_mark", 0))
	_cascade_bonus_marks += marks
	_settle_enemy(target, marks, 1.0, 0, false)
	_in_cascade = prev


## 2 참결(표식 파문) — epicenter 반경 내 적에 표식 살포(0뎀). grant=tier>0?2:1, cap 클램프. 청백 링.
func _baseline_mark_spread(epicenter: Vector3, tier: int) -> void:
	# M9-S13: 1납도당 참결 발동 cap — 다중 처치(도미노) 시 표식 살포 인플레 억제. 초과분은 살포 스킵.
	if _baseline_spread_count >= _BASELINE_SPREAD_CAP:
		return
	_baseline_spread_count += 1
	var grant: int = 2 if tier > 0 else 1
	var any: bool = false
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == null or not is_instance_valid(e) or not (e is Node3D):
			continue
		if (e as Node3D).global_position.distance_to(epicenter) > _BL_MARK_RADIUS:
			continue
		var cur: int = int(e.get_meta("slash_mark", 0))
		e.set_meta("slash_mark", min(cur + grant, _mark_cap()))
		any = true
	if any:
		_spawn_chain_arc(epicenter, epicenter)  # 제자리 청백 링(_make_disc_mesh 더미).


## 3 환혈 — PC 가 epicenter 반경 내면 회복(잡몹1/엘리트·보스3). HealthComponent.heal 이 max 클램프.
func _baseline_heal(epicenter: Vector3, tier: int) -> void:
	if _player == null or not is_instance_valid(_player) or not (_player is Node3D):
		return
	if (_player as Node3D).global_position.distance_to(epicenter) > _BL_HEAL_RADIUS:
		return
	var hc = _player.get_node_or_null("HealthComponent")
	if hc == null or not hc.has_method("heal"):
		return
	var amt: int = _BL_HEAL_BIG if tier > 0 else _BL_HEAL_TRASH
	hc.call("heal", amt)


## 4 잔열 환수 — 즉발(열기) 자원 모드면 PC 열 환급(tier 스케일). _refund_heat 가 탈진/쿨모드/0하한 가드.
func _baseline_heat_refund(tier: int) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if not _player.has_method("_refund_heat"):
		return
	# tier 스케일 — 잡몹 작게, 엘리트/보스 크게(코드 1차값, 공유 .tres 미변형).
	var amt: float = 0.06 * float(tier + 1)
	_player.call("_refund_heat", amt)


## 5 혼백 소집 — epicenter 반경 내 ExpGem(group) 강제 호밍(force_home). 0뎀.
func _baseline_gem_summon(epicenter: Vector3) -> void:
	for g in get_tree().get_nodes_in_group("exp_gems"):
		if g == null or not is_instance_valid(g) or not (g is Node3D):
			continue
		if (g as Node3D).global_position.distance_to(epicenter) > _BL_GEM_RADIUS:
			continue
		if g.has_method("force_home"):
			g.call("force_home")


## 6 참향(잔향 일섬) — Player.spawn_echo_slash(데미지0·표식만·노킬). epicenter 최근접 미표식 적 방향 1줄.
func _baseline_echo_slash(epicenter: Vector3) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if _player.has_method("spawn_echo_slash"):
		_player.call("spawn_echo_slash", epicenter)


## epicenter→대상 청백 호 더미 — _make_disc_mesh 얇은 디스크 1회(scale 펄스 후 페이드 free).
## start==end(참결) 면 제자리 링. 신규 씬 없이 재사용 헬퍼만.
func _spawn_chain_arc(start: Vector3, end: Vector3) -> void:
	var host := _effect_host()
	if host == null:
		return
	var mid: Vector3 = (start + end) * 0.5
	var mi := MeshInstance3D.new()
	mi.mesh = _make_disc_mesh(1.0)
	mi.top_level = true
	mi.global_position = Vector3(mid.x, mid.y + 0.06, mid.z)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.6, 0.85, 1.0, 0.7)  # 청백.
	mat.emission_enabled = true
	mat.emission = Color(0.7, 0.9, 1.0)
	mat.emission_energy_multiplier = 1.8
	mi.material_override = mat
	host.add_child(mi)
	mi.scale = Vector3(0.3, 1.0, 0.3)
	var t := mi.create_tween()
	t.set_parallel(true)
	t.tween_property(mi, "scale", Vector3(1.1, 1.0, 1.1), 0.2)
	t.tween_property(mat, "albedo_color:a", 0.0, 0.2)
	t.chain().tween_callback(mi.queue_free)


# ══════════════ 일섬연장(SLASH_EXTEND) — 패시브 재계산 ══════════════

## add_boon 직후 Player 가 호출 — active_boons 의 SLASH_EXTEND 를 스캔해 최댓값으로 런타임 보너스 세팅.
func refresh_passives() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var range_mult: float = 1.0
	var width_mult: float = 1.0
	_for_each_effect("Passive", "SLASH_EXTEND", func(_i, params):
		range_mult = max(range_mult, float(params.get("range_mult", 1.0)))
		width_mult = max(width_mult, float(params.get("width_mult", 1.0)))
	)
	if _player.has_method("set_slash_extend"):
		_player.call("set_slash_extend", range_mult, width_mult)


# ══════════════ 공통 순회 헬퍼 (디스패치 엔진 — 보존) ══════════════

## active_boons 를 순회하며 주어진 trigger·effect 매칭 컴포넌트에 cb.call(boon_index, params) 를 호출.
func _for_each_effect(trigger: String, effect: String, cb: Callable) -> void:
	if not is_inside_tree():
		return
	if _player == null:
		return
	var boons = _player.get("active_boons")
	if not (boons is Array) or boons.is_empty():
		return
	for i in range(boons.size()):
		var boon = boons[i]
		if not (boon is Dictionary):
			continue
		var comps = boon.get("components", [])
		if not (comps is Array):
			continue
		for comp in comps:
			if not (comp is Dictionary):
				continue
			if comp.get("trigger", "") != trigger:
				continue
			if comp.get("effect", "") != effect:
				continue
			cb.call(i, boon.get("params", {}))


# ══════════════ 거합 연출 (흰 섬광 + 미세 슬로우) ══════════════

## 거합 성공 — PC 발밑에 노랑→흰 디스크 1회 버스트(자동 페이드/free). 신규 씬 없이 _make_disc_mesh 재사용.
func _spawn_perfect_flash(origin: Vector3) -> void:
	var host := _effect_host()
	if host == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _make_disc_mesh(2.4)
	mi.top_level = true
	mi.global_position = Vector3(origin.x, origin.y + 0.08, origin.z)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1.0, 0.97, 0.7, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 1.0, 0.9)
	mat.emission_energy_multiplier = 2.2
	mi.material_override = mat
	host.add_child(mi)
	mi.scale = Vector3(0.4, 1.0, 0.4)
	var t := mi.create_tween()
	t.set_parallel(true)
	t.tween_property(mi, "scale", Vector3(1.6, 1.0, 1.6), 0.22)
	t.tween_property(mat, "albedo_color:a", 0.0, 0.22)
	t.chain().tween_callback(mi.queue_free)


## 납도 슬로우모션 — 1차값(일반 0.4/0.22s · 거합 0.3/0.32s). ignore_time_scale 타이머로 1.0 복구.
## S3 거합 _micro_slow 와 통합(중복 슬로우 제거). BulletTime 퍼펙트닷지 슬로우와 시간상 겹쳐도
## 둘 다 ignore_time_scale 라 마지막 복구 타이머가 1.0 으로 되돌린다.
func _sheathe_slowmo(is_perfect: bool) -> void:
	if not is_inside_tree():
		return
	var sc: float = 0.3 if is_perfect else 0.4
	var dur: float = 0.32 if is_perfect else 0.22
	Engine.time_scale = sc
	var tree := get_tree()
	if tree == null:
		Engine.time_scale = 1.0
		return
	# create_timer(time, process_always, process_in_physics=false, ignore_time_scale=true)
	tree.create_timer(dur, true, false, true).timeout.connect(func(): Engine.time_scale = 1.0)


## 납도 줌인 — 1차값(일반 0.82 · 거합 0.75, time 0.4). group 'camera_rig' 노드 덕타이핑.
func _sheathe_zoom(is_perfect: bool) -> void:
	var rig = get_tree().get_first_node_in_group("camera_rig") if is_inside_tree() else null
	if rig == null or not is_instance_valid(rig):
		return
	if not rig.has_method("sheathe_zoom_in"):
		return
	var sc: float = 0.75 if is_perfect else 0.82
	rig.call("sheathe_zoom_in", sc, 0.4)


# ══════════════ 블러드 FX (정산 적마다 — 핏자국 Sprite3D + 빨강 입자) ══════════════

## 거둔 적 위치에 핏자국 1장(빌보드, scale 0.3→1.2 빠르게 후 페이드) + 빨강 입자 버스트.
## 처형(is_exec)은 1.6배 크게. 신규 class_name 없이 코드 인라인(godot-pixel-sprite-alpha 적용).
func _spawn_blood(pos: Vector3, is_exec: bool) -> void:
	if pos == Vector3.ZERO:
		return
	var host := _effect_host()
	if host == null:
		return
	var idx: int = (_blood_counter % 8) + 1
	_blood_counter += 1
	var tex_path: String = "res://market/HitFx/VFX Blood Concepts/VFX Blood Concepts FXOnly%d.png" % idx
	var tex = load(tex_path)
	if tex == null:
		return
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false  # d3d12 흰배경 방지(언라이트).
	spr.transparent = true
	spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	spr.alpha_scissor_threshold = 0.3
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.pixel_size = 0.01
	spr.top_level = true
	spr.global_position = Vector3(pos.x, pos.y + 0.9, pos.z)
	host.add_child(spr)
	var s_end: float = 1.2 * (1.6 if is_exec else 1.0)
	spr.scale = Vector3.ONE * 0.3
	var t := spr.create_tween()
	t.tween_property(spr, "scale", Vector3.ONE * s_end, 0.1)  # 0.3→1.2(처형 1.92) 빠르게.
	t.tween_property(spr, "modulate:a", 0.0, 0.35)            # 0.35s 페이드.
	t.tween_callback(spr.queue_free)
	_spawn_blood_particles(pos, is_exec)


## 피 튀는 입자 — 작은 빨강 CPUParticles3D 1회 버스트(사방). one_shot 후 자동 free 타이머.
func _spawn_blood_particles(pos: Vector3, is_exec: bool) -> void:
	var host := _effect_host()
	if host == null:
		return
	var mult: float = 1.6 if is_exec else 1.0
	var p := CPUParticles3D.new()
	p.top_level = true
	p.global_position = Vector3(pos.x, pos.y + 0.7, pos.z)
	p.one_shot = true
	p.emitting = true
	p.amount = int(round(14 * mult))
	p.lifetime = 0.4
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.0 * mult
	p.gravity = Vector3(0, -9.0, 0)
	p.scale_amount_min = 0.06
	p.scale_amount_max = 0.12
	p.color = Color(0.6, 0.02, 0.02)
	host.add_child(p)
	var tree := host.get_tree()
	if tree != null:
		tree.create_timer(1.0, true).timeout.connect(p.queue_free)


# ══════════════ 재사용 FX 헬퍼 (M9 더미 연출 재활용 — 보존) ══════════════

func _effect_host() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	if tree.current_scene != null:
		return tree.current_scene
	if _player != null and is_instance_valid(_player):
		var pp := _player.get_parent()
		if pp != null:
			return pp
	return tree.root


## 평평한 원판(triangle fan, 로컬 XZ 평면) — SorcererZone 패턴 차용.
func _make_disc_mesh(r: float) -> ArrayMesh:
	var segments: int = 28
	var arr := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segments:
		var a0: float = TAU * float(i) / float(segments)
		var a1: float = TAU * float(i + 1) / float(segments)
		var v0 := Vector3(cos(a0) * r, 0.0, sin(a0) * r)
		var v1 := Vector3(cos(a1) * r, 0.0, sin(a1) * r)
		st.set_normal(Vector3.UP); st.add_vertex(Vector3.ZERO)
		st.set_normal(Vector3.UP); st.add_vertex(v1)
		st.set_normal(Vector3.UP); st.add_vertex(v0)
	st.commit(arr)
	return arr
