# ProjectFBDC

> 이 파일은 매 대화에 자동 로드되는 **인덱스**다. 콘텐츠보다 **포인터**가 우선. 상세 설계는 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## 한 줄 정의

HD-2D 핵앤슬래시 + Vampire Survivors 류 메타 진행 + 인왕(Nioh) 풍 텔레그래프 전투. 거합 사무라이 단일 캐릭터, 챕터제, 인게임은 웨이브 방식. Godot 4.7 / d3d12 / Forward Mobile.

## 빠른 명령

- 게임 실행 (Main): F5 또는 `godot --path . scenes/main/Main.tscn`
- Testplay (스폰 버튼 패널): F6 또는 `godot --path . scenes/main/Testplay.tscn`
- 빌드 → ZIP: `godot-windows-export` 스킬
- 런타임 검증 (.exe + godot.log grep): `godot-runtime-verify` 스킬
- 리팩토링 패스: `refactor-pass` 스킬 (.claude/skills/, 프로젝트 로컬)

## 디렉토리 맵

```
scenes/main/        — Main, Testplay, HD2DCamera (씬 진입점 + 카메라 rig)
scenes/player/      — Player (이아이도 슬래시 + Shift 회피)
scenes/enemies/     — MeleeEnemy / RangedEnemy / EliteEnemy / Boss
scenes/effects/     — FanTelegraph / AimLaser / BossSignal / CircularSlash / ExplosionBurst
scenes/attack/      — SlashAttack (PC 슬래시 trail)
scenes/ui/          — ExpBar / HpBar3D / LevelUpScreen / ChapterClearScreen / AimArrow
scripts/managers/   — ExpSystem / UpgradeSystem / WaveManager / InfiniteGround
scripts/resources/  — PlayerData / EnemyData / CharacterVisuals (튜닝용 Resource)
scripts/components/ — HealthComponent / SpriteRig / MonsterCollision
resources/          — .tres 데이터 파일 (player/enemies/visuals)
```

## 기능별 인덱스 — "어디를 봐야 하나"

| 만지고 싶은 것 | 핵심 파일 (1~2개) | 보조 파일 |
|---|---|---|
| PC 슬래시 거리/폭/쿨/충전 | `resources/player/player_data.tres` | `scenes/player/Player.gd` |
| PC 이동/회피/i-frame | `scenes/player/Player.gd` | `PlayerData` |
| PC HP / 피격 / 사망 | `Player.gd` + `scripts/components/HealthComponent.gd` | — |
| 새 카드 추가 | `scripts/managers/UpgradeSystem.gd` (CARDS + apply) | `scenes/ui/LevelUpScreen.gd` |
| EXP 곡선 | `scripts/managers/ExpSystem.gd` | — |
| 새 적 추가 | `scenes/enemies/<NewEnemy>.gd` + `.tscn`, `resources/enemies/*.tres` | `Main._wire_enemy_lifecycle`, `Testplay` (버튼) |
| 새 엘리트 효과 (타입 4+) | `EliteEnemy._color_for_type` / `_hp_for_type` + `Main.trigger_elite_effect` | `Testplay` (버튼 추가) |
| 웨이브 곡선 / 챕터 타이밍 | `scripts/managers/WaveManager.gd` (CURVE_* 상수) | — |
| 챕터 추가 | `Main.gd` (`_build_chapter_systems` / `_chapter_spawn_*`), `ChapterClearScreen.gd` | `WaveManager` (chapter beat) |
| 보스 패턴 / 패리 윈도우 | `scenes/enemies/Boss.gd` | `BossSignal.gd`, `FanTelegraph.gd` |
| 카메라 연출 (쉐이크/lag) | `scenes/main/HD2DCamera.gd` | — |
| HUD / UI 빌드 | `scenes/ui/<해당파일>.gd` | (현재 일부 `Main._build_hud` — 부채) |
| 스폰 위치 로직 (섹터/패스월/링) | `Main._pick_offscreen_spawn` 외 `_pick_*_spawn` | — |
| 불릿타임 / 채도 | `Main._start_bullettime` / `_end_bullettime` | `Testplay` 동일 미러 |
| 기획 / 로드맵 / 마일스톤 체크리스트 | `docs/GAMEDESIGN.md` | — |

## 동기화 규칙 (CRITICAL)

- **`Main.gd`에 새 전투/진행 시스템을 추가하면 `Testplay.gd`에도 미러링한다.**
  - 두 씬은 의도적으로 중복. Testplay는 자동 스폰만 제외, EXP/레벨업/엘리트 효과/불릿타임 모두 동일.
  - 예외: `WaveManager` 자체는 Testplay에 없음 (그 자리에 우측 버튼 패널).
  - 추후 `ArenaServices` 추출이 리팩토링 백로그 ([docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) #6 참고).

## 코딩 컨벤션

- `class_name X` 신규 추가 시: 헤드리스에서 캐시 미갱신 → 다른 스크립트에서 참조 시 `const _XScript := preload("res://...")` + 덕타이핑 (`obj.call("method")`). 자세히 → `godot-runtime-verify` 스킬.
- 새 `.tscn` / `.tres` 헤더에 `uid="uid://..."` 직접 적지 말 것 (Unrecognized UID 오류). 에디터가 생성하게 비워둔다.
- 시그널 핸들러는 `if not is_inside_tree(): return` 가드로 시작 (씬 종료 / 패키지 셧다운 시 NPE 방지).
- 적/이펙트는 group 기반으로 식별: `"enemies"`, `"elites"`, `"boss"`, `"melee_enemies"`, `"player"`, `"camera_rig"`.
- 데이터 튜닝은 `.tres` 리소스 우선. 코드 상수는 시스템 동작 자체에만.
- 한 `.gd` 파일이 **600줄**을 넘으면 `refactor-pass` 스킬 권유 신호 (휴리스틱).

## 작업 환경 / 워크플로우

- 사용자: rlaek78@gmail.com (KIMDAHOON-PANGPANG)
- 작업 폴더: `C:\DEV\GODOT\project-fbdc` (워크트리 아님 — 변경은 여기에 직접)
- Push 워크플로우: **main 브랜치 직접 커밋**. 별도 feature 브랜치 만들지 말 것 (메모리 [feedback_push_workflow])
- 메모리 인덱스: `~/.claude/projects/C--DEV-GODOT-project-fbdc/memory/MEMORY.md`

## 외부 문서

- 게임 디자인 / 로드맵 / 마일스톤 체크리스트 → [docs/GAMEDESIGN.md](docs/GAMEDESIGN.md)
- 상세 설계 / 데이터 흐름 / 책임 분리 / 확장 시나리오 → [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- 리팩토링 절차 → [.claude/skills/refactor-pass/SKILL.md](.claude/skills/refactor-pass/SKILL.md)
