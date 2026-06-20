extends SceneTree

## 헤드리스 밸런스 시뮬레이터 — 플레이 0초로 거시 곡선 검증.
## 실행:  godot --headless --path . -s tools/balance_sim.gd
##
## 이 게임의 핵심 거시 질문: "레벨(≈30초)마다 '참격 강화'(공격력+1)를 안 찍으면
## 다중타 위협(슬래머/주술사/보스)이 안 죽는가?" 를 표로 답한다.
##   - 위협 HP(레벨) = 베이스 + (레벨-1)            [Main._apply_level_hp_scaling]
##   - 슬래시 1대 데미지 = 공격력(attack_power)      [SlashAttack → take_hit(amount)]
##   - 처치 타수 = ceil(HP / 공격력),  TTK = 타수 × 슬래시 간격
## 두 시나리오 비교: (a) 무성장 = 공격력 1 고정,  (b) 풀성장 = 공격력 = 레벨.

const SLASH_INTERVAL: float = 1.0   # 가정: 슬래시 평균 간격(초). 실제 손맛 측정값으로 바꿔 튜닝.
const MAX_LV: int = 15
const ELITE_T3_BASE: int = 4        # 엘리트 타입3 베이스 HP(EliteEnemy._hp_for_type)

func _init() -> void:
	_go()

func _ttk(hp: int, dmg: int) -> float:
	return ceil(float(hp) / float(max(dmg, 1))) * SLASH_INTERVAL

func _go() -> void:
	var pd = load("res://resources/player/player_data.tres")
	var table = load("res://resources/monster_table.tres")
	var sl = table.by_id(105)   # 슬래머
	var so = table.by_id(106)   # 주술사
	var bo = table.by_id(201)   # 보스1
	if pd == null or table == null or sl == null or so == null or bo == null:
		print("ERROR: 리소스 로드 실패 (player_data.tres / monster_table.tres)")
		quit()
		return

	print("================ 밸런스 시뮬레이션 (위협 TTK 곡선) ================")
	print("가정: 슬래시 간격 %.1fs · 위협 HP = 베이스 + (레벨-1) · 슬래시 데미지 = 공격력" % SLASH_INTERVAL)
	print("PC: 이동 %.1f / 일섬사거리 %.1f / 폭 %.1f" % [pd.move_speed, pd.instant_slash_distance, pd.slash_width])
	print("베이스 HP — 슬래머 %d / 주술사 %d / 엘리트T3 %d / 보스1 %d" % [sl.max_hp, so.max_hp, ELITE_T3_BASE, bo.max_hp])
	print("")
	print("Lv | 슬래머 주술사 엘T3 보스1 ||  무성장(공1) TTK: 슬/주/엘/보  ||  풀성장(공=Lv) TTK: 슬/주/엘/보")
	print("---+---------------------------++--------------------------------++-------------------------------")
	for lv in range(1, MAX_LV + 1):
		var b: int = lv - 1
		var sl_hp: int = sl.max_hp + b
		var so_hp: int = so.max_hp + b
		var el_hp: int = ELITE_T3_BASE + b
		var bo_hp: int = bo.max_hp + b
		# (a) 무성장 = 공격력 1
		var a1 := "슬%.0f 주%.0f 엘%.0f 보%.0f" % [_ttk(sl_hp,1), _ttk(so_hp,1), _ttk(el_hp,1), _ttk(bo_hp,1)]
		# (b) 풀성장 = 공격력 = 레벨
		var af := "슬%.0f 주%.0f 엘%.0f 보%.0f" % [_ttk(sl_hp,lv), _ttk(so_hp,lv), _ttk(el_hp,lv), _ttk(bo_hp,lv)]
		print("%2d |  %2d   %2d   %2d   %2d  ||  %-28s ||  %s초" % [lv, sl_hp, so_hp, el_hp, bo_hp, a1 + "초", af])
	print("================================================================")
	print("읽는 법: '무성장' 열의 TTK 가 레벨 오를수록 치솟으면 = 공격력 카드를 강제하는 압박이 있다는 뜻.")
	print("        '풀성장' 열이 거의 평평하면 = 매 레벨 카드 1장으로 위협을 일정하게 처리 가능(이상적).")
	quit()
