# ProjectFBDC — Architecture

이 문서는 ProjectFBDC의 시스템 설계, 책임 분리, 데이터 흐름, 확장 절차의 **단일 출처(single source of truth)** 다. 매 대화에 자동 로드되지 않으므로 필요한 때 명시적으로 읽어야 한다 (`CLAUDE.md`가 인덱스로 가리킨다).

---

## 1. 시스템 다이어그램

### 1.1 씬 구조 (Main / Testplay)

```
Main.tscn (게임 본편)                  Testplay.tscn (튜닝/디버그)
├─ Player                              ├─ Player
├─ HD2DCamera                          ├─ HD2DCamera
├─ Enemies (Node3D 컨테이너)            ├─ Enemies (Node3D 컨테이너)
├─ ExpSystem                           ├─ ExpSystem
├─ WaveManager        ◄── 차이점 1     ├─ TestplayPanel (우측 버튼)
├─ InfiniteGround                      ├─ InfiniteGround
├─ WorldEnvironment + Sun              ├─ WorldEnvironment + Sun
├─ ExpBar (CanvasLayer)                ├─ ExpBar (CanvasLayer)
├─ HUD (Kills / 안내)                   └─ TestplayHelp (안내)
└─ (이벤트 시 ChapterClearScreen)
```

**핵심 차이점**: Testplay는 자동 스폰 (WaveManager + chapter beat) 만 빠지고 그 자리에 버튼 패널이 들어간다. EXP / 레벨업 / 엘리트 효과 / 불릿타임은 양쪽 동일.

### 1.2 매니저-노드 의존 관계

```
[Main.gd / Testplay.gd]  (씬 부트스트랩 + dispatcher)
       │
       ├─ ExpSystem ──────► leveled_up signal ──► LevelUpScreen ──► UpgradeSystem.apply
       │
       ├─ UpgradeSystem (RefCounted static class — 인스턴스 X)
       │
       ├─ WaveManager (Main 전용)
       │     ├─ request_spawn_cb  ──► Main._request_spawn
       │     ├─ count_alive_cb    ──► Main._count_alive_mobs
       │     ├─ spawn_elites_cb   ──► Main._chapter_spawn_elites
       │     └─ spawn_boss_cb     ──► Main._chapter_spawn_boss
       │
       ├─ InfiniteGround ◄── target = Player
       │
       └─ HD2DCamera ◄── target = Player
```

`WaveManager`는 콜백 4개로 `Main`과 약결합. `UpgradeSystem`은 인스턴스 없는 정적 클래스 (RefCounted) — `draw(n)` / `apply(id, player, exp_system)` 두 함수만.

### 1.3 효과(Effect) 노드의 수명

`scenes/effects/` 의 모든 효과는 **spawn-and-forget**: 부모를 attacker로 잡지 않고 `get_tree().current_scene`에 붙인다. 이유는 attacker가 wind-up 중 죽거나 이동해도 효과가 보존되어야 하기 때문 ([FanTelegraph.gd:11~26](../scenes/effects/FanTelegraph.gd) 주석 참고).

---

## 2. 데이터 흐름

### 2.1 적 사망 → EXP → 레벨업

```
Enemy.take_hit
  → HealthComponent.take_damage
  → HealthComponent.died signal
  → Enemy._on_died
  → queue_free (Tween 후)
  → tree_exited signal
  → Main._on_enemy_freed_with_ref (bind된 enemy ref)
  → Main.award_exp_for_kill
       └─ 분기:
           · EliteEnemy + effect_type 1/2/3 → 3/5/10 EXP
           · _lv >= 2 (LV2 melee)            → 2 EXP
           · 그 외                          → 1 EXP
  → ExpSystem.add_exp(N)
       └─ current_exp += N * gain_multiplier
       └─ while current_exp >= threshold:
              level += 1; leveled_up.emit(level)
  → Main._on_leveled_up
       → tree.paused = true
       → LevelUpScreen 인스턴스
       → UpgradeSystem.draw(3) → 카드 3장
       → screen.card_selected signal (one-shot)
  → Main._on_upgrade_card_selected
       → UpgradeSystem.apply(card_id, player, exp_system)
       → tree.paused = false
```

### 2.2 보스 사망 → 챕터 클리어 + SaveSystem

```
Boss.take_hit → take_damage → died → _on_died → boss_defeated.emit()
  → Main._on_boss_defeated
       → elapsed = (now - _chapter_start_msec) / 1000
       → stats = {time, kills, level}
       → beat = SaveSystem.record_clear(chapter_id, time, kills, level)
            └─ best_time/kills/level 갱신, clear_count++
       → best = SaveSystem.best_for(chapter_id)
       → tree.paused = true
       → ChapterClearScreen 인스턴스 + configure(stats, best, beat)
            └─ stat 행마다 beat[key]가 true면 "NEW!" 배지
  → ChapterClearScreen._on_next_pressed
       → tree.reload_current_scene  (M2에 다음 챕터 라우팅 도입)
```

