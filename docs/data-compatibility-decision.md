# 데이터 호환성 결정 — COMPAT-0

작성·갱신: 2026-09-09 · 브랜치: `codex/canvas-compatibility-plan` · 상태: **U1 확정 · D2~D6 결정 대기**

## 0. 이 문서의 역할

R27 · R28 · 번역본 귀속은 **"필사 한 행을 무엇으로 식별하고 어떻게 해석하는가"** 라는 한 문제의 세 얼굴이다. 셋을 한자리에서 결정하려고 이 문서를 만들었다. 결정의 결과는 [2.0.0 로드맵](./release-2.0.0-roadmap.md) §3-2 의 COMPAT-1 과 BIBLE-EN 범위를 정한다.

이 문서는 **코드·git 조사와 기존 문서 대조**의 결과다. 실기기 검증이나 CloudKit 콘솔 조회는 수행하지 않았다. §2 의 미확인 항목을 확인하기 전에는 §4 의 판단을 확정으로 쓰지 않는다.

---

## 1. 코드로 확인한 사실

### 1-1. 스키마 — V4 가 추가한 것은 두 필드뿐

| 스키마 | `BibleDrawing` 필드 |
|---|---|
| V3 | `id` · `titleName` · `titleChapter` · `verse` · `creationDate` · `updateDate` · `translation` · `drawingVersion` · `isPresent` · `lineData` |
| V4 | 위 전부 **+ `layoutMetadataData` + `rowUUID`** |

`translation` 과 `drawingVersion` 은 **V3 부터 이미 있다**. V4 의 신규 필드는 `layoutMetadataData` · `rowUUID` 둘뿐이다 ([DrawingSchemaV4.swift](../Domain/Domain/Sources/SwiftData/Model/DrawingSchemaV4.swift) · [DrawingSchemaV3.swift](../Domain/Domain/Sources/SwiftData/Model/DrawingSchemaV3.swift)).

### 1-2. `translation` 은 스키마에 있지만 **죽어 있다**

| 확인 항목 | 결과 |
|---|---|
| 필드 존재 | ✅ V2 · V3 · V4 전부. 기본값 `Translation.NKRV` |
| `Translation` enum | ⚠️ **`case NKRV` 하나뿐** ([Translation.swift:12](../Domain/Domain/Sources/Model/Translation.swift:12)) |
| 제품 코드에서 읽는 곳 | ⚠️ **0건.** [DrawingDataMigrationPlan.swift:63](../Domain/Domain/Sources/SwiftData/DrawingDataMigrationPlan.swift:63) 이 `.NKRV` 로 쓰는 한 줄이 전부 |
| 조회 술어가 보는가 | ⛔ **`BibleDrawing` 술어 8곳 전부 `titleName` + `titleChapter`(+절)로만 필터링. 번역본을 보는 곳이 없다** |

술어 위치: [DrawingDatabase.swift](../Domain/Domain/Sources/SwiftData/DrawingDatabase.swift) 30 · 43 · 62 · 79 · 268 · 288행, [SwiftDataDrawingRepository.swift](../Domain/Domain/Sources/SwiftData/SwiftDataDrawingRepository.swift) 52 · 150행.

### 1-3. 행 `id` 에 번역본이 없고, 성경 이름이 **파일명**이다

```
id = "\(bibleTitle.title.rawValue).\(bibleTitle.chapter).\(verse).\(Int(timestamp))"
```
([DrawingSchemaV4.swift:132](../Domain/Domain/Sources/SwiftData/Model/DrawingSchemaV4.swift:132))

그리고 `BibleTitle` 의 rawValue 는 **본문 파일명 그 자체**다 — `case genesis = "1-01Genesis.txt"` ([BibleChapter.swift:34](../Domain/Domain/Sources/Model/BibleChapter.swift:34)). 즉 행 식별자에 한국어 본문 파일명이 박혀 있다.

