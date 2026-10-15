# 회귀 기준선

> 회귀 기준선 **1619** — `Carve-Workspace` 전체 회귀의 **통과 수**(Xcode 27 · iPad mini (A17 Pro) · iPadOS 26.2). **통과 수가 줄면 회귀다.**
> 이 파일이 기준선의 유일한 원본이다. [AGENTS.md](../AGENTS.md) · [설계 문서](./single-canvas-design.md) · [런북](./phase-0a-d-device-test.md)은 여기를 가리킨다.

## 현재 값 (2026-10-15, 브랜치 `claude/settings-late-ondisappear`, Xcode 27.0 27A266a · Swift 6.4 · 언어 모드 6)

| iPadOS 런타임 | 기기 | 통과 | 실패 | 건너뜀 | 예상 실패 | 총 |
|---|---|---:|---:|---:|---:|---:|
| 26.2 | iPad mini (A17 Pro) | 1619 | 0 | 8 | 4 | 1631 |

- 설정 하위 화면이 사라질 때 보내던 정리 액션(onDisappear)을 지운 브랜치의 전체 회귀 값이다(develop `814ff37d` 에서 출발).
- 1614 → 1619(시험 선언 1626 → 1631): 하위 화면을 떠날 때 구독 정리 — SettingsFeature `SettingsDetailLifecycleTesting` +3(iCloud · 확인이 필요한 필기 · 광고 제거에서 다른 항목으로),
  CarveApp `AppCoordinatorSettingsLifecycleTesting` +2(「완료」 로 닫기). 지운 시험 0. 기대값을 바꾼 시험: `RemoveAdsFeatureTesting` 3(onDisappear 대신 효과 취소) · `CloudSettingsHoldTesting` 1(onDisappear 줄 삭제).

### 이전 값 (2026-10-14, 브랜치 `fix/2.1-release-test-findings`, Xcode 27.0 27A266a · Swift 6.4 · 언어 모드 6)

| iPadOS 런타임 | 기기 | 통과 | 실패 | 건너뜀 | 예상 실패 | 총 |
|---|---|---:|---:|---:|---:|---:|
| 26.2 | iPad mini (A17 Pro) | 1614 | 0 | 8 | 4 | 1626 |

- 2.1.0 출시 시험([시험 계획](./release-2.1.0-test-plan.md))에서 찾은 결함 수정 브랜치의 전체 회귀 값이다.
- 1609 → 1614(시험 선언 1621 → 1626): 번역본 전환 맨 위 정렬(EN-M1) — CarveFeature `TranslationSwitchTesting` +3(외부 진입 아래 정렬 유지 · `scrollOffset(bringingTopOf:)` · 맨 위 정렬 왕복),
  이어서 불러오기가 처음부터 다시 판정(D12) — Domain `BackupImporterFlowTesting` +2. 지운 시험 0. 기대값을 바꾼 시험: `BackupImporterFlowTesting` 2 · `BackupImporterCleanupTesting` 1 ·
  `BackupImportOutcomeTesting` 3 · `SettingsFeatureEnglishCopyTesting` 1(끝난 장을 비우는 규칙 · 멈춤 문구).
- 같은 날 develop `7ed86dc3` 의 여러 런타임 회귀: 26.2 1609 · 18.6 1609 · 27.0 1608(런타임 조건 건너뜀 +1) · 17.5 단독 1608(같음). 17.5 를 다른 기기와 동시에 돌리면
  `CanvasLightAppearanceTesting/singleCanvasDrawsStoredInkColorInDark(source:)` 가 렌더 대기(1.2초 고정)에 걸려 흔들린다.

### 이전 값 (2026-10-13, 커밋 `91f5d95e`, Xcode 27.0 27A266a · Swift 6.4 · 언어 모드 6)

| iPadOS 런타임 | 기기 | 통과 | 실패 | 건너뜀 | 예상 실패 | 총 |
|---|---|---:|---:|---:|---:|---:|
| 26.2 | iPad mini (A17 Pro) | 1609 | 0 | 8 | 4 | 1621 |

- 고른 언어가 없을 때의 화면 언어 규칙 시험 +2 까지의 값이다(앱 언어 즉시 전환 단계 1 · 2 · 3 포함).

