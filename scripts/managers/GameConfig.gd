class_name GameConfig
extends RefCounted

## 메인 메뉴(OutGame)에서 고른 인게임 옵션을, 씬 전환 너머로 옮기는 가벼운
## 전역 상태. `change_scene_to_file` 은 인자를 못 넘기므로 static 변수로 들고
## 간다 — 프로세스가 살아 있는 동안 씬을 갈아끼워도 값이 유지된다.
##
## class_name 캐시 미스(헤드리스)를 피하려 참조 측은 preload + 정적 접근을 쓴다:
##   const _GC := preload("res://scripts/managers/GameConfig.gd")
##   _GC.instant_slash_mode

## true = "게임 시작 2" (옛날 거합 컨트롤) — LB 클릭에 일섬이 차징 없이 곧바로
## 나간다. 근접 부채꼴 스윙 + 우클릭 게이지 일섬은 비활성.
## false = 기본(4안) — LB 근접 스윙 + RB 게이지 일섬.
static var instant_slash_mode: bool = false