### 2.3 엘리트 사망 → 특수 페이로드

```
EliteEnemy._on_died
  → 현재 씬에 trigger_elite_effect(effect_type, pos) 호출
       (Main 또는 Testplay 둘 다 이 메서드를 갖는다 — 동기화 규칙)
  → 분기:
      type 1 (빨강) → ExplosionBurst 즉시
      type 2 (초록) → _queue_circular_slash_after_slash
                       └─ PC가 DASHING이면 slash_finished 대기 후 CircularSlash
                       └─ 아니면 즉시 CircularSlash
      type 3 (파랑) → _start_bullettime(3.0s)
                       └─ 모든 적 + 화살의 time_scale_mult = 0.25
                       └─ Environment.adjustment_saturation 0 → 3s → 1.12
```

### 2.4 보스 패리 윈도우 + ⏱ 퍼펙트 패리 사슬 (M2/M6)

```
Boss._begin_telegraph
  → 단일 randf() → 다중 컬러 분포:
       WHITE  (Boss2: 0.2, Boss3: 0.15) — RED 의미, 시각만 흰색
       PURPLE (Boss3: 0.2)              — RED 의미, 시각만 보라 (광역)
       GREEN  (Boss3: 0.1)              — RED 의미, 시각만 녹색 (다단)
       나머지 확률 mass → YELLOW/RED 표준 split (parry_yellow_ratio)
  → _color_override (0=none/1=W/2=P/3=G) 가 _signal_color_for 분기
  → BossSignal (머리 위 색 아이콘) 스폰
  → FanTelegraph (지면 부채꼴) 스폰
  → YELLOW일 때만:
        timer(telegraph_time - 0.2s) → _open_parry_window  ── _parry_open = true
        timer(window_len)            → _close_parry_window
  → 0.5s 후 sweep 시점:
        FanTelegraph._try_damage_player_now (point-check)
        OR (PC가 슬래시 trail로 보스 hit) → Boss.take_hit(amount=1)
             └─ _parry_open && YELLOW → _on_parried
                  · queue_free(active_telegraph) → 휘두름 시각 캔슬
                  · BossSignal.cancel()
                  · camera_rig.shake_curve(0.5, 0.3) — 강한 ease-out
                  · _blocked = true, 1s 후 _end_block
                  · ⏱ player.parry_boost_until_msec = now + 1000
                       (다음 1초 안 다음 보스 슬래시 → dmg×3)
```

⏱ 보상 사슬은 `SlashAttack._resolve_boss_damage`가 해석한다 — boss 그룹
대상일 때만 PC의 `parry_boost_until_msec`를 읽어 `Time.get_ticks_msec()`
와 비교, 윈도우 안이면 `take_hit(3)`을 호출. 일반 적은 항상 1-shot
이라 분기 없이 argless `take_hit()` 그대로.

---

### 2.7 메타 진행 흐름 (M4)

```
부팅 (project.godot main_scene = OutGame.tscn)
  → OutGame._ready → 혼 잔액 / 챕터 best record 표시
       ├─ "게임 시작" → change_scene_to_file(Main.tscn)
       ├─ "영구강화" → change_scene_to_file(MetaMenu.tscn)
       │      └─ MetaMenu 패시브 카드 7장 + 강화 버튼
       │             → MetaProgressionSystem.upgrade(id)
       │                  · 혼 차감 + 단계+1 + user://meta.cfg 저장
       │                  · MetaMenu._refresh로 즉시 갱신
       └─ "종료" → tree.quit

Main 진입 (OutGame Start 또는 F6 Testplay X)
  → Main._build_chapter_systems 끝에 apply_to(player, exp_system)
       └─ 각 passive_level > 0 인 항목을:
              hp / move_speed / slash_width / exp_gain / evade_cooldown
              / iframe_extra → 직접 mutate
              free_card → M4 후속 (LevelUpScreen race 회피 필요)

Run end → 혼 적립
  · Main._on_boss_defeated → record_clear_reward = 10 + ch*5 + lv*2 + kills/5
  · Main._on_player_died    → record_death_reward = kills/10 + max(lv-1, 0)
                              (최소 1)
  · 두 경우 모두 stats["souls"] 로 ChapterClearScreen / GameOverScreen
    에 넘겨 "+N 혼" stat row 표시
  · "메뉴로" 버튼 → change_scene_to_file(OutGame.tscn)
```

### 2.6 메커니즘 카드 효과 흐름 (M3)

