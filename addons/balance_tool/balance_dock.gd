@tool
extends VBoxContainer

## 인하우스 밸런스 에디터 도크 — Godot 에디터 우측 도크.
##   탭1 "PC 밸런스"      → resources/player/player_data.tres (PlayerData) 편집
##   탭2 "몬스터 밸런스"   → resources/monster_table.tres (MonsterTable) 의 각 몬스터 편집
## 파라미터는 한글 이름 + 마우스오버 한글 툴팁. 값 변경 시 즉시 .tres 저장.

const PLAYER_DATA := "res://resources/player/player_data.tres"
const MONSTER_TABLE := "res://resources/monster_table.tres"

# [필드명, 한글 라벨, 한글 툴팁, 타입("f"=실수 / "i"=정수)]
# 섹션 구분 — ["@", "헤더 텍스트"] 행은 _build_pc_tab 루프가 HSeparator + 헤더 라벨로 렌더.
const PC_FIELDS := [
	["@", "─ 이동 / 생존 ─"],
	["move_speed", "이동 속도", "PC 가 1초에 움직이는 거리(유닛).", "f"],
	["max_hp", "최대 체력", "최대 HP(자연수). 피격마다 몹 공격력만큼 감소. 레벨업 '강건'으로 +1.", "i"],

	["@", "─ 일섬 (거합 / 밀리) ─"],
	["min_slash_range", "일섬 최소 사거리", "차징 0 일 때 일섬이 나가는 최소 거리(유닛).", "f"],
	["max_slash_range", "일섬 최대 사거리(밀리모드)", "근접 밀리 모드 RB 일섬의 풀차지 사거리.", "f"],
	["instant_slash_distance", "일섬 풀차지 사거리(거합)", "거합(일섬) 모드 풀차지 시 돌진 사거리(유닛).", "f"],
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

	["@", "─ 근접 기본공격 ─"],
	["melee_range", "근접 사거리", "밀리 모드 기본 공격(부채 스윙) 사거리(유닛).", "f"],
	["melee_angle_deg", "근접 부채 각도", "기본 공격 부채꼴 각도(도).", "f"],
	["melee_cooldown", "근접 공격 간격(초)", "기본 공격 사이 간격 = 공격 속도.", "f"],
	["melee_damage", "근접 데미지", "기본 공격 1회 데미지.", "i"],
	["melee_hitstop_scale", "멜리 히트스톱 배수", "기본공격 적중 시 멈칫 배수(0~1, 작을수록 강함).", "f"],
	["melee_hitstop_dur", "멜리 히트스톱 시간(초)", "기본공격 히트스톱 지속(초).", "f"],
	["melee_shake_amp", "스윙 쉐이크 세기", "기본공격 스윙 시 카메라 흔들림 세기(유닛).", "f"],
	["melee_shake_dur", "스윙 쉐이크 시간(초)", "스윙 카메라 흔들림 지속(초).", "f"],

	["@", "─ 패리 (거합 RB) ─"],
	["parry_window", "패리 유효 시간(초)", "RB 패리로 발사체를 쳐낼 수 있는 시간 창(초).", "f"],
	["parry_cooldown", "패리 쿨다운(초)", "패리 재사용 대기 시간(초).", "f"],
	["parry_hitstop_scale", "패리 히트스톱 배수", "패리 성공 시 멈칫 배수(작을수록 강함).", "f"],
	["parry_hitstop_dur", "패리 히트스톱 시간(초)", "패리 히트스톱 지속(초).", "f"],
	["parry_guardback_speed", "패리 가드백 속도", "패리 시 뒤로 밀리는 초기속도(유닛/초).", "f"],
	["parry_guardback_dur", "패리 가드백 시간(초)", "가드백 밀림 지속(초).", "f"],

	["@", "─ 피격 / 무적 / 자원 ─"],
	["hit_iframe", "피격 무적 시간(초)", "맞은 뒤 무적 시간. 이 동안 깜빡이며 연속 피해 방지.", "f"],
	["levelup_iframe", "레벨업 무적(초)", "레벨업 시 부여되는 무적 시간(초). 카드 고르고 재개 후 안전.", "f"],
	["contact_damage", "접촉 피해", "몬스터 몸에 닿을 때 받는 HP 감소량.", "i"],
	["knockback_force", "피격 넉백 속도", "피격 시 주변 적이 밀려나는 속도(유닛/초).", "f"],
	["slash_gauge_on_kill", "처치당 일섬 게이지", "적 처치 시 차는 일섬 게이지량(밀리모드).", "f"],

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
	["@", "─ 부채 공격 (근접) ─"],
	["fan_radius", "부채 반경", "부채 텔레그래프 반경(유닛).", "f"],
	["fan_angle_deg", "부채 각도", "부채 텔레그래프 각도(도).", "f"],
	["@", "─ 군집 / 경직 ─"],
	["separation_radius", "분리 반경", "서로 안 겹치게 밀어내는 반경(유닛).", "f"],
	["separation_weight", "분리 가중치", "추격 대비 분리 힘 비중.", "f"],
	["armor_max", "아머(경직 게이지)", "0=아머 없음. 데미지 누적 시 경직.", "i"],
	["stagger_duration", "경직 시간(초)", "아머 소거 시 행동 불가 시간.", "f"],
	["@", "─ [궁수] 원거리 ─"],
	["keep_distance", "원거리 선호 거리", "[궁수] 유지하려는 거리(유닛).", "f"],
	["arrow_speed", "화살 속도", "[궁수] 발사체 속도(유닛/초).", "f"],
	["aim_lock_duration", "조준 노출 시간", "[궁수] 발사 전 조준 텔레그래프 시간(초).", "f"],
	["@", "─ [리퍼] 도약 ─"],
	["leap_chance", "도약 확률", "[리퍼] 사거리 내에서 도약 발동 확률(0~1).", "f"],
	["leap_radius", "도약 슬램 반경", "[리퍼] 내려찍기 원형 반경(유닛).", "f"],
	["leap_damage", "도약 슬램 데미지", "[리퍼] 내려찍기 데미지.", "i"],
	["@", "─ [슬래머] 슬램 ─"],
	["slam_range", "슬램 발동 거리", "[슬래머] 이 거리 안이면 힘주기 시작.", "f"],
	["slam_windup", "슬램 힘주기(초)", "[슬래머] 내려찍기 전 정지 차징 시간(초).", "f"],
	["slam_radius", "슬램 반경", "[슬래머] 광역 슬램 반경(넓음=회피 전용).", "f"],
	["slam_damage", "슬램 데미지", "[슬래머] 슬램 적중 데미지.", "i"],
	["slam_cooldown", "슬램 쿨다운(초)", "[슬래머] 슬램 후 다음 공격까지.", "f"],
	["@", "─ [주술사] 장판 / 텔레포트 ─"],
	["vision_range", "시야 반경", "[주술사] PC 를 보는(장판 시전) 거리.", "f"],
	["zone_count", "장판 개수", "[주술사] 한 번에 까는 장판 수.", "i"],
	["zone_radius", "장판 반경", "[주술사] 각 장판 원형 반경(유닛).", "f"],
	["zone_spread", "장판 흩뿌림 거리", "[주술사] PC 중심에서 장판까지 거리.", "f"],
	["zone_duration", "장판 지속(초)", "[주술사] 진한 장판 지속 시간.", "f"],
	["zone_slow_mult", "장판 감속 배수", "[주술사] 장판 안 이동속도 배수(작을수록 느림).", "f"],
	["zone_precursor", "장판 전조(초)", "[주술사] 흐릿한 전조가 채워지는 시간(초).", "f"],
	["teleport_cooldown", "텔레포트 쿨(초)", "[주술사] 텔레포트 재사용 대기.", "f"],
	["teleport_range", "텔레포트 발동 거리", "[주술사] PC 가 이 안에 오면 점멸.", "f"],
	["@", "─ [보스] 돌진 ─"],
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
	var saver := Callable(self, "_save").bind(_mon_table, MONSTER_TABLE)
	for spec in MON_FIELDS:
		if spec[0] == "@":
			_mon_fields_box.add_child(_section(spec[1]))
		elif spec[0] in m:
			_mon_fields_box.add_child(_field_row(m, spec, saver))


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
	["elite_time", "엘리트 등장(초)", "엘리트 3종 1회 스폰 시각.", "f"],
	["boss_time", "보스 등장(초) = 챕터 길이", "보스 1회 스폰 시각. 챕터 종료 시점.", "f"],
	["@", "─ 스폰 페이싱 ─"],
	["tick_period", "틱 주기(초)", "WaveManager 가 결손을 재평가하는 주기.", "f"],
	["max_spawn_per_tick", "틱당 최대 스폰", "한 틱에 추가되는 최대 마릿수(시각적 분산).", "i"],
	["@", "─ 원거리 ─"],
	["ranged_ratio", "원거리 비율", "드립 스폰이 원거리일 확률(0~1).", "f"],
	["ranged_start_time", "원거리 시작(초)", "원거리가 등장하기 시작하는 경과 시간.", "f"],
	["@", "─ 슬래머 ─"],
	["slammer_ratio", "슬래머 비율", "근접 슬롯 중 슬래머 비율(0~1).", "f"],
	["slammer_start_time", "슬래머 시작(초)", "슬래머 등장 시작 경과 시간.", "f"],
	["@", "─ 리퍼 ─"],
	["leaper_ratio", "리퍼 비율", "리퍼(도약 몹) 드립 스폰 확률(0~1).", "f"],
	["leaper_start_time", "리퍼 시작(초)", "리퍼 등장 시작 경과 시간.", "f"],
]

