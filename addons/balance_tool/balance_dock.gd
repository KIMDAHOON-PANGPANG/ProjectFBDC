@tool
extends VBoxContainer

## 인하우스 밸런스 에디터 도크 — Godot 에디터 우측 도크.
##   탭1 "PC 밸런스"      → resources/player/player_data.tres (PlayerData) 편집
##   탭2 "몬스터 밸런스"   → resources/monster_table.tres (MonsterTable) 의 각 몬스터 편집
## 파라미터는 한글 이름 + 마우스오버 한글 툴팁. 값 변경 시 즉시 .tres 저장.

const PLAYER_DATA := "res://resources/player/player_data.tres"
const MONSTER_TABLE := "res://resources/monster_table.tres"
const _ExpSystemScript := preload("res://scripts/managers/ExpSystem.gd")
const UPGRADES_CSV := "res://data/upgrades.csv"

# [필드명, 한글 라벨, 한글 툴팁, 타입("f"=실수 / "i"=정수)]
# 섹션 구분 — ["@", "헤더 텍스트"] 행은 _build_pc_tab 루프가 HSeparator + 헤더 라벨로 렌더.
const PC_FIELDS := [
	["@", "─ 이동 / 생존 ─"],
	["move_speed", "이동 속도", "PC 가 1초에 움직이는 거리(유닛).", "f"],
	["max_hp", "최대 체력", "최대 HP(자연수). 피격마다 몹 공격력만큼 감소. 레벨업 '강건'으로 +1.", "i"],

	["@", "─ 일섬 ─"],
	["min_slash_range", "일섬 최소 사거리", "차징 0 일 때 일섬이 나가는 최소 거리(유닛).", "f"],
	["instant_slash_distance", "일섬 풀차지 사거리", "LB 풀차지 시 일섬 돌진 사거리(유닛).", "f"],
	["max_charge_time", "풀차지 시간", "버튼을 눌러 최대 사거리에 도달하기까지 시간(초).", "f"],
	["charge_speed_mult", "충전 속도 배수", "일섬 길이 차오르는 속도 배수. 작을수록 천천히 충전.", "f"],
	["slash_dash_speed", "일섬 돌진 속도", "일섬 대시가 1초에 전진하는 거리(유닛/초).", "f"],
	["slash_width", "일섬 폭", "일섬 타격 박스의 좌우 폭(유닛).", "f"],
	["slash_post_grace", "일섬 후 무적(초)", "일섬 직후 짧은 회복 무적 — 착지 즉시 피격 방지.", "f"],
	["slash_fixed_cooldown", "쿨다운모드 재발사(초)", "일섬 자원=쿨다운 모드(GameConfig)일 때 재발사 락(초). 열기모드면 무관.", "f"],

	["@", "─ 열관리 (거합 모드 자원) ─"],
	["heat_gain_base", "일섬당 열 획득(%)", "거합 모드: 일섬 1발당 차오르는 열(%).", "f"],
	["heat_combo_window", "열 연타 판정(초)", "직전 일섬 후 이 시간 내 재발사 시 연타로 간주 → 연타 배수 적용.", "f"],
	["heat_combo_mult", "열 연타 배수", "연타 시 열 획득 배수(1.5 = +50%).", "f"],
	["heat_overheat_threshold", "탈진 임계(%)", "열이 이 값에 닿으면 탈진.", "f"],
	["heat_overheat_duration", "탈진 지속(초)", "탈진 상태 지속 시간(초) — 이동 감소 + 발사 봉인.", "f"],
	["heat_overheat_move_mult", "탈진 이동 배수", "탈진 중 이동속도 배수(0.5 = 50% 감소).", "f"],
	["heat_decay_delay", "열 식기 유예(초)", "마지막 일섬 후 열이 다시 식기 시작하기까지의 대기(초).", "f"],
	["heat_decay_rate", "열 식는 속도 k", "100% 아닐 때 지수 감소 계수(클수록 빨리 식음). H*=e^(-k·dt).", "f"],

	["@", "─ 회피 ─"],
	["evade_distance", "회피 거리", "스페이스 회피로 이동하는 거리(유닛).", "f"],
	["evade_max_stacks", "회피 스택 수", "연속으로 쓸 수 있는 회피 횟수.", "i"],
	["evade_refill_time", "회피 재충전(초)", "스택을 다 쓰고 가득 차기까지 시간(초).", "f"],

	["@", "─ 피격 / 무적 / 자원 ─"],
	["hit_iframe", "피격 무적 시간(초)", "맞은 뒤 무적 시간. 이 동안 깜빡이며 연속 피해 방지.", "f"],
	["levelup_iframe", "레벨업 무적(초)", "레벨업 시 부여되는 무적 시간(초). 카드 고르고 재개 후 안전.", "f"],
	["contact_damage", "접촉 피해", "몬스터 몸에 닿을 때 받는 HP 감소량.", "i"],
	["knockback_force", "피격 넉백 속도", "피격 시 주변 적이 밀려나는 속도(유닛/초).", "f"],
	["slash_gauge_on_kill", "처치당 일섬 게이지", "적 처치 시 차는 일섬 게이지량(레거시 — 일섬 단일은 열기/쿨다운 자원 사용).", "f"],

	["@", "─ 카메라 연출 ─"],
	["slash_cam_zoom_scale", "일섬 줌펀치 배수", "일섬 발사 시 카메라 줌아웃 배수(>1 일수록 더 넓게).", "f"],
	["slash_cam_zoom_time", "일섬 줌펀치 시간(초)", "줌펀치 줌아웃→복귀 왕복 시간(초).", "f"],
	["slash_cam_follow_time", "일섬 카메라 추적(초)", "일섬 대시 중 카메라 밀착 추적 시간(초).", "f"],
	["slash_cam_follow_mult", "일섬 추적 강도", "일섬 대시 중 카메라 추적 강화 배수.", "f"],
]

# 몬스터 공용 필드 — 한 몬스터(MonsterStats)에 모두 표시(타입별 무관 필드는 기본값).
const MON_FIELDS := [
	["@", "─ 메타 (표시 / 리스트) ─"],
	["display_name", "표시 이름", "몬스터 리스트에 보이는 이름.", "s"],
	["concept", "컨셉", "몬스터 컨셉 설명(· 로 구분).", "s"],
	["color", "컬러(hex)", "인게임 틴트 색상 hex(예: d97333).", "s"],
	["@", "─ 기본 스탯 ─"],
	["move_speed", "이동 속도", "1초에 움직이는 거리(유닛).", "f"],
	["max_hp", "최대 체력(방컷)", "처치에 필요한 타수(잡몹은 일섬 1방·HP 무관).", "i"],
	["attack_range", "공격/시전 거리", "공격·텔레그래프 시작 거리(원거리=사격 사거리).", "f"],
	["attack_cooldown", "공격 간격(초)", "공격 사이 간격.", "f"],
	["attack_damage", "공격 데미지", "근접/부채 적중 데미지.", "i"],
	["@", "─ 부채 공격 (근접) ─", ["melee", "leaper", "slammer"]],
	["fan_radius", "부채 반경", "부채 텔레그래프 반경(유닛).", "f"],
	["fan_angle_deg", "부채 각도", "부채 텔레그래프 각도(도).", "f"],
	["@", "─ 군집 / 경직 ─"],
	["separation_radius", "분리 반경", "서로 안 겹치게 밀어내는 반경(유닛).", "f"],
	["separation_weight", "분리 가중치", "추격 대비 분리 힘 비중.", "f"],
	["armor_max", "아머(경직 게이지)", "0=아머 없음. 데미지 누적 시 경직.", "i"],
	["stagger_duration", "경직 시간(초)", "아머 소거 시 행동 불가 시간.", "f"],
	["@", "─ [궁수] 원거리 ─", ["ranged"]],
	["keep_distance", "원거리 선호 거리", "[궁수] 유지하려는 거리(유닛).", "f"],
	["arrow_speed", "화살 속도", "[궁수] 발사체 속도(유닛/초).", "f"],
	["aim_lock_duration", "조준 노출 시간", "[궁수] 발사 전 조준 텔레그래프 시간(초).", "f"],
	["@", "─ [리퍼] 도약 ─", ["leaper"]],
	["leap_chance", "도약 확률", "[리퍼] 사거리 내에서 도약 발동 확률(0~1).", "f"],
	["leap_radius", "도약 슬램 반경", "[리퍼] 내려찍기 원형 반경(유닛).", "f"],
	["leap_damage", "도약 슬램 데미지", "[리퍼] 내려찍기 데미지.", "i"],
	["@", "─ [슬래머] 슬램 ─", ["slammer"]],
	["slam_range", "슬램 발동 거리", "[슬래머] 이 거리 안이면 힘주기 시작.", "f"],
	["slam_windup", "슬램 힘주기(초)", "[슬래머] 내려찍기 전 정지 차징 시간(초).", "f"],
	["slam_radius", "슬램 반경", "[슬래머] 광역 슬램 반경(넓음=회피 전용).", "f"],
	["slam_damage", "슬램 데미지", "[슬래머] 슬램 적중 데미지.", "i"],
	["slam_cooldown", "슬램 쿨다운(초)", "[슬래머] 슬램 후 다음 공격까지.", "f"],
	["@", "─ [주술사] 장판 / 텔레포트 ─", ["sorcerer"]],
	["vision_range", "시야 반경", "[주술사] PC 를 보는(장판 시전) 거리.", "f"],
	["zone_count", "장판 개수", "[주술사] 한 번에 까는 장판 수.", "i"],
	["zone_radius", "장판 반경", "[주술사] 각 장판 원형 반경(유닛).", "f"],
	["zone_spread", "장판 흩뿌림 거리", "[주술사] PC 중심에서 장판까지 거리.", "f"],
	["zone_duration", "장판 지속(초)", "[주술사] 진한 장판 지속 시간.", "f"],
	["zone_slow_mult", "장판 감속 배수", "[주술사] 장판 안 이동속도 배수(작을수록 느림).", "f"],
	["zone_precursor", "장판 전조(초)", "[주술사] 흐릿한 전조가 채워지는 시간(초).", "f"],
	["teleport_cooldown", "텔레포트 쿨(초)", "[주술사] 텔레포트 재사용 대기.", "f"],
	["teleport_range", "텔레포트 발동 거리", "[주술사] PC 가 이 안에 오면 점멸.", "f"],
	["@", "─ [보스] 돌진 ─", ["boss"]],
	["charge_range", "돌진 시작 거리", "[보스] 아주 먼 거리에서 돌진 시작.", "f"],
	["charge_windup", "돌진 호밍(초)", "[보스] 데칼이 PC 를 따라다니는 시간.", "f"],
	["charge_speed", "돌진 속도", "[보스] 돌진 직진 속도(유닛/초).", "f"],
	["charge_distance", "돌진 거리", "[보스] 한 번 돌진 거리(유닛).", "f"],
	["charge_damage", "돌진 데미지", "[보스] 돌진 적중 데미지.", "i"],
	["charge_recover", "돌진 후 정지(초)", "[보스] 돌진 끝나고 멈추는 시간.", "f"],
	["charge_cooldown", "돌진 쿨다운(초)", "[보스] 다음 돌진까지 대기.", "f"],
	["charge_width", "돌진 폭", "[보스] 돌진 판정/데칼 폭(유닛).", "f"],
]

