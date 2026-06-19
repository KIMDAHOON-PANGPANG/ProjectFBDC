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

## ESC 웨이브 에디터 프리셋 — 0=곡선(기본) · 1=근접 웨이브(근90·원5·엘5) ·
## 2=원거리 웨이브(원90·근5·엘5 · 인원 1/10). 버튼이 이 값을 바꾸고 씬을 리로드하면
## 새 Main 이 `_apply_wave_preset` 로 읽어 적용 → "초기화 후 그 프리셋으로 재세팅".
static var wave_preset: int = 0

## ESC 옵션 토글(개발) — 리로드 없이 즉시 반영, 씬 너머로 유지.
## LB(모드2 일섬) 차징 동안 카메라가 서서히 빠지는(줌아웃, 최대값 cap) 효과 on/off.
static var charge_zoom_enabled: bool = false
## 몬스터 몸 충돌 시 HP 감소(모드2 접촉 피해) on/off. 기본 켜짐.
static var contact_damage_enabled: bool = true