```
레벨업 → LevelUpScreen → UpgradeSystem.apply(card_id, player, exp_system)
  ├─ "multistrike"    → player.has_multistrike = true
  ├─ "echo"           → player.has_echo = true
  ├─ "vampire"        → player.has_vampire = true · vampire_chance = 0.15
  ├─ "phoenix"        → player.has_phoenix = true
  ├─ "counter_step"   → player.has_counter_step = true
  └─ "parry_master"   → player.has_parry_master = true
                       + 현재 살아있는 모든 boss 그룹 노드에 즉시
                         parry_window +0.05/+0.05, parry_boost_dmg +1
                       + Boss._ready가 미래 보스에 자동 적용

런타임 트리거:
  · Player._fire_slash 끝 → has_multistrike → 0.18s 후 _fire_multistrike_followup
       (shorter trail, no dash, _is_multistrike_followup latch로 재귀 방지)
  · Player.slash_finished → Main._on_player_slash_finished → has_echo → 0.3s 후 CircularSlash at PC
  · Main.award_exp_for_kill → _try_vampire_heal → has_vampire ? roll vampire_chance → HealthComponent.heal(1)
  · Player._on_died → has_phoenix && not _phoenix_used → hp = max_hp + 2s i-frame + return (skip 죽음)
  · Boss._on_parried 끝 → player.on_parry_success() → has_counter_step → counter_step_until_msec = now + 1000
       └─ Player._handle_move가 그 시간 동안 speed_mult 1.5x
  · Parry Master는 카드 픽 시점에 Boss export 값을 직접 mutate — 런타임 hook 불필요
```

### 2.12 ⏱ M3 후속 타이밍 메커닉 (2026-06-04)

```
퍼펙트 닷지 (base, 카드 불요)
  Player._check_evade_start → _perfect_dodge_fired = false (re-arm)
  Player.take_hit (공격 도달):
    if EVADING and _evade_elapsed <= 0.12 and not fired:
      → perfect_dodge.emit()  → Main._on_player_perfect_dodge → BulletTimeService.start(0.5)
      → ZenSystem.add(1)  +  SFX "perfect_dodge"  +  camera nudge
    그 후 is_invincible() early-return (i-frame이 데미지 차단)

차징 그레이드 / Overcharge (base)
  Player._update_aim:
    _charge_t >= max → _overcharge_t += delta
    _overcharge_t >= OVERCHARGE_GRACE(0.45) → _fizzle_charge()
      → 슬래시 무산 + _cooldown_t = 1.0 (전 차징 봉인) + SFX "fizzle" + shake
  Perfect grade (charge_frac >= 0.9)는 _fire_slash에서 Zen +1 (기존)

잡몹 텔레그래프 캔슬 (base)
  MeleeEnemy._begin_telegraph → _active_telegraph = fan
  MeleeEnemy.take_hit (wind-up 중):
    _attacking and _active_telegraph valid → FanTelegraph.cancel()
      → _consumed=true (sweep 데미지 무효) + 빠른 fade
    → 예방적 슬래시가 보스/소울류처럼 "윈드업 끊기" 보상
```

### 2.9 ⏱ Zen 미터 + 풀폭 슬래시 (M4 후속, 2026-06-04 도입)

```
ZenSystem (Main / Testplay 자식)
  · zen: int (max 5)  ·  burst_armed: bool
  · add(amount): perfect 입력 시 카운트 + zen_changed.emit
       퍼펙트 차징 (>=0.9 charge_frac) → Player._fire_slash에서 +1
       on_parry_success                 → Player.on_parry_success 에서 +1
  · 가득 차면 → burst_armed = true + player.has_zen_burst = true
       zen_full.emit  ·  HUD label "⚡ ZEN BURST READY ⚡"
  · consume_burst(): 다음 슬래시가 호출 → zen 0 리셋 + 플래그 클리어
  · drain_on_hit():  피격 시 zen 반감 (burst armed면 보존)

Player._fire_slash
  → burst_active = has_zen_burst (스냅샷)
  → burst 시: range = max × 1.5, width = base × 3
              ZenSystem.consume_burst (즉시 클리어)
  → _spawn_slash_attack(start, end, width, burst=true)
       └─ SlashAttack.set_meta("zen_burst", true)
            └─ SlashAttack._resolve_boss_damage → 5 반환 (parry 3, 일반 1 위)
```

### 2.10 Boss post-M6 진짜 메커닉 (2026-06-04)

```
Boss._begin_telegraph
  → _color_override 결정 (W=1 / P=2 / G=3)
  → 분기 mutate:
       1 (WHITE 잡기): dmg_now = attack_damage × 2 (단일 강타)
       2 (PURPLE 광역): fan_radius × 1.5, fan_angle × 1.3
       3 (GREEN 다단): 첫 fan은 표준, 0.35s 후 followup sweep
  → FanTelegraph.configure(pos, dir, radius_now, angle_now, dmg_now, ...)
  → GREEN: create_timer(...).timeout.connect(_spawn_green_followup.bind(pos, dir))
       └─ _spawn_green_followup: 같은 위치/방향에 두 번째 fan
            (telegraph_time × 0.5 — 빠른 연쇄)
```

