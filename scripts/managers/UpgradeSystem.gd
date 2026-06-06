class_name UpgradeSystem
extends RefCounted

## Card pool + apply logic for level-up upgrades.
##
## ── 4안 재설계 ──
## 레벨업 효과 기획을 초기화하고 4종으로 재정의 (조작 코어 개편에 맞춤).
## 카드 풀 언락 / draw / initial 구조(기능·템플릿)는 그대로 두고 효과만
## 교체. 신규 효과는 4안 노션 페이지의 "효과 기획" DB를 단일 출처로.
##   질풍       — 이동 속도 +12%
##   강건       — 최대 HP +1칸
##   예리한 비도 — 비도 데미지 +1
##   기 충전    — 일섬 게이지 획득량 +20%

const _MetaScript := preload("res://scripts/managers/MetaProgressionSystem.gd")

const CARDS := [
	{"id": "move_speed",   "name": "질풍",        "desc": "이동 속도 +12%",          "initial": true, "unlock_cost": 0},
	{"id": "max_hp",       "name": "강건",        "desc": "최대 HP +1칸",            "initial": true, "unlock_cost": 0},
	{"id": "kunai_damage", "name": "예리한 비도",  "desc": "비도 데미지 +1",          "initial": true, "unlock_cost": 0},
	{"id": "slash_gauge",  "name": "기 충전",     "desc": "일섬 게이지 획득량 +20%",  "initial": true, "unlock_cost": 0},
]


## Draw `n` distinct cards from the AVAILABLE pool (initial OR unlocked).
static func draw(n: int) -> Array:
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
	for c in CARDS:
		if String(c.get("id", "")) == id:
			return c
	return null


## Apply a card's effect to the live PC + EXP system. Pure dispatch — no UI.
static func apply(card_id: String, player: Node, _exp_system: Node) -> void:
	match card_id:
		"move_speed":
			if player and player.data:
				player.data.move_speed *= 1.12
		"max_hp":
			var hp: Node = player.get_node_or_null("HealthComponent")
			if hp != null:
				hp.max_hp += 1
				hp.hp += 1
		"kunai_damage":
			if player and player.data:
				player.data.kunai_damage += 1
		"slash_gauge":
			if player and "slash_gauge_gain_mult" in player:
				player.slash_gauge_gain_mult += 0.2
		_:
			push_warning("UpgradeSystem: unknown card id '%s'" % card_id)