var _mon_table = null
var _mon_index: int = 0
var _mon_fields_box: VBoxContainer
var _mon_preview_icon: TextureRect = null
var _mon_preview_swatch: ColorRect = null
var _mon_preview_label: Label = null
var _built: bool = false


func _ready() -> void:
	if _built:
		return
	_built = true
	name = "밸런스 툴"
	custom_minimum_size = Vector2(340, 0)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(tabs)
	var pc := _build_pc_tab()
	pc.name = "PC 밸런스"
	tabs.add_child(pc)
	var mon := _build_monster_tab()
	mon.name = "몬스터 밸런스"
	tabs.add_child(mon)
	var wave := _build_wave_tab()
	wave.name = "웨이브 랩"
	tabs.add_child(wave)
	var lvl := _build_levelup_tab()
	lvl.name = "레벨업 랩"
	tabs.add_child(lvl)


func _build_pc_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)
	var pd = load(PLAYER_DATA)
	vb.add_child(_note("PC 밸런스 — player_data.tres (값 변경 즉시 저장)"))
	if pd == null:
		vb.add_child(_note("⚠ player_data.tres 로드 실패"))
		return scroll
	var saver := Callable(self, "_save").bind(pd, PLAYER_DATA)
	for spec in PC_FIELDS:
		if spec[0] == "@":
			vb.add_child(_section(spec[1]))
		elif spec[0] in pd:
			vb.add_child(_field_row(pd, spec, saver))
	return scroll


## PC 탭 섹션 헤더 — 구분선(HSeparator) + 색 라벨로 그룹을 시각적으로 나눈다.
func _section(title: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.add_child(HSeparator.new())
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	box.add_child(lbl)
	return box


func _build_monster_tab() -> Control:
	var vb := VBoxContainer.new()
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mon_table = load(MONSTER_TABLE)
	vb.add_child(_note("몬스터 밸런스 — monster_table.tres (값 변경 즉시 저장)"))
	if _mon_table == null or not ("monsters" in _mon_table):
		vb.add_child(_note("⚠ monster_table.tres 로드 실패"))
		return vb
	var opt := OptionButton.new()
	opt.tooltip_text = "편집할 몬스터 선택"
	for i in _mon_table.monsters.size():
		var m = _mon_table.monsters[i]
		opt.add_item("#%d  %s" % [m.id, m.display_name], i)
	opt.item_selected.connect(_on_monster_selected)
	vb.add_child(opt)
	# 프리뷰 행 — 선택 몬스터 스프라이트(틴트 아이콘) + 컬러 스와치 + 기본 정보.
	var prev := HBoxContainer.new()
	prev.add_theme_constant_override("separation", 10)
	_mon_preview_icon = TextureRect.new()
	_mon_preview_icon.custom_minimum_size = Vector2(64, 64)
	_mon_preview_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_mon_preview_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	prev.add_child(_mon_preview_icon)
	_mon_preview_swatch = ColorRect.new()
	_mon_preview_swatch.custom_minimum_size = Vector2(40, 64)
	prev.add_child(_mon_preview_swatch)
	_mon_preview_label = Label.new()
	_mon_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prev.add_child(_mon_preview_label)
	vb.add_child(prev)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	_mon_fields_box = VBoxContainer.new()
	_mon_fields_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_mon_fields_box)
	if _mon_table.monsters.size() > 0:
		_rebuild_monster_fields(0)
	return vb


func _on_monster_selected(idx: int) -> void:
	_rebuild_monster_fields(idx)


func _rebuild_monster_fields(idx: int) -> void:
	_mon_index = idx
	if _mon_fields_box == null:
		return
	for c in _mon_fields_box.get_children():
		c.queue_free()
	if idx < 0 or idx >= _mon_table.monsters.size():
		return
	var m = _mon_table.monsters[idx]
	var mkey: String = str(m.key) if ("key" in m) else ""
	var saver := Callable(self, "_save").bind(_mon_table, MONSTER_TABLE)
	# 선택한 몬스터 타입(key)에 해당하는 섹션만 노출 — 섹션마커 3번째 요소가 적용 key
	# 배열(태그). 태그 없는(공용) 섹션은 항상 표시. 필드는 현재 섹션이 보일 때만 생성.
	var section_visible: bool = true
	for spec in MON_FIELDS:
		if spec[0] == "@":
			if spec.size() > 2 and spec[2] is Array:
				section_visible = mkey in spec[2]
			else:
				section_visible = true
			if section_visible:
				_mon_fields_box.add_child(_section(spec[1]))
		elif section_visible and spec[0] in m:
			_mon_fields_box.add_child(_field_row(m, spec, saver))
	_update_mon_preview(m)


func _update_mon_preview(m) -> void:
	if _mon_preview_icon == null:
		return
	var col := Color(0.82, 0.82, 0.85)
	var cs: String = str(m.color) if ("color" in m) else ""
	if cs != "" and Color.html_is_valid(cs):
		col = Color.html(cs)
	var ic: String = str(m.icon) if ("icon" in m) else ""
	if ic != "" and ResourceLoader.exists(ic):
		_mon_preview_icon.texture = load(ic)
	else:
		_mon_preview_icon.texture = null
	_mon_preview_icon.modulate = col
	if _mon_preview_swatch != null:
		_mon_preview_swatch.color = col
	if _mon_preview_label != null:
		var id_str: String = str(int(m.id)) if ("id" in m) else "?"
		var nm_str: String = str(m.display_name) if ("display_name" in m) else ""
		_mon_preview_label.text = "#%s  %s\n%s" % [id_str, nm_str, cs]


## 한 줄: 한글 라벨(툴팁) + 편집기(SpinBox/LineEdit). 값 변경 → set + 저장 콜백.
func _field_row(obj, spec, on_save: Callable) -> Control:
	var field: String = spec[0]
	var typ: String = spec[3]
	var hb := HBoxContainer.new()
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl := Label.new()
	lbl.text = spec[1]
	lbl.tooltip_text = spec[2]
	lbl.custom_minimum_size = Vector2(160, 0)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	hb.add_child(lbl)
	if typ == "s":
		var le := LineEdit.new()
		le.tooltip_text = spec[2]
		le.custom_minimum_size = Vector2(150, 0)
		le.text = str(obj.get(field))
		le.text_submitted.connect(func(t):
			obj.set(field, t)
			on_save.call())
		le.focus_exited.connect(func():
			obj.set(field, le.text)
			on_save.call())
		hb.add_child(le)
	else:
		var sb := SpinBox.new()
		sb.tooltip_text = spec[2]
		sb.custom_minimum_size = Vector2(120, 0)
		sb.min_value = -99999.0
		sb.max_value = 99999.0
		if typ == "i":
			sb.step = 1.0
			sb.rounded = true
		else:
			sb.step = 0.01
		sb.value = float(obj.get(field))
		sb.value_changed.connect(func(v):
			obj.set(field, int(round(v)) if typ == "i" else v)
			on_save.call())
		hb.add_child(sb)
	return hb


func _save(obj, path: String) -> void:
	if obj != null:
		ResourceSaver.save(obj, path)


