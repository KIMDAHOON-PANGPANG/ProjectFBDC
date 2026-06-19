# 빌드 로그 (배포 빌드 버전)

배포용 Windows 빌드를 버전별로 보관한다. 산출물은 `build/ProjectFBDC-Windows_<버전>.zip`
(`.exe` + `.console.exe` + `.pck` + `README.txt`). 빌드 절차는 `godot-windows-export` 스킬.

> ⚠️ 빌드는 항상 **clean rebuild**(`build/windows`의 `.exe`/`.pck`/`.console.exe` 삭제 →
> `--headless --import` → `--export-debug "Windows Desktop"`)로 뽑는다. `--export-debug` 가
> 간헐적으로 `.pck` 를 재생성하지 않고 기존(옛 코드) 파일을 남기는 현상이 있어, 삭제 후
> 재생성으로 최신 코드 반영을 보장한다. 빌드 후 `build/windows`의 산출물 timestamp 가
> 방금인지 확인할 것.

| 버전 | 날짜 | 커밋 | 내용 |
|---|---|---|---|
| **m1** | 2026-06-17 | `d56e8b7` | 게임 시작 2(이동 차징 일섬) + 럼블식 열관리(HeatBar3D) + 일섬 돌진속도/거리/범위/오버차지 데이터 테이블화 + 모드2 일섬 게이지 비활성 |
| **m2** | 2026-06-20 | `d56e8b7`(+작업트리) | PC 도트 스프라이트(Adventurer idle/run/attack2, 방향=WASD·공격만 마우스) + ESC 웨이브 에디터(근접/원거리 비율 프리셋, 선택 시 재시작) + 원거리 사격 텔레그래프(흰선→중심 빨강 fill→플래시) + 동시 ~25% 회전 사격 + 일섬 탄환 반사 + 피격 1초 무적/일섬 후 회복유예/줌펀치 + 엘리트·보스 해골 스프라이트(1.2x/1.5x) + 모든 적 머리 위 HP바 |

## m1 — 2026-06-17 (`d56e8b7`)

- **파일**: `build/ProjectFBDC-Windows_m1.zip`
- **포함 모드**: 게임 시작(근접 스윙 + RB 게이지 일섬) / **게임 시작 2(LB 이동 차징 일섬 + 열관리)**
- **신규/변경**: GameConfig(모드 분기), Player(차징/오버차지/열관리), HeatBar3D, PlayerData 일섬 데이터 export, SlashAttack BoxShape extents
- **비고**: clean rebuild 로 생성. 직전 빌드들이 `--export-debug` 불안정으로 `.pck` 미갱신(게임 시작 2 누락) 상태였던 것을 이 버전에서 해소.

## m2 — 2026-06-20 (`d56e8b7` + 작업트리, 미커밋)

- **파일**: `build/ProjectFBDC-Windows_m2.zip` (32.6 MB · `.exe`/`.console.exe`/`.pck`/`README.txt`, clean rebuild 02:09)
- **비주얼**: PC 도트 스프라이트(`PlayerSprite` — Adventurer 8프레임 4방향 idle/run/attack2). 적은 해골 스프라이트(`BaseSkeleton`) — 엘리트 1.2x·보스 1.5x 크기 차등 + 타입/테마색 틴트. 모든 적 머리 위 HP 바(`HpBar3D` 코드 인스턴스).
- **조작감**: 캐릭터 방향 = WASD 전용(마우스엔 공격 방향만 동기화). 피격 무적 1초 + 깜빡임. 일섬 착지 회복 유예(접촉/피탄 즉시피격 방지) + 카메라 줌펀치(도착 지점 가시성).
- **전투**: 원거리 사격 텔레그래프 재작성(흰 더미선 → 중심에서 바깥으로 빨강 0~100% fill → 흰 플래시 → 발사) + 동시 사격 ~25% 회전(`aim_lasers` 캡). 일섬으로 적 탄환 반사(역방향·적만 타격·비관통, PC 안 맞게 팩션 변경).
- **개발 도구**: ESC 웨이브 에디터 오버레이 — 근접 웨이브(근90·원5·엘5) / 원거리 웨이브(원90·근5·엘5 · 인원 1/10) / 기본(곡선). 선택 시 `GameConfig.wave_preset` 저장 + 씬 리로드로 그 구성 재시작.
- **검증**: import 0 · Main 부팅 152 bytes(에러 0) · export 0 · 헤드리스 인스턴스화로 적 5종 HP바/해골 스프라이트 _ready 무에러 확인.
