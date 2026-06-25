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
## 물귀신 능동 FX 노드 스크립트(전용 .gd, class_name 없음).
const _WaterGrabScript := preload("res://scenes/effects/BoonWaterGrab.gd")
const _DrownedScript := preload("res://scenes/effects/BoonDrowned.gd")
const _WaterPillarScript := preload("res://scenes/effects/BoonWaterPillar.gd")
const _GraspScript := preload("res://scenes/effects/BoonGrasp.gd")

## 구미호 핑크 틴트(공통).
const PINK := Color(1.0, 0.37, 0.69)
## 도깨비 금황 틴트(공통).
const GOLD := Color(1.0, 0.76, 0.2)
## 물귀신 물빛 틴트(공통, #2f9fe0).
const WATER := Color(0.184, 0.624, 0.878)
## 저승사자 보라 틴트(공통, #7b5cf0).
const PURPLE := Color(0.482, 0.361, 0.941)
## 처녀귀신 진홍 틴트 #d11f3a.
const CRIMSON := Color(0.820, 0.122, 0.227)
## 명부 낙인(nakin_marks) 가시화 정규화 상한(아이콘 게이지 풀 = master cap 8).
const NAKIN_CAP := 8

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
	_tb.call("subscribe", _TriggerBusScript.ON_DASH, Callable(self, "_on_dash"))
	_tb.call("subscribe", _TriggerBusScript.ON_SLASH_END, Callable(self, "_on_slash_end"))
	_tb.call("subscribe", _TriggerBusScript.ON_SLASH_CHARGED, Callable(self, "_on_slash_charged"))
	_tb.call("subscribe", _TriggerBusScript.ON_JUST_DODGE, Callable(self, "_on_just_dodge"))
	_tb.call("subscribe", _TriggerBusScript.ON_MARK_FULL, Callable(self, "_on_mark_full"))


func _exit_tree() -> void:
	if _tb != null:
		_tb.call("unsubscribe", _TriggerBusScript.ON_SLASH_HIT, Callable(self, "_on_slash_hit"))
		_tb.call("unsubscribe", _TriggerBusScript.ON_KILL_VIA_SLASH, Callable(self, "_on_kill_via_slash"))
		_tb.call("unsubscribe", _TriggerBusScript.ON_DASH_PASS_ENEMY, Callable(self, "_on_dash_pass_enemy"))
		_tb.call("unsubscribe", _TriggerBusScript.ON_DASH, Callable(self, "_on_dash"))
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
	# ── 물귀신 ──
	_for_each_effect(_TriggerBusScript.ON_SLASH_HIT, "WATER_GRAB",
		func(i, params): _water_grab(i, ctx, params))
	_for_each_effect(_TriggerBusScript.ON_SLASH_HIT, "WATER_PILLAR",
		func(i, params): _water_pillar(i, ctx, params))
	# ── 저승사자 ──
	_for_each_effect(_TriggerBusScript.ON_SLASH_HIT, "SOUL_HOMING",
		func(i, params): _soul_homing(i, ctx, params))
	_for_each_effect(_TriggerBusScript.ON_SLASH_HIT, "EXECUTE",
		func(i, params): _soul_execute(i, ctx, params))
	# ── 처녀귀신 ──
	_for_each_effect(_TriggerBusScript.ON_SLASH_HIT, "CROSS_SLASH",
		func(i, params): _cross_slash(i, ctx, params))
	_for_each_effect(_TriggerBusScript.ON_SLASH_HIT, "HAIR_GRAB",
		func(i, params): _hair_grab(i, ctx, params))


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
	# ── 물귀신 ──
	_for_each_effect(_TriggerBusScript.ON_KILL_VIA_SLASH, "SUMMON_DROWNED",
		func(_i, params): _summon_drowned(ctx, params))
	# ── 저승사자 ──
	_for_each_effect(_TriggerBusScript.ON_KILL_VIA_SLASH, "SUMMON_SAJA",
		func(_i, params): _summon_saja(ctx, params))
	_for_each_effect(_TriggerBusScript.ON_KILL_VIA_SLASH, "LANTERN_ZONE",
		func(_i, params): _lantern_zone(ctx, params))
	# ── 처녀귀신 ──
	_for_each_effect(_TriggerBusScript.ON_KILL_VIA_SLASH, "GREAT_WRAITH",
		func(_i, params): _great_wraith(ctx, params))


func _on_dash_pass_enemy(ctx: Dictionary) -> void:
	_for_each_effect(_TriggerBusScript.ON_DASH_PASS_ENEMY, "APPLY_MARK",
		func(i, params): _apply_mark(i, ctx, params))


## 회피(대시) 종료 — 물귀신 발목잡는손(GRASP_ROOT) / 저승사자 차사사슬파편(CHAIN_SHARD).
func _on_dash(ctx: Dictionary) -> void:
	_for_each_effect(_TriggerBusScript.ON_DASH, "GRASP_ROOT",
		func(_i, params): _grasp_root(ctx, params))
	# ── 저승사자 ──
	_for_each_effect(_TriggerBusScript.ON_DASH, "CHAIN_SHARD",
		func(_i, params): _chain_shard(ctx, params))
	# ── 처녀귀신 ──
	_for_each_effect(_TriggerBusScript.ON_DASH, "HAIR_LINE",
		func(_i, params): _hair_line(ctx, params))


func _on_slash_end(ctx: Dictionary) -> void:
	_for_each_effect(_TriggerBusScript.ON_SLASH_END, "SUMMON_SPIRIT",
		func(_i, params): _summon_spirits(ctx, params))
	# ── 도깨비 ──
	_for_each_effect(_TriggerBusScript.ON_SLASH_END, "SMASH",
		func(_i, params): _smash(ctx, params))
	_for_each_effect(_TriggerBusScript.ON_SLASH_END, "SUMMON_CLONE",
		func(_i, params): _summon_clones(ctx, params))
	# ── 물귀신 ──
	_for_each_effect(_TriggerBusScript.ON_SLASH_END, "WHIRLPOOL",
		func(_i, params): _whirlpool(ctx, params))
	# ── 저승사자 ──
	_for_each_effect(_TriggerBusScript.ON_SLASH_END, "CLONE_SAJA",
		func(_i, params): _clone_saja(ctx, params))
	_for_each_effect(_TriggerBusScript.ON_SLASH_END, "SOUL_CHAIN",
		func(_i, params): _soul_chain(ctx, params))
	# ── 처녀귀신 ──
	_for_each_effect(_TriggerBusScript.ON_SLASH_END, "CURVE_SLASH",
		func(_i, params): _curve_slash(ctx, params))
	_for_each_effect(_TriggerBusScript.ON_SLASH_END, "HAIR_DETONATE",
		func(_i, params): _hair_detonate(ctx, params))


