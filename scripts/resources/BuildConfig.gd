class_name BuildConfig
extends Resource

## 빌드 매니저(addons/build_manager)가 설정하는 빌드 구성.
## 빌드 EXE 의 OutGame 이 읽어 "게임 시작" 단일 메뉴로 진입하고 모드/토글을 적용한다.
## 에디터(개발)에서는 무시 — OutGame 이 OS.has_feature("editor") 로 전체 메뉴를 노출.

## 게임 모드: 0=근접 밀리 / 1=근접 일섬 / 2=원거리 일섬
@export var game_mode: int = 1
## 몬스터 몸 접촉 시 HP 피해.
@export var contact_damage: bool = false
## 일섬 차징 시 카메라 줌(밀리 모드는 보통 OFF).
@export var charge_zoom: bool = true
## 플레이 로그 기록(빌드 EXE 옆 / 에디터는 user://).
@export var play_logging: bool = true
