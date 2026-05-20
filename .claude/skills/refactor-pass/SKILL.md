---
name: refactor-pass
description: ProjectFBDC 코드베이스에 주기적/명시적으로 적용하는 리팩토링 패스. 새 기능 추가가 누적되어 파일이 부풀거나, 책임 경계가 흐려지거나, CLAUDE.md 인덱스와 실제 코드가 어긋났을 때 구조를 다시 정렬한다. 트리거 - "리팩토링 패스 돌려줘", "구조 정리해줘", "Main.gd 너무 커졌어", "refactor pass", "refactor". 휴리스틱 권장 - 한 .gd 파일이 600줄을 넘거나, 마지막 패스로부터 1~2주 지났거나, docs/ARCHITECTURE.md의 Refactor Backlog 항목이 3개 이상 쌓이거나, CLAUDE.md 인덱스 표가 실제 파일과 어긋났을 때 사용자에게 권유.
---

# Refactor Pass — ProjectFBDC 주기 리팩토링 절차

ProjectFBDC가 인벤 기사([Firefield 사례](https://www.inven.co.kr))의 함정에 빠지지 않게 만드는 안전장치다. 기능을 그냥 쌓기만 하면 컨텍스트가 폭주하고 Claude가 매 수정마다 전체 코드를 다시 읽는다. 1~2주마다 또는 명시적 신호가 오면 이 패스를 돌려 구조를 다시 정렬한다.

본 스킬은 일반 `bugqa` 의 검증 원칙을 상속하고, Godot 빌드 검증은 `godot-runtime-verify` 스킬에 위임한다.

## When to apply

다음 중 하나라도 해당하면 적용:

- 사용자 명시 호출: "리팩토링 패스 돌려줘", "구조 정리", "refactor pass"
- 한 `.gd` 파일이 **600줄을 넘음** — 특히 `Main.gd` (이미 ~700줄)
- 마지막 패스로부터 **1~2주 경과**
- `docs/ARCHITECTURE.md` 의 Refactor Backlog 항목이 **3개 이상 쌓임**
- `CLAUDE.md` 의 인덱스 표가 실제 파일/책임과 어긋나 있음 (스캔 단계에서 자동 감지)
- 같은 책임의 코드가 `Main.gd` 와 `Testplay.gd` 양쪽에 중복으로 5건 이상

위 휴리스틱 중 하나가 충족되었는데 패스가 안 돌고 있으면, 사용자에게 한 줄로 권유한다. **사용자 컨펌 없이 자동 적용 금지**.

## When NOT to apply

- 단일 버그 수정 중 — 버그 먼저 잡고, 깨끗한 상태에서 패스
- 한 기능 구현 진행 중 — 기능 완료 + 검증 통과 + 커밋 후에 패스
- 사용자가 "지금은 그냥 기능부터" 라고 명시
- 파일이 600줄이라도 응집도가 좋고 분리할 자연스러운 경계가 안 보일 때

## The pass — 4단계 loop

```
1. 스캔 — 코드 상태 측정
2. 진단 — 우선순위 결정 + 사용자 컨펌
3. 적용 — 1건씩, 검증과 함께
4. 문서 정합 — CLAUDE.md / ARCHITECTURE.md 갱신
```

---

### 1. 스캔

다음 데이터를 모은다 (모든 측정은 read-only):

- **파일별 라인 수** — `scripts/` `scenes/` 하위의 `.gd` 전체. 600+ 항목 별표 표시.
- **Main.gd ↔ Testplay.gd 함수명 교집합** — 의도된 중복(`trigger_elite_effect` 등)을 잡고, 새로 추가된 중복이 있는지 확인.
- **CLAUDE.md 인덱스 표 vs 실제 파일** — 인덱스가 가리키는 경로가 다 존재하는지, 실제 있는 매니저/씬 중 인덱스에 없는 게 있는지.
- **ARCHITECTURE.md Refactor Backlog 항목** — 6.1~6.7 (또는 그 시점의 목록) 중 이미 해결된 항목이 있는지.
- **TODO / FIXME / HACK 코멘트** — `Grep` 으로 카운트.
- **Resource 화 가능한 const 곡선/배열** — `const CURVE_*`, `const CARDS` 같은 패턴.

스캔 결과는 사용자에게 한 화면 안에 들어가는 요약으로 제시:

```
## Scan (YYYY-MM-DD)
File size 600+ : Main.gd (712), …
Drift in CLAUDE.md index : 0 / 2 / …
Backlog still open : 6.1, 6.2, 6.4
Backlog resolved   : (있으면 표시)
New duplication (Main/Testplay) : (있으면 함수명 나열)
TODO/FIXME : N
```

### 2. 진단

스캔 결과로 **이번 패스의 후보 3건 이내**를 선정한다. 더 많이 하지 않는다 — 한 번에 하나씩 끝내고 검증하는 게 안전.

선정 기준:
- "지금 만지면 이득"이 분명한 것 (다음 기능 추가에 직접 영향)
- 작업 단위가 명확히 자를 수 있는 것 (애매하면 다음 패스로)
- 검증이 가능한 것 (`godot-runtime-verify` + 시각 검증으로 catch 가능)

사용자에게 후보를 보여주고 **컨펌 받는다**. 형식:

```
## 후보 (3건)
1. [6.1] Main.gd에서 SpawnService 노드 추출 — Main.gd 약 250줄 감소 예상
2. [6.3] WaveManager 곡선 Resource화 — 챕터 추가 직전에 필수
3. CLAUDE.md 인덱스 갱신 — 새 효과 1개 누락

어느 것부터 적용할까요? (전부/일부/다음 기회)
```

### 3. 적용 — 한 번에 1건씩

각 항목마다:

1. **변경 전 상태 메모** — 어떤 파일이 영향받는지, 어떤 책임이 이동하는지 한 줄 요약
2. **Edit / Write** — 해당 변경 적용
3. **`godot-runtime-verify` 스킬 호출** — .exe + godot.log grep 통과
4. **시각 검증 위임** — 사용자에게 Main.tscn / Testplay.tscn 둘 다 한 번 띄워보라고 요청. 영향 시스템(카드/적/엘리트 효과)을 1개씩 트리거해서 정상인지 확인 부탁
5. **커밋** — main 브랜치에 직접 (메모리 `feedback_push_workflow`). 메시지 예: `refactor: extract SpawnService from Main.gd (#6.1)`

다음 항목으로 넘어가기 전에 위 5단계 모두 통과해야 한다. 통과 못 하면 그 자리에서 중단하고 사용자에게 상황 공유.

### 4. 문서 정합

리팩토링이 끝나면 두 문서를 갱신:

- **CLAUDE.md** — 인덱스 표 갱신
  - 새 파일 추가됐으면 라인 추가
  - 책임이 다른 파일로 이동했으면 표 수정 (예: "스폰 위치 로직" 가 `Main._pick_*_spawn` → `SpawnService.pick_*`)
  - 새 매니저가 생겼으면 디렉토리 맵 + 외부 문서 링크 갱신

- **docs/ARCHITECTURE.md**
  - Refactor Backlog (#6.X)에서 해소된 항목 제거
  - 시스템 다이어그램 (#1.2) 의존 관계 갱신
  - 데이터 흐름 (#2) 변경 사항 반영
  - 책임 분리 매트릭스 (#3) 새 분류 추가 시 갱신
  - 새 기능 추가 체크리스트 (#4) 가 변경된 절차로 작동하는지 확인

문서 갱신은 리팩토링과 같은 커밋에 넣지 말고 **별도 커밋** — 코드 변경과 문서 변경을 시간순으로 따로 보고 싶다.

---

## 자주 등장하는 리팩토링 패턴

### A. 600+줄 .gd → 서비스 노드 분리

```
Before: Main.gd 700+
After:  Main.gd (부트 + 챕터 흐름) + SpawnService / EliteEffectService / BulletTimeService
```

- 새 서비스는 `scripts/managers/` 에 위치, Main의 자식 노드로 add
- 콜백/시그널 기반으로 약결합 (`WaveManager` 가 콜백 4개로 Main과 약결합한 방식 참고)
- 서비스가 PC를 알아야 한다면 setter로 (`set_target(player)`)

### B. Main ↔ Testplay 중복 → ArenaServices

```
Before: trigger_elite_effect / _start_bullettime / _queue_circular_slash 등이 양쪽에
After:  ArenaServices.gd 단일 노드, Main과 Testplay 양쪽이 인스턴스해서 자식으로
```

- 같은 책임을 한 곳에. 양쪽 dispatcher는 그냥 `_services.trigger_elite_effect(...)` 호출
- 동기화 규칙(CLAUDE.md)의 부담이 사라짐 — 새 효과 추가 시 한 곳만 수정

### C. const 곡선/배열 → Resource

```
Before: WaveManager 안의 const CURVE_TIMES/TARGETS/LVS
After:  WaveCurve.gd (Resource) + resources/chapters/chapter_<N>.tres
```

- 챕터 분기 시 const 코드 수정 대신 .tres 파일 추가
- 데이터/코드 분리, 인스펙터에서 튜닝 가능

### D. match 분기 3+ → dispatch table or Resource lookup

```
Before: Main.trigger_elite_effect 의 match effect_type
After:  Dictionary {1: Callable, 2: Callable, 3: Callable} 또는 EliteEffect Resource 들고 다님
```

- 신규 효과 추가가 분기 한 줄이 아니라 Resource 한 파일로 끝남
- ARCHITECTURE.md #6.4 후보

### E. 유사 클래스 3+ → 베이스 + 데이터

```
Before: MeleeEnemy / RangedEnemy / EliteEnemy 가 _ready 패턴 거의 같음
After:  EnemyBase.gd (group 등록 + collision + health 셋업) + 각 서브가 행동만
```

- 단, 행동 차이가 큰 경우(Boss의 패리 윈도우 등)는 무리해서 통합하지 않는다
- 우선순위 낮음 — 현재 4 종류면 OK

---

## 검증 절차

리팩토링 적용 후 반드시:

1. **`godot-runtime-verify` 호출** — `.exe` + `godot.log` grep으로 `error / warning / SCRIPT ERROR / Unrecognized UID / Trying to cast a freed` 0건 확인
2. **시각 검증 위임** — 사용자에게:
   - Main.tscn 띄워서 60초 / 120초 비트 도달 (스폰 / 엘리트 / 보스)
   - Testplay.tscn 띄워서 변경된 시스템 관련 버튼 1번씩 눌러 정상 동작 확인
   - 레벨업 카드 한 번 받아보기 (효과 적용되는지)
3. **커밋 직전 diff 리뷰** — main 직커밋 전 한 번 더 사용자에게 "이대로 커밋?" 컨펌

검증이 실패하면 그 항목은 **롤백** — 변경을 되돌리고 다음 패스 후보로 미룬다.

## 보고 포맷

```
## 리팩토링 패스 결과 (YYYY-MM-DD)

### 적용
- [6.1] SpawnService 추출 — Main.gd 712 → 480줄
- [6.3] WaveCurve Resource화 — 챕터 추가 준비 완료

### 보류 (다음 패스)
- [6.2] ArenaServices — 6.1 후속, 다음 패스 후보

### 문서 갱신
- CLAUDE.md 인덱스: "스폰 위치 로직" 항목 → SpawnService.pick_*
- docs/ARCHITECTURE.md: #1.2 다이어그램 + #6.1/6.3 백로그 해소

### 런타임 검증
✅ godot-runtime-verify 통과 (godot.log 153 bytes, 0 matches)
⚠️ 시각 검증은 사용자 확인 위임

### 다음 패스 권유 시점
- Main.gd 다시 600줄 넘는 시점, 또는
- 챕터 2 추가 직전 (ArenaServices 분리 필수)
```

검증이 실패한 경우:

```
## 리팩토링 패스 결과 (YYYY-MM-DD) — 중단

### 시도
- [6.1] SpawnService 추출 — 적용 후 godot-runtime-verify 실패

### 실패 내용
- Pattern matched: "Trying to cast a freed object" at SpawnService.gd:42
- Cause: PC 참조가 setter 호출 전에 사용됨

### 롤백
- SpawnService 변경 되돌림. 다음 패스에서 setter 타이밍 조정 후 재시도.

### 적용된 것 (롤백 안 함)
- (이미 통과한 항목들)
```

## 기존 스킬과의 관계

- `bugqa` — 일반 원칙(변경 후 실행 검증)을 본 스킬이 상속
- `godot-runtime-verify` — 검증 단계(#3-3, #검증절차-1)에서 호출하는 의존 스킬
- `godot-windows-export` — 무관 (배포용)
- `godot-pixel-sprite-alpha` — 무관 (특정 그래픽 이슈)

## 메타 원칙

- **한 번에 1건씩.** 패스 한 번에 5건을 처리하려 하지 않는다. 사람이 검증 가능한 단위로 쪼개야 신뢰가 쌓인다.
- **문서가 먼저 거짓말하지 않게.** 코드와 문서가 어긋난 채로 패스가 끝나는 것보다 차라리 리팩토링 1건을 건너뛰는 게 낫다.
- **롤백을 두려워하지 않는다.** 검증 실패 시 즉시 되돌리고 다음 기회를 잡는 게, 어설프게 봉합한 채 다음 기능을 쌓는 것보다 안전하다.
- **인벤 기사의 교훈**: "기초가 없는 땅에 탑을 쌓으면서 그 아래의 기초를 보강하는 작업." — 이 스킬은 바로 그 "기초 보강" 자체.