func _on_slash_charged(ctx: Dictionary) -> void:
	_for_each_effect(_TriggerBusScript.ON_SLASH_CHARGED, "SLASH_FAN",
		func(_i, params): _slash_fan(ctx, params))


func _on_just_dodge(ctx: Dictionary) -> void:
	_for_each_effect(_TriggerBusScript.ON_JUST_DODGE, "RADIAL_BURST",
		func(_i, params): _radial_burst(ctx, params))
	# ── 도깨비 ──
	_for_each_effect(_TriggerBusScript.ON_JUST_DODGE, "IGNITE_ZONE",
		func(_i, params): _ignite_zone(ctx, params))
	# ── 물귀신 ──
	_for_each_effect(_TriggerBusScript.ON_JUST_DODGE, "WATER_ZONE",
		func(_i, params): _water_zone(ctx, params))
	_for_each_effect(_TriggerBusScript.ON_JUST_DODGE, "ABYSS_MAW",
		func(_i, params): _abyss_maw(ctx, params))
	# ── 저승사자 ──
	_for_each_effect(_TriggerBusScript.ON_JUST_DODGE, "REALM",
		func(_i, params): _realm(ctx, params))
	# ── 처녀귀신 ──
	_for_each_effect(_TriggerBusScript.ON_JUST_DODGE, "SHROUD_ZONE",
		func(_i, params): _shroud_zone(ctx, params))


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


# ══════════════ 물귀신 — WATER_ZONE / ABYSS_MAW(소용돌이 결계) ══════════════

## 회피 자리 물 소용돌이 — BoonCharmZone 재사용(물빛 + 인력). 반경 적에 젖음 + 감속 부여.
func _water_zone(ctx: Dictionary, params: Dictionary) -> void:
	var pos = _ctx_position(ctx)
	if not (pos is Vector3):
		return
	var host := _effect_host()
	if host == null:
		return
	var zp := params.duplicate()
	zp["tint"] = WATER
	# 결계는 인력만 — 파열(burst)은 물귀신 결계엔 안 씀(별도 트리거 없음). burst 값 0 안전.
	var zone := _CharmZoneScript.new() as Node3D
	zone.add_to_group(GRP_ZONE)
	host.add_child(zone)
	zone.call("init_zone", pos, zp, _player)
	# 생성 즉시 반경 적에 젖음 1회 + 감속(PC 무관 = enemies 그룹).
	_apply_wet_and_slow_in_radius(pos, float(params.get("radius", 2.5)),
		int(params.get("wet_add", 1)), float(params.get("slow_mult", 0.6)))


## 심연의아가리 — 대형 소용돌이(강인력) → 클라이맥스 폭발 정산.
func _abyss_maw(ctx: Dictionary, params: Dictionary) -> void:
	var pos = _ctx_position(ctx)
	if not (pos is Vector3):
		return
	var host := _effect_host()
	if host == null:
		return
	var duration := maxf(float(params.get("duration", 3.0)), 0.5)
	var zp := {
		"radius": float(params.get("radius", 4.2)),
		"duration": duration,
		"pull": float(params.get("pull", 4.2)),
		"tint": WATER,
	}
	var zone := _CharmZoneScript.new() as Node3D
	zone.add_to_group(GRP_ZONE)
	host.add_child(zone)
	zone.call("init_zone", pos, zp, _player)
	# 클라이맥스 — duration*0.9 후 광역 토출 넉백 + 버스트.
	var tree := get_tree()
	if tree == null:
		return
	var climax_kb := float(params.get("climax_knockback", 14.0))
	var climax_r := maxf(float(params.get("climax_radius", 4.8)), 0.5)
	var center: Vector3 = pos
	var t := tree.create_timer(duration * 0.9)
	t.timeout.connect(func(): _abyss_climax(center, climax_r, climax_kb))


func _abyss_climax(center: Vector3, radius: float, kb: float) -> void:
	if not is_inside_tree():
		return
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node3D) or e.is_in_group("boss"):
			continue
		var out: Vector3 = (e as Node3D).global_position - center
		out.y = 0.0
		var d: float = out.length()
		if d <= radius and d > 0.05:
			if e.has_method("apply_knockback"):
				e.call("apply_knockback", out.normalized(), kb)
	_spawn_burst_particles(center + Vector3(0, 0.6, 0), 30, 1.8, WATER)


# ══════════════ 물귀신 — WHIRLPOOL(퇴수일섬 소용돌이) ══════════════

## 일섬 착지 소용돌이 — 반경 적 중심 인력 후 물보라 넉백 토출 + 젖음 + 버스트.
func _whirlpool(ctx: Dictionary, params: Dictionary) -> void:
	if _player == null or not is_instance_valid(_player) or not (_player is Node3D):
		return
	var center: Vector3 = (_player as Node3D).global_position
	var radius := maxf(float(params.get("radius", 3.0)), 0.5)
	var pull := float(params.get("pull", 10.0))
	var burst_kb := float(params.get("burst_knockback", 10.0))
	var burst_r := maxf(float(params.get("burst_radius", 3.0)), 0.5)
	var wet_add := int(params.get("wet_add", 1))
	# 흡입 — 반경 적을 중심으로 강하게 끌어당김 + 젖음.
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node3D) or e.is_in_group("boss"):
			continue
		var to_c: Vector3 = center - (e as Node3D).global_position
		to_c.y = 0.0
		var d: float = to_c.length()
		if d <= radius and d > 0.05:
			if e.has_method("apply_knockback"):
				e.call("apply_knockback", to_c.normalized(), pull)
			var cur := int(e.get_meta("wet_marks", 0))
			e.set_meta("wet_marks", cur + wet_add)
	# 소용돌이 디스크 연출.
	_spawn_water_swirl(center, radius)
	# 짧은 딜레이 후 물보라 토출(바깥 넉백) + 버스트.
	var tree := get_tree()
	if tree == null:
		return
	var t := tree.create_timer(0.22)
	t.timeout.connect(func(): _whirlpool_burst(center, burst_r, burst_kb))


func _whirlpool_burst(center: Vector3, radius: float, kb: float) -> void:
	if not is_inside_tree():
		return
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node3D) or e.is_in_group("boss"):
			continue
		var out: Vector3 = (e as Node3D).global_position - center
		out.y = 0.0
		var d: float = out.length()
		if d <= radius and d > 0.05:
			if e.has_method("apply_knockback"):
				e.call("apply_knockback", out.normalized(), kb)
	_spawn_burst_particles(center + Vector3(0, 0.5, 0), 26, 1.6, WATER)


# ══════════════ 물귀신 — WATER_GRAB(수장의올가미) ══════════════

