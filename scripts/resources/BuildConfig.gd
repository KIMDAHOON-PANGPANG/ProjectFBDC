class_name BuildConfig
extends Resource

## 빌드 매니저(addons/build_manager)가 설정하는 빌드 구성.
## 빌드 EXE 의 OutGame 이 읽어 "게임 시작" 단일 메뉴로 진입하고 모드/토글을 적용한다.
## 에디터(개발)에서는 무시 — OutGame 이 OS.has_feature("editor") 로 전체 메뉴를 노출.

## 게임 모드(웨이브 프리셋): 0=기본 일섬 / 1=근접 몹 일섬 / 2=원거리 몹 일섬.
## (M8 — 컨트롤은 일섬 단일이라 값은 웨이브 구성만 결정한다.)
@export var game_mode: int = 1
## 일섬 자원: 0=열기 / 1=쿨다운
@export var slash_resource_mode: int = 0
## 일섬 조작: 0=충전 / 1=즉발
@export var slash_aim_mode: int = 1
## 탈진 시 이동 감속 패널티(기본 꺼짐 — 탈진 패널티는 발사 봉인만).
@export var overheat_move_slow: bool = false
## 몬스터 몸 접촉 시 HP 피해.
@export var contact_damage: bool = false
## 일섬 차징 시 카메라 줌.
@export var charge_zoom: bool = true
## 플레이 로그 기록(빌드 EXE 옆 / 에디터는 user://).
@export var play_logging: bool = true
