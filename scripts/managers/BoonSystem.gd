extends RefCounted

## 권속 은혜(Boon) 데이터 로더 + 조회 API.
## 데이터: data/boons.json — {boons:[...]} 형태.
## 효과 실행(S5) / 3택 UI(S6) 는 이 파일 범위 밖 — 로드+조회만.
## 참조: const _B := preload("res://scripts/managers/BoonSystem.gd") + 정적 호출.

const _JSON := "res://data/boons.json"

## M9-S1: 요괴 그룹핑(YOKAI_COLORS) 철거. 카드 UI(LevelUpScreen/SkillViewer)는 여전히
## 카드 yokai 키로 액센트 색을 묻는다 — 중립 기본색을 반환하는 슬림 헬퍼만 유지.
## M9 가 카드별 색 체계를 정하면 여기서 매핑을 다시 채운다.
static func yokai_color(_y: String) -> Color:
	return Color(0.7, 0.7, 0.7)

static var BOONS: Array = []
static var _by_id: Dictionary = {}
static var _loaded := false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true

	if not FileAccess.file_exists(_JSON):
		push_warning("BoonSystem: boons.json 없음 — 은혜 0장")
		return

	var f := FileAccess.open(_JSON, FileAccess.READ)
	if f == null:
		push_warning("BoonSystem: boons.json 열기 실패")
		return
	var text := f.get_as_text()
	f.close()

	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_warning("BoonSystem: JSON 파싱 실패 — %s" % json.get_error_message())
		return

	var data = json.data
	if not (data is Dictionary):
		push_warning("BoonSystem: 최상위가 Dictionary 가 아님")
		return
	if not (data.get("boons") is Array):
		push_warning("BoonSystem: 'boons' 배열 없음")
		return

	BOONS = data["boons"]
	_by_id = {}

	for b in BOONS:
		if not (b is Dictionary):
			continue
		var id = b.get("id", "")
		if not (id is String) or id == "":
			continue
		if _by_id.has(id):
			push_warning("BoonSystem: 중복 id 스킵 — %s" % id)
			continue
		_by_id[id] = b


static func all_boons() -> Array:
	_ensure_loaded()
	return BOONS


static func by_id(id: String) -> Variant:
	_ensure_loaded()
	return _by_id.get(id, null)


static func rarities_for(id: String) -> Array:
	_ensure_loaded()
	var b = _by_id.get(id, null)
	if b == null:
		return []
	var comps = b.get("components", null)
	if not (comps is Array) or comps.is_empty():
		return []
	var first_comp = comps[0]
	if not (first_comp is Dictionary):
		return []
	var pbr = first_comp.get("params_by_rarity", null)
	if not (pbr is Dictionary):
		return []
	var order := ["chosim", "rare", "uniq", "legend", "master"]
	var result: Array = []
	for r in order:
		if pbr.has(r):
			result.append(r)
	return result


static func params_for(id: String, rarity: String, component_index: int = 0) -> Dictionary:
	_ensure_loaded()
	var b = _by_id.get(id, null)
	if b == null:
		return {}
	var comps = b.get("components", null)
	if not (comps is Array) or component_index >= comps.size():
		return {}
	var comp = comps[component_index]
	if not (comp is Dictionary):
		return {}
	var pbr = comp.get("params_by_rarity", null)
	if not (pbr is Dictionary):
		return {}
	var params = pbr.get(rarity, null)
	if not (params is Dictionary):
		return {}
	return params


static func rarity_for_level(level: int) -> String:
	var weights: Dictionary
	if level <= 4:
		weights = {"chosim": 70, "rare": 25, "uniq": 5}
	elif level <= 7:
		weights = {"chosim": 35, "rare": 40, "uniq": 20, "legend": 5}
	elif level <= 10:
		weights = {"chosim": 10, "rare": 30, "uniq": 35, "legend": 20, "master": 5}
	else:
		weights = {"rare": 15, "uniq": 30, "legend": 35, "master": 20}

	var order := ["chosim", "rare", "uniq", "legend", "master"]
	var total := 0
	for r in order:
		if weights.has(r):
			total += int(weights[r])

	var roll := randi_range(1, total)
	var accum := 0
	for r in order:
		if not weights.has(r):
			continue
		accum += int(weights[r])
		if roll <= accum:
			return r
	return "chosim"


