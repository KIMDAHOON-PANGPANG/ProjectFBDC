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

### 2.2 보스 사망 → 챕터 클리어

```
Boss.take_hit → take_damage → died → _on_died → boss_defeated.emit()
  → Main._on_boss_defeated
       → tree.paused = true
       → ChapterClearScreen 인스턴스 (Next 버튼)
  → ChapterClearScreen._on_next_pressed
       → tree.reload_current_scene  (현재는 챕터 2 없음, 1챕터 재시작)
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

### 2.4 보스 패리 윈도우

```
Boss._begin_telegraph
  → randf() < 0.7 ? YELLOW : RED
  → BossSignal (머리 위 색 아이콘) 스폰
  → FanTelegraph (지면 부채꼴) 스폰
  → YELLOW일 때만:
        timer(telegraph_time - 0.2s) → _open_parry_window  ── _parry_open = true
        timer(window_len)            → _close_parry_window
  → 0.5s 후 sweep 시점:
        FanTelegraph._try_damage_player_now (point-check)
        OR (PC가 슬래시 trail로 보스 hit) → Boss.take_hit
             └─ _parry_open && YELLOW → _on_parried
                  · queue_free(active_telegraph) → 휘두름 시각 캔슬
                  · BossSignal.cancel()
                  · camera_rig.shake_curve(0.5, 0.3) — 강한 ease-out
                  · _blocked = true, 1s 후 _end_block
```

---

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

### 4.5 새 챕터 추가

현재 `WaveManager`가 const 곡선으로 1챕터 하드코딩. 챕터 추가 시점에 **WaveManager Resource화**가 필요해진다 — 부채(6.3 참고).

순서:
1. `WaveCurve.gd` (`Resource`) 신규 — `CURVE_TIMES/TARGETS/LVS` + 이벤트 시간(엘리트/보스)을 export
2. `resources/chapters/chapter_1.tres`, `chapter_2.tres` … 작성
3. `WaveManager` 가 `curve: WaveCurve` 를 받도록 변경 (const 곡선 제거)
4. `Main.gd` 에 `current_chapter: int` + `chapter_curves: Array[WaveCurve]` 추가
5. `ChapterClearScreen` "Next" 버튼이 `reload_current_scene` 대신 다음 챕터로 라우팅 (또는 OutGame으로 복귀 — 5번 시나리오 참고)
6. 챕터별 보스 다를 경우 `Main.boss_scene: Array[PackedScene]` 배열화
7. `CLAUDE.md` 인덱스 갱신
8. 검증: 챕터 1 클리어 후 챕터 2 자동 진입, 챕터 2 클리어 후 다음 흐름

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

1. **SaveSystem + 최고기록만**: 사망/클리어 시 시간/킬/레벨을 user://save.cfg에 적고, 메인 메뉴에서 표시. 영구강화 없음. (가장 작게)
2. **혼 적립 + 단일 패시브 (HP+)**: 강화 패널에 한 개만. 흐름 검증.
3. **패시브 5~7종 확장**: 카테고리별로.
4. **카드 풀 언락**: 카드 7장이 늘어난 시점에 의미가 생긴다.
5. **챕터 선택**: 챕터가 2개 이상 생긴 시점.

---

## 6. 알려진 부채 (Refactor Backlog)

다음 항목들은 `refactor-pass` 스킬의 우선순위 후보다. 항목이 3개 이상 쌓이거나 한 파일이 600줄을 넘으면 패스 권유.

### 6.1 `Main.gd` 비대화 (~700줄)
- 챕터 시스템 / 스폰 위치 / 엘리트 효과 dispatch / 불릿타임을 한 파일에서 다 한다.
- 분리 후보:
  - `SpawnService` 노드 (`_pick_*_spawn`, `_spawn_one`, `_request_spawn`)
  - `EliteEffectService` 노드 (`trigger_elite_effect`, `_spawn_explosion`, `_queue_circular_slash_*`)
  - `BulletTimeService` 노드 (`_start_bullettime`, `_end_bullettime`, `_apply_slow_to_loose_arrows`)
- 분리 효과: Main은 부트 + 챕터 흐름만 갖고, 위 서비스들을 Testplay와 공유 가능 (6.2와 동시 해결).

### 6.2 Main ↔ Testplay 중복
- `trigger_elite_effect`, `_queue_circular_slash_after_slash`, `_start_bullettime`, `_on_leveled_up`, `award_exp_for_kill` 등이 두 파일에 거의 그대로 존재.
- 해결: `ArenaServices` 공통 노드 추출. Main / Testplay는 부트 + 자기 특유의 dispatcher만.
- 우선순위: 6.1과 함께 해결.

### 6.3 `WaveManager` const 곡선 → Resource화
- 챕터가 1개를 넘는 순간 (5.5 단계 5) 필수.
- `WaveCurve` Resource로 분리, 챕터별 `.tres` 파일.

### 6.4 엘리트 효과 dispatch 하드코딩
- `Main.trigger_elite_effect` 의 `match effect_type` 분기가 늘어나면 lookup table 또는 Resource로.
- 후보: `EliteEffect` Resource (id, color, hp, on_death_callable) — `EliteEnemy.data` 가 `EliteEffect` 를 들고 다님.

### 6.5 `Main._build_hud` 가 Main.gd 안
- HUD 빌드 코드가 Main에 직접. 별도 `scenes/ui/HUD.tscn` 으로 추출 가능.
- 우선순위 낮음 (현재 30줄 정도).

### 6.6 `UpgradeSystem.apply()` `match` 분기
- 카드 7장 시점엔 OK. 20장 넘으면 dispatch table or per-card `Callable` 자료구조로 전환.

### 6.7 `Player._build_dust_emitter` 가 Player.gd 안
- 비주얼 한 덩어리가 Player 코드 안에 있음. 별도 `DustEmitter.tscn` 으로 추출 + Player 자식으로 인스턴스. 우선순위 낮음.

---

## 7. 외부 참고

- 메모리 / 사용자 선호도 인덱스: `~/.claude/projects/C--DEV-GODOT-project-fbdc/memory/MEMORY.md`
- 빠른 인덱스 / 컨벤션: [../CLAUDE.md](../CLAUDE.md)
- 리팩토링 절차: [../.claude/skills/refactor-pass/SKILL.md](../.claude/skills/refactor-pass/SKILL.md)
- Godot 런타임 검증 스킬: `~/.claude/skills/godot-runtime-verify/SKILL.md`
- Windows 빌드/배포 스킬: `~/.claude/skills/godot-windows-export/SKILL.md`