본문 로더도 같은 rawValue 로 번들 경로를 찾고, **EUC-KR 로 하드코딩**되어 있으며 `\r` 로 줄을 나눈다 ([BibleTextClient.swift:37](../Domain/Domain/Sources/BibleText/BibleTextClient.swift:37)).

### 1-4. 최소 버전 게이트를 붙일 수단이 현재 없다

의존성에 **Firebase Remote Config 가 없다**. Analytics · Messaging · Crashlytics 만 있다 ([Package.swift:26-28](../Plugins/ProjectDescriptionHelpers/Package.swift:26)). 원격 설정·강제 업데이트·킬 스위치에 해당하는 코드도 검색되지 않는다.

`firebase-ios-sdk` 자체는 이미 의존성이라 Remote Config **product 추가**는 비교적 싸다. 다만 아래 1-5 때문에 R28 해결책은 되지 못한다.

### 1-5. 게이트는 R28 을 풀지 못한다 — 구조적으로

최소 버전 게이트를 2.0.0 에 넣어도 **이미 배포된 1.3.0 에는 그 코드가 없다.** 게이트는 "이 앱이 스스로를 막는" 장치이므로 구버전을 막으려면 구버전에 이미 들어 있어야 한다. 로드맵 §5 가 적어 둔 전제와 같고, 이번 조사로 코드 근거가 붙었다.

⇒ **게이트는 2.0.0 이후의 미래 전환을 위한 투자이지 R28 의 대응책이 아니다.**

---

## 2. 확인하지 못한 사실 — 결정 전에 필요하다

| # | 항목 | 상태 | 확인 방법 |
|---|---|---|---|
| **U1** | App Store 에 올라가 있는 실제 버전과 빌드 | ✅ **확인 완료 (2026-09-09)** — **1.3.0 (177) · 2026-03-23 빌드**. §3 참조 | 사용자가 App Store Connect 에서 확인 |
| U2 | Production CloudKit 에 `CD_translation` 이 있는가 | ❓ 미확인 | CloudKit Dashboard — 운영 컨테이너 `CD_BibleDrawing` 필드 목록 |
| U3 | 구버전이 모르는 `Translation` rawValue 를 만나면 어떻게 되는가 | ❓ 미확인. `Translation` 은 `String, Codable` 이라 `"WEB"` 을 출시본이 디코딩하지 못한다. nil 로 떨어지는지 행 자체가 안 읽히는지에 따라 등급이 달라진다 | 기기 2대 왕복 또는 V3 모델 스키마 테스트 |
| **U4** | CloudKit 이 구버전 클라이언트의 쓰기에서 모르는 필드를 보존하는가 | ❓ **미확인 — U1 확정으로 중요도 상승.** 보존하지 않으면 출시본이 편집한 행에서 `rowUUID`·`layoutMetadataData` 가 사라진다. `b68b6101` 을 "additive schema" 라 부른 전제가 이것이다 | 기기 2대 왕복 (런북 §8-7 절차) |

---

## 3. ✅ 출시본 확정 — 1.3.0 (177) · 2026-03-23 · 스키마 **V3**

사용자가 App Store Connect 에서 확인한 값은 **1.3.0 (177), 2026-03-23 빌드**다. 저장소에서 이 빌드를 특정했다.

| 항목 | 값 |
|---|---|
| 출시 커밋 | **`49f2dc27`** `[feat] version 1.3.0: chart 포팅` (2026-03-23, `main`) |
| `marketingVersion` | `"1.3.0"` — 사용자가 확인한 값과 일치 |
| 그 시점 스키마 파일 | `DrawingSchemaV1` · `V2` · `V3` — **V4 없음** |
| 마이그레이션 플랜 | `schemas: [V1, V2, V3]` |

빌드 번호 177 은 매니페스트의 `currentProjectVersion("1")` 과 다르나, 아카이브·업로드 단계에서 붙는 값이라 버전 문자열과 날짜 일치로 커밋 특정에는 충분하다.

### 3-1. 기존 문서의 전제를 정정한다

