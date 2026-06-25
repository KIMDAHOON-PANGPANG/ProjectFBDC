extends RefCounted

## 권속 은혜(Boon) 데이터 로더 + 조회 API.
## 데이터: data/boons.json — {boons:[...]} 형태.
## 효과 실행(S5) / 3택 UI(S6) 는 이 파일 범위 밖 — 로드+조회만.
## 참조: const _B := preload("res://scripts/managers/BoonSystem.gd") + 정적 호출.

const _JSON := "res://data/boons.json"

const YOKAI_COLORS := {
	"GUMIHO": Color("ff5fb0"),
	"DOKEBI": Color("ffc233"),
	"MULGWISHIN": Color("2f9fe0"),
	"JEOSEUNG": Color("7b5cf0"),
	"CHEONYEO": Color("d11f3a"),
}

static func yokai_color(y: String) -> Color:
	return YOKAI_COLORS.get(y, Color(0.7, 0.7, 0.7))

static var BOONS: Array = []
static var _by_id: Dictionary = {}
static var _by_yokai: Dictionary = {}
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
	_by_yokai = {}

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
		var yokai = b.get("yokai", "")
		if not (yokai is String) or yokai == "":
			continue
		if not _by_yokai.has(yokai):
			_by_yokai[yokai] = []
		_by_yokai[yokai].append(b)


static func all_boons() -> Array:
	_ensure_loaded()
	return BOONS


static func by_id(id: String) -> Variant:
	_ensure_loaded()
	return _by_id.get(id, null)


static func by_yokai(y: String) -> Array:
	_ensure_loaded()
	var arr = _by_yokai.get(y, null)
	if arr == null:
		return []
	return arr.duplicate()


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


# TODO: 귀신 풀이 4종 이상이면 런 시작 시 2~3 랜덤 선택 적용. 현재(구미호만)는 전부 사용.
static func run_yokai_pool() -> Array:
	_ensure_loaded()
	var keys = _by_yokai.keys()
	var result: Array = []
	for k in keys:
		result.append(k)
	return result


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
	var pool := run_yokai_pool()
	if pool.is_empty():
		return []

	var rarity_labels := {
		"chosim": "초심", "rare": "레어", "uniq": "유일",
		"legend": "전설", "master": "마스터"
	}

	# 요괴 순서 랜덤화 후 가용 카드가 있는 요괴를 첫 번째로 선택
	var pool_copy := pool.duplicate()
	pool_copy.shuffle()
	for yokai in pool_copy:
		var boons_for_yokai = _by_yokai.get(yokai, [])
		# 미보유 카드만 추려 available 구성
		var available: Array = []
		for b in boons_for_yokai:
			if not (b is Dictionary):
				continue
			var bid: String = String(b.get("id", ""))
			if bid in owned_ids:
				continue
			available.append(b)
		if available.is_empty():
			continue
		# 이 요괴로 확정 — 이 요괴 카드만으로 뽑기
		available.shuffle()
		var result: Array = []
		var used_slots: Array = []
		for b in available:
			if result.size() >= count:
				break
			var slot: String = String(b.get("skill_type", ""))
			if slot != "" and slot in used_slots:
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
				"skill_type": slot,
				"rarity": rar,
				"rarity_label": String(rarity_labels.get(rar, rar))
			})
			if slot != "":
				used_slots.append(slot)
		return result

	return []
