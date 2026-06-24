extends Node

## 권속 은혜 효과 실행기. Player 자식으로 add_child.
## TriggerBus 이벤트를 구독해 active_boons 의 컴포넌트 효과를 실행한다.
## class_name 금지 — const _BoonExecutorScript := preload(...) + 덕타이핑으로 참조.
##
## M8(6★-1) 구미호 능동 FX 풀세트:
##   APPLY_MARK / LIFESTEAL  — 표식 누적 + 흡혈 (기존 + 핑크 인장 플래시·흡혈 빔)
##   CHARM_ZONE              — 핑크 매혹 결계(인력 → 재타격 파열 넉백+버스트)
##   SUMMON_SPIRIT           — 분혼 정령(표식 적 호밍 충돌 격추, 수명·상한)
##   HOMING_PROJECTILE       — 여우불 유도탄(표식 만개 적 자동 발사 → 폭발)
##   SLASH_FAN               — 풀차지 일섬 부채 폭 확장(런타임 변수 + 핑크 호)
##   RADIAL_BURST            — 퍼펙트닷지 시 방사 혼불 N발
## 더미 FX 노드는 전부 인라인 코드 노드(신규 .tscn 없음), 그룹·수명·상한으로 누수 방지.

const _BoonSystemScript := preload("res://scripts/managers/BoonSystem.gd")
const _TriggerBusScript := preload("res://scripts/managers/TriggerBus.gd")
## 능동 FX 노드 스크립트(전용 .gd, class_name 없음 — preload + .new() 인스턴스).
const _CharmZoneScript := preload("res://scenes/effects/BoonCharmZone.gd")
const _SpiritScript := preload("res://scenes/effects/BoonSpirit.gd")
const _FoxfireScript := preload("res://scenes/effects/BoonFoxfire.gd")
## 도깨비 능동 FX 노드 스크립트(전용 .gd, class_name 없음).
const _CloneScript := preload("res://scenes/effects/BoonClone.gd")
const _GoldScript := preload("res://scenes/effects/BoonGold.gd")
const _IgniteZoneScript := preload("res://scenes/effects/BoonIgniteZone.gd")

## 구미호 핑크 틴트(공통).
const PINK := Color(1.0, 0.37, 0.69)
## 도깨비 금황 틴트(공통).
const GOLD := Color(1.0, 0.76, 0.2)

## FX 노드 그룹 + 동시 상한(성능 안전망).
const GRP_ZONE := "boon_fx_zone"
const GRP_SPIRIT := "boon_spirit"
const GRP_PROJ := "boon_proj"
const GRP_CLONE := "boon_clone"
const GRP_GOLD := "boon_gold"
const SPIRIT_CAP := 8
const PROJ_CAP := 24
const GOLD_CAP := 40

var _player: Node = null
var _tb: Node = null
## per_hits 게이팅용 카운터. 키=active_boons 인덱스(int), 값=누적 적중(int).
var _hit_counters: Dictionary = {}
## EXTRA_FAN per_hits 게이팅용 별도 카운터(APPLY_MARK 카운터와 충돌 방지).
var _fan_counters: Dictionary = {}


func setup(player: Node) -> void:
	_player = player
	_tb = get_node_or_null("/root/TriggerBus")
	if _tb == null:
		return
	_tb.call("subscribe", _TriggerBusScript.ON_SLASH_HIT, Callable(self, "_on_slash_hit"))
	_tb.call("subscribe", _TriggerBusScript.ON_KILL_VIA_SLASH, Callable(self, "_on_kill_via_slash"))
	_tb.call("subscribe", _TriggerBusScript.ON_DASH_PASS_ENEMY, Callable(self, "_on_dash_pass_enemy"))
	_tb.call("subscribe", _TriggerBusScript.ON_SLASH_END, Callable(self, "_on_slash_end"))
	_tb.call("subscribe", _TriggerBusScript.ON_SLASH_CHARGED, Callable(self, "_on_slash_charged"))
	_tb.call("subscribe", _TriggerBusScript.ON_JUST_DODGE, Callable(self, "_on_just_dodge"))
	_tb.call("subscribe", _TriggerBusScript.ON_MARK_FULL, Callable(self, "_on_mark_full"))


