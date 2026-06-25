class_name GameConfig
extends RefCounted

## 메인 메뉴(OutGame)에서 고른 인게임 옵션을, 씬 전환 너머로 옮기는 가벼운
## 전역 상태. `change_scene_to_file` 은 인자를 못 넘기므로 static 변수로 들고
## 간다 — 프로세스가 살아 있는 동안 씬을 갈아끼워도 값이 유지된다.
##
## class_name 캐시 미스(헤드리스)를 피하려 참조 측은 preload + 정적 접근을 쓴다:
##   const _GC := preload("res://scripts/managers/GameConfig.gd")
##   _GC.wave_preset

## M8 — 컨트롤은 일섬 단일(LB 롱프레스 차징·발사). 옛 근접 밀리(LB 스윙·RB 게이지
## 일섬) 모드는 전면 삭제됐다. instant_slash_mode 플래그는 제거 — Player 는 항상
## 일섬 경로로 동작한다.

## ESC 웨이브 에디터 프리셋 — 0=기본 일섬 웨이브(곡선) · 1=근접 몹 일섬(근90·원5·엘5) ·
## 2=원거리 몹 일섬(원90·근5·엘5 · 인원 1/10). 버튼이 이 값을 바꾸고 씬을 리로드하면
## 새 Main 이 `_apply_wave_preset` 로 읽어 적용 → "초기화 후 그 프리셋으로 재세팅".
static var wave_preset: int = 0

## ESC 옵션 토글 — 리로드 없이 즉시 반영, 씬 너머로 유지. LB 일섬 차징 동안 카메라가
## 서서히 빠지는(줌, 최대값 cap) 효과 on/off. 일섬 단일이라 기본 ON(시작 핸들러가 설정).
static var charge_zoom_enabled: bool = false
## 몬스터 몸 충돌 시 HP 감소(접촉 피해) on/off. 기본 꺼짐 — 시작 핸들러 / ESC 툴로 토글.
static var contact_damage_enabled: bool = false

## D-3 플래그(선언만 — 동작 배선은 다음 세션).
## 일섬 자원 방식: 0=열기(Heat, 모드2 기본) / 1=쿨다운.
static var slash_resource_mode: int = 0
## 일섬 에임 방식(즉발 일섬 모드 전용): 0=차징 / 1=즉발(기본).
static var slash_aim_mode: int = 1

## 탈진(오버히트) 시 이동 감속 패널티 on/off. 기본 꺼짐 — 탈진 패널티는 일섬 발사 봉인만,
## 이동 감속은 선택 토글. (BuildConfig.overheat_move_slow / ESC 툴에디터 토글로 제어)
static var overheat_move_slow_enabled: bool = false