func _note(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	return l


# ──────────────────────────────────────────────────────────────────────────
# 탭3 "웨이브 랩" — WaveCurve(resources/chapters/chapter_N.tres) 편집 + 시뮬레이션 차트.
# 시뮬은 WaveManager 의 실제 rate 모델을 그대로 복제(아래 _RATE/_HCAP/_sim_*).
# ──────────────────────────────────────────────────────────────────────────

const CHAPTER_PATHS := [
	"res://resources/chapters/chapter_1.tres",
	"res://resources/chapters/chapter_2.tres",
	"res://resources/chapters/chapter_3.tres",
]
# WaveManager.gd 상수 미러 — 값 바뀌면 여기도 맞춰야 수치 일치 유지.
const _SIM_RATE_PER_UNIT := 0.1
const _SIM_HARD_CAP := 120

# 웨이브 랩 단순 비율/이벤트 필드 — [필드명, 한글라벨, 한글툴팁, 타입]
const WAVE_FIELDS := [
	["@", "─ 챕터 이벤트 ─"],
	["elite_time", "엘리트 출현 시각(초)", "엘리트 3종 1회 스폰 시각.", "f"],
	["boss_time", "보스 출현 시각(초) = 챕터 길이", "보스 1회 스폰 시각. 챕터 종료 시점.", "f"],
	["@", "─ 스폰 페이싱 ─"],
	["tick_period", "틱 주기(초)", "WaveManager 가 결손을 재평가하는 주기.", "f"],
	["max_spawn_per_tick", "틱당 최대 스폰", "한 틱에 추가되는 최대 마릿수(시각적 분산).", "i"],
]

## 스폰 로스터 OptionButton 항목 인덱스 ↔ 몬스터 key 매핑.
const ROSTER_KEYS := ["melee", "ranged", "slammer", "leaper", "sorcerer"]
const ROSTER_LABELS := ["근접(베이스)", "궁수", "슬래머", "리퍼", "주술사"]

var _wave_curve = null
var _wave_path: String = ""
var _wave_points_box: VBoxContainer = null
var _wave_fields_box: VBoxContainer = null
var _wave_roster_box: VBoxContainer = null
var _wave_chart: Control = null
var _wave_metrics: Label = null
var _wave_warnings: Label = null
var _wave_clear_rate: float = 2.0
# 시각 스크럽 — 미리보기 전용(저장 안 함).
var _wave_scrub_t: float = 0.0
var _wave_compo: Label = null
var _wave_compo_chart: Control = null
var _wave_scrub_slider: HSlider = null
var _wave_scrub_spin: SpinBox = null

# ── 탭4 레벨업 랩 멤버 변수 ──
const _LVL_MAX_LEVEL := 30
var _exp_first: float = 12.0
var _exp_step: float = 7.0
var _exp_accel: float = 1.3
var _exp_xp_per_min: float = 60.0
var _lvl_chart: Control = null
var _lvl_metrics: Label = null
var _lvl_warnings: Label = null
var _lvl_targets_box: VBoxContainer = null
var _lvl_targets: Array = [[60.0, 5], [180.0, 10], [360.0, 20]]


func _build_wave_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)
	vb.add_child(_note("웨이브 랩 — chapter_N.tres (WaveCurve, 값 변경 즉시 저장). 시뮬은 WaveManager 실제 rate 모델 복제."))

	var opt := OptionButton.new()
	opt.tooltip_text = "편집할 챕터 선택"
	for i in CHAPTER_PATHS.size():
		var c = load(CHAPTER_PATHS[i])
		var nm := "Chapter %d" % (i + 1)
		if c != null and ("chapter_name" in c):
			nm = "%s" % c.chapter_name
		opt.add_item("%d.  %s" % [i + 1, nm], i)
	opt.item_selected.connect(_on_wave_chapter_selected)
	vb.add_child(opt)

	# 곡선 포인트 편집 영역.
	vb.add_child(_section("─ 인구 곡선 포인트 (시간 / 스폰비율값 / 레벨) ─"))
	_wave_points_box = VBoxContainer.new()
	_wave_points_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(_wave_points_box)
	var add_btn := Button.new()
	add_btn.text = "＋ 포인트 추가"
	add_btn.tooltip_text = "곡선 끝에 포인트 추가(시간=마지막+30, 값/레벨=마지막 복사)."
	add_btn.pressed.connect(_on_wave_add_point)
	vb.add_child(add_btn)

	# 이벤트 / 페이싱 단순 필드(종류 비율은 아래 '스폰 로스터'로 이전됨).
	vb.add_child(_note("종류 편성은 아래 '스폰 로스터'에서. 근접 잡몹은 베이스(미매칭/엔트리없음 폴백). 주술사는 가중치 무관 싱글톤(동시 1, 5% 굴림)."))
	_wave_fields_box = VBoxContainer.new()
	_wave_fields_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(_wave_fields_box)

	# 스폰 로스터 — 배열 기반 종류 편성(추가/삭제). 비어있으면 레거시 폴백 동작.
	vb.add_child(_section("─ 스폰 로스터 (종류 / 등장시각 / 수량 / on·off) ─"))
	vb.add_child(_note("드립 스폰 종류를 직접 편성한다. 비어있으면 레거시(궁수/슬래머/리퍼 비율) 동작 그대로. 수량=상대 가중치(자연수). 주술사는 확률(0~1)·활성 시 싱글톤 굴림. 종료시각 0=끝까지. 챕터 로드 시 레거시 값에서 자동 prefill(표시만, 편집 전엔 저장 안 함)."))
	_wave_roster_box = VBoxContainer.new()
	_wave_roster_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(_wave_roster_box)
	var roster_add := Button.new()
	roster_add.text = "＋ 엔트리 추가"
	roster_add.tooltip_text = "로스터 끝에 엔트리 추가(근접/0초/끝까지/가중치1/on). 추가 즉시 .tres 저장."
	roster_add.pressed.connect(_on_wave_roster_add)
	vb.add_child(roster_add)

	# 가정 처치율 슬라이더.
	vb.add_child(_section("─ 시뮬레이션 ─"))
	var hb := HBoxContainer.new()
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cl := Label.new()
	cl.text = "가정 처치율(/초)"
	cl.tooltip_text = "투영 동시생존 적분에 쓰는 가정 처치율(마리/초). 시리즈B 곡선만 바뀜(.tres 저장 안 함)."
	cl.custom_minimum_size = Vector2(160, 0)
	cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(cl)
	var csb := SpinBox.new()
	csb.min_value = 0.0
	csb.max_value = 50.0
	csb.step = 0.1
	csb.value = _wave_clear_rate
	csb.custom_minimum_size = Vector2(120, 0)
	csb.value_changed.connect(func(v):
		_wave_clear_rate = v
		_refresh_wave_sim())
	hb.add_child(csb)
	vb.add_child(hb)

	# 시각 스크럽 컨트롤.
	vb.add_child(_section("─ 시각 스크럽 (미리보기) ─"))
	var scrub_hb := HBoxContainer.new()
	scrub_hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scrub_lbl := Label.new()
	scrub_lbl.text = "현재 시각(초)"
	scrub_lbl.tooltip_text = "이 시각의 몬스터 구성 미리보기. .tres 저장 안 함."
	scrub_lbl.custom_minimum_size = Vector2(100, 0)
	scrub_hb.add_child(scrub_lbl)
	_wave_scrub_slider = HSlider.new()
	_wave_scrub_slider.min_value = 0.0
	_wave_scrub_slider.max_value = 300.0
	_wave_scrub_slider.step = 1.0
	_wave_scrub_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wave_scrub_slider.value = _wave_scrub_t
	_wave_scrub_slider.value_changed.connect(func(v): _on_wave_scrub(v, true))
	scrub_hb.add_child(_wave_scrub_slider)
	_wave_scrub_spin = SpinBox.new()
	_wave_scrub_spin.min_value = 0.0
	_wave_scrub_spin.max_value = 99999.0
	_wave_scrub_spin.step = 1.0
	_wave_scrub_spin.custom_minimum_size = Vector2(80, 0)
	_wave_scrub_spin.value = _wave_scrub_t
	_wave_scrub_spin.value_changed.connect(func(v): _on_wave_scrub(v, false))
	scrub_hb.add_child(_wave_scrub_spin)
	vb.add_child(scrub_hb)

	# 구성 readout 라벨.
	_wave_compo = Label.new()
	_wave_compo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_wave_compo.add_theme_color_override("font_color", Color(0.8, 0.95, 0.8))
	vb.add_child(_wave_compo)

	# 기존 스폰비율/투영생존 차트.
	_wave_chart = Control.new()
	_wave_chart.custom_minimum_size = Vector2(320, 220)
	_wave_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wave_chart.draw.connect(_draw_wave_chart)
	vb.add_child(_wave_chart)

	# 종류별 등장 타임라인 차트.
	_wave_compo_chart = Control.new()
	_wave_compo_chart.custom_minimum_size = Vector2(320, 90)
	_wave_compo_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wave_compo_chart.draw.connect(_draw_wave_compo_chart)
	vb.add_child(_wave_compo_chart)

	_wave_metrics = Label.new()
	_wave_metrics.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_wave_metrics)
	_wave_warnings = Label.new()
	_wave_warnings.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_wave_warnings.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
	vb.add_child(_wave_warnings)

	_load_wave_chapter(0)
	return scroll


func _on_wave_chapter_selected(idx: int) -> void:
	_load_wave_chapter(idx)


func _load_wave_chapter(idx: int) -> void:
	if idx < 0 or idx >= CHAPTER_PATHS.size():
		return
	_wave_path = CHAPTER_PATHS[idx]
	_wave_curve = load(_wave_path)
	_rebuild_wave_points()
	_rebuild_wave_fields()
	_rebuild_wave_roster()
	# 스크럽 위젯 범위 갱신 — 위젯이 이미 생성된 경우에만.
	var dur := _sim_duration()
	if _wave_scrub_slider != null:
		_wave_scrub_slider.max_value = dur
		_wave_scrub_t = clampf(_wave_scrub_t, 0.0, dur)
		_wave_scrub_slider.set_value_no_signal(_wave_scrub_t)
	if _wave_scrub_spin != null:
		_wave_scrub_spin.max_value = dur
		_wave_scrub_spin.set_value_no_signal(_wave_scrub_t)
	_refresh_wave_sim()


# 곡선 포인트 행 — 시간 / 값 / 레벨 SpinBox + 삭제 버튼. 한 줄 = curve_*[i].
func _rebuild_wave_points() -> void:
	if _wave_points_box == null:
		return
	for c in _wave_points_box.get_children():
		c.queue_free()
	if _wave_curve == null:
		_wave_points_box.add_child(_note("⚠ 챕터 로드 실패"))
		return
	# 헤더 행.
	var head := HBoxContainer.new()
	for txt in ["시간(s)", "스폰비율값", "레벨", ""]:
		var l := Label.new()
		l.text = txt
		l.custom_minimum_size = Vector2(80, 0)
		l.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
		head.add_child(l)
	_wave_points_box.add_child(head)
	var n: int = _wave_curve.curve_times.size()
	for i in n:
		_wave_points_box.add_child(_wave_point_row(i))


func _wave_point_row(i: int) -> Control:
	var hb := HBoxContainer.new()
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 시간.
	var tb := SpinBox.new()
	tb.min_value = 0.0
	tb.max_value = 99999.0
	tb.step = 1.0
	tb.custom_minimum_size = Vector2(80, 0)
	tb.value = float(_wave_curve.curve_times[i]) if i < _wave_curve.curve_times.size() else 0.0
	tb.value_changed.connect(func(v):
		var arr: PackedFloat32Array = _wave_curve.curve_times
		if i < arr.size():
			arr[i] = v
			_wave_curve.curve_times = arr
			_save_wave()
			_refresh_wave_sim())
	hb.add_child(tb)
	# 값(스폰비율값 = 곡선 target, 정수).
	var vbx := SpinBox.new()
	vbx.min_value = 0.0
	vbx.max_value = 99999.0
	vbx.step = 1.0
	vbx.rounded = true
	vbx.custom_minimum_size = Vector2(80, 0)
	vbx.value = float(_wave_curve.curve_targets[i]) if i < _wave_curve.curve_targets.size() else 0.0
	vbx.value_changed.connect(func(v):
		var arr: PackedInt32Array = _wave_curve.curve_targets
		if i < arr.size():
			arr[i] = int(round(v))
			_wave_curve.curve_targets = arr
			_save_wave()
			_refresh_wave_sim())
	hb.add_child(vbx)
	# 레벨(정수).
	var lvb := SpinBox.new()
	lvb.min_value = 1.0
	lvb.max_value = 99.0
	lvb.step = 1.0
	lvb.rounded = true
	lvb.custom_minimum_size = Vector2(80, 0)
	lvb.value = float(_wave_curve.curve_lvs[i]) if i < _wave_curve.curve_lvs.size() else 1.0
	lvb.value_changed.connect(func(v):
		var arr: PackedInt32Array = _wave_curve.curve_lvs
		if i < arr.size():
			arr[i] = int(round(v))
			_wave_curve.curve_lvs = arr
			_save_wave()
			_refresh_wave_sim())
	hb.add_child(lvb)
	# 삭제.
	var del := Button.new()
	del.text = "✕"
	del.tooltip_text = "이 포인트 삭제"
	del.pressed.connect(func(): _on_wave_delete_point(i))
	hb.add_child(del)
	return hb


func _on_wave_add_point() -> void:
	if _wave_curve == null:
		return
	var times: PackedFloat32Array = _wave_curve.curve_times
	var targets: PackedInt32Array = _wave_curve.curve_targets
	var lvs: PackedInt32Array = _wave_curve.curve_lvs
	var last_t: float = times[times.size() - 1] if times.size() > 0 else 0.0
	var last_v: int = targets[targets.size() - 1] if targets.size() > 0 else 10
	var last_l: int = lvs[lvs.size() - 1] if lvs.size() > 0 else 1
	times.append(last_t + 30.0)
	targets.append(last_v)
	lvs.append(last_l)
	_wave_curve.curve_times = times
	_wave_curve.curve_targets = targets
	_wave_curve.curve_lvs = lvs
	_save_wave()
	_rebuild_wave_points()
	_refresh_wave_sim()


func _on_wave_delete_point(i: int) -> void:
	if _wave_curve == null:
		return
	var times: PackedFloat32Array = _wave_curve.curve_times
	var targets: PackedInt32Array = _wave_curve.curve_targets
	var lvs: PackedInt32Array = _wave_curve.curve_lvs
	if i >= 0 and i < times.size():
		times.remove_at(i)
	if i >= 0 and i < targets.size():
		targets.remove_at(i)
	if i >= 0 and i < lvs.size():
		lvs.remove_at(i)
	_wave_curve.curve_times = times
	_wave_curve.curve_targets = targets
	_wave_curve.curve_lvs = lvs
	_save_wave()
	_rebuild_wave_points()
	_refresh_wave_sim()


# ── 스폰 로스터(배열) 편집 ───────────────────────────────────────────────────

# 로스터 행 목록 재구성. spawn_keys 가 비어있으면 레거시→엔트리 prefill(메모리만, 저장X).
func _rebuild_wave_roster() -> void:
	if _wave_roster_box == null:
		return
	for c in _wave_roster_box.get_children():
		c.queue_free()
	if _wave_curve == null:
		_wave_roster_box.add_child(_note("⚠ 챕터 로드 실패"))
		return
	# 비어있으면 레거시에서 prefill — 저장 금지(사용자 미커밋 튜닝 보호).
	if not _curve_has_roster():
		_roster_prefill_from_legacy()
	# 헤더 행.
	var head := HBoxContainer.new()
	for txt in ["종류", "등장시각(s)", "종료시각(s)", "수량(가중치)", "on", ""]:
		var l := Label.new()
		l.text = txt
		l.custom_minimum_size = Vector2(110, 0)
		l.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
		head.add_child(l)
	_wave_roster_box.add_child(head)
	var n: int = _roster_keys().size()
	if n == 0:
		_wave_roster_box.add_child(_note("(로스터 비어있음 → 레거시 동작. '＋ 엔트리 추가'로 배열 편성 시작)"))
		return
	for i in n:
		_wave_roster_box.add_child(_wave_roster_row(i))