## 일섬 적중 N회마다 가장 먼 적에 물올가미 발사 → PC 앞 견인 + 짧은 속박.
func _water_grab(boon_index: int, ctx: Dictionary, params: Dictionary) -> void:
	var per_hits := int(params.get("per_hits", 1))
	if per_hits > 1:
		var k := boon_index + 200000  # 다른 카운터 도메인과 충돌 방지.
		_fan_counters[k] = int(_fan_counters.get(k, 0)) + 1
		if _fan_counters[k] < per_hits:
			return
		_fan_counters[k] = 0
	var host := _effect_host()
	if host == null or _player == null or not is_instance_valid(_player) or not (_player is Node3D):
		return
	var origin: Vector3 = (_player as Node3D).global_position + Vector3(0, 0.6, 0)
	var hit_target = ctx.get("target", null)
	var count := int(params.get("count", 1))
	var gp := params.duplicate()
	gp["tint"] = WATER
	for k in range(count):
		if get_tree().get_nodes_in_group(GRP_PROJ).size() >= PROJ_CAP:
			break
		# 시드 = 가장 먼 적(방금 맞은 적 제외 우선).
		var seed_target := _farthest_enemy_excluding(origin, hit_target)
		if seed_target == null:
			seed_target = _farthest_enemy_excluding(origin, null)
		if seed_target == null:
			break
		var pr := _WaterGrabScript.new() as Node3D
		pr.add_to_group(GRP_PROJ)
		host.add_child(pr)
		var fire_dir: Vector3 = (seed_target as Node3D).global_position - origin
		pr.call("init_grab", origin, fire_dir, gp, _player, seed_target)


# ══════════════ 물귀신 — WATER_PILLAR(수몰) ══════════════

## 일섬 적중 시 젖은 적 발밑 물기둥 솟구침 버스트 + 젖음 증폭 데미지 + 인접 전파.
func _water_pillar(boon_index: int, ctx: Dictionary, params: Dictionary) -> void:
	var per_hits := int(params.get("per_hits", 1))
	if per_hits > 1:
		var k := boon_index + 300000
		_fan_counters[k] = int(_fan_counters.get(k, 0)) + 1
		if _fan_counters[k] < per_hits:
			return
		_fan_counters[k] = 0
	var target = ctx.get("target", null)
	if target == null or not is_instance_valid(target) or not (target is Node3D):
		return
	if (target as Node).is_in_group("boss"):
		return
	# 결산 — 젖음 적에만 발동(젖지 않았으면 스킵 = 젖음 페이오프 카드).
	var wet := int(target.get_meta("wet_marks", 0))
	if wet <= 0:
		return
	var center: Vector3 = (target as Node3D).global_position
	var radius := maxf(float(params.get("radius", 2.6)), 0.5)
	var base_dmg := int(params.get("damage", 1))
	var wet_bonus := int(params.get("wet_bonus_damage", 1))
	var wet_consume := bool(params.get("wet_consume", true))
	var spread := int(params.get("spread", 1))
	var spread_radius := maxf(float(params.get("spread_radius", 3.0)), 0.5)
	# 물기둥 연출(비주얼 전용).
	var host := _effect_host()
	if host != null:
		var pil := _WaterPillarScript.new() as Node3D
		host.add_child(pil)
		pil.call("init_pillar", center, radius * 0.6, WATER)
	# 반경 적 결산 타격 — 젖은 적은 증폭, 그 외 기본.
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node3D) or e.is_in_group("boss"):
			continue
		var d: float = ((e as Node3D).global_position - center).length()
		if d > radius:
			continue
		var ew := int(e.get_meta("wet_marks", 0))
		var dmg := base_dmg + (wet_bonus * ew if ew > 0 else 0)
		if e.has_method("take_hit"):
			e.call("take_hit", dmg)
		if wet_consume and ew > 0:
			e.set_meta("wet_marks", 0)
	# 인접 젖음 전파.
	_propagate_wet(center, spread_radius, spread)
	_spawn_burst_particles(center + Vector3(0, 0.6, 0), 22, 1.5, WATER)


func _propagate_wet(pos: Vector3, radius: float, count: int) -> void:
	if count <= 0:
		return
	var cands: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node3D) or e.is_in_group("boss"):
			continue
		if int(e.get_meta("wet_marks", 0)) > 0:
			continue
		var d: float = ((e as Node3D).global_position - pos).length()
		if d <= radius:
			cands.append([d, e])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	for i in range(min(count, cands.size())):
		var e = cands[i][1]
		if is_instance_valid(e):
			e.set_meta("wet_marks", 1)
			_spawn_mark_flash_color(e, WATER)


# ══════════════ 물귀신 — SUMMON_DROWNED(익사한동무) ══════════════

func _summon_drowned(ctx: Dictionary, params: Dictionary) -> void:
	var count := int(params.get("count", 1))
	var host := _effect_host()
	if host == null or _player == null or not is_instance_valid(_player) or not (_player is Node3D):
		return
	# 소환 원점 = 처치 적 위치(없으면 PC).
	var origin: Vector3 = (_player as Node3D).global_position
	var target = ctx.get("target", null)
	var pos = ctx.get("position", null)
	if pos is Vector3:
		origin = pos
	elif target is Node3D:
		origin = (target as Node3D).global_position
	var dp := params.duplicate()
	dp["tint"] = WATER
	for k in range(count):
		if get_tree().get_nodes_in_group(GRP_SPIRIT).size() >= SPIRIT_CAP:
			break
		var dr := _DrownedScript.new() as Node3D
		dr.add_to_group(GRP_SPIRIT)
		host.add_child(dr)
		var ang := TAU * float(k) / float(max(count, 1)) + randf() * 0.6
		var off := Vector3(cos(ang), 0.0, sin(ang)) * 0.7
		dr.call("init_drowned", origin + off + Vector3(0, 0.9, 0), dp)


# ══════════════ 물귀신 — GRASP_ROOT(발목잡는손) ══════════════

func _grasp_root(ctx: Dictionary, params: Dictionary) -> void:
	var pos = _ctx_position(ctx)
	if not (pos is Vector3):
		if _player is Node3D:
			pos = (_player as Node3D).global_position
		else:
			return
	var radius := maxf(float(params.get("radius", 3.0)), 0.5)
	var root_dur := float(params.get("root_duration", 1.0))
	var wet_add := int(params.get("wet_add", 1))
	# 물손 연출.
	var host := _effect_host()
	if host != null:
		var g := _GraspScript.new() as Node3D
		host.add_child(g)
		g.call("init_grasp", pos, radius, WATER)
	# 반경 적 속박 + 젖음(보스 제외, PC 무관).
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node3D) or e.is_in_group("boss"):
			continue
		var d: float = ((e as Node3D).global_position - pos).length()
		if d <= radius:
			e.set_meta("boon_root_until_msec", Time.get_ticks_msec() + int(root_dur * 1000.0))
			var cur := int(e.get_meta("wet_marks", 0))
			e.set_meta("wet_marks", cur + wet_add)