### 이전 값 (2026-10-12, 커밋 `330ee2c2`, Xcode 27.0 27A266a · Swift 6.4 · 언어 모드 6)

| iPadOS 런타임 | 기기 | 통과 | 실패 | 건너뜀 | 예상 실패 | 총 |
|---|---|---:|---:|---:|---:|---:|
| 26.2 | iPad mini (A17 Pro) | 1572 | 0 | 8 | 4 | 1584 |

- 영어 현지화 DAG(통합 브랜치 `claude/dag-carve-english`, 레이어 5 게이트)의 단일 런타임 값이다. 17.5 · 18.6 · 27.0 은 이번에 돌리지 않았다 — 2.1.0 출시 전 여러 런타임 회귀에서 함께 잰다.
- 1416 → 1572(시험 선언 1428 → 1584): 번역본 모델 · StoredBookKey · 참조 · 권 이름 +31, 번역본별 저장소 · 즐겨찾기 · 초안 · 백업 · 영어 본문 파싱 +38, 번역본 전환 · 즐겨찾기 · 위젯 · 딥링크 · 차트 · 필기 확인 · 출처 화면 +44, 모듈별 영어 문구 시험 +31, 카탈로그 완결성 시험 +10, 기타 +2. 지운 시험 0.

### 이전 값 (2026-10-06, 커밋 `321dcee5`, Xcode 27.0 27A266a · Swift 6.4 · 언어 모드 6)

| iPadOS 런타임 | 기기 | 통과 | 실패 | 건너뜀 | 예상 실패 | 총 |
|---|---|---:|---:|---:|---:|---:|
| 26.2 | iPad mini (A17 Pro) | 1416 | 0 | 8 | 4 | 1428 |
| 27.0 | iPad mini (A17 Pro) | 1415 | 0 | 9 | 4 | 1428 |
| 18.6 | iPad mini (A17 Pro) | 1416 | 0 | 8 | 4 | 1428 |
| 17.5 | iPad mini (6th generation) | 1415 | 0 | 9 | 4 | 1428 |

- 네 런타임은 한 번의 `xcodebuild test`(destination 4개, 동시 2대)로 돌렸고, 수는 xcresult 의 Test Case → Device 단위로 셌다(summary 의 기기별 수는 매개변수 케이스까지 센다).
- 17.5 · 27.0 에서만 하나 더 건너뛰는 것은 `LocalStoreLoadFailureTesting/v1OnlyContainerDropsDrawingSavesSilently()` 다(런타임 조건).
- 건너뜀 8 은 표준 실행에서 늘 건너뛰는 기기 스모크 · 장 이력 메뉴 · 스크롤 UI 시험 6개와 `RemoveAdsStoreKitUITests` 2개(`CarveApp-StoreKit` 스킴에서만 돈다)다.
- 1187 → 1416(시험 선언 1199 → 1428): 2.1 N-Canvas 제거 · 필사 백업 · 불러오기 DAG(통합 브랜치 `claude/dag-carve-21-backup`).
  - 지운 N-Canvas 경로 시험 34 — 파일째 지운 `SingleCanvasRollbackTesting` 8(나머지 코덱 시험 2 는 `DrawingCodecTesting` 으로 옮김) · `CanvasSettingsFeatureTesting` 3 · `SingleCanvasFlagTesting` 2,
    옛 경로를 쓰던 `DrawingSchemaV4MigrationTesting` 5 · `DrawingErasePersistenceTesting` 5 · `LegacyCoordinateTesting` 4 · `SyncedWriteGateTesting` 2 ·
    `DrawingDatabaseTest` · `CanvasLightAppearanceTesting` · `ChapterCanvasDeltaGuardTesting` · `ChapterCanvasLassoTesting` · `ChapterLayoutMeasurementTesting` 각 1.
  - 새 시험 263 — Domain 백업 173(형식 59 · 암호 아카이브 38 · 불러오기 계획 30 · 내보내기 17 · 불러오기 실행 17 · 복원 12), Settings 백업 화면 55,
    CarveFeature 24(flush 10 · 이력 중복 표시 8 · 제거 뒤 N-Canvas 행 3 · HUD slack 진단 3), CarveApp 11(제거 안내 6 · 실행 경로 5).
