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
	_for_each_effect("On_Sheathe", "IAIDO_PERFECT", func(_i, params):
		var window: float = float(params.get("perfect_window", 0.25))
		if _is_perfect_sheathe(window):
			range_eff *= float(params.get("range_mult", 1.0))
			dmg_mult *= float(params.get("settle_mult", 1.0))
			refund_mult *= float(params.get("refund_mult", 1.0))
			do_perfect_fx = true
	)
	# 환원(SHEATHE_REFUND) — 환급량 증폭 + 만개 회수 환원 가중.
	_for_each_effect("On_Sheathe", "SHEATHE_REFUND", func(_i, params):
		heat_extra += float(params.get("heat_per_mark_extra", 0.0))
		hp_extra += float(params.get("hp_per_mark_extra", 0.0))
		full_collect_mult = max(full_collect_mult, float(params.get("full_collect_mult", 1.0)))
	)

	var total_marks: int = 0
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
		else:
			total_marks += marks
		_settle_enemy(e, marks, dmg_mult, dmg_bonus)
	# 거둔 표식이 있으면 PC 자원 환급(열/HP — 환원·거합 배율 반영).
	if total_marks > 0 and _player.has_method("_sheathe_restore"):
		_player.call("_sheathe_restore", total_marks, heat_extra, hp_extra, refund_mult)

	# 거합 성공 연출 — 흰 섬광 + 미세 슬로우(데미지 파이프와 독립).
	if do_perfect_fx:
		_spawn_perfect_flash(origin)
		_micro_slow()


## 거합 perfect 판정 — 마지막 일섬 착지 후 window(s) 이내 납도인가.
func _is_perfect_sheathe(window: float) -> bool:
	if _player == null or not _player.has_method("get_last_slash_end_msec"):
		return false
	var last: int = int(_player.call("get_last_slash_end_msec"))
	if last <= 0:
		return false
	var dt_ms: int = Time.get_ticks_msec() - last
	return dt_ms >= 0 and dt_ms <= int(round(window * 1000.0))


## 표식 적 1마리 정산 — 만개+비보스=처형(즉사), 그 외(미만 또는 보스 만개)=marks×피해. 정산 후 표식 0.
## dmg_bonus = 발도 단가 가산, dmg_mult = 거합 정산 곱(만개 처형엔 미적용).
func _settle_enemy(e: Node, marks: int, dmg_mult: float = 1.0, dmg_bonus: int = 0) -> void:
	if not e.has_method("take_hit"):
		e.set_meta("slash_mark", 0)
		return
	var is_boss: bool = e.is_in_group("boss")
	if marks >= _MARK_CAP and not is_boss:
		e.call("take_hit", 9999)  # 만개 처형 — 잡몹/엘리트/주술사 즉사
	else:
		var dmg: int = int(round(float(marks * (_SHEATHE_DMG + dmg_bonus)) * dmg_mult))
		e.call("take_hit", max(dmg, 1))  # 미만 + 보스(만개 면역) = (표식×단가)×거합
	# 죽었든 살았든 표식 소거(살아남은 보스는 다시 새겨야 함).
	if is_instance_valid(e):
		e.set_meta("slash_mark", 0)


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


## 거합 미세 슬로우 — Engine.time_scale 짧게 낮췄다 복구. ignore_time_scale 타이머로 영구 슬로우 방지.
func _micro_slow() -> void:
	if not is_inside_tree():
		return
	Engine.time_scale = 0.6
	var tree := get_tree()
	if tree == null:
		Engine.time_scale = 1.0
		return
	# create_timer(time, process_always, process_in_physics=false, ignore_time_scale=true)
	tree.create_timer(0.12, true, false, true).timeout.connect(func(): Engine.time_scale = 1.0)


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
