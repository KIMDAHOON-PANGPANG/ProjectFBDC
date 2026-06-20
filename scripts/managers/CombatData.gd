class_name CombatData
extends RefCounted

## 몬스터 밸런스를 resources/monster_table.tres(MonsterTable) 에서 읽어 라이브 적에
## 적용하는 단일 로더. (옛 CSV/엑셀 컴뱃 테이블은 인하우스 에디터 플러그인
## "밸런스 툴"(addons/balance_tool) 로 대체 — 더 이상 data/*.csv 를 읽지 않는다.)
##
## PC 밸런스는 player_data.tres(PlayerData) 가 단일 소스이므로 apply_to_player 는 no-op.
##
## 호출(인터페이스 유지):
##   Player._ready                          → apply_to_player(self)   # no-op
##   Melee/Ranged/Elite/Sorcerer/Boss._ready → apply_to_enemy(self, kind)
##   PauseOverlay 몬스터 리스트              → all_enemy_rows()
##
## RefCounted + 정적 메서드. 다른 스크립트는 preload + 정적 호출로 참조.
## (MonsterTable/MonsterStats 는 preload 로 class 등록 보장 — 헤드리스 캐시 안전.)

const _TABLE_PATH := "res://resources/monster_table.tres"
const _MonsterStatsScript := preload("res://scripts/resources/MonsterStats.gd")
const _MonsterTableScript := preload("res://scripts/resources/MonsterTable.gd")

static var _table = null              # MonsterTable
static var _by_id: Dictionary = {}    # id(int) -> MonsterStats
static var _loaded: bool = false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_table = load(_TABLE_PATH)
	_by_id = {}
	if _table != null and "monsters" in _table:
		for m in _table.monsters:
			if m != null:
				_by_id[int(m.id)] = m


# ── PC: player_data.tres 가 단일 소스 — 별도 적용 불필요(no-op). ──
static func apply_to_player(_player: Node) -> void:
	pass


## 몬스터 리스트 UI 용 — id 오름차순 dict 배열(display_name/concept/color/icon).
static func all_enemy_rows() -> Array:
	_ensure_loaded()
	var ids: Array = _by_id.keys()
	ids.sort()
	var out: Array = []
	for id in ids:
		var m = _by_id[id]
		out.append({
			"id": str(m.id),
			"display_name": m.display_name,
			"concept": m.concept,
			"color": m.color,
			"icon": m.icon,
		})
	return out


# ── 적 / 보스 — kind → id 코드로 MonsterStats 찾아 archetype 별 적용. ──

static func apply_to_enemy(enemy: Node, kind: String) -> void:
	_ensure_loaded()
	if enemy == null or _by_id.is_empty():
		return
	var id: int = -1
	match kind:
		"melee": id = 101
		"ranged": id = 102
		"elite": id = 103
		"leaper": id = 104
		"slammer": id = 105
		"sorcerer": id = 106
		"boss": id = 200 + (int(enemy.boss_id) if "boss_id" in enemy else 1)
		_: return
	if not _by_id.has(id):
		return
	var m = _by_id[id]
	match kind:
		"melee", "leaper", "slammer": _apply_melee(enemy, m)
		"ranged": _apply_ranged(enemy, m)
		"elite": _apply_elite(enemy, m)
		"sorcerer": _apply_sorcerer(enemy, m)
		"boss": _apply_boss(enemy, m)


static func _apply_melee(e, m) -> void:
	if "data" in e and e.data != null:
		e.data.move_speed = m.move_speed
		e.data.melee_attack_cooldown = m.attack_cooldown
	e.attack_range = m.attack_range
	e.attack_damage = m.attack_damage
	e.fan_radius = m.fan_radius
	e.fan_angle_deg = m.fan_angle_deg
	if "leap_chance" in e: e.leap_chance = m.leap_chance
	if "leap_radius" in e: e.leap_radius = m.leap_radius
	if "leap_damage" in e: e.leap_damage = m.leap_damage
	if "separation_radius" in e: e.separation_radius = m.separation_radius
	if "separation_weight" in e: e.separation_weight = m.separation_weight
	if "slam_range" in e: e.slam_range = m.slam_range
	if "slam_windup" in e: e.slam_windup = m.slam_windup
	if "slam_radius" in e: e.slam_radius = m.slam_radius
	if "slam_damage" in e: e.slam_damage = m.slam_damage
	if "slam_cooldown" in e: e.slam_cooldown = m.slam_cooldown
	if "armor_max" in e: e.armor_max = m.armor_max
	if "stagger_duration" in e: e.stagger_duration = m.stagger_duration
	# 슬래머는 max_hp 적용(2방컷). 잡몹/리퍼는 EnemyData 기본 유지(레벨업이 관리).
	if m.key == "slammer" and "data" in e and e.data != null:
		e.data.max_hp = m.max_hp


