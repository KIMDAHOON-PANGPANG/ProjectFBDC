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