# ══════════════ 물귀신 공용 보조 ══════════════

## ctx 에서 position 추출(없으면 target 위치). 실패 시 null.
func _ctx_position(ctx: Dictionary):
	var pos = ctx.get("position", null)
	if pos is Vector3:
		return pos
	var t = ctx.get("target", null)
	if t is Node3D:
		return (t as Node3D).global_position
	return null


## 가장 먼 적(exclude 제외) — 수장의올가미 시드.
func _farthest_enemy_excluding(pos: Vector3, exclude) -> Node:
	var best: Node = null
	var best_d: float = -1.0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node3D) or e.is_in_group("boss"):
			continue
		if e == exclude:
			continue
		var d: float = ((e as Node3D).global_position - pos).length()
		if d > best_d:
			best_d = d
			best = e
	return best


## 반경 적에 젖음 1회 + 감속 부여(WATER_ZONE 생성 즉시). 감속은 적 apply_zone_slow 가 있으면 호출.
func _apply_wet_and_slow_in_radius(center: Vector3, radius: float, wet_add: int, slow_mult: float) -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node3D) or e.is_in_group("boss"):
			continue
		var d: float = ((e as Node3D).global_position - center).length()
		if d <= radius:
			var cur := int(e.get_meta("wet_marks", 0))
			e.set_meta("wet_marks", cur + wet_add)
			if e.has_method("apply_zone_slow"):
				e.call("apply_zone_slow", slow_mult)


## 물 소용돌이 디스크 — 빠르게 회전하듯 퍼지는 물빛 디스크(WHIRLPOOL 연출).
func _spawn_water_swirl(center: Vector3, radius: float) -> void:
	var host := _effect_host()
	if host == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _make_disc_mesh(radius)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(WATER.r, WATER.g, WATER.b, 0.5)
	mat.emission_enabled = true
	mat.emission = WATER
	mat.emission_energy_multiplier = 1.8
	mi.material_override = mat
	host.add_child(mi)
	mi.global_position = center + Vector3(0, 0.07, 0)
	mi.scale = Vector3(0.2, 1.0, 0.2)
	var t := mi.create_tween()
	t.set_parallel(true)
	t.tween_property(mi, "scale", Vector3(1.1, 1.0, 1.1), 0.2)
	t.tween_property(mi, "rotation:y", PI, 0.4)
	t.tween_property(mat, "albedo_color:a", 0.0, 0.4)
	t.chain().tween_callback(mi.queue_free)


# ══════════════ 저승사자 — 명부 낙인(nakin) 공용 ══════════════

## 명부 낙인 누적 — 구미호 holrim / 물귀신 wet 와 같은 int 누적 표식.
## cap clamp + 보라 인장 플래시. cap 전이 순간 1회 파편 버스트.
func _add_nakin(target: Node, add: int, cap: int) -> void:
	if target == null or not is_instance_valid(target) or not (target is Node3D):
		return
	if (target as Node).is_in_group("boss"):
		return
	var c := cap if cap > 0 else NAKIN_CAP
	var cur := int(target.get_meta("nakin_marks", 0))
	var nv: int = min(cur + add, c)
	target.set_meta("nakin_marks", nv)
	_spawn_mark_flash_color(target, PURPLE)
	if cur < c and nv >= c:
		_spawn_shard_burst(target, 1.4)


## 반경 안 적 중 nakin 이 가장 많은 적(최대) 반환(없으면 null). EXECUTE 시드 보강용.
func _nearest_enemy_purple(pos: Vector3) -> Node:
	var best: Node = null
	var best_d: float = 99999.0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node3D) or e.is_in_group("boss"):
			continue
		var d: float = ((e as Node3D).global_position - pos).length()
		if d < best_d:
			best_d = d
			best = e
	return best


# ══════════════ 저승사자 — SOUL_HOMING(명부혼불) ══════════════

## 일섬 적중 시 보라 혼불을 가장 가까운 '다음 적'에게 곡선 호밍 발사 + 낙인.
func _soul_homing(boon_index: int, ctx: Dictionary, params: Dictionary) -> void:
	var per_hits := int(params.get("per_hits", 1))
	if per_hits > 1:
		var k := boon_index + 400000  # 도메인 분리(다른 카운터와 충돌 방지).
		_hit_counters[k] = int(_hit_counters.get(k, 0)) + 1
		if _hit_counters[k] < per_hits:
			return
		_hit_counters[k] = 0
	var count := int(params.get("count", 1))
	var nakin_add := int(params.get("nakin_add", 1))
	var host := _effect_host()
	if host == null or _player == null or not is_instance_valid(_player) or not (_player is Node3D):
		return
	var origin: Vector3 = (_player as Node3D).global_position + Vector3(0, 0.9, 0)
	var hit_target = ctx.get("target", null)
	var seed_target := _nearest_enemy_excluding(origin, hit_target)
	if seed_target == null:
		seed_target = hit_target
	# 시드에 즉시 낙인(혼불 적중 전에라도 낙인 누적 — EXECUTE 와 연계).
	if seed_target != null:
		_add_nakin(seed_target, nakin_add, NAKIN_CAP)
	var fox_params := {
		"speed": float(params.get("speed", 12.0)),
		"damage": int(params.get("damage", 1)),
		"radius": float(params.get("radius", 0.9)),
		"tint": PURPLE,
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


# ══════════════ 저승사자 — CHAIN_SHARD(차사사슬파편) ══════════════

## 회피 종료 시 PC 발밑 반경 적 속박 + 소량 피해 + 낙인 + 보라 파편 디스크.
func _chain_shard(ctx: Dictionary, params: Dictionary) -> void:
	var pos = _ctx_position(ctx)
	if not (pos is Vector3):
		if _player is Node3D:
			pos = (_player as Node3D).global_position
		else:
			return
	var radius := maxf(float(params.get("radius", 3.0)), 0.5)
	var root_dur := float(params.get("root_duration", 0.8))
	var damage := int(params.get("damage", 1))
	var nakin_add := int(params.get("nakin_add", 1))
	# 보라 사슬 파편 연출(GraspScript 물손 패턴 재사용 — 색만 보라).
	var host := _effect_host()
	if host != null:
		var g := _GraspScript.new() as Node3D
		host.add_child(g)
		g.call("init_grasp", pos, radius, PURPLE)
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node3D) or e.is_in_group("boss"):
			continue
		var d: float = ((e as Node3D).global_position - pos).length()
		if d <= radius:
			e.set_meta("boon_root_until_msec", Time.get_ticks_msec() + int(root_dur * 1000.0))
			if e.has_method("take_hit"):
				e.call("take_hit", damage)
			_add_nakin(e, nakin_add, NAKIN_CAP)


