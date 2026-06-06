# 사운드 자산 배치 가이드 (M7)

> `SoundManager` Autoload는 이미 작동한다 (`scripts/managers/SoundManager.gd`).
> `.ogg` 파일이 **아래 경로에 있으면 자동으로 재생**되고, 없으면 조용히 스킵한다
> (`ResourceLoader.exists` 가드). 즉 **이 문서대로 파일만 떨궈 넣으면 코드 수정 0**.

---

## 1. 폴더 구조 (직접 만들 것)

```
res://audio/
├── sfx/        ← 효과음 (짧은 단발, .ogg)
└── bgm/        ← 배경음악 (루프, .ogg)
```

Godot 에디터에서 FileSystem 독 우클릭 → New Folder, 또는 탐색기에서
`C:\DEV\GODOT\project-fbdc\audio\sfx` / `audio\bgm` 생성.

---

## 2. 필요한 파일 목록 (파일명 = 코드가 부르는 이름)

### SFX — `res://audio/sfx/<name>.ogg`

현재 코드가 호출하는 큐 (파일명 정확히 일치해야 함):

| 파일명 | 호출 지점 | 느낌 |
|---|---|---|
| `slash.ogg` | 일반 슬래시 발사 | 짧은 칼바람 "쉭" |
| `burst_slash.ogg` | ⏱ Zen 풀폭 슬래시 | 묵직한 거합 "촤악" + 잔향 |
| `hit.ogg` | PC 피격 | 둔탁한 타격 + 약한 금속 |
| `shield.ogg` | 엘리트4 보호막 흡수 | 맑은 "팅" 가드음 |
| `parry.ogg` | 보스 패리 성공 | 날카로운 쇳소리 "챙" |
| `perfect_dodge.ogg` | ⏱ 퍼펙트 닷지 | 휙 하는 바람 + 짧은 슬로우 톤 |
| `fizzle.ogg` | ⏱ 차징 overcharge 실패 | 힘 빠지는 "푸쉬" 불발음 |

**추가 권장 큐** (호출 지점을 코드에 더 박으면 작동 — 아래 §5 참고):

| 파일명 | 추천 호출 지점 | 느낌 |
|---|---|---|
| `levelup.ogg` | `ExpSystem.leveled_up` | 밝은 상승 징글 |
| `card_pick.ogg` | `LevelUpScreen._on_card_pressed` | UI 선택 확정음 |
| `enemy_death.ogg` | `EliteEnemy._on_died` 등 | 짧은 소멸음 |
| `boss_signal.ogg` | `Boss._begin_telegraph` | 경고 "웅—" |
| `chapter_clear.ogg` | `Main._on_boss_defeated` | 승리 징글 |
| `souls_gain.ogg` | 결과 화면 진입 | 동전/혼 적립음 |

### BGM — `res://audio/bgm/<name>.ogg`

| 파일명 | 추천 호출 지점 | 느낌 |
|---|---|---|
| `menu.ogg` | `OutGame._ready` | 잔잔한 동양풍 메뉴곡 |
| `ingame.ogg` | `Main._build_chapter_systems` | 긴장감 있는 전투 루프 |
| `boss.ogg` | `Main._chapter_spawn_boss` | 고조되는 보스전 |

> BGM은 `SoundManager.play_bgm("ingame")` 처럼 호출. 같은 곡 재호출은 no-op
> (재시작 안 함). 챕터 전환/씬 전환 때 바꿔주면 됨.

---

## 3. 무료 자산 소스 (상업 이용 가능 라이선스 확인 필수)