func _exit_tree() -> void:
	if _tb != null:
		_tb.call("unsubscribe", _TriggerBusScript.ON_SLASH_HIT, Callable(self, "_on_slash_hit"))
		_tb.call("unsubscribe", _TriggerBusScript.ON_KILL_VIA_SLASH, Callable(self, "_on_kill_via_slash"))
		_tb.call("unsubscribe", _TriggerBusScript.ON_DASH_PASS_ENEMY, Callable(self, "_on_dash_pass_enemy"))
		_tb.call("unsubscribe", _TriggerBusScript.ON_SLASH_END, Callable(self, "_on_slash_end"))
		_tb.call("unsubscribe", _TriggerBusScript.ON_SLASH_CHARGED, Callable(self, "_on_slash_charged"))
		_tb.call("unsubscribe", _TriggerBusScript.ON_JUST_DODGE, Callable(self, "_on_just_dodge"))
		_tb.call("unsubscribe", _TriggerBusScript.ON_MARK_FULL, Callable(self, "_on_mark_full"))


# ══════════════ 공통 순회 헬퍼 ══════════════

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


# ══════════════ 트리거 핸들러 ══════════════

func _on_slash_hit(ctx: Dictionary) -> void:
	_for_each_effect(_TriggerBusScript.ON_SLASH_HIT, "APPLY_MARK",
		func(i, params): _apply_mark(i, ctx, params))
	_for_each_effect(_TriggerBusScript.ON_SLASH_HIT, "CHARM_ZONE",
		func(_i, params): _charm_zone(ctx, params))
	# ── 도깨비 ──
	_for_each_effect(_TriggerBusScript.ON_SLASH_HIT, "HOMING_PROJECTILE",
		func(i, params): _dokebi_foxfire(i, ctx, params))
	_for_each_effect(_TriggerBusScript.ON_SLASH_HIT, "EXTRA_FAN",
		func(i, params): _extra_fan(i, ctx, params))


func _on_kill_via_slash(ctx: Dictionary) -> void:
	# 처치 = 피드(굶주림 리셋) — LIFESTEAL 카드 없어도 처치만으로 굶주림 해소.
	if _player != null and is_instance_valid(_player) and _player.has_method("boon_feed"):
		_player.call("boon_feed")
	_for_each_effect(_TriggerBusScript.ON_KILL_VIA_SLASH, "LIFESTEAL",
		func(_i, params): _lifesteal(ctx, params))
	# ── 도깨비 ──
	_for_each_effect(_TriggerBusScript.ON_KILL_VIA_SLASH, "CHAIN_BURST",
		func(_i, params): _chain_burst(ctx, params))
	_for_each_effect(_TriggerBusScript.ON_KILL_VIA_SLASH, "GOLD_REFUND",
		func(_i, params): _gold_refund(ctx, params))


func _on_dash_pass_enemy(ctx: Dictionary) -> void:
	_for_each_effect(_TriggerBusScript.ON_DASH_PASS_ENEMY, "APPLY_MARK",
		func(i, params): _apply_mark(i, ctx, params))


func _on_slash_end(ctx: Dictionary) -> void:
	_for_each_effect(_TriggerBusScript.ON_SLASH_END, "SUMMON_SPIRIT",
		func(_i, params): _summon_spirits(ctx, params))
	# ── 도깨비 ──
	_for_each_effect(_TriggerBusScript.ON_SLASH_END, "SMASH",
		func(_i, params): _smash(ctx, params))
	_for_each_effect(_TriggerBusScript.ON_SLASH_END, "SUMMON_CLONE",
		func(_i, params): _summon_clones(ctx, params))


func _on_slash_charged(ctx: Dictionary) -> void:
	_for_each_effect(_TriggerBusScript.ON_SLASH_CHARGED, "SLASH_FAN",
		func(_i, params): _slash_fan(ctx, params))


