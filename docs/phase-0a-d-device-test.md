# Phase 0A-D 실기기 검증 런북

> **상태 (rev.19 · 2026-09-09):** 단일 Canvas 기본 on 전환과 `develop` 병합, Production 스키마 승격 완료. D1~D8은 §8-2의 개별 판정을 따르며 **전부 완료가 아닙니다**.
> **절차 §6-9 · 최신 D9 기록 §8-7.** 과거 측정값·실패 경위·빈 기록 양식은 보존합니다. 현재 출시 범위와 후속 순서는 [2.0.0 로드맵](./release-2.0.0-roadmap.md)을 따릅니다.
> 구기기·120Hz 실기기 검증은 미보유로 출시 선행 조건에서 제외합니다. 보유 기기는 iPad mini 7세대와 iPad Air M2 11인치이며, Air를 보유했다는 사실이 기존 미수행 결과를 통과로 바꾸지는 않습니다.
>
> **D9 진행 상황 (2026-09-09)** — 스모크 · D9-1 · D9-2 · **D9-3-1·2·4** · **D9-4-1·4** · **D9-7-4** · **D9-8**(측정) · D9-CK② 통과.
> ✅ **D9-6 은 통과입니다** — **R23**(flag off 로 장을 열기만 해도 v3→v2 강등)과 **R24**(같은 장 재로드가 기하 실측을 버림)를 모두 수정하고 실기기에서 재확인했습니다. 이전 ✅ 는 화면만 보고 DB 를 안 본 판정이었고, 이번에는 DB·HUD 콘솔·화면을 함께 봤습니다.
> ✅ **D9 H(회전 표시)와 E-4 는 종결됐습니다** — 분석 §6 의 잔여 검증 5건을 모두 수행했고 D9 H 증상은 전부 통과했습니다. **R21도 대조 측정으로 종결됐습니다.** 남은 위험은 **R20**(재구성의 전이 메모리 peak 1.8 GiB) · **R17 · R18 · R22 · R25 · R27 · R28** — §8-7.
> ✅ **D9-5 · D9-7-1·3 · D9-CK③ 도 통과**했습니다 (2026-09-09). **D9-7-2 만 ❓ 미수행** — Pencil 입력이 필요해 자동화할 수 없습니다.
>
> ⚠️ **인자 의미 주의.** `-CanvasFreshStrokesOnApply` 는 사라졌고, `-CanvasReuseStrokesOnApply` 는
> **수정을 끄고 결함을 재현하는** Debug opt-out 입니다. **기본 검증은 인자 없이** 돕니다.
>
> · 대상 문서: [설계](./single-canvas-design.md) §11 / §13 / §16 / §18 / §19 · [D9 H 분석](./single-canvas-rotation-display-investigation.md) · [실기기 CLI 조작](./device-debugging-cli.md)
> · 대상 기기: **iPad mini (A17 Pro)** — 지금까지의 **모든 실기기 결과는 이 한 대의 것**입니다.
>   ⚠️ **iPad Air (M2) 는 통째로 미수행**이며 D5-5(기기 간 유의차)와 D6 이 거기 걸려 있습니다 (설계 §13 사각지대).
> · 회귀 기준선 **312** (설계 §19-4-2). **아래 기록에 남은 265 · 296 등은 그 시점의 이력이며 현재 기준선이 아닙니다.**

---

## 0-A. 개정 이력

> rev.1~rev.5 는 "무엇을 왜 바꿨는가" 를 길게 적었습니다. **결정만 남기고 과정은 지웠습니다**
> (설계 rev.19 정리와 같은 원칙). 과정이 필요하면 `git log -- docs/phase-0a-d-device-test.md` 를 보십시오.

| rev | 내용 |
|---|---|
| 1 | `devicectl` 기반 D8 + D1~D7-pre 최초 작성. D8 절은 rev.2 가 무효화 |
| 2 | **D8 을 Finder 백업 추출 경로로 전면 교체** (§6-1). `devicectl` / Download Container 는 **개발 서명으로 설치된 앱**의 컨테이너만 본다 — 추출 대상인 App Store 판은 애초에 대상 밖이었다 (§6-1-0). 나머지 실기기 항목은 인증서 폐기로 전면 차단 |
| 3 | **차단 전면 해제 · D5 · D1 · D2 완료.** 스크롤 구조 **B 확정**(§8-3 · 설계 §12 U4) · D5 baseline(§8-4) · **§7-3-a 신설**(USB 필수 · `Allocations` 금지) · 개발 서명 설치가 App Store 앱 컨테이너를 보존함을 관측(§2-3) |
| 4 | Phase 2 가 `os_signpost` 를 추가 — Instruments **os_signpost** 계측기의 카테고리 `ChapterLayout` / 인터벌 `measure` 로 정밀 layout 시간 측정 가능 (실기기 미측정) |
| 5 | **D9 신설** — §6-9(실행) · §8-7(기록). rev.4 까지 이 문서는 N-Canvas 와 S4 하네스만 다뤘고, D9 가 **제품 코드의 단일 Canvas 경로**를 처음으로 실기기에서 본다 |
| 6 | **D9 스모크 통과 — R13 · R16 종결** (설계 §20-13 · §20-14). **§6-9 D9-0-d 신설** — R13 수정의 부작용으로 `Δ max` 가 R16 계열을 더 이상 검출하지 못해(**R17**), `H`(totalHeight) 비교가 유일한 실기기 검출 수단이 됐다 |
| 7 | 합성 프로브(`compose` HUD 줄, `f17f49b5`) 추가 · **R18** 기록. `leg`/`mism` 은 **마지막 합성**의 결과라 편집 직후에 줄지 않는다(장을 나갔다 와야 갱신) — 여기서 세 번 헛짚었다 |
| 8 | **D9 H 원인 분리** — 데이터는 도착하는데 화면만 낡음. rev.7 의 **"E-4 는 결함 아님" 판정을 되돌림**(§8-7) |
| 9 | **D9 H 정식 수정 + 실기기 A/B 통과** (`ef053111`) — 인자 없이 3왕복 정상, `-CanvasReuseStrokesOnApply` 로 결함 재현. **잔여 검증이 남아 종결 아님** |
| **10** | 문서 정리 — 소진된 계획(§3 실행 가능성 판정 · §4 실행 순서 · §5 차단 표기)과 개정 서사를 압축하고, 살아 있는 절차·실측·미수행 항목만 남김 |
| 11 | **D9 H 잔여 검증 완료 · D9 H 와 E-4 종결.** D9-3-1·2·4 · D9-4-1·4 · D9-7-4 · **D9-8(성능 실측)** 채움. ⛔ **D9-6 을 ✅→❌ 로 정정** — flag off 로 장을 열기만 해도 v3→v2 강등 + metadata 삭제(**R23**, 설계 §10-3 위반) · **R24**(flag off 직후 화면 밖 절 미표시). 이전 ✅ 는 화면만 본 판정이었고, **앱 컨테이너 DB 를 뽑아 비교하는 절차**를 새로 도입해 잡음(조사 §7). **R20**(재구성 전이 메모리 1.8 GiB) · **R21**(N-Canvas 대조 미측정) · **R22**(팔레트 폭) 추가 |
| 12 | **R23 수정·재확인.** `CanvasView` 에 프로그램 대입 억제를 넣어 flag off 강등을 닫음. 회귀 2건(기준선 302 → **304**) · 변이 테스트 · 실기기 170행 불변. **D9-6 은 ❌ → △ 부분**(R24 미해결). **D9-6-5**(flag on 편집 → v3 복귀) 실측 통과 |
| 13 | **R24 수정·재확인.** 같은 장 재로드가 기하 실측을 버려 ① flag off 시 화면 밖 절의 **잉크 미표시** ② 레이아웃의 **실측 높이 → 예측식 후퇴**(R13 재발, `H` 3016 → 2977) ③ **Δ 안전망 실명**을 함께 만들던 결함을 닫음. 회귀 4건(기준선 304 → **308**) · 변이 테스트 · 실기기 재확인. **D9-6 ✅ 통과로 복귀.** 진단은 새로 들어온 `ChapterHUD` 콘솔 로그로 수행 |
| 14 | **R21 종결** — 시편 119편에서 같은 절차로 단일 Canvas vs N-Canvas 를 순서 바꿔 2회씩 측정. **단일 Canvas 가 정점 ~435 MiB · 안정 ~440 MiB 가볍다.** D5 의 363.6 MB 와 어긋난 것은 절차 차이였다. §8-7 D9-8 에 A/B ③ 추가, 한계 5 해소 |
| 15 | **실기기 UI 자동화 도입 (XCUITest).** Appium 불필요 — 러너가 iPadOS 27.0 beta 에 프로젝트 기존 서명으로 붙는다. 스크린샷·HUD 판독·헤더 조작이 가능해졌다. **D9-5-1 · D9-7-1 · D9-7-3 통과.** ⚠️ Pencil 입력은 여전히 자동화 밖이고, **D9-5-2 는 메뉴가 remote view 라 제외**. ⛔ 자동화 사고로 시편 119편 1~4절이 수정됐다 — **A1** 참고 |
| 16 | **D9-5 종결 · R25 발견.** 5-1·5-2·5-6 확인(시트가 누른 절을 정확히 잡고, 손가락 필사 ON 에서도 점이 생기지 않는다). 5-4·5-5 는 **회차가 쌓이지 않는 설계**라 판정 불가 — 이 기능은 이력이 아니라 데이터 생존 확인용 안전망이다. ⚠️ **R25**: 롱프레스 메뉴가 약 1초 뒤 PencilKit 메뉴로 바뀌어 **오탭이 전 획 선택으로 이어진다** — A1 사고의 진짜 원인 |
| 17 | **단일 Canvas 기본 전환** · **R20 구체화.** 기본값을 `SingleCanvasFlag.defaultValue` 한 곳에 두고 on 으로. jetsam 한도를 실측(**3376 MB**, 8 GB 기기)하고 회전 peak **1839.2 MB**(여유 45.5%)를 독립 확인. ⚠️ **N-Canvas 는 같은 장 정지 상태가 1322 MB** 라, 저메모리 위험은 전환이 만든 게 아니라 이미 있던 것이며 전환은 대체로 완화 쪽이다. 기준선 308 → **310** |
| **18** | **D9-CK③ 완료 · R26 수정 · MetricKit.** CloudKit 운영 컨테이너에 `CD_layoutMetadataData` · `CD_rowUUID` 승격(배포 전 죽은 필드 3개와 `CD_BiblePageDrawing` 정리). **기본 활성화의 하드 블로커 해소.** 그 과정에서 **R27**(기존 행의 rowUUID 가 서버에 없음)과 **R28**(혼재 버전에서 `drawingVersion == 3` 오해석 위험)을 세움 |
| **19** | **2.0.0 문서 정리** — D1~D8 전체 완료 오기, D9 H·D9-8·R21·E-4 현재 상태 정정. 과거 실측은 보존. 출시 후 관측 범위와 로드맵 연결 |

## 0. 이 런북을 읽는 방법

### 표기 규칙

| 표기 | 뜻 |
|---|---|
| ✅ **확인함** | 이 머신에서 실제로 실행했거나 `--help` 로 하위 명령·옵션 존재를 조회함 |
| 🔌 **실물 확인 필요** | 명령·쿼리 형태는 확인했으나, 결과는 **실기기가 붙거나 실제 백업이 있어야** 알 수 있음 |
| ❓ **미확인 / 미수행** | 확인할 수단이 없었거나 아직 하지 않았음. 추측하지 않고 그대로 남김 |
| ⚠️ | 되돌릴 수 없는 손실 가능성 |

> **판정은 ✅ 통과 / ❌ 실패 / △ 부분 / ❓ 미수행 넷 중 하나만 씁니다.**
> ⚠️ **"아마 됐다" 를 ✅ 로 적지 마십시오.** §8-4 가 남긴 교훈이 그것입니다 — 스크롤 절차를 세지 않아
> D5-2 가 **판정 보류**로 끝났습니다. **관측하지 않은 것은 ❓ 로 남기는 편이 낫습니다.**
>
> rev.1~rev.3 이 쓰던 🚫(차단)·🗄️(소진된 계획) 표기는 **재개 조건이 전부 충족돼 무효**가 됐고 정리에서 걷어냈습니다.
> 본문에 남은 🚫 는 "여기서 중단" 이라는 뜻의 절차 표시입니다.

### 절 번호 참조 규칙

이 문서와 설계 문서의 절 번호가 겹칩니다. 다음과 같이 구분합니다.

| 표기 | 가리키는 곳 |
|---|---|
| `§11`, `§13`, `§18-3`, `§19-5` 처럼 **이 문서에 없는 번호** | [single-canvas-design.md](./single-canvas-design.md) |
| `§2-4`, `§8-3` 처럼 **이 문서에 있는 번호** | 이 문서 |
| **`설계 §7-3`** 처럼 `설계` 를 붙인 것 | 번호가 겹칠 때 설계 문서 쪽 |
| **`이 문서 §7`** | 번호가 겹칠 때 이 문서 쪽 |

> ⚠️ **`§10` 이 겹칩니다.** 이 문서의 §10 은 하위 절(§10-1 ~ §10-3)로 나뉘어 설계 §10-2 와 충돌합니다.
> 접두어 없는 `§10-1` / `§10-2` / `§10-3` 은 **이 문서**이고, 설계 쪽은 전부 `설계 §10-2` 로 명시합니다.
>
> ⚠️ **`D1`~`D9` 도 겹칩니다.** 이 문서의 D1~D9 는 **실기기 검증 항목**이고,
> 설계 §2 의 D1~D9 는 **두 번의 롤백 원인 진단 ID** 입니다. 서로 무관합니다.

## 1. 사전 상태 점검

### 1-1. 저장소 상태 — ⚠️ rev.1 시점(Phase 0A 착수 전)의 기록입니다

원래 표는 *"새 아키텍처 미착수 · 스키마 V3까지 · S4 spike 미구현 · 계측 코드 없음"* 을 적었습니다.
**지금은 전부 사실이 아닙니다** — Phase 0A~3 이 구현됐습니다 (설계 §13). 당시 표는 git 이력에 있습니다.

**그 표에서 지금도 유효한 것만 남깁니다.**

| 사실 | 왜 남기나 | 근거 |
|---|---|---|
| **URL scheme 이 없습니다** (`CFBundleURLTypes` 0건) | 딥링크로 특정 장에 진입할 수 없습니다. 실기기에서 장 지정은 **앱 UI 이동**뿐입니다 (§7-1) | 전 저장소 grep |
| **`UISupportedInterfaceOrientations~ipad` 가 Tuist 기본값(4방향)** 이고 scene manifest / `UIRequiresFullScreen` 키가 없습니다 | 세로 고정이 iPad 에서 적용되지 않습니다. D6(리사이즈·Split View)과 D9-7-4(회전)의 전제 | [InfoPlist.swift:23](../Plugins/ProjectDescriptionHelpers/InfoPlist.swift) |
| **1.2.0 이 실제로 배포됐습니다** (`ver1.2.0` · `ver1.2.1` 태그) | 설계 §10-2 의 절대좌표 데이터가 존재할 개연성 — D8 이 확인 대상으로 삼은 것 | `git tag` |
| **`.xcodeproj` 는 gitignore 대상입니다** | 다른 Mac 에서 처음 열면 `mise x -- tuist generate --no-open` 을 **먼저** 돌려야 합니다. 생략하면 `Cannot find 'DrawingSchemaV4' in scope` 처럼 **자사 코드와 무관해 보이는 컴파일 에러**가 납니다 (D9 세션에서 실제로 겪음) | AGENTS.md |
| **빌드 전 `git status --short` 로 `… 2.swift` 사본 확인** | iCloud 동기화 충돌 사본을 Tuist 의 `sources: "Sources/**"` 글롭이 컴파일 대상으로 잡아 **중복 선언 빌드 실패**를 냅니다 | 실측 |

### 1-2. 도구 실측 — ⚠️ rev.1 시점의 머신 기록입니다

원래 표는 *"설치된 Xcode 는 `/Applications/Xcode-beta.app` 하나뿐 = 27.0 beta"* 로 적었으나,
**실제 실기기 세션(rev.3 · rev.5 이후)은 전부 Xcode 26.3 으로 수행**됐습니다. 그 사이 26.3 이 설치된 것으로 보이나
**언제 어떻게인지는 확인하지 않았습니다** (§10-2 C3). **현재 머신의 실측값은 §6-9 D9-0 입니다.**

**머신이 바뀌어도 다시 확인해야 할 것:**

| 항목 | 기준값 | 확인 |
|---|---|---|
| `xcode-select -p` · `xcodebuild -version` | **Xcode 26.3 (17C529)** — 다른 버전은 빌드되지 않습니다 (AGENTS.md 툴체인 제약) | 머신마다 경로가 다릅니다. **하드코딩 금지** |
| tuist | **4.39.0** — `PATH` 기본값과 다르므로 반드시 `mise x -- tuist …` | `mise x -- tuist version` |
| iPad 시뮬레이터 런타임 | 검증은 **iPad** destination 으로만 (AGENTS.md). iOS 17/18 iPad 런타임은 없어 "저사양 iOS 17 iPad" 리스크는 시뮬레이터로 보완 불가 | `xcrun simctl list devices available` |
| **`sqlite3`** ★ | `/usr/bin/sqlite3` 3.54.0 — `median()` 집계까지 사용 가능. **§6-1 D8 추출의 핵심 도구** | ✅ 실행 확인 |
| **`plutil`** ★ | `/usr/bin/plutil` — `-extract '<공백 포함 키>' raw -o -` 로 바이너리 plist 값을 꺼낼 수 있음 | ✅ 모의 plist 로 실행 확인 |
| `shasum` / `xxd` / `file` / `ditto` / `python3` | 전부 `/usr/bin/` 에 존재 | ✅ `which` 확인 |
| `idevicebackup2` / `ideviceinfo` / `cfgutil` | **미설치.** ⚠️ **필요 없습니다** — 비암호화 백업의 `Manifest.db` 는 평문 SQLite 라 `sqlite3` + 셸만으로 추출이 성립합니다 (§6-1) | ✅ `which` 확인 |

> ⚠️ **`xcode-select` 가 CommandLineTools 를 가리키면 `xcrun devicectl` 이 `unable to find utility` 로 죽습니다.**
> 그 머신에서만 `export DEVELOPER_DIR=<실제 설치된 26.3 경로>/Contents/Developer` 를 씁니다.
> `sudo xcode-select -s` 로 영구 전환하는 것은 **머신 설정 변경**이라 이 런북은 환경변수만 씁니다.

### 1-2-a. ⚠️ TCC — 백업 디렉터리는 기본적으로 **셸에서 읽히지 않습니다** ★ (rev.2)

이 머신에서 실측한 결과입니다.

```
$ ls -la ~/Library/Application\ Support/MobileSync/Backup/
ls: /Users/leetaek/Library/Application Support/MobileSync/Backup/: Operation not permitted

$ test -d ~/Library/Application\ Support/MobileSync/Backup && echo EXISTS
EXISTS
```

✅ **둘 다 이 머신에서 실제로 실행한 결과입니다.**

| 관측 | 해석 |
|---|---|
| `test -d` 는 **성공**, `stat` 도 성공 | 디렉터리는 **존재**합니다 |
| `ls` 는 `Operation not permitted` | **내용 열람이 macOS TCC 로 차단**돼 있습니다. `~/Library/Safari` 도 같은 오류가 나는 것으로 교차 확인했습니다 |

**그러나 `stat` 의 링크수로 비어 있음을 확정할 수 있습니다.** ★

TCC 는 `ls`(디렉터리 내용 열거)를 막지만 `stat`(메타데이터)은 막지 않습니다.
APFS 에서 디렉터리의 링크수는 **2 + 항목 수** 입니다 — 이 머신에서 실측으로 확인했습니다.

```
빈 디렉터리      링크수 2
항목 1개         링크수 3
항목 3개         링크수 5
항목 4개         링크수 6      ← 하위 디렉터리뿐 아니라 파일도 셉니다

$ stat -f "%l" ~/Library/Application\ Support/MobileSync/Backup
2
```

링크수 2 ⇒ 항목 0개 ⇒ 기존 로컬 백업 없음. (백업은 기기 UDID 이름의 하위 디렉터리로 저장됩니다.)
rev.1 시점에는 링크수가 2 였고, 그 뒤 D8 을 위해 백업을 떴습니다.

> **왜 세는가:** **오래된 백업이 남아 있으면 새로 뜬 백업 대신 그것을 추출해
> 낡은 데이터를 fixture 로 만들 위험**이 있습니다. 재추출 전에 반드시 확인하십시오.
> ❓ TCC 하에서 링크수가 항상 신뢰 가능한지는 검증하지 않았습니다.
> FDA 를 부여했다면 `ls` 로 한 번 더 확인하는 편이 확실합니다.

**해소 방법 — 셸에 전체 디스크 접근 권한(Full Disk Access) 부여**

`~/Library/Application Support/MobileSync/Backup/` 은 Apple 이 TCC 로 보호하는 경로입니다.
§6-1 의 추출 스크립트를 돌리려면 **그 스크립트를 실행하는 앱**(Terminal.app / iTerm / Claude Code 등)에
권한을 줘야 합니다.

1. 시스템 설정 → **개인정보 보호 및 보안** → **전체 디스크 접근 권한**
2. 사용할 터미널 앱을 추가하고 토글을 켬
3. **해당 앱을 완전히 종료 후 재실행** (권한은 프로세스 시작 시점에 결정됩니다)
4. 위 `ls` 를 다시 실행해 목록이 나오는지 확인

🚫 이 권한 부여는 **머신 설정 변경**이므로 이 문서는 수행하지 않았습니다. 실행자가 직접 판단하십시오.

**권한을 주고 싶지 않다면 — GUI 경로**

Finder → 사이드바에서 기기 선택 → **일반** 탭 → **백업 관리…** →
목록에서 해당 백업을 **우클릭 → Finder에서 보기**.
이 방법은 FDA 없이도 백업 디렉터리를 열어 주며, 열린 창의 경로를 그대로 스크립트의 `BK` 에 넣으면 됩니다.
🔌 다만 **스크립트 자체는 여전히 그 경로를 읽어야** 하므로, 결국 FDA 가 필요할 가능성이 높습니다.
❓ Finder 로 연 경로에 한해 예외가 적용되는지는 확인하지 못했습니다.

> ⚠️ **`xcode-select` 가 CommandLineTools 를 가리키는 머신에서는 `xcrun devicectl ...` 이
> `unable to find utility "devicectl"` 로 실패합니다.** 그 머신에서만 `DEVELOPER_DIR` 를 붙이십시오 (§1-2).
> ⚠️ **경로를 하드코딩하지 마십시오** — 이 문서의 rev.1 은 `Xcode-beta.app`(27.0) 경로를 적었는데,
> **빌드는 Xcode 26.3 이어야 합니다** (AGENTS.md 툴체인 제약). 실제 설치 경로를 먼저 조회하십시오.

**세션 시작 시 한 번 실행:**

```bash
xcode-select -p                                     # 이미 26.3 이면 아래 export 는 불필요
# export DEVELOPER_DIR=<실제 설치된 Xcode 26.3>/Contents/Developer
cd <저장소 루트>
```

### 1-3. §18(시뮬레이터 기록)과 실기기의 차이 — 재현 시 주의

| 항목 | 설계 §18-3 (시뮬레이터) | 실기기 세션 | 영향 |
|---|---|---|---|
| 툴체인 | Xcode 26.3 | Xcode 26.3 | **같아졌습니다.** ⚠️ 그래도 §7-2 의 "직접 비교 금지" 는 **풀리지 않습니다** — 툴체인은 여섯 이유 중 하나일 뿐이고, 나머지 다섯(메모리 회계·CPU·렌더 파이프라인·메모리 압력·입력 방식)은 시뮬레이터와 실기기의 차이라 그대로 남습니다 |
| OS | 시뮬레이터 iOS 26.2 | iPadOS **27.0 beta** (24A5408d) | OS 쪽 차이가 새로 생겼습니다. **R13(절당 0.5pt)이 정확히 이 차이에서 나왔습니다** — 시뮬레이터 26.2 에서 Δ 0.00 이던 것이 실기기 27.0 에서 0.5pt 였습니다 (§8-7 R14) |

## 2. ⚠️ 데이터 안전 — 실행 전 반드시 읽으십시오

### 2-0. 요약

| | 내용 |
|---|---|
| **되돌릴 수 없는 단계** | **설치(P0-6)** 하나입니다. Debug 빌드는 App Store 판 "새기다" 와 **같은 번들 ID** 를 써서 side-by-side 로 공존하지 않고 **대체**합니다 (§2-1) |
| **D8(백업 추출)은 위험이 없습니다** | Finder 백업을 **읽기만** 합니다. 설치·서명·프로비저닝이 전혀 필요 없습니다 (§6-1) |
| **결론** | ⚠️ **설치 직전에는 매번 §2-4 백업을 뜨십시오.** 컨테이너 보존은 관측됐지만 **1회 관측**이고, prod CloudKit 이 안전망이라는 보장은 **여전히 없습니다** (§2-3 3번) |

### 2-1. Debug 빌드가 App Store 앱과 **같은 번들 ID** 를 씁니다

| 항목 | 값 | 근거 |
|---|---|---|
| Debug / Release 번들 ID | 둘 다 `kr.co.carve.leetaek` — **configuration 별 분기 없음** | `Plugins/ProjectDescriptionHelpers/Target+Templates.swift:111` (`defaultBundleID`) |

즉 **Debug 빌드를 설치하면 iPad 의 App Store 판을 대체합니다.**

### 2-2. 안전하다고 **근거를 가지고** 말할 수 있는 것

| # | 사실 | 근거 |
|---|---|---|
| 1 | Debug 빌드는 로컬 DB 로 **`Carve.dev.sqlite`** 를 씁니다. 실사용 파일 `Carve.sqlite` 를 **열지 않습니다** | `SwiftDataContextProvider.swift:26` — `localDBPath = id.contains("dev") ? "Carve.dev.sqlite" : "Carve.sqlite"` |
| 2 | Debug 빌드의 CloudKit 미러링 대상은 **dev 컨테이너**(`iCloud.Carve.SwiftData.iCloud.dev`). **prod 컨테이너에 쓰지 않습니다** | `App/CarveApp/Project.swift:36` + `SwiftDataContextProvider+Dependency.swift:36` |
| 3 | 따라서 **앱을 실행하는 동안** 실사용 필사 데이터가 덮어써질 경로는 코드상 존재하지 않습니다 | 1·2의 조합 |
| 4 | ✅ **실기기 실증 (rev.3)** — V4 마이그레이션으로 `Carve.dev.sqlite` 는 7.4 → 8.8 MB 로 갱신됐지만 **`Carve.sqlite` 는 변동 없음.** Debug/Release 분리가 설계대로 동작합니다 | §8-1 |

> **앱이 비어 보이는 것은 정상입니다** — 다른 파일(dev DB)을 보고 있는 것이지 데이터가 사라진 게 아닙니다.

### 2-3. 안전하다고 **확인하지 못한** 것 ⚠️

| # | 불확실한 것 | 상태 |
|---|---|---|
| 1 | 개발 서명 빌드를 App Store 서명 앱 위에 설치할 때 iOS 가 기존 데이터 컨테이너를 **보존하는가** | ✅ **보존합니다.** 설치 후 `Carve.sqlite` **11.1 MB (3/23/26)** 가 그대로 있었습니다. ⚠️ **iPad mini / iPadOS 27.0 beta 에서 1회 관측**입니다 — 보장이 아닙니다 |
| 2 | 설치 후에도 컨테이너 안에 `Carve.sqlite` 가 남아 있는가 | ✅ 해소 — 1번과 같은 관측 |
| 3 | prod CloudKit 컨테이너에 **모든** 필사 기록이 실제로 올라가 있는가 | ❓ **여전히 미확인.** 확인 수단이 없습니다 |

> ⚠️ **3번이 §2-4 백업을 계속 필수로 두는 이유입니다.**
> 1번이 해소돼도 **prod CloudKit 이 안전망이라는 보장이 없는 한 로컬 백업이 유일한 안전망**입니다.
> 관측 1건이 정책을 대체하지 않습니다.

### 2-4. 백업 ★

백업은 두 역할을 겸합니다 — **① 설치 전 안전망**(D1~D9 재개 시)이자 **② D8 의 추출 원본**(§6-1). 시점은 항상 다른 모든 단계보다 먼저입니다.

**D8 추출용이라면 비암호화로 떠야 합니다**

| # | 근거 |
|---|---|
| 1 | D8 은 설치를 하지 않으므로, 추출용 백업에서는 "완전 복원 가능성" 을 최우선으로 둘 이유가 없습니다. ⚠️ **설치를 동반하는 세션(D1~D9)에서는 아래 "안전 백업" 문단대로 암호화 백업을 한 벌 더 뜨십시오** |
| 2 | **암호화 백업은 `Manifest.db` 자체가 암호화**돼 `/usr/bin/sqlite3` 로 열리지 않습니다. 비암호화 백업의 `Manifest.db` 는 **평문 SQLite** 라 이 머신의 기본 도구만으로 추출이 끝납니다 (§6-1) |
| 3 | 앱 데이터는 백업에 **기본 포함**됩니다 — 저장소 전체에 `NSURLIsExcludedFromBackupKey` / `isExcludedFromBackup` 이 ✅ **0건**입니다 |

**⚠️ 비암호화 백업의 한계 — 반드시 알고 고르십시오**

비암호화 백업에는 다음이 **포함되지 않습니다**: 키체인(저장된 암호·인증서·Wi-Fi 암호),
건강 데이터, 화면 시간 데이터, 통화 기록 등 Apple 이 암호화 백업에만 넣는 항목들.
→ **이 백업만으로는 기기를 "완전 복원" 할 수 없습니다.**

> **전체 복원용 안전 백업이 따로 필요하면, 암호화 백업을 한 벌 더 뜨십시오.**
> Finder 는 기기당 백업을 하나만 유지하므로, 두 벌을 가지려면 **순서와 이동**이 필요합니다:
>
> 1. 먼저 **암호화** 백업 (안전망)
> 2. `~/Library/Application Support/MobileSync/Backup/<UDID>/` 를 **다른 위치로 옮기거나 이름을 바꿉니다**
> 3. 암호화 체크를 해제하고 **비암호화** 백업 (D8 추출용) → 새 `<UDID>` 디렉터리가 생깁니다
>
> §6-1 의 `BK` 변수는 임의 경로를 받으므로, 옮겨 둔 쪽을 쓰고 싶으면 그 경로를 넣으면 됩니다.
> 🔌 백업 디렉터리를 옮기거나 이름을 바꾼 뒤 Finder 가 어떻게 동작하는지는 확인하지 못했습니다.
> ⚠️ 옮긴 백업도 **기기 전체 데이터**입니다. 보관 위치를 신중히 고르십시오 (§2-5).