func _curve_has_roster() -> bool:
	return _roster_keys().size() > 0


# 로스터 배열 안전 접근 — class_name 캐시 미갱신/구버전 리소스 대비("spawn_keys" 부재 시 빈배열).
func _roster_keys() -> PackedStringArray:
	if _wave_curve == null or not ("spawn_keys" in _wave_curve):
		return PackedStringArray()
	var v = _wave_curve.spawn_keys
	return v if v != null else PackedStringArray()


func _roster_starts() -> PackedFloat32Array:
	if _wave_curve == null or not ("spawn_start_times" in _wave_curve):
		return PackedFloat32Array()
	var v = _wave_curve.spawn_start_times
	return v if v != null else PackedFloat32Array()


func _roster_weights() -> PackedFloat32Array:
	if _wave_curve == null or not ("spawn_weights" in _wave_curve):
		return PackedFloat32Array()
	var v = _wave_curve.spawn_weights
	return v if v != null else PackedFloat32Array()


func _roster_enabled() -> PackedInt32Array:
	if _wave_curve == null or not ("spawn_enabled" in _wave_curve):
		return PackedInt32Array()
	var v = _wave_curve.spawn_enabled
	return v if v != null else PackedInt32Array()


func _roster_ends() -> PackedFloat32Array:
	if _wave_curve == null or not ("spawn_end_times" in _wave_curve):
		return PackedFloat32Array()
	var v = _wave_curve.spawn_end_times
	return v if v != null else PackedFloat32Array()


# 차트 종류 마커용 시작시각 — 로스터(있으면) 활성 enabled 엔트리 중 최소 start_time,
# 없으면 레거시 *_start_time. enabled==1 인 엔트리가 없으면 0 반환(마커 = 미표시: <=0).
func _roster_start_for(key: String) -> float:
	if _curve_has_roster():
		var keys: PackedStringArray = _roster_keys()
		var starts: PackedFloat32Array = _roster_starts()
		var ens: PackedInt32Array = _roster_enabled()
		var best: float = -1.0
		for i in keys.size():
			if str(keys[i]) != key:
				continue
			var en: int = ens[i] if i < ens.size() else 1
			if en != 1:
				continue
			var st: float = starts[i] if i < starts.size() else 0.0
			if best < 0.0 or st < best:
				best = st
		# enabled 엔트리 없음 → 0(마커 그리지 않음). start==0 이면 0(마커 생략 — _draw_marker mt<=0 가드).
		return maxf(0.0, best)
	# 레거시.
	match key:
		"ranged": return float(_wave_curve.ranged_start_time)
		"slammer": return float(_wave_curve.slammer_start_time)
		"leaper": return float(_wave_curve.leaper_start_time)
	return 0.0


# 경고 진단용 — 로스터에서 key 의 활성(enabled==1 && weight>0) 엔트리 최소 start_time.
# 없으면 -1.0(=미등장 경고).
func _roster_active_start_for(key: String) -> float:
	if _wave_curve == null:
		return -1.0
	var keys: PackedStringArray = _roster_keys()
	var starts: PackedFloat32Array = _roster_starts()
	var weights: PackedFloat32Array = _roster_weights()
	var ens: PackedInt32Array = _roster_enabled()
	var best: float = -1.0
	for i in keys.size():
		if str(keys[i]) != key:
			continue
		var en: int = ens[i] if i < ens.size() else 1
		var w: float = weights[i] if i < weights.size() else 0.0
		if en != 1 or w <= 0.0:
			continue
		var st: float = starts[i] if i < starts.size() else 0.0
		if best < 0.0 or st < best:
			best = st
	return best


# 레거시 종류별 필드 → 동등 엔트리 배열을 _wave_curve.spawn_* 에 in-memory set.
# ⚠ 저장 금지 — GUI 표시/시뮬용. (자동 마이그레이션 강제저장이 챕터 튜닝을 덮으면 안 됨)
func _roster_prefill_from_legacy() -> void:
	if _wave_curve == null:
		return
	var rr: float = clampf(float(_wave_curve.ranged_ratio), 0.0, 1.0)
	var lr: float = clampf(float(_wave_curve.leaper_ratio), 0.0, maxf(0.0, 1.0 - rr))
	var sr: float = clampf(float(_wave_curve.slammer_ratio), 0.0, 1.0)
	var rest: float = maxf(0.0, 1.0 - rr - lr)
	var slam_w: float = rest * sr
	var mel_w: float = rest * (1.0 - sr)
	# 엔트리(가중치=레거시 비율 ×10 반올림 자연수 → weighted-random 비율 동등).
	var keys := PackedStringArray()
	var starts := PackedFloat32Array()
	var weights := PackedFloat32Array()
	var ens := PackedInt32Array()
	var ends := PackedFloat32Array()
	# 근접 베이스(항상).
	keys.append("melee"); starts.append(0.0); weights.append(float(maxi(1, int(round(mel_w * 10.0))))); ens.append(1); ends.append(0.0)
	# 궁수.
	keys.append("ranged"); starts.append(float(_wave_curve.ranged_start_time)); weights.append(float(int(round(rr * 10.0)))); ens.append(1 if rr > 0.0 else 0); ends.append(0.0)
	# 슬래머.
	keys.append("slammer"); starts.append(float(_wave_curve.slammer_start_time)); weights.append(float(int(round(slam_w * 10.0)))); ens.append(1 if sr > 0.0 else 0); ends.append(0.0)
	# 리퍼.
	keys.append("leaper"); starts.append(float(_wave_curve.leaper_start_time)); weights.append(float(int(round(lr * 10.0)))); ens.append(1 if lr > 0.0 else 0); ends.append(0.0)
	# 주술사(싱글톤·확률 슬롯 — 0.05=5%).
	keys.append("sorcerer"); starts.append(0.0); weights.append(0.05); ens.append(1); ends.append(0.0)
	_wave_curve.spawn_keys = keys
	_wave_curve.spawn_start_times = starts
	_wave_curve.spawn_weights = weights
	_wave_curve.spawn_enabled = ens
	_wave_curve.spawn_end_times = ends


func _wave_roster_row(i: int) -> Control:
	var hb := HBoxContainer.new()
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 종류 OptionButton.
	var ob := OptionButton.new()
	ob.custom_minimum_size = Vector2(110, 0)
	for k in ROSTER_LABELS.size():
		ob.add_item(ROSTER_LABELS[k], k)
	var _rk := _roster_keys()
	var cur_key: String = str(_rk[i]) if i < _rk.size() else "melee"
	var sel: int = ROSTER_KEYS.find(cur_key)
	ob.select(sel if sel >= 0 else 0)
	ob.item_selected.connect(func(idx):
		var arr: PackedStringArray = _roster_keys()
		if i < arr.size() and idx >= 0 and idx < ROSTER_KEYS.size():
			arr[i] = ROSTER_KEYS[idx]
			_wave_curve.spawn_keys = arr
			_save_wave()
			_refresh_wave_sim())
	hb.add_child(ob)
	# 등장시각.
	var tb := SpinBox.new()
	tb.min_value = 0.0
	tb.max_value = 99999.0
	tb.step = 1.0
	tb.custom_minimum_size = Vector2(110, 0)
	var _rs := _roster_starts()
	tb.value = float(_rs[i]) if i < _rs.size() else 0.0
	tb.value_changed.connect(func(v):
		var arr: PackedFloat32Array = _roster_starts()
		if i < arr.size():
			arr[i] = v
			_wave_curve.spawn_start_times = arr
			_save_wave()
			_refresh_wave_sim())
	hb.add_child(tb)
	# 종료시각.
	var eb := SpinBox.new()
	eb.min_value = 0.0
	eb.max_value = 99999.0
	eb.step = 1.0
	eb.custom_minimum_size = Vector2(110, 0)
	var _ren := _roster_ends()
	eb.value = float(_ren[i]) if i < _ren.size() else 0.0
	eb.tooltip_text = "0=종료없음(챕터 끝까지). 등장시각~종료시각 구간만 활성(웨이브 윈도우)."
	eb.value_changed.connect(func(v):
		var arr: PackedFloat32Array = _roster_ends()
		while arr.size() < _roster_keys().size():
			arr.append(0.0)
		arr[i] = v
		_wave_curve.spawn_end_times = arr
		_save_wave()
		_refresh_wave_sim())
	hb.add_child(eb)
	# 수량(가중치) — 주술사이면 확률(0~1) 슬롯으로 분기.
	var wb := SpinBox.new()
	wb.min_value = 0.0
	wb.max_value = 999.0
	wb.custom_minimum_size = Vector2(110, 0)
	var _rw := _roster_weights()
	wb.value = float(_rw[i]) if i < _rw.size() else 1.0
	if cur_key == "sorcerer":
		wb.step = 0.01
		wb.max_value = 1.0
		wb.tooltip_text = "주술사 확률(0~1, 싱글톤 굴림). 가중치 아님 — 활성 시 매 드립마다 이 확률로 1마리."
	else:
		wb.step = 1.0
		wb.tooltip_text = "수량(상대 가중치, 자연수). 8/1/1=80%/10%/10%. 주술사는 확률(0~1) 의미."
	wb.value_changed.connect(func(v):
		var arr: PackedFloat32Array = _roster_weights()
		if i < arr.size():
			arr[i] = v
			_wave_curve.spawn_weights = arr
			_save_wave()
			_refresh_wave_sim())
	hb.add_child(wb)
	# on/off.
	var cb := CheckBox.new()
	cb.custom_minimum_size = Vector2(40, 0)
	var _re := _roster_enabled()
	cb.button_pressed = (i < _re.size() and _re[i] == 1)
	cb.toggled.connect(func(on):
		var arr: PackedInt32Array = _roster_enabled()
		if i < arr.size():
			arr[i] = 1 if on else 0
			_wave_curve.spawn_enabled = arr
			_save_wave()
			_refresh_wave_sim())
	hb.add_child(cb)
	# 삭제.
	var del := Button.new()
	del.text = "✕"
	del.tooltip_text = "이 엔트리 삭제"
	del.pressed.connect(func(): _on_wave_roster_delete(i))
	hb.add_child(del)
	return hb


func _on_wave_roster_add() -> void:
	if _wave_curve == null:
		return
	# prefill 이 아직 안 됐으면(빈 로스터) 먼저 메모리 prefill 해서 사용자 기존 편성 보존.
	if not _curve_has_roster():
		_roster_prefill_from_legacy()
	var keys: PackedStringArray = _roster_keys()
	var starts: PackedFloat32Array = _roster_starts()
	var weights: PackedFloat32Array = _roster_weights()
	var ens: PackedInt32Array = _roster_enabled()
	var ends: PackedFloat32Array = _roster_ends()
	while ends.size() < keys.size():
		ends.append(0.0)
	keys.append("melee")
	starts.append(0.0)
	weights.append(1.0)
	ens.append(1)
	ends.append(0.0)
	_wave_curve.spawn_keys = keys
	_wave_curve.spawn_start_times = starts
	_wave_curve.spawn_weights = weights
	_wave_curve.spawn_enabled = ens
	_wave_curve.spawn_end_times = ends
	_save_wave()
	_rebuild_wave_roster()
	_refresh_wave_sim()


