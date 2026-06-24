extends Node

## 권속 은혜 효과 실행기. Player 자식으로 add_child.
## TriggerBus 이벤트를 구독해 active_boons 의 컴포넌트 효과를 실행한다.
## class_name 금지 — const _BoonExecutorScript := preload(...) + 덕타이핑으로 참조.

const _BoonSystemScript := preload("res://scripts/managers/BoonSystem.gd")
const _TriggerBusScript := preload("res://scripts/managers/TriggerBus.gd")

var _player: Node = null
var _tb: Node = null
## per_hits 게이팅용 카운터. 키=active_boons 인덱스(int), 값=누적 적중(int).
var _hit_counters: Dictionary = {}


func setup(player: Node) -> void:
	_player = player
	_tb = get_node_or_null("/root/TriggerBus")
	if _tb == null:
		return
	_tb.call("subscribe", _TriggerBusScript.ON_SLASH_HIT, Callable(self, "_on_slash_hit"))
	_tb.call("subscribe", _TriggerBusScript.ON_KILL_VIA_SLASH, Callable(self, "_on_kill_via_slash"))
	_tb.call("subscribe", _TriggerBusScript.ON_DASH_PASS_ENEMY, Callable(self, "_on_dash_pass_enemy"))


func _exit_tree() -> void:
	if _tb != null:
		_tb.call("unsubscribe", _TriggerBusScript.ON_SLASH_HIT, Callable(self, "_on_slash_hit"))
		_tb.call("unsubscribe", _TriggerBusScript.ON_KILL_VIA_SLASH, Callable(self, "_on_kill_via_slash"))
		_tb.call("unsubscribe", _TriggerBusScript.ON_DASH_PASS_ENEMY, Callable(self, "_on_dash_pass_enemy"))


func _on_slash_hit(ctx: Dictionary) -> void:
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
			if comp.get("trigger", "") != _TriggerBusScript.ON_SLASH_HIT:
				continue
			match comp.get("effect", ""):
				"APPLY_MARK":
					_apply_mark(i, ctx, boon.get("params", {}))


func _on_kill_via_slash(ctx: Dictionary) -> void:
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
			if comp.get("trigger", "") != _TriggerBusScript.ON_KILL_VIA_SLASH:
				continue
			match comp.get("effect", ""):
				"LIFESTEAL":
					_lifesteal(ctx, boon.get("params", {}))


func _on_dash_pass_enemy(ctx: Dictionary) -> void:
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
			if comp.get("trigger", "") != _TriggerBusScript.ON_DASH_PASS_ENEMY:
				continue
			match comp.get("effect", ""):
				"APPLY_MARK":
					_apply_mark(i, ctx, boon.get("params", {}))


func _apply_mark(boon_index: int, ctx: Dictionary, params: Dictionary) -> void:
	var per_hits := int(params.get("per_hits", 1))
	var mark_add := int(params.get("mark_add", 1))
	var cap := int(params.get("cap", 0))

	_hit_counters[boon_index] = int(_hit_counters.get(boon_index, 0)) + 1
	if _hit_counters[boon_index] < per_hits:
		return
	_hit_counters[boon_index] = 0

	var target = ctx.get("target", null)
	if target == null or not is_instance_valid(target):
		return

	var cur := int(target.get_meta("holrim_marks", 0))
	var nv: int
	if cap > 0:
		nv = min(cur + mark_add, cap)
	else:
		nv = cur + mark_add
	target.set_meta("holrim_marks", nv)


func _lifesteal(ctx: Dictionary, params: Dictionary) -> void:
	var heal_per_mark := float(params.get("heal_per_mark", 0.0))

	var target = ctx.get("target", null)
	var marks := 0
	if target != null and is_instance_valid(target):
		marks = int(target.get_meta("holrim_marks", 0))

	var heal_amount := int(round(marks * heal_per_mark))

	if _player == null or not is_instance_valid(_player):
		return
	var hp := _player.get_node_or_null("HealthComponent")
	if hp != null and heal_amount > 0:
		hp.call("heal", heal_amount)
		print("[Boon] LIFESTEAL marks=%d heal=%d" % [marks, heal_amount])

	# transfer 표식 전이는 S5 확장(후속)에서 — 인접 적 질의 + meta 복사. 현재 슬라이스는 흡혈 회복만.