var _wave_curve = null
var _wave_path: String = ""
var _wave_points_box: VBoxContainer = null
var _wave_fields_box: VBoxContainer = null
var _wave_chart: Control = null
var _wave_metrics: Label = null
var _wave_warnings: Label = null
var _wave_clear_rate: float = 2.0


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

	# 비율 / 이벤트 단순 필드.
	_wave_fields_box = VBoxContainer.new()
	_wave_fields_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(_wave_fields_box)

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

	# 차트.
	_wave_chart = Control.new()
	_wave_chart.custom_minimum_size = Vector2(320, 220)
	_wave_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wave_chart.draw.connect(_draw_wave_chart)
	vb.add_child(_wave_chart)

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
	_update_wave_metrics()


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
	_draw_marker(ctrl, _wave_curve.ranged_start_time, dur, pad_l, pad_t, w, h, Color(0.5, 0.8, 1.0), true, "R")
	_draw_marker(ctrl, _wave_curve.slammer_start_time, dur, pad_l, pad_t, w, h, Color(0.95, 0.55, 0.2), true, "S")
	_draw_marker(ctrl, _wave_curve.leaper_start_time, dur, pad_l, pad_t, w, h, Color(0.7, 0.5, 0.95), true, "L")

	# 시리즈B(투영 생존) — 파랑.
	_draw_series(ctrl, alive_pts, dur, alive_scale, pad_l, pad_t, w, h, Color(0.35, 0.6, 1.0), 1.5)
	# 시리즈A(스폰비율) — 초록(자기 스케일).
	_draw_series(ctrl, rate_pts, dur, rate_scale, pad_l, pad_t, w, h, Color(0.4, 1.0, 0.5), 2.0)

	# Y축 라벨(스폰비율 피크 / 생존 HARD_CAP).
	if font != null:
		ctrl.draw_string(font, Vector2(2, pad_t + 8), "%.1f" % rate_peak, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, Color(0.4, 1.0, 0.5))
		ctrl.draw_string(font, Vector2(2, pad_t + 20), "cap%d" % _SIM_HARD_CAP, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, Color(0.35, 0.6, 1.0))


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

	_wave_warnings.text = "\n".join(PackedStringArray(warns)) if warns.size() > 0 else "✔ 경고 없음"
