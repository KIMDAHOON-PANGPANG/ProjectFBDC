class_name UpgradeSystem
extends RefCounted

## 레벨업 카드 풀 + 적용 로직. ── 데이터 테이블화(CSV) ──
## 카드 목록·효과 수치를 data/upgrades.csv 에서 읽는다(로우 데이터 = 데이터 드리블).
##   CSV: 1행 헤더 / 2행 한글주석(스킵) / 3행~ 데이터.
##   컬럼: id, name, desc, value, initial(1=항상 풀), unlock_cost
##
## ⚠ M8 S1 — 기존 스킬 빌드(레벨업 카드 효과) 전면 철거. apply() 는 no-op 으로
## 비활성(권속 은혜 시스템으로 교체 예정). draw/3택 골격·시그니처(draw/card_by_id/
## value_for/all_cards/_load_csv)는 LevelUpScreen/CardUnlock/Main/Testplay 가 계속
## 호출하므로 그대로 유지한다. upgrades.csv 카드 로우는 비워 풀이 비어 있다(카드 0장).

const _MetaScript := preload("res://scripts/managers/MetaProgressionSystem.gd")
const _CSV := "res://data/upgrades.csv"

## 로드된 카드 목록(CSV). CardUnlock 등 외부는 all_cards() 로 접근(자동 로드).
static var CARDS: Array = []
static var _loaded: bool = false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	CARDS = _load_csv()


## 외부 접근용 — 로드 보장 후 카드 목록 반환.
static func all_cards() -> Array:
	_ensure_loaded()
	return CARDS


static func _clean(s: String) -> String:
	return s.lstrip("﻿").strip_edges()


static func _float_field(d: Dictionary, key: String, fallback: float) -> float:
	var s := String(d.get(key, ""))
	if s.is_valid_float():
		return s.to_float()
	return fallback


static func _int_field(d: Dictionary, key: String, fallback: int) -> int:
	var s := String(d.get(key, ""))
	if s.is_valid_int():
		return s.to_int()
	return fallback


static func _bool_field(d: Dictionary, key: String, fallback: bool) -> bool:
	var s := String(d.get(key, "")).to_lower()
	if s == "":
		return fallback
	return s == "1" or s == "true" or s == "yes"


static func _load_csv() -> Array:
	var out: Array = []
	if not FileAccess.file_exists(_CSV):
		push_warning("UpgradeSystem: %s 없음 — 카드 0장" % _CSV)
		return out
	var f := FileAccess.open(_CSV, FileAccess.READ)
	if f == null:
		return out
	var rows: Array = []
	while not f.eof_reached():
		var line: PackedStringArray = f.get_csv_line()
		if line.size() > 0:
			rows.append(line)
	f.close()
	if rows.size() < 1:
		return out
	var headers: PackedStringArray = rows[0]
	for r in range(1, rows.size()):
		var row: PackedStringArray = rows[r]
		if row.size() == 0:
			continue
		var first := _clean(row[0])
		# 헤더/2행 한글주석/빈 id 스킵.
		if first == "" or first == "id" or first == "식별자(영문키)":
			continue
		var d: Dictionary = {}
		for i in range(min(headers.size(), row.size())):
			d[_clean(headers[i])] = _clean(row[i])
		var card := {
			"id": String(d.get("id", "")),
			"name": String(d.get("name", "?")),
			"desc": String(d.get("desc", "")),
			"value": _float_field(d, "value", 0.0),
			"initial": String(d.get("initial", "1")) == "1",
			"unlock_cost": _int_field(d, "unlock_cost", 0),
			"weight": maxf(_float_field(d, "weight", 1.0), 0.0),
			"rarity": String(d.get("rarity", "normal")),
			"available_after_sec": maxf(_float_field(d, "available_after_sec", 0.0), 0.0),
			"unique": _bool_field(d, "unique", false),
		}
		if card["id"] == "":
			continue
		out.append(card)
	return out


## AVAILABLE 풀(initial 또는 언락됨)에서 서로 다른 카드 n 장 뽑기.
static func draw(n: int, elapsed_sec: float = 0.0, player: Node = null) -> Array:
	_ensure_loaded()
	var pool: Array = []
	for c in CARDS:
		if _is_available(c, elapsed_sec, player):
			pool.append(c)
	return _draw_weighted(pool, n)


static func _is_available(c: Dictionary, elapsed_sec: float = 0.0, player: Node = null) -> bool:
	if elapsed_sec + 0.001 < float(c.get("available_after_sec", 0.0)):
		return false
	var id := String(c.get("id", ""))
	if id.is_empty():
		return false
	if bool(c.get("unique", false)) and player != null:
		var owned_prop := "has_%s" % id
		if owned_prop in player and bool(player.get(owned_prop)):
			return false
	return bool(c.get("initial", false)) or _MetaScript.is_card_unlocked(id)


static func _draw_weighted(pool: Array, n: int) -> Array:
	var available := pool.duplicate()
	var out: Array = []
	while out.size() < n and not available.is_empty():
		var total_weight := 0.0
		for c in available:
			total_weight += maxf(float(c.get("weight", 1.0)), 0.0)
		if total_weight <= 0.0:
			available.shuffle()
			out.append(available.pop_back())
			continue
		var pick := randf() * total_weight
		var acc := 0.0
		var picked_idx := available.size() - 1
		for i in range(available.size()):
			acc += maxf(float(available[i].get("weight", 1.0)), 0.0)
			if pick <= acc:
				picked_idx = i
				break
		out.append(available[picked_idx])
		available.remove_at(picked_idx)
	return out


static func card_by_id(id: String) -> Variant:
	_ensure_loaded()
	for c in CARDS:
		if String(c.get("id", "")) == id:
			return c
	return null


static func value_for(id: String) -> float:
	var c = card_by_id(id)
	if c == null:
		return 0.0
	return float(c.get("value", 0.0))


## 카드 효과를 라이브 PC 에 적용. ── M8 S1: 기존 스킬 빌드 철거로 no-op ──
## 권속 은혜 시스템 교체 전까지 어떤 카드 효과도 적용하지 않는다(풀도 비어 있어
## 실제로는 호출돼도 card_id 가 없음). 시그니처는 Main/Testplay/ArenaDebug 가
## 계속 호출하므로 유지. 로드 보장 + null 가드만 남긴다.
static func apply(_card_id: String, _player: Node, _exp_system: Node) -> void:
	_ensure_loaded()
	# 의도적으로 아무 효과도 적용하지 않음(레거시 카드 효과 전면 비활성).
	return
