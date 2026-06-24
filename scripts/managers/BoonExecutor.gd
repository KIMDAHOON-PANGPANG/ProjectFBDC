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

## 구미호 핑크 틴트(공통).
const PINK := Color(1.0, 0.37, 0.69)

## FX 노드 그룹 + 동시 상한(성능 안전망).
const GRP_ZONE := "boon_fx_zone"
const GRP_SPIRIT := "boon_spirit"
const GRP_PROJ := "boon_proj"
const SPIRIT_CAP := 8
const PROJ_CAP := 24

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


func _on_kill_via_slash(ctx: Dictionary) -> void:
	# 처치 = 피드(굶주림 리셋) — LIFESTEAL 카드 없어도 처치만으로 굶주림 해소.
	if _player != null and is_instance_valid(_player) and _player.has_method("boon_feed"):
		_player.call("boon_feed")
	_for_each_effect(_TriggerBusScript.ON_KILL_VIA_SLASH, "LIFESTEAL",
		func(_i, params): _lifesteal(ctx, params))


func _on_dash_pass_enemy(ctx: Dictionary) -> void:
	_for_each_effect(_TriggerBusScript.ON_DASH_PASS_ENEMY, "APPLY_MARK",
		func(i, params): _apply_mark(i, ctx, params))


func _on_slash_end(ctx: Dictionary) -> void:
	_for_each_effect(_TriggerBusScript.ON_SLASH_END, "SUMMON_SPIRIT",
		func(_i, params): _summon_spirits(ctx, params))


func _on_slash_charged(ctx: Dictionary) -> void:
	_for_each_effect(_TriggerBusScript.ON_SLASH_CHARGED, "SLASH_FAN",
		func(_i, params): _slash_fan(ctx, params))


func _on_just_dodge(ctx: Dictionary) -> void:
	_for_each_effect(_TriggerBusScript.ON_JUST_DODGE, "RADIAL_BURST",
		func(_i, params): _radial_burst(ctx, params))


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


# ══════════════ 더미 FX 스폰 헬퍼 ══════════════

## 표식 적용 시 적 위에 핑크 인장 플래시(짧은 디스크 펄스).
func _spawn_mark_flash(target: Node) -> void:
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
	mat.albedo_color = Color(PINK.r, PINK.g, PINK.b, 0.7)
	mat.emission_enabled = true
	mat.emission = PINK
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
	mat.albedo_color = Color(PINK.r, PINK.g, PINK.b, 0.4)
	mat.emission_enabled = true
	mat.emission = PINK
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


## 공용 파편 버스트(핑크 CPUParticles3D 1회, one_shot).
func _spawn_burst_particles(pos: Vector3, amount: int, scale: float) -> void:
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
	mat.albedo_color = Color(PINK.r, PINK.g, PINK.b, 0.9)
	mat.emission_enabled = true
	mat.emission = PINK
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
