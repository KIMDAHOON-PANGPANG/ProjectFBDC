# ProjectFBDC

> 이 파일은 매 대화에 자동 로드되는 **인덱스**다. 콘텐츠보다 **포인터**가 우선. 상세 설계는 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## 한 줄 정의

HD-2D 핵앤슬래시 + Vampire Survivors 류 메타 진행 + 인왕(Nioh) 풍 텔레그래프 전투. 거합 사무라이 단일 캐릭터, 챕터제, 인게임은 웨이브 방식. Godot 4.7 / d3d12 / Forward Mobile.

## 빠른 명령

- 게임 실행 (OutGame 메인 메뉴부터): F5 또는 `godot --path . scenes/main/OutGame.tscn`
- Main 직접 진입 (Ch1 시작): `godot --path . scenes/main/Main.tscn`
- Testplay (스폰 버튼 패널): F6 또는 `godot --path . scenes/main/Testplay.tscn`
- 빌드 → ZIP: `godot-windows-export` 스킬
- 런타임 검증 (.exe + godot.log grep): `godot-runtime-verify` 스킬
- 리팩토링 패스: `refactor-pass` 스킬 (.claude/skills/, 프로젝트 로컬)

## 디렉토리 맵

```
scenes/main/        — Main, Testplay, HD2DCamera (씬 진입점 + 카메라 rig)
scenes/player/      — Player (이아이도 슬래시 + Shift 회피)
scenes/enemies/     — MeleeEnemy(추적 근접) / Leaper(베리에이션2·리프전용, MeleeEnemy.gd behavior=LEAPER) / RangedEnemy / EliteEnemy / Boss
scenes/effects/     — FanTelegraph / LeapTelegraph (근접 리프 빨간 원형 데칼) / AimLaser / BossSignal / CircularSlash / ExplosionBurst
scenes/attack/      — SlashAttack (PC 슬래시 trail) / Kunai (비도 기본공격 투사체)
scenes/ui/          — ExpBar / HpBar3D / ReloadBar3D / LevelUpScreen / ChapterClearScreen / AimArrow / AimCursor (마우스 십자선)
scripts/managers/   — ExpSystem / UpgradeSystem / WaveManager / InfiniteGround / SaveSystem / MetaProgressionSystem / ZenSystem / SoundManager (Autoload) / EliteEffectService · BulletTimeService (Main+Testplay 공유)
scripts/resources/  — PlayerData / EnemyData / CharacterVisuals / WaveCurve / MetaPassive (튜닝용 Resource)
scripts/components/ — HealthComponent / SpriteRig / MonsterCollision
resources/          — .tres 데이터 파일 (player/enemies/visuals/chapters/meta)
resources/chapters/ — chapter_1.tres, chapter_2.tres, chapter_3.tres (WaveCurve)
resources/meta/passives/ — hp_bonus / move_speed / slash_width / exp_gain / evade_cooldown / iframe_extra / free_card (MetaPassive)
data/               — 전투 데이터 테이블: combat_table.xlsx(편집용, README/PC/ENEMY 시트) + pc.csv / enemy.csv(런타임, CombatData 로더가 읽음)
```

## 기능별 인덱스 — "어디를 봐야 하나"