func _on_just_dodge(ctx: Dictionary) -> void:
	_for_each_effect(_TriggerBusScript.ON_JUST_DODGE, "RADIAL_BURST",
		func(_i, params): _radial_burst(ctx, params))
	# ── 도깨비 ──
	_for_each_effect(_TriggerBusScript.ON_JUST_DODGE, "IGNITE_ZONE",
		func(_i, params): _ignite_zone(ctx, params))


func _on_mark_full(ctx: Dictionary) -> void:
	_for_each_effect(_TriggerBusScript.ON_MARK_FULL, "HOMING_PROJECTILE",
		func(_i, params): _fire_homing(ctx, params))


# ══════════════ APPLY_MARK + On_Mark_Full emit ══════════════

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

	# 적중 핑크 인장 플래시(매 표식 적용 시).
	_spawn_mark_flash(target)

	# cap 도달 '전이 순간' 1회만 On_Mark_Full emit — 직전에 이미 cap 이었으면 재발화 금지.
	if cap > 0 and cur < cap and nv >= cap:
		# cap 도달 연출 — 파편 버스트.
		_spawn_shard_burst(target, 1.4)
		if _tb != null and target is Node3D:
			_tb.call("emit", _TriggerBusScript.ON_MARK_FULL, {
				"source": _player,
				"target": target,
				"position": (target as Node3D).global_position,
			})


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
		# 흡혈 빔 더미 — 적 위치 → PC 핑크 라인.
		if target is Node3D:
			_spawn_lifesteal_beam((target as Node3D).global_position)
		# 흡혈도 피드(굶주림 리셋) — 중복 무해.
		if _player.has_method("boon_feed"):
			_player.call("boon_feed")


# ══════════════ CHARM_ZONE — 매혹 결계 ══════════════

func _charm_zone(ctx: Dictionary, params: Dictionary) -> void:
	var pos = ctx.get("position", null)
	if not (pos is Vector3):
		var t = ctx.get("target", null)
		if t is Node3D:
			pos = (t as Node3D).global_position
		else:
			return
	var host := _effect_host()
	if host == null:
		return
	# 기존 활성 결계가 같은 적 근처면 '재타격' = 파열. 가장 가까운 결계를 찾는다.
	var existing := _nearest_zone(pos, 2.0)
	if existing != null and is_instance_valid(existing):
		existing.call("burst")
		return

	var zone := _make_charm_zone_node(params)
	host.add_child(zone)
	zone.call("init_zone", pos, params, _player)


## 핑크 매혹 결계 노드. 디스크 + 인력 + 재타격 파열. 자체 _process 타이머로 free.
func _make_charm_zone_node(_params: Dictionary) -> Node3D:
	var n := _CharmZoneScript.new() as Node3D
	n.add_to_group(GRP_ZONE)
	return n


func _nearest_zone(pos: Vector3, max_d: float) -> Node:
	var best: Node = null
	var best_d := max_d
	for z in get_tree().get_nodes_in_group(GRP_ZONE):
		if not is_instance_valid(z) or not (z is Node3D):
			continue
		var d: float = ((z as Node3D).global_position - pos).length()
		if d <= best_d:
			best_d = d
			best = z
	return best


# ══════════════ SUMMON_SPIRIT — 분혼 정령 ══════════════

func _summon_spirits(ctx: Dictionary, params: Dictionary) -> void:
	var count := int(params.get("count", 1))
	var host := _effect_host()
	if host == null or _player == null or not is_instance_valid(_player) or not (_player is Node3D):
		return
	var origin: Vector3 = (_player as Node3D).global_position
	for k in range(count):
		# 동시 상한 — 누수 방지.
		if get_tree().get_nodes_in_group(GRP_SPIRIT).size() >= SPIRIT_CAP:
			break
		var sp := _SpiritScript.new() as Node3D
		sp.add_to_group(GRP_SPIRIT)
		host.add_child(sp)
		var ang := TAU * float(k) / float(max(count, 1)) + randf() * 0.6
		var off := Vector3(cos(ang), 0.0, sin(ang)) * 0.6
		sp.call("init_spirit", origin + off + Vector3(0, 0.9, 0), params)


