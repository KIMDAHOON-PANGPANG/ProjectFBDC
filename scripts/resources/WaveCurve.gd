class_name WaveCurve
extends Resource

## A chapter's population curve + chapter beats. Injected into WaveManager
## so the same wave engine can run any chapter — the const Ch1 schedule
## that used to live in WaveManager.gd is now resources/chapters/*.tres.
##
## Three parallel value-typed arrays (PackedFloat32 / PackedInt32) define
## a piecewise step function: from `curve_times[i]` onward, the spawner
## targets `curve_targets[i]` alive enemies with mob level `curve_lvs[i]`.
## All three must be the same length.
##
## Tip — bumping `boss_time` lengthens a chapter. Bumping
## `curve_targets[*]` raises the surround pressure; bumping
## `max_spawn_per_tick` lets the spawner catch up to a deficit faster.

## Chapter ID — used for SaveSystem section keys, label text, etc.
@export var chapter_id: int = 1
## Display name shown on the clear screen.
@export var chapter_name: String = "Chapter 1"

@export_group("Population Curve")
@export var curve_times: PackedFloat32Array = PackedFloat32Array([0.0, 30.0, 60.0, 90.0, 120.0])
@export var curve_targets: PackedInt32Array = PackedInt32Array([18, 39, 39, 55, 9])
@export var curve_lvs: PackedInt32Array = PackedInt32Array([1, 1, 2, 2, 2])

@export_group("Chapter Beats")
## One-shot elite trio spawn time.
@export var elite_time: float = 60.0
## One-shot boss spawn time.
@export var boss_time: float = 120.0

@export_group("Spawn Pacing")
## How often (seconds) WaveManager re-evaluates the deficit and adds.
@export var tick_period: float = 1.0
## Max spawns per tick — keeps adds visually staggered.
@export var max_spawn_per_tick: int = 4
## Probability a single drip-spawn is a ranged mob (≈1/6 → 5:1 melee:ranged).
@export var ranged_ratio: float = 0.16
## 원거리 몹이 등장하기 시작하는 경과 시간(초). 이 시간 전의 드립 스폰은 전부
## 근접(WaveManager.ranged_ratio() 가 0 반환). 0 = 처음부터(게이트 없음).
## 요청: 2분대 웨이브부터 원거리 → 120.0.
@export var ranged_start_time: float = 0.0
## 리퍼(리프 전용 몹) 드립 스폰 확률(0~1). 0 = 미등장. 요청: ≈0.1.
@export var leaper_ratio: float = 0.0
## 리퍼가 등장하기 시작하는 경과 시간(초). 요청: 1분대 웨이브부터 → 60.0.
@export var leaper_start_time: float = 0.0
## 슬래머(내려찍기) — 근접 슬롯 중 이 비율이 슬래머. slammer_start_time 후부터 적용.
@export var slammer_ratio: float = 0.3
## 슬래머 등장 시작 경과 시간(초). 0=처음부터. 스토리보드: ~40s(2렙 즈음).
@export var slammer_start_time: float = 0.0

## ── 스폰 로스터 (배열 기반 종류 편성) ──
## 위 종류별 고정 필드(ranged_ratio 등)는 *레거시 폴백*. 로스터가 비어있으면
## (has_roster()==false) Main/Testplay/시뮬은 전부 레거시 경로로 동작한다(현 동작 100% 보존).
## 로스터에 엔트리가 있으면 그 배열이 종류 선택을 지배한다. 4개 병렬 배열이 같은
## 인덱스로 한 엔트리를 이룬다(class_name 신규 Resource 회피 — 곡선 포인트와 동일 패턴).
##   spawn_keys[i]        — 몬스터 key(melee/ranged/slammer/leaper/sorcerer …)
##   spawn_start_times[i] — 등장 시작 경과 시간(초)
##   spawn_weights[i]     — 상대 가중치(weighted-random). 주술사는 가중치풀에서 제외(아래)
##   spawn_enabled[i]     — 1=스폰 on / 0=off
## 주술사(sorcerer) 엔트리는 가중치 추첨에서 빠지고, "활성 여부"만 본다 —
## 싱글톤+_SORCERER_CHANCE 굴림(Main) 의미 유지.
@export_group("Spawn Roster")
@export var spawn_keys: PackedStringArray = PackedStringArray([])
@export var spawn_start_times: PackedFloat32Array = PackedFloat32Array([])
@export var spawn_weights: PackedFloat32Array = PackedFloat32Array([])
@export var spawn_enabled: PackedInt32Array = PackedInt32Array([])
## 엔트리 종료 경과시간(초). 0=종료없음=챕터끝까지=현 동작.
@export var spawn_end_times: PackedFloat32Array = PackedFloat32Array([])