**절차 (Finder GUI — macOS 27 기준)** 🔌 *실제로 수행하지 않았습니다. 메뉴 문구는 macOS 버전에 따라 다를 수 있습니다*

1. iPad 를 Mac 에 **케이블로** 연결 (Wi-Fi 동기화보다 안정적입니다)
2. iPad 화면의 **"이 컴퓨터를 신뢰하시겠습니까?"** → **신뢰** → 기기 암호 입력
3. Finder 사이드바 → **위치** 아래 해당 iPad 선택 → **일반** 탭
4. **"iPad의 모든 데이터를 이 Mac에 백업"** 선택
5. ★ **"로컬 백업 암호화" 체크를 해제** — D8 추출을 위해 **반드시** 해제해야 합니다
   - 체크를 해제하려면 **기존에 설정한 백업 암호를 입력**해야 할 수 있습니다
   - 암호를 모르면 §2-4-a 를 보십시오
6. **"지금 백업"** 클릭 → 진행 표시가 사라지고 **"마지막 백업: …"** 문구가 갱신되는 것을 **눈으로 확인**
7. 완료 시각을 §8-1 기록표에 적어 둡니다

### 2-4-a. 비암호화를 고를 수 없는 경우 ❓

Finder 의 **"로컬 백업 암호화"** 체크박스가 **회색으로 비활성**이거나 해제해도 다시 켜진다면,
기기에 **감독(supervision) 또는 MDM 구성 프로파일**이 걸려 암호화 백업이 강제된 상태일 수 있습니다.
(설정 → 일반 → VPN 및 기기 관리 에서 프로파일 존재 여부를 확인할 수 있습니다.)
기존 백업 암호를 분실해 해제하지 못하는 경우도 마찬가지입니다.
— 참고: iOS 는 백업 암호를 "설정 → 일반 → 전송 또는 iPhone/iPad 재설정 → 재설정 → **모든 설정 재설정**" 으로 초기화할 수 있지만,
이는 Wi-Fi·홈 화면 배치 등 **기기 설정 전반을 되돌립니다.** 필사 데이터는 지워지지 않지만 되돌릴 수 없는 변경이므로 신중히 판단하십시오. 🔌 미검증.

**그래도 암호화 백업밖에 못 뜨는 경우:**

암호화 백업은 `Manifest.db` 를 포함한 백업 파일 전체가 **백업 암호에서 파생된 키로 암호화**돼 있어,
`/usr/bin/sqlite3` 로는 열리지 않습니다. 추출하려면 **백업 암호를 알고, 그 암호로 키체인을 풀어
파일을 복호화하는 별도의 도구**가 필요합니다.

> ❓ **이 문서는 그 도구 선택을 다루지 않습니다.**
> 확인하지 못한 도구의 이름을 적으면 그 자체가 잘못된 안내가 되므로, 추측해서 적지 않았습니다.
> 실사용자의 필사 데이터를 다루는 작업이므로 **출처가 불분명한 도구에 백업 암호를 입력하지 마십시오.**
> 비암호화 백업을 뜰 수 있게 만드는 쪽이 거의 항상 더 안전하고 빠릅니다.

**추가 안전 조치 (권장):**

- **legacy 데이터를 가진 기기가 어느 쪽인지는 사용자만 압니다.** 백업 대상 기기를 먼저 정하십시오.
- iCloud 백업도 켜져 있다면 설정 → Apple 계정 → iCloud → iCloud 백업 → **"지금 백업"** 을 추가로 한 번.
  (iCloud 백업은 D8 추출에 쓸 수 없습니다 — 로컬 파일이 없습니다. 순수한 안전망입니다.)

### 2-5. 개인 데이터 취급 — fixture 로 만들 때 ⚠️

D8 이 꺼내는 것은 **사용자 본인의 실제 필사 데이터**입니다.

| 규칙 | 내용 |
|---|---|
| **저장소 커밋 금지** | 추출한 `.sqlite` / `-wal` / `_EXTERNAL_DATA` / 백업 사본을 **git 에 추가하지 마십시오**. `.gitignore` 에 없는 이름이면 `git add .` 한 번에 들어갑니다 |
| **작업 위치** | 저장소 밖. 예: `~/carve-device-dump/<날짜>/` |
| ★ **백업 전체는 훨씬 더 민감합니다** | *(rev.2)* Finder 로컬 백업에는 **기기 전체**(사진·메시지·다른 앱 데이터)가 들어 있습니다. §6-1 의 추출 스크립트는 `AppDomain-kr.co.carve.leetaek` **한 도메인만** 골라 복사하도록 되어 있습니다. **도메인 필터를 넓히지 마십시오.** 백업 원본 자체도 다른 곳에 복사하거나 공유하지 마십시오 |
| **fixture 로 승격할 때** | ① 필요한 **`lineData` 블롭 1~3개만** 골라내고, ② `titleName` / `titleChapter` / `verse` / `creationDate` / `updateDate` 같은 **식별·시각 메타는 버리거나 고정 더미값으로 치환**하고, ③ base64 상수로 테스트 파일에 내장 — §19-4 가 이미 쓴 방식 그대로 |
| **왜 base64 상수인가** | 테스트 타깃에 resource 설정이 없어 파일 추가가 프로젝트 설정 변경을 부르기 때문 (§19-4, AGENTS.md) |
| **필기 내용 자체** | PKDrawing 블롭은 획 좌표이므로 텍스트가 들어 있진 않지만, **어느 절을 언제 필사했는지**는 개인 기록입니다. 커밋 메시지·문서에도 구체 절/날짜를 남기지 마십시오 |
| **정리** | 검증이 끝나면 컨테이너 덤프 원본을 삭제하거나 저장소 밖 암호화 위치로 옮기십시오 |

---

## 3. D1~D8 — 최종 상태

> rev.1~rev.3 은 각 항목의 "실행 가능성" 을 세 번 재분류했습니다 (부분 가능 → 차단(설치 불가) → 해제).
> **D1~D8 이 전부 수행됐거나 절차가 확정된 지금, 그 판정 과정은 이력일 뿐입니다.**
> 결과만 남깁니다. 과정은 `git log -- docs/phase-0a-d-device-test.md` 를 보십시오.

### 3-1. 요약

| ID | 항목 | 결과 | 절차 · 기록 |
|---|---|---|---|
| **D1** | Pencil hover / live stroke | ✅ **완료** — §11 기준 7·8 이 **A ❌ / B ✅** 로 갈려 **스크롤 구조 B 확정** (설계 §12 U4) | §6-7 · §8-3 |
| **D2** | `.pencilOnly` / `anyInput` 스크롤 UX | ✅ **완료** — 기준 9 ✅(A·B) · 기준 10 ✅. 남은 것은 **제품 과제**(발견 가능성) | §6-8 · §8-3 |
| **D3** | 실제 Pencil 지우개로 S1 재확인 | ✅ **완료** — 설계 §20-7. **D9-2 가 단일 Canvas 경로에서 다시 확인** | §6-5 (절차 유효) |
| **D4** | Pencil 더블탭 / 두 손가락 더블탭 | ✅ **완료** — 설계 §20-7. 정상. **D9-3-2 가 단일 Canvas 경로에서 다시 확인** | §6-6 (절차 유효) |
| **D5** | 시편 119편 layout·메모리·프레임 | △ **부분 완료** — memory·CPU baseline 확보. ⚠️ **layout 시간 · hitch time ratio · 기기 B 는 미측정** | §6-2 · **§7-3-a** · §8-4 |
| **D6** | Stage Manager / 리사이즈 / 외부 디스플레이 | ✅ **완료(관측)** — 회전·리사이즈 시 필사 배치가 바뀌거나 잘려 보이고 되돌리면 복구. G4 가 풀려는 문제 그 자체 (설계 §20-7). ⚠️ **iPad Air (M2) 미수행** | §6-4 (절차 유효) |
| **D7** | V4 스키마의 CloudKit 제약 | △ **부분** — 컨테이너 V4 수용 · `.externalStorage` 미러링 · `rowUUID` 정책 · 큐 정상. ❌ **`CD_layoutMetadataData` 서버 스키마 없음**(배포 순서 문제, 설계 §10-1-a). ❓ **미검증 2건은 기기 2대 필요** | §6-3 · §8-3 |
| **D8** | 진짜 legacy `lineData` 추출 | ✅ **완료** (`0e9a8449`) — 실사용 blob 225행에서 fixture 5건 | **§6-1 (절차 보존)** · §8-3 |

> ⚠️ **D3 · D4 · D6 의 "완료" 는 N-Canvas 경로의 결론입니다.** 단일 Canvas 경로에서 같은지는 D9 가 봅니다.

### 3-1-a. 차단 판정의 잔재 — 지금은 무효

rev.2 는 *"`Carve.entitlements` 의 CloudKit entitlement 가 유료 멤버십 전용이라 무료 Personal Team 으로는
서명되지 않는다"* 를 근거로 D1~D6 · D7-pre 를 차단했습니다. **유료 멤버십에서 서명·설치·동작이 실증돼
차단은 전부 풀렸습니다** (§8-1).

⚠️ 다만 **가설 자체(무료 팀에서 거부되는가)는 실증되지 않았습니다** — 무료 팀으로 시도한 적이 없습니다 (§10-2 C1).
판정에 더 이상 영향을 주지 않으므로 참고로만 둡니다.

### 3-2. 저장소 근거 — 지금도 유효한 것

> 원래 이 절은 D1~D7-pre 각각의 저장소 근거를 길게 적었습니다. **대부분은 Phase 0A 착수 전 코드 기준이라
> 낡았습니다.** 아래 셋만 지금도 유효합니다.

| 항목 | 사실 |
|---|---|
| **D6 의 값** | `InfoPlist.swift:23` 이 세로 고정 단일 값이고 `UIApplicationSceneManifest` / `UISupportsMultipleScenes` / `UIRequiresFullScreen` 키가 **하나도 없습니다.** 이 조합에서 iPadOS 가 앱을 어떻게 리사이즈하는지가 **§11 기준 3(Split View resize)이 애초에 적용 가능한 기준인지**를 결정합니다 |
| **D8 의 성립 근거 ★** | 기기의 `Carve.sqlite` 가 이미 V3 로 마이그레이션됐어도 괜찮습니다. `DrawingDataMigrationPlan.swift` 의 V1→V2 커스텀 스테이지가 `new.lineData = old.lineData` 로 **블롭을 바이트 그대로** 옮기므로, V3 저장소 안에도 **1.2.0 시절 PencilKit 인코딩의 블롭**이 남아 있습니다 |
| **D8 의 비가역성** | 기기 초기화·앱 삭제·재마이그레이션이 일어나면 **1.2.0 시절 인코딩 원본이 사라집니다.** 이미 추출했으므로(§8-3) 지금은 해소됐지만, 재추출이 필요해지면 이 조건이 다시 걸립니다 |

---

## 4. 실행 순서

> rev.2·rev.3 이 두던 하위 실행 순서표("지금은 D8 하나뿐" · "재결제 이후로 이월" · "재분류가 후속 Phase 에 주는 영향")는
> **전부 소진돼 지웠습니다** — D8 은 완료됐고, 이월 항목도 실행됐습니다. 지금 따라야 할 순서는 아래 하나입니다.

| 순서 | 항목 | 이걸 하면 풀리는 것 | 비고 |
|---:|---|---|---|
| **0** | **★ D9 — 단일 Canvas 실기기 검증 (§6-9)** | **flag 기본 활성화·Phase 4 의 선행 조건.** 설계 §8 저장 경로 · §14 14·16·17 · §11 기준 2·5 · §20-11 롱프레스 | **진행 중.** 남은 것은 D9-3 나머지 · D9-4 · D9-5 · D9-7 · D9-8 · D9-CK③ 과 **D9 H 잔여 검증**(§8-7) |
| **1** | **D7 나머지** — CloudKit 미러링 (§6-3) | Phase 1 배포 판단 | ⚠️ **기기 2대가 필요**하므로 D9 와 별도 세션. 스키마 승격(②③)만 D9-CK 로 선행 |
| **2** | **iPad Air (M2)** — D5-5 · D6 | 기기 간 유의차 (설계 §13 사각지대) | D9 통과 후 |

> ⚠️ **D5 baseline 의 비가역성은 실현되지 않았습니다** — Phase 2 착수 **전에** 쟀습니다 (§8-4 · 설계 §18-3-a).

---

## 5. P0 — 공통 준비

> P0-2 ~ P0-7 은 **전부 수행돼 성공**했습니다.
>
> | 단계 | 결과 |
> |---|---|
> | P0-3 Signing | ✅ 유료 멤버십 활성 상태에서 CloudKit entitlement 포함해 서명됨 |
> | P0-5 빌드 | ✅ 성공 — ❓ CLI 인지 Xcode GUI 인지는 **미기록** (§10-3 3번) |
> | P0-6 설치 | ✅ 성공. `Carve.sqlite` **11.1 MB 보존** (§2-3 1번) |
> | P0-7 실행 | ✅ 성공. V4 마이그레이션 완료, 크래시 없음 |
>
> ⚠️ **P0-6 은 여전히 되돌릴 수 없는 단계입니다.** 컨테이너 보존은 **관측 1건**이지 보장이 아닙니다.
> **다음 설치 전에도 §2-4 백업을 뜨십시오.**
>
> **D8(§6-1)만 하려면 P0-0 · P0-1 두 개면 충분합니다** — 기기 연결도 빌드도 필요 없습니다.

### P0-0. ⚠️ 백업 (§2-4) — 먼저 하십시오

완료 전에는 아래 어떤 단계도 실행하지 마십시오. 설치를 동반하는 세션이면 **안전망(암호화)**,
D8 추출이면 **비암호화**입니다 (§2-4).

### P0-1. 툴체인 고정

```bash
# xcode-select 가 26.3 을 가리키지 않는 머신에서만 (§1-2)
# export DEVELOPER_DIR=<실제 설치된 Xcode 26.3>/Contents/Developer
cd <저장소 루트>
git status --short          # "… 2.swift" 중복 사본이 없어야 함 (§1-1)
xcodebuild -version         # Xcode 26.3 / 17C529
mise x -- tuist version     # 4.39.0
```

### P0-2. 프로젝트 생성 (필요 시) — D8 에는 불필요

`Carve.xcworkspace` 가 이미 있습니다. 재생성이 필요하면:

```bash
mise x -- tuist install
mise x -- tuist generate
```

> ❗ `tuist generate` 는 프로젝트 파일을 다시 씁니다. **`Project.swift` / signing 설정은 건드리지 마십시오.**

### P0-3. Signing — Xcode GUI 에서 **확인만** ⚠️ 변경 금지

`App/CarveApp/Project.swift:22` 에 이미 다음이 들어 있습니다.

```
.automaticCodeSigning(devTeam: "H4MSW7FUBB")
```

즉 자동 서명 + 팀 `H4MSW7FUBB` 가 **이미 설정돼 있습니다.** 별도 설정이 필요 없을 가능성이 높습니다.

**확인 절차 (GUI):**

1. `open Carve.xcworkspace`
2. 좌측 네비게이터 → **CarveApp** 프로젝트 → **CarveApp** 타깃 → **Signing & Capabilities** 탭
3. **Debug** 를 선택
4. 다음을 **눈으로 확인만** 합니다
   - `Automatically manage signing` 체크됨
   - `Team` 이 본인 개발자 계정으로 잡혀 있음
   - `Bundle Identifier` = `kr.co.carve.leetaek`
   - `iCloud` capability 에 `iCloud.Carve.SwiftData.iCloud` / `…​.dev` 두 컨테이너
5. **Team 이 비어 있거나 오류가 나는 경우에만** 드롭다운에서 본인 팀을 선택합니다.
   Xcode → Settings → Accounts 에 Apple 계정이 없으면 먼저 추가합니다.

> ⚠️ **`Project.swift` 나 `Carve.entitlements` 를 편집하지 마십시오** (AGENTS.md: signing/build setting 변경 금지).
> Xcode GUI 에서 팀을 고르는 것은 생성된 `.xcodeproj` 에만 반영되며 `tuist generate` 로 되돌아갑니다.
> 그래도 되돌아가면 GUI 에서 다시 고르십시오 — 저장소 파일을 고치는 쪽으로 해결하지 마십시오.

**기기 신뢰:**

- iPad 를 연결하고 iPad 화면의 **"이 컴퓨터를 신뢰하시겠습니까?"** 에서 신뢰
- iPad 설정 → 개인정보 보호 및 보안 → **개발자 모드** 켜기 (재부팅 필요)
- 🔌 개발자 모드 항목은 Xcode 가 기기를 한 번 인식한 뒤에 나타납니다

### P0-4. 기기 인식 확인 — D8 에는 불필요

> D8 은 **이미 만들어진 백업 파일**만 읽습니다. 기기를 연결할 필요도, `devicectl` 이 기기를 볼 필요도 없습니다.
> (백업을 뜰 때만 케이블 연결이 필요하고, 그건 Finder 가 합니다.)

```bash
xcrun devicectl list devices
```

✅ 명령 실행 확인 (현재는 시뮬레이터만 나옵니다).
🔌 iPad 를 연결하면 `Reality` 열이 `physical` 인 행이 추가됩니다. 그 행의 **Identifier(UUID)** 를 아래에서 씁니다.

```bash
# 나중에 쓰기 편하게 변수로
DEV="<위에서 확인한 Identifier 또는 기기 이름>"
```

**대안 (GUI):** Xcode → **Window > Devices and Simulators** → Devices 탭.

### P0-5. 실기기용 빌드

```bash
DD=~/carve-build/device
xcodebuild build \
  -workspace Carve.xcworkspace \
  -scheme CarveApp \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DD" \
  -allowProvisioningUpdates
```

- ✅ `-destination 'generic/platform=iOS'` 가 CarveApp 스킴에서 유효한 destination 임을 `xcodebuild -showdestinations` 로 확인했습니다 (`name:Any iOS Device`).
- 🔌 **빌드 성공 여부는 미검증**입니다 (이 문서는 빌드를 실행하지 않았습니다).
- `-allowProvisioningUpdates` 는 명령줄 플래그이며 저장소 설정을 바꾸지 않습니다.
- 산출물 예상 경로: `$DD/Build/Products/Debug-iphoneos/CarveApp.app`

> **`-derivedDataPath` 를 저장소 안으로 잡지 마십시오.**
> ✅ 확인: `.gitignore` 에는 `build/` · `DerivedData/` · `Derived/` · `Tuist/.build/` 만 있습니다.
> `./.build-device` 같은 이름은 **추적 대상이 됩니다.** 위처럼 저장소 밖(`~/carve-build/device`)을 쓰십시오.

**대안 (GUI):** Xcode 에서 상단 destination 을 연결된 iPad 로 바꾸고 `⌘R`. 서명 문제를 대화형으로 해결하기에는 GUI 가 편합니다.

### P0-6. ⚠️ 설치 — 되돌릴 수 없는 단계

> ⚠️ **직전에 §2-4 백업을 다시 뜨십시오.** §2-1 · §2-3 의 경고가 여기서 발동합니다.
> **D8(§6-1)은 이 단계를 통과하지 않습니다** — 백업에서 읽으므로 필요가 없습니다.

```bash
xcrun devicectl device install app --device "$DEV" \
  "$DD"/Build/Products/Debug-iphoneos/CarveApp.app
```

✅ 하위 명령·인자 형태 확인 (`devicectl device install app [<options>] --device <...> <path>`).
🔌 실행 결과 미검증.

**설치 직후 확인 (앱을 실행하기 전에):**

```bash
xcrun devicectl device info apps --device "$DEV" \
  --bundle-id kr.co.carve.leetaek \
  --include-container-paths
```

✅ `--bundle-id` / `--include-container-paths` / `--require-container-access` 옵션 존재 확인.

> ⚠️ **`devicectl` 의 컨테이너 접근 조건** — *"Third-party (not system app) / Installed via Xcode (profile validated) / Not enterprise signed."*
> 즉 **App Store 로 설치된 앱의 컨테이너는 내려받을 수 없습니다.** 이것이 D8 을 백업 경로로 바꾼 이유입니다 (§6-1-0).
> 개발 서명으로 설치한 뒤 만든 `Carve.dev.sqlite` 는 조건을 만족하므로 D3 등에서는 이 경로가 유효합니다.

### P0-7. 실행

```bash
xcrun devicectl device process launch --device "$DEV" \
  --terminate-existing kr.co.carve.leetaek
```

✅ 하위 명령·옵션 확인. 🔌 결과 미검증.

> **앱이 비어 보이는 것은 정상입니다.** Debug 빌드는 `Carve.dev.sqlite` 를 새로 만들고 dev CloudKit 컨테이너를 봅니다.
> 실사용 데이터가 사라진 것이 아니라 **다른 파일을 보고 있는 것**입니다 (§2-2 1·2번).

---

## 6. 항목별 런북

각 항목은 **준비 → 실행 → 판정 → 기록** 순서입니다. 기록표는 §8 에 모아 뒀습니다.

> | 절 | 상태 |
> |---|---|
> | §6-1 D8 | ✅ 완료. **절차는 재추출용으로 보존** |
> | §6-2 D5 | △ 부분 완료 — ⚠️ **이 절의 절차 그대로 하지 않았습니다.** 실제로 쓴 방법은 **§7-3-a**, 결과는 §8-4 |
> | §6-3 D7-pre | ⏳ 미수행 — 절차 유효 |
> | §6-4 D6 / §6-5 D3 / §6-6 D4 | ✅ 완료 (설계 §20-7) — 절차는 **iPad Air 재수행·재확인용으로 유효** |
> | §6-7 D1 / §6-8 D2 | ✅ 완료 — ⚠️ **이 절의 절차 그대로 하지 않았습니다.** **S4 하네스를 실기기에서 돌렸습니다** (§8-3) |
> | **§6-9 D9** | ★ **진행 중 — 지금 살아 있는 절차** |

---

### 6-1. D8 — 진짜 legacy `lineData` 추출 ✅ **완료** (절차는 재추출용으로 보존)

**푸는 것:** S5 fixture → Phase 0B 회귀 판정 기준. **결과는 §8-3 · 설계 §20-3.**

#### 6-1-0. ⚠️ 함정 — `devicectl` 경로는 성립하지 않습니다

`devicectl device copy from` 과 Xcode *Download Container…* 는 **개발 서명으로 설치된 앱**의 컨테이너만 봅니다
(*Third-party / Installed via Xcode (profile validated) / Not enterprise signed*). D8 이 꺼내려는 것은
**App Store 판이 쌓아 온 실사용 데이터**이므로 애초에 대상 밖입니다. 개발 빌드를 덮어 설치해 조건을 만들면
그 순간 App Store 설치 상태가 파괴되므로 우회도 못 됩니다.

**→ 성립하는 유일한 경로: Finder 로컬 백업에서 파일을 꺼낸다.** 기기에 **쓰지 않고**, 설치도 서명도 필요 없으며,
되돌릴 수 없는 단계가 하나도 없습니다. 필요한 도구(`/usr/bin/sqlite3` · `/usr/bin/plutil`)는 이미 있습니다 (§1-2).

---

#### 준비

**(1) §2-4 의 비암호화 Finder 백업 완료** ⚠️

⚠️ **암호화 백업이면 이 절차 전체가 동작하지 않습니다.** `Manifest.db` 가 암호화돼 `sqlite3` 로 열리지 않습니다.
암호화를 해제할 수 없는 경우의 선택지는 §2-4-a 를 보십시오.

**(2) §1-2-a 전체 디스크 접근 권한(FDA)**

✅ 이 머신에서 실측한 바로, FDA 없이는 백업 디렉터리를 **열거할 수 없습니다**:

```
ls: /Users/leetaek/Library/Application Support/MobileSync/Backup/: Operation not permitted
```

터미널 앱에 FDA 를 주고 **앱을 완전히 종료 후 재실행**하십시오 (§1-2-a).

**(3) 작업 변수와 디렉터리 — 저장소 밖**

```bash
BKROOT="$HOME/Library/Application Support/MobileSync/Backup"
OUT="$HOME/carve-device-dump/$(date +%Y%m%d)"
APPDOMAIN="AppDomain-kr.co.carve.leetaek"
mkdir -p "$OUT"
echo "OUT=$OUT"
```

✅ `mkdir -p` / `date +%Y%m%d` 확인. ⚠️ **`$OUT` 을 저장소 안으로 잡지 마십시오** (§2-5).
✅ 번들 ID `kr.co.carve.leetaek` 은 Debug/Release 동일하며 configuration 분기가 없음을 확인했습니다
(`Target+Templates.swift:111`). 따라서 앱 도메인은 위 하나뿐입니다.

---

#### 실행

**1단계 — 백업 디렉터리 찾기**

```bash
ls -1 "$BKROOT"
```

🔌 기기 UDID 형태의 디렉터리가 하나 이상 나옵니다.
(형식은 기기·iOS 버전에 따라 40자 hex 이거나 `########-################` 형태일 수 있습니다.)

**어느 것이 어느 기기인지 확인:**

```bash
for d in "$BKROOT"/*/; do
  echo "=== $d"
  for k in 'Device Name' 'Product Type' 'Product Version' 'Last Backup Date'; do
    printf '  %-18s ' "$k"
    /usr/bin/plutil -extract "$k" raw -o - "$d/Info.plist" 2>/dev/null || echo '(없음)'
  done
done
```

✅ `plutil -extract '<공백 포함 키>' raw -o -` 가 바이너리 plist 에서 값을 꺼내는 것을
**모의 `Info.plist` 를 만들어 이 머신에서 실행 확인**했습니다 (한글 기기 이름 포함).
🔌 실제 백업의 `Info.plist` 에 위 네 키가 모두 있는지는 백업이 있어야 확인됩니다.

**대상 백업을 변수에 고정:**

```bash
BK="$BKROOT/<위에서 고른 UDID 디렉터리>"
ls -1 "$BK" | head
```

🔌 `Info.plist` · `Manifest.db` · `Manifest.plist` · `Status.plist` 와 2자리 hex 디렉터리들이 보이면 정상입니다.

---

**2단계 — 비암호화 백업인지 반드시 확인 (여기서 갈립니다)**

```bash
/usr/bin/plutil -extract IsEncrypted raw -o - "$BK/Manifest.plist"
/usr/bin/file "$BK/Manifest.db"
```

✅ 두 명령 모두 모의 백업으로 이 머신에서 실행 확인했습니다.

| 관측 | 의미 | 다음 |
|---|---|---|
| `false` + `SQLite 3.x database` | ✅ **비암호화.** 진행합니다 | 3단계 |
| `true` + `data` | 🚫 **암호화 백업.** `sqlite3` 로 열 수 없습니다 | §2-4-a — 비암호화로 다시 뜨십시오 |

> ⚠️ **`sqlite3 "$BK/Manifest.db" ".tables"` 로 판별하지 마십시오.**
> ✅ 실측: 암호화된(=SQLite 가 아닌) 파일에도 `.tables` 는 **종료 코드 0** 으로 조용히 빠져나옵니다.
> 실제 `SELECT` 를 던져야 `file is not a database (26)` 이 납니다. **`file(1)` 로 판별하는 편이 확실합니다.**

---

**3단계 — `Manifest.db` 에서 앱 파일 목록 조회 (읽기 전용)**

백업의 `Files` 테이블 구조 — 🔌 실제 백업에서 `.schema Files` 로 확인하십시오:

```bash
/usr/bin/sqlite3 -readonly "$BK/Manifest.db" ".schema Files"
```

> 🔌 `-readonly` 가 `unable to open database file (14)` 로 실패하면, `Manifest.db` 가 WAL 모드인데
> `-shm` 이 없는 경우입니다. 그때는 **`Manifest.db` 를 작업 위치로 복사한 뒤** 사본을 여십시오 —
> 백업 원본을 쓰기 가능하게 열지 마십시오.
> ```bash
> cp -p "$BK/Manifest.db" "$OUT/Manifest.db.copy"
> /usr/bin/sqlite3 "$OUT/Manifest.db.copy" ".schema Files"
> ```
> ❓ 실제 백업의 `Manifest.db` 가 WAL 모드인지는 확인하지 못했습니다.

이 문서가 전제하는 형태 (❓ 실제 백업으로 검증하지 못했으므로 다르면 아래 쿼리를 맞추십시오):

| 컬럼 | 뜻 |
|---|---|
| `fileID` | SHA-1 해시 문자열. **실제 파일의 저장 이름** |
| `domain` | `AppDomain-kr.co.carve.leetaek` 등 |
| `relativePath` | 도메인 루트 기준 원래 경로 (`Library/Application Support/Carve.sqlite`) |
| `flags` | `1` = 파일, `2` = 디렉터리 (🔌 확인 필요) |
| `file` | 메타데이터 바이너리 plist (크기·권한 등). **이 절차에서는 쓰지 않습니다** |

**(3-a) 앱 도메인이 백업에 있는지:**

```bash
/usr/bin/sqlite3 -readonly "$BK/Manifest.db" \
  "SELECT domain, COUNT(*) FROM Files WHERE domain LIKE '%carve%' GROUP BY domain;"
```

✅ 쿼리 문법을 모의 `Manifest.db` 로 실행 확인.
🔌 `AppDomain-kr.co.carve.leetaek` 이 나와야 합니다. 아무것도 안 나오면 **그 백업에 앱 데이터가 없습니다** → 판정 D8-1 실패.

**(3-b) `Library/Application Support` 아래에 무엇이 있는지:**

```bash
/usr/bin/sqlite3 -readonly -header -column "$BK/Manifest.db" \
  "SELECT flags, substr(fileID,1,2) || '/' || fileID AS stored_at, relativePath
     FROM Files
    WHERE domain = '$APPDOMAIN'
      AND relativePath LIKE 'Library/Application Support%'
    ORDER BY relativePath;"
```

✅ `substr(fileID,1,2) || '/' || fileID` 로 **해시 경로를 복원하는 식**을 모의 DB 로 실행 확인했습니다.
실제 파일은 `<백업루트>/<fileID 앞 2자리>/<fileID>` 에 있습니다.

**여기서 1차 판정을 합니다:**

| 관측 | 의미 |
|---|---|
| `Library/Application Support/Carve.sqlite` 가 **보인다** | ✅ 실사용 DB 가 백업에 있습니다. 4단계로 |
| `Carve.dev.sqlite` **만** 보인다 | ⚠️ Debug 빌드 흔적만 있습니다. legacy 실사용 데이터가 아닙니다 |
| 아무것도 없다 | ❌ 이 백업에는 앱 데이터가 없습니다. 다른 기기의 백업을 확인하십시오 |

