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
scenes/player/      — Player (근접 부채꼴 스윙 LB + 일섬 RB + SPACE 회피) · PlayerSprite (PC 도트 애니 — Adventurer 8프레임 4방향 idle/run/attack2)
scenes/enemies/     — MeleeEnemy(추적 근접) / Leaper(베리에이션2·리프전용, MeleeEnemy.gd behavior=LEAPER) / RangedEnemy / EliteEnemy / Boss
scenes/effects/     — FanTelegraph / LeapTelegraph (근접 리프 빨간 원형 데칼) / AimLaser / BossSignal / CircularSlash / ExplosionBurst
scenes/attack/      — SlashAttack (일섬 trail) / MeleeSwing (근접 기본공격 부채 VFX)
scenes/ui/          — ExpBar / HpBar3D / DodgeStackBar3D(회피 스택) / HeatBar3D(즉발 일섬 열관리, 모드2만) / LevelUpScreen / ChapterClearScreen / AimArrow / AimCursor (마우스 십자선)
scripts/managers/   — ExpSystem / UpgradeSystem / WaveManager / InfiniteGround / SaveSystem / MetaProgressionSystem / ZenSystem / SoundManager (Autoload) / EliteEffectService · BulletTimeService (Main+Testplay 공유) / GameConfig (시작 모드 플래그)
scripts/resources/  — PlayerData / EnemyData / CharacterVisuals / WaveCurve / MetaPassive (튜닝용 Resource)
scripts/components/ — HealthComponent / SpriteRig / MonsterCollision / Knockback (스무스 넉백)
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
| ⭐ 일섬 돌진속도/거리/범위/오버차지 (기획 테이블) | `PlayerData` `slash_dash_speed`(m/s) · `instant_slash_distance`(m, 모드2 풀차지 사거리) · `instant_overcharge_hold`(s, 모드2 최대차지 유지→자동발사) · `slash_hit_extents`(Vec3 x=폭/y=높이/z=길이가산) | `Player._fire_slash`(대시시간=거리÷속도 `_dash_dur`) · `SlashAttack.configure(start,end,extents)` BoxShape 판정 |
| PC 이동/회피/i-frame | `scenes/player/Player.gd` | `PlayerData` |
| 회피 2스택 (SPACE) + 한칸씩 충전 + 머리위 UI | `Player.gd` (`_evade_stacks` 소비 · `_physics_process` charge 리필 한 칸씩) · `scenes/ui/DodgeStackBar3D.gd`(머리 위 2칸) | `pc.csv` evade_max_stacks / evade_refill_time(칸당) / evade_distance · 입력맵 `dash`=SPACE |
| 근접 2종 분리 (추적 vs 리프) | `MeleeEnemy.behavior` (CHASER=부채만 / LEAPER=리프만) · `Leaper.tscn`(behavior=1·보라 `leaper_visuals.tres`) | 슬래시는 잡몹/리퍼 한방(`take_hit` 치명타) |
| 잡몹 군집 분리 (겹침 방지, Boid) | `MeleeEnemy._separation_vector` + 추격 블렌딩 · 정적 `_sep_list`(프레임당 1회 `melee_enemies` 수집 → 할당 폭증 방지, O(n²) 계산) | `enemy.csv` 근접(101)/리퍼(104) `separation_radius`/`weight` · 엘리트는 `_compute_separation` 별도 · 확장: 공간 그리드로 이웃질의 교체 |
| ⭐ 리프어택 (삐슝→점프→데칼 100%→슬램+쉐이크) | `MeleeEnemy._begin_leap`(토큰 획득·삐슝 빨간 플래시) → `_update_leap`(PRE 사전경고 `leap_pre_time` → AIR 상승·체공·순식간 낙하) · `_spawn_leap_decal`(점프 시작 시 등장, windup=leap_duration 동안 중심→바깥 100% 차오름) · `LeapTelegraph._slam`(착지=100% → 데미지 + 카메라 쉐이크 `shake_amp/dur`) | **동시 3마리 캡**(`Main._alive_leaper_count`<3, `leapers` 그룹) · **그룹 AI 토큰**(`MeleeEnemy._leap_attacker` static — 한 마리만 공격, 나머지 `_leap_standoff_move` 뒷걸음/대기 추적) · **가시성 게이트**(`_is_on_screen` 카메라 절두체 = PC 시야일 때만 발동) · `enemy.csv` leaper(104) leap_chance/radius/damage · 스폰 chapters `leaper_ratio`/`leaper_start_time` |
| ⭐ 기본 공격 (근접 부채꼴 스윙, LB) | `Player._update_melee` / `_do_melee_swing` (커서 방향 전방 부채꼴 → 적 HealthComponent.take_damage) + `scenes/attack/MeleeSwing.gd`(VFX) | `pc.csv` melee_range/angle/cooldown/damage · 이동+공격 동시 · 항상 커서 방향(좌우 플립) · 비도(원거리) 전부 제거 |
| PC HP / 피격 / 사망 | `Player.gd` + `scripts/components/HealthComponent.gd` | — |
| ⭐ PC 도트 스프라이트 (애니) | `scenes/player/PlayerSprite.gd`(Sprite3D + hframes 8) — `market/Adventurer 2D Top-Down` 에셋 4방향(down/left/right/up) idle/run/attack2, 96×80×8 스트립. `set_facing_vec`(4방향)·`set_state`(WALK=run/ATTACK=attack2 1회)·`flash`/`start_iframe_blink`/`play_death_then_free` = SpriteRig 호환 API | `Player.tscn` "SpriteRig" 노드를 PlayerSprite 로 교체(적은 기존 `scripts/components/SpriteRig.gd` 유지) · 일섬 발사 시 set_state(ATTACK)→대시 중 attack2 재생=일섬 연출 · 알파: transparent+ALPHA_CUT_DISCARD+NEAREST, `.import`=PC.png 설정 복제(compress0/mipmap off/detect_3d compress_to=0) |
| HP 칸 UI (좌상단 빨간 사각형) | `Main.gd` `_build_hud`(`_hp_box`) + `_refresh_hp_cells` (`get_hp`/`get_max_hp`, `_HP_FULL/_HP_EMPTY`) · `Testplay.gd` 미러 | 머리 위 연속바는 `scenes/ui/HpBar3D.gd` (병행) |
| ⭐ 피격 연출 (넉백 / 1s 무적+깜빡임 / 일섬 후 회복유예) | `Player.take_hit` (`_iframe_t`=`data.hit_iframe`(pc.csv **1.0**) · `is_invincible`=DASHING/EVADING/iframe/**`_slash_grace_t`** · `start_iframe_blink` 무적 동안 플래시 머티리얼 깜빡) · 일섬 착지 시 `_slash_grace_t`=`slash_post_grace`(0.4s)=접촉/피탄 즉시피격 방지 | `PlayerSprite.start_iframe_blink` · `pc.csv` hit_iframe · `_update_dash` 종료에서 grace 세팅 |
| 스무스 넉백 (피격 AOE) | `scripts/components/Knockback.gd`(감쇠 슬라이드) — 적이 소유 `apply_knockback(dir,speed)` · `_kb.integrate(self,delta)` | 피격 시 `Player._knockback_nearby_enemies`(`knockback_force`=속도/`knockback_radius`) · ⚠ 비도 제거로 피탄 넉백 없음 |
| ⭐ 몬스터 경직 + 아머 게이지(poise) | `HealthComponent`(`armor_max`/`armor`/`take_damage` 가 데미지만큼 아머 소거 → 0이면 `staggered` + 경직) · 각 적 `_physics_process` `_health.tick_stagger`+`is_staggered`→정지 | `enemy.csv` armor_max(잡몹0/엘리트4/보스6~8)·stagger_duration · 경직 끝 → 아머 재충전 · 사망 시 `clear_stagger`(경직보다 사망 우선) |
| HP+아머 한 줄 바 (머리 위) | `scenes/ui/HpBar3D.gd` — 빨강 HP(좌) + 파랑 아머(우)를 한 바에 zone 분할(armor_max>0 일 때만 파랑 노출) · top_level + 매 프레임 부모 추적 + 카메라 풀빌보드 | **모든 적**이 `_ready` 에서 `_HpBar3DScene` 코드 인스턴스 + `attach_health` — 잡몹/리퍼/원거리=`follow_offset` y1.55, 엘리트 1.7, 보스 2.7. PC=아머0 전폭 HP |
| 적 발사체 격추 (PC 공격에 소멸) | `Arrow`(group `enemy_projectiles` + `take_hit`→free) · `Player._do_melee_swing` 부채 안 격추 · `SlashAttack._try_kill` 발사체 우선 격추(킬 카운트 제외) | 발사체 HP 없이 한 방 |
| ⭐ 적 발사체 반사 (일섬으로 되받아치기) | `SlashAttack._try_kill` 발사체 → `Arrow.reflect()`(역방향 + 팩션 PlayerAttack`1<<3`/mask `World+Enemy` → **PC 안 맞음** + `enemy_projectiles` 그룹 이탈 + 청록 + 속도×1.5) · **비관통**(`_on_hit` `_reflected` 분기 = 첫 적 명중 시 소멸) | reflect 없으면 기존 격추 폴백 · "저스트 타이밍"=슬래시로 탄을 잡는 행위 자체 |
| ⭐ ESC 웨이브 에디터 (비율 프리셋) | `Main._unhandled_input`(ESC→`_toggle_dev_overlay`) + `_build_dev_overlay`(버튼 패널) · 버튼=`_set_wave_preset`(`GameConfig.wave_preset` 저장 후 **`reload_current_scene`=게임 초기화**) → 리로드된 Main 이 `_apply_wave_preset`(wave_mgr 생성 직후+오버레이) 로 적용 · `_request_spawn_preset` 비율 스폰(0=곡선/1=근90·원5·엘5/2=원90·근5·엘5, +엘리트 랜덤1~4) | 원거리 프리셋=`WaveManager.target_mult`0.1·`min_target`3 (인원 **1/10**·바닥3) · `GameConfig.wave_preset` static = 리로드 너머 유지 · UI 클릭은 `_is_pointer_over_ui` 가드로 일섬 안 됨 · **옵션 토글**(`_make_toggle_button`→`GameConfig.charge_zoom_enabled`/`contact_damage_enabled`, 리로드 없이 즉시): LB 차징 줌아웃(`HD2DCamera.set_charge_zoom`→`_charge_zoom` move_toward `charge_zoom_max`) / 몬스터 충돌 피해(`Player._check_contact_damage` 게이트) |
| ⭐ 원거리 사격 텔레그래프 + 동시 사격 캡 | `AimLaser`(흰 더미 라인 + **중심→바깥** 빨강 fill 0~100% → 100% 흰 플래시 → 발사) · `RangedEnemy._can_fire_now`(활성 `aim_lasers` < `ranged_enemies`수×`_FIRE_FRACTION`(0.25) → **~25%만 동시 사격**, 레이저=슬롯이라 자연 회전) | `AimLaser.lock_duration`/`flash_duration` · 가시성 게이트(PC 화면 내) |
| ⭐ 일섬 후 가시성 (카메라 줌펀치) | `Player._fire_slash`→`HD2DCamera.zoom_punch`(`slash_cam_zoom_scale`1.18/`time`0.45) · 로컬 오프셋 줌아웃→복귀로 착지 지점 적을 넓게 노출 | `HD2DCamera._update_cam_local`(줌+쉐이크 통합) |
| 비대칭 충돌 (PC가 군중 헤집기) | PC `collision_mask`=World only(불가침) · 적은 World+Player(겹치면 스스로 빠져나감=PC가 밀침) · ⭐ `Boss._eject_overlapping_player` **재도입**(PC가 보스 박스에 끼면 작은축으로 밖 푸시, 대시 중 스킵 · 경계 `_boss_half_xz`=콜리전박스×scale 런타임 산출 → 스케일 변경 자동 추종) | 잡몹은 한 방향 디펜트레이션, 보스만 eject(큰 박스 일섬 관통 실패 끼임 해소) · 보스 노드 스케일 0.6(콜리전 유지) — 비주얼은 해골 스프라이트로 1.5× 차등(별도 행) · 데미지는 부채/슬래시/텔레그래프 판정 |
| ⭐ 타격감 (스윙 카메라쉐이크 + 적중 히트스탑) | `Player._do_melee_swing` 끝 → `camera_rig.shake`(매 스윙) + `hitstop`(적중 시) · `HD2DCamera.hitstop`(`Engine.time_scale` 잠깐↓, ignore_time_scale 타이머로 복구, `_exit_tree` 안전망) | `pc.csv` melee_shake_amp/dur · melee_hitstop_scale/dur · BulletTime(per-enemy)과 독립 |
| 회피 스택 UI (머리 위 2칸) | `scenes/ui/DodgeStackBar3D.gd` (`Player.get_evade_stacks`/`get_max_evade_stacks`/`evade_refill_frac` 덕타이핑, 충전칸은 아래→위 부분채움) | `Player.tscn` 자식 → Main/Testplay 자동 반영 · HP바 위(y≈2.16) |
| 마우스 십자선 (에임 커서) | `scenes/ui/AimCursor.gd` (`_draw` 원+십자, OS커서 숨김/복원, process ALWAYS) | `Main.tscn`/`Testplay.tscn` 인스턴스 (OutGame 제외) |
| 일섬(RMB) + 게이지 (100% 게이트 / 사용 후 0) | `Player.gd` (`_check_attack_start` 게이트 · `_fire_slash` 리셋 · `add_slash_gauge` / `gain_gauge_on_*`) | 입력맵 `slash`(RMB) · `player_data.tres` (Slash Gauge 그룹) |
| 일섬 게이지 획득 배선 | 처치/젬 → `Main.gd`+`Testplay.gd` (`gain_gauge_on_kill`/`gain_gauge_on_gem`) · 저스트회피 → `Player.take_hit` | `slash_gauge_on_kill/gem/perfect_dodge` |
| 일섬 게이지바 HUD (하단 중앙) | `Main.gd` `_build_slash_gauge`/`_refresh_slash_gauge` (+`Testplay.gd` 미러) | `slash_gauge_frac()`/`is_slash_ready()` |
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
| ⭐ 게임 시작 2 (이동 차징 일섬 모드) | `OutGame._on_start2_pressed`(`GameConfig.instant_slash_mode=true`) → `Player._instant_slash` 분기 | `scripts/managers/GameConfig.gd`(static, preload) · `Player._check_instant_slash`(LB→`State.AIMING` 차징 시작) · `State.AIMING` 모드2 `_handle_move`(이동하며 차징, AimArrow가 PC 추적) · `_update_aim` 오버차지 `instant_overcharge_hold`(2s) 후 자동발사(모드1 fizzle 과 달리 발사) · `_check_attack_release`(LB 떼면 발사) · 거리 `lerp(min, instant_slash_distance, frac)` · 근접 스윙 + 일섬 게이지(처치/젬/저스트회피·HUD) 전체 비활성(`add_slash_gauge` no-op) · **NPC 접촉 피해**(`_check_contact_damage` + PC `collision_layer=0`=서로 안 밀림, `contact_damage`/`contact_radius`, take_hit `do_knockback=false`) · 카메라 일섬 동반 이동(`slash_cam_follow_time/mult` → `HD2DCamera.follow_boost`, 대시 동안 추적 밀착 = 공격과 함께 이동), 회피 공통 |
| ⭐ 열관리(Heat) — 즉발 일섬 모드 (럼블식) | `Player._update_heat`/`_add_heat`/`_enter_overheat` (일섬마다 +10%, 직전 7s내 연타 ×1.5 → 7발째 100%, 100%→5s 탈진[이동50%↓ + 발사봉인]→열0, 4s 유예 후 `exp(-k·dt)` 지수감소) · 머리 위 `scenes/ui/HeatBar3D.gd` — **5칸 스택**(연속 게이지 아님, 켜진 칸=`ceil(get_heat_frac×5)`, 칸색 주황→빨강 보간, 탈진 시 전부 회색) | `PlayerData` Heat 그룹(gain_base/combo_window·mult/overheat_*/decay_*) · `_instant_slash`(모드2)만 동작 · getter `is_instant_slash_mode`/`get_heat_frac`/`is_overheated` |
| ⭐ 마취 비도 (게임 시작2 RMB · 하데스 캐스트식 1/1) | `Player._check_tranq`/`_fire_tranq`(우클릭 → `_tranq_cd`=`tranq_cooldown` · `_aim_dir`로 `tranq_range` 지점에 곡사) + `scenes/attack/TranqKunai.gd`(포물선 `sin(k·π)·arc_height` → 착탄 `_land`→`_apply_stun`: "enemies"/"boss" 범위 내 `HealthComponent.force_stagger(3s)` + 청록 AOE 원반) | 데이터 `PlayerData` Tranq 그룹(stun_duration/cooldown/radius/range/arc_height/travel_time) · 스턴=`HealthComponent.force_stagger`(아머 무관, 모든 적 `is_staggered`로 정지 재사용) · ⚠ configure 는 add_child 전 호출이라 `global_position`은 `_ready`에서 설정 |
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