## M9-T6: 빌드 진행 — pool 분기. L2(첫 레벨업·style 미보유)=pillar(발도술 3종)만 결정적 노출,
## L3+(style 보유)=style_kit + support 합성(support_slots 비율). 카드 pool 키:
##   pillar    = 발도술 3종(kind=='style') — 한 판 1택, L2 강제 노출.
##   style_kit = 기존 비-style 35장 — 메인 빌드 카드.
##   support   = 보조 11장 — L3+ 에 support_slots 만큼 끼워 가독성/도배 방지.
## draw_boons 시그니처 불변(count, level, owned_ids). level 을 support 합류(>=3)·support_slots 램프에 실사용.
static func draw_boons(count: int, level: int, owned_ids: Array = []) -> Array:
	_ensure_loaded()
	# 빈 풀(boons.json == [])이면 [] 반환 → 레벨업 오버레이 graceful 스킵(크래시 금지).
	if BOONS.is_empty():
		return []

	var rarity_labels := {
		"chosim": "초심", "rare": "레어", "uniq": "유일",
		"legend": "전설", "master": "마스터"
	}

	# ── 활성 스타일 판정 — style 카드(pillar) 보유 시 그 style_req 를 '활성 스타일'로 본다(필터 기준). ──
	var owns_style := false
	var active_style := ""
	for oid in owned_ids:
		var ob = _by_id.get(String(oid), null)
		if ob is Dictionary and String(ob.get("kind", "")) == "style":
			owns_style = true
			var sr := String(ob.get("style_req", ""))
			if sr != "":
				active_style = sr
			break

	# ── L2(첫 레벨업·style 미보유) — pillar(발도술 3종)만 결정적 노출(한 판 = 발도술 1픽 확정). ──
	# ★결정적 노출: kind=='style' 전부를 result 에 push 한 뒤 좌우 순서만 셔플(shuffle→앞3 의존 제거).
	#   향후 발도술 4종+ 로 늘어나도 무너지지 않게 — count 까지만 남긴다(현재 3종이면 그대로 3장).
	var force_style := not owns_style
	if force_style:
		var pillars: Array = []
		for b in BOONS:
			if not (b is Dictionary):
				continue
			if String(b.get("pool", "")) != "pillar":
				continue
			var pid: String = String(b.get("id", ""))
			if pid == "" or pid in owned_ids:
				continue
			pillars.append(b)
		if pillars.is_empty():
			return []
		pillars.shuffle()  # 좌우 순서만 — 어떤 발도술이 어디 뜰지 무작위(노출 집합은 결정적 = 전부).
		var pres: Array = []
		for b in pillars:
			if pres.size() >= count:
				break
			pres.append(_make_card(b, rarity_for_level(level), rarity_labels))
		return pres

	# ── L3+(style 보유) — style_kit + support 합성. pillar 제외 + style exclusive + style_req 필터. ──
	# available 을 kit_pool / support_pool 둘로 분리(둘 다 style_req 통과 카드만). support 는 level>=3 에서만 합류.
	var kit_pool: Array = []
	var support_pool: Array = []
	for b in BOONS:
		if not (b is Dictionary):
			continue
		var bid: String = String(b.get("id", ""))
		if bid == "" or bid in owned_ids:
			continue
		var pool: String = String(b.get("pool", ""))
		if pool == "pillar":
			continue  # 발도술 1픽 exclusive — L3+ 에 재노출 금지.
		if pool != "style_kit" and pool != "support":
			continue
		# style_req 필터 — 활성 스타일 + universal(빈값)만. 다른 발도술 전용 카드는 제외.
		var card_style := String(b.get("style_req", ""))
		if active_style != "" and card_style != "" and card_style != active_style:
			continue
		if pool == "support":
			support_pool.append(b)
		else:
			kit_pool.append(b)

	kit_pool.shuffle()
	support_pool.shuffle()

	# ── support_slots 램프(결정적 도배 방지) — level 3~5=1, level>=6=1~2(가중 — 2 는 1/3 확률). level<3 = 0. ──
	var support_slots := 0
	if level >= 6:
		support_slots = 2 if randi_range(0, 2) == 0 else 1
	elif level >= 3:
		support_slots = 1
	# support 풀이 비면(또는 슬롯이 풀 크기 초과) kit 으로 채움(graceful). 슬롯은 count 도 넘지 않는다.
	support_slots = min(support_slots, support_pool.size())
	support_slots = min(support_slots, count)

	# kit 에서 (count - support_slots)장, support 에서 support_slots 장 — kit 은 skill_type 중복 회피(슬롯 한 종 1장).
	# ★support 는 전부 같은 skill_type('보조')라 슬롯 dedup 을 적용하면 2장 동시 노출이 불가능 → support 는 dedup 면제.
	var result: Array = []
	var used_slots: Array = []
	var kit_take: int = count - support_slots
	_collect_into(result, used_slots, kit_pool, kit_take, level, rarity_labels, true)
	_collect_into(result, used_slots, support_pool, count - result.size(), level, rarity_labels, false)
	# 합산이 count 에 못 미치면(슬롯 충돌로 kit/support 가 모자람) kit 으로 한 번 더 채움(graceful).
	if result.size() < count:
		_collect_into(result, used_slots, kit_pool, count - result.size(), level, rarity_labels, true)
	result.shuffle()  # 좌우 순서 셔플 — kit/support 가 항상 같은 위치에 뜨지 않게.
	return result


## available 에서 take 장까지 result 에 추가(중복 id 회피 + dedup_slots 면 skill_type 슬롯 중복 회피). result/used_slots 누적 변경.
## dedup_slots=false(support) 면 슬롯 중복을 허용해 같은 skill_type('보조') 카드가 둘 이상 동시 노출될 수 있다.
static func _collect_into(result: Array, used_slots: Array, available: Array, take: int, level: int, rarity_labels: Dictionary, dedup_slots: bool) -> void:
	if take <= 0:
		return
	var added: int = 0
	for b in available:
		if added >= take:
			break
		var slot: String = String(b.get("skill_type", ""))
		if dedup_slots and slot != "" and slot in used_slots:
			continue
		var bid: String = String(b.get("id", ""))
		var already := false
		for r in result:
			if r.get("id", "") == bid:
				already = true
				break
		if already:
			continue
		result.append(_make_card(b, rarity_for_level(level), rarity_labels))
		if dedup_slots and slot != "":
			used_slots.append(slot)
		added += 1


## 카드 dict 형상(Main/Testplay _selected_cards 미러용 — pool 키 포함). 등급은 호출부가 정한 rarity.
static func _make_card(b: Dictionary, rar: String, rarity_labels: Dictionary) -> Dictionary:
	return {
		"id": String(b.get("id", "")),
		"name": String(b.get("name", "")),
		"desc": String(b.get("desc", "")),
		"yokai": String(b.get("yokai", "")),
		"kind": String(b.get("kind", "")),
		"pool": String(b.get("pool", "")),
		"skill_type": String(b.get("skill_type", "")),
		"rarity": rar,
		"rarity_label": String(rarity_labels.get(rar, rar))
	}