> ✅ **왜 `Carve.sqlite` 인가 (`Carve.dev.sqlite` 가 아니라):**
> `SwiftDataContextProvider.swift:26` 이
> `localDBPath = id.contains("dev") ? "Carve.dev.sqlite" : "Carve.sqlite"` 입니다.
> App Store 판은 Release configuration 이고 `CLOUDKIT_CONTAINER_ID` 가
> `iCloud.Carve.SwiftData.iCloud` (`Project.swift:40`, `dev` 없음) 이므로 **`Carve.sqlite`** 입니다.
>
> ✅ **왜 경로가 `Library/Application Support/` 인가:**
> `SwiftDataContextProvider+Dependency.swift:29` 가 `URL.applicationSupportDirectory` 를 씁니다.

---

**4단계 — 추출 스크립트 (해시 경로 → 원래 트리 복원)**

> ★ **`Carve.sqlite` 파일 하나만 뽑으면 안 됩니다.**
> - `lineData` 는 `@Attribute(.externalStorage)` 입니다 (`DrawingSchemaV3.swift:35`).
>   큰 블롭은 sqlite **바깥**의 `.Carve.sqlite_SUPPORT/_EXTERNAL_DATA/` 에 별도 파일로 나갑니다.
>   `BiblePageDrawing.fullLineData` 도 마찬가지입니다 (`DrawingSchemaV3.swift:79-80`).
> - `-wal` 이 없으면 **가장 최근 필사가 통째로 빠질 수 있습니다.**
> - ✅ **실측한 근거:** WAL 모드 DB 를 본체만 복사한 뒤 `sqlite3 -readonly` 로 열면
>   `unable to open database file (14)` 로 **실패**합니다. `-shm`/`-wal` 이 함께 있어야 열립니다.
>
> **→ `Library/Application Support/` 아래를 통째로 복원하십시오.**

아래를 **한 덩어리로** 붙여 넣습니다. 스크립트를 저장소 밖(`~/carve-device-dump/extract.sh`)에 쓴 뒤
`bash` 로 실행하는 형태입니다.

> ★ **왜 파일로 쓰고 `bash` 로 돌리는가 (대화형 셸에 직접 붙여 넣지 않고):**
> ① 이 스크립트는 프로세스 치환 `< <(...)` 과 `${var:0:2}` 를 씁니다. `bash` 로 명시 실행하면
> 사용자의 zsh 설정(예: `interactive_comments` 미설정)에 흔들리지 않습니다.
> ② `exit` 을 써도 **사용자의 터미널 세션이 죽지 않습니다.**
> ③ 히어독 구분자를 `'SCRIPT'` 로 **따옴표** 처리해, 붙여 넣는 시점에 `$` 나 백틱이 전개되지 않습니다.
> ⚠️ 스크립트 파일은 `~/carve-device-dump/` — **저장소 밖**에 만들어집니다. 저장소 안에 두지 마십시오.

```bash
mkdir -p ~/carve-device-dump
cat > ~/carve-device-dump/extract.sh <<'SCRIPT'
#!/bin/bash
# 사용법: bash extract.sh <백업디렉터리> <출력디렉터리> <앱도메인>
BK="$1"; OUT="$2"; APPDOMAIN="$3"

[ -f "$BK/Manifest.db" ] || { echo "!! Manifest.db 가 없습니다: $BK"; exit 1; }
/usr/bin/file "$BK/Manifest.db" | grep -q 'SQLite' || {
  echo "!! Manifest.db 가 SQLite 가 아닙니다 → 암호화 백업입니다. 문서 §2-4-a 를 보십시오."; exit 1; }

n_file=0; n_dir=0; n_miss=0
while IFS=$'\t' read -r flags fileID rel; do
  [ -z "$fileID" ] && continue
  dst="$OUT/$rel"
  if [ "$flags" = "2" ]; then
    mkdir -p "$dst"; n_dir=$((n_dir+1)); continue
  fi
  src="$BK/${fileID:0:2}/$fileID"
  if [ -f "$src" ]; then
    mkdir -p "$(dirname "$dst")"
    cp -p "$src" "$dst"
    n_file=$((n_file+1))
  else
    echo "  [MISSING] $rel   <- $src"
    n_miss=$((n_miss+1))
  fi
done < <(/usr/bin/sqlite3 -readonly -separator $'\t' "$BK/Manifest.db" \
  "SELECT flags, fileID, relativePath
     FROM Files
    WHERE domain = '$APPDOMAIN'
      AND relativePath LIKE 'Library/Application Support%'
    ORDER BY flags DESC, relativePath;")

echo "복사: 파일 $n_file · 디렉터리 $n_dir · 누락 $n_miss"
echo "위치: $OUT"
if [ "$n_miss" -gt 0 ]; then
  echo "!! 누락이 있습니다 → 백업이 불완전합니다. 백업을 다시 뜨십시오."
  exit 2
fi
SCRIPT

bash ~/carve-device-dump/extract.sh "$BK" "$OUT" "$APPDOMAIN"
```

✅ **이 블록을 그대로 실행해 다음 네 경우를 모두 확인했습니다** (모의 백업 트리 사용, `bash` 와 `zsh` 양쪽):

| 시나리오 | 결과 | 종료 코드 |
|---|---|---|
| 정상 (공백 든 `Application Support` 경로 + 중첩 `_EXTERNAL_DATA` 포함) | `복사: 파일 3 · 디렉터리 1 · 누락 0` | `0` |
| `Manifest.db` 가 암호화(SQLite 아님) | 암호화 경고 후 중단 | `1` |
| 해시 파일 하나 누락 | `[MISSING]` 출력 + 불완전 경고 | `2` |
| `Manifest.db` 자체가 없음 | 경로 오류 메시지 | `1` |

**스크립트가 하는 일 / 주의점**

| 항목 | 설명 |
|---|---|
| `flags DESC` 정렬 | 디렉터리(2)를 파일(1)보다 먼저 만들어 순서 문제를 없앱니다 |
| `IFS=$'\t'` + `-separator $'\t'` | `Application Support` 처럼 **경로에 공백이 있어도** 안전하게 나눕니다 |
| `${fileID:0:2}` | 해시 앞 2자리 = 백업 안의 하위 디렉터리 이름 |
| `cp -p` | 타임스탬프를 보존합니다 (D8-5 판정에 도움) |
| `-readonly` | `Manifest.db` 를 **변형하지 않습니다.** 백업 원본은 그대로 남습니다 |
| `[MISSING]` / 종료 코드 2 | `Manifest.db` 에는 있는데 실물 파일이 없는 경우. **하나라도 나오면 백업이 불완전**하니 다시 뜨십시오 |
| ⚠️ **도메인 필터를 넓히지 마십시오** | `LIKE '%carve%'` 같은 느슨한 조건이나 `domain` 조건 제거는 **기기 전체(사진·메시지)를 복사**합니다 (§2-5) |

> 🔌 **`flags` 값의 의미(1=파일 / 2=디렉터리)는 실제 백업으로 확인하지 못했습니다.**
> 3-b 출력에서 `Library/Application Support` 처럼 **확장자 없는 상위 경로**의 `flags` 값을 보고,
> 그 값이 2가 아니면 스크립트의 `"2"` 를 실제 값으로 바꾸십시오.
> 잘못돼도 위험하지는 않습니다 — 디렉터리를 파일로 복사하려다 `[MISSING]` 이 뜰 뿐입니다.

**결과 확인:**

```bash
find "$OUT" -type f | sed "s|$OUT|OUT|" | sort
du -sh "$OUT"
```

🔌 최소한 다음이 보여야 합니다:

```
OUT/Library/Application Support/Carve.sqlite
OUT/Library/Application Support/Carve.sqlite-shm      (있을 수도, 없을 수도)
OUT/Library/Application Support/Carve.sqlite-wal      (있을 수도, 없을 수도)
OUT/Library/Application Support/.Carve.sqlite_SUPPORT/_EXTERNAL_DATA/...   (블롭이 클 때만)
```

> ❓ **`-shm` / `-wal` 이 백업에 포함되는지는 확인하지 못했습니다.**
> `-shm` 은 스크래치 파일이라 백업에서 빠질 수 있습니다. 없더라도 5단계의 **작업 사본** 방식이면 문제없습니다.
> ❓ `_EXTERNAL_DATA` 가 안 보이는 것은 **오류가 아닐 수 있습니다** — 블롭이 전부 임계값 아래라
> sqlite 안에 인라인으로 들어간 경우입니다. 5단계에서 실제 블롭 길이를 보고 판단하십시오.

---

**5단계 — 추출물 검증**

⚠️ **4단계의 추출물을 직접 열지 말고, 그 사본을 하나 더 만들어 그 위에서 조회하십시오.**
WAL 이 남아 있으면 sqlite 가 열면서 체크포인트를 수행해 **파일을 변형**합니다.
4단계 추출물은 "백업에서 꺼낸 그대로" 로 보존하는 편이 안전합니다.

```bash
WORK="$OUT/_work"
mkdir -p "$WORK"
cp -Rp "$OUT/Library/Application Support/." "$WORK/"
DB="$WORK/Carve.sqlite"
ls -la "$WORK"
```

✅ `cp -Rp` 로 트리를 복사하는 형태 확인.

> ★ **왜 아래 쿼리에 `-readonly` 를 쓰지 않는가 — 실측 근거가 있습니다.**
> ✅ WAL 모드 DB 를 `-shm` 없이 열면 `sqlite3 -readonly` 는
> `unable to open database file (14)` 로 **실패**합니다. 같은 파일을 쓰기 가능하게 열면 성공합니다
> (sqlite 가 `-shm` 을 새로 만듭니다). `-shm` 이 백업에 포함되는지는 ❓ 확인하지 못했으므로,
> **버려도 되는 사본 위에서 쓰기 가능하게 여는 것**이 가장 확실합니다.
> 그래서 4단계 추출물과 5단계 작업 사본을 분리했습니다.
>
> `-readonly` 를 꼭 쓰고 싶다면 `file:"$DB"?immutable=1` 도 동작합니다 (✅ 실행 확인).
> ⚠️ 단 `immutable=1` 은 **WAL 을 무시**하므로, `-wal` 에 미체크포인트 내용이 있으면
> **가장 최근 필사가 빠진 상태**를 보게 됩니다. 이 목적에는 권하지 않습니다.

**(5-a) 먼저 스키마를 확인합니다 — 테이블·컬럼명을 추측하지 마십시오**

```bash
/usr/bin/sqlite3 "$DB" ".tables"
/usr/bin/sqlite3 "$DB" ".schema ZBIBLEDRAWING"
```

✅ `.tables` / `.schema <table>` 동작을 모의 DB 로 확인.

> ⚠️ **아래 (5-b)~(5-e) 의 `ZBIBLEDRAWING` · `ZLINEDATA` 등은 Core Data 명명 규칙에서 온 추정입니다.**
> §18-3 이 `length(ZLINEDATA)` 를 이미 쓴 것으로 미루어 이 형태일 가능성이 높지만,
> **이 문서에서 실제 DB 로 검증하지는 못했습니다.**
> `.tables` 출력에 맞춰 이름을 고쳐 쓰십시오. 모델은 `BibleDrawing` / `BiblePageDrawing` 두 개이므로
> (`DrawingSchemaV3.swift:22`, `:70`) 대응 테이블도 두 개일 것으로 예상합니다.

**(5-b) 행 수와 블롭 유무**

```bash
/usr/bin/sqlite3 -header -column "$DB" "
SELECT COUNT(*)                       AS rows_all,
       SUM(ZLINEDATA IS NULL)         AS null_blob,
       SUM(LENGTH(ZLINEDATA) = 0)     AS zero_len
  FROM ZBIBLEDRAWING;"
```

**(5-c) `ZLINEDATA` 길이 분포**

```bash
/usr/bin/sqlite3 -header -column "$DB" "
SELECT MIN(LENGTH(ZLINEDATA))    AS min_len,
       median(LENGTH(ZLINEDATA)) AS median_len,
       MAX(LENGTH(ZLINEDATA))    AS max_len,
       COUNT(*)                  AS n
  FROM ZBIBLEDRAWING
 WHERE ZLINEDATA IS NOT NULL;"
```

✅ `median()` 이 이 머신의 sqlite **3.54.0** 에서 동작함을 확인했습니다.
다른 환경에서 없다면 아래로 대체하십시오 (✅ 이것도 실행 확인):

```bash
/usr/bin/sqlite3 "$DB" "
SELECT LENGTH(ZLINEDATA) FROM ZBIBLEDRAWING WHERE ZLINEDATA IS NOT NULL
 ORDER BY LENGTH(ZLINEDATA)
 LIMIT 1 OFFSET (SELECT COUNT(*)/2 FROM ZBIBLEDRAWING WHERE ZLINEDATA IS NOT NULL);"
```

**(5-d) `ZDRAWINGVERSION` 분포** — legacy 여부의 핵심 신호

```bash
/usr/bin/sqlite3 -header -column "$DB" "
SELECT IFNULL(ZDRAWINGVERSION, '(null)') AS drawing_version, COUNT(*) AS n
  FROM ZBIBLEDRAWING
 GROUP BY ZDRAWINGVERSION
 ORDER BY 1;"
```

✅ `IFNULL` 로 NULL 을 표시하는 형태까지 실행 확인.
`DrawingSchemaV3.swift:33` 의 기본값이 `1` 이므로 **`1` 또는 `NULL` 인 행이 구 인코딩 후보**입니다.

**(5-e) 생성 시각 범위** — Core Data 는 2001-01-01 기준 초를 저장합니다

```bash
/usr/bin/sqlite3 -header -column "$DB" "
SELECT datetime(MIN(ZCREATIONDATE) + 978307200, 'unixepoch') AS oldest,
       datetime(MAX(ZCREATIONDATE) + 978307200, 'unixepoch') AS newest,
       COUNT(*)                                              AS n
  FROM ZBIBLEDRAWING
 WHERE ZCREATIONDATE IS NOT NULL;"
```

✅ `+ 978307200` 오프셋과 `datetime(..., 'unixepoch')` 변환을 모의 DB 로 실행 확인
(2001-01-01 ~ 1970-01-01 사이 초 = 978,307,200).
⚠️ 결과는 **UTC** 입니다. 한국 시간과 비교할 때 9시간을 더하십시오.

**(5-f) `_EXTERNAL_DATA` 로 나간 블롭 확인**

```bash
find "$WORK" -path '*_EXTERNAL_DATA*' -type f | head -20
find "$WORK" -path '*_EXTERNAL_DATA*' -type f | wc -l
du -sh "$WORK"/.*_SUPPORT 2>/dev/null
```

> ⚠️ ★ **`LENGTH(ZLINEDATA)` 를 블롭의 실제 크기로 읽지 마십시오.**
> `.externalStorage` 로 바깥에 나간 블롭은 **컬럼에 참조(작은 바이너리 plist)만 남습니다.**
> 즉 5-c 에서 **비정상적으로 짧고 균일한 길이**(수십~수백 바이트)가 나오면
> 그것은 "필사가 짧다" 는 뜻이 아니라 **"블롭이 바깥에 있다"** 는 뜻입니다.
> 그때는 `_EXTERNAL_DATA` 파일들의 크기가 곧 실제 블롭 크기이며,
> **그 파일들이 4단계에서 함께 복사됐는지가 결정적**입니다.
> ❓ 실제 임계값과 참조 plist 형식은 이 문서에서 검증하지 못했습니다.

---

#### 판정

| # | 판정 기준 | 통과 | 실패 시 |
|---|---|---|---|
| **D8-0** | 백업이 **비암호화**다 (`IsEncrypted = false`, `Manifest.db` = SQLite) | 통과 | 🚫 여기서 중단. §2-4-a |
| **D8-1** | `Manifest.db` 에 `AppDomain-kr.co.carve.leetaek` 도메인의 `Library/Application Support/Carve.sqlite` 가 있다 | 존재 | 없음 → 이 백업/기기에는 실사용 DB 가 없음. 다른 기기 백업 확인 |
| **D8-2** | 추출 스크립트의 **누락 0건**, `Carve.sqlite` 가 `sqlite3` 로 열린다 | `[MISSING]` 0 + `.tables` 성공 | 누락 → 백업 재생성. 열리지 않음 → 5단계 작업 사본 방식 재확인 |
| **D8-3** | `ZBIBLEDRAWING` (또는 실제 테이블) 행이 **1건 이상**이고 블롭이 있는 행이 있다 | 행 ≥ 1 · `null_blob < rows_all` | 0건 → **legacy 데이터 없음.** 설계 §10-2 의 전제를 재검토해야 합니다 |
| **D8-4** | `ZDRAWINGVERSION` 이 `1` 또는 `NULL` 인 행이 있다 | 존재 | 전부 상위 버전 → "진짜 legacy" 가 아닐 수 있음 |
| **D8-5** | `ZCREATIONDATE` 최솟값이 **1.2.0 배포 이전**을 가리킨다 | 그렇다 | 아니면 구 인코딩 블롭이 아닐 수 있음 — 설계 §10-2 재검토 |
| **D8-6** | `.externalStorage` 블롭이 **누락 없이** 확보됐다 | `_EXTERNAL_DATA` 파일이 복사됨 **또는** 5-c 길이 분포로 "전부 인라인" 임이 확인됨 | 참조만 있고 파일이 없음 → 4단계 다시 |

> **D8-4 · D8-5 는 "실패해도 D8 이 무의미해지지 않습니다."**
> 그 경우의 결론은 *"이 기기에는 1.2.0 시절 인코딩의 블롭이 남아 있지 않다"* 이고,
> 이것 역시 **설계 §10-2 의 전제를 뒤집는 유효한 발견**입니다. §8-6 에 올리십시오.
>
> **D8-1 · D8-2 · D8-6 만 진짜 실패**입니다 — 추출 자체가 안 된 경우입니다.

**S5 fixture 로 성립하려면:** D8-0 · D8-1 · D8-2 · D8-3 · D8-6 통과 + **D8-4 또는 D8-5 중 하나 이상** 통과.
그래야 "실제 사용자가 만든, 구 인코딩일 가능성이 있는 `lineData` 블롭" 이라는 S5 의 요구를 만족합니다.

#### 기록 → §8-3

#### 사후 — ⚠️ 개인정보 취급 (§2-5 를 반드시 함께 보십시오)

여기서 꺼낸 것은 **사용자 본인의 실제 필사 데이터**입니다.

| 규칙 | 내용 |
|---|---|
| **저장소 커밋 금지** | `$OUT` 아래의 어떤 파일도 git 에 넣지 마십시오. `~/carve-device-dump/` 는 저장소 밖이므로 실수로 `git add` 될 일은 없지만, **저장소 안으로 복사하지 마십시오** |
| **백업 원본** | Finder 백업에는 기기 전체가 들어 있습니다. 다른 곳으로 복사·공유하지 마십시오 |
| **fixture 승격** | ① `lineData` 블롭 **1~3개만** 고르고, ② `ZTITLENAME` / `ZTITLECHAPTER` / `ZVERSE` / `ZCREATIONDATE` / `ZUPDATEDATE` 같은 **식별·시각 메타는 버리거나 고정 더미값으로 치환**하고, ③ **base64 상수**로 테스트 파일에 내장 — §19-4 가 이미 쓴 방식 그대로 |
| **왜 base64 상수인가** | 테스트 타깃에 resource 설정이 없어 파일 추가가 프로젝트 설정 변경을 부르기 때문 (§19-4, AGENTS.md) |
| **커밋 메시지·문서** | PKDrawing 블롭에 텍스트는 없지만 **어느 절을 언제 필사했는지**는 개인 기록입니다. 구체적인 절·날짜를 남기지 마십시오 |
| **정리** | 검증이 끝나면 `$OUT` 을 삭제하거나 저장소 밖 암호화 위치로 옮기십시오 |

**fixture 후보 블롭 하나를 base64 로 꺼내는 방법** (Z_PK 는 5-b~5-e 로 고른 행의 값):

```bash
/usr/bin/sqlite3 "$DB" \
  "SELECT hex(ZLINEDATA) FROM ZBIBLEDRAWING WHERE Z_PK = <고른 Z_PK>;" \
  | xxd -r -p | base64
```

✅ `xxd -r -p` (hex → binary) 와 `base64` 가 이 머신에 존재함을 확인했습니다.
🔌 실제 파이프 결과는 DB 가 있어야 확인됩니다.
⚠️ **`_EXTERNAL_DATA` 로 나간 블롭에는 이 방법이 통하지 않습니다** — 컬럼에 참조만 있기 때문입니다.
그 경우 `_EXTERNAL_DATA` 아래의 해당 파일을 `base64 < <파일>` 로 직접 인코딩하십시오.
❓ 어느 파일이 어느 행에 대응하는지 매핑하는 방법은 이 문서에서 확인하지 못했습니다.
파일이 몇 개 안 되면 **크기로 대조**하는 것이 가장 현실적입니다.

**범위 경계:** **블롭 확보까지가 이 런북**입니다.
확보한 블롭을 `PencilKitDataModelTesting.swift` 에 base64 상수로 넣어 비교하는 것은 **코드 작업(Phase 0B)** 입니다.

---

### 6-2. D5 — 시편 119편 실측 (N-Canvas baseline) △ **부분 완료**

> ⚠️ **아래 절차 그대로 하지 않았습니다.** 실제로는 **Debug Navigator 시점별 읽기(1)가 아니라
> `xctrace` 타임라인 1회 기록**을 썼고, **(2) 의 `Allocations` 는 쓸 수 없었습니다**(오버헤드로 앱이 멈춤).
> **실제로 쓴 방법과 근거는 §7-3-a, 결과는 §8-4.** 재측정 시 §7-3-a 를 먼저 읽으십시오.
> **(3) hitch · (4) Time Profiler · (5) layout 시간은 여전히 ❓ 미수행**이라 아래 지시가 그대로 유효합니다.

**푸는 것:** Phase 2 판정 기준 (Phase 2 착수 전에 확보 완료).
**측정 방법의 근거는 이 문서 §7 에 있습니다. 실행 전에 반드시 읽으십시오.**

#### 준비

- Instruments 는 **`xcode-select` 가 가리키는 Xcode(26.3) 안의 것**을 씁니다: `$(xcode-select -p)/../Applications/Instruments.app`. ⚠️ rev.1 이 적은 `Xcode-beta.app`(27.0) 경로를 그대로 쓰지 마십시오 (§1-2)
- **딥링크가 없으므로** 시편 119편에는 앱 UI 로 이동합니다 (§1-1: `CFBundleURLTypes` 0건).
  §18-3 이 쓴 `UserDefaults "title"` 시드 방식은 시뮬레이터 컨테이너를 호스트 파일시스템에서 직접 고치는 방법이라 **실기기에 그대로 쓸 수 없습니다.**
- 절차를 두 기기에서 **똑같이** 반복해야 하므로, 스크롤 횟수·방향·대기 시간을 먼저 정해 적어 두십시오.

#### 실행

**(1) peak memory — Xcode Debug Navigator**

1. Xcode 에서 기기를 destination 으로 잡고 `⌘R`
2. 좌측 네비게이터 → **Debug Navigator** (⌘7) → **Memory**
3. 창세기 1장 진입 후 **8초 대기**(§18-3 의 settle 기준과 동일) → footprint 기록
4. 시편 119편으로 이동 → 8초 대기 → footprint 기록
5. 장 끝까지 스크롤(횟수 고정) → footprint 및 최대치 기록
6. 시편 120편(7절)으로 이동 → 6초, 추가 25초 → footprint 기록 (§18-3 (D) 대응)

> **왜 Debug Navigator 인가:** Xcode 의 Memory gauge 가 보여 주는 값은 앱의 **memory footprint** 계열로,
> §18-3 이 쓴 `vmmap --summary` 의 Physical footprint 와 **같은 종류의 지표**입니다
> (Instruments Allocations 의 "All Heap & Anonymous VM" 합계는 **다른 지표**이므로 footprint 값으로 쓰지 마십시오).
> ❓ 다만 두 값을 같은 대상에 대해 실측 대조하지는 못했습니다. **절대값 등가로 다루지 말고 A/B 비교용으로만** 쓰십시오.
> 디버거가 붙어 있는 것 자체도 오버헤드입니다.

**(2) 메모리 귀속 — Instruments Allocations**

```bash
xcrun xctrace record \
  --template 'Allocations' \
  --device "$DEV" \
  --attach 'CarveApp' \
  --time-limit 90s \
  --output ~/carve-device-dump/d5-alloc-<기기>-<장>.trace
```

✅ `xctrace record` 의 `--template` / `--device` / `--attach` / `--time-limit` / `--output` 옵션 확인,
`Allocations` 템플릿 존재 확인.
🔌 `--attach` 에 프로세스 이름과 pid 중 무엇이 먹는지는 기기 연결 후 확인 (`--attach <pid|name>`).

**대안 (GUI, 권장):** Instruments.app → Allocations → 기기·앱 선택 → Record. GUI 가 마킹·구간 선택에 훨씬 낫습니다.

**(3) 프레임 드랍 — Instruments Animation Hitches**

```bash
xcrun xctrace record \
  --template 'Animation Hitches' \
  --device "$DEV" \
  --attach 'CarveApp' \
  --time-limit 60s \
  --output ~/carve-device-dump/d5-hitch-<기기>-<장>.trace
```

✅ `Animation Hitches` 템플릿 존재 확인.
기록 중 **창세기 1장 전체 스크롤 → 시편 119편 전체 스크롤**을 같은 리듬으로 수행합니다.

- 읽을 값: **hitch time ratio (ms/s)** 와 개별 hitch 의 지속시간·원인 구간
- ❓ 절대 임계값은 이 문서에서 단정하지 않습니다. **두 장 사이 / 두 기기 사이의 상대 비교**로 판정하십시오.

**(4) CPU 분포 — Time Profiler (선택)**

같은 형태로 `--template 'Time Profiler'`. §18-3 의 "flick 중 한 코어 95~100%" 관측이 실기기에서도 나오는지 확인용입니다.

**(5) layout 소요 시간 — 지금은 정밀 측정 불가**

- `os_signpost` 가 저장소에 없어 정밀 측정은 **Phase 2 이월**입니다 (§18-3 "측정 못 한 것" 과 동일).
- 코드 변경 없이 가능한 대체:
  - **`SwiftUI` 템플릿** — View body 평가 횟수·시간, Core Animation commit 을 보여 줍니다. "레이아웃 비용이 어디서 나는가" 의 근사치로는 가장 낫습니다. ✅ 템플릿 존재 확인
  - **`App Launch` 템플릿** — cold launch 구간 분해
  - **화면 녹화 기반 wall clock** — 장 전환 탭부터 본문이 그려질 때까지. 거칠지만 A/B 에는 쓸 수 있습니다

#### 판정

| # | 판정 기준 | 비고 |
|---|---|---|
| D5-1 | 두 기기 모두에서 시편 119편 진입·스크롤 중 **크래시·jetsam 종료가 없다** | 절대 기준으로 쓸 수 있는 유일한 항목 |
| D5-2 | 절 수에 대한 메모리 증분이 **선형 근사에서 크게 벗어나지 않는다** | §18-3 의 `증분 ≈ 37 + 0.41·N` 은 **기울기/절편 구조만** 참고. 값 자체를 비교하지 마십시오 |
| D5-3 | 장 전환 후 메모리 **미회수 현상이 실기기에서도 재현되는가** | §18-3 (D). 재현되면 "기존부터 존재" 가 실기기에서도 확정됩니다 |
| D5-4 | hitch time ratio 가 **창세기 1장 대비 시편 119편에서 유의하게 나쁜가** | 상대 비교 |
| D5-5 | mini 와 Air 사이에 유의한 차이가 있는가 | 둘 다 60Hz·8GB 라 큰 차이는 기대하지 않음 (§13) |

#### 기록 → §8-4

---

### 6-3. D7-pre — 실기기에서 CloudKit 미러링이 동작하는가 ❓ **미수행**

**푸는 것:** 설계 §18-5 1번의 공백. Phase 1 배포 판단. **설치·entitlement 조건은 충족돼 있고, 관측만 남았습니다** (§8-3).

#### 준비

- iPad 가 iCloud 에 로그인돼 있고 네트워크 연결됨
- P0-6/P0-7 완료

#### 실행

1. 앱 실행 후 필사를 몇 획 남깁니다 (dev DB 에 기록 생성)
2. Xcode 콘솔에서 `cloudEvent` 로그를 봅니다 — `SwiftDataContextProvider.swift:105` 가 `Log.debug("cloudEvent", ...)` 를 남깁니다
3. `NSPersistentCloudKitContainer.Event` 의 `type == .import` / `.export` 가 실제로 오는지 확인
4. 설치된 앱의 entitlement 가 실제로 채워졌는지 확인:

```bash
codesign -d --entitlements - \
  "$DD"/Build/Products/Debug-iphoneos/CarveApp.app
```

✅ 명령 형태는 §18-5 가 시뮬레이터에서 쓴 것과 동일합니다. 🔌 실기기 빌드 결과는 미검증.

#### 판정

| # | 판정 기준 | 통과 | 실패 |
|---|---|---|---|
| D7-pre-1 | 기기 빌드의 entitlement 에 `com.apple.developer.icloud-container-identifiers` 가 **비어 있지 않다** | 두 컨테이너 나옴 | `<dict></dict>` → 서명 프로파일 문제 |
| D7-pre-2 | `CKAccountStatus` 가 `.available` (실패 로그 `"CloudKit 초기화 실패…"` 가 안 남는다) | 통과 | 계정/네트워크 확인 |
| D7-pre-3 | `NSPersistentCloudKitContainer` import/export 이벤트가 관측된다 | 통과 | 미러링 미동작 → **D7 은 실기기로도 검증 불가**. 이 경우 CloudKit 제약은 코드 리뷰·문서로만 판단해야 하며 리스크로 승격 |

> ⚠️ **prod 컨테이너를 확인하려고 Release 빌드를 설치하지 마십시오.** 실사용 데이터에 직접 쓰게 됩니다.
> D7-pre 는 **dev 컨테이너에서만** 수행합니다.

#### 기록 → §8-3

---

### 6-4. D6 — Stage Manager / 리사이즈 / 외부 디스플레이 ✅ **관측 완료** (iPad Air 는 ❓ 미수행)

**푸는 것:** §11 기준 3(Split View resize)과 기준 4(왼손잡이 전환)의 적용 가능 여부.
**결과: 회전·리사이즈 시 필사 배치가 바뀌거나 잘려 보이고 되돌리면 복구** — G4 가 풀려는 문제 그 자체 (설계 §20-7).
아래 절차는 **iPad Air (M2) 재수행**과 단일 Canvas 경로 확인(D9-7-4)용으로 유효합니다.

