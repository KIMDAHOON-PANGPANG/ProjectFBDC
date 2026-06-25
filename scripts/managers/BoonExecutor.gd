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


func setup(player: Node) -> void:
	_player = player
	_tb = get_node_or_null("/root/TriggerBus")
	if _tb == null:
		return
	# M9-S2: 납도 정산 구독. (요괴 트리거 구독은 S1 에서 철거됨, S3+ 에서 effect 추가.)
	_tb.call("subscribe", _TriggerBusScript.ON_SHEATHE, _on_sheathe)


func _exit_tree() -> void:
	if _tb != null:
		_tb.call("unsubscribe", _TriggerBusScript.ON_SHEATHE, _on_sheathe)


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
	var total_marks: int = 0
	# 'enemies' 그룹에 보스 포함(Boss._ready 가 enemies+boss 둘 다 가입) — 단일 순회로 충분.
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == null or not is_instance_valid(e) or not (e is Node3D):
			continue
		var marks: int = int(e.get_meta("slash_mark", 0))
		if marks <= 0:
			continue
		if (e as Node3D).global_position.distance_to(origin) > _SHEATHE_RANGE:
			continue
		total_marks += marks
		_settle_enemy(e, marks)
	# 거둔 표식이 있으면 PC 자원 환급(열 -8%/marks + HP +0.4/marks).
	if total_marks > 0 and _player.has_method("_sheathe_restore"):
		_player.call("_sheathe_restore", total_marks)


## 표식 적 1마리 정산 — 만개+비보스=처형(즉사), 그 외(미만 또는 보스 만개)=marks×피해. 정산 후 표식 0.
func _settle_enemy(e: Node, marks: int) -> void:
	if not e.has_method("take_hit"):
		e.set_meta("slash_mark", 0)
		return
	var is_boss: bool = e.is_in_group("boss")
	if marks >= _MARK_CAP and not is_boss:
		e.call("take_hit", 9999)  # 만개 처형 — 잡몹/엘리트/주술사 즉사
	else:
		e.call("take_hit", marks * _SHEATHE_DMG)  # 미만 + 보스(만개 면역) = 표식×단가
	# 죽었든 살았든 표식 소거(살아남은 보스는 다시 새겨야 함).
	if is_instance_valid(e):
		e.set_meta("slash_mark", 0)


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
