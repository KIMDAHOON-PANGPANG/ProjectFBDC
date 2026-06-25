extends Node

## 권속 은혜 효과 실행기. Player 자식으로 add_child.
## TriggerBus 이벤트를 구독해 active_boons 의 컴포넌트 효과를 실행한다.
## class_name 금지 — const _BoonExecutorScript := preload(...) + 덕타이핑으로 참조.
##
## M9-S1: M8 요괴(5종) 콘텐츠 전면 철거. 디스패치 엔진(_for_each_effect)·구독 스켈레톤·
## 재사용 FX 헬퍼(_effect_host/_make_disc_mesh)만 보존. M9 카드/효과는 후속 스텝(S3+)에서 채움.

const _BoonSystemScript := preload("res://scripts/managers/BoonSystem.gd")
const _TriggerBusScript := preload("res://scripts/managers/TriggerBus.gd")

## 납도(On_Sheathe) 정산 — Player 상수와 동일값(정산 주체이므로 자체 보유). 공유 .tres 변형 금지.
const _SHEATHE_RANGE := 5.0
const _SHEATHE_DMG := 2
const _MARK_CAP := 5

var _player: Node = null
var _tb: Node = null
## DEEP_MARK(심도) per_hits 게이팅용 — boon_index → 누적 적중 카운터.
var _hit_counters: Dictionary = {}
## 무납(IAIDO_CHAIN) 거합 미터 — 연속 납도 단계(0~max). _last_chain_msec 로 combo_window 판정.
var _chain_stage: int = 0
var _last_chain_msec: int = 0
## 블러드 FX 변주 카운터 — 정산 적마다 +1, %8 로 핏자국 텍스처 인덱스 선택.
var _blood_counter: int = 0
## 안티-보스 처형선 — 보스 HP 가 max_hp 의 이 비율 이하면 거합+만개 납도로 처형(코드 1차값).
const _BOSS_EXECUTE_THRESHOLD := 0.25


func setup(player: Node) -> void:
	_player = player
	_tb = get_node_or_null("/root/TriggerBus")
	if _tb == null:
		return
	# M9-S3: 납도 정산(발도/거합/환원 통합) + 일섬 적중(심도) 구독.
	_tb.call("subscribe", _TriggerBusScript.ON_SHEATHE, _on_sheathe)
	_tb.call("subscribe", _TriggerBusScript.ON_SLASH_HIT, _on_slash_hit_deepmark)