# ══════════════ 저승사자 — SUMMON_SAJA(거두는 사자불) ══════════════

## 일섬 처치 자리에서 보라 사자불(추격 호밍) 소환 — 최근접 적 자동 추격 충돌 폭발.
func _summon_saja(ctx: Dictionary, params: Dictionary) -> void:
	var count := int(params.get("count", 1))
	var nakin_add := int(params.get("nakin_add", 1))
	var host := _effect_host()
	if host == null or _player == null or not is_instance_valid(_player) or not (_player is Node3D):
		return
	var origin: Vector3 = (_player as Node3D).global_position + Vector3(0, 0.9, 0)
	var target = ctx.get("target", null)
	var pos = ctx.get("position", null)
	if pos is Vector3:
		origin = (pos as Vector3) + Vector3(0, 0.9, 0)
	elif target is Node3D:
		origin = (target as Node3D).global_position + Vector3(0, 0.9, 0)
	var fox_params := {
		"speed": float(params.get("speed", 8.0)),
		"damage": int(params.get("damage", 1)),
		"radius": float(params.get("radius", 0.9)),
		"tint": PURPLE,
	}
	# 소환 즉시 최근접 적 낙인(추격불 펫이 '거두는' 연출 보강).
	var nearest := _nearest_enemy_purple(origin)
	if nearest != null:
		_add_nakin(nearest, nakin_add, NAKIN_CAP)
	for k in range(count):
		# 추격불도 발사체로 취급 — 동시 상한은 SPIRIT_CAP(펫 도메인).
		if get_tree().get_nodes_in_group(GRP_SPIRIT).size() >= SPIRIT_CAP:
			break
		var pr := _FoxfireScript.new() as Node3D
		pr.add_to_group(GRP_SPIRIT)
		host.add_child(pr)
		var ang := TAU * float(k) / float(max(count, 1)) + randf() * 0.6
		var fire_dir := Vector3(cos(ang), 0.0, sin(ang))
		# homing=true → 최근접/낙인 적 추격.
		pr.call("init_proj", origin, fire_dir, fox_params, true, nearest)


# ══════════════ 저승사자 — CLONE_SAJA(저승곡사자) ══════════════

## 일섬 착지 시 보라 차사 분신 소환 — 일섬을 지연 에코로 따라 벤다(BoonClone 재사용, 보라).
func _clone_saja(ctx: Dictionary, params: Dictionary) -> void:
	var count := int(params.get("count", 1))
	var cap := int(params.get("cap", 4))
	var host := _effect_host()
	if host == null or _player == null or not is_instance_valid(_player):
		return
	var cp := params.duplicate()
	cp["tint"] = PURPLE
	for k in range(count):
		if get_tree().get_nodes_in_group(GRP_CLONE).size() >= cap:
			break
		var cl := _CloneScript.new() as Node3D
		cl.add_to_group(GRP_CLONE)
		host.add_child(cl)
		var ang := TAU * float(get_tree().get_nodes_in_group(GRP_CLONE).size()) / float(max(cap, 1)) + randf() * 0.5
		cl.call("init_clone", _player, cp, ang)


# ══════════════ 저승사자 — EXECUTE(명부낙인 혼불처형) ══════════════

## 일섬 적중 시 낙인 cap 도달 적에 혼불 연발 자동 폭격 + 처형선 이하 즉사 + 인접 낙인 전파.
func _soul_execute(boon_index: int, ctx: Dictionary, params: Dictionary) -> void:
	var per_hits := int(params.get("per_hits", 1))
	if per_hits > 1:
		var k := boon_index + 500000
		_hit_counters[k] = int(_hit_counters.get(k, 0)) + 1
		if _hit_counters[k] < per_hits:
			return
		_hit_counters[k] = 0
	var target = ctx.get("target", null)
	if target == null or not is_instance_valid(target) or not (target is Node3D):
		return
	if (target as Node).is_in_group("boss"):
		return
	var cap := int(params.get("cap", 6))
	# 결산 — 낙인 만렙(cap 도달) 적에만 발동.
	if int(target.get_meta("nakin_marks", 0)) < cap:
		return
	var count := int(params.get("count", 3))
	var damage := int(params.get("damage", 3))
	var threshold := int(params.get("execute_threshold", 3))
	var spread := int(params.get("spread", 1))
	var spread_radius := maxf(float(params.get("spread_radius", 3.4)), 0.5)
	var center: Vector3 = (target as Node3D).global_position
	var host := _effect_host()
	# 혼불 연발 자동 폭격 — 처형 대상 좌표로 직격.
	if host != null:
		var origin: Vector3 = center + Vector3(0, 2.4, 0)
		for k in range(count):
			if get_tree().get_nodes_in_group(GRP_PROJ).size() >= PROJ_CAP:
				break
			var pr := _FoxfireScript.new() as Node3D
			pr.add_to_group(GRP_PROJ)
			host.add_child(pr)
			var fire_dir: Vector3 = (center - origin)
			pr.call("init_proj", origin, fire_dir, {
				"speed": 16.0, "damage": damage, "radius": 1.0, "tint": PURPLE,
			}, true, target)
	# 처형 — HP 가 처형선 이하면 즉사 정산(큰 피해).
	if is_instance_valid(target) and target.has_method("take_hit"):
		var hp_now := _enemy_hp(target)
		if hp_now >= 0 and hp_now <= threshold:
			target.call("take_hit", 999)
	# 낙인 소비 + 처형 버스트.
	if is_instance_valid(target):
		target.set_meta("nakin_marks", 0)
		_spawn_burst_particles(center + Vector3(0, 0.8, 0), 26, 1.7, PURPLE)
	# 인접 낙인 전파.
	_propagate_nakin(center, spread_radius, spread)


## 적 현재 HP 읽기(HealthComponent.hp 덕타이핑). 못 읽으면 -1.
func _enemy_hp(e: Node) -> int:
	if e == null or not is_instance_valid(e):
		return -1
	var hc = e.get_node_or_null("HealthComponent")
	if hc != null and ("hp" in hc):
		return int(hc.get("hp"))
	return -1


func _propagate_nakin(pos: Vector3, radius: float, count: int) -> void:
	if count <= 0:
		return
	var cands: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node3D) or e.is_in_group("boss"):
			continue
		if int(e.get_meta("nakin_marks", 0)) > 0:
			continue
		var d: float = ((e as Node3D).global_position - pos).length()
		if d <= radius:
			cands.append([d, e])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	for i in range(min(count, cands.size())):
		var e = cands[i][1]
		if is_instance_valid(e):
			_add_nakin(e, 1, NAKIN_CAP)


# ══════════════ 저승사자 — LANTERN_ZONE(황천 인도등불) ══════════════