static func _apply_ranged(e, m) -> void:
	if "data" in e and e.data != null:
		e.data.move_speed = m.move_speed
		e.data.ranged_attack_range = m.attack_range
		e.data.ranged_attack_cooldown = m.attack_cooldown
		e.data.ranged_keep_distance = m.keep_distance
		e.data.arrow_speed = m.arrow_speed
		e.data.max_hp = m.max_hp   # 궁수 HP(요청: 1방컷)
	e.aim_lock_duration = m.aim_lock_duration
	if "armor_max" in e: e.armor_max = m.armor_max
	if "stagger_duration" in e: e.stagger_duration = m.stagger_duration


static func _apply_elite(e, m) -> void:
	e.move_speed = m.move_speed
	e.attack_range = m.attack_range
	e.attack_cooldown = m.attack_cooldown
	e.attack_damage = m.attack_damage
	e.fan_radius = m.fan_radius
	e.fan_angle_deg = m.fan_angle_deg
	e.separation_radius = m.separation_radius
	e.separation_weight = m.separation_weight
	if "armor_max" in e: e.armor_max = m.armor_max
	if "stagger_duration" in e: e.stagger_duration = m.stagger_duration
	# max_hp 미적용 (effect_type 표가 관리).


static func _apply_sorcerer(e, m) -> void:
	if "move_speed" in e: e.move_speed = m.move_speed
	if "max_hp" in e: e.max_hp = m.max_hp
	if "vision_range" in e: e.vision_range = m.vision_range
	if "zone_count" in e: e.zone_count = m.zone_count
	if "zone_radius" in e: e.zone_radius = m.zone_radius
	if "zone_spread" in e: e.zone_spread = m.zone_spread
	if "zone_duration" in e: e.zone_duration = m.zone_duration
	if "zone_slow_mult" in e: e.zone_slow_mult = m.zone_slow_mult
	if "zone_precursor" in e: e.zone_precursor = m.zone_precursor
	if "teleport_cooldown" in e: e.teleport_cooldown = m.teleport_cooldown
	if "teleport_range" in e: e.teleport_range = m.teleport_range
	if "armor_max" in e: e.armor_max = m.armor_max
	if "stagger_duration" in e: e.stagger_duration = m.stagger_duration


static func _apply_boss(e, m) -> void:
	e.move_speed = m.move_speed
	e.attack_range = m.attack_range
	e.attack_damage = m.attack_damage
	e.fan_radius = m.fan_radius
	e.fan_angle_deg = m.fan_angle_deg
	e.max_hp = m.max_hp
	e.attack_cooldown = m.attack_cooldown
	e.parry_yellow_ratio = m.parry_yellow_ratio
	e.parry_window_pre_sweep = m.parry_window_pre_sweep
	e.parry_window_post_sweep = m.parry_window_post_sweep
	e.block_duration = m.block_duration
	e.parry_boost_window_ms = m.parry_boost_window_ms
	e.parry_boost_dmg = m.parry_boost_dmg
	e.white_ratio = m.white_ratio
	if "charge_range" in e: e.charge_range = m.charge_range
	if "charge_windup" in e: e.charge_windup = m.charge_windup
	if "charge_speed" in e: e.charge_speed = m.charge_speed
	if "charge_distance" in e: e.charge_distance = m.charge_distance
	if "charge_damage" in e: e.charge_damage = m.charge_damage
	if "charge_recover" in e: e.charge_recover = m.charge_recover
	if "charge_cooldown" in e: e.charge_cooldown = m.charge_cooldown
	if "charge_width" in e: e.charge_width = m.charge_width
	if "armor_max" in e: e.armor_max = m.armor_max
	if "stagger_duration" in e: e.stagger_duration = m.stagger_duration