설계 §16 과 런북 §8-7 의 R28 은 **"출시본은 V4 스키마(`b68b6101`)까지만 있습니다"** 로 적혀 있었다. **틀렸다.**

| 커밋 | 날짜 | 내용 |
|---|---|---|
| **`49f2dc27`** | **2026-03-23** | **← 실제 출시본 (1.3.0). 스키마 V3** |
| `9377a7de` | 2026-04-02 | `ver 1.3.1 Base추가` — 다음 버전의 준비 커밋. **출시되지 않았다** |
| `b68b6101` | 2026-09-05 | V4 additive schema — 출시본보다 **5개월 뒤** |
| `24e9818e` | 2026-09-06 | Phase 3 — `displayTransform` · v3→v2 강등 |

출시본은 V4 를 **갖고 있지 않다.** `1.3.1` 은 출시된 적 없는 준비 버전이었고, 이 문서를 쓰기 전까지 그 구분이 없었다.

### 3-2. 정정이 각 위험에 미치는 영향

| 위험 | 결론 |
|---|---|
| **R28** | **등급 유지.** 전제는 틀렸지만 메커니즘은 그대로 성립한다 — V3 에도 `drawingVersion` 이 있고, 출시본이 그 값을 **편집 시 건드리지 않기** 때문이다 (§3-3) |
| **R27** | ⚠️ **범위 확대.** 출시본에 `rowUUID` **필드 자체가 없다.** 기존 판정은 "기존 행에 rowUUID 가 없다" 였으나, 실제로는 **구버전 사용자가 앞으로 만드는 모든 행에도 없다.** 과거 데이터 문제가 아니라 **구버전이 살아 있는 동안 계속 생기는 문제**다 |
| **U4** | ⚠️ **중요도 상승.** 출시본이 V4 필드를 아예 모르므로, 그 클라이언트의 쓰기가 서버의 `rowUUID`·`layoutMetadataData` 를 보존하는지가 데이터 보전의 핵심 조건이 된다 |
| 번역본 | `translation` 은 V3 에도 있으므로 출시본도 필드는 갖고 있다. 다만 enum 은 `NKRV` 뿐이라 U3 위험은 그대로 |

### 3-3. 출시본은 `drawingVersion` 을 편집 시 쓰지 않는다 — 코드로 확인

`49f2dc27` 전체에서 `drawingVersion` 에 값을 **쓰는** 곳은 두 군데뿐이다.

- `DrawingDataMigrationPlan.swift:63` — V1→V2 마이그레이션에서 `new.drawingVersion = 1`
- `DrawingSchemaV2/V3` 의 모델 기본값 `= 1`

**저장 경로에는 없다.** 즉 출시본이 기존 행을 편집하면 `lineData` 만 자기 좌표 규약으로 덮어쓰고 `drawingVersion` 은 **원래 값 그대로 남긴다.** `drawingVersion == 3` 인 행이면 **라벨 3 · 좌표는 캔버스 로컬**인 어긋난 행이 된다.

이것은 설계 §16 이 서술한 R28 메커니즘과 정확히 일치한다. **전제는 정정하되 판정은 유지한다.** 아울러 D3 의 "`drawingVersion` 은 전부 1 로만 쓰이는 죽은 필드" 관측(추출 데이터 225행 전부 1, 2025-02-13 ~ 2026-03-23)과도 모순되지 않는다 — 출시본이 그 값을 올린 적이 없기 때문이다.

---

## 4. 항목별 판단과 선택지

### 4-1. R27 — 기존 행의 `rowUUID` 부재

행 키는 `rowUUID` 가 있으면 그것, 없으면 business `id` 다 ([SwiftDataDrawingRepository.swift:178](../Domain/Domain/Sources/SwiftData/SwiftDataDrawingRepository.swift:178)). 기존 행은 후자를 쓰고 `id` 는 **초 단위 타임스탬프**를 포함하므로, 두 기기가 같은 절에 같은 초에 행을 만들면 충돌한다.