func _on_wave_roster_delete(i: int) -> void:
	if _wave_curve == null:
		return
	var keys: PackedStringArray = _roster_keys()
	var starts: PackedFloat32Array = _roster_starts()
	var weights: PackedFloat32Array = _roster_weights()
	var ens: PackedInt32Array = _roster_enabled()
	var ends: PackedFloat32Array = _roster_ends()
	if i >= 0 and i < keys.size():
		keys.remove_at(i)
	if i >= 0 and i < starts.size():
		starts.remove_at(i)
	if i >= 0 and i < weights.size():
		weights.remove_at(i)
	if i >= 0 and i < ens.size():
		ens.remove_at(i)
	if i >= 0 and i < ends.size():
		ends.remove_at(i)
	_wave_curve.spawn_keys = keys
	_wave_curve.spawn_start_times = starts
	_wave_curve.spawn_weights = weights
	_wave_curve.spawn_enabled = ens
	_wave_curve.spawn_end_times = ends
	_save_wave()
	_rebuild_wave_roster()
	_refresh_wave_sim()


func _rebuild_wave_fields() -> void:
	if _wave_fields_box == null:
		return
	for c in _wave_fields_box.get_children():
		c.queue_free()
	if _wave_curve == null:
		return
	for spec in WAVE_FIELDS:
		if spec[0] == "@":
			_wave_fields_box.add_child(_section(spec[1]))
		elif spec[0] in _wave_curve:
			_wave_fields_box.add_child(_wave_field_row(spec))


# 단순 필드 — _field_row 와 동일 패턴이나 변경 시 차트 갱신을 추가로 호출.
func _wave_field_row(spec) -> Control:
	var field: String = spec[0]
	var typ: String = spec[3]
	var hb := HBoxContainer.new()
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl := Label.new()
	lbl.text = spec[1]
	lbl.tooltip_text = spec[2]
	lbl.custom_minimum_size = Vector2(160, 0)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	hb.add_child(lbl)
	var sb := SpinBox.new()
	sb.tooltip_text = spec[2]
	sb.custom_minimum_size = Vector2(120, 0)
	sb.min_value = 0.0
	sb.max_value = 99999.0
	if typ == "i":
		sb.step = 1.0
		sb.rounded = true
	else:
		sb.step = 0.01
	sb.value = float(_wave_curve.get(field))
	sb.value_changed.connect(func(v):
		_wave_curve.set(field, int(round(v)) if typ == "i" else v)
		_save_wave()
		_refresh_wave_sim())
	hb.add_child(sb)
	return hb


func _save_wave() -> void:
	if _wave_curve != null and _wave_path != "":
		ResourceSaver.save(_wave_curve, _wave_path)


# ── 시뮬레이션 모델 — WaveManager 복제 ──────────────────────────────────────

# WaveCurve.index_for_elapsed 복제(step 함수 — 보간 아님).
func _sim_index_for_elapsed(elapsed: float) -> int:
	if _wave_curve == null:
		return 0
	var times: PackedFloat32Array = _wave_curve.curve_times
	var n: int = times.size()
	if n == 0:
		return 0
	var idx: int = 0
	for i in n:
		if elapsed >= times[i]:
			idx = i
		else:
			break
	return idx


# WaveCurve.target_for_elapsed 복제.
func _sim_target_for_elapsed(elapsed: float) -> int:
	if _wave_curve == null:
		return 0
	var idx := _sim_index_for_elapsed(elapsed)
	var targets: PackedInt32Array = _wave_curve.curve_targets
	if idx >= targets.size():
		return 0
	return targets[idx]


# 시리즈A — 초당 스폰비율 = target × _RATE_PER_UNIT (WaveManager._maintain_population rate).
func _sim_rate_at(elapsed: float) -> float:
	return float(_sim_target_for_elapsed(elapsed)) * _SIM_RATE_PER_UNIT


func _sim_duration() -> float:
	if _wave_curve == null:
		return 120.0
	var d: float = float(_wave_curve.boss_time)
	var times: PackedFloat32Array = _wave_curve.curve_times
	if times.size() > 0:
		d = max(d, float(times[times.size() - 1]))
	return max(d, 1.0)


func _refresh_wave_sim() -> void:
	if _wave_chart != null:
		_wave_chart.queue_redraw()
	if _wave_compo_chart != null:
		_wave_compo_chart.queue_redraw()
	_update_wave_metrics()
	_update_wave_compo_readout()


# ── 스크럽 콜백 ─────────────────────────────────────────────────────────────

func _on_wave_scrub(v: float, from_slider: bool) -> void:
	_wave_scrub_t = v
	if from_slider:
		if _wave_scrub_spin != null:
			_wave_scrub_spin.set_value_no_signal(v)
	else:
		if _wave_scrub_slider != null:
			_wave_scrub_slider.set_value_no_signal(v)
	if _wave_chart != null:
		_wave_chart.queue_redraw()
	if _wave_compo_chart != null:
		_wave_compo_chart.queue_redraw()
	_update_wave_compo_readout()


# ── 구성 시뮬 헬퍼 ────────────────────────────────────────────────────────────

# WaveCurve.lv_for_elapsed 복제.
func _sim_lv_at(t: float) -> int:
	if _wave_curve == null:
		return 1
	var idx := _sim_index_for_elapsed(t)
	var lvs: PackedInt32Array = _wave_curve.curve_lvs
	if idx >= lvs.size():
		return 1
	return lvs[idx]


# t 시점 몬스터 구성 시뮬 — Main._request_spawn 종류선택 수식 복제.
# 반환: {melee, ranged, slammer, leaper, sorc, rate, lv}
# melee/ranged/slammer/leaper 는 비주술사 풀 기준(합=1).
# 롤 순서: ranged 먼저 차감 → leaper(1-rr 내) → slammer/melee(나머지 내부 분배).
func _sim_composition(t: float) -> Dictionary:
	if _wave_curve == null:
		return {}
	# 로스터(있으면) 기반 — 활성 비주술사 엔트리 가중치 합으로 종류별 비율.
	if _curve_has_roster():
		return _sim_composition_roster(t)
	# 레거시 폴백.
	var rr: float = float(_wave_curve.ranged_ratio) if t >= float(_wave_curve.ranged_start_time) else 0.0
	var lr: float = float(_wave_curve.leaper_ratio) if t >= float(_wave_curve.leaper_start_time) else 0.0
	var sr: float = float(_wave_curve.slammer_ratio) if t >= float(_wave_curve.slammer_start_time) else 0.0
	rr = clampf(rr, 0.0, 1.0)
	# ranged 가 먼저 차감되므로 leaper 는 남은 (1-rr) 내에서만.
	lr = clampf(lr, 0.0, maxf(0.0, 1.0 - rr))
	var rest: float = maxf(0.0, 1.0 - rr - lr)
	var slam: float = rest * clampf(sr, 0.0, 1.0)
	var mel: float = rest * (1.0 - clampf(sr, 0.0, 1.0))
	return {
		"melee": mel,
		"ranged": rr,
		"slammer": slam,
		"leaper": lr,
		"sorc": 0.05,
		"sorc_active": true,
		"rate": _sim_rate_at(t),
		"lv": _sim_lv_at(t),
	}


# 로스터 기반 t 시점 구성 — 활성(enabled&start<=t) 비주술사 엔트리 가중치 합으로 비율.
func _sim_composition_roster(t: float) -> Dictionary:
	var keys: PackedStringArray = _roster_keys()
	var starts: PackedFloat32Array = _roster_starts()
	var weights: PackedFloat32Array = _roster_weights()
	var ens: PackedInt32Array = _roster_enabled()
	var ends: PackedFloat32Array = _roster_ends()
	var sums := {"melee": 0.0, "ranged": 0.0, "slammer": 0.0, "leaper": 0.0}
	var total: float = 0.0
	var sorc_active := false
	var sorc_chance: float = 0.05
	for i in keys.size():
		var en: int = ens[i] if i < ens.size() else 1
		var st: float = starts[i] if i < starts.size() else 0.0
		var et: float = ends[i] if i < ends.size() else 0.0
		if en != 1 or t < st or (et > 0.0 and t >= et):
			continue
		var k: String = str(keys[i])
		if k == "sorcerer":
			sorc_active = true
			sorc_chance = clampf(float(weights[i]) if i < weights.size() else 0.05, 0.0, 1.0)
			continue
		var w: float = weights[i] if i < weights.size() else 0.0
		if w <= 0.0:
			continue
		if not sums.has(k):
			# 미지정 종류 → 근접 베이스로 합산(roster_pick_key 의 미매칭 폴백과 동일).
			k = "melee"
		sums[k] += w
		total += w
	var inv: float = (1.0 / total) if total > 0.0 else 0.0
	return {
		"melee": sums["melee"] * inv,
		"ranged": sums["ranged"] * inv,
		"slammer": sums["slammer"] * inv,
		"leaper": sums["leaper"] * inv,
		"sorc": (sorc_chance if sorc_active else 0.0),
		"sorc_active": sorc_active,
		"rate": _sim_rate_at(t),
		"lv": _sim_lv_at(t),
	}


# 구성 readout 텍스트 갱신.
func _update_wave_compo_readout() -> void:
	if _wave_compo == null:
		return
	if _wave_curve == null:
		_wave_compo.text = ""
		return
	var c: Dictionary = _sim_composition(_wave_scrub_t)
	if c.is_empty():
		_wave_compo.text = ""
		return
	var rate: float = c["rate"]
	if rate <= 0.001:
		_wave_compo.text = "t=%.0fs (레벨 %d) · 이 시각 스폰 없음(휴식 구간)" % [_wave_scrub_t, c["lv"]]
		return
	var elite_state: String = "출현" if _wave_scrub_t >= float(_wave_curve.elite_time) else "미출현"
	var boss_state: String = "출현" if _wave_scrub_t >= float(_wave_curve.boss_time) else "미출현(%.0fs 후)" % maxf(0.0, float(_wave_curve.boss_time) - _wave_scrub_t)
	# ⚠ WaveCurve 는 @tool 아님 → 에디터에선 placeholder 라 .call() 불가. 확률은
	# _sim_composition 이 로컬 산출해 c["sorc"] 로 이미 담아둠(로스터=실확률, 레거시=0.05).
	var sc: float = float(c.get("sorc", 0.05))
	var sorc_txt: String = ("활성(%.0f%% 굴림, 싱글톤)" % (sc * 100.0)) if bool(c.get("sorc_active", true)) else "미활성(로스터 엔트리 없음/off)"
	_wave_compo.text = (
		"t=%.0fs (레벨 %d) · 스폰비율 %.2f/s\n"
		+ "근접(베이스) %.0f%% ~%.2f/s · 궁수 %.0f%% ~%.2f/s · 슬래머 %.0f%% ~%.2f/s · 리퍼 %.0f%% ~%.2f/s\n"
		+ "주술사: %s · 엘리트: %s · 보스: %s"
	) % [
		_wave_scrub_t, c["lv"], rate,
		c["melee"] * 100.0, c["melee"] * rate,
		c["ranged"] * 100.0, c["ranged"] * rate,
		c["slammer"] * 100.0, c["slammer"] * rate,
		c["leaper"] * 100.0, c["leaper"] * rate,
		sorc_txt, elite_state, boss_state,
	]