### 2.11 사운드 (M7 인프라, 2026-06-04)

```
project.godot [autoload] SoundManager
  → /root/SoundManager (Node)
  · play_sfx(name): res://audio/sfx/<name>.ogg → AudioStreamPlayer 풀(6) 라운드로빈
  · play_bgm(name): res://audio/bgm/<name>.ogg → 전용 player + 크로스페이드 (same-stem no-op)
  · ResourceLoader.exists로 가드 — .ogg 미배치는 silent skip
  · 캐시 (sfx_cache / bgm_cache) — 히트도 미스도 캐시

호출 지점 (현재):
  · Player._fire_slash → play_sfx("slash" 또는 "burst_slash")
  · Player.take_hit    → play_sfx("hit" 또는 "shield")
  · Player.on_parry_success → play_sfx("parry")
  (확장 예정: ExpSystem.leveled_up, Boss.died, ChapterClear 등)
```

`audio/sfx/*.ogg`, `audio/bgm/*.ogg`는 미배치 — 인프라만 도입, 자산 드롭 시 작동.

### 2.8 챕터별 환경색 (M6)

```
_build_chapter_systems / _advance_chapter 끝
  → _apply_chapter_visuals()
       → ProceduralSkyMaterial.sky_horizon_color / sky_top_color /
         ground_bottom_color / ground_horizon_color
         + env.ambient_light_energy
       · Ch1: 푸름 (0.78/0.85/0.95 horizon · ambient 0.75)
       · Ch2: 노을 (0.92/0.68/0.48 horizon · ambient 0.65)
       · Ch3: 황혼 (0.32/0.25/0.42 horizon · ambient 0.45)
```

WorldEnvironment 자체를 재생성하지 않고 기존 environment의 색만 갱신
하므로 챕터 전환 시 시각 hitch 없음. BGM/사운드 차이는 M7에서.

### 2.5 PC 사망 → GameOver + SaveSystem (M1)

```
Player.take_hit (HP → 0)
  → HealthComponent.take_damage → died.emit
  → Player._on_died
       → died.emit()                       ← Main이 받음
       → SpriteRig.play_death_then_free(self, 0.5)
            └─ 0.5s tween 후 queue_free (시각적 fade)
  → Main._on_player_died (signal handler — Player가 sprite tween 중에 즉시)
       → _game_over_shown 가드 (중복 spawn 방지)
       → SaveSystem.record_death(chapter_id, time, kills, level)
            └─ best_kills / best_level 갱신 (사망 시 best_time은 미기록)
       → SaveSystem.best_for(chapter_id)
       → tree.paused = true
       → GameOverScreen 인스턴스 + configure(stats, best, beat)
            └─ Retry → reload_current_scene
            └─ Quit  → tree.quit
```

**Testplay 분기**: Testplay.gd는 같은 `Player.died` 시그널을 받지만, SaveSystem
호출도 GameOverScreen 표시도 없다 (`_on_player_died_testplay` → 1초 후
자동 reload). 디버그 씬이 best-record를 오염시키지 않기 위한 의도적 차이 —
동기화 규칙에서 명시적으로 빠지는 한 케이스.

### 2.13 ⚔️ M9 발도술 / 표식 '참' / 납도 처치 연쇄 (2026-06)

**한 줄**: 일섬 본체가 적에게 0뎀 '표식(참)'을 누적 → 납도(RB)가 그 표식을 거둬 정산(처형/환금) → 정산 처치가 연쇄를 점화. **주인공 규칙 = 모든 처치는 일섬 본체·납도 정산·연쇄 중 하나로만 일어난다**(자율 FX 는 절대 죽이지 않는다).

**TriggerBus 이벤트 흐름** (`scripts/managers/TriggerBus.gd` = autoload 단일 인스턴스, `BoonExecutor` 가 유일 구독자):

```
일섬 적중 SlashAttack
  → emit ON_SLASH_HIT  ──→ BoonExecutor._on_slash_hit_deepmark (심도=DEEP_MARK: 표식 추가)
  → SlashAttack._apply_slash_mark: slash_mark +1 (0뎀 마커 메타)
       └─ cur<cap → nv==cap 전이 1회 emit ON_MARK_FULL (현재 구독자 없음 — 예약 키)
  → 적 사망 시 emit ON_KILL_via_Slash ──→ _on_kill_via_slash_charge (충전류 관통 처형 후속)

납도(RB) Player._do_sheathe
  → emit ON_SHEATHE ──→ BoonExecutor._on_sheathe
       → 1차 패스: sheathe_range 내 표식 적마다 _settle_enemy (정산)
            ├─ 만개(marks==cap) 비보스 → take_damage(9999) 처형
            ├─ 미만/보스          → take_damage(marks × sheathe_dmg × 거합배수 × 취약배수)
            └─ 보스 처형선         → 저HP + 거합 + 만개 조건 충족 시 처형
       → _settle_enemy 가 적을 '죽인' 순간 emit ON_SHEATHE_KILL
            └─ BoonExecutor._on_sheathe_kill (연쇄 점화)
                 ├─ 연환납도(SHEATHE_DOMINO) epicenter 도미노 (카드 보유 시)
                 ├─ baseline 6종 (항상 on·카드 무관·0뎀 셋업/자원)
                 └─ 연쇄 카드 (S7 4종 + S9 4종 …)
       → 처치 1회 이상이면 거합 추격 윈도우 open (다음 RB 즉시 추격 납도)
```