#### 준비

- iPad Air (M2) 권장 (§13 표가 지목한 기기)
- 설정 → 멀티태스킹 및 제스처 → Stage Manager 켜기 (버전에 따라 위치가 다릅니다)

#### 실행 / 판정

| # | 확인 | 판정 기준 |
|---|---|---|
| D6-1 | Stage Manager 에서 앱 창이 **리사이즈되는가** | 리사이즈됨 / 전체화면 고정 |
| D6-2 | 리사이즈 시 본문 폭이 바뀌고 필사가 재배치되는가 | `CarveDetailView.swift` 의 `contentView.id("\(sentenceSetting)-\(halfWidth)")` 때문에 **폭이 바뀌면 전체가 재생성**됩니다. 재생성 후 획 위치가 유지되는지 봅니다 |
| D6-3 | Split View / Slide Over 진입이 되는가 | ❓ 세로 고정 + scene manifest 부재 조합의 결과를 확인 |
| D6-4 | 왼손잡이 전환 후 좌표 정합 (§11 기준 4) | `SentencesWithDrawingView` 의 `isLeftHanded` 로 좌우 배치가 바뀝니다 |
| D6-5 | 외부 디스플레이 연결 시 동작 | 미러링만 되는지, 확장 창이 뜨는지 |
| D6-6 | 화면 회전 | 세로 고정이므로 가로에서 어떻게 되는지 관측 |

> ★ **D6-1/D6-3 의 결과가 §11 통과 기준표를 바꿉니다.**
> 앱이 애초에 리사이즈되지 않는다면 §11 기준 3 은 **S4 통과 기준에서 빼거나, "리사이즈 지원을 추가한 뒤 재평가" 로 이월**해야 합니다.
> 이 판단을 D6 결과에 근거해 설계 문서에 반영하십시오.

#### 기록 → §8-3

---

### 6-5. D3 — 실제 Apple Pencil 지우개로 S1 재확인 ✅ **완료**

**푸는 것:** 설계 §19-5 가 남긴 "실제 Pencil 지우개 미확인" → 설계 §7-3 / §7-4 확정.
**결과: S1 과 동일** — 획 1개가 stroke 2개로 분할되고 각각 다른 `mask`, `seed`/`creationDate`/`points` 동일(IdentityKey 1개),
완전히 지운 획은 `strokes` 에 없음 (설계 §20-7). 아래 절차는 재확인용입니다.

#### 준비

- Apple Pencil 페어링
- Debug 빌드 실행 중
- **깨끗한 절을 하나 고릅니다** (dev DB 이므로 실사용 데이터와 무관)

#### 실행

1. 절 하나에 **가로로 긴 획 1개**를 Pencil 로 긋습니다 (§19-2 의 264pt 획에 대응)
2. 앱을 잠시 대기 (trailing debounce 0.3s + 저장 완료)
3. 도구를 지우개(`monoline`)로 바꿔 **획의 가운데를 지웁니다** → 두 조각이 되는지 눈으로 확인
4. 다시 대기
5. **같은 절의 남은 조각을 전부 지웁니다** (stroke 0개 상태)
6. 앱 종료 후 컨테이너를 내려받습니다

> ⚠️ **6번의 추출 방법은 D8(§6-1)과 다릅니다.** D3 의 대상은 **개발 빌드가 만든 `Carve.dev.sqlite`** 라
> 컨테이너 접근 조건(§P0-6)을 만족하므로 **`devicectl device copy from` 또는 Xcode *Download Container…* 가 적절합니다.**
> D3 을 위해 백업을 뜰 필요는 없습니다 (dev DB 는 실사용 데이터가 아닙니다).
> 🔌 실행 결과는 미검증입니다.

각 단계 사이에 컨테이너를 받아 **3개의 블롭 스냅샷**(원본 / 분할 후 / 전부 지운 뒤)을 확보하는 것이 이상적입니다.

#### 판정

시뮬레이터 결과(§19-1, §19-2)와 **같은가 다른가**를 봅니다.

| # | 시뮬레이터 결론 (S1) | 실기기 판정 기준 |
|---|---|---|
| D3-1 | S1-1 `randomSeed` 라운드트립 보존 | 보존되면 통과 |
| D3-2 | S1-2 bitmap 지우개는 **분할 + 마스킹 동시** | 조각 수와 `mask` 유무가 시뮬레이터와 같으면 통과 |
| D3-3 | S1-4 IdentityKey 구성요소 전부 불변 (`randomSeed`, `creationDate`, `path.count`, control point 값) | 전부 같으면 통과 |
| D3-4 | S1-5 `mask` / `maskedPathRanges` 보존 | 보존되면 통과 |
| D3-5 | S1-3 완전히 지운 stroke 는 제거됨 | `strokes == 0` 이고 **DB 길이가 줄어들면** 통과 (rev.9 §19-5 의 `515 → 317` 대응) |

> **하나라도 다르면 설계 §7-3 승계 전략과 설계 §7-4 `.bitmap` 확정을 재검토해야 합니다.**
> 이건 "성능 차이" 가 아니라 **데이터 모델 전제의 차이**이므로 설계에 직접 영향이 갑니다.

> **범위 경계:** 블롭 확보까지가 이 런북입니다. 실제 필드 비교(`randomSeed` 등)는
> `PencilKitDataModelTesting.swift` 에 base64 상수를 추가하는 **코드 작업**이며 Phase 0B 에서 합니다.

#### 기록 → §8-3

---

### 6-6. D4 — Pencil 더블탭 / 두 손가락 더블탭 ✅ **완료**

**푸는 것:** 현재 배선의 실동작. **결과: 둘 다 정상**(절을 넘나드는 순차 undo 포함).
⚠️ `SharedUndoManager` 의 구조적 지적은 **관측 가능한 오동작으로 이어지지 않았습니다** —
삭제 근거는 "깨져 있어서" 가 아니라 **"단일 Canvas 에서 불필요해서"** 입니다 (설계 §20-7 · §13 Phase 4).
아래 표의 "오동작 예상" 은 실행 전 가설이며 **빗나갔습니다.**

#### 준비

- Apple Pencil (더블탭 지원 모델: Pencil 2세대 / Pro)
- iPad 설정 → Apple Pencil → 더블탭 동작이 "끄기" 로 돼 있지 않은지 확인

#### 실행 / 판정

| # | 조작 | 기대 (코드 근거) | 판정 기준 |
|---|---|---|---|
| D4-1 | 필기 중 Pencil 더블탭 | 지우개로 전환 (`CarveDetailView.swift:46` → `switchToEraser`) | 전환되면 통과 |
| D4-2 | 지우개 상태에서 다시 더블탭 | 직전 펜 타입으로 복귀 (`switchToPreviousPenType`, `lastUsedPencil`) | 복귀하면 통과 |
| D4-3 | 두 손가락 더블탭 | undo (`CarveDetailView.swift:112` → `PencilPalatteFeature.swift:99`) | **오동작 예상.** 방금 그은 획이 아니라 다른 캔버스가 undo 되거나 아무 일도 안 일어나면 §13 근거 확정 |
| D4-4 | D4-3 이후 팔레트의 undo 버튼 | `canUndo` 상태가 실제와 맞는가 | 어긋나면 `isPerformingUndoRedo` 누수 정황 |
| D4-5 | 두 손가락 더블탭이 스크롤·탭 제스처와 충돌하는가 | `.onTapGesture { tapForHeaderHidden }` 과 공존 | 헤더가 의도치 않게 토글되면 기록 |

#### 기록 → §8-3

---

### 6-7. D1 — Pencil hover / live stroke ✅ **완료** (이 절의 형태로는 하지 않음)

> **S4 하네스(`-CanvasScrollSpike`)를 실기기에서 모드 A / B 로 띄워 §11 기준 7·8 을 직접 판정**했습니다.
> 이 절이 원래 적었던 "§11 기준 7·8 의 판정은 아닙니다" 라는 제약은 하네스 구현으로 사라졌습니다.
> **결과는 §8-3, 결론은 설계 §11 · §12 U4 (B 확정).**
> ⚠️ 아래 **D1-3 · D1-4 · D1-5 는 여전히 ❓ 미수행**입니다.

#### 실행 / 판정

