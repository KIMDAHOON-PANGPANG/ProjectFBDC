# ProjectFBDC

> 이 파일은 매 대화에 자동 로드되는 **인덱스**다. 콘텐츠보다 **포인터**가 우선. 상세 설계는 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## 한 줄 정의

HD-2D 핵앤슬래시 + Vampire Survivors 류 메타 진행 + 인왕(Nioh) 풍 텔레그래프 전투. 거합 사무라이 단일 캐릭터, 챕터제, 인게임은 웨이브 방식. **성장 = 발도술 스타일 1택(숏/미들/롱) + 일섬으로 표식'참(斬)' 누적 + 납도(RB) 정산으로 거두고 처치 연쇄**. Godot 4.7 / d3d12 / Forward Mobile.

## 개발 파이프라인 (자동 적용 — 별도 언급 불필요)

**코드 구현/수정 요청은 항상 `dev-pipeline`으로 처리한다.** 사용자가 명시적으로 자동화를 요청했으므로 Workflow 툴 상시 허가 상태.

파이프라인: **Opus 4.8 리드**(복잡도 판정 + 설계) → **Sonnet 4.6 구현** → **Opus 4.8 교차검증**

적용 대상: 파일을 수정하는 모든 구현 요청.  
제외: 질문, 탐색/분석만, 단순 파일 읽기.

에이전트: `.claude/agents/lead-programmer.md` (Opus 4.8) · `.claude/agents/programmer.md` (Sonnet 4.6)  
스킬/스크립트: `.claude/skills/dev-pipeline/SKILL.md`

### 백그라운드 파이프라인 순서 규칙 (CRITICAL — 동시 실행 충돌 방지)

dev-pipeline 은 백그라운드(Workflow)로 돈다. 여러 개를 동시에 띄우면 **파일 충돌·커밋 레이스**가 난다:

1. **같은 파일을 건드릴 작업은 직렬.** 진행 중 파이프라인이 끝나 **검증·커밋될 때까지** 그 파일을 또 건드리는 다음 파이프라인을 시작하지 말 것. (동시 실행 시 두 번째 writer 가 첫 번째를 덮어써 손상 / 사용자가 `_wave_curve()` 류 전조(WIP) 버그를 봄.)
2. **파일이 안 겹치면(disjoint) 병렬 OK** (예: 한쪽 ExpGem/Sorcerer, 다른쪽 Main/HpBar). 단 의존 시그니처(예: `is_world_pos_visible`) 변경 가능성 있으면 직렬.
3. **순서 고정: 완료 → 검증(import + Main/Testplay 부팅 0에러) → 타겟 커밋 → 다음 착수.** 커밋은 **`git add <특정 파일>`**(타겟)으로 — `.tres` 튜닝·타 작업이 안 섞이게.
4. **파이프라인이 자체 커밋할 수 있음.** 완료 후 `git status` / `git log -1` / `git show --stat` 으로 무엇이 커밋됐는지·`.tres` 튜닝이 휩쓸렸는지 확인.
5. **진행 중 파일 = 미검증 WIP.** 사용자가 중간 상태를 볼 수 있다(켜면 크래시가 정상). 완료 전 "실행/편집 말 것" 안내.
6. **선행이 후행에 흡수되면 중단.** 접근이 바뀌어 선행 작업이 무의미해지면 `TaskStop` 으로 중단 + 부분 편집은 `git checkout -- <파일>` 로 되돌리고(.tres 튜닝은 보존) 깨끗한 베이스에서 재설계.
7. **무관 파일**(CLAUDE.md/docs/노션 등)은 파이프라인과 disjoint 라 병렬 편집·타겟 커밋 가능.

## 빠른 명령