### SFX
- **Kenney.nl** (https://kenney.nl/assets) — CC0(저작권 free). "Impact Sounds",
  "RPG Audio" 팩에 슬래시/타격/UI 다수. **최우선 추천** (라이선스 깔끔).
- **Freesound.org** — CC0 / CC-BY 필터링 가능. "katana slash", "sword hit",
  "parry" 검색. CC-BY는 크레딧 표기 필요.
- **OpenGameArt.org** — CC0/CC-BY/GPL 혼재. 라이선스 항목 꼭 확인.
- **sonniss.com/gameaudiogdc** — 매년 GDC 무료 번들 (수십 GB, 상업 이용 가능).

### BGM
- **OpenGameArt.org** — "japanese" / "samurai" / "action loop" 태그.
- **Pixabay Music** (https://pixabay.com/music/) — 로열티 프리, 크레딧 불요.
- **incompetech.com** (Kevin MacLeod) — CC-BY (크레딧 표기 시 무료).
- **AI 생성**: Suno / Udio 등으로 "lo-fi japanese battle loop" 생성 가능
  (서비스별 상업 이용 약관 확인).

---

## 4. OGG 변환 / 준비

Godot는 `.ogg`(Vorbis)를 기본 지원. `.wav`/`.mp3`를 받았다면 변환:

```
# ffmpeg (https://ffmpeg.org)
ffmpeg -i input.wav  -c:a libvorbis -q:a 5  output.ogg     # SFX (q5 ≈ 160kbps)
ffmpeg -i input.mp3  -c:a libvorbis -q:a 6  bgm.ogg         # BGM (조금 더 고음질)
```

### BGM 루프 설정 (중요)
`.ogg`를 Godot에 임포트하면 기본은 루프 OFF. FileSystem에서 해당 `.ogg` 선택 →
Import 탭 → **Loop 체크** → Reimport. (BGM만. SFX는 루프 OFF 유지.)

### SFX 볼륨/길이
- 단발 0.1~0.8초 권장. 너무 길면 연타 시 겹침.
- 피크 정규화 -3dB 정도. SoundManager가 `sfx_volume_linear`(기본 1.0)로 한 번 더 조절.

---

## 5. 추가 호출 지점 박는 법 (선택)

§2의 "추가 권장 큐"를 작동시키려면 한 줄씩 추가:

```gdscript
# 예: 레벨업 징글 — ExpSystem.gd 또는 Main._on_leveled_up 안
func _on_leveled_up(new_level: int) -> void:
    _play_sfx_global("levelup")   # 아래 헬퍼 참고
    ...

# Player.gd 의 _play_sfx 와 동일 패턴 (autoload 가드):
func _play_sfx_global(name: String) -> void:
    var root := get_tree().root if get_tree() != null else null
    if root != null and root.has_node("SoundManager"):
        root.get_node("SoundManager").call("play_sfx", name)
```

BGM 예:
```gdscript
# OutGame._ready 끝
var root := get_tree().root
if root.has_node("SoundManager"):
    root.get_node("SoundManager").call("play_bgm", "menu")
```

> 이미 박힌 큐 (slash/hit/parry/shield/perfect_dodge/fizzle/burst_slash)는
> 파일만 넣으면 즉시 들린다. 추가 큐는 위처럼 호출 한 줄씩.

---

## 6. 볼륨 슬라이더 (Settings — 아직 미구현)

`SoundManager.set_sfx_volume(0~1)` / `set_bgm_volume(0~1)` API는 이미 있음.
Settings 화면이 생기면 슬라이더 → 이 두 함수에 연결만 하면 됨. (M7 잔여 작업)

---

## 7. 체크리스트

- [ ] `audio/sfx/`, `audio/bgm/` 폴더 생성
- [ ] §2 SFX 7종 (slash/burst_slash/hit/shield/parry/perfect_dodge/fizzle) `.ogg` 배치
- [ ] BGM 1~3곡 배치 + Import에서 Loop 체크
- [ ] 게임 실행 → 슬래시/피격/패리 소리 확인
- [ ] (선택) 추가 큐 호출 한 줄씩 박기 (levelup/clear/boss_signal …)
- [ ] (선택) Settings 볼륨 슬라이더 → set_*_volume 연결
- [ ] 라이선스 출처 메모 (CC-BY면 크레딧 파일에 기록)

---

## 참고

- 호출 코드: `scripts/managers/SoundManager.gd`
- 현재 hook: `scenes/player/Player.gd` (`_play_sfx`), `Boss._on_parried`(parry)
- 아키텍처: [ARCHITECTURE.md](ARCHITECTURE.md) #2.11 사운드