# ══════════════ HOMING_PROJECTILE — 여우불 유도탄 ══════════════

func _fire_homing(ctx: Dictionary, params: Dictionary) -> void:
	var count := int(params.get("count", 1))
	var host := _effect_host()
	if host == null or _player == null or not is_instance_valid(_player) or not (_player is Node3D):
		return
	var origin: Vector3 = (_player as Node3D).global_position + Vector3(0, 0.9, 0)
	var seed_target = ctx.get("target", null)
	for k in range(count):
		if get_tree().get_nodes_in_group(GRP_PROJ).size() >= PROJ_CAP:
			break
		var pr := _FoxfireScript.new() as Node3D
		pr.add_to_group(GRP_PROJ)
		host.add_child(pr)
		# 초기 방향 — 살짝 흩뿌리고 호밍이 보정.
		var ang := TAU * float(k) / float(max(count, 1)) + randf() * 0.4
		var fire_dir := Vector3(cos(ang), 0.0, sin(ang))
		pr.call("init_proj", origin, fire_dir, params, true, seed_target)


# ══════════════ RADIAL_BURST — 퍼펙트닷지 혼불 난무 ══════════════

func _radial_burst(ctx: Dictionary, params: Dictionary) -> void:
	var count := int(params.get("count", 6))
	var host := _effect_host()
	if host == null or _player == null or not is_instance_valid(_player) or not (_player is Node3D):
		return
	var origin: Vector3 = (_player as Node3D).global_position + Vector3(0, 0.9, 0)
	for k in range(count):
		if get_tree().get_nodes_in_group(GRP_PROJ).size() >= PROJ_CAP:
			break
		var pr := _FoxfireScript.new() as Node3D
		pr.add_to_group(GRP_PROJ)
		host.add_child(pr)
		var ang := TAU * float(k) / float(max(count, 1))
		var fire_dir := Vector3(cos(ang), 0.0, sin(ang))
		# 호밍 OFF — 360° 균등 직진.
		pr.call("init_proj", origin, fire_dir, params, false, null)


# ══════════════ SLASH_FAN — 풀차지 일섬 부채 확장(간이-액티브) ══════════════

func _slash_fan(ctx: Dictionary, params: Dictionary) -> void:
	var width_mult := float(params.get("width_mult", 1.4))
	var arc_bonus := float(params.get("arc_bonus", 1.0))
	# Player 런타임 변수에 일회성 부채 보너스 플래그 세팅(공유 .tres 변형 금지 → 인스턴스 변수).
	if _player != null and is_instance_valid(_player):
		_player.set("boon_slash_fan_width_mult", width_mult)
		_player.set("boon_slash_fan_arc_bonus", arc_bonus)
	# 즉시 전방 핑크 호 연출(가시화) — PC 전방 _aim_dir 방향.
	var pos = ctx.get("position", null)
	if not (pos is Vector3):
		if _player is Node3D:
			pos = (_player as Node3D).global_position
		else:
			return
	_spawn_fan_arc(pos, width_mult)


# ══════════════ 도깨비 — HOMING_PROJECTILE(도깨비불 일섬) ══════════════

