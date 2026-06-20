class_name UpgradeSystem
extends RefCounted

## 레벨업 카드 풀 + 적용 로직. ── 데이터 테이블화(CSV) ──
## 카드 목록·효과 수치를 data/upgrades.csv 에서 읽는다(로우 데이터 = 데이터 드리블).
##   CSV: 1행 헤더 / 2행 한글주석(스킵) / 3행~ 데이터.
##   컬럼: id, name, desc, value, initial(1=항상 풀), unlock_cost
##
## 효과(비도 삭제, 이동속도·최대HP 유지 + 신규):
##   move_speed       이동 속도 +value(배)
##   max_hp           최대 HP +value(칸)
##   slash_range      기본 공격(일섬) 범위 ×(1+...) — Player.slash_size_mult
##   charge_speed     기본 공격 충전 속도 + — Player.charge_speed_bonus
##   dodge            회피율 +value — Player.dodge_chance
##   overheat_reduce  탈진 시간 -value(초) — Player.overheat_dur_reduce
##   heat_delay_reduce 열 감소 시작 -value(초) — Player.heat_delay_reduce
##
## ⚠ 데이터 .tres 영구 변형은 런 너머 누적되므로, 열/충전/회피/범위는 Player 런타임
## 보너스 필드에 적용(런마다 리셋). move_speed/max_hp 만 직접(pc.csv·인스턴스 리셋).

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
			"value": String(d.get("value", "0")).to_float(),
			"initial": String(d.get("initial", "1")) == "1",
			"unlock_cost": int(String(d.get("unlock_cost", "0")).to_int()) if String(d.get("unlock_cost", "0")).is_valid_int() else 0,
		}
		if card["id"] == "":
			continue
		out.append(card)
	return out


## AVAILABLE 풀(initial 또는 언락됨)에서 서로 다른 카드 n 장 뽑기.
static func draw(n: int) -> Array:
	_ensure_loaded()
	var pool: Array = []
	for c in CARDS:
		if _is_available(c):
			pool.append(c)
	pool.shuffle()
	return pool.slice(0, min(n, pool.size()))


static func _is_available(c: Dictionary) -> bool:
	if c.get("initial", false):
		return true
	var id := String(c.get("id", ""))
	if id.is_empty():
		return false
	return _MetaScript.is_card_unlocked(id)


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


## 카드 효과를 라이브 PC 에 적용. 효과 수치는 CSV value 컬럼.
static func apply(card_id: String, player: Node, _exp_system: Node) -> void:
	_ensure_loaded()
	if player == null:
		return
	var v := value_for(card_id)
	match card_id:
		"move_speed":
			if player.data:
				player.data.move_speed *= (1.0 + v)
		"max_hp":
			var hp: Node = player.get_node_or_null("HealthComponent")
			if hp != null:
				hp.max_hp += int(v)
				hp.hp += int(v)
		"slash_range":
			if "slash_size_mult" in player:
				player.slash_size_mult += v
		"charge_speed":
			if "charge_speed_bonus" in player:
				player.charge_speed_bonus += v
		"dodge":
			if "dodge_chance" in player:
				player.dodge_chance = clamp(player.dodge_chance + v, 0.0, 0.9)
		"overheat_reduce":
			if "overheat_dur_reduce" in player:
				player.overheat_dur_reduce += v
		"heat_delay_reduce":
			if "heat_delay_reduce" in player:
				player.heat_delay_reduce += v
		"attack_power":
			# 기본 공격력 +value — 다중타 적/보스 데미지 + 근접 스윙 데미지에 반영.
			if "attack_power" in player:
				player.attack_power += int(v)
		"evade_refill":
			# 회피 충전 시간 ×(1-value) — 0.4 바닥(보스전에서 너무 빨리 회피 못 쓰게).
			if "evade_refill_mult" in player:
				player.evade_refill_mult = maxf(0.4, player.evade_refill_mult * (1.0 - v))
		"exp_range":
			# 경험치 자석 반경 +value(픽당) — ExpGem 이 player.exp_magnet_mult 로 읽음.
			if "exp_magnet_mult" in player:
				player.exp_magnet_mult += v
		_:
			push_warning("UpgradeSystem: unknown card id '%s'" % card_id)