| # | 조작 | 판정 기준 (현재 N-Canvas 구조 기준) |
|---|---|---|
| D1-1 | Pencil 을 화면 위 hover | 본문·밑줄·캔버스가 **움직이지 않는다** |
| D1-2 | 획을 긋고 pencil-up | live stroke 가 **확대되거나 이동하지 않는다** (issue #6 증상) |
| D1-3 | 스크롤 도중 필기 | 획이 손끝 위치에 그려진다 |
| D1-4 | 절 경계를 넘는 획 | **끊긴다** (현재 구조의 알려진 한계, §1-1). 끊기는 지점을 기록 |
| D1-5 | 빠른 fling 직후 필기 | 좌표가 어긋나지 않는다 |

> **D1-2 가 현재 구조에서 재현되지 않는다면**, issue #6 은 `CombinedCanvasView` 구조 고유의 문제였다는 뜻이고
> S4 spike 에서 **정확히 그 구조를 재현해 비교해야** 한다는 결론이 나옵니다. 그것이 이 항목의 가치입니다.

#### 기록 → §8-3

---

### 6-8. D2 — 손가락 입력과 스크롤 UX ✅ **완료**

> S4 하네스로 수행했습니다. 결과는 §8-3.
> ⚠️ **아래 "§11 기준 9 는 여기서 판정하지 않습니다 — 옵션 B 구조가 없기 때문" 은 무효입니다.**
> 하네스가 옵션 B 구조를 제공하므로 **기준 9 도 판정했고 A·B 모두 통과**였습니다.
> ⚠️ **D2-4 palm rejection 은 여전히 ❓ 미수행**입니다.

#### 실행 / 판정

| # | 조작 | 판정 기준 |
|---|---|---|
| D2-1 | `allowFingerDrawing = false` (기본) 에서 한 손가락 스크롤 | 정상 스크롤 (현재는 SwiftUI ScrollView 가 처리) |
| D2-2 | 설정에서 **"손가락 필사 허용"** 켜기 (`SentenceSettingsView.swift:95`) 후 스크롤 시도 | **§11 기준 10 — 지금 판정 가능.** 캔버스 위에서 손가락이 획이 되어 스크롤 방법이 사라지는지 확인 |
| D2-3 | D2-2 상태에서 스크롤 가능한 영역이 남아 있는가 | 본문 쪽(캔버스 밖)에서만 되는지, 두 손가락으로 되는지 기록 |
| D2-4 | 손바닥 거치(palm rejection) | Pencil 모드에서 손바닥이 획을 만들지 않는다 |

> **§11 기준 9 는 여기서 판정하지 않습니다.** 옵션 B(PKCanvasView 단독 스크롤) 구조가 없기 때문입니다.

#### 기록 → §8-3

---

### 6-9. D9 — 단일 Canvas 실기기 검증 ★ **진행 중**

> ★ **지금 살아 있는 절차입니다. 설계 §13 의 마지막 게이트** — 통과해야 flag 기본 활성화와 Phase 4(구 구조 제거)로 갑니다.
>
> **진행 상황 (2026-09-08):** 스모크 ✅ · D9-1 ✅ · D9-2 ✅ · D9-3-1·2·4 ✅ · D9-4-1·4 ✅ · D9-7-4 ✅ · D9-8 ✅(측정) · D9-CK② ✅ ·
> ✅ **D9-6 통과** (R23 · R24 수정 완료) · **D9-5 통과** · **D9-7-1 · D9-7-3 통과** · ✅ **D9-CK③ 완료 (2026-09-09 CloudKit 승격)** — **기본 활성화의 하드 블로커가 없습니다.**
> ⚠️ 남은 위험: **R25**(롱프레스 메뉴 교체 — 데이터 위험) · **R22**(팔레트 폭) · **R20**(저메모리 미검증) · **R27**(기존 행 rowUUID 부재) · **R28**(혼재 버전). **D9-7-2 ❓ 미수행**(Pencil 필요) (§8-7).
>
> ✅ **D9 H(회전 표시)는 종결됐습니다** — 분석 §6 잔여 검증 5건 완료.
> 완료 기준은 [분석 문서 §6](./single-canvas-rotation-display-investigation.md), CLI 회전·A/B 는 [조작 절차](./device-debugging-cli.md).
> ⚠️ **`-CanvasReuseStrokesOnApply` 는 수정을 끄는 opt-out 입니다** — 그 실행에서 결함이 재현되는 것이 정상이고,
> **기본 검증은 인자 없이** 돕니다. 비교 모드 결과를 기본 경로 결과로 기록하지 마십시오.

**이 항목이 풀어주는 것**

| 열려 있는 것 | D9 가 닫는 방식 |
|---|---|
| 설계 §8 전체(편집 계약·mutation·coalescing·atomic batch·flush·재합성)가 **테스트로만** 검증됨. 실행 0회 | 실제 Pencil 입력으로 저장 경로를 한 번 통과 |
| 설계 §14 필수 항목 **14 · 16 · 17** 이 테스트로 고정되지 않음 | 손으로 판정 (D9-3 · D9-6) |
| 설계 §11 기준 **2 (관성 fling)** · **5 (탭/롱프레스)** — rev.3 세션에서 미수행 (§8-6 R12) | D9-7 에서 함께 처리 |
| 설계 §20-11 — 롱프레스 → 메뉴 → 시트의 **실제 터치를 시뮬레이터에서 확인 못 함** | D9-5 |
| 설계 §10-1-a — dev CloudKit 스키마에 `CD_layoutMetadataData` 가 **없음** (아무도 쓴 적이 없어서) | D9-CK. **순서 문제라 여기서 처리하지 않으면 배포 때 터집니다** |
| 단일 Canvas 의 진입/스크롤 footprint 미측정 | D9-8 (§18-3-a 절차) |

---

#### D9-0. 전제 확인 — ⚠️ rev.3 과 **다른 Mac 입니다**

rev.3 세션의 머신(macOS 27 beta)과 다릅니다. 아래는 **이번 머신에서 실제로 조회한 값**입니다 (✅).

| 항목 | 값 | 비고 |
|---|---|---|
| Mac | macOS **26.3** (25D125) | ✅ **`DEVELOPER_DIR` 우회가 불필요합니다** — AGENTS.md 의 우회는 macOS 27 beta 전용 |
| Xcode | **26.3** (17C529), `/Applications/Xcode.app` | ✅ AGENTS.md 의 `/Applications/Xcode-26.3.0.app` 경로는 **이 머신에 없습니다** |
| `xcode-select -p` | `/Applications/Xcode.app/Contents/Developer` | ✅ 이미 올바름 |
| 기기 | **iPad mini (A17 Pro)** `iPad16,2` / iOS **27.0 beta (24A5408d)** | ✅ **D5 baseline 과 같은 기기·같은 OS 빌드** → §18-3-a 와 비교 가능 |
| 하드웨어 UDID (`xctrace` · `xcodebuild -destination`) | `00008130-000C24A60C92001C` | ✅ |
| CoreDevice UUID (`devicectl`) | `12D4D553-6E31-5870-AD22-F36DF517AFD3` | ✅ 도구마다 다름 (AGENTS.md) |
| **`transportType`** ★ | **`wired`** | ✅ **§7-3-a ① 충족.** Wi-Fi 면 Instruments 기록이 1.1초에 끊기고 데이터도 유실 |
| `developerModeStatus` | `enabled` | ✅ |
| 서명 | `Apple Development: LEE TAEKSEONG (4XGUH223QX)` 유효 | ✅ 폐기된 인증서(`5M7X3FV4SS`)가 함께 있으니 서명 실패 시 여기를 의심 |
| 회귀 기준선 | **312** (설계 §19-4-2) | ⚠️ 이 표가 작성될 당시(rev.5)는 265 였습니다. **줄어들면 회귀입니다** |

```bash
# 이번 머신의 전제 (AGENTS.md 의 Xcode-26.3.0.app 경로가 아님)
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
DEV=12D4D553-6E31-5870-AD22-F36DF517AFD3          # devicectl 용
UDID=00008130-000C24A60C92001C                     # xctrace / xcodebuild 용

# ⚠️ 기록 직전에 반드시 재확인 — 케이블이 빠지면 조용히 Wi-Fi 로 넘어갑니다
xcrun devicectl device info details --device "$DEV" | grep transportType   # → wired
```

> ⚠️ **`.xcodeproj` 는 gitignore 대상입니다.** 다른 Mac 에서 처음 여는 것이라면
> **`mise x -- tuist generate --no-open` 을 먼저 돌리십시오.** 생략하면 `Cannot find 'DrawingSchemaV4' in scope`
> 처럼 **자사 코드와 무관해 보이는 컴파일 에러**가 납니다 (이번 세션에서 실제로 겪음).

#### D9-0-a. ⚠️ 백업 — 건너뛰지 마십시오

§2-4 의 결론은 rev.3 이후에도 **유지**입니다. 근거는 §2-3 3번(prod CloudKit 에 모든 필사가 올라가 있는지)이 **여전히 미확인**이기 때문입니다.
컨테이너 보존은 §2-3 1번에서 관측됐지만 **iOS 27.0 beta 에서의 1회 관측**입니다. 설치 직전에 Finder 백업을 다시 뜨십시오.

#### D9-0-b. 빌드 · 설치 · 실행

P0-5 ~ P0-7 을 그대로 따르되, 실행 인자를 붙입니다.

> ✅ **빌드·설치·실행 모두 이 머신에서 성공했습니다.** 산출물
> `~/carve-build/device/Build/Products/Debug-iphoneos/CarveApp.app`,
> 서명 `Identifier=kr.co.carve.leetaek` / `TeamIdentifier=H4MSW7FUBB`.
> ⚠️ **설치는 여전히 되돌릴 수 없는 단계입니다** — 직전에 §2-4 백업 (D9-0-a).

```bash
DD=~/carve-build/device
xcodebuild build -workspace Carve.xcworkspace -scheme CarveApp \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath "$DD" -allowProvisioningUpdates

xcrun devicectl device install app --device "$DEV" \
  "$DD"/Build/Products/Debug-iphoneos/CarveApp.app

# ★ 오버레이 + 단일 Canvas 강제. 앱 인자는 `--` 뒤에 (AGENTS.md)
xcrun devicectl device process launch --device "$DEV" --terminate-existing \
  kr.co.carve.leetaek -- -SingleCanvas -ChapterLayoutOverlay
```

> ⚠️ **실기기 로그는 시뮬레이터와 다릅니다.** `Log.info` 는 `OSLog` 기반이라
> `devicectl … process launch --console`(stdout/stderr)에는 **찍히지 않습니다.**
> AGENTS.md 의 `simctl spawn <UDID> log stream …` 도 시뮬레이터 전용입니다. 실기기에서는 둘 중 하나를 쓰십시오 —
> **① Console.app** (기기 선택 → `subsystem: kr.co.carve.leetaek` 필터. `ChapterLayout 완성 …` · `com.apple.pencilkit` 확인)
> **② Instruments 의 `os_log` / `os_signpost` 계측기** (D9-8 과 같은 세션에서 볼 수 있어 효율적).
> 로그를 못 붙여도 **판정의 본체는 HUD** 입니다 — D9-0-c 표는 화면만으로 채울 수 있습니다.

> `-SingleCanvas` 는 설정 토글(`SingleCanvasFlag.appStorageKey`)과 **같은 효과**입니다.
> D9-6 에서 토글 자체를 검증하므로, D9-1~D9-5 는 실행 인자로 켜고 D9-6 에서 인자 없이 다시 띄우십시오.
> **앱이 비어 보이는 것은 정상입니다** — Debug 는 `Carve.dev.sqlite` 를 봅니다 (§2-2).

#### D9-0-c. 스모크 — 여기서 막히면 나머지는 의미 없습니다

시편 119편으로 이동해 하단 HUD 를 봅니다 (`ChapterLayoutDebugHUD`).

| HUD 항목 | 통과 값 | 실패 시 |
|---|---|---|
| `gate PASS` (초록) | **PASS** | `FAIL` 이면 **장 전체가 필기 불가**. 설계 §6-2 게이트 |
| `176/176` | 실측/기대 절 수 일치 | 모자라면 아래 `missing` 줄에 절 번호가 뜸 |
| `Δ max` | **0.00** (초록, tol 1.00pt) | 0 이 아니면 **레이아웃보다 측정 경로를 먼저 의심** (AGENTS.md — 중첩 호스팅의 `.named` → global 대체). ⚠️ **rev.6 — 이 값은 R16 계열을 잡지 못합니다.** D9-0-d 를 함께 도십시오 |
| `guard` | **`OPEN`** (초록) | `BLOCKED` 면 Δ 안전망이 새 획 입력을 막는 중입니다 (합성·표시·저장은 계속 돕니다). Δ 가 0 인데 `BLOCKED` 면 **오탐**입니다. `guard —` 는 N-Canvas 이거나 실측 대기 (설계 §14) |
| `columnX` | **366.70** (오른손·세로) | 다르면 화면 크기·왼손 설정을 먼저 확인 |
| `missing` 줄 | **없어야 함** (있으면 노란색) | 있으면 게이트가 열리지 않은 절 |
| `compose` | **`SYNC`** (초록) · `leg 0` | `STALE` 이면 캔버스가 **옛 레이아웃으로 합성된 채**입니다 — 본문만 재배치되고 잉크가 남습니다. 켜진 플래그가 원인을 가릅니다 (`pend` 편집 중 보류 · `rl`/`rws` 재조회 대기 · 전부 0 이면 미전달). `leg`/`mism` 은 절 번호까지 나옵니다 |
| `PKCanvasView` 개수 | **1** | 설계 §20-8 — `com.apple.pencilkit` 의 `isGenerationToolEnabled` 가 생성 1회당 1줄. ⚠️ **실기기에서는 `simctl spawn … log stream` 을 쓸 수 없습니다** (아래 참고) |

#### D9-0-d. R16 계열 재확인 — `Δ` 로는 잡히지 않습니다 ★ (rev.6 신설)

R13 수정으로 행 높이가 **실측 입력**이 된 뒤로, 호스트 제안이 행을 늘려도 레이아웃이 그 렌더를 따라갑니다.
예측 == 실측이 되어 **`Δ max` 가 0.00 을 표시합니다** — R16 이 살아 있어도 그렇습니다 (rev.6 에서 실측 확인).
판별식은 Δ 가 아니라 **`H`(totalHeight)** 입니다. 늘어난 행의 높이가 그대로 합산되므로, 신장이 일어나면
`H` 가 **이전 장의 컬럼 높이**에 가까워집니다.

| # | 조작 | 적을 값 |
|---:|---|---|
| ⓐ | 앱 재실행 → **창세기 2장으로 바로 진입** (전환 없음) | `H` = |
| ⓑ | 창세기 1장 → 창세기 2장 전환 | `H` = |
| ⓒ | **시편 119편(176절) → 창세기 2장** 전환 | `H` = |

**ⓐ == ⓑ == ⓒ 이면 R16 없음.** ⓒ 가 가장 강한 판별입니다 — 이전 장이 가장 길어 초과분이 가장 큽니다.
ⓑ·ⓒ 가 ⓐ 보다 크면 행이 늘어난 것이고, 그때 `Δ max` 는 여전히 0.00 을 표시합니다.

눈으로 함께 볼 것: 전환 직후 **절 사이에 평소보다 큰 빈 공간**이 생기지 않는지. 늘어난 행은 밑줄과 텍스트를
제자리에 두고 아래 여백만 키웁니다 (§8-7 R16 기록 "밑줄은 제자리, 빨강 박스만 큼").

> 자동 검출은 시뮬레이터의 `ChapterCanvasControllerTesting.hostedColumnKeepsIdealHeightAndStaysAtTop`
> 하나뿐입니다. `UIWindow` 를 실제로 띄우는 테스트이고, 그 형태가 아니면 되먹임 고리가 테스트 경로에
> 들어오지 않습니다 (설계 §14 · §20-13).

---

#### D9-1. 필기 → 저장 → 재실행 복원 ★ 가장 중요

**이 경로가 실행된 적이 한 번도 없습니다.** 여기서 결함이 나오면 나머지는 후순위입니다.

| # | 조작 | 판정 기준 | 근거 |
|---|---|---|---|
| D9-1-1 | 시편 119편의 서로 떨어진 **3개 이상 절**에 Pencil 로 필기 | 잉크가 손끝을 따라오고 pencil-up 에 **점프하지 않음** | 설계 §11 기준 7 (D1 에서 B 통과) |
| D9-1-2 | **절 경계를 넘는 긴 획**을 1개 이상 (다음 절 본문까지 이어 긋기) | ⚠️ **획이 끊기지 않고, 통째로 `시작 절`에 귀속** | G1 · 설계 §7-1 U1 |
| D9-1-3 | 이웃 절 잉크와 **겹치는** 새 획을 긋기 | ⚠️ **겹쳐도 시작 절에 귀속** — rev.19 `df15ba45` 가 고친 그 결함의 실물 확인 | 설계 §7-3 · §20-12 |
| D9-1-4 | HUD 의 `dirty vN (x, y, w × h)` 확인 | 방금 편집한 **절 번호**가 뜨고, 자홍 사각형이 획을 감쌈 | 설계 §20-11 |
| D9-1-5 | 앱 **강제 종료** → 재실행 → 같은 장 | ⚠️ **모든 획이 같은 위치에 복원.** 하나라도 사라지면 **중단** | 설계 §14 1 · §9-1 |
| D9-1-6 | 잉크가 있는 상태로 장 전체 스크롤 | 렌더 누락·잔상 없음 | 설계 §16 D9 "잉크 있는 장의 렌더" |

> **D9-1-2 의 판정 방법:** 재실행 후에도 그 획이 **한 덩어리**여야 합니다. 경계에서 두 조각으로 보이면
> 소유권이 아니라 **저장 분할**이 일어난 것이고, 이는 단일 Canvas 의 존재 이유(G1)가 깨진 것입니다.

#### D9-2. 지우개 (§14 2 · `7ba5bc46` 회귀)

| # | 조작 | 판정 기준 |
|---|---|---|
| D9-2-1 | `.bitmap` 지우개로 **획의 가운데만** 지우기 | 획이 조각으로 갈라지고, 각 조각이 **자기 절에 남음** (승계 규칙 1) |
| D9-2-2 | 절 하나를 **완전히** 비우기 | 화면에서 사라짐 |
| D9-2-3 | D9-2-2 후 앱 재실행 | ⚠️ **지운 절이 비어 있어야 함.** 되살아나면 `clear` mutation 미발생 — §7-5 회귀 |
| D9-2-4 | D9-2-2 절에 **과거 회차**가 있었다면 | 자동 승격되지 않음 (설계 §14 5 · U2) |

#### D9-3. undo / redo · reflow (§14 14 · 17)

단일 Canvas 는 `canvas.undoManager` 를 쓰고 팔레트는 `delegatesUndoToCanvas` 로 위임합니다 (설계 §11).

> ⚠️ **reflow(D9-3-4)를 보기 전에 HUD 의 `leg` 가 0 인지 먼저 확인하십시오.**
> **v1/v2 행은 band reflow 되지 않고 평행이동만 됩니다** — 설계 §9-3 대로이며 결함이 아닙니다.
> **flag 를 오간 장(D9-6 대상)에는 v1/v2 행이 섞입니다** — N-Canvas 로 새로 그은 획이 v1 행을 만들기 때문입니다.
> `leg` 에 번호가 있으면 그 절을 단일 Canvas 로 한 번 편집해 v3 로 올린 뒤(§10-3) 보십시오.
> 단, **`leg` 는 마지막 합성의 결과라 편집 직후에는 안 줄어듭니다.** 장을 나갔다 와야 갱신됩니다.

| # | 조작 | 판정 기준 |
|---|---|---|
| D9-3-1 | 필기 → **팔레트 undo** → redo | 획이 사라졌다 돌아옴. 팔레트 버튼 활성/비활성이 따라옴 |
| D9-3-2 | **Pencil 더블탭** · **두 손가락 더블탭** | D4 에서 N-Canvas 는 정상이었음. 단일 Canvas 에서도 같은지 |
| D9-3-3 | D9-3-1 뒤 앱 재실행 | ⚠️ **최종 상태 유지** — 설계 §14 **17** (테스트로 고정 안 됨) |
| D9-3-4 | 헤더에서 **폰트·자간·폭 변경**으로 reflow 유발 ★ **E-4 재판정 지점** | 필사가 밑줄 기준으로 재배치 (G4) · ⚠️ **undo 스택이 비워짐** — 설계 §14 **14** (테스트로 고정 안 됨). ⚠️ **D9 H 정식 수정 뒤 아직 수행하지 않았습니다** — E-4(미확정, §8-7)가 여기서 판정됩니다 |
| D9-3-5 | 획을 긋는 **도중**에 설정을 바꿔보기 | pencil-up **뒤에** reflow 가 적용 (설계 §14 11 · §8-1) |

#### D9-4. 장 전환 flush (§14 7 · §8-5)

⚠️ **§8-5 의 "요청/승인 흐름" 은 미구현입니다.** 현재는 물러난 세션 + 장 진입 재시도로 대체합니다. 그 대체가 실제로 동작하는지 보는 항목입니다.

| # | 조작 | 판정 기준 |
|---|---|---|
| D9-4-1 | 마지막 획을 긋고 **0.3초 debounce 가 끝나기 전에** 즉시 다음 장으로 전환 | 그 획이 **이전 장에** 저장됨 (돌아와서 확인) |
| D9-4-2 | 필기 직후 홈 제스처로 **백그라운드** → 복귀 | 미저장분 유실 없음 (`appWillResignActive` flush) |
| D9-4-3 | 필기 직후 **설정 화면으로 push** → 복귀 | Carve 상태·미저장분 유지 (`NavigationStack` push) |
| D9-4-4 | 여러 장을 빠르게 왕복 | 이전 장의 획이 **다음 장에 나타나지 않음** (설계 §14 6-3) |

#### D9-5. 히스토리 메뉴 (설계 §20-11 — 시뮬레이터에서 터치 미확인)

| # | 조작 | 판정 기준 |
|---|---|---|
| D9-5-1 | 필기가 있는 절에서 **손가락 롱프레스** | **"이전 필사 내용 보기"** 메뉴가 뜸 (`UIEditMenuInteraction`) |
| D9-5-2 | 메뉴 선택 | 시트가 뜨고 **누른 위치의 절**이 잡힘 (엉뚱한 절이면 `verse(containing:)` 결함) |
| D9-5-3 | 본문(텍스트) 쪽 여백에서 롱프레스 | x 클램프로 같은 절이 잡힘 |
| D9-5-4 | 시트에서 **과거 회차 복원** | 화면이 바뀌고, ⚠️ **복원이 mutation 을 만들지 않음** (설계 §14 5-2) |
| D9-5-5 | **미저장 획이 있는 상태**에서 복원 | 미저장분이 **먼저 저장된 뒤** 복원 — 유실 없음 (설계 §14 5-3) |
| D9-5-6 | ⚠️ 헤더 설정에서 **"손가락 필사 허용"** 을 켠 뒤 롱프레스 | **그리기 제스처와 겹치는지** — 가만히 0.5초 누르면 메뉴 + 점이 함께 생기는가 (설계 §15 리스크) |

> D9-5-6 은 N-Canvas 의 행별 메뉴도 같은 조건이므로 **신규 결함인지 기존 조건인지**를 함께 적으십시오.

#### D9-6. flag 토글과 롤백 (§14 16 · 설계 §10-3) ★ 두 번째로 중요

**V4 저장소는 forward-only 입니다. flag off 가 유일한 롤백 수단이므로, 이 경로가 깨지면 배포 자체가 불가능합니다.**

| # | 조작 | 판정 기준 |
|---|---|---|
| D9-6-1 | 앱을 **인자 없이** 재실행 → 설정 > **필사 캔버스** → 토글 **on** | 장이 다시 로드되고 단일 Canvas 경로로 뜸 |
| D9-6-2 | 필기 후 같은 토글을 **off** | 장 재로드 → **N-Canvas 가 같은 데이터를 같은 위치에 표시** |
| D9-6-3 | D9-6-2 에서 v3 행의 표시 위치 | `firstUnderlineY` 만큼 내려 표시 (`displayTransform`). 눈에 띄게 어긋나면 기록 |
| D9-6-4 | flag off 상태에서 그 절을 **편집** | v2 로 강등됨 (설계 §10-3 표) |
| D9-6-5 | 다시 flag **on** → 그 절을 편집 | v3 로 복귀 |
| D9-6-6 | 토글 직전에 **미저장 획**을 남기고 off | 미저장분이 flush 되어 N-Canvas 에도 보임 (`setSentence`) |

> ⚠️ **D9-6-2 에서 데이터가 안 보이면 즉시 중단하십시오.** 롤백 수단이 없다는 뜻입니다.

#### D9-7. §11 잔여 기준 — 2 (관성 fling) · 5 (탭/롱프레스)

rev.3 세션이 기준 7~10 에 집중하느라 남긴 것입니다 (§8-6 R12). **제품 코드(단일 Canvas)에서 직접** 봅니다 — S4 하네스가 아니라도 됩니다.

| # | 조작 | 판정 기준 |
|---|---|---|
| D9-7-1 | **빠른 관성 fling** 을 위·아래로 여러 번, 끝까지 튕겨 bounce | 멈춘 뒤 잉크와 본문의 상대 위치가 **어긋나지 않음** (§11 기준 2) |
| D9-7-2 | 깊은 offset(뒷부분 절)에서 필기 | 스크롤 깊이에 비례한 오차가 **없음** — A 구조의 실패 양상 (§8-6 R5) |
| D9-7-3 | 한 손가락 **탭** (헤더 토글) · 헤더 애니메이션 중 스크롤 | 정상 (§11 기준 5) |
| D9-7-4 | 화면 **회전** · Split View 리사이즈 후 재필기 | D6 에서 N-Canvas 는 "표시가 어긋나고 되돌리면 복구" 였음. 단일 Canvas 는 어떤지 (§11 기준 3) |

#### D9-8. 성능 — §18-3-a 절차 그대로

⚠️ **D5 의 최대 약점이 "스크롤 속도·횟수 미계측" 이었습니다** (§8-4 한계 3). 이번에는 절차를 먼저 고정하고 시작하십시오.

```bash
# ⚠️ USB 확인 후 (§7-3-a ①). Allocations 금지 — 앱이 멈춥니다 (§7-3-a ②)
xcrun xctrace record --template 'Activity Monitor' --device "$UDID" \
  --all-processes --output ~/carve-device-dump/d9-actmon-mini.trace
```

| 구간 | D5 baseline (N-Canvas) | 단일 Canvas 판정 |
|---|---:|---|
| 시편 119편 진입·스크롤 peak | **363.6 MB** / CPU 84.5% | 기록 |
| 다음 장 전환 후 정지 | **109.7 MB** (평평) | ⚠️ **회수되지 않으면 그것은 새로운 현상** (§8-6 R6) |
| 기동 직후 | 62.2 MB | 기록 |

- 읽는 지표: `sysmon-process` 의 **`memory-physical-footprint`**
- layout 시간은 Instruments **os_signpost** 카테고리 `ChapterLayout` 의 `measure` 인터벌 (§0-A rev.4). 같은 값이 `Log.info("ChapterLayout 완성 …")` 로도 남지만 **실기기에서는 Console.app 으로만 보입니다** (D9-0-b). 시뮬레이터 값은 176절 **0.71 s** — ⚠️ **이것이 실기기 첫 측정입니다**
- ⚠️ **기록 중 `pgrep`/`pkill` 금지** (AGENTS.md) — 트레이스가 메타데이터 없이 저장돼 `xctrace export` 가 실패합니다
- ⚠️ 설계 §18-3(시뮬레이터)과 **절대값 비교 금지** (§7-2). D5 와는 같은 기기·같은 OS 빌드라 **비교 가능**합니다

#### D9-CK. CloudKit 스키마 승격 (설계 §10-1-a) ⚠️ 기본 활성화 전 필수 ★ 절차 (2026-09-09 정리)

**메커니즘이 아니라 순서의 문제입니다.** CloudKit **Development** 는 값이 처음 저장될 때 필드를 자동으로 만들지만,
**Production** 은 Dashboard 에서 명시적으로 배포해야 생깁니다. 승격 없이 배포하면 사용자가 만든 v3 행의
metadata 가 **서버로 올라가지 못하고**, 기기를 바꾸거나 재설치한 사용자는 그만큼을 잃습니다.

⚠️ **사람이 직접 해야 합니다.** 되돌릴 수 없는 외부 상태 변경이라 자동화하지 않습니다.

**대상 컨테이너**

| 환경 | 컨테이너 ID | 어디서 오나 |
|---|---|---|
| Debug | `iCloud.Carve.SwiftData.iCloud.dev` | `App/CarveApp/Project.swift` 의 `CLOUDKIT_CONTAINER_ID` |
| Release | `iCloud.Carve.SwiftData.iCloud` | 〃 |

⚠️ **둘은 별개 컨테이너입니다.** dev 에서 스키마를 만들어도 운영 컨테이너와는 무관하며,
**운영 컨테이너의 Development 환경**에서 만들어 **같은 컨테이너의 Production 으로** 배포해야 합니다.

**확인할 필드** — `layoutMetadataData` 하나가 아닙니다

레코드 타입은 `CD_BibleDrawing` (SwiftData 가 `CD_` 접두사를 붙입니다). V4 가 **새로 추가한** 필드는 둘입니다.

| 모델 필드 | 서버 필드(예상) | 언제 생기나 |
|---|---|---|
| `layoutMetadataData` (`.externalStorage`) | `CD_layoutMetadataData` | ⚠️ **v3 저장이 한 번 일어나야** — D7 시점에 없던 이유 |
| `rowUUID` | `CD_rowUUID` | 신규 행 생성 시 |
| `drawingVersion` · `isPresent` · `lineData` | `CD_drawingVersion` 등 | V3 부터 존재 — 이미 있을 가능성이 큼 |

⚠️ **`.externalStorage` 필드는 서버 이름이 다를 수 있습니다.** D7 실측에서 `CD_lineDataBytes` 가 관측됐으므로
`CD_layoutMetadataData` 와 `CD_layoutMetadataDataBytes` **둘 다** 확인하십시오. 이 이름 규칙은 실측 1건에 근거한
것이고 확정된 문서 근거가 없습니다 — **Dashboard 에서 실제 이름을 보고 판단하십시오.**

**절차**

| 순서 | 할 일 | 확인 |
|---:|---|---|
| ① | **운영 컨테이너**(`iCloud.Carve.SwiftData.iCloud`)의 **Development** 환경에 위 필드가 있는지 본다 | 없으면 ②로, 있으면 ③으로 |
| ② | 없으면 **Release 서명 빌드**로 v3 저장을 한 번 일으켜 필드를 만든다 — 필사 있는 절을 단일 Canvas 에서 편집하면 된다 | Dashboard 에서 필드 생성 확인 |
| ③ | ⚠️ **Development 스키마에 실험 중 만들어진 불필요한 레코드 타입·필드가 없는지 훑는다** | 승격은 **스키마 전체**를 옮긴다 |
| ④ | Development → **Production 배포(promote)** | ⚠️ **되돌릴 수 없습니다.** 필드 추가는 영구적이고 삭제할 수 없습니다 |
| ⑤ | Production 환경에서 필드가 보이는지 재확인 | — |
| ⑥ | 그 다음에야 단일 Canvas 를 담은 빌드를 **출시** | 설계 §10-1-a |

**✅ 2026-09-09 배포 완료.** 실제로 해 본 결과와 그때 드러난 것들:

| | Development | Production (배포 전) |
|---|---|---|
| `CD_layoutMetadataData` | ✅ | ❌ |
| `CD_rowUUID` | ✅ | ❌ ⚠️ |
| `CD_isWritten` | ✅ | ✅ |
| `CD_base*` 3개 | ✅ (죽은 필드) | ❌ |
| `CD_BiblePageDrawing` | ✅ (죽은 타입) | ❌ |

- **두 환경은 완전히 별개였습니다.** dev 컨테이너(`…iCloud.dev`)에서 확인한 것은 운영 컨테이너와 무관합니다
- **`CD_isWritten` 이 Production 에 있다는 것이 "과거에 배포한 적 있다" 의 증거**입니다 — 그 필드는 어느 스키마 버전(V1~V4)에도 없으니, 모델에 있던 시절에 누군가 배포한 것입니다. 자동 배포가 아닙니다
- **배포 전에 죽은 것들을 Development 에서 지웠습니다** — `CD_base*` 3개와 `CD_BiblePageDrawing` 레코드 타입. Production 에 없었으므로 그대로 배포했다면 **영구히** 들어갔을 것입니다. CloudKit 은 Production 에서 필드·타입을 지울 수 없습니다
- `CD_BiblePageDrawing` 은 삭제 후 앱을 다시 동기화해도 **돌아오지 않았습니다** — 모델에 등록은 돼 있으나(`Schema([...])`) 읽기·쓰기 호출부가 없어(유일한 읽기는 주석 처리된 `CombinedCanvasFeature`) 레코드가 올라가지 않기 때문입니다

> **⚠️ 필드가 안 보이면 토글부터 보십시오 (2026-09-09 실제로 겪음).**
> `CD_rowUUID` 는 보이는데 `CD_layoutMetadataData` 만 없다면, 십중팔구 **단일 Canvas 가 꺼진 채로 돌고 있는 것**입니다.
> `rowUUID` 는 새 행마다 값이 들어가 저절로 생기지만, `layoutMetadataData` 는 **절이 v3 로 저장될 때만** 값이 들어가고
> **v3 저장은 단일 Canvas 에서만** 일어납니다. 토글을 켜고 필사가 있는 절을 한 번 편집하면 곧바로 생깁니다.
> ⚠️ 기본값이 on 으로 바뀐 뒤에도 **명시적으로 껐던 기기는 꺼진 채로 유지**됩니다 (§10-3 롤백 의사 존중) — 그래서 헷갈리기 쉽습니다.

> **왜 ⑥ 이 마지막인가.** 출시가 먼저면 사용자가 곧바로 v3 + metadata 를 쓰기 시작하는데
> 서버에 필드가 없어 그 값이 동기화되지 않습니다. 로컬에는 남으므로 즉시 눈에 띄지도 않습니다.

> **이번 세션에서 확인된 것:** D9-CK② (**dev 컨테이너**의 `CD_layoutMetadataData` 생성) ✅.
> **③ 은 운영 컨테이너 기준으로 다시 봐야 합니다** — dev 컨테이너에서 확인한 것이지 운영 컨테이너가 아닙니다.

> D7 나머지(메타데이터 없는 행의 도착 · `isPresent` 복수 충돌)는 **기기 2대가 필요**하므로 D9 범위 밖입니다.

---

#### ⛔ 중단 기준 — 하나라도 나오면 멈추고 §8-7 에 기록

| 증상 | 뜻 |
|---|---|
| 재실행 후 필기가 **사라짐** | 저장 경로 결함. 설계 §8 전체 재검토 |
| flag off 에서 데이터가 **안 보임** | ⚠️ **롤백 수단 붕괴.** 가장 심각 — 배포 불가 |
| 게이트가 열리지 않음 (`gate FAIL` · `missing`) | 장 전체가 필기 불가 (설계 §15 리스크) |
| 장 전환 후 메모리가 **회수되지 않음** | D5 에서는 회수됐으므로 **새로운 현상** (§8-6 R6) |
| 경계 획이 **두 조각으로** 저장됨 | G1 이 깨짐 — 단일 Canvas 의 존재 이유 |

#### 기록 → §8-7

---

## 7. ★ 실기기 성능 측정 방법 — D5 · D9-8 공통

> **D5 결과는 §8-4 · 설계 §18-3-a, 완료된 D9-8 측정은 §8-7에 있습니다.** 아래는 재측정 시 사용하는 절차입니다.
> ⚠️ **§7-2(시뮬레이터 수치와 직접 비교 금지)는 실기기 수치가 실제로 생긴 지금 오히려 더 중요합니다** —
> 나란히 놓고 싶어지기 때문입니다. **설계 §18-3 표와 나란히 놓지 마십시오.**
> ⚠️ **§7-3 의 도구 표는 실행 결과와 어긋난 부분이 있고 §7-3-a 가 정정합니다.** §7-3-a 를 먼저 읽으십시오.

### 7-1. §18-3 의 방법이 실기기에 그대로 안 되는 이유

| §18-3 방법 | 실기기에서 | 왜 |
|---|---|---|
| `vmmap --summary <pid> \| grep "Physical footprint"` | ❌ 불가 | `vmmap` 은 **호스트 macOS 프로세스**를 봅니다. 시뮬레이터 앱은 Mac 위의 프로세스라서 통했습니다. iPad 에는 셸도 없고 그 프로세스를 볼 수단도 없습니다 |
| `ps -o time=` 델타, 0.25s 샘플링 | ❌ 불가 | 같은 이유 |
| `UserDefaults "title"` 에 JSON 시드 후 재기동 | ❌ 불가 | 시뮬레이터 컨테이너를 호스트 파일시스템에서 직접 고치는 방식입니다. 기기에서는 `devicectl device copy to` 로 밀어 넣어도 `cfprefsd` 캐시 때문에 신뢰할 수 없고, ❓ 이 문서에서 검증하지 못했습니다. **앱 UI 로 이동하십시오** (URL scheme 도 없음) |
| 자동 flick 11회 `(372,900)→(372,200)` | ⚠️ 그대로 불가 | 좌표는 iPad mini 744×1133pt 기준이며, 실기기에는 동일한 자동 입력 수단이 없습니다. **손가락 제스처를 횟수·방향·속도를 정해 반복**하고, 그 절차를 기록표에 적으십시오 |

### 7-2. ⚠️ §18-3 수치와 **직접 비교하면 안 되는** 이유

| # | 이유 |
|---|---|
| 1 | **메모리 회계가 다릅니다.** 시뮬레이터의 Physical footprint 는 호스트 macOS 커널의 값이고, 실기기는 iOS 커널의 `phys_footprint` 입니다. 공유 캐시·dyld·Metal 스택 구성이 다릅니다 |
| 2 | **CPU 시간이 무의미합니다.** 시뮬레이터는 앱 코드를 **Mac 의 M 시리즈 CPU** 에서 네이티브로 돌립니다. A17 Pro / M2 의 성능이 아닙니다 |
| 3 | **렌더 파이프라인이 다릅니다.** 시뮬레이터는 macOS WindowServer 를 경유합니다. 프레임 타이밍·hitch 는 실기기와 같은 종류의 값이 아닙니다 (§11 이 기준 7~11 을 Device 전용으로 둔 이유) |
| 4 | **압력이 없습니다.** 시뮬레이터에는 jetsam 메모리 압박도, thermal throttling 도 없습니다 |
| 5 | **입력이 다릅니다.** §18-3 은 자동 마우스 flick, 실기기는 손가락입니다. 스크롤 속도·거리·관성이 다릅니다 |
| 6 | **OS 가 다릅니다.** 설계 §18-3 은 시뮬레이터 **iOS 26.2**, 실기기는 **iPadOS 27.0 beta** 입니다 (§1-3). 툴체인은 둘 다 Xcode 26.3 으로 같아졌지만 **위 1~5 는 그대로 남습니다** |

**비교해도 되는 것:**

| 비교 가능 | 설명 |
|---|---|
| **A/B 상대값** | 같은 기기·같은 절차에서 구조 A vs 구조 B |
| **스케일링 형태** | `증분 ≈ 37 + 0.41·N` 의 **기울기/절편 구조** — 절 수에 선형인가, 초선형인가 |
| **알고리즘 복잡도** | O(N) 인가 O(N²) 인가. 절 수를 31 / 176 두 점으로만 봐도 판단 가능 |
| **정성적 현상의 재현 여부** | 예: §18-3 (D) "작은 장으로 옮겨도 메모리가 회수되지 않는다" 가 실기기에서도 그런가 |

> 이것이 §11 통과 기준 11번에 붙은 **△ 표기**("시뮬레이터 수치는 절대값으로 쓸 수 없고 A/B 상대 비교와 알고리즘 복잡도 확인에만 사용")의 뜻입니다.
> **실기기 D5 는 그 △ 를 ✅ 로 바꾸는 작업이지, §18-3 표에 새 열을 붙이는 작업이 아닙니다.**

### 7-3. 도구 선택과 근거

| 측정 대상 | 도구 | 근거 | 상태 |
|---|---|---|---|
| **peak memory (footprint)** | **Xcode Debug Navigator > Memory** | §18-3 의 Physical footprint 와 **같은 종류의 footprint 지표**를 코드 변경 없이 볼 수 있는 유일한 수단. Instruments Allocations 총합은 다른 지표. ❓ 두 값의 실측 대조는 못 했으니 **절대값 등가로 다루지 마십시오** | ✅ Instruments.app 존재 확인 |
| **메모리 귀속** | **Instruments `Allocations`** | 무엇이 얼마나 쌓이는지. §18-3 이 "PencilKit 캔버스 1개당 실제 점유" 를 못 쟀다고 적은 부분을 여기서 근사 | ✅ 템플릿 존재 |
| **프레임 드랍 / hitch** | **Instruments `Animation Hitches`** | 스크롤 hitch 를 ms/s 비율로 정량화. §18-3 이 "`CADisplayLink` 또는 Instruments 필요" 로 이월한 항목 그대로 | ✅ 템플릿 존재 |
| **CPU 분포** | **Instruments `Time Profiler`** | §18-3 의 "flick 중 한 코어 95~100%" 재현 확인 | ✅ 템플릿 존재 |
| **레이아웃 비용 근사** | **Instruments `SwiftUI`** | View body 평가·Core Animation commit. 코드 변경 없이 얻을 수 있는 최선의 layout 근사 | ✅ 템플릿 존재 |
| **정밀 layout 시간** | **`os_signpost`** | ~~코드 변경 필요 → Phase 2 이월. 저장소에 signpost 0건~~ → **rev.4: Phase 2 가 추가함** (카테고리 `ChapterLayout`, 인터벌 `measure`) | ✅ 가능 (실기기 미측정) |
| **MetricKit** | **쓰지 않습니다 (지금은)** | ① 저장소에 `MetricKit` 0건 → 구독 코드 추가가 필요(코드 변경), ② 보고가 **하루 단위 집계**로 도착해 A/B 스파이크에 부적합, ③ 개별 조작과 수치를 대응시킬 수 없음 | ❌ 지금 불가 |

> ★ **MetricKit 은 버리지 말고 위치를 옮기십시오.**
> §13 이 리스크로 적은 두 사각지대 — **120Hz ProMotion 기기**와 **저메모리 iPad** — 는 보유 기기로 덮을 수 없고,
> 대응이 "TestFlight 베타에서 확인" 으로 돼 있습니다. **MetricKit(`MXAnimationMetric` 의 hitch time ratio, `MXMemoryMetric` 의 peak memory)은
> 바로 그 베타 단계에서 실사용자 기기의 값을 모으는 수단으로 가장 적합합니다.**
> Phase 2~3 에서 계측을 넣을 때 signpost 와 함께 검토하십시오.

### 7-3-a. ★ 실행에서 드러난 재현 조건 2건 — 실행 전에 읽으십시오 (rev.3)

**둘 다 실측입니다. §7-3 의 도구 선택을 정정합니다.**

#### ① Instruments 기록에는 **USB 연결이 필수**입니다 ⚠️

| 연결 | 결과 |
|---|---|
| **Wi-Fi** (`Transport Type: localNetwork`) | ❌ **`Device disconnected` 로 1.1초 만에 끊깁니다.** ⚠️ `Deferred` 기록 모드라 **그때까지 모은 데이터도 함께 유실**됩니다 — 부분 결과조차 남지 않습니다 |
| **USB** (`wired`) | ✅ **201초 완주** |

> **실패가 "느려지는" 형태가 아니라 "기록 전체를 잃는" 형태**라 재현 조건으로 못박습니다.
> 무선 페어링된 기기가 목록에 보인다고 해서 기록이 되는 것이 아닙니다.
> **`xctrace record` 전에 케이블 연결을 눈으로 확인하십시오.**
> ❓ 다른 템플릿·다른 iOS 버전에서도 동일한지는 확인하지 않았습니다. 관측은 이 조합(Activity Monitor / iOS 27.0 beta) 1건입니다.

#### ② 스크롤 성능 측정에는 `Allocations` 가 아니라 **`Activity Monitor`** 를 쓰십시오 ⚠️

| 템플릿 | 결과 |
|---|---|
| `Allocations` | ❌ **오버헤드가 너무 커서 앱이 사실상 멈춥니다.** SwiftData 마이그레이션·CloudKit 동기화와 겹칠 때 특히 그렇습니다. **스크롤 조작 자체가 불가능해 측정 대상이 사라집니다** |
| **`Activity Monitor`** | ✅ 201초 기록 완주. `--all-processes` 로 붙였고 CarveApp 샘플 **188개** 확보 |

> ⚠️ **§7-3 표의 "메모리 귀속 → Instruments `Allocations`" 행을 스크롤 측정에 쓰지 마십시오.**
> 그 용도 자체(무엇이 얼마나 쌓이는가)는 유효하지만, **스크롤 부하와 같은 세션에서 잴 수 없습니다.**
> 두 측정을 분리하십시오 — 성능은 Activity Monitor, 귀속은 별도 세션.
>
> **§7-3 표의 "peak memory → Xcode Debug Navigator" 행도 실제로는 쓰지 않았습니다.**
> `xctrace` + Activity Monitor 로 **타임라인 전체**를 얻는 편이 구간별 관측에 낫고,
> 디버거 부착 오버헤드도 피할 수 있었습니다.

**실제로 쓴 명령 형태**

```bash
xcrun xctrace record \
  --template 'Activity Monitor' \
  --device "$DEV" \
  --all-processes \
  --output ~/carve-device-dump/d5-actmon-mini.trace
```

**읽은 지표:** `sysmon-process` 스키마의 **`memory-physical-footprint`**

> ★ **이 지표가 §18-3 이 `vmmap --summary` 로 잰 "Physical footprint" 와 같은 지표입니다.**
> §7-3 이 ❓ 로 남긴 *"Debug Navigator 값과 `vmmap` 값의 실측 대조를 못 했다"* 는 문제가,
> **애초에 같은 이름의 지표를 직접 읽음으로써 우회**됐습니다.
> ⚠️ **그렇다고 §7-2 가 무효가 되는 것은 아닙니다.** 지표 이름이 같아도
> **시뮬레이터(호스트 macOS 커널)와 실기기(iOS 커널)의 값은 여전히 다른 회계**입니다.
> **절대값 비교는 계속 금지입니다.**

### 7-4. 측정 절차를 반드시 문서화하십시오

§18-3 이 "재측정 시 그대로 반복" 이라고 적고 절차를 남긴 것과 같은 이유입니다.
아래를 §8-4 기록표에 채우십시오.

```
기기 / iOS 버전 / 화면 크기(pt)
Xcode 버전 / 빌드 configuration
장 지정 방법            (앱 UI 이동 — 딥링크 없음)
settle 대기 시간        (§18-3 은 cold launch 후 8초)
스크롤 절차             (방향 / 1회 이동량 / 횟수 / 간격 / 끝 도달 확인 방법)
측정 도구 및 버전       (Debug Navigator / Instruments 템플릿명)
디버거 부착 여부        (footprint 값에 영향)
```

---

## 8. 기록 양식

> 아래 표를 이 문서에 그대로 채워 넣으십시오.
> 완료 후 설계 문서의 **§18·§19 와 같은 부록**(예: 새 "부록 E — Phase 0A-D 실측 결과") 으로 옮길 수 있는 형태입니다.

### 8-1. 실행 환경 및 안전 조치 (D5 · D1 · D2 세션)

> **채우지 못한 칸은 빈칸으로 두지 않고 "미기록" 이라고 적었습니다** — 빈칸은 "값이 없다" 와
> "적지 않았다" 를 구분하지 못하고, 나중에 지어내기 쉬운 자리가 되기 때문입니다.
> **D9 세션의 환경은 §6-9 D9-0 과 §8-7 입니다.**

| 항목 | 값 |
|---|---|
| 실행일 | ❓ **미기록** (세션에 날짜를 남기지 않았습니다) |
| 실행자 | leetaek |
| Mac / macOS | ❓ **미기록** |
| Xcode | **26.3** |
| tuist (`mise x -- tuist version`) | ❓ **미기록** (§1-2 기준 4.39.0) |
| 저장소 커밋 (`git rev-parse --short HEAD`) | `cff1bdee` — 문서 반영 시점의 HEAD (branch `feat/canvas`). ❓ 세션 중의 정확한 커밋은 별도로 기록하지 않았습니다 |
| 워킹 트리 상태 | clean · **소스 변경 없음** (저장소에 이미 있는 Debug 빌드와 S4 하네스 사용) |
| **기기 A** — 모델 / iOS / 화면(pt) | **iPad mini (A17 Pro)** / **iOS 27.0 beta (24A5408d)** / ❓ 화면 pt 미기록 (§18-3 기준 744×1133pt) |
| **기기 B** — 모델 / iOS / 화면(pt) | ❌ **미사용.** iPad Air (M2) 는 이번 세션에서 쓰지 않았습니다 |
| **★ 기기 연결 방식** *(rev.3 추가)* | **USB (`wired`)** — ⚠️ **Wi-Fi 로는 Instruments 기록이 성립하지 않습니다** (§7-3-a ①) |
| **⚠️ 백업 완료 여부 / 시각 (기기 A)** | ❓ **미기록** |
| **⚠️ 백업 완료 여부 / 시각 (기기 B)** | 해당 없음 (기기 B 미사용) |
| ★ **백업 암호화 여부** (`IsEncrypted`) — **`false` 여야 합니다** | 해당 없음 — **D8 은 rev.10 에 이미 완료**됐고 이번 세션은 백업을 추출하지 않았습니다 |
| ★ 백업 디렉터리 (UDID) / `Last Backup Date` | 위와 같음 |
| ★ **터미널 FDA 부여 여부** (§1-2-a) | 위와 같음 (이번 세션에 불필요) |
| ★ `sqlite3` 버전 (`/usr/bin/sqlite3 --version`) | 위와 같음 (§1-2 기준 3.54.0) |
| 백업 시점의 App Store 판 버전 | ❓ **미기록** |
| **설치한 Debug 빌드 configuration / 번들 ID** | **Debug / `kr.co.carve.leetaek`** |
| **설치 후 기존 데이터 컨테이너 보존 여부** ★ | ✅ **보존됨.** `Carve.sqlite` **11.1 MB (3/23/26)** 가 그대로 있었습니다 → §2-3 1번 |
| **★ V4 마이그레이션 결과** *(rev.3 추가)* | ✅ 성공. `Carve.dev.sqlite` **7.4 MB → 8.8 MB**, 크래시 없음. `Carve.sqlite`(prod) **변동 없음** |

### 8-2. D1~D8 판정 요약

| ID | 결과 | 비고 |
|---|---|---|
| **D1** | ✅ **통과 (B) / ❌ 실패 (A)** | **§11 기준 7·8 이 A ❌ / B ✅ 로 갈려 스크롤 구조 B 확정** (설계 §12 U4). 상세 §8-3. ⚠️ D1-3·D1-4·D1-5 는 ❓ 미수행 |
| **D2** | ✅ **통과** | 기준 9 ✅(A·B) · 기준 10 ✅. 남은 것은 "두 손가락" 의 발견 가능성 = **제품 과제**. ⚠️ D2-4 palm rejection ❓ 미수행 |
| **D3** | ✅ **통과** | 실제 Pencil 로 S1 재확인 — 전 항목 시뮬레이터와 동일 (설계 §20-7) |
| **D4** | ✅ **통과** | 두 제스처 모두 정상. `SharedUndoManager` 오동작은 **관측되지 않았습니다** (설계 §20-7) |
| **D5** | △ **부분 통과** | baseline 확보 → Phase 2 착수 조건 해소. ⚠️ **layout 시간 · hitch · 기기 B 미측정.** 상세 §8-4 |
| **D6** | ✅ **관측 완료** | 회전·리사이즈 시 필사 배치가 바뀌고 되돌리면 복구 — G4 가 풀려는 문제 그 자체 (설계 §20-7). ⚠️ **iPad Air (M2) ❓ 미수행** |
| **D7** | △ **부분** | 컨테이너 V4 수용 · `.externalStorage` 미러링 · `rowUUID` · 큐 정상. ❌ **`CD_layoutMetadataData` 서버 스키마 없음**(설계 §10-1-a). ❓ 미검증 2건은 기기 2대 필요. 상세 §8-3 · 설계 §20-7 |
| **D7-pre** | ❓ **미수행** | 설치·entitlement 조건은 충족. **import/export 이벤트 관측은 하지 않았습니다** |
| **D8** | ✅ **통과** | `0e9a8449` 완료 (설계 §20-3). 실사용 blob 225행 → fixture 5건 |

### 8-3. 항목별 상세 기록

**D8 — legacy `lineData` 추출 (백업 경로)** — ✅ **완료** (`0e9a8449`, 2026-09-05). 값의 출처는 설계 §20-3.

| # | 판정 기준 | 관측 | 판정 |
|---|---|---|---|
| D8-0 | 백업이 비암호화 (`IsEncrypted = false`, `Manifest.db` = SQLite) | 비암호화 백업에서 §6-1 절차로 추출 성공 | ✅ |
| D8-1 | `AppDomain-kr.co.carve.leetaek` 도메인에 `Library/Application Support/Carve.sqlite` 존재 | 존재 | ✅ |
| D8-2 | 추출 누락 0건 + `Carve.sqlite` 가 `sqlite3` 로 열림 | **파일 누락 0**, 열림 | ✅ |
| D8-3 | 드로잉 테이블 행 ≥ 1, 블롭이 있는 행 존재 | `ZBIBLEDRAWING` **225행** · 디코드 **225/225 성공** | ✅ |
| D8-4 | `ZDRAWINGVERSION` 이 `1` 또는 `NULL` 인 행 존재 | **전부 `1`** — 설계 §2 D3 "죽은 필드" 진단 실증 | ✅ |
| D8-5 | `ZCREATIONDATE` 최솟값이 1.2.0 배포 이전 | 범위 **2025-02-13 ~ 2026-03-23** → 1.2.0 배포(2025-12-08~)보다 이릅니다 | ✅ |
| D8-6 | `.externalStorage` 블롭 누락 없음 (또는 "전부 인라인" 확인) | 인라인 **224행**(최대 111KB) + 외부저장 **1행**, 누락 0 | ✅ |

**S5 fixture 성립 여부:** D8-0·1·2·3·6 통과 + (D8-4 또는 D8-5) → ✅ **성립**

| 항목 | 값 |
|---|---|
| 백업 디렉터리 (UDID) | ❓ 미기록 |
| 백업 시각 (`Last Backup Date`) | ❓ 미기록 (추출일 **2026-09-05**) |
| 덤프 저장 위치 (저장소 밖) | `~/carve-device-dump/` |
| 복사한 파일 수 / 디렉터리 수 / **누락 수** | ❓ 미기록 / ❓ 미기록 / **0** |
| `.tables` 실제 출력 (테이블명) | ❓ 전체 미기록. 확인된 것: `ZBIBLEDRAWING` · `ZBIBLEPAGEDRAWING` |
| 드로잉 테이블 행 수 | `ZBIBLEDRAWING` **225** · `ZBIBLEPAGEDRAWING` **0** ★ |
| 블롭 길이 분포 (최소 / 중앙 / 최대) | ❓ 미기록 / ❓ 미기록 / **111 KB** (인라인 최대) |
| `_EXTERNAL_DATA` 파일 수 / 총 크기 | **1** / ❓ 미기록 |
| `ZDRAWINGVERSION` 분포 | **전부 `1`** |
| `ZCREATIONDATE` 범위 (UTC) | **2025-02-13 ~ 2026-03-23** |
| fixture 후보로 고른 블롭 (개수 / 길이 / 인라인·external 여부) | **5건** (base64 내장). 길이·저장형태 ❓ 미기록 |
| 개인정보 제거 조치 | 권·장·절·날짜 등 **식별 메타 제거** 후 base64 상수로 내장 |
| 덤프 사후 처리 (삭제 / 이동 위치) | 저장소 밖 `~/carve-device-dump/` 유지, **커밋하지 않음** |

> ★ **`ZBIBLEPAGEDRAWING` 0행** — `BiblePageDrawing` 은 실사용 데이터가 **전무**합니다.
> 설계 부록의 "캐시/복구 전용 격하 → 장기 제거" 를 **마이그레이션 부담 없이** 수행할 수 있습니다.
>
> ⚠️ **확보하지 못한 것:** 225건은 **전부 절 로컬 좌표**입니다. 1.2.0 배포 기간에 이 기기로 필사한
> 기록이 0건이라, **절대좌표 fixture 는 실데이터가 아니라 합성**입니다 (설계 §20-3 · §10-2).

**D7-pre — CloudKit 미러링** *(rev.3: 미실행. 아래는 부수 확인으로 알게 된 것뿐입니다)*

| # | 판정 기준 | 관측 | 판정 |
|---|---|---|---|
| D7-pre-1 | entitlement 에 컨테이너 2개 존재 | ⚠️ `codesign -d --entitlements` 로 **직접 확인하지 않았습니다.** 다만 **CloudKit entitlement 를 요구하는 서명으로 설치·실행이 성공**했으므로 `<dict></dict>`(§18-5 1번의 시뮬레이터 상태)는 아닙니다 | ⚠️ **간접 정황** |
| D7-pre-2 | `CKAccountStatus == .available` | ❌ **미관측** (Xcode 콘솔의 `"CloudKit 초기화 실패…"` 유무를 보지 않았습니다) | **미실행** |
| D7-pre-3 | import/export 이벤트 관측 | ❌ **미관측** (`cloudEvent` 로그 미확인) | **미실행** |

> ★ **rev.3 부수 확인 — D7 의 일부는 진전했습니다.**
>
> | 관측 | 값 |
> |---|---|
> | **V4 마이그레이션이 실기기에서, CloudKit entitlement 가 활성인 상태로 성공** | `Carve.dev.sqlite` **7.4 MB → 8.8 MB**, 앱 **크래시 없음** |
> | `Carve.sqlite` (prod / App Store 판) | **변동 없음** → **Debug/Release 분리가 설계대로 동작** (§2-2 1·2번의 실증) |
>
> ⚠️ **이것은 "마이그레이션이 실기기에서 돈다" 까지입니다. 미러링 검증은 여전히 미완입니다.**
> 설계 §20-5 의 미검증 4건 — `NSPersistentCloudKitContainer` 의 V4 수용 ·
> `layoutMetadataData` 의 CKAsset 미러링 · 메타데이터 없는 행의 도착 · `isPresent` 복수 충돌 —
> 은 **하나도 확인되지 않았습니다.** **설계 §13 의 배포 판단 조건은 그대로입니다.**
>
> ⚠️ **주의: prod 컨테이너를 확인하려고 Release 빌드를 설치하지 마십시오** (§6-3 의 경고 그대로 유효).

**D6 — Stage Manager / 리사이즈** — ✅ **관측 완료.** ⚠️ **결과는 설계 §20-7 에만 있고 아래 항목별 칸은 채워지지 않았습니다.**
요지: 회전·리사이즈 시 레이아웃은 깨지지 않으나 **필사 배치가 바뀌거나 잘려 보이고, 되돌리면 복구**됩니다 (폭이 바뀌면 개행 수가 바뀌는데 현재 구조에 reflow 가 없기 때문 — G4 가 풀려는 문제).
⚠️ **iPad Air (M2) 와 Stage Manager / Split View 자체의 동작은 ❓ 미수행**이라 **§11 기준 3 의 적용 가능 여부는 아직 미결**입니다 (§10-3 6번).

| # | 판정 기준 | 관측 | 판정 |
|---|---|---|---|
| D6-1 | Stage Manager 에서 리사이즈됨 | | |
| D6-2 | 리사이즈 후 필사 위치 유지 | | |
| D6-3 | Split View / Slide Over 진입 | | |
| D6-4 | 왼손잡이 전환 후 좌표 정합 (§11 기준 4) | | |
| D6-5 | 외부 디스플레이 동작 | | |
| D6-6 | 화면 회전 동작 | | |

> **§11 기준 3 적용 가능 여부 결론:** ______

**D3 — 실제 Pencil 지우개** — ✅ **완료.** ⚠️ **결과는 설계 §20-7 에만 있고 아래 항목별 칸은 채워지지 않았습니다.**
요지: **S1 과 동일** — 획 1개가 stroke 2개로 분할되고 각각 다른 `mask`, `seed`/`creationDate`/`points` 는 동일(IdentityKey 1개),
완전히 지운 획은 `strokes` 에 없음. → 설계 §7-2 · §7-3 · §7-4 가 실기기에서 유효.

| # | 판정 기준 (S1 결론과 동일한가) | 관측 | 판정 |
|---|---|---|---|
| D3-1 | `randomSeed` 라운드트립 보존 | | |
| D3-2 | 분할 + 마스킹 동시 | | |
| D3-3 | IdentityKey 구성요소 전부 불변 | | |
| D3-4 | `mask` / `maskedPathRanges` 보존 | | |
| D3-5 | 완전히 지운 stroke 제거 + DB 길이 감소 | | |

| 스냅샷 | 블롭 길이 | stroke 수 | 비고 |
|---|---|---|---|
| 원본 (획 1개) | | | |
| 가운데 지운 뒤 | | | |
| 전부 지운 뒤 | | | |

**D4 — 제스처** — ✅ **완료.** ⚠️ **결과는 설계 §20-7 에만 있고 아래 항목별 칸은 채워지지 않았습니다.**
요지: Pencil 더블탭 지우개 전환 · 두 손가락 더블탭 undo(절을 넘나드는 순차 undo 포함) **모두 정상.**
⚠️ **D4-3 의 "오동작 예상" 은 빗나갔습니다** — `SharedUndoManager` 삭제 근거는 "깨져 있어서" 가 아니라 **"단일 Canvas 에서 불필요해서"** 입니다.

| # | 판정 기준 | 관측 | 판정 |
|---|---|---|---|
| D4-1 | Pencil 더블탭 → 지우개 전환 | | |
| D4-2 | 다시 더블탭 → 직전 펜 복귀 | | |
| D4-3 | 두 손가락 더블탭 → undo | | |
| D4-4 | `canUndo` 상태 정합 | | |
| D4-5 | 다른 제스처와 충돌 | | |

**D1 — Pencil 입력** ★ **실행 완료 — 스크롤 구조가 여기서 결정됐습니다**

> 설계 §13 의 지시("새 하네스를 만들지 말고 **같은 S4 하네스를 실기기에서 그대로 돌려라**")를 따라
> **S4 하네스(`-CanvasScrollSpike`)를 모드 A / B 로 각각 띄워 Apple Pencil 로 관측**했습니다.
> 따라서 아래는 §6-7 의 D1-1~D1-5 항목이 아니라 **설계 §11 통과 기준 7·8 의 A/B 판정**입니다.

| 기준 | 모드 A | 모드 A + `A정규화` ON | 모드 B |
|---|---|---|---|
| **§11 기준 7** live stroke pencil-up | ❌ **그리는 동안 다른 위치에 렌더되고, 펜을 떼면 정상 위치로 점프** | ❌ **동일하게 실패** | ✅ **위치·크기 동일** |
| **§11 기준 8** hover 중 좌표 | ❌ **크게 어긋남** | ❌ **동일하게 실패** | ✅ **HUD `peak 0.000`** |

**★ 원인을 가른 결정적 관찰**

| # | 관측 | 해석 |
|---|---|---|
| 1 | 모드 A 에서 hover 시 **시스템이 그리는 펜슬 그림자는 정상 위치**에 뜨는데, **PencilKit 이 그리는 hover 잉크 점만 어긋난다** | 그림자는 **윈도우/화면 좌표계**, 잉크 점은 **캔버스 자신의 content 좌표계**. 어긋나는 것은 입력 좌표가 아니라 **캔버스의 스크롤 상태 인식** |
| 2 | **어긋남의 크기가 스크롤 깊이에 비례해 커진다.** 맨 위에서는 정상 | **오차 = 바깥 `ScrollView` 의 `contentOffset`** 이 실측으로 확정 |
| 3 | **`A정규화` 를 켜도 동일하게 실패한다** | **보정으로 구제 불가.** `StableCanvasView` 가 하던 offset 0 고정과 PencilKit 의 라이브 렌더는 **구조 A 에서 동시에 만족 불가** — 과거 두 번의 롤백을 설명합니다 |

**§6-7 의 원래 항목들 — 이번 세션의 대응**

| # | 판정 기준 | 관측 | 판정 |
|---|---|---|---|
| D1-1 | hover 중 화면 이동 없음 | 위 기준 8 로 대체 관측 (하네스 기준) | **A ❌ / B ✅** |
| D1-2 | pencil-up 시 live stroke 스냅 없음 | 위 기준 7 로 대체 관측 | **A ❌ / B ✅** |
| D1-3 | 스크롤 중 필기 위치 정확 | ❌ **미관측** (별도 항목으로 분리해 재지 않았습니다) | **미실행** |
| D1-4 | 절 경계 획 끊김 지점 | ❌ **해당 없음** — 하네스는 장 전체가 캔버스 하나라 절 경계가 없습니다. **현행 N-Canvas 화면에서는 미관측** | **미실행** |
| D1-5 | fling 직후 필기 좌표 정합 | ❌ **미관측.** §11 기준 2 의 관성 fling 이 이번에도 남았습니다 | **미실행** |

**D2 — 손가락 입력과 스크롤 UX** — ✅ **실행 완료**

| # | 판정 기준 | 관측 | 판정 |
|---|---|---|---|
| D2-1 | pencilOnly 에서 한 손가락 스크롤 | **A·B 모두 정상** — **§11 기준 9** | ✅ **통과 (A·B)** |
| D2-2 | **§11 기준 10** — anyInput 에서 스크롤 방법이 명확한가 | 모드 B + `allowFingerDrawing = true`(`.anyInput`) 에서 **한 손가락 그리기 / 두 손가락 스크롤**. 동작이 명확하고 **스크롤 수단이 사라지지 않음** | ✅ **통과** |
| D2-3 | anyInput 에서 스크롤 가능한 영역 | **두 손가락이면 어디서나** — rev.1 이 우려한 "캔버스 위에서 스크롤 수단이 사라짐" 은 일어나지 않았습니다 | ✅ |
| D2-4 | palm rejection | ❌ **미관측** | **미실행** |

> ★ **기준 9 는 A·B 를 구별하지 못했습니다.** rev.2 §3-2 가 *"기준 9 는 옵션 B 를 전제한 항목인데
> 판정 대상 구조가 없다"* 고 적었으나, S4 하네스로 두 구조를 다 띄워 보니 **양쪽 다 정상**이었습니다.
> **A/B 를 가른 것은 기준 7·8 뿐입니다.**

> ⚠️ **기준 10 에 남은 것은 구조 문제가 아니라 제품 과제입니다.**
> "두 손가락으로 스크롤한다" 를 **사용자가 발견할 수 있는가** — 안내·온보딩·설정 문구의 문제이며
> 호스팅 구조 A/B 선택과 무관합니다. §11 통과 기준으로서는 **통과**입니다.
> → §8-6 에 후속 항목으로 올렸습니다.

### 8-4. D5 실측 기록 ★

> ⚠️ **계획했던 (A)~(D) 시점별 스냅샷 표로는 기록할 수 없었습니다.** 그 형태는 Debug Navigator 로
> 시점마다 값을 읽는 것을 전제하는데, 실제로는 **`xctrace` 로 201초 타임라인 하나를 통째로 기록**하고(§7-3-a ②)
> 그 안에서 구간을 나눴습니다. **두 형태의 차이 자체가 재현 정보이므로 아래에 그대로 적습니다.**
> ⚠️ **구간과 조작의 대응은 타임라인 형태로 추정한 것이며, 정확한 전환 시각은 기록되지 않았습니다.**

**측정 절차 (이 문서 §7-4 항목)**

| 항목 | 값 |
|---|---|
| 기기 / iOS / 화면(pt) | **iPad mini (A17 Pro)** / **iOS 27.0 beta (24A5408d)** / ❓ pt 미기록 |
| Xcode / configuration | **26.3** / **Debug** (개발 서명) |
| **기기 연결** ★ | **USB (`wired`)** — ⚠️ **Wi-Fi 로는 1.1초 만에 끊기고 데이터도 유실됩니다** (§7-3-a ①) |
| 장 지정 방법 | **앱 UI 로 이동** (딥링크 없음 — §1-1 `CFBundleURLTypes` 0건) |
| settle 대기 | ❓ **미기록.** §18-3 의 "8초" 를 그대로 지켰는지 확인되지 않습니다 |
| 스크롤 절차 (방향/이동량/횟수/간격) | ❌ **계측하지 않았습니다.** 손가락 조작이며 속도·횟수를 세지 않았습니다 ⚠️ **재현성의 최대 약점** |
| 끝 도달 확인 방법 | ❓ **미기록** |
| 디버거 부착 여부 | ❌ **부착하지 않음** — `xctrace` 로 붙였습니다 (Debug Navigator 미사용) |
| 사용 도구 / 템플릿 | **`xctrace record --template 'Activity Monitor' --all-processes`** · 기록 길이 **201초** · CarveApp 샘플 **188개** |
| **읽은 지표** ★ | `sysmon-process` 스키마의 **`memory-physical-footprint`** — **§18-3 이 잰 "Physical footprint" 와 같은 지표** |

**(A)~(D) — 시점별 스냅샷 형태로는 미기록.** 연속 타임라인이라 그 칸들에 대응하는 값이 없고,
억지로 채우면 지어낸 값이 되므로 아래 **(A′)·(D′)** 로 대체합니다. **기기 B(Air) 는 전부 미측정입니다.**

**(A′) 구간별 관측 — 실제로 기록된 형태** ★

| 구간 | 메모리 (MB) | 평균 CPU |
|---|---|---:|
| 기동 ~ settle | 54.7 ~ 237.7 | 8.2% |
| 창세기 1장(31절) 진입·스크롤 | 70.9 ~ 276.7 | 35.5% |
| 저부하 구간 | 71.5 ~ 72.9 | 21.6% |
| **시편 119편(176절) 진입·스크롤** | 73.0 ~ **363.6** | **84.5%** |
| 시편 120편(7절) 전환 직후 | 104.9 ~ 164.8 | 4.3% |
| **정지 유지** | **109.7** (평평) | 0.1% |

| 요약 | 값 |
|---|---|
| 전체 peak | **363.6 MB** (t = 95.1 s) |
| 기동 직후 | 62.2 MB |
| 최종 정지 | **109.7 MB** |
| CPU > 90% 샘플 | **47 / 188 (약 25%)** |

**(D′) 메모리 회수 — §18-3 (D) 재현 여부** ★ **이번 D5 의 가장 중요한 결과**

| | §18-3 (시뮬레이터) | **실기기 (rev.3)** |
|---|---|---|
| 시편 119편 스크롤 후 | 195.2 MB | **363.6 MB** (peak) |
| 작은 장(시편 120편)으로 이동 후 | **209.3 MB — 오히려 증가** | **109.7 MB — 회수됨** |
| 추가 대기 | 209.5 MB (그대로) | **109.7 MB 평평 유지** |
| 판정 | 회수되지 않음 | ❌ **재현되지 않음** |

> ★ **이것은 §7-2 가 "비교해도 되는 것" 으로 꼽은 정성적 현상의 재현 여부에 해당하며,
> 재현되지 않았습니다.**
> → 설계 §18-5 3번("장 전환 시 메모리 미회수는 기존부터 존재")과 §18-3 (D) 는
> **시뮬레이터 한정으로 읽어야 합니다.** 그 면책 논거를 실기기 평가에 그대로 쓸 수 없습니다.
> 설계 반영: §18-3-a · §18-5 정정 블록.

**(E) 판정** — §6-2 의 D5-1~D5-5

| # | 판정 기준 | 결과 |
|---|---|---|
| D5-1 | 크래시·jetsam 종료 없음 | ✅ **통과** — 201초 완주, 종료 없음 |
| D5-2 | 절 수 대비 메모리 증분의 **형태**가 선형 | ❓ **판정 보류** — 구간 경계가 추정치라 31절/176절 두 점의 증분을 신뢰 구간으로 잡을 수 없습니다. **초선형 폭발의 징후는 관측되지 않았습니다** |
| D5-3 | 장 전환 후 미회수 현상 재현 | ❌ **재현되지 않음** ★ (D′) |
| D5-4 | 시편 119편의 hitch 가 창세기 1장 대비 유의하게 나쁨 | ❓ **미측정** — Activity Monitor 에 hitch 지표가 없습니다. 다만 **CPU 는 35.5% → 84.5% 로 명확히 악화** |
| D5-5 | mini vs Air 유의차 | ❓ **미수행** — Air 미측정 |

**⚠️ 한계 — 반드시 함께 읽으십시오**

| # | 한계 |
|---|---|
| 1 | **iOS 27 beta 수치**입니다 (24A5408d) |
| 2 | **1회 측정.** 분산을 모릅니다 |
| 3 | **스크롤 속도·횟수 미계측.** §18-3 의 "flick 11회 (372,900)→(372,200)" 같은 고정 절차가 아닙니다 |
| 4 | **구간과 조작의 대응은 타임라인 형태로 추정**한 것이며 **정확한 전환 시각은 기록되지 않았습니다** |
| 5 | **§18-3 과 절대값 비교 불가** (§7-2) |
| 6 | **iPad mini 한 대.** Air (M2) 미수행 |
| 7 | **hitch time ratio · 정밀 layout 시간 미측정** (후자는 `os_signpost` 부재로 **Phase 2 이월**) |

> ⚠️ **이 표의 수치를 §18-3 표와 나란히 놓고 "개선/악화" 를 말하지 마십시오.** 이유는 §7-2.

### 8-5. §11 통과 기준 — 실기기 항목 (7~11)

> S4 하네스(`b53cbfd8`)를 실기기에서 돌려 7·8·9·10 을 모두 판정했습니다. 아래 "지금 판정 가능?" 열은
> 그 전후를 함께 남긴 것입니다. **⚠️ §11 기준 2(관성 fling)·3(리사이즈)·5(탭/롱프레스)는 D9-7 로 이월돼 아직 ❓ 미수행입니다.**

| # | 기준 | 지금 판정 가능? | 관측 | 판정 |
|---|---|---|---|---|
| **7** | live stroke 가 pencil-up 순간 확대·이동하지 않음 | ~~아니오~~ → **예** (S4 하네스 구현됨) | **A: 그리는 동안 다른 위치에 렌더되고 펜을 떼면 정상 위치로 점프. `A정규화` 를 켜도 동일. B: 위치·크기 동일** | **A ❌ / B ✅** |
| **8** | Pencil hover 중 좌표 변화 없음 | ~~아니오~~ → **예** | **A: 크게 어긋남(`A정규화` 무관). B: HUD `peak 0.000`.** ★ 그림자는 정상 위치인데 잉크 점만 어긋나고, 어긋남이 스크롤 깊이에 비례 → **오차 = 바깥 `ScrollView` 의 `contentOffset`** | **A ❌ / B ✅** |
| **9** | `.pencilOnly` 에서 한 손가락 스크롤 가능 | ~~아니오~~ → **예** | **A·B 모두 정상 스크롤** | ✅ **통과 (A·B)** |
| **10** | `allowFingerDrawing == true` 일 때 스크롤 방법이 명확 | **예** — D2-2 로 판정 | 모드 B + `.anyInput` 에서 **한 손가락 그리기 / 두 손가락 스크롤**. 스크롤 수단이 사라지지 않음 | ✅ **통과** (발견 가능성은 **제품 과제**) |
| 11 | 시편 119편 layout 시간·peak memory (baseline 대비) | **부분** — memory/hitch 는 D5, layout 시간은 Phase 2 | memory·CPU baseline 확보 (§8-4). **hitch 미측정 · layout 시간 미측정** | △ **부분** |

> ★ **§11 통과 기준 7·8 이 A 와 B 를 갈랐습니다 → 스크롤 구조 B 확정** (설계 §12 U4).
> 설계 §11 이 *"S4 는 A/B 를 구별하지 못했다. 실패는 라이브 Pencil 입력·hover·렌더 타이밍에서
> 나오며 그건 기준 7·8 — 실기기 전용"* 이라고 예측했고, **그 예측이 그대로 맞았습니다.**

### 8-6. 후속 작업 / 설계 문서 반영 사항

| # | 발견 | 영향 | 반영할 곳 |
|---|---|---|---|
| **R1~R3** | ✅ **소진.** R1 `devicectl` 이 App Store 앱 컨테이너에 접근 못 함 → §6-1-0 에 반영 · R2 멤버십 차단 → 해제됨 · R3 "D5 를 Phase 2 전에 못 잴 위험" → **실현되지 않음**(Phase 2 착수 전에 쟀습니다) | — | §6-1-0 · §3-1 · 설계 §18-3-a |
| **R4** | ★ **§11 기준 7·8 이 실기기 Pencil 입력에서 A ❌ / B ✅ 로 갈렸다.** `A정규화` 를 켜도 A 는 동일하게 실패 | **스크롤 구조 A 는 채택 불가.** 보정 실패가 아니라 **구조적 모순** — offset 0 고정과 PencilKit 라이브 렌더는 A 에서 양립 불가 | 설계 **§12 U4 (확정: B)** · §11 "D1/D2 실행 결과" · §2 D5 · §17 — **반영 완료** |
| **R5** | **오차의 정체 = 바깥 `ScrollView` 의 `contentOffset`** (스크롤 깊이 비례 + 펜슬 그림자는 정상 위치) | `StableCanvasView` 는 **재작성에 흡수** 가 아니라 **접근 자체 폐기**. 스케일 동기화(①)도 A 전용 증상 대응이라 이월 대상이 아님 | 설계 **부록(삭제/격하)** · §13 Phase 4 — **반영 완료** |
| **R6** | ★ **설계 §18-3 (D) 의 "메모리 미회수" 가 실기기에서 재현되지 않았다** (363.6MB → 109.7MB 회수) | 설계 §18-5 3번의 면책 논거("기존부터 존재하니 새 설계 탓이 아니다")를 **실기기 평가에 그대로 쓸 수 없음.** Phase 3 이후 실기기에서 회수가 안 되면 **그것은 새로운 현상** | 설계 **§18-3-a** · **§18-5 정정 블록** — **반영 완료** |
| **R7** | **개발 서명 설치가 App Store 앱의 데이터 컨테이너를 보존한다** (`Carve.sqlite` 11.1MB 생존). Debug/Release DB 분리도 실증 | §2-3 1번의 최대 미확인 위험이 해소. ⚠️ **다만 1회 관측이므로 §2-4 백업 절차는 유지** | 이 문서 §2-0 · §2-3 · §10-3 — **반영 완료** |
| **R8** | **V4 마이그레이션이 실기기에서, CloudKit entitlement 활성 상태로 성공** | **D7 의 일부만 진전.** 설계 §20-5 의 미검증 4건(미러링)은 그대로 → **Phase 1 배포 판단 조건 불변** | 설계 §13 · **§20-6 ②** — **반영 완료** |
| **R9** | **Instruments 기록에 USB 필수** (Wi-Fi 는 1.1초 만에 끊기고 `Deferred` 라 데이터도 유실) · **`Allocations` 는 스크롤 측정 불가** | D5 재측정·D6·Phase 2 측정의 **재현 조건** | 이 문서 **§7-3-a** — **반영 완료** |
| **R10** | ⚠️ **`allowFingerDrawing == true` 의 "두 손가락 스크롤" 을 사용자가 발견하지 못할 수 있다** | **구조 문제가 아니라 제품 과제.** 안내·온보딩·설정 문구 | 설계 §15 리스크표 — **반영 완료.** 제품 백로그 항목으로 별도 관리 필요 |
| **R11** | ⚠️ **iPad Air (M2) 가 통째로 미수행** | **D5-5(기기 간 유의차)** 와 **D6**(설계 §13 표가 Air 를 지목)이 열려 있음. 설계 §13 의 사각지대(120Hz·저메모리)도 그대로 | **실행 판단 필요** — §4 |
| **R12** | ⚠️ **설계 §20-4 의 "실기기에서 fling·탭/롱프레스도 함께 해소된다" 는 예상이 빗나감** | §11 기준 2·5 가 여전히 미수행. **실기기에서 불가능해서가 아니라 세션이 기준 7~10 에 집중했기 때문** | **D9-7 로 이월** — §4 · §6-9 |

### 8-7. D9 실측 기록

> **현재 상태 (2026-09-09 · rev.19 정리)**
>
> | 항목 | 판정 |
> |---|---|
> | D9-0-c 스모크 · D9-0-d (`H` 비교) | ✅ **통과** — R13 · R16 종결 후 재검증 |
> | **D9-1** 필기 → 저장 → 재실행 복원 | ✅ **통과** |
> | **D9-2** 지우개 | ✅ **통과** |
> | **D9-6** flag 토글과 롤백 | ✅ **통과 (2026-09-08 재검증)** — **R23**(강등)·**R24**(잉크 미표시) 둘 다 수정하고 실기기에서 확인했다. 이전 ✅ 는 화면만 보고 DB 를 안 본 판정이었고, 이번에는 DB·HUD 콘솔·화면을 모두 봤다 |
> | **D9-3-1·2** undo/redo · 더블탭 | ✅ **통과** |
> | **D9-3-4** reflow 후 잉크 재배치 | ✅ **통과** — v1·v3 모두 따라감. **E-4 종결** (undo 스택 초기화 여부는 ❓ 미확인) |
> | **D9-4-1·4** 장 전환 flush · 잉크 혼입 | ✅ **통과** |
> | **D9-7-4** 회전 후 재필기 | ✅ **통과** — 회전 12회 중 12획, 유실 0 |
> | **D9-8** 성능 | ✅ **측정 완료** — 진입 비용은 A/B 동일, 재합성 전이 peak 은 큰 차이 (R20) |
> | **D9-H** 회전 표시 | ✅ **종결** — 조사 §6 잔여 검증 완료. 별개 결함 R23·R24도 수정 후 N-Canvas 왕복 재확인 |
> | **D9-5** 히스토리 메뉴 | ✅ **통과** — 5-1(메뉴)·5-2(시트·절 귀속)·5-6(손가락 필사 충돌 없음) 확인. 5-4·5-5 는 회차가 쌓이지 않는 설계라 **판정 불가**. ⚠️ 다만 **R25** 를 함께 발견 |
> | **D9-7-1 · D9-7-3** | ✅ **통과** — XCUITest 실기기 자동화 (2026-09-09) |
> | **D9-CK③** CloudKit 승격 | ✅ **완료 (2026-09-09)** — Production 에 `CD_layoutMetadataData` · `CD_rowUUID` 추가. 배포 전 죽은 필드·타입 정리 |
> | **D9-7-2** | ❓ **미수행** — Pencil 필요 |
>
> ⚠️ **절 단위 판정입니다 — 아래 "판정 요약" 표의 항목별 관측은 기록되지 않았습니다.**
> 재수행할 때 채우십시오.
>
> **후속 항목:** R17·R18·R20·R22·R25·R27·R28. **E-4·R21·R23·R24·R26은 종결**. 판정 근거는 아래 후속 작업 표, 작업 순서는 [2.0.0 로드맵](./release-2.0.0-roadmap.md) 참조.

> **채우는 방법:** 판정은 ✅ 통과 / ❌ 실패 / △ 부분 / ❓ 미수행 넷 중 하나만 씁니다.
> ⚠️ **"아마 됐다" 를 ✅ 로 적지 마십시오.** §8-4 가 남긴 교훈이 그것입니다 — 스크롤 절차를 세지 않아
> D5-2 가 **판정 보류**로 끝났습니다. **관측하지 않은 것은 ❓ 로 남기는 편이 낫습니다.**

**실행 환경**

| 항목 | 값 |
|---|---|
| 실행일 | 2026-09-08 (D9 H 세션). 앞선 스모크·R13/R16 재검증 세션의 날짜는 ❓ 미기록 |
| 기기 / iOS / 화면(pt) | iPad mini (A17 Pro) `iPad16,2` / iPadOS 27.0 beta (24A5408d) / ❓ pt 미기록 |
| Mac / Xcode / configuration | macOS 26.3 (25D125) / Xcode 26.3 (17C529) / Debug (개발 서명) |
| **기기 연결** ★ | **`wired`** — ⚠️ 기록 직전에 반드시 재확인 (§7-3-a ①) |
| 실행 인자 | `-SingleCanvas -ChapterLayoutOverlay` (+ D9 H 세션은 `-CanvasDisplayProbe`) |
| flag 경로 | 실행 인자 / 설정 토글 (D9-6 은 토글) |
| 백업 (§2-4) | ❓ 미기록 |
| 실기기 빌드·설치·실행 | ✅ 성공 |
| 회귀 기준선 | **312** (설계 §19-4-2). ⚠️ 아래 기록에 남은 265 · 296 은 그 시점의 이력입니다 |

**D9-0-c 스모크 — 실행 결과 (진행 중) ★ 결함 1건**

| 항목 | 기대 | 실측 | 판정 |
|---|---|---|---|
| `gate` | PASS | (미기록) | ❓ |
| 절 수 | 176/176 | (미기록) | ❓ |
| **`Δ max`** | **0.00** (tol 1.00pt) | **87.50** | ❌ **실패** |
| `worst` | — | **v176 · top +87.50 · height +0.50** | — |
| `columnX` | 366.70 (세로) | 세로 **366.70** ✅ / 가로 **556.34** | ✅ |
| `missing` | 없음 | (미기록) | ❓ |

**Δ 87.50 — 절당 0.5pt 누적** (`175 × 0.50 = 87.50`, v176 이 worst)

| 조건 | Δ max | 뜻 |
|---|---|---|
| 가로 (container 1133pt) | **87.50** | — |
| **세로** (container 744pt) | **87.50** | 폭·줄 수와 무관 → **줄당이 아니라 절당 상수** |
| **N-Canvas** (`-SingleCanvas` 없이) | **87.50** | **Phase 3 무관.** 두 경로가 공유하는 행 뷰/빌더 쪽 |
| **폰트 변경 후** | **87.50** | 폰트·행간과 무관 → **텍스트 메트릭 반올림 아님.** `sig` 가 함께 바뀐 것을 확인했으므로 레이아웃은 실제로 재계산됐다 (실험 유효) |
| **다른 길이의 장** | **예측대로** | 창세기 1장(31절) **15.00** = 30 × 0.5 등. **절당 0.5pt 선형 누적 확정** |
| **창세기 2장 (25절)** | ⚠️ **1335.78** | 아래 별도 항목 — 같은 현상이 아니다 |

`columnX` 는 정상입니다 — 가로 556.34 는 `halfWidth(566.5) − 행 padding(10)` 으로 예측치 556.5 와 0.16pt 차이,
세로 366.70 은 AGENTS.md 기준값과 일치. **방향에 따른 컨테이너 폭 차이일 뿐 결함이 아닙니다.**


**절별 Δ 프로파일 (rev.5 계측)**

```
창세기 1장   h[min +0.50 max   +0.50]  slope  +0.500/절
             top v1 +0.00 · v8   +3.50 · v16   +7.50 · v31   +15.00      ← 완전 선형
창세기 2장   h[min +0.50 max +152.50]  slope +55.657/절
             top v1 +0.00 · v7 +342.40 · v13 +735.53 · v25 +1335.78      ← 선형 아님
```

⚠️ **창세기 2장은 시편 119편·창세기 1장과 같은 현상이 아닙니다.**

| 근거 | 뜻 |
|---|---|
| `top` 값이 **0.5의 배수가 아님** (342.40 · 735.53 · 1335.78) | 픽셀 반올림 누적이 아니라 **실측 float 이 섞인** 값 |
| `slope` 55.657 — 행 높이(≈`lineSpace`)보다 크다 | 절당 한 줄 이상씩 어긋남 |
| `h min` 은 여전히 **+0.50** | 일부 절은 정상 패턴, 일부만 폭발 |
| `h max` **+152.50** | 특정 절의 높이가 예측보다 152.5pt 큼 |

**본문 데이터 확인 (`1-01Genesis.txt`, EUC-KR):**

| 장 | 절 수 | 소제목 |
|---|---:|---|
| 창세기 1장 | 31 | **1:1** `<천지 창조>` — 장 **첫 절** |
| 창세기 2장 | 25 | **2:4** `<에덴 동산>` — 장 **중간 절** ★ |

두 장의 구조적 차이는 **소제목이 첫 절이냐 중간 절이냐** 하나뿐입니다. 중간 절 소제목은
`VerseLayoutInput.leadingInset` 이 담당하는 바로 그 경로이고 (코드 주석이 `창세기 2:4 "에덴 동산"` 을 예시로 듭니다),
`leadingInset` 은 **실측 `titleHeight` + `titleSpacing`** 이라 값이 0.5 배수가 아닙니다 — 위의 비정수 delta 와 부합합니다.

⚠️ **다만 소제목 1개로 v7 의 +342.40 을 설명할 수 없습니다** (소제목 높이는 약 35pt). 따라서 두 가설이 남습니다.

| 가설 | 예측 |
|---|---|
| **(가) 측정 미수렴** — 장 전환 직후 행 frame 이 아직 도착·갱신 중. `rowFrame`/`canvasFrameInRow` 는 재계산을 유발하지 않으므로(`applyVerseGeometry`) 레이아웃과 실측의 시점이 어긋날 수 있다 | 가라앉으면 **12.00** (24 × 0.5) 으로 수렴 |
| **(나) 중간 절 소제목 경로 결함** | 수렴해도 큰 값이 남고, `h max` 가 소제목 절 근처에 몰린다 |


**★ 장 전환 결함 — 판별 결과 (창세기 1장 → 2장, `-SingleCanvas`)**

| 조건 | Δ max | slope | `build #` |
|---|---:|---|---|
| **새로 진입**한 창세기 2장 | **12.00** = 24 × 0.5 | +0.500/절 · `h[min +0.50 max +0.50]` | 1 |
| **창세기 1장 → 2장 전환** | **1335.78** | +55.657/절 · `h[min +0.50 max +152.50]` | **1 (고정)** |

| 관측 | 확인된 것 |
|---|---|
| 스크롤 왕복해도 `build #1` 고정, Δ 불변 | **자가 복구되지 않는다.** `ChapterContent` 좌표계에서 스크롤은 행 frame 을 바꾸지 않으므로 `onGeometryChange` 가 다시 뛰지 않는다 |
| **`H` 5125.50 · `sig` cl1-d62ed3a659 — 두 경우 동일** | **레이아웃은 두 경우 모두 같게, 옳게 지어졌다.** 스키마·설정·폭 문제가 아니다 |
| 화면: 레이아웃 마크(파랑·초록·주황)가 **v25 까지 있으나 실제 22절 위치**에서 끝남 | 레이아웃이 장을 **실제 렌더보다 짧다고** 믿는다 |
| 그 아래로 **빨강 박스 + 행의 밑줄**이 실제 25절 `sentenceView` 옆까지 이어짐 | **실측 frame 이 실제 본문을 정확히 따라간다** — 실측은 오염이 아니다 |
| `gate` **PASS** | 입력이 열린 상태 |
| 행 ID = `"\(권).\(장).\(절)"` (`SentencesWithDrawingFeature.State.init`) | 장이 ID 에 포함되므로 `applyVerseGeometry` 의 id 가드는 동작한다. **이전 장 값 혼입 경로는 아니다** |
| 단일 Canvas 는 `verseColumn(isCanvasActive: { _ in false })` | 행 캔버스가 없으므로 `activeCanvasIDs` 누적(N-Canvas 전용 `scrollBody` 에서만 초기화)도 원인이 아니다 |

**⇒ 레이아웃은 옳고 실측도 옳다. 어긋난 것은 "레이아웃이 예측한 행 높이" 와 "실제로 렌더된 행 높이" 다.**
전환 후 행이 실제로 더 크게 렌더되고 있으며(예측보다 최대 152.5pt), 레이아웃은 그것을 모른다.
`topDelta` 가 **양수**인 것이 이 방향과 일치한다.

⚠️ **심각도 정정.** `measuredFrames` 가 검증 전용이라는 이유로 "Δ 오탐, 잉크는 무사" 로 볼 수 없다.
실측이 실제 본문을 따라가고 있으므로, **잉크를 배치하는 레이아웃과 사용자가 보는 본문이 최대 1335pt 어긋난 상태**다.
**장 전환만으로 재현되며 자가 복구되지 않는다.**

**경로 판별 결과**

| 조건 | 결과 |
|---|---|
| **N-Canvas** 로 같은 전환 (`-SingleCanvas` 없이) | ✅ **재현되지 않음** → **Phase 3 단일 Canvas 호스팅 전용 결함** |
| 오버레이 라벨 `v{절} · {N}줄` vs 행의 실제 밑줄 | 줄 수는 정상. **밑줄은 제자리인데 빨강 박스(행)만 커져** 밑줄 없는 구간에 박스 경계가 보임 → **줄바꿈이 늘어난 게 아니라 행이 세로로 늘어난 것** |

#### ★ R16 — 원인과 검증 (✅ 종결)

**원인:** `ChapterCanvasController.columnHeight` 가 장 전환에 초기화되지 않아, 긴 장 → 짧은 장 전환에서
이전 장의 큰 높이가 텍스트 호스트 frame 이 되고 그 초과분을 행의 `underLineView`(`maxHeight: .infinity`)가
흡수해 **행이 실제로 늘어납니다.** 늘어난 컬럼을 다시 재도 높이가 같아 `setColumnHeight` 가드에 걸리는
**안정 고정점**이라 자가 복구되지 않습니다. **되먹임 고리의 전문과 수정(`fixedSize`)은 설계 §11 · §20-13 에 있습니다** — 여기서는 실측만 남깁니다.

**관측 일치표에서 남길 것 (재발 판별용)**

| 관측 | 뜻 |
|---|---|
| `H` · `sig` 가 새 진입과 전환에서 **동일** | 세로 **분배**만 일어나고 줄바꿈은 그대로 → 레이아웃은 두 경우 모두 **같게, 옳게** 지어진다. 스키마·설정·폭 문제가 아니다 |
| `build #1` 고정 · 스크롤로 복구 안 됨 | 레이아웃 입력이 안 바뀌어 재계산 트리거가 없고, `setColumnHeight` 가드가 고정점을 잠근다 |
| **N-Canvas 는 무사** | `ScrollView` 가 무한 높이를 제안 → **초과분 자체가 없다.** ⇒ **Phase 3 단일 Canvas 호스팅 전용** |
| 새 진입은 깨끗 | `columnHeight == 0` → 뷰포트 높이(컬럼보다 작음) → 초과분 없음 |
| `h[min +0.50 max +152.50]` 비균일·비정수 | SwiftUI 가 초과분을 행마다 다르게 분배 |
| **밑줄은 제자리, 빨강 박스(행)만 큼** | 밑줄은 `underlineOffsets` 로 텍스트 위치에 그려지고 행만 늘어난다 — **눈으로 보는 판별 기준** |

**⚠️ 심각도.** 실측 frame 이 실제 본문을 따라가므로 "Δ 오탐, 잉크는 무사" 가 아닙니다 —
**잉크를 배치하는 레이아웃과 사용자가 보는 본문이 최대 1335pt 어긋난 상태**였습니다.

**검증 4건 — 실측 결과 ✅ 전부 통과** (iPad mini A17 Pro · iPadOS 27.0 beta · USB · `-SingleCanvas -ChapterLayoutOverlay`)

| # | 전환 | 수정 **전** | 수정 **후** 기준 | **실측** |
|---:|---|---|---|---|
| ① | 시편 117편(2절) → 창세기 2장 | 깨끗 12.00 (이전이 더 짧아 초과분 없음) | 12.00 | ✅ |
| ② | **시편 119편(176절) → 창세기 2장** ★ 가장 강한 판별 | 1335 보다 훨씬 크게 재현 | **12.00** | ✅ |
| ③ | 창세기 2장 → 창세기 1장 (짧은 → 긴) | 깨끗 15.00 | 15.00 | ✅ |
| ④ | 창세기 1장 → 창세기 2장 | ❌ **1335.78** (관측됨) | **12.00** | ✅ |

> ⚠️ **R16 수정의 통과 기준은 "Δ 가 0" 이 아니라 "장 전환 Δ == 새 진입 Δ" 입니다.**
> 남은 12.00 · 15.00 은 R13(절당 0.5pt)이며 별개 결함이었습니다 (그 뒤 종결).
>
> ✅ **`.fixedSize` 가 실제 행의 줄바꿈을 바꾸지 않았습니다** — 오버레이 라벨 `v{절} · {N}줄` 과 실제 밑줄이
> 수정 전후로 같아 보였다는 확인을 받았습니다 (정성 관측).
> **재수정 시에도 이 확인을 반복하십시오** — 시뮬레이터 회귀 테스트는 스텁 컬럼으로 **유연성만** 재현하고,
> 실제 절 행은 `touchIgnoringContextMenu`(중첩 `UIHostingController`)를 거칩니다.
>
> **한 가지 더 (❓ 미확인).** 전환 순간 `contentSize` 가 한 프레임 이전 장 값으로 남는 과도 구간이 있습니다.
> 스크롤 요청은 `layout != nil` 게이트에 막혀 실행되지 않으므로 관측 가능한 영향은 없다고 보지만,
> **전환 순간 스크롤바가 튀는지** 볼 가치는 있습니다.

⚠️ **게이트는 Δ 를 보지 않습니다** (`ChapterLayoutMeasurement.isReady` 는 절 개수만 확인).
따라서 `gate PASS` + `Δ 87.50` 이면 **입력이 열린 채로** 보이는 텍스트와 잉크 좌표계가 하단에서 87.5pt(≈2~3줄) 벌어집니다
→ **G3(절별 귀속)이 장 하단에서 깨집니다.** 설계 §2 가 기록한 두 번의 롤백과 같은 계열이며,
**시뮬레이터 176절 Δ 0.00 에서는 전혀 드러나지 않았습니다.** (그 뒤 Δ 안전망을 넣었습니다 — 설계 §14)


**아직 설명되지 않은 것** — R13 은 예측 자체를 없애 종결했으므로 아래는 원인 규명이 아니라 **재발 감시 항목**입니다.

| # | 미해결 |
|---|---|
| 1 | **같은 코드가 시뮬레이터(iOS 26.2)에서는 Δ 0.00, 실기기(iOS 27.0 beta)에서는 87.50.** 이 머신에 iPad iOS 27 시뮬레이터 런타임이 없어 격리 불가 — 아래 **R14** |
| 2 | 폰트·폭 무관한 **절당 정확히 0.5pt** 의 출처 (0.5pt = @2x 의 1픽셀). ❓ 미규명 — 실측 승격으로 무해해졌을 뿐입니다 |

**D9-0-c 스모크 — R13 수정 후 재검증 (rev.6) ★ 통과**

| 항목 | 기대 | 실측 | 판정 |
|---|---|---|---|
| **`Δ max`** | 0.00 (tol 1.00pt) | **0.00** | ✅ |
| `slope` | +0.000/절 | **+0.000/절** | ✅ |
| `top` v1 · v44 · v88 · v176 | 전부 0.00 | **전부 0.00** | ✅ |
| `guard` | `OPEN` | **`OPEN`** | ✅ 오탐 없음 |
| **`H` (D9-0-d)** | ⓐ == ⓑ == ⓒ | **5138.0 / 5138.0 / 5138.0** | ✅ R16 없음 |

> ⚠️ **이 재검증 도중 R17 을 관측했습니다.** `.fixedSize` 가 빠진 빌드(R13 수정만 들어간 상태)에서도 장 전환
> Δ 가 0.00 으로 나왔습니다 — 레이아웃이 늘어난 렌더를 따라가기 때문입니다. 위 `H` 3건은 `.fixedSize` 를
> 되돌린 빌드에서 다시 잰 값입니다. **Δ 만 보고 R16 을 통과로 적으면 안 됩니다** (D9-0-d).

**후속 (§8-6 형식)**

| # | 발견 | 영향 | 반영할 곳 |
|---|---|---|---|
| **R13** | ✅ **종결** — 빌더의 행 높이 예측이 절당 0.5pt 씩 실측과 어긋나 176절 87.5pt 누적. 방향·폰트·경로 무관, 장 길이에 선형. **행 높이를 실측 입력으로 승격**해 닫았다 (Δ 87.50 → **0.00**) | 허용치 상향은 G3 포기라 선택지가 아니었다 | 설계 **§20-14** |
| **R16** | ✅ **종결** — `columnHeight` 미초기화 → 1335.78pt. `fixedSize` 로 닫고 실기기 4건 통과 (위 블록) | **Phase 3 단일 Canvas 전용.** 잉크 좌표계가 깨지므로 R13 보다 우선이었다 | 설계 **§11 · §20-13** |
| **R14** | ⚠️ **같은 코드가 시뮬레이터(iOS 26.2)에서는 Δ 0.00, 실기기(iOS 27.0 beta)에서는 절당 0.5pt.** 이 머신에 iPad iOS 27 시뮬레이터 런타임이 없어 격리 불가 | 빌더가 행 높이를 **예측**(`lineCount × lineSpace`)하는 한 **OS 판올림마다 재발**한다. 나머지 파이프라인은 전부 실측인데 높이만 모델이다 | 설계 §6-3 — **구조적 논점** |
| **R15** | ✅ **Phase 2 의 Δ 오버레이가 정확히 이걸 잡으라고 만든 것이고, 잡았다.** 오버레이가 없었다면 "장 하단에서 필기가 이상하다" 는 재현 어려운 제보로 왔을 것 | Phase 2 계측 투자에 대한 사후 근거 | 설계 §20-8 |

**D9-0-c 스모크 — 아직 안 채운 칸**

실제 관측은 위 두 블록입니다. 양식 중 다음 둘은 여전히 ❓ **미기록**입니다.

| 항목 | 기대 | 실측 |
|---|---|---|
| `first` (첫 레이아웃 완성) | 시뮬레이터 176절 0.71 s — **이것이 실기기 첫 측정이 됩니다** | ❓ |
| `PKCanvasView` 개수 | 1 | ❓ — 실기기에서는 `simctl … log stream` 을 쓸 수 없어 Console.app / Instruments `os_log` 필요 (D9-0-b) |

**판정 요약** — ⚠️ **아래 항목별 칸은 채워지지 않았습니다.** 절 단위 판정은 이 절 머리말에 있습니다.
D9-1 · D9-2 · D9-6 은 ✅ 통과했으나 **항목별 관측이 기록되지 않았으므로** 재수행 시 채우십시오.

| # | 항목 | 판정 | 관측 |
|---|---|---|---|
| D9-1-1 | 라이브 스트로크 점프 없음 | | |
| D9-1-2 | **경계 획이 통째로 시작 절에** | | |
| D9-1-3 | **겹치는 새 획도 시작 절** (rev.19) | | |
| D9-1-4 | `dirty vN` 이 편집 절을 가리킴 | | |
| D9-1-5 | **재실행 복원** ★ | | |
| D9-1-6 | 잉크 있는 장의 렌더 | | |
| D9-2-1 | 지우개 조각이 각자 절에 | | |
| D9-2-2 | 절 완전 비우기 | | |
| D9-2-3 | **비운 절이 재실행 후에도 빔** | | |
| D9-2-4 | 과거 회차 미승격 | | |
| D9-3-1 | 팔레트 undo/redo | | |
| D9-3-2 | Pencil · 두 손가락 더블탭 | | |
| D9-3-3 | **undo 후 재실행 유지** (§14 17) | | |
| D9-3-4 | **reflow 후 undo 초기화** (§14 14) | | |
| D9-3-5 | 획 도중 설정 변경 → pencil-up 뒤 적용 | | |
| D9-4-1 | **장 전환 직전 획이 이전 장에** | | |
| D9-4-2 | 백그라운드 flush | | |
| D9-4-3 | 설정 push 후 상태 유지 | | |
| D9-4-4 | 장 왕복 시 잉크 혼입 없음 | | |
| D9-5-1 | 롱프레스 → 메뉴 | ✅ | XCUITest 로 자동화. 필기가 있는 절을 1초 누르면 `이전 필사 내용 보기` 가 뜬다 (스크린샷 판정) |
| D9-5-2 | 올바른 절이 잡힘 | ✅ | 손으로 확인 — 시트가 뜨고 **누른 절이 정확히** 잡힌다(1절 기준). 필기 없는 절은 "필사 없다" 안내문 |
| D9-5-3 | 본문 쪽 x 클램프 | ❓ | 사용자 판단으로 건너뜀 |
| D9-5-4 | 회차 복원 (mutation 미생성) | — | **판정 불가 — 대상이 존재하지 않는다.** 두 저장 경로(`DrawingDatabase.updateDrawings` · `SwiftDataDrawingRepository`)가 모두 행을 **제자리에서 갱신**해 회차가 쌓이지 않는다. dev DB 170행 중 같은 절에 2행인 경우가 0건. ⚠️ **결함이 아니다** — 이 기능은 회차 이력이 아니라 "필사가 사라진 것처럼 보일 때 데이터가 살아 있는지 확인하는 안전망"이다 (2026-09-09 작성자 확인) |
| D9-5-5 | 미저장 pending 유실 없음 | — | 판정 불가 — D9-5-4 와 같은 이유 |
| D9-5-6 | ⚠️ 손가락 필사 ON 에서 롱프레스 충돌 | ✅ | 손으로 확인 — **점이 생기지 않고 메뉴만 열린다.** 설계 §15 가 우려한 그리기 제스처 충돌은 없다 |
| D9-6-1 | 설정 토글 on → 경로 전환 | | |
| D9-6-2 | **flag off 에서 N-Canvas 표시** ★ (§14 16) | | |
| D9-6-3 | v3 행의 표시 위치 | | |
| D9-6-4 | N-Canvas 편집 → v2 강등 | | |
| D9-6-5 | flag on 편집 → v3 복귀 | | |
| D9-6-6 | 토글 직전 미저장분 flush | | |
| D9-7-1 | **관성 fling** (§11 기준 2) | ✅ | 시편 122편에서 아래 4회·위 6회(끝 bounce). 복귀 후 잉크가 절 박스·밑줄과 정렬, `Δ max 0.00` · `compose SYNC` · **`dirty —`**(fling 이 편집을 만들지 않음) |
| D9-7-2 | 깊은 offset 에서 필기 | | |
| D9-7-3 | **탭 / 헤더 애니메이션** (§11 기준 5) | ✅ | 스크롤로 헤더가 접히고, 애니메이션 중 반대로 스크롤해도 헤더 버튼이 살아 있다. 깊은 위치에서도 잉크·본문 정렬 유지 |
| D9-7-4 | 회전 · 리사이즈 후 재필기 (§11 기준 3) | | |

**D9-8 성능** — 2026-09-08 실측 (D9 H 수정 A/B). ⚠️ **이것은 D5 와의 N-Canvas 비교가 아니라
`-CanvasReuseStrokesOnApply` 유무의 A/B 입니다.** 단일 Canvas vs N-Canvas 비교는 여전히 ❓ 미수행입니다.

| 항목 | 절차 | D5 baseline (N-Canvas) | 실측 (단일 Canvas · 수정 ON) |
|---|---|---:|---|
| 도구 | `xctrace record --template 'Activity Monitor' --device <UDID> --all-processes --time-limit 60s` · 지표 `sysmon-process` 의 `memory-physical-footprint` | — | ✅ USB `wired` 확인 후 기록 |
| settle 대기 | cold launch 후 8초 (`-ChapterLayoutAutoScroll` 내장) | 8초 | 8초 |
| 스크롤 절차 | **`-ChapterLayoutAutoScroll`** — 176절을 11등분해 1초 간격 11단계. ⚠️ 손가락 fling 이 아니라 프로그램 스크롤이다 | 미계측 | **11단계 · 1초 간격 · 계측됨** |
| 끝 도달 확인 | 마지막 단계가 v176 으로 스크롤 · 로그 `AUTOSCROLL done` | 미기록 | 로그로 확인 |
| 기동 직후 | | 62.2 MB | **28.6 MiB** |
| 시편 119편 진입 peak | | **363.6 MB** / CPU 84.5% | **944.8 MiB** / CPU 68.6% |
| 스크롤 중 안정 | | — | 869~884 MiB / CPU ~47% |
| layout 시간 (`first`) | HUD `first NN ms` (= `begin` 부터 첫 build 까지. **회전으로는 다시 재지 않는다**) | 시뮬레이터 176절 0.71 s | **456 ms** (시편 119편 · cold launch · build #13 시점 HUD) · 시편 122편(9절) **52 ms** |
| 트레이스 파일 | 세션 임시 디렉터리 (`runA-fix` · `runB-reuse` · `runC/C2-fix-rot` · `runD/D2-reuse-rot`) | | ⚠️ 임시 파일 — 보존하지 않음 |

**A/B ① 진입 비용 (autoscroll, 회전 없음) — 차이 없음**

| | 기본 (수정 ON) | 대조 `-CanvasReuseStrokesOnApply` |
|---|---:|---:|
| 기동 직후 | 28.6 MiB | 28.2 MiB |
| **진입 peak** | **944.8 MiB** | **945.4 MiB** |
| 마지막 (정지) | 876.7 MiB | 884.7 MiB |
| CPU 최대 | 68.6% | 60.9% |

**A/B ② 재합성 비용 (회전 4회) — ★ 차이가 큽니다.** 순서 효과를 배제하려고 C→D→D2→C2 로 교차 실행했습니다.

| 실행 | footprint peak | CPU 최대 | 안정(마지막) |
|---|---:|---:|---:|
| **C** 기본 | **1759.6 MiB** | 107.5% | 858.5 MiB |
| **C2** 기본 | **1817.8 MiB** | 98.6% | 863.3 MiB |
| **D** 대조 | 995.3 MiB | 88.9% | 863.6 MiB |
| **D2** 대조 | 1173.6 MiB | 88.1% | 858.8 MiB |

회전별 peak — C: 1742 · 1400 · 1760 · 993 / D: 950 · 995 · 949 · 989 (MiB).
**안정 상태는 두 경로가 같아 누수가 아니라 전이(transient)입니다.**

> **계측과 해석을 구분합니다.** 계측된 것은 위 숫자뿐입니다. 가장 잘 맞는 설명은 **대조 경로가 메모리를 덜 쓰는 이유가 결함 그 자체**라는 것입니다 — 획 정체성을 재사용하면 PencilKit 이 타일 캐시를 재사용해 화면을 고치지 않고, 그래서 렌더 작업을 건너뜁니다. 수정은 그 캐시를 끊으므로 **실제로 다시 그리는 비용**이 드러납니다. 즉 낭비가 아니라 결함이 생략하던 일입니다.
> ⚠️ 그래도 176절 장에서 전이 peak **1.8 GiB** 는 실측입니다. 보유 기기(8 GB)에서는 문제가 없었으나 **저메모리 iPad 에서는 위험**입니다 (§10-3 기기 사각지대). → 후속 **R20**.

**A/B ③ 단일 Canvas vs N-Canvas (R21) — ★ 단일 Canvas 가 더 가볍다.** 같은 절차(60초 기록 · +8초 cold launch · `-ChapterLayoutAutoScroll` 11단계)로 시편 119편에서 순서를 바꿔 2회씩 쟀다. 경로는 `ChapterHUD` 의 `mode=` 로 매 실행 확인했다.

| 실행 | 경로 | footprint 정점 | 정점 시각 | 안정(마지막) | CPU 최대 | `firstMs` |
|---|---|---:|---|---:|---:|---:|
| E | N-Canvas | 1376.4 MiB | +20.5s | 1322.1 MiB | 74.8% | 419 |
| E2 | N-Canvas | **1387.6 MiB** | +21.6s | 1320.9 MiB | 105.2% | — |
| F | 단일 Canvas | 948.1 MiB | +3.1s | 874.4 MiB | 83.4% | 437 |
| F2 | 단일 Canvas | **943.3 MiB** | +4.1s | 881.8 MiB | 66.3% | — |

**정점 ~435 MiB · 안정 ~440 MiB 를 단일 Canvas 가 덜 쓴다.** 곡선의 모양이 이유를 말해 준다.

```
N-Canvas    28 → 937(진입) → 980 → 1105 → 1227 → 1351 → 1322 (평평)
                              └── 스크롤하는 동안 단조 증가 ──┘
단일 Canvas 28 → 948(진입) → 870 → 863 → 867 → 871 → 874 (평평)
                              └──── 스크롤해도 평평 ────┘
```

N-Canvas 는 행이 뷰포트에 들어올 때마다 `PKCanvasView` 를 만들고 `activeCanvasIDs` 가 그것을 놓지 않는다("한 번 활성화되면 유지"). 그래서 **스크롤이 곧 메모리**다. 단일 Canvas 는 캔버스가 하나라 스크롤이 메모리를 늘리지 않는다. 레이아웃 시간(`firstMs` 419 vs 437)은 차이가 없다.

> **⇒ R21 종결.** 단일 Canvas 의 진입 peak 944.8 MiB 는 회귀가 아니다 — 같은 절차의 N-Canvas 보다 **낮다.** D5 의 363.6 MB 와 어긋난 것은 D5 가 다른 세션·다른(계측되지 않은) 스크롤 절차였기 때문이며, §7-2 가 이미 절대값 비교를 금하고 있고 §8-4 한계 3 이 "스크롤 절차 미계측"을 기록해 두었다. **D5 와의 차이는 경로 차이가 아니라 절차 차이였다.**
>
> ⚠️ 이 결과는 **R20 을 지우지 않는다.** 회전 시 전이 peak(1.8 GiB)은 여전히 실측이다. 다만 정지 상태에서는 단일 Canvas 가 대체하는 경로보다 440 MiB 가볍다는 점을 함께 봐야 한다.

**⚠️ 이 측정의 한계**

| # | 한계 |
|---|---|
| 1 | iOS 27.0 beta 수치다 |
| 2 | 구성당 **n=2** (회전 A/B), 진입 A/B 는 **n=1**. 분산을 모른다 |
| 3 | 스크롤은 프로그램 스크롤이라 **손가락 fling 의 관성·합성 부하를 재현하지 않는다** |
| 4 | iPad Air (M2) 미수행 |
| 5 | ✅ **해소** — A/B ③ 에서 같은 절차로 N-Canvas 를 재어 비교했다. D5 와의 차이는 경로가 아니라 절차 차이였다 (R21 종결) |
| 6 | 회전 기록 중 이전 앱 인스턴스가 앞 6초간 함께 살아 있었다 (양쪽 실행 모두 같은 조건) |
| layout 시간 (`measure` 인터벌) | os_signpost 또는 로그 | 실기기 미측정 (시뮬레이터 0.71 s) | |
| 트레이스 파일 | | | |

**D9-CK CloudKit**

| 순서 | 항목 | 결과 |
|---:|---|---|
| ② | dev 스키마에 `CD_layoutMetadataData` 생성 | ✅ **통과** |
| ③ | Development → Production 승격 | ✅ **완료 (2026-09-09)** — 운영 컨테이너 Production 에 `CD_layoutMetadataData` · `CD_rowUUID` 추가 확인. 배포 전 죽은 필드 3개와 `CD_BiblePageDrawing` 을 Development 에서 정리해 함께 넘어가지 않게 했습니다 |

**⚠️ 한계 — 반드시 함께 적으십시오**

| # | 한계 |
|---|---|
| 1 | iOS 27 beta 수치인가 |
| 2 | 측정 횟수 (분산을 아는가) |
| 3 | 스크롤 절차를 계측했는가 |
| 4 | iPad Air (M2) 미수행 여부 |
| 5 | 정성 관측과 계측을 구분해 적었는가 |

**후속 작업 (§8-6 형식으로 추가)**

| # | 발견 | 영향 | 반영할 곳 |
|---|---|---|---|
| **D9 H** | ✅ **정식 수정 적용 + 실기기 A/B 통과** (`ef053111`). 인자 없이 가로↔세로 **3왕복 전부 정상**, `-CanvasReuseStrokesOnApply` 로 **결함 재현**(양성 대조). 계측은 두 실행이 구분되지 않고 화면 판정만 갈린다 | ✅ **후속 검증 완료로 종결** — 조사 §6 및 이 절 상단 최신 판정 참조. 회전 메모리 비용은 별개 R20으로 추적 | [분석](./single-canvas-rotation-display-investigation.md) §3 · [조작 절차](./device-debugging-cli.md) · 설계 **§20-16** |
| **R18** | ⚠️ **N-Canvas 가 새로 만드는 행이 v2 가 아니라 v1(모델 기본값)로 저장된다.** 같은 함수가 기존 v3 행을 편집할 때는 v2 로 정확히 내린다 ([CanvasFeature.swift:81](../Feature/CarveFeature/Sources/Presentation/Drawing/Canvas/CanvasFeature.swift:81)) | **배치에는 영향 없음** — 코덱이 v1·v2 를 똑같이 `writingRect` 원점으로 옮긴다. 문제는 **라벨**이다: "1.2.0 절대좌표"(진짜 legacy)와 오늘 N-Canvas 로 그린 행이 `legacyVerses` 한 통에 들어가 진단에서 구별되지 않는다. **E-4 오독의 직접 원인** | 저장 경로 별건 |
| **E-4** | ✅ **종결 — 결함 아님. D9 H 와 같은 결함이었다.** 2026-09-08 실기기 A/B: 세로 고정 상태에서 글꼴·행간만 바꾸자 **v1(120편 2·4절)·v3(120편 1절) 잉크가 모두 본문을 따라갔다.** `-CanvasReuseStrokesOnApply` 대조에서는 **제자리에 남아 결함이 재현**됐고, 두 실행의 계측(`store/delivered/applied` 일치 · `storeDiff=0` · `expected==canvas` · 합성 bounds 갱신)은 구분되지 않았다 | §8-7 이 세운 가설(폰트 변경과 회전이 같은 `.id` 자극)이 실측으로 확인됐다. rev.22 의 "v1 이라서" 설명은 성립하지 않는다 — **v1 잉크도 정상 경로에서는 따라간다.** `ef053111` 이 처방이다 | [D9 H 분석 §3](./single-canvas-rotation-display-investigation.md) · 설계 §16 |
| **R17** | ⚠️ **`Δ max` 가 R16 계열을 더 이상 검출하지 못한다** — 레이아웃이 실측 높이를 따라가 예측 == 실측이 되기 때문. `.fixedSize` 가 빠진 빌드가 장 전환 Δ 0.00 을 표시하는 것으로 실증 | 실기기 계측의 진단 범위 축소. 대체 절차가 필요 | **런북 §6-9 D9-0-d (신설)** · 설계 §15 · §20-14 |
| **R27** ⚠️ | **`CD_rowUUID` 가 Production 스키마에 없었다 (2026-09-09 배포로 해소).** V4 는 새 행을 만들 때마다 `rowUUID` 를 쓰는데 서버 스키마에 필드가 없어 **그 값이 CloudKit 으로 올라가지 못했다.** 단일 Canvas 와 무관한 선재 문제이며, 이번 승격으로 앞으로는 올라간다 | ⚠️ **이미 만들어진 행들의 `rowUUID` 는 여전히 서버에 없다.** 저장 경로는 rowUUID 로 행을 찾으므로(`requireDrawingRow`) 다른 기기에 도착한 행이 `rowUUID == nil` 로 보이면 **절당 행이 중복 생성될 여지**가 있다. 기기 2대 동기화로 중복 유무를 확인해야 한다 (미수행) | 설계 §8-7 · §10-1-a |
| **R28** ⛔ | **혼재 버전에서 구버전 기기가 v3 행을 잘못 다룬다 — 2026-09-09 git 확인으로 severity 상향.** `displayTransform`(v3 를 `firstUnderlineY` 만큼 내려 표시)과 **v3→v2 강등**이 둘 다 `24e9818e`(Phase 3, **미출시**)에 들어왔다. 출시본은 V4 스키마(`b68b6101`)까지만 있어 **필드는 받지만 해석·강등 규칙이 없다.** | **① 보기만 하면**: v3 행이 한 줄쯤 위로 밀려 보인다 (데이터 무사). **② 구버전에서 편집하면**: `lineData` 를 캔버스 로컬로 덮어쓰면서 **`drawingVersion` 은 3 으로 남긴다** → **좌표와 라벨이 어긋난 행**이 되고 새 기기에서도 그 절이 어긋난다. 새 기기에서 재편집하면 정상 v3 로 복구되므로 영구 손실은 아니다. ⚠️ 조건은 **기기 2대 + 한쪽 미업데이트 + 양쪽 필기**로 좁다. 완화책: 단계적 출시 / 최소 버전 게이트 / 감수 — **출시 전 결정 필요** | 설계 §10-1 · §10-2 · §10-3 |
| **R26** | ✅ **수정 완료 (2026-09-09).** 증상: **긴 장을 떠나도 메모리가 회수되지 않았다** — 같은 시편 120편인데 cold launch 179.7 MB vs 시편 119편을 거쳐 오면 **945 MB**(765 MB 잔류). 짧은 장끼리(120→121)는 누적이 없었다. **귀속 실험(실기기, 알림 트리거):** 본문 컬럼만 비우자 858.3 → **101.3 MB (757 MB 해제)**, 잉크만 비우자 860.2 → 844.2 MB (16 MB). ⇒ 원인은 잉크가 아니라 **호스팅된 SwiftUI 본문 컬럼**이다 (744 × 64,651pt @2x ≈ 770 MB 와 일치). **단일 Canvas 는 `UIHostingController` 를 장마다 재사용하며 `rootView` 만 교체**하는데, 그러면 이전 컬럼의 백업이 풀리지 않는다. N-Canvas 는 행 identity 가 바뀌어 SwiftUI 가 놓으므로 D5 에서 109.7 MB 로 회수됐던 것이다 | **수정:** `setColumn(_:chapter:)` 이 장이 바뀔 때만 `rootView` 를 한 번 비우고 레이아웃을 돌린 뒤 새 컬럼을 넣는다. ⚠️ 매 SwiftUI 갱신마다 비우면 깜빡이므로 **장 전환에서만** 한다. **실기기 재확인: 119편 → 120편 전환 후 945 MB → 124.4 MB** (D5 의 N-Canvas 109.7 MB 와 같은 수준). 회귀 2건 추가 — 같은 장은 놓지 않는다 / 장이 바뀌면 놓는다(`columnReleaseCount`). 기준선 310 → **312** | 설계 §5 · §16 · 이 문서 §8-7 D9-8 |
| **R20** | ⚠️ **회전 전이 peak 과 jetsam 한도의 거리 — 2026-09-09 실측으로 구체화.** 보유 기기(iPad mini A17 Pro · 8 GB)의 **jetsam 한도는 ≈ 3376 MB**(`os_proc_available_memory()` + `phys_footprint` 로 역산). 시편 119편에서 진입 **934.8 MB**(여유 72.3%), **회전 peak 1839.2 MB**(여유 **45.5%**) — Instruments 의 1759~1818 MiB 와 독립적으로 일치한다. | ⚠️ **비교 대상을 바로잡는다.** R21 과 함께 보면 **N-Canvas 는 같은 장에서 정지 상태가 1322 MB** 다. 한도가 RAM 에 비례한다고 보면(3376/8192 ≈ 41%) 3 GB 기기의 한도는 ~1260 MB 로 추정되며, **현재 출시본(N-Canvas)이 긴 장을 읽는 내내 그 선을 넘는다.** 단일 Canvas 는 정지 448 MB 낮고 회전 순간에만 높다. ⇒ **저메모리 위험은 이 전환이 만든 것이 아니라 이미 있던 것이고, 전환은 대체로 완화 쪽이다.** 전환을 미룰 근거로 R20 을 쓰면 더 무거운 경로에 사용자를 남긴다. ⚠️ **외삽은 한 점에서 나왔다** — Apple 의 한도는 계단식이라 어느 기기가 어디서 죽는지는 모른다. 실제 확인은 **MetricKit 의 `MXAppExitMetric.cumulativeMemoryResourceLimitExitCount`** 로 한다. 회전 전이(1839 MB)는 **콘텐츠 넓이에 비례**한다 — 시편 120편(H 1,875)에서는 전이가 **0** 이다. **R26 수정으로 장을 떠날 때의 잔류는 해소됐고**(945 → 124.4 MB), 남은 것은 긴 장에 **머무는 동안**의 비용이다 | 이 문서 §8-7 D9-8 · 설계 §16 |
| **R21** | ✅ **종결 (2026-09-08).** 단일 Canvas 의 시편 119편 진입 peak(944.8 MiB)이 D5 의 N-Canvas baseline(363.6 MB)과 크게 달라 열어 둔 항목. **같은 절차로 N-Canvas 를 재니 오히려 N-Canvas 가 더 무거웠다** — 정점 1376/1388 MiB vs 943/948 MiB, 안정 1321/1322 MiB vs 874/882 MiB (순서 바꿔 2회씩) | **단일 Canvas 가 정점 ~435 MiB · 안정 ~440 MiB 가볍다.** N-Canvas 는 스크롤할수록 `PKCanvasView` 가 쌓여 메모리가 단조 증가하고, 단일 Canvas 는 평평하다. **D5 와의 차이는 절차 차이였다**(§7-2 · §8-4 한계 3). 이 결과는 R20(회전 전이 peak)을 지우지는 않는다 | 이 문서 §8-7 D9-8 A/B ③ |
| **R22** | ⚠️ **세로 화면인데 도구 팔레트가 가로 폭으로 배치돼 redo 버튼이 잘린다** (2026-09-08 사용자 관측). 캔버스·저장 경로와 무관한 UI 별건이라 이번 세션에서 다루지 않았다 | 표시만의 문제로 보이나 **undo/redo 접근성이 실제로 막힌다** | 별건 — D9 범위 밖 |
| **R23** ★ | ✅ **수정 완료 (2026-09-08).** 증상: **flag off 로 장을 열기만 해도 그 장의 v3 절이 전부 v2 로 강등되고 `layoutMetadataData` 가 삭제됐다 — 사용자 편집이 없어도.** 실측은 시편 122편 9개 절(`meta` 217~225 B → **0**). **원인:** `CanvasView` 가 `canvas.drawing` 을 프로그램 대입할 때 PencilKit 이 `canvasViewDrawingDidChange` 를 부르는데 N-Canvas coordinator 에 **억제가 없어** 곧바로 `.saveDrawing` 이 나갔다([CanvasFeature.swift:76](../Feature/CarveFeature/Sources/Presentation/Drawing/Canvas/CanvasFeature.swift:76)). **수정:** 단일 Canvas 와 같은 관용구로 `isApplyingDrawing` 억제를 넣고 두 대입 지점을 `applyProgrammatically` 로 모았다([CanvasView.swift](../Feature/CarveFeature/Sources/Presentation/Drawing/Canvas/CanvasView.swift)) | **검증:** 회귀 2건 추가(기준선 302 → **304**) — ① 프로그램 대입은 강등하지 않는다 ② 사용자 편집 콜백은 그대로 저장된다(억제 과잉 방지). **변이 테스트**로 억제를 빼자 `drawingVersion → 2` · `metadata → nil` · `lineData` 불일치로 정확히 실패. **실기기 재확인:** 같은 조작에서 **170행 전부 불변**, v3 2개 절이 metadata 와 함께 유지됨. ⚠️ 변이 로그에서 `lineData` 가 **같은 379 B 인데 내용이 달랐다** — 기기 실측의 길이 비교로는 구분되지 않던 부분이며, 표시 변환된 좌표가 v2 로 다시 쓰인 것이다(자기 일관적이라 배치는 유지) | 설계 **§10-3 · §14 16** · 이 문서 §6-9 D9-6 |
| **R25** ⚠️ | ⛔ **롱프레스 메뉴가 약 1초 뒤 PencilKit 메뉴로 바뀐다.** `이전 필사 내용 보기` 가 뜬 직후 그 자리에 `전체 선택 | 빈칸 삽입` 이 올라온다 (2026-09-09 실기기, 사용자 관측). **원인:** `ChapterCanvasController` 가 캔버스에 자체 `UIEditMenuInteraction` + 손가락 전용 롱프레스를 붙이는데([ChapterCanvasController.swift:149](../Feature/CarveFeature/Sources/Presentation/Drawing/ChapterCanvas/ChapterCanvasController.swift:149)), `PKCanvasView` 자신의 롱프레스·편집 메뉴가 **더 늦게 발화해 덮는다.** 둘 사이에 `require(toFail:)` 같은 관계가 없다 | ⚠️ **표시 문제가 아니라 데이터 위험이다.** 사용자가 본 대로 누르면 그 사이 바뀐 `전체 선택` 이 눌려 **전 획이 선택되고, 이어진 조작에 끌려가 저장된다.** 자동화가 정확히 그 경로로 시편 119편 1~4절을 수정했다(**A1**) — 사람도 같은 순서를 밟는다. 수정 방향은 두 메뉴의 충돌을 없애는 것인데, PencilKit 메뉴 항목(`전체 선택`·`빈칸 삽입`)을 없앨지 남길지는 **제품 결정**이라 손대지 않았다 | 설계 §15 · §20-11 · 이 문서 §6-9 D9-5 |
| **A1** ⚠️ | **자동화 사고 — 시편 119편 1~4절이 수정됐다 (2026-09-09 09:19).** D9-5-2 를 자동화하려고 `UIEditMenuInteraction` 메뉴를 좌표로 눌렀는데, 열거된 `menuItems` 의 frame 이 앱 메뉴가 아니라 **PencilKit 자체 메뉴(`전체 선택`)** 의 것이었다. 두 메뉴가 화면에서 겹쳐 구분되지 않았다. 탭이 전 획을 선택했고 선택된 획이 끌려가 저장됐다 — 119:1 `v2 → v3` (ink 23171→23427, metadata 생성), 119:2 8711→8691, 119:3 6830→6790, 119:4 metadata 재작성 | **행이 제자리에서 갱신돼 이전 내용은 로컬에 남지 않는다**(회차 행 없음). **운영 DB(`Carve.sqlite`)는 무사**하고 피해는 Debug 의 `Carve.dev.sqlite` 에 한정된다. 시편 120편 증거 표본과 122편 테스트 장은 영향 없다. 사용자 판단으로 복구하지 않았다. ⛔ **규칙:** 자동화는 **테스트 장(시편 122편)에서만**, **잉크 컬럼 안을 탭하지 않는다** | 이 문서 §6-9 D9-5 · UI 테스트 주석 |
| **R24** | ✅ **수정 완료 (2026-09-08).** 증상: **flag off 시점에 화면 밖이던 절의 잉크가 표시되지 않았다** — 스크롤로는 안 살아나고 회전이나 장 왕복 후에야 나타났다. **원인:** `setSentence` → `beginLayoutMeasurement` → `ChapterLayoutMeasurement.begin()` 이 기하 실측(`rowFrames`·`canvasFramesInRow`·`measuredFrames`·`titleHeights`)을 지우는데, 그 유일한 producer 인 SwiftUI `onGeometryChange` 는 **값이 바뀔 때만** 부른다. 같은 장을 같은 폭·설정으로 다시 부르면 콜백이 오지 않아 **아무도 복구할 수 없는 상태**가 된다. ⚠️ **잉크는 증상 하나였을 뿐이고 셋이 함께 무너졌다** — ① `measuredFrames` 가 비어 `updateActiveCanvases()` 가 항상 즉시 반환(캔버스 미활성 = 잉크 없음) ② `canvasFramesInRow` 가 비어 레이아웃이 **실측 높이 대신 예측식으로 후퇴**(R13 이 없앤 상태의 재발, 시편 122편 `H` 3016.00 → **2977.00**) ③ `frameDeltas` 가 비어 **Δ 안전망 실명**(`deltaMax=unmeasured`). **수정:** 장(과 절 목록)이 실제로 바뀔 때만 기하를 버린다. 폭·설정이 바뀌면 컬럼이 다시 지어져 값이 덮이므로 낡은 값이 남지 않는다 | **검증:** 회귀 4건을 별도 suite(`ChapterLayoutReloadTesting`)로 추가(기준선 304 → **308**). **변이 테스트**로 `isSameChapter = false` 를 주자 `measuredFrames → [:]` · `columnOrigin → nil` · **`heightAfter 233.0` vs `heightBefore 334.0`**(예측식 후퇴)로 정확히 실패. **실기기 재확인:** 토글 재로드 뒤 `frames=9` · `columnOrigin=(366.7, 0)` · `H=3016.00` · `deltaMax=0.00` 유지, 그리고 **회전 없이 9절 잉크가 보였다**(사용자 확인). 진단은 새로 추가된 `ChapterHUD` 콘솔 로그로 수행했다 | 설계 **§6 · §10-3** · 이 문서 §6-9 D9-6 |

---

## 9. 정리

### 9-1. D8(백업 추출)만 수행한 경우

**기기에 한 일이 없으므로 "기기 원복" 이라 할 것이 없습니다.** 정리할 것은 Mac 쪽뿐입니다.

**1) 덤프 정리** ⚠️ 가장 중요

```bash
ls -la ~/carve-device-dump/
du -sh ~/carve-device-dump/*
```

- fixture 로 승격할 블롭을 확보했다면(§6-1 사후), `~/carve-device-dump/` 를
  **삭제하거나 저장소 밖 암호화 위치로 옮기십시오** (§2-5).
- ⚠️ `_work` 작업 사본에도 **같은 실사용 데이터**가 들어 있습니다. 반드시 **함께** 처리하십시오.
- `~/carve-device-dump/extract.sh` (§6-1 4단계가 만든 스크립트) 는 데이터가 아니므로 남겨 둬도 무방합니다.

**2) 저장소 정리**