**slash_mark = 0뎀 마커 메타**: `SlashAttack` 이 적중 시 부여(데미지 아님 — 적 HP 불변). 적 머리 위 가시화는 상태 스트립. **cap 단일소스 = `Player.get_mark_cap()`**(발도술 스타일별 숏3/미들5/롱7) — `SlashAttack` 부여 시·`BoonExecutor._mark_cap` 정산 시 같은 게터를 폴링해 분기 없음.

**_settle_enemy 정산 분기**(`BoonExecutor`):
- **만개·비보스** → 9999 처형(즉사).
- **미만 또는 보스** → `marks × sheathe_dmg × 거합배수(IAIDO perfect) × 취약배수`.
- **보스 처형선** → 저HP + 거합 + 만개 동시 충족 시 처형(`_BOSS_EXECUTE_THRESHOLD`).

**★무한연쇄 가드 (correctness 최우선)**: `_on_sheathe_kill` 진입 시 `_in_cascade` 플래그를 세우고, 연쇄 도중 발생하는 ON_SHEATHE_KILL 재진입을 막는다(연쇄가 또 연쇄를 점화 → 무한 루프 차단). 추가로 마릿수·뎁스 cap: `_CASCADE_DEPTH_CAP` / `_CASCADE_KILL_CAP` / `_BASELINE_SPREAD_CAP`. 충전류 관통 처형도 `_in_cascade` 가드로 ON_SHEATHE_KILL 재발을 차단한다.

**cap 단일소스 원칙**: 정산·연쇄가 참조하는 모든 cap(표식 cap·연쇄 cap)은 진입 시 1회 폴링한 단일 값 — 분기마다 재계산하지 않는다(불일치 방지).

**킬소스 계측**(`BoonExecutor.get_kill_source_counts`): 처치를 `slash`(일섬 본체) / `sheathe`(납도 정산) / `cascade`(연쇄) / **`other`** 로 분류해 `ArenaDebug` 가 readout. ★불변식: **`other`(자율 FX) 킬 = 0** — 감속장·취약표식·자원·연출 FX 는 `take_hit` 을 호출하지 않으므로 절대 처치를 만들지 않는다. 이 0 이 깨지면 주인공 규칙 위반.

**미러 규칙**: `BoonSystem`/`BoonExecutor`/`TriggerBus` 는 단일 인스턴스라 Main↔Testplay 미러 불필요(2.3 EliteEffectService 패턴과 동일). `_selected_cards` 의 카드 dict 형상(yokai 키 포함)만 양쪽 동일 유지.

## 3. 책임 분리 매트릭스

| 분류 | 무엇 | 예시 | 수명 |
|---|---|---|---|
| **Resource** (`.tres` 튜닝) | 데이터 값만, 행동 없음 | `PlayerData`, `EnemyData`, `CharacterVisuals` | 디스크 |
| **Manager** (`scripts/managers/`) | 씬 동안 살아있는 시스템, 시그널/콜백 허브 | `ExpSystem`, `UpgradeSystem`, `WaveManager`, `InfiniteGround` | Scene |
| **Component** (`scripts/components/`) | 엔티티에 붙는 작은 책임 | `HealthComponent`, `SpriteRig`, `MonsterCollision` | Entity |
| **Effect** (`scenes/effects/`) | 자기수명 일회성 노드 | `FanTelegraph`, `AimLaser`, `BossSignal`, `CircularSlash`, `ExplosionBurst` | 자기제어 |
| **Scene** (`scenes/<영역>/`) | 가시 엔티티 + 그 행동 | `Player`, `MeleeEnemy`, `Boss`, `LevelUpScreen` | Tree |
| **Dispatcher** (현재 Main/Testplay) | 씬 부트 + 효과 라우팅 + 챕터 흐름 | `Main.gd`, `Testplay.gd` | Scene root |

### 새 코드를 어디에 둘지

- **단순 수치**라면? → 기존 Resource (`PlayerData`/`EnemyData`)에 export 추가
- **모든 적이 갖는 행동**이라면? → Component
- **한 엔티티의 고유한 행동**이라면? → 그 Scene의 `.gd`
- **시간/이벤트로 자기소멸**이라면? → Effect
- **씬 동안 계속 살아있어야** 한다면? → Manager
- **여러 시스템을 연결**한다면? → 일단 Main/Testplay에 두고, 비대해지면 Manager로 추출