## 일섬 적중 시 금황 혼불을 '다음 적'(가장 가까운 적)에게 호밍 발사. 적중 시 불씨 표식.
func _dokebi_foxfire(boon_index: int, ctx: Dictionary, params: Dictionary) -> void:
	var per_hits := int(params.get("per_hits", 1))
	if per_hits > 1:
		var k := boon_index + 100000  # APPLY_MARK 카운터와 키 충돌 방지(별 도메인).
		_hit_counters[k] = int(_hit_counters.get(k, 0)) + 1
		if _hit_counters[k] < per_hits:
			return
		_hit_counters[k] = 0
	var count := int(params.get("count", 1))
	var host := _effect_host()
	if host == null or _player == null or not is_instance_valid(_player) or not (_player is Node3D):
		return
	var origin: Vector3 = (_player as Node3D).global_position + Vector3(0, 0.9, 0)
	# 시드 = 가장 가까운 적('다음 적'). ctx.target 은 방금 맞은 적이라 제외 우선.
	var hit_target = ctx.get("target", null)
	var seed_target := _nearest_enemy_excluding(origin, hit_target)
	if seed_target == null:
		seed_target = hit_target
	var fox_params := {
		"speed": float(params.get("speed", 12.0)),
		"damage": int(params.get("damage", 1)),
		"radius": float(params.get("radius", 0.8)),
		"tint": GOLD,
		"ember_meta": "dokebi_ember",
	}
	for k in range(count):
		if get_tree().get_nodes_in_group(GRP_PROJ).size() >= PROJ_CAP:
			break
		var pr := _FoxfireScript.new() as Node3D
		pr.add_to_group(GRP_PROJ)
		host.add_child(pr)
		var ang := TAU * float(k) / float(max(count, 1)) + randf() * 0.4
		var fire_dir := Vector3(cos(ang), 0.0, sin(ang))
		pr.call("init_proj", origin, fire_dir, fox_params, true, seed_target)


# ══════════════ 도깨비 — CHAIN_BURST(옮겨붙는 도깨비불) ══════════════

## 불씨(dokebi_ember) 적 사망 시 금불 폭발 + 인접 적에 불씨 전파(도미노).
func _chain_burst(ctx: Dictionary, params: Dictionary) -> void:
	var target = ctx.get("target", null)
	var pos = ctx.get("position", null)
	if not (pos is Vector3):
		if target is Node3D:
			pos = (target as Node3D).global_position
		else:
			return
	# 불씨 표식이 없던 적이면 발동 안 함(도깨비불 일섬으로 점화된 적만).
	if target != null and is_instance_valid(target):
		if not bool(target.get_meta("dokebi_ember", false)):
			return
	var radius := float(params.get("radius", 2.6))
	var damage := int(params.get("damage", 1))
	var knockback := float(params.get("knockback", 6.0))
	var spread := int(params.get("spread", 1))
	var spread_radius := float(params.get("spread_radius", 3.4))
	# 금불 폭발 — 반경 적 타격 + 넉백.
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node3D) or e.is_in_group("boss"):
			continue
		var out: Vector3 = (e as Node3D).global_position - pos
		out.y = 0.0
		var d: float = out.length()
		if d <= radius and d > 0.05:
			if e.has_method("take_hit"):
				e.call("take_hit", damage)
			if e.has_method("apply_knockback"):
				e.call("apply_knockback", out.normalized(), knockback)
	# 불씨 전파 — 가장 가까운 미점화 적 spread 마리에 도장.
	_propagate_ember(pos, spread_radius, spread)
	_spawn_burst_particles(pos + Vector3(0, 0.6, 0), 22, 1.5, GOLD)


func _propagate_ember(pos: Vector3, radius: float, count: int) -> void:
	if count <= 0:
		return
	var cands: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node3D) or e.is_in_group("boss"):
			continue
		if bool(e.get_meta("dokebi_ember", false)):
			continue
		var d: float = ((e as Node3D).global_position - pos).length()
		if d <= radius:
			cands.append([d, e])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	for i in range(min(count, cands.size())):
		var e = cands[i][1]
		if is_instance_valid(e):
			e.set_meta("dokebi_ember", true)
			_spawn_mark_flash_color(e, GOLD)


# ══════════════ 도깨비 — SMASH(방망이 한방) ══════════════