```bash
git status --short   # 덤프·추출물이 저장소 안에 없는지 확인
```

✅ 이 머신에서 실행 확인 (현재 clean).

**3) 전체 디스크 접근 권한 되돌리기 (선택)**

§1-2-a 에서 터미널에 FDA 를 줬다면, 더 필요 없을 때 꺼 두는 것이 안전합니다.
시스템 설정 → 개인정보 보호 및 보안 → 전체 디스크 접근 권한 → 해당 앱 토글 끄기.

**4) 백업 정리 (선택)**

비암호화 백업은 **기기 전체**를 담고 있습니다 (§2-5).
더 필요 없으면 Finder → 기기 → 일반 → **백업 관리…** 에서 해당 백업을 삭제하십시오.
⚠️ **삭제 전에 D8 추출이 끝났는지 확인**하고, 이것이 유일한 안전망이 아닌지도 확인하십시오.

**5) 기기**

**아무것도 하지 않았습니다.** 개발자 모드도 켜지 않았고, 앱도 그대로입니다.

---

### 9-2. 설치를 동반한 세션(D1~D9) 이후

**1) Debug 빌드 제거**

```bash
xcrun devicectl device uninstall app --device "$DEV" kr.co.carve.leetaek
```

✅ `devicectl device uninstall app` 하위 명령 존재 확인. 🔌 결과 미검증.