⚠️ **U1 확정으로 범위가 커졌다 (§3-2).** 출시본(V3)에는 `rowUUID` 필드가 아예 없어 **앞으로도 절대 발급하지 못한다.** 따라서 "rowUUID 없는 행" 은 과거에 고정된 집합이 아니라 **구버전 사용자가 쓰는 동안 계속 늘어난다.** 2.0.0 배포 후에도 업데이트하지 않은 기기가 있는 한 이어진다.

| 선택지 | 내용 | 비용 |
|---|---|---|
| **A. 보유 기기 2대로 확인** | 런북 §8-7 절차로 절당 행 중복이 실제로 생기는지 관측 | 세션 1회. 기기 2대 보유 중 |
| B. 확인 없이 이월 | 미확인을 명시하고 출시 후 제보로 판단 | 0. 단 §7 체크리스트가 "결정 필요 상태를 방치하지 않음"을 요구 |
| C. 방어 코드 추가 | 중복 행 병합·정리 로직 | COMPAT-1 에서 산정. U1 결과에 따라 필요 범위가 달라짐 |

**권고: A.** 기기가 있고 절차가 이미 문서화돼 있다. 확인 결과가 C 의 필요 여부를 정한다.

### 4-2. R28 — 혼재 버전의 v3 오해석

게이트는 §1-5 대로 쓸 수 없다. 남는 선택지는 셋이다.

| 선택지 | 내용 | 평가 |
|---|---|---|
| **A. 감수 + 안내** | 조건(기기 2대 + 한쪽 미업데이트 + 양쪽 필기)이 좁고 재편집으로 복구됨을 근거로 수용. NEWS·도움말로 "모든 기기를 업데이트하세요" 안내 | 조건이 실제로 좁다면 합리적. U1 확정 후에도 메커니즘은 유지된다 (§3-3) |
| B. 단계적 출시 | 확산 속도만 조절. 혼재 버전을 없애지 못하고 수동 업데이트도 가능 | R28 해결로 표시할 수 없음. A 의 보조 수단 |
| **C. 2.0.0 쪽 데이터 방어** | 구버전이 망칠 수 있는 형태로 쓰지 않거나, 어긋난 행을 2.0.0 이 감지·복구 | **로드맵의 기존 선택지 목록에 없던 안.** 위험을 실제로 없애는 유일한 방향이나 실현 가능성 미확인 |

**권고: A + B 조합을 기본선으로, C 의 실현 가능성을 COMPAT-1 에서 한 번 검토.** C 가 싸게 되면 A 의 "감수" 범위가 줄어든다.

### 4-3. 번역본 귀속 — BIBLE-EN 의 선행 결정

**현재 구조 그대로 영어 성경을 넣으면 같은 절의 한국어 필사와 영어 필사가 한 행 집합으로 취급된다.** 술어가 번역본을 보지 않기 때문이다 (§1-2).

| 선택지 | 내용 | 스키마 변경 | 구버전 영향 |
|---|---|---|---|
| **A. 술어에 번역본 조건 추가** | `id` 형식은 그대로 두고 조회 8곳에 `translation` 조건을 더함 | ❌ 불필요 — 필드가 이미 있음 | ⚠️ 구버전은 조건이 없어 **여전히 섞어 본다**. U3 결과에 따라 더 나빠질 수 있음 |
| B. `id` 형식에 번역본 포함 | `"<판본>.<책>.<장>.<절>.<ts>"` | ❌ 불필요하나 **기존 행의 `id` 와 형식이 갈림** | 구버전이 새 형식 `id` 를 legacy 키로 씀 |
| C. 2.0.0 에서는 한국어만 유지 | BIBLE-EN 을 2.1 로 이월 | 없음 | 없음 |

세 선택지 모두 **`Translation` enum 에 case 를 추가**해야 하고, 그 자체가 U3 의 위험(구버전이 `"WEB"` 을 디코딩하지 못함)을 만든다. 이건 스키마 변경이 아니어도 발생하는 호환성 문제다.

