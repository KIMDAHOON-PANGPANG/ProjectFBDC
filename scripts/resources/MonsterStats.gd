class_name MonsterStats
extends Resource

## 몬스터 한 종류의 밸런스 데이터. enemy.csv 를 대체하는 인하우스 리소스
## (Godot 에디터 플러그인 "밸런스 툴" 의 몬스터 탭이 편집, CombatData 가 런타임 적용).
## 필드명은 코드 친화 영문 — 한글 표시명/툴팁은 밸런스 툴(addons/balance_tool)이 제공.

@export var id: int = 0                  # 종류 코드(101 근접 / 102 원거리 / 103 엘리트 / 104 리퍼 / 105 슬래머 / 106 주술사 / 201~203 보스)
@export var key: String = ""             # melee/ranged/elite/leaper/slammer/sorcerer/boss
@export var display_name: String = ""    # 표시 이름(몬스터 리스트)
@export var concept: String = ""         # 컨셉 코멘트
@export var color: String = "ffffff"     # 컬러(hex, 인게임 틴트)
@export var icon: String = ""            # 리스트 아이콘 텍스처 경로

# ── 공통 전투 ──
@export var move_speed: float = 2.0
@export var max_hp: int = 1
@export var attack_range: float = 1.6
@export var attack_cooldown: float = 1.4
@export var attack_damage: int = 1
@export var fan_radius: float = 1.8
@export var fan_angle_deg: float = 70.0
@export var separation_radius: float = 1.3
@export var separation_weight: float = 1.2
@export var armor_max: int = 0
@export var stagger_duration: float = 0.4

# ── 원거리(궁수) ──
@export var keep_distance: float = 6.0
@export var arrow_speed: float = 4.7   # 6.75 에서 -30% (요청)
@export var aim_lock_duration: float = 1.3

# ── 리퍼(도약 내려찍기) ──
@export var leap_chance: float = 0.0
@export var leap_radius: float = 2.4
@export var leap_damage: int = 1

# ── 슬래머(강타 내려찍기) ──
@export var slam_range: float = 2.2
@export var slam_windup: float = 2.5
@export var slam_radius: float = 2.8
@export var slam_damage: int = 1
@export var slam_cooldown: float = 1.8

# ── 주술사(장판 + 텔레포트) ──
@export var vision_range: float = 14.0
@export var zone_count: int = 3
@export var zone_radius: float = 2.0
@export var zone_spread: float = 2.6
@export var zone_duration: float = 3.0
@export var zone_slow_mult: float = 0.45
@export var zone_precursor: float = 2.0
@export var teleport_cooldown: float = 20.0
@export var teleport_range: float = 4.0

# ── 보스(멧돼지 돌진 + 시그널/패리) ──
@export var charge_range: float = 22.0
@export var charge_windup: float = 1.0
@export var charge_speed: float = 18.0
@export var charge_distance: float = 16.0
@export var charge_damage: int = 2
@export var charge_recover: float = 0.9
@export var charge_cooldown: float = 1.6
@export var charge_width: float = 2.4
@export var enable_white_signal: bool = false
@export var white_ratio: float = 0.0
@export var enable_purple_signal: bool = false
@export var purple_ratio: float = 0.0
@export var enable_green_signal: bool = false
@export var green_ratio: float = 0.0
