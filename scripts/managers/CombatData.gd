class_name CombatData
extends RefCounted

## data/*.csv 의 PC·적 전투 파라미터를 읽어 라이브 객체에 적용하는 단일 로더.
## (요청: 엑셀/CSV 컴뱃 테이블 연동 — data/combat_table.xlsx 를 편집 후 각 시트를
##  pc.csv / enemy.csv 로 내보내면 게임이 이 CSV 를 읽는다.)
##
## CSV 레이아웃(combat_table.xlsx 와 동일):
##   1행 = 영문 컬럼명(키)  ·  2행 = 한글 설명(건너뜀)  ·  3행~ = 데이터
##   - PC   : 데이터 행 1개 (id = "pc"). 컬럼명 = PlayerData 필드명.
##   - ENEMY: 행마다 적 종류. id 코드(ENUM) 101=근접 102=원거리 103=엘리트
##            201/202/203=보스1/2/3.
##
## 규칙:
##   - 셀이 비어 있으면 호출부가 넘긴 기존 기본값을 유지(안전 폴백).
##   - 숫자 데이터는 ASCII 라 CSV 인코딩(UTF-8/cp949)과 무관하게 읽힌다.
##   - ⚠ 잡몹(101)·엘리트(103) max_hp 는 적용하지 않는다(잡몹=WaveManager 레벨업,
##     엘리트=effect_type 표가 관리). 보스 max_hp 는 변형 고정값이라 적용.
##
## 호출(JSON 판과 동일 인터페이스):
##   Player._ready                    → apply_to_player(self)
##   Melee/Ranged/Elite/Boss._ready   → apply_to_enemy(self, "melee"/"ranged"/"elite"/"boss")
##
## RefCounted + 정적 메서드. 다른 스크립트는 preload + 정적 호출로 참조.

const _PC_CSV := "res://data/pc.csv"
const _ENEMY_CSV := "res://data/enemy.csv"

static var _pc: Dictionary = {}        # 필드명(String) -> 값(String)
static var _enemy: Dictionary = {}     # id(int) -> { 필드명: 값(String) }
static var _loaded: bool = false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_pc = _read_pc(_PC_CSV)
	_enemy = _read_enemy(_ENEMY_CSV)


## CSV 전체를 행 배열로 읽는다 (각 행 = PackedStringArray, 따옴표/콤마 처리됨).
static func _read_rows(path: String) -> Array:
	var rows: Array = []
	if not FileAccess.file_exists(path):
		push_warning("CombatData: file not found — %s (기본값 유지)" % path)
		return rows
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return rows
	while not f.eof_reached():
		var line: PackedStringArray = f.get_csv_line()
		if line.size() > 0:
			rows.append(line)
	f.close()
	return rows


## 첫 셀의 BOM(엑셀 UTF-8 저장 시) 제거 + 양끝 공백 제거.
static func _clean(s: String) -> String:
	return s.lstrip("﻿").strip_edges()


## PC: id == "pc" 인 데이터 행을 헤더와 매핑. (2행 한글 주석은 자동 무시.)
static func _read_pc(path: String) -> Dictionary:
	var rows := _read_rows(path)
	if rows.size() < 1:
		return {}
	var headers: PackedStringArray = rows[0]
	for r in range(1, rows.size()):
		var row: PackedStringArray = rows[r]
		if row.size() == 0:
			continue
		if _clean(row[0]) != "pc":
			continue
		var d: Dictionary = {}
		for i in range(min(headers.size(), row.size())):
			d[_clean(headers[i])] = _clean(row[i])
		return d
	return {}


## ENEMY: 첫 셀이 정수 id 인 행만 데이터로 취급(헤더/한글주석/이름행 자동 스킵).
static func _read_enemy(path: String) -> Dictionary:
	var rows := _read_rows(path)
	if rows.size() < 1:
		return {}
	var headers: PackedStringArray = rows[0]
	var out: Dictionary = {}
	for r in range(1, rows.size()):
		var row: PackedStringArray = rows[r]
		if row.size() == 0:
			continue
		var first := _clean(row[0])
		if not first.is_valid_int():
			continue
		var d: Dictionary = {}
		for i in range(min(headers.size(), row.size())):
			d[_clean(headers[i])] = _clean(row[i])
		out[int(first)] = d
	return out


# ── 문자열 → 타입 변환 헬퍼 ──
static func _to_f(raw: String, fallback: float) -> float:
	if raw == "":
		return fallback
	return raw.to_float()

static func _to_i(raw: String, fallback: int) -> int:
	if raw == "":
		return fallback
	return raw.to_int() if raw.is_valid_int() else int(raw.to_float())

static func _to_b(raw: String, fallback: bool) -> bool:
	if raw == "":
		return fallback
	var u := raw.to_upper()
	return u == "TRUE" or u == "1"

## 행 dict 에서 키를 읽어 float/int/bool 로 — 없거나 비면 fallback.
static func _rf(row: Dictionary, key: String, fallback: float) -> float:
	return _to_f(String(row.get(key, "")), fallback)
static func _ri(row: Dictionary, key: String, fallback: int) -> int:
	return _to_i(String(row.get(key, "")), fallback)
static func _rb(row: Dictionary, key: String, fallback: bool) -> bool:
	return _to_b(String(row.get(key, "")), fallback)


# ─────────────────────────────────────────────────────────────
# PC — 컬럼명 = PlayerData 필드명. 존재하는 필드만, 현재 타입으로 변환해 적용.
# ─────────────────────────────────────────────────────────────