- 게임 실행 (OutGame 메인 메뉴부터): F5 또는 `godot --path . scenes/main/OutGame.tscn`
- Main 직접 진입 (Ch1 시작): `godot --path . scenes/main/Main.tscn`
- Testplay = **밸런싱 아레나** (F1 탭 디버그 패널, 우측 스폰패널 삭제됨): F6 / OutGame "밸런싱 아레나" — 탭 5종 **환경**(무적·시간배속·전체삭제·모드선택 3종) / **스폰**(▶웨이브 시작 토글 `Testplay.toggle_wave`=chapter_1 곡선 자동스폰 + 수량 SpinBox·몬스터별 버튼 → `Testplay.arena_spawn`) / **스탯**(레벨+1·공격력·카드·회피 = 검은 카드창 없이 즉시) / **현재**(PC 최종 적용 스탯 읽기전용) / **튜닝**(라이브 슬라이더) + TTK readout (`scenes/ui/ArenaDebug.gd`)
- 밸런스 시뮬레이터 (플레이 없이 레벨별 위협 TTK 곡선): `godot --headless --path . -s tools/balance_sim.gd`
- 빌드 매니저 (모드/토글 설정 + EXE 빌드): 프로젝트 > 도구 > "빌드 매니저" (`addons/build_manager`) — `build_config.tres` 굽고 `OS.execute` 로 익스포트. 빌드 EXE 는 **게임 시작 단일 메뉴**(OutGame 이 `OS.has_feature("editor")` 로 개발/릴리스 분기 + `BuildConfig` 적용). 플레이 로그 = `PlayLogger` 자동로드(빌드는 EXE 옆 / 에디터는 user:// `playlog_<ts>.txt`)
- 빌드 → ZIP: `godot-windows-export` 스킬
- 런타임 검증 (.exe + godot.log grep): `godot-runtime-verify` 스킬
- 리팩토링 패스: `refactor-pass` 스킬 (.claude/skills/, 프로젝트 로컬)

## 디렉토리 맵

```
scenes/main/        — Main, Testplay, HD2DCamera (씬 진입점 + 카메라 rig)
scenes/player/      — Player (근접 부채꼴 스윙 LB + 일섬 RB + SPACE 회피) · PlayerSprite (PC 도트 애니 — Adventurer 8프레임 4방향 idle/run/attack2)
scenes/enemies/     — MeleeEnemy(추적 근접) / Leaper(베리에이션2·리프전용, behavior=LEAPER) / Slammer(걸어와 2초 힘주기→광역 슬램, behavior=SLAMMER·2방컷) / RangedEnemy(궁수·1방컷) / EliteEnemy / Sorcerer(주술사 엘리트·싱글톤·장판+텔레포트·5방컷) / Boss(멧돼지 돌진 — 추적/돌진/정지 상태머신)
scenes/effects/     — FanTelegraph / LeapTelegraph (근접 리프/슬래머 빨간 원형 데칼) / SorcererZone (주술사 보라 장판 — PC 감속) / ChargeTelegraph (보스 돌진 레인 데칼 — 호밍/lock) / AimLaser / BossSignal / CircularSlash / ExplosionBurst
scenes/attack/      — SlashAttack (일섬 trail) / MeleeSwing (근접 기본공격 부채 VFX)
scenes/ui/          — ExpBar / HpBar3D / DodgeStackBar3D(회피 스택) / HeatBar3D(즉발 일섬 열관리, 모드2만) / LevelUpScreen / SkillViewer(보유 보은 목록 뷰어) / ChapterClearScreen / AimArrow / AimCursor (마우스 십자선)
scripts/managers/   — ExpSystem / UpgradeSystem / WaveManager / InfiniteGround / SaveSystem / MetaProgressionSystem / ZenSystem / SoundManager (Autoload) / EliteEffectService · BulletTimeService (Main+Testplay 공유) / GameConfig (시작 모드 플래그) / TriggerBus(M9 이벤트 버스 — 발도/표식/납도/연쇄) · BoonSystem(보은 로더·draw_boons 스타일 필터) · BoonExecutor(보은 효과 실행기 — Player 자식 단일 인스턴스)
scripts/resources/  — PlayerData / EnemyData / CharacterVisuals / WaveCurve / MetaPassive (튜닝용 Resource)
scripts/components/ — HealthComponent / SpriteRig / MonsterCollision / Knockback (스무스 넉백)
resources/          — .tres 데이터 파일 (player/enemies/visuals/chapters/meta)
resources/chapters/ — chapter_1.tres, chapter_2.tres, chapter_3.tres (WaveCurve)
resources/meta/passives/ — hp_bonus / move_speed / slash_width / exp_gain / evade_cooldown / iframe_extra / free_card (MetaPassive)
resources/          — monster_table.tres(MonsterTable=몬스터 밸런스 단일 소스) + player/player_data.tres(PlayerData=PC 밸런스) · ⚠ 옛 pc.csv/enemy.csv/combat_table.xlsx 는 **삭제됨**(인하우스 툴로 대체)
addons/balance_tool — 인하우스 밸런스 에디터 플러그인(PC/몬스터 탭, 한글 라벨+툴팁) — Godot Project Settings>Plugins 에서 켬
data/               — upgrades.csv(레벨업 효과 — UpgradeSystem 로더, 아직 CSV) · boons.json(M9 권속 은혜 54장(pillar 3/style_kit 35/support 16) — BoonSystem 로더) ⚠ 전투 테이블은 리소스로 이관됨
```

## 기능별 인덱스 — "어디를 봐야 하나"

| 만지고 싶은 것 | 핵심 파일 (1~2개) | 보조 파일 |
|---|---|---|
| ⭐ M9 발도술 3종 스타일 1택 (숏/미들/롱) | `scripts/managers/BoonSystem.gd` `draw_boons`(`force_style`=style 미보유 시 첫 draw 에 발도술 `kind=='style'` 3종만 강제 노출 1픽 · 보유 후 `style_req` 필터 + style 카드 exclusive 제외 → 한 판 한 스타일 풀만) · 카드 데이터 `data/boons.json`(54장(pillar 3/style_kit 35/support 16), `kind`=style/mark/sheathe/slash/control) | `LevelUpScreen`/`SkillViewer`(카드 UI · `BoonSystem.pool_color`=pool별 색(pillar 금/style_kit 청/support 녹)) · `Player.active_boons`(런마다 `_ready` 리셋) |
| ⭐ M9 표식 '참(斬)' (slash_mark) + cap 단일소스 | `scenes/attack/SlashAttack.gd` `_apply_slash_mark`(일섬 적중마다 마커 +1, cap 전이 1회 `ON_MARK_FULL` emit) · **cap 단일소스 = `Player.get_mark_cap()`**(숏3/미들5/롱7 — `BoonExecutor._mark_cap` 도 같은 게터 폴링) | 적 머리 위 가시화 = `Player._status_strip`/HpBar3D 계열 · 표식은 0뎀 마커(데미지 없음, 납도 정산에서만 환금) |
| ⭐ M9 납도(RB) 정산 — slash_mark 거두기 | `scenes/player/Player.gd` `_do_sheathe`→`TriggerBus.ON_SHEATHE` emit → `scripts/managers/BoonExecutor.gd` `_on_sheathe`→`_settle_enemy`(만개 비보스=9999 처형 / 미만·보스=marks×`sheathe_dmg`×거합×취약 / 보스 처형선=저HP+거합+만개) | 쿨타임 = `Player` 납도 쿨 + HUD 시계 클록 표시 · `_BOSS_EXECUTE_THRESHOLD`(보스 처형선) · 거합(IAIDO) perfect 윈도우 = `Player.last_slash_end_msec` |
| ⭐ M9 납도 처치 연쇄 (★무한방지 최우선) | `BoonExecutor.gd` `ON_SHEATHE_KILL`→`_on_sheathe_kill`(연환납도 `_cascade_domino_from` 도미노 + baseline 카드 5종(has-card 게이트) + 연쇄 카드) · **★`_in_cascade` 가드**(연쇄 중 ON_SHEATHE_KILL 재발 차단=무한연쇄 불성립) + `_CASCADE_DEPTH_CAP`/`_KILL_CAP`/`_BASELINE_SPREAD_CAP` 마릿수·뎁스 cap | 카드 다수(baseline 5 + S7 4 + S9 4 + 충전류 + 보조 16 등) · 충전류 관통 처형은 일섬 본체 적중 편승(자동딜 아님, `_in_cascade` 가드) |
| ⭐ M9 납도 연출 (슬로우/줌인/블러드) | `BoonExecutor.gd` 거합 연출(흰 섬광 + 미세 슬로우) · 블러드 FX(`_spawn_blood` 정산 적마다 핏자국 Sprite3D + 빨강 입자 = **FXOnly·take_hit 미호출·0킬**) | `Player` 납도 슬로우모션/캐릭터 줌인 훅 · FX 헬퍼는 더미 연출(보존) |
| ⭐ M9 킬소스 계측 (주인공 규칙 검증) | `BoonExecutor.gd` `get_kill_source_counts`(slash/sheathe/cascade/**other**) → `scenes/ui/ArenaDebug.gd` readout(일섬/납도/연쇄/기타FX) · ★불변식: **기타FX 킬 = 0**(자율 FX 는 take_hit 미호출이라 절대 처치 안 함) | 모든 처치는 일섬 본체·납도 정산·연쇄 중 하나로만 귀속 |
| ⭐ M9 빌드 진행 (pool 분기·L2 기둥 1픽·L3+ kit/support 합성) | `scripts/managers/BoonSystem.gd` `draw_boons`(L2=style 미보유 시 pillar 발도술 3종 결정적 노출 1픽 · L3+=style_req 필터 통과한 style_kit + support 합성, support_slots 램프[lv3~5=1·lv6+=1~2] · pool=pillar/style_kit/support 분기) | `_collect_into`(kit dedup·support 면제) · `data/boons.json` pool 필드 |
| ⭐ M9 보조 카드 16장 (pool=support·전부 0뎀) | `scripts/managers/BoonExecutor.gd` 보조 핸들러(흡인장판/이속 `boon_move_speed_mult`/열식힘 `boon_gauge_burst`/EXP자석 `boon_exp_magnet_mult`/표식가속/질주표식/차지여운/흡혈의 의식 등 — On_Dash/On_Slash_End/On_Kill/On_Sheathe_Kill 트리거) | ★전부 take_hit 미호출 = 기타FX 킬 0 · `data/boons.json` pool=support 16장 |
| ⭐ M9 흡혈/baseline 카드화 (옛 항상-on 6종 → 카드 5종) | `BoonExecutor.gd` `_baseline_heal/gem_summon/mark_spread/heat_refund/echo_slash`(전부 has-card 게이트·0뎀·take_hit 미호출) · 납도 파문 baseline 제거 | 미문서 항상-on 0 — 보유 카드만 발동 |
| ⭐ M9 퍼펙트 타이밍 바 | `scenes/ui/TimingBar3D.gd` (`Player.get_timing_window` 거합/박자/완극 윈도우 시각화) | `Player.gd` `get_timing_window` |
| ⭐ 튜토리얼 (발도/회피/납도) | `scenes/main/Tutorial.gd` (단계별 발도→회피→납도 안내) | `OutGame` 튜토리얼 버튼 |
| ⭐ TAB 일시정지 + 스킬 빌드 뷰 · 납도 쿨 HUD | `scenes/ui/SkillViewer.gd` (TAB → 보유 보은 pool별 색 목록) · 납도 쿨 클록 = `PlayerData.sheathe_cooldown`(`Player.get_sheathe_cooldown_frac`) | `PlayerHud` 클록 표시 |
| ⭐ 전투 밸런스 데이터 (인하우스 툴) | **몬스터** = `resources/monster_table.tres`(`MonsterTable`=`Array[MonsterStats]`, scripts/resources/) · **PC** = `resources/player/player_data.tres`(`PlayerData`) · 편집은 **`addons/balance_tool`** 플러그인(PC/몬스터 탭, 한글 라벨+마우스오버 한글 툴팁, 값 변경 즉시 `ResourceSaver.save`) | CSV/xlsx 전부 삭제됨. 새 몬스터 필드 = `MonsterStats.gd` @export + `balance_dock.gd` `MON_FIELDS` 한 줄 추가 |
| 전투 데이터 로더 (적용 지점) | `CombatData._ensure_loaded`(monster_table.tres → id→MonsterStats 맵) · `apply_to_enemy(self, kind)` (Melee/Ranged/Elite/Sorcerer/Boss `_ready`) — `_apply_*`가 MonsterStats 필드를 적 export 로 복사 · `apply_to_player`=**no-op**(PlayerData.tres 직접 사용) · `all_enemy_rows()`(몬스터 리스트 UI) | kind→id: melee101/ranged102/elite103/leaper104/slammer105/sorcerer106/boss200+boss_id · ⚠ 잡몹/엘리트 HP 미적용(레벨링/타입표), 슬래머·궁수·보스·주술사 HP 는 적용 |
| 적 종류 코드 (enemy.csv ENUM) | 101=근접 102=원거리 103=엘리트 104=리퍼 105=슬래머 106=주술사 · 201/202/203=보스1/2/3 | `CombatData.apply_to_enemy` 의 kind→id 매핑 · `Boss.boss_id` export |
| ⭐ 몬스터 리스트 (ESC 검색 에디터) | `PauseOverlay` 메뉴 "몬스터 리스트" 버튼 → `_build_monsters`(`CombatData.all_enemy_rows` 읽어 카드 목록: 틴트 아이콘 + #id·표시이름 + 컨셉 + 컬러 스와치) + 검색창(`_filter_monsters` 이름/컨셉 필터) | 메타 = `MonsterStats` `display_name`/`concept`/`color`(hex 틴트)/`icon`(텍스처 res) · 슬래머는 `slammer_visuals.tres`(주황 틴트)로 인게임도 컬러 일치 |
| ⭐ 슬래머 (걸어와 2.5초 힘주기 → 광역 원형 슬램, 2방컷) | `MeleeEnemy.behavior=SLAMMER`(`Slammer.tscn`) — `_physics_process` 슬램 분기 → `_begin_slam`(PC 위치 중심 `LeapTelegraph` 데칼 + `slam_windup`**2.5초** rooted "힘주기" → 차오름 끝=슬램+쉐이크) · `take_hit` SLAMMER 분기=`take_damage(1)`(2방컷·잡몹 999 와 분리) | `monster_table.tres`(id 105) slam_range/windup/radius(넓음=회피전용)/damage/cooldown → `_apply_melee` 슬램 reads · `_active_slam_decal` 취소(피격/사망) · 스폰: `Main._spawn_melee_or_slammer`(근접의 `_SLAMMER_RATIO`0.3) |
| ⭐ 주술사 (마법사 엘리트 — 싱글톤·장판·텔레포트, 5방컷) | `scenes/enemies/Sorcerer.{gd,tscn}`(CharacterBody3D · 그룹 enemies/elites/sorcerers) — `_physics_process`: PC 가 `teleport_range`(4) 안 + 쿨(20s) → `_do_teleport`(화면 반대편 `teleport_dist`14 점멸) · `vision_range`(14) 안 + 시전쿨 → `_do_cast`(PC 주변 360° 랜덤 `zone_count`3개 `SorcererZone` 흩뿌림) · 그 외 카이팅 · `take_hit`=`take_damage(1)`(5방컷) | `SorcererZone.gd` **2단계**: ① 전조(`zone_precursor`2s — 흐릿한 원이 scale 0→1 로 점점 채워짐) → ② 발동(진한 장판 + `_spawn_aura` 보라 입자가 솔솔 상승[더미 연출] + PC 가 안이면 `Player.apply_zone_slow`(`zone_slow_mult`0.45) 매프레임=동선 방해, 데미지 0) · `Player._zone_slow_t`/`_handle_move` 감속 훅 · **싱글톤**: `Main._alive_sorcerer_count`<1 + `_try_spawn_sorcerer`(`_SORCERER_CHANCE`0.05) · `monster_table.tres`(106) `_apply_sorcerer` |
| PC 전투 상수 (이관됨) | `PlayerData.gd` Combat Tuning 그룹 (hit_iframe/knockback/overcharge/perfect_dodge/zen_burst/boss_slash_damage 등) | 기존 `Player.gd` const 에서 이관 — CSV 구동 |
| PC 슬래시 거리/폭/쿨/충전 | `resources/player/player_data.tres` | `scenes/player/Player.gd` |
| ⭐ 일섬 돌진속도/거리/범위/오버차지 (기획 테이블) | `PlayerData` `slash_dash_speed`(m/s) · `instant_slash_distance`(m, 모드2 풀차지 사거리) · `instant_overcharge_hold`(s, 모드2 최대차지 유지→자동발사) · `slash_hit_extents`(Vec3 x=폭/y=높이/z=길이가산) | `Player._fire_slash`(대시시간=거리÷속도 `_dash_dur`) · `SlashAttack.configure(start,end,extents)` BoxShape 판정 |
| PC 이동/회피/i-frame | `scenes/player/Player.gd` | `PlayerData` |
| 회피 2스택 (SPACE) + 한칸씩 충전 + 머리위 UI | `Player.gd` (`_evade_stacks` 소비 · `_physics_process` charge 리필 한 칸씩) · `scenes/ui/DodgeStackBar3D.gd`(머리 위 2칸) | `pc.csv` evade_max_stacks / evade_refill_time(칸당) / evade_distance · 입력맵 `dash`=SPACE |
| 근접 2종 분리 (추적 vs 리프) | `MeleeEnemy.behavior` (CHASER=부채만 / LEAPER=리프만) · `Leaper.tscn`(behavior=1·보라 `leaper_visuals.tres`) | 슬래시는 잡몹/리퍼 한방(`take_hit` 치명타) |
| 잡몹 군집 분리 (겹침 방지, Boid) | `MeleeEnemy._separation_vector` + 추격 블렌딩 · 정적 `_sep_list`(프레임당 1회 `melee_enemies` 수집 → 할당 폭증 방지, O(n²) 계산) | `enemy.csv` 근접(101)/리퍼(104) `separation_radius`/`weight` · 엘리트는 `_compute_separation` 별도 · 확장: 공간 그리드로 이웃질의 교체 |
| ⭐ 리프어택 (삐슝→점프→데칼 100%→슬램+쉐이크) | `MeleeEnemy._begin_leap`(토큰 획득·삐슝 빨간 플래시) → `_update_leap`(PRE 사전경고 `leap_pre_time` → AIR 상승·체공·순식간 낙하) · `_spawn_leap_decal`(점프 시작 시 등장, windup=leap_duration 동안 중심→바깥 100% 차오름) · `LeapTelegraph._slam`(착지=100% → 데미지 + 카메라 쉐이크 `shake_amp/dur`) | **동시 3마리 캡**(`Main._alive_leaper_count`<3, `leapers` 그룹) · **그룹 AI 토큰**(`MeleeEnemy._leap_attacker` static — 한 마리만 공격, 나머지 `_leap_standoff_move` 뒷걸음/대기 추적) · **가시성 게이트**(`_is_on_screen` 카메라 절두체 = PC 시야일 때만 발동) · `enemy.csv` leaper(104) leap_chance/radius/damage · 스폰 chapters `leaper_ratio`/`leaper_start_time` |
| ⭐ 기본 공격 (근접 부채꼴 스윙, LB) | `Player._update_melee` / `_do_melee_swing` (커서 방향 전방 부채꼴 → 적 HealthComponent.take_damage) + `scenes/attack/MeleeSwing.gd`(VFX) | `pc.csv` melee_range/angle/cooldown/damage · 이동+공격 동시 · 항상 커서 방향(좌우 플립) · 비도(원거리) 전부 제거 |
| PC HP / 피격 / 사망 | `Player.gd` + `scripts/components/HealthComponent.gd` | — |
| ⭐ PC 도트 스프라이트 (애니) | `scenes/player/PlayerSprite.gd`(Sprite3D + hframes 8) — `market/Adventurer 2D Top-Down` 에셋 4방향(down/left/right/up) idle/run/attack2, 96×80×8 스트립. `set_facing_vec`(4방향)·`set_state`(WALK=run/ATTACK=attack2 1회)·`flash`/`start_iframe_blink`/`play_death_then_free` = SpriteRig 호환 API | `Player.tscn` "SpriteRig" 노드를 PlayerSprite 로 교체(적은 기존 `scripts/components/SpriteRig.gd` 유지) · 일섬 발사 시 set_state(ATTACK)→대시 중 attack2 재생=일섬 연출 · 알파: transparent+ALPHA_CUT_DISCARD+NEAREST, `.import`=PC.png 설정 복제(compress0/mipmap off/detect_3d compress_to=0) |
| ⭐ PC HUD (하단 중앙 통합) | `scenes/ui/PlayerHud.gd` — 초상화(`market/Adventurer.../IDLE/idle_down.png` 얼굴 크롭) + 빨강 HP 바("cur/max" 텍스트, HP=자연수 10) + 열기(=일섬) 5스택 + 회피 2스택 + 레벨 다이아 뱃지. PC 게터(`get_hp`/`get_max_hp`/`is_instant_slash_mode`/`get_heat_frac`/`slash_gauge_frac`/`get_evade_stacks`) 매 프레임 자가 갱신. `Main`/`Testplay` 가 `_PlayerHudScene.new()` 인스턴스 + `exp_system` 주입(레벨 뱃지=`Main._exp_system.level`) | 옛 좌상단 HP 칸·하단 일섬 게이지바 4개 함수(`_build_hp_bar`/`_refresh_hp_cells`/`_build_slash_gauge`/`_refresh_slash_gauge`)는 Main/Testplay 양쪽에서 삭제됨 · 머리 위 3D 바(HpBar3D/DodgeStackBar3D/HeatBar3D)는 PC 한정 `Player._ready` 에서 `visible=false`(하단 HUD 로 이전, 적은 계속 HpBar3D 사용) |
| ⭐ 피격 연출 (넉백 / 1s 무적+깜빡임 / 일섬 후 회복유예) | `Player.take_hit` (`_iframe_t`=`data.hit_iframe`(pc.csv **1.0**) · `is_invincible`=DASHING/EVADING/iframe/**`_slash_grace_t`** · `start_iframe_blink` 무적 동안 플래시 머티리얼 깜빡) · 일섬 착지 시 `_slash_grace_t`=`slash_post_grace`(0.4s)=접촉/피탄 즉시피격 방지 | `PlayerSprite.start_iframe_blink` · `pc.csv` hit_iframe · `_update_dash` 종료에서 grace 세팅 |
| 스무스 넉백 (피격 AOE) | `scripts/components/Knockback.gd`(감쇠 슬라이드) — 적이 소유 `apply_knockback(dir,speed)` · `_kb.integrate(self,delta)` | 피격 시 `Player._knockback_nearby_enemies`(`knockback_force`=속도/`knockback_radius`) · ⚠ 비도 제거로 피탄 넉백 없음 |
| ⭐ 몬스터 경직 + 아머 게이지(poise) | `HealthComponent`(`armor_max`/`armor`/`take_damage` 가 데미지만큼 아머 소거 → 0이면 `staggered` + 경직) · 각 적 `_physics_process` `_health.tick_stagger`+`is_staggered`→정지 | `enemy.csv` armor_max(잡몹0/엘리트4/보스6~8)·stagger_duration · 경직 끝 → 아머 재충전 · 사망 시 `clear_stagger`(경직보다 사망 우선) |
| HP+아머 한 줄 바 (머리 위) | `scenes/ui/HpBar3D.gd` — 빨강 HP(좌) + 파랑 아머(우)를 한 바에 zone 분할(armor_max>0 일 때만 파랑 노출) · top_level + 매 프레임 부모 추적 + 카메라 풀빌보드 | **모든 적**이 `_ready` 에서 `_HpBar3DScene` 코드 인스턴스 + `attach_health` — 잡몹/리퍼/원거리=`follow_offset` y1.55, 엘리트 1.7, 보스 2.7. ⚠ PC 머리 위 바는 `Player._ready` 에서 `HpBar3D/DodgeStackBar3D/HeatBar3D` 전부 `visible=false`(PlayerHud 하단 통합으로 이전) |
| 적 발사체 격추 (PC 공격에 소멸) | `Arrow`(group `enemy_projectiles` + `take_hit`→free) · `Player._do_melee_swing` 부채 안 격추 · `SlashAttack._try_kill` 발사체 우선 격추(킬 카운트 제외) | 발사체 HP 없이 한 방 |
| ⭐ 저스트 패리 (게임 시작2 RMB · 발사체 쳐냄) | 평타(일섬/스윙)는 발사체 **격추만**(`SlashAttack._try_kill`→`Arrow.take_hit`, 반사 없음). 우클릭=패리: `Player._check_parry`→`_start_parry`(attack1 1회 + `_parry_t`=`parry_window`0.2s · `_parry_cd` 쿨) · `is_parrying()` true 중 발사체 적중 시 `Arrow._on_hit`→`Player.on_projectile_parried`(피해 0 + 카메라 쉐이크 + 자기 `hitstop` + **노란 섬광 파티클 버스트**(`_spawn_parry_spark` = CPUParticles3D 1회, 사방 180° 퍼짐·노랑→투명) + `on_parry_success` 보상) | `PlayerData` Parry 그룹(parry_window/cooldown/anim_dur) · `PlayerSprite.play_oneshot("attack1")`(이동 애니가 안 덮는 1회 오버라이드) |
| ⭐ ESC 일시정지 메뉴 + 툴 에디터 (모드 버튼화) | `scenes/ui/PauseOverlay.gd`(CanvasLayer · **process_mode ALWAYS** 라 `tree.paused` 중에도 입력/버튼 동작 — Main 은 paused면 입력 못 받음) · `_unhandled_input`(ESC)→`_pause`(게임 정지 `tree.paused=true` + 전체 화면 **반투명 검정 딤**) / `_resume`(재개) · 메뉴/툴에 **현재 모드명**(`_mode_name`: 컨트롤+웨이브 조합) 표시 · "툴 에디터"→`_open_tools` | **모드 버튼 3종**(`_set_mode(instant, wave)`→`GameConfig.instant_slash_mode`+`wave_preset`+`reload_current_scene`): 근접 밀리(false,0) / 근접 몬스터 일섬(true,1) / 원거리 몬스터 일섬(true,2) · 리로드된 Main 이 instant_slash_mode(Player)+`_apply_wave_preset`(wave_mgr target_mult, 원거리=인원1/10) 적용 · 토글→`GameConfig.charge_zoom_enabled`/`contact_damage_enabled` 즉시 · 자족적(GameConfig만 의존) · **OutGame 은 "게임 시작" 단일**(일섬 모드 기본, 게임 시작1 제거) — 모드 전환은 ESC 에서 |
| ⭐ 원거리 사격 텔레그래프 + 동시 사격 캡 | `AimLaser`(흰 더미 라인 + **몬스터쪽 끝(local −X)→PC(+X)** 로 빨강 fill 0~100% 차오름 → 100% 흰 플래시 → 발사. `_fill.position`=`-len/2+fill_len/2`) · `RangedEnemy._can_fire_now`(활성 `aim_lasers` < `ranged_enemies`수×`_FIRE_FRACTION`(0.25) → **~25%만 동시 사격**, 레이저=슬롯이라 자연 회전) | `AimLaser.lock_duration`/`flash_duration` · 가시성 게이트(PC 화면 내) |
| ⭐ 발사체 PC 피격 (모드2 Hurtbox) | 모드2 는 PC body `collision_layer=0`(서로 안 밀림·보스 돌진 관통)이라 화살(mask Player)이 PC body 를 못 잡음 → `Player.tscn` **Hurtbox Area3D(layer 2=Player, monitorable)** 추가 · `Arrow._on_hit`→`_find_player`(맞은 노드→부모 거슬러 "player" 그룹 = Hurtbox→PC)→take_hit/`is_parrying`. 모드1 은 PC body 가 직접 잡힘 | Hurtbox 는 Area라 적/보스 body 를 막지 않음(돌진 관통 유지) · 이게 패리(`on_projectile_parried`) 작동 전제 |
| ⭐ 일섬 후 가시성 (카메라 줌펀치) | `Player._fire_slash`→`HD2DCamera.zoom_punch`(`slash_cam_zoom_scale`1.18/`time`0.45) · 로컬 오프셋 줌아웃→복귀로 착지 지점 적을 넓게 노출 | `HD2DCamera._update_cam_local`(줌+쉐이크 통합) |
| 비대칭 충돌 (PC가 군중 헤집기) | PC `collision_mask`=World only(불가침) · 적은 World+Player(겹치면 스스로 빠져나감=PC가 밀침) · ⭐ `Boss._eject_overlapping_player` **재도입**(PC가 보스 박스에 끼면 작은축으로 밖 푸시, 대시 중 스킵 · 경계 `_boss_half_xz`=콜리전박스×scale 런타임 산출 → 스케일 변경 자동 추종) | 잡몹은 한 방향 디펜트레이션, 보스만 eject(큰 박스 일섬 관통 실패 끼임 해소) · 보스 노드 스케일 0.6(콜리전 유지) — 비주얼은 해골 스프라이트로 1.5× 차등(별도 행) · 데미지는 부채/슬래시/텔레그래프 판정 |
| ⭐ 타격감 (스윙 카메라쉐이크 + 적중 히트스탑) | `Player._do_melee_swing` 끝 → `camera_rig.shake`(매 스윙) + `hitstop`(적중 시) · `HD2DCamera.hitstop`(`Engine.time_scale` 잠깐↓, ignore_time_scale 타이머로 복구, `_exit_tree` 안전망) | `pc.csv` melee_shake_amp/dur · melee_hitstop_scale/dur · BulletTime(per-enemy)과 독립 |
| 회피 스택 UI (머리 위 2칸) | `scenes/ui/DodgeStackBar3D.gd` (`Player.get_evade_stacks`/`get_max_evade_stacks`/`evade_refill_frac` 덕타이핑, 충전칸은 아래→위 부분채움) | `Player.tscn` 자식 → Main/Testplay 자동 반영 · HP바 위(y≈2.16) |
| 마우스 십자선 (에임 커서) | `scenes/ui/AimCursor.gd` (`_draw` 원+십자, OS커서 숨김/복원, process ALWAYS) | `Main.tscn`/`Testplay.tscn` 인스턴스 (OutGame 제외) |
| 일섬(RMB) + 게이지 (100% 게이트 / 사용 후 0) | `Player.gd` (`_check_attack_start` 게이트 · `_fire_slash` 리셋 · `add_slash_gauge` / `gain_gauge_on_*`) | 입력맵 `slash`(RMB) · `player_data.tres` (Slash Gauge 그룹) |
| 일섬 게이지 획득 배선 | 처치/젬 → `Main.gd`+`Testplay.gd` (`gain_gauge_on_kill`/`gain_gauge_on_gem`) · 저스트회피 → `Player.take_hit` | `slash_gauge_on_kill/gem/perfect_dodge` |
| 일섬 게이지바 HUD (하단 중앙) | **`scenes/ui/PlayerHud.gd`** 열기(=일섬) 5스택에 통합 — 모드2=`get_heat_frac`(열), 모드1=`slash_gauge_frac`(게이지)를 같은 자원으로 표현(`_slash_resource_frac`). 옛 `Main._build_slash_gauge`/`_refresh_slash_gauge` 는 삭제됨 | `slash_gauge_frac()`/`is_slash_ready()` |
| 새 카드 추가 | `scripts/managers/UpgradeSystem.gd` (CARDS + apply) | `scenes/ui/LevelUpScreen.gd` |
| M3 메커니즘 카드 효과 | Multistrike/Echo/Vampire/Phoenix → `Player.gd` (플래그 + `_fire_multistrike_followup` + `_on_died` Phoenix) · `Main.gd` (`_try_vampire_heal` / `_on_player_slash_finished` Echo) | `HealthComponent.heal()` |
| M3 ⏱ 타이밍 카드 효과 | Counter Step → `Player.on_parry_success` + `_handle_move` speed_mult · Parry Master → `Boss._ready` 보정 + `UpgradeSystem.apply` 즉시 적용 | `Boss._on_parried` |
| EXP 곡선 | `scripts/managers/ExpSystem.gd` | — |
| EXP 젬 드랍/픽업 (VS식) | `scenes/effects/ExpGem.gd` — **라이프타임 없음**(줍기 전엔 안 사라짐) · 자석 `magnet_radius`=3.5 + **이지인 호밍**(`_home_t` 램프 `magnet_min_speed`→`magnet_speed`, k² · PC 매 프레임 재추적 = 졸졸 따라붙음) + `Main.award_exp_for_kill`→`_drop_exp_gem`/`collect_exp_gem` | 처치만으론 거의 안 차고 **젬 수집이 EXP원** · `Testplay` 미러 |
| 골드 재화 (자동 적립) | `MetaProgressionSystem.gold` / `record_gold_reward` (kills×3 + 초) | `Main._on_boss_defeated`/`_on_player_died` → `stats.gold` · `OutGame` 표시 |
| 새 적 추가 | `scenes/enemies/<NewEnemy>.gd` + `.tscn`, `resources/enemies/*.tres` | `Main._wire_enemy_lifecycle`, `Testplay` (버튼) |
| ⭐ 엘리트/보스 해골 스프라이트 + 스케일 차등 | 둘 다 큐브 MeshInstance3D → **해골 Sprite3D**("Visual" 노드, `BaseSkeleton.png`) 교체. 크기: 잡몹(pixel 0.02·노드1.5)=1.0× 기준 → **엘리트 pixel 0.024=1.2×**(노드1.5 유지) · **보스 pixel 0.075=1.5×**(노드0.6 유지=eject/콜리전 보존) | 틴트=modulate: 엘리트 `_color_for_type`(타입색) · 보스 `boss_tint` export(1=빨강/2=보라/3=청록) · 플래시/사망 페이드도 modulate 기반(`EliteEnemy`/`Boss` `_on_damaged`/`_play_death_fade`) |
| 새 엘리트 효과 (타입 5+) | `EliteEnemy._color_for_type` / `_hp_for_type` + `Main.trigger_elite_effect` | `Testplay` (버튼 추가) |
| 엘리트 4 (보호막) | `Player.shield_charges` (`take_hit` 흡수) ← `Main._give_player_shield` | `EliteEnemy.effect_type=4` |
| ⚠ 보스 다중 시그널 컬러 (삭제됨) | 멧돼지 돌진 상태머신으로 대체 — `enable_white/purple/green_signal`·`purple_ratio`·`green_ratio`·`telegraph_scene`·`boss_signal_scene` export 및 `.tscn`(Boss/Boss2/Boss3)·CombatData 브리지 모두 제거. `_color_override` 는 항상 0 | 현재 보스 패턴 = "보스 = 멧돼지 돌진" 행 참조 |
| ⚠ Boss post-M6 메커닉 (삭제됨) | WHITE 2뎀/PURPLE 광역/GREEN 다단 시그널 분기는 돌진 상태머신으로 대체됨 | 현재 보스 패턴 = "보스 = 멧돼지 돌진" 행 참조 |
| ⏱ Zen 미터 | `scripts/managers/ZenSystem.gd` (Main 자식) — on_parry_success / 퍼펙트 차징 +1, max 5 → burst | `Player.has_zen_burst` / `_fire_slash` 부스트 |
| Zen 풀폭 슬래시 | `Player._fire_slash` (burst 시 width×3, range max×1.5) + `SlashAttack` `zen_burst` meta → 보스 5뎀 | `ZenSystem.consume_burst` |
| 사운드 (SoundManager Autoload) | `scripts/managers/SoundManager.gd` (project.godot autoload). `play_sfx(name)` / `play_bgm(name)` | `audio/sfx/*.ogg` · `audio/bgm/*.ogg` (자산 미배치 = silent skip) |
| 챕터별 환경색 | `Main._apply_chapter_visuals` (sky horizon/top + ambient energy) | `_build_chapter_systems` / `_advance_chapter` 호출 |
| 웨이브 곡선 / 챕터 타이밍 | `resources/chapters/chapter_<N>.tres` (`WaveCurve` Resource) | `scripts/managers/WaveManager.gd` (인젝션) — ⭐ **시간 기반 비율 모델**(`_maintain_population`/`_RATE_PER_UNIT`): 곡선값×비율로 초당 스폰, 안 잡아도 시간대로 계속 나오고 잡으면 화면 빔(옛 "동시 N 유지" 모델 아님) · 성능 안전망 `_HARD_CAP`(120)에서만 멈춤 |
| 챕터 추가 | `resources/chapters/chapter_<N>.tres` + `Main.gd` `chapter_curves` 배열 export | `Main._advance_chapter` / `_chapter_spawn_*` |
| 챕터 라우팅 (Next → 다음 챕터) | `Main._on_chapter_next_pressed` / `_advance_chapter` | `ChapterClearScreen.next_pressed` |
| 보스 추가 | `scenes/enemies/Boss.gd` + `Boss2.tscn`/`Boss3.tscn` (돌진 파라미터는 데이터 드리블) · ⚠ 시그널 컬러 export(enable_white_signal 등)는 삭제됨 | `Main.boss_scenes[]` |
| ⏱ 퍼펙트 패리 보상 사슬 | `Boss._on_parried` (`parry_boost_window_ms`) + `SlashAttack._resolve_boss_damage` | `Player.parry_boost_until_msec` |
| 챕터 결과 / 사망 UI / NEW! 배지 | `scenes/ui/ChapterClearScreen.gd` / `GameOverScreen.gd` | `Main._on_boss_defeated` / `_on_player_died` |
| 챕터 최고기록 저장 / 로드 | `scripts/managers/SaveSystem.gd` | `user://save.cfg` · M4 메타 진행 토대 |
| 메타 영구강화 (혼 + 패시브) | `scripts/managers/MetaProgressionSystem.gd` + `resources/meta/passives/*.tres` | `user://meta.cfg` |
| ⚠️ 아웃게임 효과 기획 초기화 | `passives/*.tres` 7개 = **빈 슬롯**(내용 비움, id만 유지) · `_apply_effect` no-op | 시스템(혼/MetaMenu/언락/저장)·`PASSIVE_PATHS` 구조는 유지 |
| 메타 패시브 적용 지점 | `Main._build_chapter_systems` 끝 → `MetaProgressionSystem.apply_to(player, exp_system)` | `Player.iframe_bonus` |
| 메인 메뉴 / 영구강화 UI | `scenes/main/OutGame.{gd,tscn}` / `scenes/ui/MetaMenu.{gd,tscn}` | `project.godot run/main_scene` |
| ⭐ 게임 시작 2 (이동 차징 일섬 모드) | `OutGame._on_start2_pressed`(`GameConfig.instant_slash_mode=true`) → `Player._instant_slash` 분기 | `scripts/managers/GameConfig.gd`(static, preload) · `Player._check_instant_slash`(LB→`State.AIMING` 차징 시작) · `State.AIMING` 모드2 `_handle_move`(이동하며 차징, AimArrow가 PC 추적) · `_update_aim` 오버차지 `instant_overcharge_hold`(2s) 후 자동발사(모드1 fizzle 과 달리 발사) · `_check_attack_release`(LB 떼면 발사) · 거리 `lerp(min, instant_slash_distance, frac)` · 근접 스윙 + 일섬 게이지(처치/젬/저스트회피·HUD) 전체 비활성(`add_slash_gauge` no-op) · **NPC 접촉 피해**(`_check_contact_damage` + PC `collision_layer=0`=서로 안 밀림, `contact_damage`/`contact_radius`, take_hit `do_knockback=false`) · 카메라 일섬 동반 이동(`slash_cam_follow_time/mult` → `HD2DCamera.follow_boost`, 대시 동안 추적 밀착 = 공격과 함께 이동), 회피 공통 |
| ⭐ 열관리(Heat) — 즉발 일섬 모드 (럼블식) | `Player._update_heat`/`_add_heat`/`_enter_overheat` (일섬마다 +10%, 직전 7s내 연타 ×1.5 → 7발째 100%, 100%→5s 탈진[이동50%↓ + 발사봉인]→열0, 4s 유예 후 `exp(-k·dt)` 지수감소) · 머리 위 `scenes/ui/HeatBar3D.gd` — **5칸 스택**(연속 게이지 아님, 켜진 칸=`ceil(get_heat_frac×5)`, 칸색 주황→빨강 보간, 탈진 시 전부 회색) | `PlayerData` Heat 그룹(gain_base/combo_window·mult/overheat_*/decay_*) · `_instant_slash`(모드2)만 동작 · getter `is_instant_slash_mode`/`get_heat_frac`/`is_overheated` |
| ⭐ 레벨업 원형 넉백 (피해 0) | 카드 선택 직후 `Main`/`Testplay._on_upgrade_card_selected` → `Player.levelup_pushback`(자기 중심 `levelup_push_radius` 안 적 `apply_knockback`(약하게 `levelup_push_speed`) + `_spawn_pushback_ring` 청백 링) | `PlayerData` Level-up Pushback 그룹 · 피해 없음(넉백만) · 보스 등 `apply_knockback` 없는 적은 스킵 |
| 카드 풀 언락 (M5) | `scenes/ui/CardUnlock.{gd,tscn}` + `UpgradeSystem.all_cards()`(CSV 로드) `initial`/`unlock_cost` | `MetaProgressionSystem.is_card_unlocked` / `unlock_card` |
| ⭐ 레벨업 효과 (CSV 테이블) | **`data/upgrades.csv`**(로우 데이터 — id/name/desc/value/initial/unlock_cost) → `UpgradeSystem._load_csv`→`CARDS`/`draw`/`apply`(value 로 효과). 효과: move_speed/max_hp(직접) · slash_range/charge_speed/dodge/overheat_reduce/heat_delay_reduce(Player 런타임 보너스 = 런마다 리셋) | 비도 효과 삭제 · `Player.slash_size_mult`(_fire_slash ext)·`charge_speed_bonus`(_update_aim)·`dodge_chance`(take_hit)·`overheat_dur_reduce`(_enter_overheat)·`heat_delay_reduce`(_update_heat) |
| 혼 적립 (클리어/사망) | `Main._on_boss_defeated` / `_on_player_died` → `MetaProgressionSystem.record_*_reward` | `stats.souls` → 결과 화면 |
| ⭐ 보스 = 멧돼지 돌진 (근접 패턴 삭제) | `Boss.gd` 상태머신 `BState`(CHASE→WINDUP→CHARGE→RECOVER): 추적 → `charge_range` 안+쿨 차면 `_begin_windup`(돌진 레인 데칼 `ChargeTelegraph` 생성) → `_state_windup`(데칼이 `charge_windup`1s 동안 PC 호밍 → `lock()` 고정) → `_state_charge`(`_charge_dir`로 `charge_speed` 직진, `charge_distance` 소진까지, 근접 시 1회 `charge_damage`) → `_state_recover`(`charge_recover` 정지) | `scenes/effects/ChargeTelegraph.{gd,tscn}`(set_lane/lock) · `Boss.tscn`에 주입 · 패리/fan/시그널 코드·export 는 미사용 잔존(추후 정리) · take_hit=피해만 |
| 보스 돌진 파라미터 (데이터 드리블) | `data/enemy.csv` 보스행(201/202/203) charge_range/windup/speed/distance/damage/recover/cooldown/width → `CombatData._apply_boss` | 멧돼지 초벌 밸런스: b1(22/1.0/18/16) b2(24/0.9/20/18) b3(26/0.8/22/20·dmg3) |
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
  - **M9 발도/표식/납도 연쇄**: `BoonSystem`(static loader)·`BoonExecutor`(Player 자식 단일 인스턴스)·`TriggerBus`(autoload 단일)는 **Main↔Testplay 미러 불필요**(EliteEffectService 패턴 — 양쪽이 같은 단일 인스턴스에 위임). 단 `Main`/`Testplay` 의 `_selected_cards` 에 `pool` 키를 담는 `_on_upgrade_card_selected` 부분은 **양쪽 동일 유지**(카드 dict 형상 미러).

## 코딩 컨벤션

- `class_name X` 신규 추가 시: 헤드리스에서 캐시 미갱신 → 다른 스크립트에서 참조 시 `const _XScript := preload("res://...")` + 덕타이핑 (`obj.call("method")`). 자세히 → `godot-runtime-verify` 스킬.
- 새 `.tscn` / `.tres` 헤더에 `uid="uid://..."` 직접 적지 말 것 (Unrecognized UID 오류). 에디터가 생성하게 비워둔다.
- 시그널 핸들러는 `if not is_inside_tree(): return` 가드로 시작 (씬 종료 / 패키지 셧다운 시 NPE 방지).
- 적/이펙트는 group 기반으로 식별: `"enemies"`, `"elites"`, `"boss"`, `"melee_enemies"`, `"player"`, `"camera_rig"`.
- 데이터 튜닝은 `.tres` 리소스 우선. 코드 상수는 시스템 동작 자체에만.
- 한 `.gd` 파일이 **600줄**을 넘으면 `refactor-pass` 스킬 권유 신호 (휴리스틱).
- ⚠ **레벨업/카드 효과는 Player 의 런타임 보너스 변수**(런마다 1.0/0 으로 리셋, 예: `move_speed_mult`/`exp_magnet_mult`/`slash_size_mult`)로 구현하고 **공유 `PlayerData.tres`(또는 어떤 `.tres`)도 직접 변형 금지**. Godot 가 리소스를 캐시하므로 `player.data.X *= …` 같은 변형은 **런 간 값이 영구 누적**된다(질풍 카드 이속 누적 버그 사례). HP 처럼 인스턴스(`HealthComponent.max_hp`)에 적용하는 건 OK.
- **Resource `@export` 제거 시 동반 정리**: 그 export 를 `.tscn`/`.tres` 가 set 하고 있으면 거기서도 그 줄을 제거(안 하면 고아 속성 → 로드 경고)하고, 값을 bridge 하는 코드(`CombatData._apply_*` 등 `obj.export = …`)도 함께 제거. 안 하면 런타임에 없는 프로퍼티 set → 에러. 죽은 코드 판정 grep 은 **문자열 `"name"`(call/has_method/connect/get) + `.tscn` 프로퍼티**까지 확인.
- **기능 개발/데이터 변경 시 밸런스 툴(`addons/balance_tool`) 점검·갱신**: PC=`balance_dock.gd` `PC_FIELDS`, 몬스터=`MON_FIELDS` 에 `[필드명, 한글라벨, 한글툴팁, 타입]` 줄 추가/수정. 새 `@export` 는 노출하고, 의미 바뀐 레거시 라벨/툴팁은 갱신(예: HP "칸"→자연수). PC 탭은 `"@"` 섹션 마커 행으로 그룹 구분(이동/일섬/열관리/회피/근접/패리/피격·자원/카메라).

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

### ⚠ 구현 진행 시 무조건 갱신 (스펙 2DB — 별도 페이지)
기능/규칙/툴을 구현·변경하면 **반드시** 아래 두 스펙 DB도 갱신한다(기존 항목=update-page, 신규=create-pages · notion-personal rlaek78 · 방법론은 `notion-access` 스킬).
- **게임 규칙/스펙 구현·변경** → "구현된 스펙 리스트" DB
  - 페이지 https://app.notion.com/p/386c19a9cda38068ac9dca073a6afa4e (구현 내용 최신화)
  - data_source `386c19a9-cda3-8094-816a-000b55434f49` · 컬럼: 이름·카테고리(전투·자원/적/웨이브·스폰/진행·성장/모드·옵션/HUD·연출)·요약·판정(유지/검토/제거후보, 빈칸=사용자 선별)
- **개발/밸런싱 툴 구현·변경** → "구현된 툴 스펙 리스트" DB (+ 행 본문에 매뉴얼 갱신)
  - 페이지 https://app.notion.com/p/386c19a9cda380019032df3b29997242 (툴 매뉴얼 최신화)
  - data_source `5e865387-eb9b-41d9-ac5e-bcd533b8bc77` · 컬럼: 이름·구분(에디터 플러그인/인게임 패널/CLI/자동로드)·진입 경로·요약 · 본문=매뉴얼(진입/사용법/메모)
- 시스템 로직 자체가 아니라 "무엇이 구현됐는지"를 기록(선별·매뉴얼 용도). 의미 바뀐 기존 행은 새로 만들지 말고 갱신.

## 외부 문서

- 게임 디자인 / 로드맵 / 마일스톤 체크리스트 → [docs/GAMEDESIGN.md](docs/GAMEDESIGN.md)
- 비전 & 타이밍 액션 인터랙티브 대시보드 → [docs/VISION.html](docs/VISION.html)
- 사운드 자산 배치 가이드 (M7) → [docs/AUDIO_GUIDE.md](docs/AUDIO_GUIDE.md)
- 상세 설계 / 데이터 흐름 / 책임 분리 / 확장 시나리오 → [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- 리팩토링 절차 → [.claude/skills/refactor-pass/SKILL.md](.claude/skills/refactor-pass/SKILL.md)