func _exit_tree() -> void:
	if _tb != null:
		_tb.call("unsubscribe", _TriggerBusScript.ON_SHEATHE, _on_sheathe)
		_tb.call("unsubscribe", _TriggerBusScript.ON_SLASH_HIT, _on_slash_hit_deepmark)
	# 영구 슬로우 방지 — 셧다운 중 납도 슬로우가 걸려 있었어도 강제 정상화.
	if not is_equal_approx(Engine.time_scale, 1.0):
		Engine.time_scale = 1.0


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
	var origin: Vector3 = (_player as Node3D).global_position

	# ── 이 한 번의 납도에 적용될 배율을 active_boons 스캔으로 산출 ──
	var range_eff: float = _SHEATHE_RANGE
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
	_apply_iaido_chain(func(stage_mult):
		range_eff *= stage_mult
		refund_mult *= stage_mult
	)

	# ── 1차 정산 패스: sheathe_range 내 표식 적 거두기. 처형(만개·비보스) 적은 위치 기록(도미노/피니셔). ──
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
		var is_full: bool = marks >= _MARK_CAP and not e.is_in_group("boss")
		if is_full:
			total_marks += int(round(float(marks) * full_collect_mult))
			executed_pts.append((e as Node3D).global_position)
		else:
			total_marks += marks
		settled.append(e)
		_settle_enemy(e, marks, dmg_mult, dmg_bonus, is_perfect)

	# ── 연환납도(SHEATHE_DOMINO): 처형 기점 주변 chain_radius 내 (아직 안 거둔) 표식 적도 함께 거둠. ──
	if not executed_pts.is_empty():
		total_marks += _apply_sheathe_domino(executed_pts, settled, dmg_mult, dmg_bonus, full_collect_mult)

	# 거둔 표식이 있으면 PC 자원 환급(열/HP — 환원·거합·미터 배율 반영).
	if total_marks > 0 and _player.has_method("_sheathe_restore"):
		_player.call("_sheathe_restore", total_marks, heat_extra, hp_extra, refund_mult)

	# 역수(IAIDO_HASTE) — 납도 성공(표식 거둠) 시 다음 일섬 가속 + 대시 거리.
	if total_marks > 0:
		_for_each_effect("On_Sheathe", "IAIDO_HASTE", func(_i, params):
			if _player.has_method("apply_iaido_haste"):
				_player.call("apply_iaido_haste", float(params.get("haste_pct", 0.0)), float(params.get("dash_bonus", 0.0)))
		)

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
	# 블러드 FX 위치 — take_hit(사망 free) 전에 적 위치 캡처.
	var blood_pos: Vector3 = (e as Node3D).global_position if e is Node3D else Vector3.ZERO
	if not e.has_method("take_hit"):
		e.set_meta("slash_mark", 0)
		return
	var is_boss: bool = e.is_in_group("boss")
	# 처형 여부 산출 — 아래 take_hit 분기와 동일 판정(블러드 크기 결정용).
	var is_exec: bool = (marks >= _MARK_CAP and not is_boss) \
		or (is_boss and marks >= _MARK_CAP and is_perfect and _boss_below_execute_threshold(e))
	if marks >= _MARK_CAP and not is_boss:
		e.call("take_hit", 9999)  # 만개 처형 — 잡몹/엘리트/주술사 즉사
	elif is_boss and marks >= _MARK_CAP and is_perfect and _boss_below_execute_threshold(e):
		# 안티-보스 처형선 — 보스 저HP(≤threshold)에서 거합+만개 납도면 처형.
		e.call("take_hit", 9999)
	else:
		var dmg: int = int(round(float(marks * (_SHEATHE_DMG + dmg_bonus)) * dmg_mult))
		e.call("take_hit", max(dmg, 1))  # 미만 + 보스(처형선 미달) = (표식×단가)×거합
	# 죽었든 살았든 표식 소거(살아남은 보스는 다시 새겨야 함).
	if is_instance_valid(e):
		e.set_meta("slash_mark", 0)
	# 정산 적마다 블러드 터짐(처형은 크게).
	_spawn_blood(blood_pos, is_exec)


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
				(target as Node).set_meta("slash_mark", min(cur + extra, _MARK_CAP))
		else:
			_hit_counters[i] = c
	)
	# 광인(MARK_SPREAD) — 적중 적 주변 미표식 적 1~2에 표식 1 전파(엘리트 호위 군집 번짐).
	_for_each_effect("On_Slash_Hit", "MARK_SPREAD", func(_i, params):
		_spread_marks_from(target as Node3D, int(params.get("spread_count", 1)), float(params.get("spread_radius", 2.5)))
	)


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
func _apply_iaido_chain(apply_cb: Callable) -> void:
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
	if _last_chain_msec > 0 and (now - _last_chain_msec) <= window_ms:
		_chain_stage = min(_chain_stage + 1, max_stage)
	else:
		_chain_stage = 1  # 창 밖/첫 납도 — 1단부터 시작.
	_last_chain_msec = now
	# 단계 보너스 = 1 + per_stage × (stage-1). 1단=무보너스, 단계마다 per_stage 누진.
	var stage_mult: float = 1.0 + per_stage * float(max(_chain_stage - 1, 0))
	if stage_mult > 1.0:
		apply_cb.call(stage_mult)


# ══════════════ 연환납도(SHEATHE_DOMINO) — 처형 전파 ══════════════

## 처형 기점(executed_pts) 주변 chain_radius 내, 아직 안 거둔(settled 에 없는) 표식 적도 함께 거둔다.
## 비보스만(보스는 도미노 처형 면역 — 표식 유지). 거둔 표식 합을 반환(환급 가중).
func _apply_sheathe_domino(executed_pts: Array, settled: Array, dmg_mult: float, dmg_bonus: int, full_collect_mult: float) -> int:
	var radius: float = 0.0
	_for_each_effect("On_Sheathe", "SHEATHE_DOMINO", func(_i, params):
		radius = max(radius, float(params.get("chain_radius", 0.0)))
	)
	if radius <= 0.0 or executed_pts.is_empty():
		return 0
	var extra_marks: int = 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == null or not is_instance_valid(e) or not (e is Node3D):
			continue
		if e.is_in_group("boss"):
			continue  # 보스는 도미노 면역.
		if e in settled:
			continue  # 1차 패스에서 이미 거둠.
		var marks: int = int(e.get_meta("slash_mark", 0))
		if marks <= 0:
			continue
		var pos: Vector3 = (e as Node3D).global_position
		var near: bool = false
		for p in executed_pts:
			if pos.distance_to(p) <= radius:
				near = true
				break
		if not near:
			continue
		var is_full: bool = marks >= _MARK_CAP
		if is_full:
			extra_marks += int(round(float(marks) * full_collect_mult))
		else:
			extra_marks += marks
		settled.append(e)
		_settle_enemy(e, marks, dmg_mult, dmg_bonus, false)
	return extra_marks


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