- Xcode 26.x 는 Swift 언어 모드 6 전환부터 지원하지 않는다(AGENTS.md 「툴체인 제약」). 그 전 값은 아래 이력에 있다.

## 고치는 법

- 전체 회귀를 새로 돌려 통과 수가 늘면 위 요약 줄과 표를 고치고 아래 이력에 한 줄 더한다. **이 파일만 고친다.**
- 수치를 낮추는 것은 테스트를 의도적으로 지운 커밋에서만 한다(`ios-verify` 는 `--full --accept-baseline`).
- `ios-verify` 는 이 파일의 첫 「회귀 기준선 **N**」 을 정규식으로 읽는다. 요약 줄의 형식을 바꾸지 않는다.

## 이력

rev.37(2026-09-29) 까지의 이력은 [설계 문서](./single-canvas-design.md) §19-4-2 에 있다.

| 날짜 | 기준선 | 커밋 | 내용 |
|---|---:|---|---|
| 2026-09-29 | 1112 | `c3c320ad` | 설정 「의견 보내기」 · 「앱 버전」 시험 9 추가(설계 rev.37 과 같은 값) |
| 2026-09-30 | 1112 | `b9a8b438` | 기준선 원본을 이 파일로 옮김. 값은 그대로 |
| 2026-10-01 | 1175 | `8853b0ac` | release/2.0.1 본문 파싱 시험 +22, `CarveAppTest` +41(AI 적합성 2차 묶음 DAG 통합 브랜치 게이트) |
| 2026-10-02 | 1186 | `795746bd` | develop 역병합 — Xcode 27 빌드의 `.appStorage` 해석 핫픽스, 저장 형식 · JSON 되돌림 시험 +11 |
| 2026-10-02 | 1187 | `8edd0c89` | Swift 언어 모드 6 전환(Xcode 27 기준으로 옮김, 26.3 비교 기준 내림) — N-Canvas 이력 복원 시험 +1. 17.5 · 18.6 · 26.2 · 27.0 실패 0 |
| 2026-10-06 | 1416 | `321dcee5` | 2.1 N-Canvas 제거 · 필사 백업 · 불러오기 DAG 통합 브랜치 — N-Canvas 경로 시험 34 삭제(코덱 시험 2 는 옮김), 백업 · 불러오기 · 제거 안내 시험 263 추가. 17.5 · 18.6 · 26.2 · 27.0 실패 0 |
| 2026-10-12 | 1572 | `330ee2c2` | 영어 현지화(KJV · BSB · 영어 UI) DAG 통합 브랜치 — 번역본 귀속 · 본문 · 전환 · 현지화 시험 156 추가, 지운 시험 0. 26.2 실패 0(다른 런타임은 출시 전 회귀에서) |
| 2026-10-13 | 1607 | `76c04bb2` | 앱 언어 즉시 전환 — 단계 1 · 2(앱 안 고르기 · 헤더 · 설정 「화면」 · 캔버스 호스트) +15, 단계 3 DAG 통합 브랜치(모듈 전체 이행 · Domain 표시 API 비옵셔널 · lint) +20, 지운 시험 0. 26.2 실패 0(다른 런타임은 출시 전 회귀에서) |
| 2026-10-13 | 1609 | `91f5d95e` | 수동 확인 M1-b 회귀 수정 — 고른 언어가 없을 때 화면 언어를 번들 규칙(선호 언어에서 앱이 옮긴 첫 언어)으로, 규칙 시험 +2. 26.2 실패 0 |
| 2026-10-14 | 1614 | `fix/2.1-release-test-findings` | 2.1.0 출시 시험 결함 수정 — 번역본 전환 맨 위 정렬 +3, 계정 바뀜 뒤 이어서 불러오기 처음부터 다시 판정 +2, 지운 시험 0. 26.2 실패 0 |
| 2026-10-15 | 1619 | `claude/settings-late-ondisappear` | 설정 하위 화면의 늦은 onDisappear(`ifCaseLet` · `ifLet` 경고) 제거 — 하위 화면을 떠날 때 구독 정리 시험 +5, 지운 시험 0. 26.2 실패 0 |