## 일섬 처치 자리 보라 등불 존 — 내부 적 둔화 + 틱딜(IgniteZone 재사용) + 재화 자석 가속.
func _lantern_zone(ctx: Dictionary, params: Dictionary) -> void:
	var pos = _ctx_position(ctx)
	if not (pos is Vector3):
		if _player is Node3D:
			pos = (_player as Node3D).global_position
		else:
			return
	var host := _effect_host()
	if host == null:
		return
	var radius := maxf(float(params.get("radius", 3.0)), 0.5)
	# IgniteZone 재사용 — dot 틱딜. foxfire 는 끄기 위해 interval 을 duration 초과로(발사 안 함).
	var duration := maxf(float(params.get("duration", 3.5)), 0.5)
	var zp := {
		"radius": radius,
		"duration": duration,
		"dot_interval": 0.5,
		"dot_damage": int(params.get("dot_damage", 1)),
		"foxfire_interval": duration + 10.0,
		"foxfire_speed": 1.0,
		"tint": PURPLE,
	}
	var z := _IgniteZoneScript.new() as Node3D
	z.add_to_group(GRP_ZONE)
	host.add_child(z)
	z.call("init_zone", pos, zp, GRP_PROJ, PROJ_CAP)
	# 생성 즉시 반경 적 둔화 1회(apply_zone_slow 있으면).
	var slow_mult := float(params.get("slow_mult", 0.6))
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node3D) or e.is_in_group("boss"):
			continue
		if ((e as Node3D).global_position - pos).length() <= radius:
			if e.has_method("apply_zone_slow"):
				e.call("apply_zone_slow", slow_mult)
	# 재화(EXP 젬) 자석 가속 — 그룹 없음 → 효과 호스트 자식 중 magnet_radius 보유 노드 일시 확대.
	var magnet_mult := float(params.get("magnet_mult", 2.0))
	if magnet_mult > 1.0:
		_boost_gem_magnet(pos, radius * 1.5, magnet_mult)


## 반경 안 EXP 젬류(magnet_radius·exp_value 덕타이핑) 자석 반경 일시 확대(중복 무해).
func _boost_gem_magnet(center: Vector3, radius: float, mult: float) -> void:
	var host := _effect_host()
	if host == null:
		return
	for n in host.get_children():
		if not is_instance_valid(n) or not (n is Node3D):
			continue
		if not ("magnet_radius" in n):
			continue
		var d: float = ((n as Node3D).global_position - center).length()
		if d <= radius:
			# 1회 확대 — 자석권 안에 들어와 졸졸 끌려오게(영구 변형 무해, 노드 수명 짧음).
			n.set("magnet_radius", float(n.get("magnet_radius")) * mult)


# ══════════════ 저승사자 — REALM(명부의 영역) ══════════════

## 퍼펙트 회피 시 대형 보라 명계 결계 — 주기 낫 틱딜(IgniteZone dot 재사용, foxfire OFF).
func _realm(ctx: Dictionary, params: Dictionary) -> void:
	var pos = _ctx_position(ctx)
	if not (pos is Vector3):
		if _player is Node3D:
			pos = (_player as Node3D).global_position
		else:
			return
	var host := _effect_host()
	if host == null:
		return
	var duration := maxf(float(params.get("duration", 4.5)), 0.5)
	var zp := {
		"radius": maxf(float(params.get("radius", 5.0)), 0.5),
		"duration": duration,
		"dot_interval": maxf(float(params.get("tick_interval", 0.5)), 0.1),
		"dot_damage": int(params.get("tick_damage", 1)),
		"foxfire_interval": duration + 10.0,
		"foxfire_speed": 1.0,
		"tint": PURPLE,
	}
	var z := _IgniteZoneScript.new() as Node3D
	z.add_to_group(GRP_ZONE)
	host.add_child(z)
	z.call("init_zone", pos, zp, GRP_PROJ, PROJ_CAP)


# ══════════════ 저승사자 — SOUL_CHAIN(구혼사슬) ══════════════

## 일섬 착지 시 보라 사슬을 부채꼴로 사출 — 다수 근접 적 견인+속박+낙인, 혼불 1발 동반.
func _soul_chain(ctx: Dictionary, params: Dictionary) -> void:
	var host := _effect_host()
	if host == null or _player == null or not is_instance_valid(_player) or not (_player is Node3D):
		return
	var origin: Vector3 = (_player as Node3D).global_position + Vector3(0, 0.6, 0)
	var count := int(params.get("count", 2))
	var nakin_add := int(params.get("nakin_add", 1))
	var gp := params.duplicate()
	gp["tint"] = PURPLE
	gp["speed"] = float(params.get("speed", 18.0))
	# 시드 = 서로 다른 근접 적 다수(이미 잡힌 적 제외).
	var picked: Array = []
	for k in range(count):
		if get_tree().get_nodes_in_group(GRP_PROJ).size() >= PROJ_CAP:
			break
		var seed_target := _nearest_enemy_excluding_list(origin, picked)
		if seed_target == null:
			break
		picked.append(seed_target)
		_add_nakin(seed_target, nakin_add, NAKIN_CAP)
		var pr := _WaterGrabScript.new() as Node3D
		pr.add_to_group(GRP_PROJ)
		host.add_child(pr)
		var fire_dir: Vector3 = (seed_target as Node3D).global_position - origin
		pr.call("init_grab", origin, fire_dir, gp, _player, seed_target)
	# 혼불 1발 동반(가장 가까운 적 호밍).
	if get_tree().get_nodes_in_group(GRP_PROJ).size() < PROJ_CAP:
		var nearest := _nearest_enemy_purple(origin)
		var pr := _FoxfireScript.new() as Node3D
		pr.add_to_group(GRP_PROJ)
		host.add_child(pr)
		pr.call("init_proj", origin, Vector3(1, 0, 0), {
			"speed": 14.0, "damage": 1, "radius": 0.9, "tint": PURPLE,
		}, true, nearest)


## 가장 가까운 적(제외 리스트의 노드는 건너뜀) — 구혼사슬 다수 시드.
func _nearest_enemy_excluding_list(pos: Vector3, exclude: Array) -> Node:
	var best: Node = null
	var best_d: float = 99999.0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node3D) or e.is_in_group("boss"):
			continue
		if e in exclude:
			continue
		var d: float = ((e as Node3D).global_position - pos).length()
		if d < best_d:
			best_d = d
			best = e
	return best


# ══════════════ 처녀귀신 — 원한(wonhan) 표식 공용 ══════════════

## 원한 표식 누적 — nakin 패턴 복제, 진홍 인장 플래시. cap 전이 순간 파편 버스트.
func _add_wonhan(target: Node, add: int, cap: int) -> void:
	if target == null or not is_instance_valid(target) or not (target is Node3D):
		return
	if (target as Node).is_in_group("boss"):
		return
	var c: int = cap if cap > 0 else NAKIN_CAP
	var cur := int(target.get_meta("wonhan_marks", 0))
	var nv: int = min(cur + add, c)
	target.set_meta("wonhan_marks", nv)
	_spawn_mark_flash_color(target, CRIMSON)
	if cur < c and nv >= c:
		_spawn_shard_burst(target, 1.4)