| 만지고 싶은 것 | 핵심 파일 (1~2개) | 보조 파일 |
|---|---|---|
| ⭐ 전투 데이터 관리 (엑셀/CSV, 폴리싱) | `data/combat_table.xlsx`(README/PC/ENEMY 시트, 1행=영문컬럼·2행=한글주석·ENUM셀메모) → `data/pc.csv` / `data/enemy.csv`(런타임) | `scripts/managers/CombatData.gd` 로더가 CSV 읽어 적용 |
| 전투 CSV 로더 (적용 지점) | `CombatData.apply_to_player` (`Player._ready`) · `apply_to_enemy(self, kind)` (Melee/Ranged/Elite/Boss `_ready`) | CSV 2행(한글주석) 스킵 · 빈칸=기본값 폴백. ⚠ 잡몹/엘리트 HP 미적용(레벨링/타입표), 보스 HP 는 enemy.csv id(201~203)로 적용 |
| 적 종류 코드 (enemy.csv ENUM) | 101=근접 102=원거리 103=엘리트 · 201/202/203=보스1/2/3 | `CombatData.apply_to_enemy` 의 kind→id 매핑 · `Boss.boss_id` export |
| PC 전투 상수 (이관됨) | `PlayerData.gd` Combat Tuning 그룹 (hit_iframe/knockback/overcharge/perfect_dodge/zen_burst/boss_slash_damage 등) | 기존 `Player.gd` const 에서 이관 — CSV 구동 |
| PC 슬래시 거리/폭/쿨/충전 | `resources/player/player_data.tres` | `scenes/player/Player.gd` |
| PC 이동/회피/i-frame | `scenes/player/Player.gd` | `PlayerData` |
| 회피 2스택 + 5s 리필 | `Player.gd` (`_evade_stacks` / `_evade_refill_t` · `_check_evade_start` 소비 · `_physics_process` 리필) | `pc.csv` evade_max_stacks / evade_refill_time / evade_distance / evade_cooldown |
| 근접 2종 분리 (추적 vs 리프) | `MeleeEnemy.behavior` (CHASER=부채만 / LEAPER=리프만) · `Leaper.tscn`(behavior=1·보라 `leaper_visuals.tres`) | 슬래시는 잡몹/리퍼 한방(`take_hit` 치명타) |
| 리프어택 (곡선 점프+빨간 원형 슬램) | `MeleeEnemy._begin_leap` / `_update_leap` + `scenes/effects/LeapTelegraph.gd` | `enemy.csv` leaper(104) leap_chance/radius/damage · 스폰: chapters `leaper_ratio`(0.1)/`leaper_start_time`(60) → `WaveManager.leaper_ratio` → `Main._request_spawn` |
| 비도 자동/수동 차등 | `Player._fire_kunai` (자동락온=`kunai_autoaim_damage`/`×kunai_autoaim_speed_mult` · 수동=`kunai_damage` 한방) · 이동 시 `kunai_move_spread_deg` 분산 | `pc.csv` · 잡몹 HP=2(`EnemyData.max_hp`)라 수동 한방/자동 두 방 |
| PC HP / 피격 / 사망 | `Player.gd` + `scripts/components/HealthComponent.gd` | — |
| HP 칸 UI (좌상단 빨간 사각형) | `Main.gd` `_build_hud`(`_hp_box`) + `_refresh_hp_cells` (`get_hp`/`get_max_hp`, `_HP_FULL/_HP_EMPTY`) · `Testplay.gd` 미러 | 머리 위 연속바는 `scenes/ui/HpBar3D.gd` (병행) |
| 피격 연출 (넉백 / 0.5s 무적 / 플래시) | `Player.take_hit` (`_knockback_nearby_enemies` · `HIT_IFRAME`/`_iframe_t`/`is_invincible` · `SpriteRig.flash`/`start_iframe_blink`) | `scripts/components/SpriteRig.gd` |
| 기본 공격 비도 (LB 발사 / 탄약 / 자동리로드 / SPACE 자동조준) | `Player.gd` (`_update_kunai` / `_fire_kunai` / `_lock_on_target`) + `scenes/attack/Kunai.gd` | `player_data.tres` (Kunai 그룹) · 입력맵 `fire`(LB) / `autoaim`(SPACE) |
| 리로드 진행바 (캐릭터 위) | `scenes/ui/ReloadBar3D.gd` (`Player.is_reloading()`/`reload_frac()` 덕타이핑) | `Player.tscn` 자식 → Main/Testplay 자동 반영 |
| 장탄수 텍스트 HUD (좌상단) | `Main.gd` `_build_hud`(`_ammo_label`) + `_refresh_ammo` (`get_ammo`/`get_max_ammo`/`is_reloading`) · `Testplay.gd` 미러 | 머리 위 진행바는 `ReloadBar3D` |
| 마우스 십자선 (에임 커서) | `scenes/ui/AimCursor.gd` (`_draw` 원+십자, OS커서 숨김/복원, process ALWAYS) | `Main.tscn`/`Testplay.tscn` 인스턴스 (OutGame 제외) |
| 일섬(RMB) + 게이지 (100% 게이트 / 사용 후 0) | `Player.gd` (`_check_attack_start` 게이트 · `_fire_slash` 리셋 · `add_slash_gauge` / `gain_gauge_on_*`) | 입력맵 `slash`(RMB) · `player_data.tres` (Slash Gauge 그룹) |
| 일섬 게이지 획득 배선 | 처치/젬 → `Main.gd`+`Testplay.gd` (`gain_gauge_on_kill`/`gain_gauge_on_gem`) · 저스트회피 → `Player.take_hit` | `slash_gauge_on_kill/gem/perfect_dodge` |
| 일섬 게이지바 HUD (하단 중앙) | `Main.gd` `_build_slash_gauge`/`_refresh_slash_gauge` (+`Testplay.gd` 미러) | `slash_gauge_frac()`/`is_slash_ready()` |
| 새 카드 추가 | `scripts/managers/UpgradeSystem.gd` (CARDS + apply) | `scenes/ui/LevelUpScreen.gd` |
| M3 메커니즘 카드 효과 | Multistrike/Echo/Vampire/Phoenix → `Player.gd` (플래그 + `_fire_multistrike_followup` + `_on_died` Phoenix) · `Main.gd` (`_try_vampire_heal` / `_on_player_slash_finished` Echo) | `HealthComponent.heal()` |
| M3 ⏱ 타이밍 카드 효과 | Counter Step → `Player.on_parry_success` + `_handle_move` speed_mult · Parry Master → `Boss._ready` 보정 + `UpgradeSystem.apply` 즉시 적용 | `Boss._on_parried` |
| EXP 곡선 | `scripts/managers/ExpSystem.gd` | — |
| EXP 젬 드랍/픽업 (VS식) | `scenes/effects/ExpGem.gd` (자석 `magnet_radius`=1.0 / `pickup_radius`=0.6 — 근접픽업) + `Main.award_exp_for_kill` / `collect_exp_gem` | `Testplay` 미러 |
| 골드 재화 (자동 적립) | `MetaProgressionSystem.gold` / `record_gold_reward` (kills×3 + 초) | `Main._on_boss_defeated`/`_on_player_died` → `stats.gold` · `OutGame` 표시 |
| 새 적 추가 | `scenes/enemies/<NewEnemy>.gd` + `.tscn`, `resources/enemies/*.tres` | `Main._wire_enemy_lifecycle`, `Testplay` (버튼) |
| 새 엘리트 효과 (타입 5+) | `EliteEnemy._color_for_type` / `_hp_for_type` + `Main.trigger_elite_effect` | `Testplay` (버튼 추가) |
| 엘리트 4 (보호막) | `Player.shield_charges` (`take_hit` 흡수) ← `Main._give_player_shield` | `EliteEnemy.effect_type=4` |
| 보스 다중 시그널 컬러 | `Boss.gd` (enable_white/purple/green_signal + `_color_override` 0/1/2/3) | `_signal_color_for` |
| Boss post-M6 메커닉 | `Boss._begin_telegraph` _color_override 분기 (WHITE×2뎀 / PURPLE 1.5x 반경 / GREEN followup sweep) | `_spawn_green_followup` |
| ⏱ Zen 미터 | `scripts/managers/ZenSystem.gd` (Main 자식) — on_parry_success / 퍼펙트 차징 +1, max 5 → burst | `Player.has_zen_burst` / `_fire_slash` 부스트 |
| Zen 풀폭 슬래시 | `Player._fire_slash` (burst 시 width×3, range max×1.5) + `SlashAttack` `zen_burst` meta → 보스 5뎀 | `ZenSystem.consume_burst` |
| 사운드 (SoundManager Autoload) | `scripts/managers/SoundManager.gd` (project.godot autoload). `play_sfx(name)` / `play_bgm(name)` | `audio/sfx/*.ogg` · `audio/bgm/*.ogg` (자산 미배치 = silent skip) |
| 챕터별 환경색 | `Main._apply_chapter_visuals` (sky horizon/top + ambient energy) | `_build_chapter_systems` / `_advance_chapter` 호출 |
| 웨이브 곡선 / 챕터 타이밍 | `resources/chapters/chapter_<N>.tres` (`WaveCurve` Resource) | `scripts/managers/WaveManager.gd` (인젝션) |
| 챕터 추가 | `resources/chapters/chapter_<N>.tres` + `Main.gd` `chapter_curves` 배열 export | `Main._advance_chapter` / `_chapter_spawn_*` |
| 챕터 라우팅 (Next → 다음 챕터) | `Main._on_chapter_next_pressed` / `_advance_chapter` | `ChapterClearScreen.next_pressed` |
| 보스 추가 / WHITE 시그널 컬러 | `scenes/enemies/Boss.gd` (`enable_white_signal` export) + `Boss2.tscn` | `Main.boss_scenes[]` |
| ⏱ 퍼펙트 패리 보상 사슬 | `Boss._on_parried` (`parry_boost_window_ms`) + `SlashAttack._resolve_boss_damage` | `Player.parry_boost_until_msec` |
| 챕터 결과 / 사망 UI / NEW! 배지 | `scenes/ui/ChapterClearScreen.gd` / `GameOverScreen.gd` | `Main._on_boss_defeated` / `_on_player_died` |
| 챕터 최고기록 저장 / 로드 | `scripts/managers/SaveSystem.gd` | `user://save.cfg` · M4 메타 진행 토대 |
| 메타 영구강화 (혼 + 패시브) | `scripts/managers/MetaProgressionSystem.gd` + `resources/meta/passives/*.tres` | `user://meta.cfg` |
| ⚠️ 아웃게임 효과 기획 초기화 | `passives/*.tres` 7개 = **빈 슬롯**(내용 비움, id만 유지) · `_apply_effect` no-op | 시스템(혼/MetaMenu/언락/저장)·`PASSIVE_PATHS` 구조는 유지 |
| 메타 패시브 적용 지점 | `Main._build_chapter_systems` 끝 → `MetaProgressionSystem.apply_to(player, exp_system)` | `Player.iframe_bonus` |
| 메인 메뉴 / 영구강화 UI | `scenes/main/OutGame.{gd,tscn}` / `scenes/ui/MetaMenu.{gd,tscn}` | `project.godot run/main_scene` |
| 카드 풀 언락 (M5) | `scenes/ui/CardUnlock.{gd,tscn}` + `UpgradeSystem.CARDS` `initial`/`unlock_cost` | `MetaProgressionSystem.is_card_unlocked` / `unlock_card` |
| 레벨업 효과 (4안 재설계) | `UpgradeSystem.CARDS` 4장 = 질풍(이동+12%) / 강건(HP+1) / 예리한 비도(비도뎀+1) / 기 충전(일섬게이지+20%) + `apply` match | `UpgradeSystem.draw` 필터 |
| 혼 적립 (클리어/사망) | `Main._on_boss_defeated` / `_on_player_died` → `MetaProgressionSystem.record_*_reward` | `stats.souls` → 결과 화면 |
| 보스 패턴 / 패리 윈도우 | `scenes/enemies/Boss.gd` | `BossSignal.gd`, `FanTelegraph.gd` |
| 카메라 연출 (쉐이크/lag) | `scenes/main/HD2DCamera.gd` | — |
| HUD / UI 빌드 | `scenes/ui/<해당파일>.gd` | (현재 일부 `Main._build_hud` — 부채) |
| 스폰 위치 로직 (섹터/패스월/링) | `Main._pick_offscreen_spawn` 외 `_pick_*_spawn` | — |
| 불릿타임 / 채도 | `scripts/managers/BulletTimeService.gd` (`start`/`cancel`/`is_active`) | Main/Testplay가 자식으로 인스턴스 |
| 엘리트 효과 dispatch | `scripts/managers/EliteEffectService.gd` (`trigger`/`spawn_circular_slash`) | Main/Testplay `trigger_elite_effect` 위임 |
| ⏱ 퍼펙트 닷지 | `Player.take_hit` (EVADING + `_evade_elapsed <= 0.12`) → `perfect_dodge` 시그널 | `Main._on_player_perfect_dodge` → 0.5s 불릿타임 |
| ⏱ 차징 그레이드 / Overcharge | `Player._update_aim` (`_overcharge_t`) + `_fizzle_charge` | `OVERCHARGE_GRACE` / `OVERCHARGE_LOCKOUT` |
| ⏱ 잡몹 텔레그래프 캔슬 | `MeleeEnemy.take_hit` (wind-up 중 → `_active_telegraph.cancel()`) | `FanTelegraph.cancel()` |
| 슬래시 VFX (emission/burst 골드) | `SlashAttack._ready` emission + `set_burst_visual()` | `Player._spawn_slash_attack` |
| 사운드 자산 배치 | [docs/AUDIO_GUIDE.md](docs/AUDIO_GUIDE.md) | `SoundManager.gd` |
| 기획 / 로드맵 / 마일스톤 체크리스트 | `docs/GAMEDESIGN.md` | — |