static func apply_to_player(player: Node) -> void:
	_ensure_loaded()
	if player == null or not ("data" in player) or player.data == null:
		return
	if _pc.is_empty():
		return
	var d = player.data
	for key in _pc.keys():
		if key == "id":
			continue
		var raw := String(_pc[key])
		if raw == "":
			continue
		if not (key in d):
			continue  # PlayerData 에 없는 컬럼은 무시(안전)
		var cur = d.get(key)
		match typeof(cur):
			TYPE_INT:
				d.set(key, _to_i(raw, cur))
			TYPE_FLOAT:
				d.set(key, _to_f(raw, cur))
			TYPE_BOOL:
				d.set(key, _to_b(raw, cur))
			_:
				d.set(key, raw)


# ─────────────────────────────────────────────────────────────
# 적 / 보스 — kind → id 코드로 행을 찾아 archetype 별로 매핑.
# ─────────────────────────────────────────────────────────────

static func apply_to_enemy(enemy: Node, kind: String) -> void:
	_ensure_loaded()
	if enemy == null or _enemy.is_empty():
		return
	var id: int = -1
	match kind:
		"melee": id = 101
		"ranged": id = 102
		"elite": id = 103
		"boss": id = 200 + (int(enemy.boss_id) if "boss_id" in enemy else 1)
		_: return
	if not _enemy.has(id):
		return
	var row: Dictionary = _enemy[id]
	match kind:
		"melee": _apply_melee(enemy, row)
		"ranged": _apply_ranged(enemy, row)
		"elite": _apply_elite(enemy, row)
		"boss": _apply_boss(enemy, row)


static func _apply_melee(e, row: Dictionary) -> void:
	if "data" in e and e.data != null:
		e.data.move_speed = _rf(row, "move_speed", e.data.move_speed)
		e.data.melee_attack_cooldown = _rf(row, "attack_cooldown", e.data.melee_attack_cooldown)
	e.attack_range = _rf(row, "attack_range", e.attack_range)
	e.attack_damage = _ri(row, "attack_damage", e.attack_damage)
	e.fan_radius = _rf(row, "fan_radius", e.fan_radius)
	e.fan_angle_deg = _rf(row, "fan_angle_deg", e.fan_angle_deg)
	# max_hp 미적용 (WaveManager 레벨업이 관리).


static func _apply_ranged(e, row: Dictionary) -> void:
	if "data" in e and e.data != null:
		e.data.move_speed = _rf(row, "move_speed", e.data.move_speed)
		e.data.ranged_attack_range = _rf(row, "attack_range", e.data.ranged_attack_range)
		e.data.ranged_attack_cooldown = _rf(row, "attack_cooldown", e.data.ranged_attack_cooldown)
		e.data.ranged_keep_distance = _rf(row, "keep_distance", e.data.ranged_keep_distance)
		e.data.arrow_speed = _rf(row, "arrow_speed", e.data.arrow_speed)
	e.aim_lock_duration = _rf(row, "aim_lock_duration", e.aim_lock_duration)
	# max_hp / 화살 데미지 미적용.


static func _apply_elite(e, row: Dictionary) -> void:
	e.move_speed = _rf(row, "move_speed", e.move_speed)
	e.attack_range = _rf(row, "attack_range", e.attack_range)
	e.attack_cooldown = _rf(row, "attack_cooldown", e.attack_cooldown)
	e.attack_damage = _ri(row, "attack_damage", e.attack_damage)
	e.fan_radius = _rf(row, "fan_radius", e.fan_radius)
	e.fan_angle_deg = _rf(row, "fan_angle_deg", e.fan_angle_deg)
	e.separation_radius = _rf(row, "separation_radius", e.separation_radius)
	e.separation_weight = _rf(row, "separation_weight", e.separation_weight)
	# max_hp 미적용 (effect_type 표가 관리).


static func _apply_boss(e, row: Dictionary) -> void:
	e.move_speed = _rf(row, "move_speed", e.move_speed)
	e.attack_range = _rf(row, "attack_range", e.attack_range)
	e.attack_damage = _ri(row, "attack_damage", e.attack_damage)
	e.fan_radius = _rf(row, "fan_radius", e.fan_radius)
	e.fan_angle_deg = _rf(row, "fan_angle_deg", e.fan_angle_deg)
	e.max_hp = _ri(row, "max_hp", e.max_hp)  # 보스 HP 는 적용(변형 고정값).
	e.attack_cooldown = _rf(row, "attack_cooldown", e.attack_cooldown)
	e.parry_yellow_ratio = _rf(row, "parry_yellow_ratio", e.parry_yellow_ratio)
	e.parry_window_pre_sweep = _rf(row, "parry_window_pre_sweep", e.parry_window_pre_sweep)
	e.parry_window_post_sweep = _rf(row, "parry_window_post_sweep", e.parry_window_post_sweep)
	e.block_duration = _rf(row, "block_duration", e.block_duration)
	e.parry_boost_window_ms = _ri(row, "parry_boost_window_ms", e.parry_boost_window_ms)
	e.parry_boost_dmg = _ri(row, "parry_boost_dmg", e.parry_boost_dmg)
	e.enable_white_signal = _rb(row, "enable_white_signal", e.enable_white_signal)
	e.white_ratio = _rf(row, "white_ratio", e.white_ratio)
	e.enable_purple_signal = _rb(row, "enable_purple_signal", e.enable_purple_signal)
	e.purple_ratio = _rf(row, "purple_ratio", e.purple_ratio)
	e.enable_green_signal = _rb(row, "enable_green_signal", e.enable_green_signal)
	e.green_ratio = _rf(row, "green_ratio", e.green_ratio)