**권고: U2 · U3 확인 후 결정.** U2 가 "없음"이면 CloudKit 승격이 선행돼야 하고, U3 이 "행을 못 읽음"이면 A · B 모두 구버전에 데이터 손실처럼 보이므로 **C 가 유력해진다.**

BIBLE-EN 자체의 다른 준비물(판본·권리·본문 형식)은 이 결정과 독립적으로 병행할 수 있다. 본문 로더가 EUC-KR·`\r` 고정이라 판본별 인코딩·줄 구분 분기가 필요하고, 파일명이 곧 `BibleTitle` rawValue 이자 행 `id` 의 일부라 **번역본 차원은 파일명이 아니라 경로로 넣어야 한다** (§1-3).

---

## 5. 결정 요약 — 사용자 확인 필요

| # | 결정할 것 | 이 문서의 권고 | 선행 |
|---|---|---|---|
| ~~D1~~ | ~~출시본 확인~~ | ✅ **완료** — 1.3.0 (177) · `49f2dc27` · 스키마 V3 (§3) | — |
| D2 | R27 대응 | 보유 기기 2대로 중복 확인. **범위가 커졌으므로 (§4-1) 확인을 이월하지 않는 쪽을 권고** | — |
| D3 | R28 대응 | 감수 + 단계적 출시 기본선, 데이터 방어(C) 실현성 검토 | — |
| **D6** | **U4 확인** — 출시본 쓰기가 서버의 V4 필드를 보존하는가 | **새로 승격.** 보존하지 않으면 R27·R28 과 별개의 데이터 유실 경로가 된다. 기기 2대 왕복으로 D2 와 같은 세션에서 확인 가능 | — |
| D4 | 번역본 귀속 | `CD_translation`(U2) · 구버전 디코딩(U3) 확인 후 A / C 중 선택 | U2 · U3 |
| D5 | BIBLE-EN 의 2.0.0 포함 여부 | D4 결과에 따름 | D4 |

**D2 · D6 는 같은 절차(기기 2대 왕복, 런북 §8-7)로 한 세션에서 확인할 수 있다.** U2 는 CloudKit Dashboard 조회 한 번이다.

## 6. COMPAT-1 후보 작업

D1~D5 의 결과에 따라 아래 중 필요한 것만 남는다. **결정만으로 끝나면 COMPAT-1 은 기록으로 완료한다.**

- R27 중복 행 병합·정리
- R28 데이터 방어 또는 어긋난 행 복구 경로
- 번역본 조건을 조회 술어 8곳에 반영
- `Translation` enum 확장과 구버전 디코딩 방어
- 최소 버전 게이트 (2.0.0 이후를 위한 투자로만, R28 대응이 아님)

---

## 7. 이 문서가 하지 않은 것

- 실기기 검증 · CloudKit 콘솔 조회 · 구버전 왕복 테스트 (U2 · U3 · U4 미수행)
- R28 판정의 변경 — **전제(출시본 = V4)를 정정했으나 등급은 유지했다.** 메커니즘이 코드로 재확인됐기 때문이다 (§3-3)
- 영어 본문 확보 · 판본 권리 확인 (BIBLE-EN 범위)

**U1 확인에 사용한 경로 (2026-09-09):** App Store 판이 설치된 iPad mini 에서 `devicectl` 로 조회를 시도했다. 앱 실행(`process launch`)과 프로세스 확인은 되지만 **`info apps` 는 빈 목록을 반환하고**(설치돼 있는데도) `info files --domain-type appDataContainer` 는 `CoreDevice.ActionError error 3` 으로 거부된다. 런북 §6-1-0 의 "App Store 판 컨테이너는 못 읽는다" 가 Xcode 26.3 · iPadOS 27 에서도 유효하다. `info apps` 가 비는 것은 런북에 없던 관측이다. 결국 **버전·빌드는 사용자의 App Store Connect 확인으로 얻었고**, 저장소 대조로 커밋을 특정했다. 기기의 실제 sqlite 스키마 확인(Finder 백업 추출, 런북 §6-1)은 수행하지 않았다 — 현재 로컬에 백업이 없다.