# ══════════════ 처녀귀신 — HAIR_LINE(난발) ══════════════

## 회피 종료 시 PC 발밑 진홍 결계선 존(BoonCharmZone 진홍 변형). GRP_ZONE 등록(단발참 소모).
func _hair_line(ctx: Dictionary, params: Dictionary) -> void:
	var pos = _ctx_position(ctx)
	if not (pos is Vector3):
		if _player is Node3D:
			pos = (_player as Node3D).global_position
		else:
			return
	var host := _effect_host()
	if host == null:
		return
	var zp := params.duplicate()
	zp["tint"] = CRIMSON
	var zone := _CharmZoneScript.new() as Node3D
	zone.add_to_group(GRP_ZONE)
	host.add_child(zone)
	zone.call("init_zone", pos, zp, _player)
	# 생성 즉시 반경 적에 도트 + 원한.
	var radius := maxf(float(params.get("radius", 2.5)), 0.5)
	var dot_dmg := int(params.get("dot_damage", 1))
	var wonhan_add := int(params.get("wonhan_add", 1))
	var slow_mult := float(params.get("slow_mult", 0.6))
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node3D) or e.is_in_group("boss"):
			continue
		if ((e as Node3D).global_position - pos).length() <= radius:
			if e.has_method("take_hit"):
				e.call("take_hit", dot_dmg)
			if e.has_method("apply_zone_slow"):
				e.call("apply_zone_slow", slow_mult)
			_add_wonhan(e, wonhan_add, NAKIN_CAP)


# ══════════════ 처녀귀신 — CROSS_SLASH(교차원한) ══════════════

## 일섬 적중 N회마다 전방 X자 추가타 + 원한. 원한 보유 적 재타격 시 십자 폭발.
func _cross_slash(boon_index: int, ctx: Dictionary, params: Dictionary) -> void:
	var per_hits := int(params.get("per_hits", 2))
	var k := boon_index + 600000
	_fan_counters[k] = int(_fan_counters.get(k, 0)) + 1
	if _fan_counters[k] < per_hits:
		return
	_fan_counters[k] = 0
	if _player == null or not is_instance_valid(_player) or not (_player is Node3D):
		return
	var origin: Vector3 = (_player as Node3D).global_position
	var rng := float(params.get("range", 3.0))
	var width := float(params.get("width", 1.6))
	var damage := int(params.get("damage", 1))
	var wonhan_add := int(params.get("wonhan_add", 1))
	var cross_radius := maxf(float(params.get("cross_radius", 2.6)), 0.5)
	var cross_damage := int(params.get("cross_damage", 1))
	var aim := Vector3(1, 0, 0)
	var av = _player.get("_aim_dir")
	if av is Vector3 and (av as Vector3).length_squared() > 0.0001:
		aim = (av as Vector3).normalized()
	var cos_half: float = clampf(1.0 - width * 0.18, -0.3, 0.9)
	# X자 추가타 + 원한.
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
		_add_wonhan(e, wonhan_add, NAKIN_CAP)
	# 원한 보유 적 십자 폭발(범위 안 원한 적 위치마다).
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node3D) or e.is_in_group("boss"):
			continue
		if int(e.get_meta("wonhan_marks", 0)) <= 0:
			continue
		var to_e: Vector3 = (e as Node3D).global_position - origin
		to_e.y = 0.0
		if to_e.length() > rng:
			continue
		var epos: Vector3 = (e as Node3D).global_position
		for e2 in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(e2) or not (e2 is Node3D) or e2.is_in_group("boss"):
				continue
			if ((e2 as Node3D).global_position - epos).length() <= cross_radius:
				if e2.has_method("take_hit"):
					e2.call("take_hit", cross_damage)
		_spawn_burst_particles(epos + Vector3(0, 0.6, 0), 24, 1.5, CRIMSON)
	_spawn_fan_arc_color(origin + aim * (rng * 0.4), width, CRIMSON)


# ══════════════ 처녀귀신 — GREAT_WRAITH(대원혼) ══════════════

## 일섬 처치 시 진홍 원귀 포위 솟구침 연출 + 반경 광역 처형 + 결박.
func _great_wraith(ctx: Dictionary, params: Dictionary) -> void:
	var target = ctx.get("target", null)
	var pos = ctx.get("position", null)
	var center: Vector3
	if pos is Vector3:
		center = pos
	elif target is Node3D:
		center = (target as Node3D).global_position
	elif _player is Node3D:
		center = (_player as Node3D).global_position
	else:
		return
	var radius := maxf(float(params.get("radius", 3.0)), 0.5)
	var damage := int(params.get("damage", 2))
	var threshold := int(params.get("execute_threshold", 3))
	var root_dur := float(params.get("root_duration", 0.6))
	# 원귀 포위 솟구침 연출.
	_spawn_burst_particles(center + Vector3(0, 0.4, 0), 34, 2.0, CRIMSON)
	_spawn_burst_particles(center + Vector3(0, 1.0, 0), 18, 1.4, CRIMSON)
	# 반경 적 처리.
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node3D) or e.is_in_group("boss"):
			continue
		if ((e as Node3D).global_position - center).length() > radius:
			continue
		if e.has_method("take_hit"):
			e.call("take_hit", damage)
		var hp_now := _enemy_hp(e)
		if hp_now >= 0 and hp_now <= threshold:
			if e.has_method("take_hit"):
				e.call("take_hit", 999)
		e.set_meta("boon_root_until_msec", Time.get_ticks_msec() + int(root_dur * 1000.0))
	# 카메라 쉐이크.
	var rig := get_tree().get_first_node_in_group("camera_rig")
	if rig != null and is_instance_valid(rig) and rig.has_method("shake"):
		rig.call("shake", 0.12, 0.3)


# ══════════════ 처녀귀신 — CURVE_SLASH(회포일섬) ══════════════