> ⚠️ **이 명령은 `Carve.dev.sqlite` 뿐 아니라 컨테이너 전체를 지웁니다.**
> **D3 등에서 받은 dev 덤프를 저장소 밖에 이미 확보했는지 확인한 뒤에 실행하십시오.**

**2) App Store 판 재설치**

App Store 에서 "새기다" 를 다시 설치하고, 같은 iCloud 계정으로 prod 컨테이너에서 동기화되는지 확인합니다.
동기화가 안 되면 §2-4 백업으로 복원합니다.

> ⚠️ **복원에는 §2-4 의 "비암호화" 백업으로 충분하지 않을 수 있습니다** — 키체인이 빠져 있습니다.
> 설치를 재개하기 **직전에 암호화 백업을 새로 뜨십시오** (§2-4 의 "안전 백업" 문단).

**3) 개발자 모드**

필요 없으면 iPad 설정 → 개인정보 보호 및 보안 → 개발자 모드 끄기.

**4) 덤프·저장소 정리**

§9-1 의 1)·2) 와 동일. 추가로 빌드 산출물(`~/carve-build/device`)도 정리하십시오.

---

## 10. 이 문서가 확인하지 **못한** 것

### 10-1. D8 (백업 추출 경로)

D8 자체는 완료됐지만(§8-3), **아래 항목들은 이 문서가 절차를 쓰는 시점에 확인하지 못한 것들이고
재추출할 때 다시 확인해야 합니다.** 실행 세션이 이 값들을 기록에 남기지 않았습니다.