## 일섬 착지(On_Slash_End) 시 PC 위치 금황 원형 충격파 + 쉐이크 + 히트스탑 + 반경 적 강타.
func _smash(ctx: Dictionary, params: Dictionary) -> void:
	if _player == null or not is_instance_valid(_player) or not (_player is Node3D):
		return
	var pos: Vector3 = (_player as Node3D).global_position
	var radius := float(params.get("radius", 3.0))
	var damage := int(params.get("damage", 1))
	var knockback := float(params.get("knockback", 9.0))
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node3D) or e.is_in_group("boss"):
			continue
		var out: Vector3 = (e as Node3D).global_position - pos
		out.y = 0.0
		var d: float = out.length()
		if d <= radius and d > 0.05:
			if e.has_method("take_hit"):
				e.call("take_hit", damage)
			if e.has_method("apply_knockback"):
				e.call("apply_knockback", out.normalized(), knockback)
	# 충격파 디스크 + 버스트.
	_spawn_shockwave(pos, radius)
	_spawn_burst_particles(pos + Vector3(0, 0.5, 0), 26, 1.6, GOLD)
	# 카메라 쉐이크 + 히트스탑.
	var rig := get_tree().get_first_node_in_group("camera_rig")
	if rig != null and is_instance_valid(rig):
		if rig.has_method("shake"):
			rig.call("shake", float(params.get("shake_amp", 0.12)), float(params.get("shake_dur", 0.28)))
		if rig.has_method("hitstop"):
			rig.call("hitstop", 0.25, float(params.get("hitstop", 0.07)))


# ══════════════ 도깨비 — EXTRA_FAN(방망이 난타) ══════════════

## 일섬 적중 N회 누적마다 전방 금황 부채 잔상 추가타(간이 부채 판정).
func _extra_fan(boon_index: int, ctx: Dictionary, params: Dictionary) -> void:
	var per_hits := int(params.get("per_hits", 2))
	_fan_counters[boon_index] = int(_fan_counters.get(boon_index, 0)) + 1
	if _fan_counters[boon_index] < per_hits:
		return
	_fan_counters[boon_index] = 0
	if _player == null or not is_instance_valid(_player) or not (_player is Node3D):
		return
	var origin: Vector3 = (_player as Node3D).global_position
	var rng := float(params.get("range", 3.0))
	var width := float(params.get("width", 1.6))
	var damage := int(params.get("damage", 1))
	# 전방 방향 — PC _aim_dir.
	var aim := Vector3(1, 0, 0)
	var av = _player.get("_aim_dir")
	if av is Vector3 and (av as Vector3).length_squared() > 0.0001:
		aim = (av as Vector3).normalized()
	# 부채 판정 — 전방 사거리 안 + 반각(width 로 폭 환산).
	var cos_half: float = clampf(1.0 - width * 0.18, -0.3, 0.9)
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node3D) or e.is_in_group("boss"):
			continue
		var to_e: Vector3 = (e as Node3D).global_position - origin
		to_e.y = 0.0
		var d: float = to_e.length()
		if d > rng or d < 0.05:
			continue
		if aim.dot(to_e.normalized()) < cos_half:
			continue
		if e.has_method("take_hit"):
			e.call("take_hit", damage)
	_spawn_fan_arc_color(origin + aim * (rng * 0.4), width, GOLD)


# ══════════════ 도깨비 — SUMMON_CLONE(난장도깨비패) ══════════════

func _summon_clones(ctx: Dictionary, params: Dictionary) -> void:
	var count := int(params.get("count", 1))
	var cap := int(params.get("cap", 4))
	var host := _effect_host()
	if host == null or _player == null or not is_instance_valid(_player):
		return
	for k in range(count):
		if get_tree().get_nodes_in_group(GRP_CLONE).size() >= cap:
			break
		var cl := _CloneScript.new() as Node3D
		cl.add_to_group(GRP_CLONE)
		host.add_child(cl)
		var ang := TAU * float(get_tree().get_nodes_in_group(GRP_CLONE).size()) / float(max(cap, 1)) + randf() * 0.5
		cl.call("init_clone", _player, params, ang)


# ══════════════ 도깨비 — GOLD_REFUND(뚝딱 금 나와라) ══════════════