## 동기화 규칙 (CRITICAL)

- **`Main.gd`에 새 전투/진행 시스템을 추가하면 `Testplay.gd`에도 미러링한다.**
  - 두 씬은 의도적으로 중복. Testplay는 자동 스폰만 제외, EXP/레벨업/엘리트 효과/불릿타임 모두 동일.
  - 예외: `WaveManager` 자체는 Testplay에 없음 (그 자리에 우측 버튼 패널).
  - **M8 진행**: 엘리트 효과 + 불릿타임은 `EliteEffectService` / `BulletTimeService`로 추출됨 → 그 부분은 더 이상 미러 코드 아님, 양쪽이 같은 서비스를 인스턴스. 신규 효과는 서비스 한 곳만 수정. (다음 후보: 스폰 로직 `SpawnService`)

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

## 노션 작업 로그 (Notion Log)

기획·리뷰·로드맵 진행은 **개인 Notion 「⚔️ 프로젝트 일섬뱀서」** 단일 페이지의 3개 DB에 기록한다.
**기록 형식·언제·update vs create·연결 검증 등 방법론은 `notion-access` 스킬**(공통)을 따른다.
연결: 개인 `notion-personal` (rlaek78@gmail.com) — 회사 계정과 분리.

이 프로젝트 목적지:
- 페이지: https://app.notion.com/p/374c19a9cda3804eb960d935b0faaed2
- 📋 기획서: `6db3560b-9b2b-47d3-bb52-0adf63e87bd4`
- 🛠 코드 로그: `3d2dfb20-b63e-4984-8c28-8a329fa849fc`
- 🗺 로드맵: `2311e6e4-d6b0-4d15-97ea-832deff5f9af`

## 외부 문서

- 게임 디자인 / 로드맵 / 마일스톤 체크리스트 → [docs/GAMEDESIGN.md](docs/GAMEDESIGN.md)
- 비전 & 타이밍 액션 인터랙티브 대시보드 → [docs/VISION.html](docs/VISION.html)
- 사운드 자산 배치 가이드 (M7) → [docs/AUDIO_GUIDE.md](docs/AUDIO_GUIDE.md)
- 상세 설계 / 데이터 흐름 / 책임 분리 / 확장 시나리오 → [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- 리팩토링 절차 → [.claude/skills/refactor-pass/SKILL.md](.claude/skills/refactor-pass/SKILL.md)