# ── 차트 ────────────────────────────────────────────────────────────────────

func _draw_wave_chart() -> void:
	var ctrl := _wave_chart
	if ctrl == null or _wave_curve == null:
		return
	var sz := ctrl.size
	var pad_l := 36.0
	var pad_b := 18.0
	var pad_t := 8.0
	var pad_r := 8.0
	var w := sz.x - pad_l - pad_r
	var h := sz.y - pad_t - pad_b
	if w <= 10.0 or h <= 10.0:
		return
	var dur := _sim_duration()
	var font := ctrl.get_theme_default_font()
	var fsz := 10

	# 배경.
	ctrl.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.08, 0.09, 0.12))
	# 시뮬레이션 데이터 산출(피크/적분).
	var dt := 0.5
	var rate_peak := 0.0
	var alive_peak := 0.0
	var alive := 0.0
	var t := 0.0
	var rate_pts := PackedVector2Array()
	var alive_pts := PackedVector2Array()
	while t <= dur:
		var rate := _sim_rate_at(t)
		rate_peak = max(rate_peak, rate)
		# 투영 동시생존 적분 — alive += (rate - clear)*dt, [0, HARD_CAP] 클램프.
		alive += (rate - _wave_clear_rate) * dt
		alive = clampf(alive, 0.0, float(_SIM_HARD_CAP))
		alive_peak = max(alive_peak, alive)
		rate_pts.append(Vector2(t, rate))
		alive_pts.append(Vector2(t, alive))
		t += dt
	var rate_scale := max(rate_peak, 0.001)
	var alive_scale := max(float(_SIM_HARD_CAP), 1.0)

	# 격자 + 분 라벨(세로 격자=1분 간격).
	var grid_col := Color(0.2, 0.22, 0.28)
	var minute := 0
	while float(minute * 60) <= dur:
		var gx := pad_l + (float(minute * 60) / dur) * w
		ctrl.draw_line(Vector2(gx, pad_t), Vector2(gx, pad_t + h), grid_col, 1.0)
		if font != null:
			ctrl.draw_string(font, Vector2(gx + 2, sz.y - 4), "%dm" % minute, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, Color(0.5, 0.55, 0.65))
		minute += 1
	# 가로 격자 4분할.
	for gi in range(1, 4):
		var gy := pad_t + h * (float(gi) / 4.0)
		ctrl.draw_line(Vector2(pad_l, gy), Vector2(pad_l + w, gy), grid_col, 1.0)
	# 축.
	ctrl.draw_line(Vector2(pad_l, pad_t), Vector2(pad_l, pad_t + h), Color(0.4, 0.4, 0.5), 1.0)
	ctrl.draw_line(Vector2(pad_l, pad_t + h), Vector2(pad_l + w, pad_t + h), Color(0.4, 0.4, 0.5), 1.0)

	# 이벤트 마커 세로선.
	_draw_marker(ctrl, _wave_curve.elite_time, dur, pad_l, pad_t, w, h, Color(1.0, 0.6, 0.1), false, "E")
	_draw_marker(ctrl, _wave_curve.boss_time, dur, pad_l, pad_t, w, h, Color(0.7, 0.4, 1.0), false, "B")
	_draw_marker(ctrl, _roster_start_for("ranged"), dur, pad_l, pad_t, w, h, Color(0.5, 0.8, 1.0), true, "R")
	_draw_marker(ctrl, _roster_start_for("slammer"), dur, pad_l, pad_t, w, h, Color(0.95, 0.55, 0.2), true, "S")
	_draw_marker(ctrl, _roster_start_for("leaper"), dur, pad_l, pad_t, w, h, Color(0.7, 0.5, 0.95), true, "L")

	# 시리즈B(투영 생존) — 파랑.
	_draw_series(ctrl, alive_pts, dur, alive_scale, pad_l, pad_t, w, h, Color(0.35, 0.6, 1.0), 1.5)
	# 시리즈A(스폰비율) — 초록(자기 스케일).
	_draw_series(ctrl, rate_pts, dur, rate_scale, pad_l, pad_t, w, h, Color(0.4, 1.0, 0.5), 2.0)

	# Y축 라벨(스폰비율 피크 / 생존 HARD_CAP).
	if font != null:
		ctrl.draw_string(font, Vector2(2, pad_t + 8), "%.1f" % rate_peak, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, Color(0.4, 1.0, 0.5))
		ctrl.draw_string(font, Vector2(2, pad_t + 20), "cap%d" % _SIM_HARD_CAP, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, Color(0.35, 0.6, 1.0))

	# 스크럽 세로선(NOW).
	var now_x: float = pad_l + (_wave_scrub_t / dur) * w
	now_x = clampf(now_x, pad_l, pad_l + w)
	ctrl.draw_line(Vector2(now_x, pad_t), Vector2(now_x, pad_t + h), Color(1.0, 1.0, 1.0, 0.9), 1.5)
	if font != null:
		ctrl.draw_string(font, Vector2(now_x + 2, pad_t + 9), "NOW", HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, Color(1.0, 1.0, 1.0, 0.9))


func _draw_wave_compo_chart() -> void:
	var ctrl := _wave_compo_chart
	if ctrl == null or _wave_curve == null:
		return
	var sz := ctrl.size
	var pad_l := 36.0
	var pad_b := 18.0
	var pad_t := 8.0
	var pad_r := 8.0
	var w := sz.x - pad_l - pad_r
	var h := sz.y - pad_t - pad_b
	if w <= 10.0 or h <= 10.0:
		return
	var dur := _sim_duration()
	var font := ctrl.get_theme_default_font()
	var fsz := 10

	# 배경.
	ctrl.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.07, 0.08, 0.10))

	# 격자(1분 간격).
	var grid_col := Color(0.2, 0.22, 0.28)
	var minute := 0
	while float(minute * 60) <= dur:
		var gx: float = pad_l + (float(minute * 60) / dur) * w
		ctrl.draw_line(Vector2(gx, pad_t), Vector2(gx, pad_t + h), grid_col, 1.0)
		if font != null:
			ctrl.draw_string(font, Vector2(gx + 2, sz.y - 4), "%dm" % minute, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, Color(0.5, 0.55, 0.65))
		minute += 1

	# 종류별 색 스택 밴드 — 시간축 dt=1.0 로 훑음.
	# 색: 근접=회색 / 궁수=하늘 / 슬래머=주황 / 리퍼=보라
	var col_melee := Color(0.6, 0.6, 0.65)
	var col_ranged := Color(0.5, 0.8, 1.0)
	var col_slammer := Color(0.95, 0.55, 0.2)
	var col_leaper := Color(0.7, 0.5, 0.95)
	var dt: float = 1.0
	var t: float = 0.0
	while t <= dur:
		var c: Dictionary = _sim_composition(t)
		if not c.is_empty():
			var x0: float = pad_l + (t / dur) * w
			var x1: float = pad_l + (minf(t + dt, dur) / dur) * w
			var bw: float = maxf(x1 - x0, 1.0)
			# 스택 쌓기 — 아래부터: 근접 / 궁수 / 슬래머 / 리퍼.
			var y_bottom: float = pad_t + h
			var stacks := [
				[c["melee"], col_melee],
				[c["ranged"], col_ranged],
				[c["slammer"], col_slammer],
				[c["leaper"], col_leaper],
			]
			for stack in stacks:
				var frac: float = float(stack[0])
				var band_h: float = frac * h
				if band_h > 0.5:
					ctrl.draw_rect(Rect2(x0, y_bottom - band_h, bw, band_h), stack[1] as Color)
					y_bottom -= band_h
		t += dt

	# 이벤트 마커(엘리트·보스).
	_draw_marker(ctrl, _wave_curve.elite_time, dur, pad_l, pad_t, w, h, Color(1.0, 0.6, 0.1), false, "E")
	_draw_marker(ctrl, _wave_curve.boss_time, dur, pad_l, pad_t, w, h, Color(0.7, 0.4, 1.0), false, "B")

	# 종류 등장 시작 마커(점선).
	_draw_marker(ctrl, _roster_start_for("ranged"), dur, pad_l, pad_t, w, h, col_ranged, true, "R")
	_draw_marker(ctrl, _roster_start_for("slammer"), dur, pad_l, pad_t, w, h, col_slammer, true, "S")
	_draw_marker(ctrl, _roster_start_for("leaper"), dur, pad_l, pad_t, w, h, col_leaper, true, "L")

	# 축.
	ctrl.draw_line(Vector2(pad_l, pad_t), Vector2(pad_l, pad_t + h), Color(0.4, 0.4, 0.5), 1.0)
	ctrl.draw_line(Vector2(pad_l, pad_t + h), Vector2(pad_l + w, pad_t + h), Color(0.4, 0.4, 0.5), 1.0)

	# 범례 (우상단).
	if font != null:
		var lx: float = pad_l + 4.0
		var ly: float = pad_t + 9.0
		ctrl.draw_string(font, Vector2(lx, ly), "■근접", HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, col_melee)
		ctrl.draw_string(font, Vector2(lx + 36, ly), "■궁수", HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, col_ranged)
		ctrl.draw_string(font, Vector2(lx + 72, ly), "■슬래머", HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, col_slammer)
		ctrl.draw_string(font, Vector2(lx + 116, ly), "■리퍼", HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, col_leaper)

	# 스크럽 세로선(NOW).
	var now_x: float = pad_l + (_wave_scrub_t / dur) * w
	now_x = clampf(now_x, pad_l, pad_l + w)
	ctrl.draw_line(Vector2(now_x, pad_t), Vector2(now_x, pad_t + h), Color(1.0, 1.0, 1.0, 0.9), 1.5)


func _draw_series(ctrl: Control, pts: PackedVector2Array, dur: float, yscale: float, pad_l: float, pad_t: float, w: float, h: float, col: Color, width: float) -> void:
	if pts.size() < 2:
		return
	var screen := PackedVector2Array()
	for p in pts:
		var x := pad_l + (p.x / dur) * w
		var y := pad_t + h - (p.y / yscale) * h
		screen.append(Vector2(x, y))
	ctrl.draw_polyline(screen, col, width)


func _draw_marker(ctrl: Control, mt: float, dur: float, pad_l: float, pad_t: float, w: float, h: float, col: Color, dashed: bool, tag: String) -> void:
	if mt <= 0.0 or mt > dur:
		return
	var x := pad_l + (mt / dur) * w
	if dashed:
		var yy := pad_t
		while yy < pad_t + h:
			ctrl.draw_line(Vector2(x, yy), Vector2(x, min(yy + 4.0, pad_t + h)), col, 1.0)
			yy += 8.0
	else:
		ctrl.draw_line(Vector2(x, pad_t), Vector2(x, pad_t + h), col, 1.5)
	var font := ctrl.get_theme_default_font()
	if font != null:
		ctrl.draw_string(font, Vector2(x + 1, pad_t + 9), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)


# ── 지표 / 경고 ──────────────────────────────────────────────────────────────