func _gold_refund(ctx: Dictionary, params: Dictionary) -> void:
	var count := int(params.get("count", 2))
	var host := _effect_host()
	if host == null or _player == null or not is_instance_valid(_player) or not (_player is Node3D):
		return
	# 토출 원점 = 처치된 적 위치(없으면 PC).
	var origin: Vector3 = (_player as Node3D).global_position
	var target = ctx.get("target", null)
	var pos = ctx.get("position", null)
	if pos is Vector3:
		origin = pos
	elif target is Node3D:
		origin = (target as Node3D).global_position
	# 코인당 환급은 총량을 분할(회수 시마다 조금씩).
	var per_refund := float(params.get("heat_refund", 8.0)) / float(max(count, 1))
	var per_heal := int(params.get("heal", 0))
	for k in range(count):
		if get_tree().get_nodes_in_group(GRP_GOLD).size() >= GOLD_CAP:
			break
		var g := _GoldScript.new() as Node3D
		g.add_to_group(GRP_GOLD)
		host.add_child(g)
		var ang := TAU * float(k) / float(max(count, 1)) + randf() * 0.6
		var spit := Vector3(cos(ang), 0.0, sin(ang))
		# 첫 코인만 회복분 부여(중복 회복 과다 방지), 환급은 균등.
		var heal_this := per_heal if k == 0 else 0
		g.call("init_gold", _player, origin, {"heat_refund": per_refund, "heal": heal_this}, spit)


# ══════════════ 도깨비 — IGNITE_ZONE(도깨비 금줄) ══════════════

func _ignite_zone(ctx: Dictionary, params: Dictionary) -> void:
	var host := _effect_host()
	if host == null or _player == null or not is_instance_valid(_player) or not (_player is Node3D):
		return
	var pos: Vector3 = (_player as Node3D).global_position
	var z := _IgniteZoneScript.new() as Node3D
	z.add_to_group(GRP_ZONE)
	host.add_child(z)
	z.call("init_zone", pos, params, GRP_PROJ, PROJ_CAP)


# ══════════════ 도깨비 공용 보조 ══════════════

func _nearest_enemy_excluding(pos: Vector3, exclude) -> Node:
	var best: Node = null
	var best_d: float = 99999.0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node3D) or e.is_in_group("boss"):
			continue
		if e == exclude:
			continue
		var d: float = ((e as Node3D).global_position - pos).length()
		if d < best_d:
			best_d = d
			best = e
	return best


## 금황 충격파 — 빠르게 퍼지는 링/디스크.
func _spawn_shockwave(center: Vector3, radius: float) -> void:
	var host := _effect_host()
	if host == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _make_disc_mesh(radius)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.55)
	mat.emission_enabled = true
	mat.emission = GOLD
	mat.emission_energy_multiplier = 2.0
	mi.material_override = mat
	host.add_child(mi)
	mi.global_position = center + Vector3(0, 0.07, 0)
	mi.scale = Vector3(0.2, 1.0, 0.2)
	var t := mi.create_tween()
	t.set_parallel(true)
	t.tween_property(mi, "scale", Vector3(1.1, 1.0, 1.1), 0.22)
	t.tween_property(mat, "albedo_color:a", 0.0, 0.3)
	t.chain().tween_callback(mi.queue_free)


# ══════════════ 더미 FX 스폰 헬퍼 ══════════════

## 표식 적용 시 적 위에 핑크 인장 플래시(짧은 디스크 펄스).
func _spawn_mark_flash(target: Node) -> void:
	_spawn_mark_flash_color(target, PINK)


## 색 지정 인장 플래시(도깨비 금황 불씨 전파 등 재사용).
func _spawn_mark_flash_color(target: Node, col: Color) -> void:
	if not (target is Node3D):
		return
	var host := _effect_host()
	if host == null:
		return
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.9, 0.9)
	mi.mesh = qm
	mi.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(col.r, col.g, col.b, 0.7)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 2.0
	mi.material_override = mat
	host.add_child(mi)
	mi.global_position = (target as Node3D).global_position + Vector3(0, 1.4, 0)
	mi.scale = Vector3(0.3, 0.3, 0.3)
	var t := mi.create_tween()
	t.set_parallel(true)
	t.tween_property(mi, "scale", Vector3(1.2, 1.2, 1.2), 0.22)
	t.tween_property(mat, "albedo_color:a", 0.0, 0.28)
	t.chain().tween_callback(mi.queue_free)