---

## 4. 새 기능 추가 절차 (체크리스트)

### 4.1 새 적 추가

1. `resources/enemies/<new>_visuals.tres` — `CharacterVisuals` (텍스처/색)
2. `resources/enemies/<new>_data.tres` — `EnemyData` (HP/속도/사거리/공격 쿨)
3. `scenes/enemies/<NewEnemy>.gd` — 행동 스크립트 (MeleeEnemy/RangedEnemy 참고)
4. `scenes/enemies/<NewEnemy>.tscn` — CharacterBody3D + Health/SpriteRig 자식 + data 익스포트
5. `Main.gd` 에 `@export var new_enemy_scene: PackedScene` 추가
6. `Main._request_spawn` 분기 추가 (또는 새 카테고리 — 곡선 갱신 필요)
7. **Testplay.gd 동기화**: 버튼 추가 + `_spawn_<new>` 함수
8. `Main.award_exp_for_kill` 분기 추가 (필요 시)
9. `CLAUDE.md` 인덱스 표 갱신 — "<NewEnemy> 추가 → 어디"
10. 검증: `godot-runtime-verify` 스킬, Testplay 버튼으로 시각 검증

### 4.2 새 카드 추가 (단순 패시브)

1. `UpgradeSystem.gd` `CARDS` 배열에 `{id, name, desc}` 추가
2. `UpgradeSystem.apply()` `match` 분기 추가
3. 검증: `Testplay` → 일반 몹 10 스폰 → 레벨업 화면 새로고침 여러 번 → 카드 뜨는지 확인 → 효과 적용 후 슬래시/이속 변화 확인

`draw(3)`은 카드 풀 크기 무관 (shuffle + slice).

### 4.3 새 카드 추가 (메커니즘 — 예: "처치 시 폭발")

1. 4.2 단계 모두 적용
2. 효과 노드 신규 작성 (`scenes/effects/OnKillExplosion.gd/.tscn`) — `ExplosionBurst` 참고
3. `Player.gd` 또는 적 `_on_died` 훅에서 카드 보유 여부 체크 → 효과 스폰
4. **카드 보유 상태를 어디에 저장할지** 결정 — 권장: `PlayerData`에 `bool has_on_kill_explosion` 같은 플래그 (또는 `Array[StringName] cards`)
5. `UpgradeSystem.apply()`에서 그 플래그를 켠다
6. 검증: 적 처치 시 이펙트 발생 확인

### 4.4 새 엘리트 효과 (타입 4+)

1. `EliteEnemy._color_for_type` 새 색 추가
2. `EliteEnemy._hp_for_type` 새 HP 단계 추가
3. `Main.trigger_elite_effect` `match` 분기 추가 — 효과 함수 호출
4. **Testplay.gd 동기화** — `trigger_elite_effect` 미러 + 우측 버튼 패널에 "엘리트 4 (...)" 추가
5. `Main.award_exp_for_kill` 분기 — 새 타입 EXP 값
6. 검증: Testplay 버튼 → 효과 발동 + EXP 획득

### 4.5 새 챕터 추가 (M2에서 인프라 완성 ✅)

순서:
1. `resources/chapters/chapter_<N>.tres` 작성 (기존 chapter_1/2 복제 + 곡선/시간 조정)
2. `Main.tscn` 에서 `chapter_curves` 배열에 새 `.tres` 추가
3. (보스 신규) `scenes/enemies/Boss<N>.tscn` 작성 → `boss_scenes` 배열에 추가
   - 단순 변형이면 같은 `Boss.gd` + export 값만 다른 `.tscn` (예: `Boss2.tscn`이 max_hp/white_ratio 만 다름)
   - 완전 다른 패턴이면 Boss.gd 복제 + 신규 _begin_telegraph 로직
4. `CLAUDE.md` 인덱스 갱신
5. 검증: Ch<N-1> 클리어 → Ch<N> 자동 진입 (`Main._advance_chapter`), Ch<N> 클리어

#### 챕터 전환 흐름 (in-place)

```
Boss<N>._on_died → boss_defeated.emit
  → Main._on_boss_defeated
       → SaveSystem.record_clear(chapter_id, time, kills, level)
       → ChapterClearScreen.configure(stats, best, beat) + next_pressed 시그널 연결
  → ChapterClearScreen._on_next_pressed
       → next_pressed.emit  +  tree.paused = false  +  queue_free
  → Main._on_chapter_next_pressed
       → if _current_chapter < chapter_curves.size():
              _advance_chapter()
                   · wipe enemies + loose arrows + 효과
                   · bullet-time tween 정리
                   · WaveManager queue_free + 새로 인스턴스
                   · _current_chapter += 1
                   · _kill_count = 0  /  _chapter_cleared = false
                   · set_curve(chapter_curves[_current_chapter - 1])
                   · _chapter_start_msec = now
                   · tree.paused = false
                   ※ PC HP / EXP / 카드 빌드는 유지 — 메타 사이클 핵심
         else:
              tree.reload_current_scene  (마지막 챕터 — OutGame 메뉴는 M4에서)
```