func _update_wave_metrics() -> void:
	if _wave_metrics == null or _wave_warnings == null:
		return
	if _wave_curve == null:
		_wave_metrics.text = "—"
		_wave_warnings.text = ""
		return
	var dur := _sim_duration()
	var dt := 0.5
	var rate_peak := 0.0
	var alive_peak := 0.0
	var total_spawn := 0.0
	var alive := 0.0
	var rest_segments := 0
	var was_resting := false
	# 틱 모델 적분 — total_spawn 은 max_spawn_per_tick 캡 반영(WaveManager 와 동일).
	var tick := max(0.01, float(_wave_curve.tick_period))
	var max_per_tick: int = int(_wave_curve.max_spawn_per_tick)
	var accum := 0.0
	var tt := 0.0
	while tt <= dur:
		var rate := _sim_rate_at(tt)
		rate_peak = max(rate_peak, rate)
		accum += rate * tick
		var nn: int = int(accum)
		accum -= float(nn)
		nn = min(nn, max_per_tick)
		total_spawn += float(nn)
		# 동시생존 적분(가정 처치율).
		var alive_steps := int(round(tick / dt))
		for _i in max(1, alive_steps):
			alive += (rate - _wave_clear_rate) * dt
			alive = clampf(alive, 0.0, float(_SIM_HARD_CAP))
			alive_peak = max(alive_peak, alive)
		# 휴식 구간(스폰비율 0) 카운트 — 0으로 떨어지는 전환 횟수.
		var resting := rate <= 0.001
		if resting and not was_resting:
			rest_segments += 1
		was_resting = resting
		tt += tick

	_wave_metrics.text = "피크 스폰비율 %.2f/s · 총 투영 스폰 %d · 피크 동시생존 %d · 휴식구간 %d" % [
		rate_peak, int(round(total_spawn)), int(round(alive_peak)), rest_segments]

	# 경고 휴리스틱.
	var warns: Array = []
	# 1) 곡선 배열 길이 불일치.
	var nt: int = _wave_curve.curve_times.size()
	var ng: int = _wave_curve.curve_targets.size()
	var nl: int = _wave_curve.curve_lvs.size()
	if not (nt == ng and ng == nl):
		warns.append("⚠ 곡선 배열 길이 불일치 (시간%d/값%d/레벨%d)" % [nt, ng, nl])
	# 2) curve_times 비정렬.
	var sorted := true
	for i in range(1, nt):
		if _wave_curve.curve_times[i] < _wave_curve.curve_times[i - 1]:
			sorted = false
			break
	if not sorted:
		warns.append("⚠ curve_times 가 시간순 정렬이 아님")
	# 3) 직전 대비 ×2 이상 급증.
	for i in range(1, min(ng, nt)):
		var pv: int = _wave_curve.curve_targets[i - 1]
		var cv: int = _wave_curve.curve_targets[i]
		if pv > 0 and float(cv) >= float(pv) * 2.0:
			warns.append("⚠ %ds 지점 스폰비율 급증 (%d→%d, ×2↑)" % [int(_wave_curve.curve_times[i]), pv, cv])
	# 4) 계속 상승만(휴식 없음) — 값이 한 번도 줄지 않음.
	var ever_down := false
	for i in range(1, ng):
		if _wave_curve.curve_targets[i] < _wave_curve.curve_targets[i - 1]:
			ever_down = true
			break
	if ng >= 2 and not ever_down:
		warns.append("⚠ 곡선이 계속 상승만 — 휴식 구간 없음(완급 부족)")
	# 5) boss_time < elite_time.
	if float(_wave_curve.boss_time) < float(_wave_curve.elite_time):
		warns.append("⚠ boss_time(%.0f) < elite_time(%.0f)" % [float(_wave_curve.boss_time), float(_wave_curve.elite_time)])
	# 6) 투영 생존 HARD_CAP 도달(과밀).
	if int(round(alive_peak)) >= _SIM_HARD_CAP:
		warns.append("⚠ 투영 동시생존이 HARD_CAP(%d) 도달 — 과밀 / 처치율 부족" % _SIM_HARD_CAP)
	# 7~11) 몬스터 종류별 미등장 진단 — 로스터 있으면 엔트리 기반, 없으면 레거시.
	if _curve_has_roster():
		for diag in [["ranged", "궁수"], ["slammer", "슬래머"], ["leaper", "리퍼"]]:
			var dk: String = diag[0]
			var dn: String = diag[1]
			var st: float = _roster_active_start_for(dk)
			if st < 0.0:
				warns.append("⚠ %s 로스터 엔트리 없음/off — 전혀 안 나옴" % dn)
			elif st > dur:
				warns.append("⚠ %s가 챕터 내 등장 안 함(등장시각 %.0fs > 챕터 %.0fs)" % [dn, st, dur])
	else:
		if float(_wave_curve.ranged_start_time) > dur:
			warns.append("⚠ 궁수가 챕터 내 등장 안 함(등장시각 %.0fs > 챕터 %.0fs)" % [float(_wave_curve.ranged_start_time), dur])
		elif float(_wave_curve.ranged_ratio) <= 0.0:
			warns.append("⚠ 궁수 비율 0 — 전혀 안 나옴")
		if float(_wave_curve.leaper_start_time) > dur:
			warns.append("⚠ 리퍼가 챕터 내 등장 안 함(등장시각 %.0fs > 챕터 %.0fs)" % [float(_wave_curve.leaper_start_time), dur])
		elif float(_wave_curve.leaper_ratio) <= 0.0:
			warns.append("⚠ 리퍼 비율 0 — 전혀 안 나옴")
		if float(_wave_curve.slammer_start_time) > dur:
			warns.append("⚠ 슬래머가 챕터 내 등장 안 함(등장시각 %.0fs > 챕터 %.0fs)" % [float(_wave_curve.slammer_start_time), dur])
		elif float(_wave_curve.slammer_ratio) <= 0.0:
			warns.append("⚠ 슬래머 비율 0 — 전혀 안 나옴")
	# 곡선 스폰비율값 전부 0 — 잡몹 미스폰.
	var all_zero: bool = true
	for tgt in _wave_curve.curve_targets:
		if tgt > 0:
			all_zero = false
			break
	if all_zero:
		warns.append("⚠ 곡선 스폰비율값이 전부 0 — 잡몹 미스폰")

	_wave_warnings.text = "\n".join(PackedStringArray(warns)) if warns.size() > 0 else "✔ 경고 없음"


# ── 탭4 레벨업 랩 ──────────────────────────────────────────────────────────────
# EXP 곡선/카드 풀 시각화·시뮬. ExpSystem.gd 기본값을 읽기전용 참조,
# 슬라이더는 시뮬 전용(.gd 저장 안 함). 투영 레벨 공식 = ExpSystem._compute_threshold 복제.
# ──────────────────────────────────────────────────────────────────────────────

func _load_exp_defaults() -> void:
	var es = _ExpSystemScript.new()
	_exp_first = float(es.first_threshold)
	_exp_step = float(es.threshold_step)
	_exp_accel = float(es.threshold_accel)
	es.free()


func _exp_threshold(lv: int) -> int:
	var n: int = max(lv - 1, 0)
	return int(_exp_first) + int(_exp_step) * n + int(round(_exp_accel * float(n) * float(n)))


func _exp_cumulative(lv: int) -> int:
	var total := 0
	for l in range(1, lv):
		total += _exp_threshold(l)
	return total


func _build_levelup_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)

	_load_exp_defaults()

	vb.add_child(_note("레벨업 랩 — 레벨업에 젬을 몇 개 모아야 하는지 + 몇 분에 몇 레벨이 되는지 미리 보고 조절. (적 처치만으론 EXP 0, 떨어진 젬을 주워야 오름 · 잡몹 젬=1, 정예=2, 엘리트=3~10) · 값은 미리보기 전용(.gd 저장 안 함, 영구 반영은 .tres 추출)"))

	# 레벨업 곡선 섹션 — 레벨업당 필요한 젬 개수.
	vb.add_child(_section("─ 레벨업 곡선 (레벨업당 필요한 젬 개수) ─"))
	var param_specs := [
		["첫 레벨업 필요 젬", "Lv1→2 에 필요한 젬 개수(잡몹 1짜리 기준). 줄이면 첫 레벨업이 빨라짐.", 0.0, 9999.0, 1.0, false, "first"],
		["레벨마다 +필요 젬", "레벨이 하나 오를 때마다 더 필요해지는 젬 개수.", 0.0, 9999.0, 1.0, false, "step"],
		["후반 가팔라짐", "레벨이 높을수록 곡선이 가팔라지는 정도. 0이면 일정하게만 증가.", 0.0, 9999.0, 0.1, true, "accel"],
	]
	var param_inits := [_exp_first, _exp_step, _exp_accel]
	for pi in param_specs.size():
		var ps = param_specs[pi]
		var hb := HBoxContainer.new()
		hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var lbl := Label.new()
		lbl.text = ps[0]
		lbl.tooltip_text = ps[1]
		lbl.custom_minimum_size = Vector2(160, 0)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.mouse_filter = Control.MOUSE_FILTER_STOP
		hb.add_child(lbl)
		var sb := SpinBox.new()
		sb.tooltip_text = ps[1]
		sb.custom_minimum_size = Vector2(120, 0)
		sb.min_value = ps[2]
		sb.max_value = ps[3]
		sb.step = ps[4]
		sb.value = param_inits[pi]
		var key: String = ps[6]
		sb.value_changed.connect(func(v):
			if key == "first":
				_exp_first = v
			elif key == "step":
				_exp_step = v
			elif key == "accel":
				_exp_accel = v
			_refresh_lvl_sim())
		hb.add_child(sb)
		vb.add_child(hb)

	# 시뮬레이션 섹션.
	vb.add_child(_section("─ 시간 예측 (몇 분에 몇 레벨?) ─"))
	var xhb := HBoxContainer.new()
	xhb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var xlbl := Label.new()
	xlbl.text = "분당 젬 수입(예측용)"
	xlbl.tooltip_text = "1분에 젬(=EXP)을 몇 개 줍는다고 가정할지. 예측 전용 — 실제 게임 값은 안 바뀜. 예: 60이면 초당 1개."
	xlbl.custom_minimum_size = Vector2(160, 0)
	xlbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xlbl.mouse_filter = Control.MOUSE_FILTER_STOP
	xhb.add_child(xlbl)
	var xsb := SpinBox.new()
	xsb.tooltip_text = "1분에 젬(=EXP)을 몇 개 줍는다고 가정할지. 예측 전용 — 실제 게임 값은 안 바뀜. 예: 60이면 초당 1개."
	xsb.custom_minimum_size = Vector2(120, 0)
	xsb.min_value = 0.0
	xsb.max_value = 5000.0
	xsb.step = 10.0
	xsb.value = _exp_xp_per_min
	xsb.value_changed.connect(func(v):
		_exp_xp_per_min = v
		_refresh_lvl_sim())
	xhb.add_child(xsb)
	vb.add_child(xhb)

	# 차트.
	_lvl_chart = Control.new()
	_lvl_chart.custom_minimum_size = Vector2(320, 220)
	_lvl_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lvl_chart.draw.connect(_draw_lvl_chart)
	vb.add_child(_lvl_chart)

	_lvl_metrics = Label.new()
	_lvl_metrics.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_lvl_metrics)
	_lvl_warnings = Label.new()
	_lvl_warnings.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lvl_warnings.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
	vb.add_child(_lvl_warnings)

	# 빌드 타겟 섹션.
	vb.add_child(_section("─ 빌드 타겟 (시간 → 목표 레벨) ─"))
	_lvl_targets_box = VBoxContainer.new()
	_lvl_targets_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(_lvl_targets_box)
	var add_btn := Button.new()
	add_btn.text = "＋ 타겟 추가"
	add_btn.tooltip_text = "타겟 행 추가(시간=마지막+60, 레벨=마지막+5)"
	add_btn.pressed.connect(_on_lvl_add_target)
	vb.add_child(add_btn)
	_rebuild_lvl_targets()

	# 카드 풀 섹션.
	vb.add_child(_section("─ 카드 풀 (upgrades.csv · 읽기전용) ─"))
	var cards := _load_cards()
	if cards.size() == 0:
		vb.add_child(_note("⚠ upgrades.csv 카드 0장"))
	else:
		for card in cards:
			var clbl := Label.new()
			var suffix := "[초기]" if card.get("initial", false) else "[언락 %d]" % card.get("unlock_cost", 0)
			clbl.text = "· %s (%s) val=%s %s" % [card.get("name", "?"), card.get("id", "?"), String.num(card.get("value", 0.0), 4).rstrip("0").rstrip("."), suffix]
			clbl.tooltip_text = card.get("desc", "")
			clbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			vb.add_child(clbl)

	_refresh_lvl_sim()
	return scroll


