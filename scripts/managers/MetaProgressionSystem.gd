class_name MetaProgressionSystem
extends RefCounted

## Permanent between-run progression — souls (혼) ledger + passive levels.
## Sister system to SaveSystem (best records). RefCounted static class,
## same pattern as SaveSystem / UpgradeSystem. Save file is its own
## `user://meta.cfg` so save-format breakage in one doesn't take the
## other with it.
##
## Run-time flow:
##   1. OutGame boots → reads souls + passive_level for the menu.
##   2. Player picks "Start" → Main.tscn loads → Main._ready calls
##      `MetaProgressionSystem.apply_to(player, exp_system)` which walks
##      every owned passive and mutates the live PC / ExpSystem.
##   3. Run ends → Main calls `record_clear_reward` (boss kill) or
##      `record_death_reward` (PC died), which credits 혼 and returns
##      the amount so the result screen can display it.
##   4. Player returns to OutGame → MetaMenu shows new balance, can
##      `upgrade(passive_id)` if they can afford it.

const META_PATH := "user://meta.cfg"

## Source of truth for which passives exist + their defaults. Order
## here drives the MetaMenu row order — keep the most universally
## useful ones at the top.
const PASSIVE_PATHS := [
	"res://resources/meta/passives/hp_bonus.tres",
	"res://resources/meta/passives/slash_width.tres",
	"res://resources/meta/passives/move_speed.tres",
	"res://resources/meta/passives/exp_gain.tres",
	"res://resources/meta/passives/evade_cooldown.tres",
	"res://resources/meta/passives/iframe_extra.tres",
	"res://resources/meta/passives/free_card.tres",
]

static var _cfg: ConfigFile = null
static var _passives: Array = []
static var _passives_loaded: bool = false


# ─────────────────────────────────────────────────────────────
# Load / save plumbing
# ─────────────────────────────────────────────────────────────

static func _ensure_loaded() -> void:
	if _cfg != null:
		return
	_cfg = ConfigFile.new()
	var err := _cfg.load(META_PATH)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning("MetaProgressionSystem: load failed code=%s — starting fresh" % err)


static func _ensure_passives_loaded() -> void:
	if _passives_loaded:
		return
	_passives_loaded = true
	for path in PASSIVE_PATHS:
		var res = load(path)
		if res != null and res is MetaPassive:
			_passives.append(res)
		else:
			push_warning("MetaProgressionSystem: failed to load passive at %s" % path)


static func save() -> void:
	_ensure_loaded()
	var err := _cfg.save(META_PATH)
	if err != OK:
		push_warning("MetaProgressionSystem: save failed code=%s" % err)


# ─────────────────────────────────────────────────────────────
# 혼(souls) ledger
# ─────────────────────────────────────────────────────────────

static func souls() -> int:
	_ensure_loaded()
	return int(_cfg.get_value("ledger", "souls", 0))


static func add_souls(amount: int) -> void:
	if amount <= 0:
		return
	_ensure_loaded()
	var current: int = souls()
	_cfg.set_value("ledger", "souls", current + amount)
	save()


## Try to deduct `amount`. Returns true on success, false (no change) if
## the wallet didn't have enough.
static func spend_souls(amount: int) -> bool:
	if amount <= 0:
		return true
	_ensure_loaded()
	var current: int = souls()
	if current < amount:
		return false
	_cfg.set_value("ledger", "souls", current - amount)
	save()
	return true


# ─────────────────────────────────────────────────────────────
# 골드(gold) ledger — basic out-game currency. Souls = upgrade/unlock
# currency; gold is the general-purpose wallet earned automatically every
# run from kills + survival time (shop / cosmetics later).
# ─────────────────────────────────────────────────────────────

## Gold awarded per kill at run end.
const _GOLD_PER_KILL := 3
## Gold awarded per second survived at run end.
const _GOLD_PER_SEC := 1.0


static func gold() -> int:
	_ensure_loaded()
	return int(_cfg.get_value("ledger", "gold", 0))


static func add_gold(amount: int) -> void:
	if amount <= 0:
		return
	_ensure_loaded()
	_cfg.set_value("ledger", "gold", gold() + amount)
	save()


static func spend_gold(amount: int) -> bool:
	if amount <= 0:
		return true
	_ensure_loaded()
	var current: int = gold()
	if current < amount:
		return false
	_cfg.set_value("ledger", "gold", current - amount)
	save()
	return true


## Auto-award gold at run end (clear OR death) from kills + time survived.
##   gold = kills * 3 + floor(time_seconds)
## Returns the amount so the result screen can show "+N 골드".
static func record_gold_reward(kills: int, time_seconds: float) -> int:
	var g: int = kills * _GOLD_PER_KILL + int(time_seconds * _GOLD_PER_SEC)
	if g < 0:
		g = 0
	add_gold(g)
	return g


# ─────────────────────────────────────────────────────────────
# Passive level queries
# ─────────────────────────────────────────────────────────────

static func all_passives() -> Array:
	_ensure_passives_loaded()
	return _passives


static func passive_by_id(id: String) -> MetaPassive:
	_ensure_passives_loaded()
	for p in _passives:
		if p.id == id:
			return p
	return null


static func passive_level(id: String) -> int:
	_ensure_loaded()
	return int(_cfg.get_value("passives", id, 0))


