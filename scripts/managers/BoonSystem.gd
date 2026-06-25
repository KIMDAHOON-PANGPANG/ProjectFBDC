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


static func draw_boons(count: int, level: int, owned_ids: Array = []) -> Array:
	_ensure_loaded()
	# M9: 요괴 그룹핑 없음 — 전체 BOONS 풀(발도술/표식/납도/연쇄/제어 kind)에서 직접 뽑는다.
	# 빈 풀(boons.json == [])이면 [] 반환 → 레벨업 오버레이 graceful 스킵(크래시 금지).
	if BOONS.is_empty():
		return []

	var rarity_labels := {
		"chosim": "초심", "rare": "레어", "uniq": "유일",
		"legend": "전설", "master": "마스터"
	}

	# 스타일 exclusive(S3 프레임) + style_req 필터(M9-S10): 한 판에 한 발도술 풀만 노출한다.
	# - 플레이어가 style 카드를 이미 보유하면 그 카드의 style_req(예: 'iaido'/'nuki')를 '활성 스타일'로 본다.
	#   → 같은 style_req 카드 + style_req 빈값(universal) 카드만 draw(다른 발도술 카드는 풀에서 제외).
	#   → 동시에 style 카드(발도술)는 더 노출하지 않는다(1픽 exclusive 유지).
	# - style 미보유면 active_style 빈값 → 모든 style_req 통과(첫 픽에서 발도술 style 카드들이 노출됨).
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

	# ── M9-S12 첫 발도술 강제 1픽 — style 미보유면 첫 draw 에 발도술(kind=='style') 3종만 노출한다. ──
	# style 카드를 1개 확정하기 전엔 build-up/universal 카드를 섞지 않는다(한 판 = 발도술 1픽 확정).
	# style 보유 시엔 기존 로직(style 제외 + style_req 필터) 그대로.
	var force_style := not owns_style

	# 미보유 카드만 추려 available 구성.
	var available: Array = []
	for b in BOONS:
		if not (b is Dictionary):
			continue
		var bid: String = String(b.get("id", ""))
		if bid == "" or bid in owned_ids:
			continue
		if force_style:
			# 첫 픽 강제 — style 카드만 노출(발도/속발/일도양단 3종). 나머지(build-up/universal) 전부 제외.
			if String(b.get("kind", "")) != "style":
				continue
			available.append(b)
			continue
		# style 카드는 1픽 exclusive — 이미 스타일 보유면 제외.
		if owns_style and String(b.get("kind", "")) == "style":
			continue
		# style_req 필터 — 활성 스타일이 정해졌으면 그 스타일 + universal(빈값)만 노출(다른 발도술 카드 섞임 방지).
		var card_style := String(b.get("style_req", ""))
		if active_style != "" and card_style != "" and card_style != active_style:
			continue
		available.append(b)
	if available.is_empty():
		return []

	available.shuffle()
	var result: Array = []
	var used_slots: Array = []
	for b in available:
		if result.size() >= count:
			break
		var slot: String = String(b.get("skill_type", ""))
		# ★강제 첫 픽(force_style)에서는 slot 중복 체크를 건너뛴다 — 발도술 3종은 skill_type 이 모두
		#   '발도술'(동일 slot)이라, used_slots 가 막으면 1개만 노출돼 1픽이 불가능해진다. 3종 다 노출해야 한다.
		if not force_style and slot != "" and slot in used_slots:
			continue
		var bid: String = String(b.get("id", ""))
		var already := false
		for r in result:
			if r.get("id", "") == bid:
				already = true
				break
		if already:
			continue
		var rar := rarity_for_level(level)
		result.append({
			"id": bid,
			"name": String(b.get("name", "")),
			"desc": String(b.get("desc", "")),
			"yokai": String(b.get("yokai", "")),
			"kind": String(b.get("kind", "")),
			"skill_type": slot,
			"rarity": rar,
			"rarity_label": String(rarity_labels.get(rar, rar))
		})
		if slot != "":
			used_slots.append(slot)
	return result