### 4.6 새 보스 추가

1. `scenes/enemies/<NewBoss>.gd` — `Boss.gd` 복제 + 패턴 수정
2. **반드시 유지할 것**:
   - `add_to_group("boss")` (alive cap 제외 + 챕터 클리어 dispatch)
   - `signal boss_defeated` (같은 이름)
   - `take_hit` 메서드 (SlashAttack이 부른다)
3. 새 패턴 효과는 `scenes/effects/` 에 신규 노드로
4. `Main.boss_scene` 배열에 등록 (4.5와 함께 갈 가능성 큼)
5. 검증: Testplay "보스" 버튼이 챕터별 인덱스로 분기되도록 (혹은 별도 버튼 추가)

---

## 5. 확장 시나리오 — 메타 영구강화 시스템

> Vampire Survivors 본가의 "Power-Up" 패널 + 사망 시 코인 적립 + 챕터/캐릭터 언락 구조를 우리 프로젝트에 맞게 단순화한 버전. **이 시나리오는 미구현**, 가이드로만 존재한다.

### 5.1 컨셉

- 인게임 사망 또는 챕터 클리어 시 **"혼(魂)"** 적립 → 아웃게임 메인 메뉴에서 영구 패시브 강화에 사용
- 챕터 최고기록 (생존 시간, 처치 수, 도달 레벨) 표시
- 시작 시 카드 풀 일부만 해금 → 혼으로 신규 카드 풀 언락

### 5.2 추가 파일

```
scenes/main/OutGame.tscn / .gd          — 새 main_scene (메인 메뉴)
scenes/ui/MetaMenu.tscn / .gd           — 패시브 강화 패널
scenes/ui/ChapterSelect.tscn / .gd      — 챕터 선택
scenes/ui/CardUnlock.tscn / .gd         — 카드 풀 언락 패널
scripts/managers/MetaProgressionSystem.gd — 영구 재화 + 패시브 적용
scripts/managers/SaveSystem.gd          — ConfigFile or JSON 저장/로드
scripts/resources/MetaPassive.gd        — Resource 정의 (id/name/desc/max_level/cost_curve/effect_id)
resources/meta/passives/<id>.tres       — 각 패시브 정의
resources/meta/chapter_records.tres     — 최고기록 (저장 파일은 user://)
```

### 5.3 기존 파일 변경

- `project.godot` — `run/main_scene` 을 `OutGame.tscn` 로 변경
- `Main.gd` — `_ready` 진입 시 `MetaProgressionSystem.apply_to(player, exp_system)` 호출 (HP +X, EXP gain +X% 등 출발선 보정)
- `Main._on_boss_defeated` — 챕터 클리어 결과를 `MetaProgressionSystem.record_clear(chapter_id, stats)` 로 저장 후 OutGame으로 복귀
- `Player._on_died` — 사망 시 `MetaProgressionSystem.record_death(stats)` 로 혼 적립 후 OutGame으로 복귀
- `UpgradeSystem.draw` — 잠긴 카드는 풀에서 제외 (`MetaProgressionSystem.is_card_unlocked(id)`)

### 5.4 인덱스 (CLAUDE.md) 갱신 항목

| 만지고 싶은 것 | 핵심 파일 |
|---|---|
| 메타 패시브 추가 | `MetaProgressionSystem.gd` + `resources/meta/passives/<id>.tres` |
| 메타 패시브가 적용되는 지점 | `MetaProgressionSystem.apply_to` + `Main._ready` |
| 카드 풀 언락 조건 | `MetaProgressionSystem.unlock_card` + `CardUnlock.gd` |
| 챕터 선택 메뉴 | `ChapterSelect.gd` |
| 최고기록 저장/로드 | `SaveSystem.gd` + `chapter_records.tres` |
| 아웃게임 ↔ 인게임 라우팅 | `OutGame.gd` → `Main.tscn` 인스턴스 / `Main.gd` → `OutGame.tscn` 복귀 |

### 5.5 단계적 도입 권장 순서