static func upgrade_cost(id: String) -> int:
	var p := passive_by_id(id)
	if p == null:
		return -1
	return p.cost_at(passive_level(id))


static func can_upgrade(id: String) -> bool:
	var p := passive_by_id(id)
	if p == null:
		return false
	var lvl := passive_level(id)
	if lvl >= p.max_level:
		return false
	return souls() >= p.cost_at(lvl)


## Spend souls and bump the passive one level. Returns true on success,
## false if maxed or unaffordable. The MetaMenu reads this return and
## either repaints (true) or flashes the cost (false).
static func upgrade(id: String) -> bool:
	var p := passive_by_id(id)
	if p == null:
		return false
	var lvl := passive_level(id)
	if lvl >= p.max_level:
		return false
	var cost := p.cost_at(lvl)
	if not spend_souls(cost):
		return false
	_ensure_loaded()
	_cfg.set_value("passives", id, lvl + 1)
	save()
	return true


# ─────────────────────────────────────────────────────────────
# Card unlocks (M5)
# ─────────────────────────────────────────────────────────────

## Initial cards are hardcoded unlocked at the UpgradeSystem level
## (`initial: true` in CARDS). For everything else, we store an
## `unlock_<id> = true` flag in the [unlocks] section once the player
## spends souls on it. Reading defaults to false for any id we don't
## explicitly know about — UpgradeSystem.draw treats unknowns as
## locked, matching the conservative behaviour.
static func is_card_unlocked(id: String) -> bool:
	_ensure_loaded()
	return bool(_cfg.get_value("unlocks", id, false))


## UpgradeSystem owns the cost table — we just expose a setter so the
## MetaMenu doesn't have to round-trip through UpgradeSystem.unlock.
## In practice CardUnlock reads cost from UpgradeSystem.CARDS directly
## and passes it here; this signature lets a different cost source
## plug in later (per-chapter tiers, etc.) without changing the API.
static func unlock_card(id: String, cost: int) -> bool:
	if id.is_empty():
		return false
	if is_card_unlocked(id):
		return false  # Already unlocked — caller spent nothing.
	if cost < 0:
		return false
	if not spend_souls(cost):
		return false
	_ensure_loaded()
	_cfg.set_value("unlocks", id, true)
	save()
	return true


# ─────────────────────────────────────────────────────────────
# Apply to live PC
# ─────────────────────────────────────────────────────────────

## Walk every owned passive and mutate the live PC / ExpSystem. Called
## from Main._ready right after PC + ExpSystem are built, so PlayerData
## tweaks land before the first _physics_process tick.
static func apply_to(player: Node, exp_system: Node) -> void:
	_ensure_loaded()
	_ensure_passives_loaded()
	for passive in _passives:
		var lvl := passive_level(passive.id)
		if lvl <= 0:
			continue
		_apply_effect(passive, lvl, player, exp_system)


## 4안 — 아웃게임(메타 패시브) 효과 기획 초기화.
## 패시브 시스템(souls 적립 · 강화 단계 저장 · MetaMenu UI · 카드 언락)은
## 그대로 유지하되, 실제 능력치 적용은 비활성화한다. 새 효과 기획이
## 정해지면 4안 노션 "효과 기획" DB(구분=아웃게임)를 단일 출처로 이 match를
## 복원/재작성. 기존 effect_kind(hp/move_speed/slash_width/exp_gain/
## evade_cooldown/iframe_extra/free_card)는 참고용으로 .tres에 보존됨.
static func _apply_effect(_passive: MetaPassive, _lvl: int, _player: Node, _exp_system: Node) -> void:
	# Intentionally no-op until the meta passive effects are re-designed.
	pass


# ─────────────────────────────────────────────────────────────
# Run-end rewards
# ─────────────────────────────────────────────────────────────

## Chapter clear → fat reward. Formula tuned so a clean Ch1 run nets
## ~40-60 혼 (Iron Will single-step = 5, so a clear funds 8+ upgrades).
static func record_clear_reward(chapter_id: int, _time_seconds: float, kills: int, level: int) -> int:
	var reward: int = 10 + chapter_id * 5 + level * 2 + int(kills / 5)
	add_souls(reward)
	return reward


## PC death → consolation reward. About half a clear so dying isn't
## net-zero (the player still earns SOMETHING to bring back), but
## meaningfully less than completion.
static func record_death_reward(_chapter_id: int, _time_seconds: float, kills: int, level: int) -> int:
	var reward: int = int(kills / 10) + max(level - 1, 0)
	if reward < 1:
		reward = 1  # Floor: even an instant death drops 1 혼.
	add_souls(reward)
	return reward


# ─────────────────────────────────────────────────────────────
# Debug
# ─────────────────────────────────────────────────────────────

## Wipe everything — handy for a debug "reset meta" menu later.
static func reset_all() -> void:
	_ensure_loaded()
	for section in _cfg.get_sections():
		_cfg.erase_section(section)
	save()


## Convenience for the CardUnlock screen — list every unlocked card id.
static func unlocked_card_ids() -> PackedStringArray:
	_ensure_loaded()
	var out: PackedStringArray = PackedStringArray()
	if not _cfg.has_section("unlocks"):
		return out
	for key in _cfg.get_section_keys("unlocks"):
		if bool(_cfg.get_value("unlocks", key, false)):
			out.append(key)
	return out