## 표식 cap 도달 시 파편 버스트(CPUParticles3D 1회).
func _spawn_shard_burst(target: Node, scale: float) -> void:
	if not (target is Node3D):
		return
	_spawn_burst_particles((target as Node3D).global_position + Vector3(0, 1.0, 0), 18, scale)


## 흡혈 빔 — 적 위치 → PC 핑크 라인(짧은 페이드).
func _spawn_lifesteal_beam(from_pos: Vector3) -> void:
	if _player == null or not is_instance_valid(_player) or not (_player is Node3D):
		return
	var host := _effect_host()
	if host == null:
		return
	var to_pos: Vector3 = (_player as Node3D).global_position + Vector3(0, 0.9, 0)
	var a := from_pos + Vector3(0, 0.9, 0)
	var mid := (a + to_pos) * 0.5
	var diff := to_pos - a
	var len := diff.length()
	if len < 0.05:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(len, 0.08, 0.08)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(PINK.r, PINK.g, PINK.b, 0.85)
	mat.emission_enabled = true
	mat.emission = PINK
	mat.emission_energy_multiplier = 2.5
	mi.material_override = mat
	host.add_child(mi)
	mi.global_position = mid
	var yaw := atan2(-diff.z, diff.x)
	mi.rotation = Vector3(0.0, yaw, 0.0)
	var t := mi.create_tween()
	t.tween_property(mat, "albedo_color:a", 0.0, 0.3)
	t.tween_callback(mi.queue_free)


## 풀차지 일섬 부채 확장 연출 — PC 전방 핑크 호(부채꼴 디스크).
func _spawn_fan_arc(center: Vector3, width_mult: float) -> void:
	_spawn_fan_arc_color(center, width_mult, PINK)


## 색 지정 부채 호(도깨비 난타 금황 잔상 재사용).
func _spawn_fan_arc_color(center: Vector3, width_mult: float, col: Color) -> void:
	var host := _effect_host()
	if host == null:
		return
	var mi := MeshInstance3D.new()
	var r: float = 2.0 * clampf(width_mult, 1.0, 3.0)
	mi.mesh = _make_disc_mesh(r)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(col.r, col.g, col.b, 0.4)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 1.6
	mi.material_override = mat
	host.add_child(mi)
	mi.global_position = center + Vector3(0, 0.08, 0)
	mi.scale = Vector3(0.3, 1.0, 0.3)
	var t := mi.create_tween()
	t.set_parallel(true)
	t.tween_property(mi, "scale", Vector3(1, 1, 1), 0.18)
	t.tween_property(mat, "albedo_color:a", 0.0, 0.3)
	t.chain().tween_callback(mi.queue_free)


## 공용 파편 버스트(CPUParticles3D 1회, one_shot). 색 기본 핑크(구미호), 인자로 금황 등 주입.
func _spawn_burst_particles(pos: Vector3, amount: int, scale: float, col: Color = PINK) -> void:
	var host := _effect_host()
	if host == null:
		return
	var p := CPUParticles3D.new()
	host.add_child(p)
	p.global_position = pos
	p.one_shot = true
	p.emitting = true
	p.amount = amount
	p.lifetime = 0.5
	p.local_coords = false
	p.explosiveness = 1.0
	p.direction = Vector3(0, 1, 0)
	p.spread = 180.0
	p.initial_velocity_min = 2.0 * scale
	p.initial_velocity_max = 5.0 * scale
	p.gravity = Vector3(0, -3.0, 0)
	p.scale_amount_min = 0.06
	p.scale_amount_max = 0.14
	var qm := QuadMesh.new()
	qm.size = Vector2(0.18, 0.18)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Color(col.r, col.g, col.b, 0.9)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 2.0
	qm.material = mat
	p.mesh = qm
	# one_shot 종료 후 자가 free(lifetime + 여유).
	p.get_tree().create_timer(p.lifetime + 0.3).timeout.connect(p.queue_free)


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