1. **SaveSystem + 최고기록만** ✅ (M1 완료, 2026-06-03): 사망/클리어 시 시간/킬/레벨을 user://save.cfg에 적고 결과 화면에 NEW! 배지로 표시. OutGame에서도 best 표시 (M4).
2. **혼 적립 + 패시브 5종** ✅ (M4 완료, 2026-06-03): MetaProgressionSystem + user://meta.cfg. 7종 .tres 정의, 5종 활성(hp/move/slash/exp/evade), iframe_extra는 활성(Player.iframe_bonus), free_card는 정의만(후속).
3. **OutGame + MetaMenu** ✅ (M4 완료): project.godot main_scene 변경. Start / 영구강화 / 종료. 패시브별 단계/비용/MAX 표시.
4. **카드 풀 언락** ✅ (M5 완료, 2026-06-03): `UpgradeSystem.CARDS`에 `initial: bool` + `unlock_cost: int` 필드. 초기 풀 4장 (Razor's Edge / Quickstep / Iron Will / Reach), 나머지 9장은 `MetaProgressionSystem.is_card_unlocked`로 게이트. `CardUnlock.tscn` 화면 + OutGame 라우팅 추가.
2. **혼 적립 + 단일 패시브 (HP+)**: 강화 패널에 한 개만. 흐름 검증.
3. **패시브 5~7종 확장**: 카테고리별로.
4. **카드 풀 언락**: 카드 7장이 늘어난 시점에 의미가 생긴다.
5. **챕터 선택**: 챕터가 2개 이상 생긴 시점.

---

## 6. 알려진 부채 (Refactor Backlog)

다음 항목들은 `refactor-pass` 스킬의 우선순위 후보다. 항목이 3개 이상 쌓이거나 한 파일이 600줄을 넘으면 패스 권유.

### 6.1 `Main.gd` 비대화 (947 → 878줄, M8 리팩토링 후)
- 분리 완료:
  - `EliteEffectService` ✅ **통합 완료** (2026-06-04) — `trigger(type,pos)` / `spawn_circular_slash`. Main/Testplay는 `trigger_elite_effect` 얇은 위임만.
  - `BulletTimeService` ✅ **통합 완료** (2026-06-04) — `start`/`cancel`/`is_active`/`current_slow_factor`. 스폰 헬퍼는 `_inherit_bullettime`로 쿼리.
- 남은 분리 후보:
  - `SpawnService` 노드 (`_pick_*_spawn`, `_spawn_one`, `_request_spawn`) — 다음 패스 1순위. Main.gd가 다시 600줄 넘으면.

### 6.2 ~~Main ↔ Testplay 중복~~ ✅ 부분 해소 (M8, 2026-06-04)
- 엘리트 효과 + 불릿타임은 서비스로 단일화 — 그 부분 미러 사라짐.
- 잔여 중복: `_on_leveled_up` / `award_exp_for_kill` / `_try_vampire_heal` / Echo / Zen wire-up / perfect_dodge handler. `SpawnService` + `ArenaServices` 추출 시 추가 해소 가능.


### 6.3 ~~`WaveManager` const 곡선 → Resource화~~ ✅ M2 완료 (2026-06-03)
- `scripts/resources/WaveCurve.gd` + `resources/chapters/chapter_{1,2}.tres`.
- `Main.chapter_curves: Array[WaveCurve]` 에서 active chapter 주입.
- `WaveManager.set_curve(curve)` API — 챕터 전환 시 같은 노드를 재사용할
  수도 있지만 현재 `_advance_chapter` 는 queue_free 후 새 인스턴스를 선호
  (state reset이 명확).

### 6.4 엘리트 효과 dispatch 하드코딩
- `Main.trigger_elite_effect` 의 `match effect_type` 분기가 늘어나면 lookup table 또는 Resource로.
- 후보: `EliteEffect` Resource (id, color, hp, on_death_callable) — `EliteEnemy.data` 가 `EliteEffect` 를 들고 다님.

### 6.5 `Main._build_hud` 가 Main.gd 안
- HUD 빌드 코드가 Main에 직접. 별도 `scenes/ui/HUD.tscn` 으로 추출 가능.
- 우선순위 낮음 (현재 30줄 정도).

### 6.6 `UpgradeSystem.apply()` `match` 분기
- 카드 7장 시점엔 OK. M3에서 **13장**으로 늘었음 (수치 7 + 메커니즘 4 + ⏱ 타이밍 2).
- 20장 넘으면 dispatch table or per-card `Callable` 자료구조로 전환. 현재는 OK.

### 6.7 `Player._build_dust_emitter` 가 Player.gd 안
- 비주얼 한 덩어리가 Player 코드 안에 있음. 별도 `DustEmitter.tscn` 으로 추출 + Player 자식으로 인스턴스. 우선순위 낮음.

---

## 7. 외부 참고

- 메모리 / 사용자 선호도 인덱스: `~/.claude/projects/C--DEV-GODOT-project-fbdc/memory/MEMORY.md`
- 빠른 인덱스 / 컨벤션: [../CLAUDE.md](../CLAUDE.md)
- 리팩토링 절차: [../.claude/skills/refactor-pass/SKILL.md](../.claude/skills/refactor-pass/SKILL.md)
- Godot 런타임 검증 스킬: `~/.claude/skills/godot-runtime-verify/SKILL.md`
- Windows 빌드/배포 스킬: `~/.claude/skills/godot-windows-export/SKILL.md`