| # | 항목 | 상태 / 왜 |
|---|---|---|
| B1 | **이 Mac 에 기존 백업이 있는가** | ✅ **없습니다.** `ls` 는 TCC 로 거부되지만 `stat` 의 링크수가 **2**(= 항목 0개)로, 백업 디렉터리가 비어 있음이 확정됩니다 (§1-2-a 의 링크수 실측). 따라서 §6-1 에서 만드는 백업이 유일한 백업이며, 낡은 백업을 잘못 추출할 위험은 없습니다 |
| B2 | 실제 `Manifest.db` 의 `Files` 테이블 스키마 | 🔌 이 문서의 쿼리는 `fileID` / `domain` / `relativePath` / `flags` / `file` 컬럼 구조를 전제합니다. `.schema Files` 로 먼저 확인하십시오 (§6-1 3단계) |
| B3 | **`flags` 값의 의미** (1 = 파일, 2 = 디렉터리) | 🔌 추출 스크립트가 이 값에 의존합니다. 3-b 출력에서 상위 경로의 `flags` 를 보고 맞추십시오. 틀려도 위험하지 않고 `[MISSING]` 이 늘 뿐입니다 |
| B4 | 앱 도메인명이 정확히 `AppDomain-kr.co.carve.leetaek` 인가 | 🔌 3-a 의 `LIKE '%carve%'` 쿼리로 실제 문자열을 먼저 확인하도록 절차를 짰습니다 |
| B5 | `-shm` / `-wal` 이 백업에 포함되는가 | ❓ 미확인. `-shm` 은 스크래치 파일이라 빠질 수 있습니다. §6-1 5단계의 **작업 사본** 방식이면 없어도 문제없습니다 |
| B6 | `.externalStorage` 임계값과 참조 plist 형식 | ❓ 미확인. 블롭이 전부 인라인일 수도, 전부 바깥일 수도 있습니다. 5-c 길이 분포와 5-f `_EXTERNAL_DATA` 존재 여부로 판단하도록 절차를 짰습니다 |
| B7 | **`_EXTERNAL_DATA` 파일 ↔ DB 행의 매핑 방법** | ❓ **미확인.** fixture 로 승격할 블롭이 external 로 나가 있다면, 어느 파일이 어느 절인지 대응시킬 방법을 이 문서는 제시하지 못합니다. 파일 수가 적으면 크기 대조가 현실적입니다 |
| B8 | 실제 테이블·컬럼명 (`ZBIBLEDRAWING` / `ZLINEDATA` 등) | 🔌 Core Data 명명 규칙과 §18-3 의 `length(ZLINEDATA)` 사용에서 추정. `.tables` / `.schema` 로 먼저 확인하도록 절차를 짰습니다 |
| B9 | Finder 백업 UI 의 정확한 문구 (macOS 27) | 🔌 "이 Mac에 백업" · "로컬 백업 암호화" 등은 macOS 버전에 따라 다를 수 있습니다 |
| B10 | **암호화 백업 복호화 도구** | ❓ **의도적으로 다루지 않았습니다.** 확인하지 못한 도구 이름을 적으면 그 자체가 잘못된 안내가 되므로 추측하지 않았습니다 (§2-4-a) |
| B11 | 백업 암호를 "모든 설정 재설정" 으로 초기화하는 절차 | 🔌 미검증. 되돌릴 수 없는 변경이므로 §2-4-a 에 경고와 함께만 적었습니다 |
| B12 | Finder 의 "Finder에서 보기" 로 연 백업 경로에 FDA 예외가 적용되는가 | ❓ 미확인 (§1-2-a) |

### 10-2. 차단 판정에 대한 미확인 — 지금은 판정에 영향 없음

| # | 항목 | 상태 |
|---|---|---|
| C1 | **CloudKit entitlement 가 무료 Personal Team 에서 정말 거부되는가** | ❓ **미실증.** 무료 팀으로 시도한 적이 없습니다. 유료 멤버십에서는 서명·설치·동작이 실증됐고(§8-1) 차단은 풀렸으므로 **더 이상 판정에 영향을 주지 않습니다** |
| C2 | ~~D6-1/3/6 을 App Store 판으로 관측할 수 있는가~~ | **불필요해졌습니다** — 개발 빌드로 D6 전체를 수행했습니다 |
| **C3** | **이 머신에 Xcode 26.3 이 언제 어떻게 들어왔는가** | ❓ **미확인.** rev.1 의 §1-2 는 *"설치된 Xcode 는 27.0 beta 하나뿐"* 이라고 실측 기록했는데 실제 세션은 전부 26.3 으로 수행됐습니다. §1-2 표는 갱신하지 않고 주석만 달았습니다 (§1-2 · §1-3) |

### 10-3. 남아 있는 미확인 항목

| # | 항목 | 상태 |
|---|---|---|
| 1 | **개발 서명 빌드 설치가 기존 데이터 컨테이너를 보존하는가** | ✅ **보존합니다** — `Carve.sqlite` 11.1 MB 생존. ⚠️ **1회 관측**(iPad mini / iPadOS 27.0 beta)이므로 **§2-4 백업 절차는 유지**하십시오 |
| 2 | `devicectl device copy from --source` 의 `appDataContainer` 상대 경로 해석 | ❓ **미확인.** dev 컨테이너를 내려받을 때만 필요합니다 (§6-5) |
| 3 | `xcodebuild … -destination 'generic/platform=iOS'` 빌드가 실제로 성공하는가 | ⚠️ **빌드·설치는 성공했습니다.** 다만 **CLI 로 했는지 Xcode GUI 로 했는지 미기록**입니다. 이 명령 형태 자체의 검증으로 삼지 마십시오 |
| 4 | Xcode 27.0 으로 이 프로젝트가 빌드되는가 | ❌ **빌드되지 않습니다** — Xcode 27.x 는 의존성 배포 타깃(iOS 12/13, macOS 10.15)을 거부합니다 (AGENTS.md). **Xcode 26.3 이 유일하게 동작합니다** |
| 5 | `xctrace record --attach` 가 실기기 프로세스에 이름으로 붙는가 (pid 필요한가) | ❓ **미확인.** `--attach` 대신 **`--all-processes`** 를 썼습니다 (§7-3-a) |
| 6 | Stage Manager 에서 세로 고정 + scene manifest 부재 앱이 어떻게 처리되는가 | △ D6 이 회전·리사이즈를 관측했으나(설계 §20-7) **Stage Manager / Split View 자체의 동작은 기록되지 않았습니다.** §11 기준 3 의 적용 가능 여부는 아직 미결 |
| 7 | prod CloudKit 컨테이너에 실사용 데이터가 **전부** 올라가 있는가 | ❓ **미확인. 확인 수단이 없습니다.** ★ **이것이 §2-4 백업을 계속 필수로 두는 이유입니다** — 1번이 해소돼도 이 항목이 남는 한 로컬 백업이 유일한 안전망입니다 |
| 8 | Apple 이 제시하는 hitch time ratio 절대 임계값 | ❓ **미확인.** 이 문서는 단정하지 않고 A/B 상대 비교로 판정합니다. ⚠️ **hitch 자체도 측정하지 못했습니다** — Activity Monitor 에 그 지표가 없습니다 (§7-3-a ②) |
| 9 | **D1 어긋남의 pt 단위 크기와 `contentOffset` 과의 정확한 일치** | ❓ **정성 관측입니다.** "스크롤 깊이에 비례" 는 관측된 경향이고 회귀식·수치 대조를 하지 않았습니다. 결론(구조 A 채택 불가)에는 영향이 없지만 **"오차 = contentOffset" 을 수치로 인용하지 마십시오** |
| 10 | **D5 측정의 스크롤 부하 재현성** | ❌ **스크롤 속도·횟수를 계측하지 않았습니다.** 같은 절차를 반복해도 같은 부하가 되리라는 보장이 없습니다 (§8-4 한계 3·4). **D9-8 에서는 절차를 먼저 고정하십시오** |