## 일섬 착지 시 곡선 다단 베기 + 결계호 잔류 존.
func _curve_slash(ctx: Dictionary, params: Dictionary) -> void:
	if _player == null or not is_instance_valid(_player) or not (_player is Node3D):
		return
	var center: Vector3 = (_player as Node3D).global_position
	var radius := maxf(float(params.get("radius", 3.0)), 0.5)
	var damage := int(params.get("damage", 1))
	var hits := int(params.get("hits", 2))
	var zone_duration := maxf(float(params.get("zone_duration", 2.0)), 0.3)
	var zone_radius := maxf(float(params.get("zone_radius", 2.2)), 0.3)
	# 다단 베기 — 반경 적에 hits 회 take_hit.
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node3D) or e.is_in_group("boss"):
			continue
		if ((e as Node3D).global_position - center).length() <= radius:
			for _h in range(hits):
				if is_instance_valid(e) and e.has_method("take_hit"):
					e.call("take_hit", damage)
	# 곡선 호 연출.
	_spawn_fan_arc_color(center, 2.0, CRIMSON)
	_spawn_burst_particles(center + Vector3(0, 0.5, 0), 20, 1.4, CRIMSON)
	# 잔류 결계호 존.
	var host := _effect_host()
	if host == null:
		return
	var zp := {
		"radius": zone_radius,
		"duration": zone_duration,
		"pull": 1.0,
		"tint": CRIMSON,
	}
	var zone := _CharmZoneScript.new() as Node3D
	zone.add_to_group(GRP_ZONE)
	host.add_child(zone)
	zone.call("init_zone", center, zp, _player)


# ══════════════ 처녀귀신 — HAIR_GRAB(머리채) ══════════════

## 일섬 적중 N회마다 가장 먼 적에 진홍 머리채 발사 → 견인+결박+원한. BoonWaterGrab 진홍 변형.
func _hair_grab(boon_index: int, ctx: Dictionary, params: Dictionary) -> void:
	var per_hits := int(params.get("per_hits", 1))
	if per_hits > 1:
		var k := boon_index + 700000
		_fan_counters[k] = int(_fan_counters.get(k, 0)) + 1
		if _fan_counters[k] < per_hits:
			return
		_fan_counters[k] = 0
	var host := _effect_host()
	if host == null or _player == null or not is_instance_valid(_player) or not (_player is Node3D):
		return
	var origin: Vector3 = (_player as Node3D).global_position + Vector3(0, 0.6, 0)
	var hit_target = ctx.get("target", null)
	var count := int(params.get("count", 1))
	var wonhan_add := int(params.get("wonhan_add", 1))
	var gp := params.duplicate()
	gp["tint"] = CRIMSON
	for k in range(count):
		if get_tree().get_nodes_in_group(GRP_PROJ).size() >= PROJ_CAP:
			break
		var seed_target := _farthest_enemy_excluding(origin, hit_target)
		if seed_target == null:
			seed_target = _farthest_enemy_excluding(origin, null)
		if seed_target == null:
			break
		# 발사 전 원한 부여.
		_add_wonhan(seed_target, wonhan_add, NAKIN_CAP)
		var pr := _WaterGrabScript.new() as Node3D
		pr.add_to_group(GRP_PROJ)
		host.add_child(pr)
		var fire_dir: Vector3 = (seed_target as Node3D).global_position - origin
		pr.call("init_grab", origin, fire_dir, gp, _player, seed_target)


# ══════════════ 처녀귀신 — SHROUD_ZONE(소복결계) ══════════════

## 퍼펙트 회피 시 대형 진홍 결계 — 내부 슬로우/주기 도트(IgniteZone 재사용).
func _shroud_zone(ctx: Dictionary, params: Dictionary) -> void:
	var pos = _ctx_position(ctx)
	if not (pos is Vector3):
		if _player is Node3D:
			pos = (_player as Node3D).global_position
		else:
			return
	var host := _effect_host()
	if host == null:
		return
	var duration := maxf(float(params.get("duration", 5.0)), 0.5)
	var radius := maxf(float(params.get("radius", 5.0)), 0.5)
	var slow_mult := float(params.get("slow_mult", 0.6))
	var zp := {
		"radius": radius,
		"duration": duration,
		"dot_interval": maxf(float(params.get("dot_interval", 0.5)), 0.1),
		"dot_damage": int(params.get("dot_damage", 1)),
		"foxfire_interval": duration + 10.0,
		"foxfire_speed": 1.0,
		"tint": CRIMSON,
	}
	var z := _IgniteZoneScript.new() as Node3D
	z.add_to_group(GRP_ZONE)
	host.add_child(z)
	z.call("init_zone", pos, zp, GRP_PROJ, PROJ_CAP)
	# 생성 즉시 반경 적 감속.
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node3D) or e.is_in_group("boss"):
			continue
		if ((e as Node3D).global_position - pos).length() <= radius:
			if e.has_method("apply_zone_slow"):
				e.call("apply_zone_slow", slow_mult)


# ══════════════ 처녀귀신 — HAIR_DETONATE(단발참) ══════════════

## 일섬 착지 시 GRP_ZONE 결계존 일제 소모 → 각 존 위치 방사 폭발 + 원한 적 처형.
func _hair_detonate(ctx: Dictionary, params: Dictionary) -> void:
	if _player == null or not is_instance_valid(_player) or not (_player is Node3D):
		return
	var knockback := float(params.get("knockback", 12.0))
	var burst_radius := maxf(float(params.get("burst_radius", 3.0)), 0.5)
	var threshold := int(params.get("execute_threshold", 3))
	var zones: Array = []
	for z in get_tree().get_nodes_in_group(GRP_ZONE):
		if is_instance_valid(z) and z is Node3D:
			zones.append(z)
	if zones.size() == 0:
		# 폴백 — 존 없으면 PC 중심 1회 폭발.
		var pc_pos: Vector3 = (_player as Node3D).global_position
		_spawn_burst_particles(pc_pos + Vector3(0, 0.6, 0), 26, 1.6, CRIMSON)
		for e in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(e) or not (e is Node3D) or e.is_in_group("boss"):
				continue
			var out: Vector3 = (e as Node3D).global_position - pc_pos
			out.y = 0.0
			if out.length() <= burst_radius and out.length() > 0.05:
				if e.has_method("apply_knockback"):
					e.call("apply_knockback", out.normalized(), knockback)
		return
	for z in zones:
		if not is_instance_valid(z) or not (z is Node3D):
			continue
		var zcenter: Vector3 = (z as Node3D).global_position
		# 반경 적 폭발.
		for e in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(e) or not (e is Node3D) or e.is_in_group("boss"):
				continue
			var out: Vector3 = (e as Node3D).global_position - zcenter
			out.y = 0.0
			if out.length() <= burst_radius and out.length() > 0.05:
				if e.has_method("apply_knockback"):
					e.call("apply_knockback", out.normalized(), knockback)
				# 원한 적 처형.
				if int(e.get_meta("wonhan_marks", 0)) > 0:
					var hp_now := _enemy_hp(e)
					if hp_now >= 0 and hp_now <= threshold:
						if e.has_method("take_hit"):
							e.call("take_hit", 999)
		_spawn_burst_particles(zcenter + Vector3(0, 0.6, 0), 26, 1.6, CRIMSON)
		# 존 소모.
		if z.has_method("_fade"):
			z.call("_fade")
		else:
			z.queue_free()


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
