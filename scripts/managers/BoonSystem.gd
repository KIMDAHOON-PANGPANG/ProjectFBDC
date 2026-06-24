extends RefCounted

## 권속 은혜(Boon) 데이터 로더 + 조회 API.
## 데이터: data/boons.json — {boons:[...]} 형태.
## 효과 실행(S5) / 3택 UI(S6) 는 이 파일 범위 밖 — 로드+조회만.
## 참조: const _B := preload("res://scripts/managers/BoonSystem.gd") + 정적 호출.

const _JSON := "res://data/boons.json"

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