func _refresh_lvl_sim() -> void:
	if _lvl_chart != null:
		_lvl_chart.queue_redraw()
	_update_lvl_metrics()


func _load_cards() -> Array:
	var out: Array = []
	if not FileAccess.file_exists(UPGRADES_CSV):
		return out
	var f := FileAccess.open(UPGRADES_CSV, FileAccess.READ)
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
		var first := row[0].lstrip("﻿").strip_edges()
		if first == "" or first == "id" or first == "식별자(영문키)":
			continue
		var d: Dictionary = {}
		for i in range(min(headers.size(), row.size())):
			d[headers[i].lstrip("﻿").strip_edges()] = row[i].strip_edges()
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


func _rebuild_lvl_targets() -> void:
	if _lvl_targets_box == null:
		return
	for c in _lvl_targets_box.get_children():
		c.queue_free()
	var head := HBoxContainer.new()
	for txt in ["시간(s)", "목표 레벨", ""]:
		var l := Label.new()
		l.text = txt
		l.custom_minimum_size = Vector2(100, 0)
		l.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
		head.add_child(l)
	_lvl_targets_box.add_child(head)
	for i in _lvl_targets.size():
		_lvl_targets_box.add_child(_lvl_target_row(i))


func _lvl_target_row(i: int) -> Control:
	var hb := HBoxContainer.new()
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tsb := SpinBox.new()
	tsb.min_value = 0.0
	tsb.max_value = 99999.0
	tsb.step = 1.0
	tsb.custom_minimum_size = Vector2(100, 0)
	tsb.value = float(_lvl_targets[i][0])
	tsb.value_changed.connect(func(v):
		_lvl_targets[i][0] = v
		_refresh_lvl_sim())
	hb.add_child(tsb)
	var lsb := SpinBox.new()
	lsb.min_value = 1.0
	lsb.max_value = float(_LVL_MAX_LEVEL)
	lsb.step = 1.0
	lsb.rounded = true
	lsb.custom_minimum_size = Vector2(100, 0)
	lsb.value = float(_lvl_targets[i][1])
	lsb.value_changed.connect(func(v):
		_lvl_targets[i][1] = int(round(v))
		_refresh_lvl_sim())
	hb.add_child(lsb)
	var del := Button.new()
	del.text = "✕"
	del.tooltip_text = "이 타겟 삭제"
	del.pressed.connect(func(): _on_lvl_delete_target(i))
	hb.add_child(del)
	return hb


func _on_lvl_add_target() -> void:
	var last_t: float = 60.0
	var last_lv: int = 5
	if _lvl_targets.size() > 0:
		last_t = float(_lvl_targets[_lvl_targets.size() - 1][0])
		last_lv = int(_lvl_targets[_lvl_targets.size() - 1][1])
	var new_t := last_t + 60.0
	var new_lv := mini(last_lv + 5, _LVL_MAX_LEVEL)
	_lvl_targets.append([new_t, new_lv])
	_rebuild_lvl_targets()
	_refresh_lvl_sim()


func _on_lvl_delete_target(i: int) -> void:
	if i < 0 or i >= _lvl_targets.size():
		return
	_lvl_targets.remove_at(i)
	_rebuild_lvl_targets()
	_refresh_lvl_sim()


func _projected_level_at(t_target: float) -> int:
	var xp_per_sec := _exp_xp_per_min / 60.0
	if xp_per_sec <= 0.0:
		return 1
	var t := 0.0
	var exp_pool := 0.0
	var level := 1
	var dt := 0.5
	while t <= t_target:
		exp_pool += xp_per_sec * dt
		while level < _LVL_MAX_LEVEL and exp_pool >= float(_exp_threshold(level)):
			exp_pool -= float(_exp_threshold(level))
			level += 1
		t += dt
	return level


func _draw_lvl_chart() -> void:
	var ctrl := _lvl_chart
	if ctrl == null:
		return
	var sz := ctrl.size
	var pad_l := 36.0
	var pad_b := 18.0
	var pad_t := 8.0
	var pad_r := 8.0
	var w := sz.x - pad_l - pad_r
	var h := sz.y - pad_t - pad_b
	if w <= 10.0 or h <= 10.0:
		return

	var xp_per_sec: float = _exp_xp_per_min / 60.0
	# 챕터 최대시간 = LVL_MAX_LEVEL 도달 시간 또는 타겟 최대시간 중 큰 값.
	var cum_max: float = float(_exp_cumulative(_LVL_MAX_LEVEL))
	var time_to_max: float = cum_max / maxf(xp_per_sec, 0.0001)
	var dur: float = time_to_max
	for tgt in _lvl_targets:
		dur = maxf(dur, float(tgt[0]))
	dur = maxf(dur, 60.0)

	var font := ctrl.get_theme_default_font()
	var fsz := 10

	ctrl.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.08, 0.09, 0.12))

	# 격자 + 분 라벨.
	var grid_col := Color(0.2, 0.22, 0.28)
	var minute := 0
	while float(minute * 60) <= dur:
		var gx: float = pad_l + (float(minute * 60) / dur) * w
		ctrl.draw_line(Vector2(gx, pad_t), Vector2(gx, pad_t + h), grid_col, 1.0)
		if font != null:
			ctrl.draw_string(font, Vector2(gx + 2, sz.y - 4), "%dm" % minute, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, Color(0.5, 0.55, 0.65))
		minute += 1
	for gi in range(1, 4):
		var gy := pad_t + h * (float(gi) / 4.0)
		ctrl.draw_line(Vector2(pad_l, gy), Vector2(pad_l + w, gy), grid_col, 1.0)
	ctrl.draw_line(Vector2(pad_l, pad_t), Vector2(pad_l, pad_t + h), Color(0.4, 0.4, 0.5), 1.0)
	ctrl.draw_line(Vector2(pad_l, pad_t + h), Vector2(pad_l + w, pad_t + h), Color(0.4, 0.4, 0.5), 1.0)

	# 빌드 타겟 마커.
	for tgt in _lvl_targets:
		_draw_marker(ctrl, float(tgt[0]), dur, pad_l, pad_t, w, h, Color(1.0, 0.6, 0.1), false, "T")

	# 시리즈A — 누적EXP 요구량(초록): 레벨 lv 의 도달시간 × 누적EXP 스케일로 표시.
	var cum_peak := float(max(_exp_cumulative(_LVL_MAX_LEVEL), 1))
	var series_a := PackedVector2Array()
	for lv in range(1, _LVL_MAX_LEVEL + 1):
		var t_reach: float = float(_exp_cumulative(lv)) / maxf(xp_per_sec, 0.0001)
		var cum_val := float(_exp_cumulative(lv))
		series_a.append(Vector2(t_reach, cum_val))

	# 시리즈B — 투영 레벨(파랑): 시간 t 적분.
	var series_b := PackedVector2Array()
	var t := 0.0
	var exp_pool := 0.0
	var level := 1
	var dt := 0.5
	while t <= dur:
		exp_pool += xp_per_sec * dt
		while level < _LVL_MAX_LEVEL and exp_pool >= float(_exp_threshold(level)):
			exp_pool -= float(_exp_threshold(level))
			level += 1
		series_b.append(Vector2(t, float(level)))
		t += dt

	# 시리즈 그리기 — B 먼저(파랑, 레벨스케일), A 나중(초록, 누적EXP 스케일).
	_draw_series(ctrl, series_b, dur, float(_LVL_MAX_LEVEL), pad_l, pad_t, w, h, Color(0.35, 0.6, 1.0), 1.5)
	_draw_series(ctrl, series_a, dur, cum_peak, pad_l, pad_t, w, h, Color(0.4, 1.0, 0.5), 2.0)

	# Y축 라벨.
	if font != null:
		ctrl.draw_string(font, Vector2(2, pad_t + 8), "Lv%d" % _LVL_MAX_LEVEL, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, Color(0.35, 0.6, 1.0))
		ctrl.draw_string(font, Vector2(2, pad_t + 20), "xp%d" % int(cum_peak), HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, Color(0.4, 1.0, 0.5))


func _lvl_fmt_time(xp_needed: int, xps: float) -> String:
	if xps <= 0.0:
		return "∞"
	return "%.0fs" % (float(xp_needed) / xps)


func _update_lvl_metrics() -> void:
	if _lvl_metrics == null or _lvl_warnings == null:
		return
	var xp_per_sec := _exp_xp_per_min / 60.0
	var t5 := _lvl_fmt_time(_exp_cumulative(5), xp_per_sec)
	var t10 := _lvl_fmt_time(_exp_cumulative(10), xp_per_sec)
	var t20 := _lvl_fmt_time(_exp_cumulative(20), xp_per_sec)
	_lvl_metrics.text = "Lv5 %s · Lv10 %s · Lv20 %s · 총 레벨업 %d회(카드 픽)" % [t5, t10, t20, _LVL_MAX_LEVEL - 1]

	var warns: Array = []
	# 1) 곡선 비단조.
	for lv in range(2, _LVL_MAX_LEVEL + 1):
		if _exp_threshold(lv) < _exp_threshold(lv - 1):
			warns.append("⚠ EXP 임계가 비단조(레벨 %d 에서 감소)" % lv)
			break
	# 2) 너무 가파름(인접비 ×1.8 이상).
	for lv in range(2, _LVL_MAX_LEVEL + 1):
		var prev := _exp_threshold(lv - 1)
		if prev > 0 and float(_exp_threshold(lv)) / float(prev) >= 1.8:
			warns.append("⚠ EXP 곡선 급증(레벨 %d, ×1.8↑)" % lv)
			break
	# 3) 타겟 미달/초과.
	for tgt in _lvl_targets:
		var tt := float(tgt[0])
		var target_lv := int(tgt[1])
		var proj := _projected_level_at(tt)
		if abs(proj - target_lv) > 2:
			warns.append("⚠ %ds 타겟 Lv%d 미달/초과(투영 Lv%d)" % [int(tt), target_lv, proj])
	_lvl_warnings.text = "\n".join(PackedStringArray(warns)) if warns.size() > 0 else "✔ 경고 없음"