## 로스터가 채워져 있는가(엔트리 1개 이상). false 면 레거시 종류선택을 쓴다.
func has_roster() -> bool:
	return spawn_keys != null and spawn_keys.size() > 0


## 인덱스 i 엔트리가 t 시점에 활성인가 — enabled==1 && start<=t && (end<=0||t<end).
func _entry_active_at(i: int, t: float) -> bool:
	var en: int = spawn_enabled[i] if (spawn_enabled != null and i < spawn_enabled.size()) else 1
	var st: float = spawn_start_times[i] if (spawn_start_times != null and i < spawn_start_times.size()) else 0.0
	var et: float = spawn_end_times[i] if (spawn_end_times != null and i < spawn_end_times.size()) else 0.0
	return en == 1 and t >= st and (et <= 0.0 or t < et)


## t 시점에 활성(enabled==1 && start_time<=t && end 게이트)인 엔트리 인덱스 목록.
func active_entries_at(t: float) -> Array:
	var out: Array = []
	var n: int = spawn_keys.size() if spawn_keys != null else 0
	for i in n:
		if _entry_active_at(i, t):
			out.append(i)
	return out


## t 시점 활성 sorcerer 엔트리의 확률값(spawn_weights)을 반환. 없으면 fallback 반환.
func sorcerer_chance_at(t: float, fallback: float) -> float:
	for i in active_entries_at(t):
		if i < spawn_keys.size() and spawn_keys[i] == "sorcerer":
			var w: float = spawn_weights[i] if (spawn_weights != null and i < spawn_weights.size()) else fallback
			return clampf(w, 0.0, 1.0)
	return fallback


## t 시점 활성 sorcerer 엔트리가 존재하는가(가중치 무관 — 활성만).
func sorcerer_entry_active_at(t: float) -> bool:
	for i in active_entries_at(t):
		if i < spawn_keys.size() and spawn_keys[i] == "sorcerer":
			return true
	return false


## 가중치 추첨으로 t 시점 종류 key 를 고른다(sorcerer 제외). rng_val 은 0~1 난수.
## 활성 비주술사 엔트리가 없거나 가중치 합<=0 이면 "" 반환(호출부에서 melee 폴백).
func roster_pick_key(t: float, rng_val: float) -> String:
	var idxs: Array = active_entries_at(t)
	var total: float = 0.0
	for i in idxs:
		if i < spawn_keys.size() and spawn_keys[i] == "sorcerer":
			continue
		var w: float = spawn_weights[i] if (spawn_weights != null and i < spawn_weights.size()) else 0.0
		if w > 0.0:
			total += w
	if total <= 0.0:
		return ""
	var pick: float = clampf(rng_val, 0.0, 0.999999) * total
	var acc: float = 0.0
	for i in idxs:
		if i < spawn_keys.size() and spawn_keys[i] == "sorcerer":
			continue
		var w2: float = spawn_weights[i] if (spawn_weights != null and i < spawn_weights.size()) else 0.0
		if w2 <= 0.0:
			continue
		acc += w2
		if pick < acc:
			return spawn_keys[i]
	return ""


## Defensive lookup — caller passes elapsed time, gets back the active
## curve index. Returns 0 if the curve is empty (shouldn't happen with
## a valid resource).
func index_for_elapsed(elapsed: float) -> int:
	var n: int = curve_times.size()
	if n == 0:
		return 0
	var idx: int = 0
	for i in n:
		if elapsed >= curve_times[i]:
			idx = i
		else:
			break
	return idx


func target_for_elapsed(elapsed: float) -> int:
	var idx := index_for_elapsed(elapsed)
	if idx >= curve_targets.size():
		return 0
	return curve_targets[idx]


func lv_for_elapsed(elapsed: float) -> int:
	var idx := index_for_elapsed(elapsed)
	if idx >= curve_lvs.size():
		return 1
	return curve_lvs[idx]
