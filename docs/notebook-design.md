# 회차별 필사책 설계 (2.2)

작성: 2026-10-15 · 목표: **2.2** · 브랜치: `feat/2.2-notebooks`(← develop, 2.1.0 이 main 에 머지되기 전에는 develop 에 합치지 않는다 — 결정 18) ·
상태: **설계 확정(2026-10-15) — 구현 DAG `carve-reading-rounds` 진행 / 수동 확인 M · 공존 C · 출시 관문 G 남음**(§9)

> 이 문서는 「회차별 필사책」 을 2.2 에 넣는 **계약**이다. 「결정 n」 은 2026-10-15 사용자 결정의 번호이고(§3) 이 문서에서 다시 정하지 않는다.
> 탐색 결과와 인터뷰 원본은 보관함 plan 노트 「Carve 2.2 회차별 필사책」 · 결정 노트 「회차별 필사책 저장 방식 결정」 이다. 이 문서를 쓴 것이 구현을 시작할 때의 사용자 확인이다(DAG 실행 승인).
> 코드 줄 번호는 main(2.0.0) `118715de` · 1.3.0 `49f2dc27` 기준이고, develop(2.1)은 줄 번호가 자주 움직여 파일 · 함수 이름으로 적는다(확인 `33fd09ed`).
> 코드와 함께 바뀌는 문서다 — 구현하며 바뀐 것은 그 절에 날짜와 함께 적는다.
>
> 관련: [데이터 호환성 결정](./data-compatibility-decision.md) §5 D7 · [영어 현지화 설계](./english-localization-design.md) §3(같은 방식으로 번역본을 가른 선례) ·
> [필사 백업 · 불러오기 설계](./backup-import-design.md) · [단일 Canvas 설계](./single-canvas-design.md) §8-7 · [호환성 시험 계획](./icloud-sync-compatibility-test-plan.md) ·
> [2.1.0 출시 시험](./release-2.1.0-test-plan.md) · 룰북 `.codex/skills/carve-rulebook/references/localization.md` 「필사책 귀속」

## 1. 목적과 범위

같은 말씀을 여러 번 쓰고 **회차마다 독립된 필사 기록(필사책)** 으로 보관한다. 예: 「시편 첫 번째 필사」 · 「시편 두 번째 필사」 · 「2027년 사순절」.
다시 써도 이전 필사책의 필기는 그대로이고, 필사책을 골라 이어 쓰거나 돌아본다.

| 구분 | 2.2 |
|---|---|
| 필사책 | **개인 필사책**. 지금까지의 모든 필사 = 기본 필사책 「첫 번째 필사」(결정 3). 필사책의 말씀 범위는 성경 전체(결정 4) |
| 화면 | 별도 「책장」 화면(앱 스택)에서 고르고 관리한다 — 만들기 · 고르기 · 이름 바꾸기 · 완료 표시 · 지우기(결정 5 · 7). 필사 화면 헤더 부제에 지금 필사책 이름(결정 9) |
| 저장 | 잉크는 `BibleDrawing` 그대로, 다른 필사책은 `titleName` 접두로 가른다(결정 1 · §4). 필사책 정보는 스키마 **V7** 새 엔티티 `DrawingNotebook`(결정 2 · §5) |
| 혼재 버전 | 같은 iCloud 를 2.0.0 · 2.1 기기가 함께 쓴다. 옛 기기에는 기본 필사책만 보이고, 다른 필사책은 죽지도 섞이지도 덮이지도 않는다(§3-2 · §4-2) |
| 연결 고리만 | 그룹 공동 필사책 · 챌린지 — V7 에 예약 필드(`kind` · `scopeData` · `linkData`)만 두고 1차에는 쓰지 않는다(§5-2) |
| 범위 밖 | 그룹 · 챌린지 기능, 필사책별 말씀 범위 · 진행률, 겹쳐 보기 · 절 메뉴 「다른 필사책에서 보기」, 필사책 보관(숨기기), 필사책별 차트, 묵상 메모 · PDF 연결 |

제품 근거는 제품 로드맵 `docs/product-roadmap.md` §1 · §3(2026-10-13, 우선순위 높음 · 개인 기능 — 이 문서를 쓸 때 이 브랜치에는 커밋되지 않았다)과 보관함 결정 「새기다 후속 기능 우선순위와 챌린지 방향 결정」 이다.

### 1-1. 구현 위치

구현 DAG(보관함 plan 의 plan JSON, slug `carve-reading-rounds`)의 태스크가 맡은 곳이다 — 2026-10-16 t4 가 구현된 파일 · 이름으로 고쳤다(t3a 의 책장 · 헤더 줄은
같은 레이어라 병합 전 계획 그대로다). 이름이 바뀌면 여기를 고친다.

| 모듈 | 위치 | 맡는 것 |
|---|---|---|
| Domain | `Sources/Notebook/` — `NotebookID.swift`(`NotebookID` · `NotebookChapter` · 키 `SharedReaderKey.currentNotebookID`) · `NotebookSnapshot.swift`(`NotebookStatus` · `NotebookSnapshot`) · `NotebookRepository.swift`(`NotebookRepository` · `NotebookRepositoryError` · `\.notebookRepository`) | 필사책 식별 · 계약(t0) |
| Domain | `Sources/Model/StoredBookKey.swift` — `titleName(for: NotebookChapter)` · `titleName(title:translation:notebook:)` · `decodeRow(_:)`(`StoredRowKey` · `page(chapter:)`) · `translationColumn(for:)` | 행 `titleName` 짓기 · 풀기 — 필사책 접두(t0, §4). 필사책 없는 옛 공개 함수는 t4 에서 지웠다 |
| Domain (SwiftData) | `Model/DrawingSchemaV7.swift`(`DrawingNotebook`) · `DrawingDataMigrationPlan.swift`(V6 → V7) · `Model/DrawingSchemaV4.swift`(`BibleDrawing.init(page:…)`) · `SwiftDataNotebookRepository.swift`(목록 · 쓴 절 수 · 만들기 · 이름 · 완료 · 지우기) | V7 · 마이그레이션 · 새 행(t0), 필사책 저장소(t1b) |
| Domain (SwiftData) | `SwiftDataDrawingRepository.swift`(`load(_:)` · `apply(_:page:generation:)` · `archiveAndReset(_:page:)`, actor `loadChapterDrawings(page:)` · `applyDrawingMutations(_:page:…)` · `archiveAndResetVerseDrawing(_:page:…)`) · `SwiftDatabaseActor+DrawingDatabase.swift`(`verseDrawingSnapshots(page:verse:)` · `markPresentDrawing(page:…)` · 활동 조회) · `DrawingDatabase.swift`(`fetchVerseSnapshots(page:verse:)` · `updatePresentDrawing(page:verse:presentRowID:)` · `fetchDrawingRecord(notebook:title:translation:)`) · `Drawing/VerseDrawingSnapshot.swift`(`notebook`) · `Drawing/DrawingActivityRepository.swift`(`DrawingActivity.page`) | 필사 행 조회 · 저장 · 지우기를 page 로(t1a) |
| Domain | `Drawing/VerseDraftKey.swift`(`VerseDraftKey.notebook` · 파일 이름 `nb_<id>~` — t4 가 `LocalPreservationWriter.swift` 에서 떼어 냈다) · `Drawing/LocalPreservationWriter.swift`(`drafts(in:page:)` · `discardDrafts(notebook:)`) · `Drawing/VerseDraftRecoveryInventory.swift`(`DraftBucketSummary.pages` · `unreadPages` · `currentVerse(page:verse:)` · `NotebookDraftDiscarding`) · `Drawing/VerseDraftImport.swift`(`VerseDrawingImportCommand.page` · `importVerse(_:generation:)`) · `Drawing/LocalDrawingChangeClient.swift`(`LocalDrawingChange.page`) · `SwiftData/SwiftDataDrawingRepository+Import.swift` | 초안 · 확인이 필요한 필기 · 가져오기(t1c) |
| Domain | `Sources/Backup/` — `Format/BackupNotebookRecord.swift` · `BackupManifest.notebooks` · `BackupVerseKey.notebook` · `BackupItemID.draftSourceKey(…notebook:)` · `Import/BackupImportJobStore.swift`(recordVersion 2), `SwiftData/SwiftDatabaseActor+Backup.swift`(`backupListing()` · `backupRows(page:)`) · `SwiftData/SwiftDataDrawingRepository+BackupRestore.swift`(`restoreNotebooks`) | 백업 형식 2(t1d · 다른 필사책 초안 t4) — [백업 설계](./backup-import-design.md) §10 |
| Domain | `Drawing/DrawingDataEraser.swift` | 전체 삭제에 `DrawingNotebook`(t1b) |
| CarveFeature | `Presentation/Notebook/` — `NotebookShelfFeature` · `NotebookShelfView` | 책장(t1e 뼈대 · t3a) |
| CarveFeature | `Presentation/Drawing/ChapterCanvas/ChapterCanvas*`(`State.page` · `PendingDrawingMutation.page` · 초안 `loadDrafts(page:)` · 컨트롤러 `hostedPage`) · `Presentation/Carve/CarveDetail/CarveDetailFeature.swift`(`currentNotebook` · `reopenInCurrentNotebookIfNeeded`) · `Presentation/Carve/CarveNavigation/CarveNavigationFeature.swift`(`switchNotebook` · `openPage` · `View.moveToNotebooks`) · `Presentation/Drawing/VerseDrawingHistory/VerseDrawingHistoryFeature.swift`(`State(page:verse:)`) · `Presentation/Drawing/SentenceWithDrawing/SentencesWithDrawingFeature.swift`(절 행 id) | 저장 경로를 page 로 · 필사책 바꾸기(t1e 경계 · t2a) |
| CarveFeature | `Presentation/Header/MainHeader/*` · `Presentation/Carve/CarveNavigation/CarveNavigationView.swift` | 헤더 부제 · 「책장 열기」 · 서재 아래 「책장」 아이콘(t3a) |
| ChartFeature | `Chart/DrawingChartFeature.swift`(`chapterNotebooksByDay`) · `Chart/DrawingWeeklySummaryFeature.swift`(`recentChapters` · `topChapterPage` · 위임 `openChapter(NotebookChapter)` · `openVerse(NotebookChapter, verse:)`) · `Model/RecentVerseItem.swift`(`notebook` · `page`) | 합산 · 최근 기록은 그 필사책으로(t1e 위임 · t2b, §7) |
| SettingsFeature | `Details/DraftRecovery/*`(`DraftRecoveryCopy.place(_:notebookNames:locale:)` · `chapterName(_:notebookNames:locale:)`) · `Details/iCloud/iCloudSettingReducer.swift`(`resetCurrentNotebook()`) · `Details/Backup/BackupImportFeature.swift` · `BackupImportView.swift` | 확인이 필요한 필기 · 전체 삭제 · 백업 미리보기(t2c, §7) |
| App | `Coordinator/AppCoordinatorFeature.swift`(`Path.notebooks` · 책장 위임 셋 · 차트 위임을 `openPage` 로) · `AppCoordinatorView.swift` | 책장 경로 · `-UITestRoute notebooks`(t1e) |
| ClientInterfaces | `Analytics/AnalyticsEvents.swift` | `AnalyticsFeatureName.notebook`(t3a) |

저장 경로는 「추가 → 이전 → 제거」 로 옮겼다 — t0 이 새 계약을 과도기 기본 구현과 함께 더하고, L1 이 Domain 구현, L2 가 Feature 호출부를 옮기고,
**t4 가 옛 API 와 과도기 기본 구현을 지웠다**(2026-10-16, §4-1).

## 2. 용어

| 말 | 뜻 · 코드 |
|---|---|
| **필사책** | 같은 말씀을 다시 쓸 때 독립된 필기 묶음. 코드 `Notebook`(`NotebookID` · `DrawingNotebook` · `NotebookSnapshot`). 영어 화면 「Notebook」 |
| **기본 필사책** | `NotebookID.default`(rawValue 「default」). 2.2 이전의 모든 필사와 접두 없는 행이 여기에 속한다. 기본 이름 「첫 번째 필사」(en 「First Notebook」) — 바꿀 수 있고 지울 수 없다 |
| **지금 필사책** | 이 기기에서 쓰고 있는 필사책. `@Shared(.currentNotebookID)`(UserDefaults 키 `currentNotebookID`, 기기마다) |
| **책장** | 필사책을 고르고 관리하는 화면. `NotebookShelfFeature`(앱 스택 `Path.notebooks`). 영어 화면 「Notebooks」 |
| **page** | 저장 경로가 나르는 「필사책 + 장」 값 `NotebookChapter`. 장 `BibleChapter` 는 번역본을 담는다 — page 하나 = 필사책 × 번역본 × 권 × 장 |
| **필사책 메타데이터** | 이름 · 상태 · 시각 — V7 `DrawingNotebook` 레코드. 행에서 풀 수 없어 따로 둔다 |
| **이름 없는 필사책** | 메타데이터 없이 행만 있는 필사책(지운 뒤 늦게 온 행 · 메타데이터보다 먼저 온 행). en 「Untitled Notebook」 |

> **「회차」 와 구별한다.** 기존 문서의 「회차」 는 **절 하나의 보관 행**이다 — 한 절의 여러 `BibleDrawing` 행 중 `isPresent` 로 대표를 고르고,
> 나머지가 「이전 필사 내용 보기」(`VerseDrawingHistoryFeature`)의 목록이 된다([단일 Canvas 설계](./single-canvas-design.md) §8-7 · `docs/design/ui-design-direction.md` 「이전 필사 기록」).
> 새 기능은 코드 · 문서 · 화면에서 **「필사책」** 이라 부르고 「회차」 라고 쓰지 않는다. 기능 이름 「회차별 필사책」 만 예외다.
> 이전 필사(보관 행)는 필사책 **안에서** 쌓인다(§7).

## 3. 결정

### 3-1. 결정 표

결정 1 ~ 15 는 구현 태스크 공통 규칙의 번호이고(코드 주석 · 커밋이 이 번호로 부른다), 16 ~ 19 는 그 밖의 인터뷰 결정에 이 문서가 붙인 번호다.
「인터뷰」 열은 보관함 plan 인터뷰 기록의 번호다. 모두 사용자 확인 2026-10-15.

| 결정 | 내용 | 인터뷰 | 근거 · 기각 |
|---|---|---|---|
| 1 | **잉크 행은 `BibleDrawing` 그대로 두고 필사책은 `titleName` 접두로 가른다.** 기본 필사책은 지금 형식 그대로(접두 없음) | 0 | 옛 앱 술어가 `titleName ==` 뿐이다 · EN-M4 선례(§4-2). 기각: V7 잉크 엔티티 · `BibleDrawing` 새 필드(§4-3) |
| 2 | **필사책 정보(이름 · 상태 · 만든 날)는 V7 새 엔티티 `DrawingNotebook`**(같은 SwiftData 저장소 · CloudKit) | 1 | 백업 · 전체 삭제와 한 곳. 기각: iCloud KVS(행과 따로 동기화 · 전체 삭제 · 계정 전환을 따로, 핵심 데이터에 비권장), `BibleDrawing` 특수 행(옛 앱 `hasAny` · 차트 · 삭제에 섞임) |
| 3 | **지금까지의 모든 필사 = 기본 필사책, 기본 이름 「첫 번째 필사」(바꿀 수 있음). 기존 행은 고치지 않는다.** 번역본이 섞여 있어도 한 권 | 3 | 다시 쓰는 행이 없어 업로드 · 옛 기기 손실이 없고 2.0 · 2.1 기기와 계속 같이 쓴다. 기각: 번역본별 기본 필사책 · 업데이트 때 묻기 |
| 4 | **필사책 범위는 성경 전체** — 범위 필드는 예약만 | 4 | 범위를 넣으면 탐색 거르기 · 진행률 · 범위 밖 장 처리까지 는다. 챌린지가 붙을 때 쓴다 |
| 5 | **필사책은 별도 「책장」 화면에서 고르고 관리한다** | 5 | 사용자가 추천안(헤더 제목 팝오버) 대신 고름 — 진입점은 결정 9 |
| 6 | **새 필사책을 만들면 그 필사책으로 바뀌고 지금 보던 장이 빈 종이로 열린다.** 이전 필사책은 그 필사책으로 돌아가 본다 | 6 | 캔버스 합성(D9 영역)을 건드리지 않는다. 기각: 겹쳐 보기(합성 변경 → D9 재관문), 절 메뉴 「다른 필사책에서 보기」(후속 후보) |
| 7 | **관리: 만들기 · 고르기 · 이름 바꾸기(기본 포함) · 완료 표시/취소(표시일 뿐 계속 쓸 수 있음) · 지우기(기본은 못 지움, 확인 뒤 그 필사책의 필기 전부).** 보관(숨기기)은 없다 | 7 | 지운 뒤 오프라인 기기가 늦게 올린 필기는 「이름 없는 필사책」 으로 다시 보인다(사라지거나 섞이지 않음 — 혼재 ⑥) |
| 8 | **번역본은 고정하지 않는다** — 필사책 × 번역본마다 따로 쓰인다. 번역본은 지금처럼 헤더에서 바꾼다 | 8 | 기본 필사책이 이미 번역본이 섞여 있어 규칙 하나로 간단하다 |
| 9 | **책장 진입 = 서재 열 아래 아이콘 줄의 「책장」(즐겨찾기 · 차트처럼 앱 스택) + 헤더 부제에 지금 필사책 이름 + 번역본 팝오버 끝 「책장 열기」.** 책장 카드 = 이름 · 시작 월 · 쓴 절 수 · 지금 표시 · 완료 배지, 그리고 「새 필사책」 | 9 | 본보기: 서재 아래 버튼(`CarveNavigationView`) → `AppCoordinatorFeature.Path`(`chart` · `favorites` 꼴) |
| 10 | **차트 · 주간 요약은 모든 필사책 합산.** 최근 절 · 장을 누르면 그 필사책으로 연다. 필사책별 수는 책장 카드의 쓴 절 수로 대신한다 | 10 | 지금 차트도 번역본을 합산한다. 2.1 기기 차트도 날짜별 합산 수를 본다(장별에서는 빠짐) |
| 11 | **즐겨찾기 · 위젯은 지금처럼 번역본 · 절마다 하나(필사책 공통).** 추가할 때 지금 필사책의 필기 사본. `FavoriteVerse` 는 접두를 쓰지 않는다 | 11 | 즐겨찾기 · 위젯은 이미 사본이라 필사 행을 읽지 않는다 — 스키마 · 키 변경 없음, 2.0 · 2.1 기기에도 그대로 보인다 |
| 12 | **저장 경로는 `NotebookChapter`(필사책 + 장)를 기본값 없는 인자로 나른다** — 저장소 · 캔버스 · 초안 · 이전 필사 · 탐색 칠하기 · 가져오기 · 백업. 본문 · 탐색 선택 · 위젯은 `BibleChapter` 그대로 | 12 | 빠뜨린 곳이 컴파일 오류로 드러난다. 기각: `BibleChapter.notebook`(기본값이 조용히 기본 필사책에 씀, `==` 변경이 탐색 비교를 흔듦) |
| 13 | **지금 필사책은 기기마다(UserDefaults)** — 목록에 없으면(다른 기기에서 지움) 기본 필사책으로 | 15 | 마지막 장도 기기마다다(`@Shared("title")`) |
| 14 | **책장 아래와 만들기 시트에 옛 기기 안내 한 줄** 「2.2 이전 버전을 쓰는 기기에서는 처음부터 있던 필사책만 보여요」 | 16 | 옛 기기에는 기본 필사책만 보인다(§8) |
| 15 | **위젯 · 필사 알림 · 즐겨찾기에서 여는 장은 지금 필사책으로 연다** | 세부 | 즐겨찾기 · 위젯은 필사책 공통(결정 11)이라 어느 필사책인지 담지 않는다 |
| 16 | **V7 은 필사책으로 확정하고, 말씀 카드 설계가 V7 첫 TestFlight 전에 끝나면 같은 V7 에 더한다**(그 뒤면 V8) | 2 | V7 은 TestFlight 에 나가기 전까지만 고칠 수 있다(`DrawingSchemaV6` 문서 주석의 규칙). 말씀 카드는 러프 논의 단계 |
| 17 | **출시 관문 = 공존 실측 + 부분 D9** — 2.0.0 · 2.1 기기와 같은 계정 dev 저장소 공존 실측, 실기기 iPad 캔버스 부분 관문, V7 Production 배포 뒤 TestFlight 동기화. D9 전체 재수행은 하지 않는다 | 13 | 저장 큐 · 세대 · 합성 규칙은 바꾸지 않고 키만 넓히므로 D9 중단 기준(「재실행 후 필기가 사라지면」)에 해당하는 경로만 다시 본다(§9) |
| 18 | **구현 브랜치는 develop 에서 딴 `feat/2.2-notebooks`, 2.1.0 이 main 에 머지될 때까지 develop 에 합치지 않는다.** 그 사이 develop 의 2.1 수정은 merge 로 받는다(rebase 없음). CloudKit 운영 배포는 2.1 출시 뒤 | 14 | 필사 알림(`feat/2.2-reading-reminder`)과 같은 방식 |
| 19 | **V7 유지 — 소유 증명 판독기(C14)의 V7 관측 · 확장(G-2)을 develop 병합 · TestFlight 전 필수 관문으로 둔다** | 17 | 결정 2 뒤에 찾은 비용(§5-5). 말씀 카드도 V7 후보라 어차피 치를 비용이고, 한 V7 로 묶으면 관측도 한 번이다 |

**설계에서 정한 세부**(인터뷰 「—」 행 — 구현 전 검토 때 바꿀 수 있다): 새 필사책 이름 제안 「두 번째 필사」 …(en 「Notebook 2」) · 이름 40자 상한 ·
「이름 없는 필사책」 표시 · 분석 이벤트 하나(만들 때 `feature_complete` · `notebook`, 책장 진입은 코디네이터 `screen_view`) · 백업은 늘 형식 2 ·
필사책 지우기는 메타데이터를 물리 삭제(늦게 온 필기는 「이름 없는 필사책」) · 같은 ID 레코드는 `updatedAt` 최신 · 위젯 · 알림 · 즐겨찾기에서 여는 장은 지금 필사책(→ 결정 15) ·
기본 필사책 메타데이터는 이름 바꾸기 · 완료 표시 때만 생김 · 영어 용어(Notebook · Notebooks · First Notebook).

### 3-2. 혼재 버전 규칙 (동결)

같은 iCloud 를 2.0.0 · 2.1 기기가 함께 쓴다. **옛 앱은 `BibleDrawing` 을 `titleName ==` 로만 찾고 모르는 `titleName` 은 건너뛴다 — 이 동작에 기댄다**(§4-2).

| # | 규칙 | 어기면 |
|---|---|---|
| ① | 기본 필사책 행 형식(`titleName` · `translation` 열 · business id)을 바꾸지 않는다 | 옛 기기에서 지금까지의 필사가 사라지거나 두 벌이 된다. 이전 일치 검사(`LegacyMigrationContentMatcher`) · 백업 형식 1 이 어긋난다 |
| ② | 필사책을 `translation` 등 기존 열로 판정하지 않는다 | 옛 앱이 레코드에 없는 열을 스키마 기본값으로 채워 서버로 되올린다(EN-M4 관찰 ①) — 열 값이 필사책을 잃는다 |
| ③ | `FavoriteVerse` 에 필사책 접두를 쓰지 않고, V6 의 `VerseDrawingVersion` · `DrawingEraseEpoch` 에는 아무것도 쓰지 않는다 | 즐겨찾기가 옛 기기에서 사라진다. V6 두 타입은 운영 Development 에 없어(§5-6) 쓰기 시작하면 운영 배포 대상이 는다 |
| ④ | `DrawingNotebook` 상태는 열거형 열이 아니라 **String 열** — 모르는 값은 active 로 읽는다(`NotebookStatus(stored:)`) | 다음 버전이 상태를 더할 때 2.2 가 디코딩하다 죽을 수 있다 — 옛 앱 열거형 디코딩 위험 U3([데이터 호환성 결정](./data-compatibility-decision.md) §2)와 같은 이유 |
| ⑤ | 백업은 `formatVersion` **2** 로 쓴다. 2.2 는 1 · 2 를 모두 읽고, 1 은 전부 기본 필사책이다 | 2.1 은 형식이 다르면 파일 전체를 거부하고 업데이트를 안내한다 — 형식 1 에 키만 더하면 2.1 이 모르는 키를 버리고 다른 필사책 항목을 기본 행에 합친다(불러오기는 권 · 번역본으로 `titleName` 을 다시 짓는다) |
| ⑥ | 지운 필사책의 행이 늦게 오거나 메타데이터보다 행이 먼저 오면 **「이름 없는 필사책」** 으로 보인다 — 숨기거나 기본 필사책에 합치지 않는다 | 숨기면 오프라인 기기의 필기가 보이지 않게 사라지고, 합치면 필사책이 섞인다 |

## 4. 행 귀속

### 4-1. 규칙 — `titleName` 접두

| 행 | `titleName` | `translation` 열 | 읽을 때 |
|---|---|---|---|
| 기본 필사책 — 지금 · 앞으로 | **지금 형식 그대로** — 개역개정 `1-19Psalms.txt`, KJV · BSB `KJV-1-19Psalms.txt`(번역본 귀속, [영어 현지화 설계](./english-localization-design.md) §3-1) | 번역본 귀속 그대로(개역개정 `.NKRV` · 영어 nil — 받은 기기에서는 `.NKRV` 일 수 있다) | `NotebookID.default` |
| 다른 필사책 | `"nb_" + NotebookID.rawValue + "~" + 기본 형식` — 예 `nb_0f3a…(32자리)~KJV-1-19Psalms.txt` · `nb_0f3a…~1-19Psalms.txt` | 번역본 귀속 그대로 — 필사책은 열에 적지 않는다(혼재 ②) | 접두의 필사책 + 나머지를 번역본 귀속대로 |
| 접두 형식이 틀림(대문자 · 길이 · `~` 없음 · `nb_default~`) | — | — | 풀지 못함(nil) — 지금처럼 건너뛴다 |

- **`NotebookID`**: rawValue 는 「default」 또는 **소문자 16진 32자리**만이다(`init?(rawValue:)` 가 그 밖은 nil). 새 ID 는 `NotebookID.make(uuid:)` — `uuidString` 에서 `-` 를 빼고
  소문자로(uuid 는 `@Dependency(\.uuid)`). 기본 필사책에는 접두를 짓지 않고, 풀 때도 32자리 16진만 받는다 — `nb_default~` 는 짓지도 풀지도 않는다.
- **토큰을 이렇게 고른 이유**: `nb_` 는 번역본 rawValue(`NKRV` · `KJV` · `BSB`)로 시작하지 않아 2.1 `StoredBookKey.decode` 의 `KJV-` · `BSB-` 접두 판정에 걸리지 않고,
  `BibleTitle(rawValue:)` 에도 맞지 않는다(2.0.0 · 1.3.0 은 그것으로 푼다). `.` 을 담지 않아 business id(`<titleName>.<장>.<절>.<초>`)의 구분자와 겹치지 않는다.
  `~` 는 기기 안 초안 파일 이름(`<번역~권~장~절>.json`)의 구분자와 같아 초안 파일 이름 앞에도 같은 토큰을 붙인다(§7).
- **business id**: 새 행의 business id 도 이 `titleName` 으로 짓는다(`BibleDrawing(page:verse:…)`). business id 는 `rowUUID` 가 없을 때의 행 키일 뿐 어디서도 쪼개 읽지 않는다.
- **짓고 푸는 곳은 Domain `StoredBookKey` 하나다.** `titleName` 문자열을 직접 잇거나 자르지 않는다. 조회 술어의 `titleName == …` 도 page 로 짓는다.

  | API | 뜻 |
  |---|---|
  | `titleName(for page: NotebookChapter) -> String` | page 가 놓일 행의 `titleName`. 기본 필사책은 지금 형식, 그 밖은 `"nb_<id>~"` + 지금 형식 |
  | `titleName(title:translation:notebook:) -> String` | 권 · 번역본 · 필사책으로 같은 것을 짓는다 |
  | `decodeRow(_ titleName: String) -> StoredRowKey?` | `StoredRowKey`(`title` · `translation` · `notebook`, `page(chapter:)`)로 푼다. 접두 형식이 틀리거나 권 · 번역본을 모르면 nil |
  | `translationColumn(for:)` | 그대로 — 필사책과 상관없다 |
  | 옛 `titleName(for: BibleChapter)` · `titleName(title:translation:)` · `decode(_:)` | **t4 에서 공개 함수로는 지웠다**(2026-10-16). 뜻은 「기본 필사책」 이었고 옛 `decode` 는 접두 행에 nil 이었다(2.1 과 같다). 규칙은 `StoredBookKey` 안의 private 함수(`bookTitleName` · `decodeBook`)로 남아 접두 행의 뒷부분을 짓고 푼다. 기본 필사책도 `notebook: .default` 로 밝혀 짓는다(즐겨찾기 `FavoriteVerse` 권 이름 포함 — 접두를 쓰지 않는다, 혼재 ③) |

- **저장 경로 계약**(결정 12): `DrawingRepository` 의 `load(_ page:)` · `apply(_:page:generation:)` · `archiveAndReset(_:page:)`, 옛 클라이언트 `DrawingDatabase` 의
  `fetchVerseSnapshots(page:verse:)` · `updatePresentDrawing(page:verse:presentRowID:)` · `fetchDrawingRecord(notebook:title:translation:)`, 초안 · 가져오기의
  `LocalDrawingChange.page` · `drafts(in:page:)` · `discardDrafts(notebook:)`. page · notebook 인자에는 **기본값을 두지 않는다.** DTO 에 더하는 필드
  (`VerseDrawingSnapshot.notebook` · `DrawingActivity.page`)는 init 끝에 기본값을 둬도 된다. 과도기 기본 구현(page 가 기본 필사책이면 옛 chapter 메서드로 위임,
  아니면 `DrawingRepositoryError.unsupportedNotebook`)과 옛 chapter 요구 · 메서드는 **t4 에서 지웠다**(2026-10-16) — 이제 저장 경로에는 page · notebook 판만 있고,
  필사책을 빠뜨린 호출은 컴파일되지 않는다. 지운 것: `DrawingRepository` 의 `load(chapter:)` · `apply(_:chapter:generation:)` · `archiveAndReset(_:chapter:)`,
  `DrawingVerseImporting.importVerse(_:chapter:generation:)`, `DrawingDatabase` 의 `fetchVerseSnapshots(chapter:verse:)` · `updatePresentDrawing(chapter:…)` ·
  `fetchDrawingRecord(title:translation:)`, 초안의 `VerseDraftKey(sessionID:chapter:…)` · `drafts(in:chapter:translation:)` · `DraftBucketSummary.chapters` ·
  `unreadChapters` · `currentVerse(chapter:verse:)`, `LocalDrawingChange(chapter:date:)` · `DrawingActivity(updateDate:chapter:verse:)` · `BibleDrawing.init(bibleTitle:…)`.

### 4-2. 옛 앱 동작 근거

2.0.0 = main `118715de`, 2.1 = develop, 1.3.0 = `49f2dc27`(App Store 출시본). 다른 필사책의 행은 옛 앱에게 **모르는 권 이름의 행**이다 — 2.1 에서 2.0.0 이 영어 행을 대한 것과 같다.

| 경로 | 옛 앱의 동작 | 다른 필사책 행 |
|---|---|---|
| 장 조회 · 저장 · 지우기 · 이전 필사 · 이전 필사 고르기 · 장 칠하기 · 즐겨찾기 조회 · 가져오기 · 백업 복원 | 술어가 모두 `titleName ==`(+ 장 · 절 · rowID). `contains` · `hasPrefix` · LIKE 는 없다(2026-10-15 전수 확인) — main `DrawingDatabase.swift:34,54,166,296,322` · `SwiftDataDrawingRepository.swift:71,289` · `+Import.swift:90` · `SwiftDataFavoriteVerseRepository.swift:130`, 1.3.0 `DrawingDatabase.swift:31,63,175`, develop `SwiftDatabaseActor+DrawingDatabase` · `DrawingDatabase` · `SwiftDataDrawingRepository` · `+Import` · `+BackupRestore` · `SwiftDatabaseActor+Backup` · `SwiftDataFavoriteVerseRepository` | 맞지 않아 **보이지 않고 고치지도 않는다** — (b) 섞이지 않음 · (c) 덮지 않음 |
| 읽은 `titleName` 풀기 | 2.0.0 · 1.3.0 `guard let BibleTitle(rawValue:)`, 2.1 `StoredBookKey.decode`(`KJV-` · `BSB-` 로 **시작할 때만** 접두를 뗀다). 강제 언랩 · `fatalError` 없음 | nil — 건너뛴다 · (a) 죽지 않음 |
| 차트 날짜별 수 · 주간 합계 | `updateDate` 술어로 권을 가리지 않고 행을 센다 | **센다** — 다른 필사책의 필기도 그날 수에 든다(§8) |
| 2.0.0 주간 요약 「최근 절」 | `BibleTitle(rawValue:) ?? .genesis`(main `Feature/ChartFeature/Sources/Chart/DrawingChartFeature.swift:212`). 2.1 은 건너뛴다 | ⚠️ **창세기로 보일 수 있다** — 쓰기는 없다(§8) |
| 2.1 백업 내보내기 | `decode` 가 nil 인 행을 담지 않고 수만 로그로 남긴다(develop `SwiftDatabaseActor+Backup.swift`) | 빠진다(§8) |
| `hasAny` · `databaseIsEmpty` · 전체 삭제 | 술어 없이 전부 | 든다 · 지운다. 전체 삭제는 `BibleDrawing` 만 지워 `DrawingNotebook` 이 남는다(§8) |

- **실측 선례**: 2.0.0 기기가 `KJV-` 행을 받아도 숨기고 죽지 않았다(2.1.0 출시 시험 EN-M4 — [출시 시험](./release-2.1.0-test-plan.md)).
  1.3.0 은 모르는 레코드 타입(`CD_FavoriteVerse` · `CD_VerseDrawingVersion`)을 건너뛰고, 새 스키마로 올린 뒤 그 레코드를 받았다(FAV-P0 · ENT-P1 —
  [호환성 시험 계획](./icloud-sync-compatibility-test-plan.md)). **2.0.0 · 2.1 이 모르는 레코드 타입(`CD_DrawingNotebook`)을 받는 시험은 아직 없다** — 공존 C1 · C2 가 첫 실측이다(§9).
- **기존 열로 가르면 안 된다**(혼재 ②): 옛 앱은 레코드에 없는 열 값을 스키마 기본값으로 채워 서버로 되올린다(EN-M4 관찰 ① — `StoredBookKey` 문서 주석).
  1.3.0 은 모르는 필드를 서버에 남기지만(F11) 아는 필드는 자기 값으로 덮는다(F16).
- 기기 안 초안 · 위젯 payload · 지금 필사책 키는 동기화하지 않아 다른 기기의 옛 앱에 가지 않는다.

### 4-3. 기각한 대안

판정 기준 — 같은 iCloud 를 2.0.0 · 2.1 기기가 함께 쓸 때 (a) 죽지 않는다 (b) 필사책을 섞어 한 장에 보이지 않는다 (c) 고쳐 쓰다가 다른 필사책의 필기를 덮지 않는다.

| | ① **`titleName` 접두(채택)** | ② 새 엔티티(V7)에 필사책 잉크 | ③ `BibleDrawing` 에 새 optional 필드(V7) |
|---|---|---|---|
| 옛 기기에서 보이는 것 | 캔버스 · 이전 필사 · 탐색 칠하기 · 즐겨찾기 · 위젯에서 안 보임. 차트 날짜별 수 · 주간 합계에는 셈 | 전혀 안 보임(레코드 타입을 모름) | **보통 행으로 보임** — 같은 절의 기본 행과 대표 경쟁 |
| (a) | ✅ 강제 언랩 0, EN-M4 실측 선례 | ✅ 1.3.0 실측(ENT-P1), 2.x 는 미시험 | ✅ |
| (b) | ✅ (차트 수만 예외) | ✅ | ❌ 장 하나 · 이전 필사 목록에 두 필사책이 섞임 |
| (c) | ✅ 옛 앱의 모든 쓰기가 `titleName ==` 로 행을 찾음 | ✅ | ❌ 대표로 뽑힌 다른 필사책 행에 `.replace` · `.clear`, 보관 행을 필사책 없이 복사, `isPresent` 이동 |
| 스키마 · 배포 | 잉크는 없음(필사책 정보만 V7) | V7 + Production 배포 | V7 + Production 배포(필드 영구) |
| 저장 경로 | 지금 경로 그대로(키만 바뀜) | **이중화** — 캔버스 · 이력 · 백업 · 차트 · 초안을 두 엔티티로(영어 번역본 때 기각한 이유와 같다) | 그대로 + 모든 술어에 필드 조건 |
| 옛 앱 「모든 필사 삭제」 | 함께 지움(사용자 뜻과 맞음) | 못 지움(F20) | 함께 지움 |

- ③ 은 단독으로 쓸 수 없고, ② 는 ① 과 같은 안전성을 저장 경로 이중화 비용으로 산다.
- 그 밖의 기각: **`BibleChapter.notebook` 필드**(번역본 선례와 맞고 호출부 수정은 적지만, 기본값이 조용히 기본 필사책에 써서 섞임 결함이 생기고 `==` 변경이 탐색 선택 비교를 흔든다) ·
  **필사책 정보를 iCloud KVS 에**(스키마 · 운영 배포 · C14 관측이 빠지지만 행과 따로 동기화되고 전체 삭제 · 백업 · 계정 전환을 따로 챙겨야 하며 핵심 데이터에 권하지 않는다 — C14 비용을 알고 다시 물었을 때도 V7 유지) ·
  **필사책 정보를 `BibleDrawing` 특수 행으로**(옛 앱 `hasAny` · 차트 수 · 전체 삭제에 섞이고 행의 뜻이 뒤엉킨다) ·
  **기존 필사를 번역본별 기본 필사책으로 나누기 · 업데이트 때 묻기**(기본 필사책 하나가 행을 고치지 않고 옛 기기와의 공유를 그대로 둔다).

## 5. V7 `DrawingNotebook`

### 5-1. 필드

`Domain/Domain/Sources/SwiftData/Model/DrawingSchemaV7.swift`. **모든 필드 optional, `unique` · 관계 없음**(CloudKit private DB 미러링 조건). `public typealias DrawingNotebook = DrawingSchemaV7.DrawingNotebook`.

| 필드 | 타입 | 뜻 |
|---|---|---|
| `notebookID` | `String?` | `NotebookID.rawValue` — 「default」 또는 소문자 16진 32자리. 풀지 못하면 그 레코드를 쓰지 않는다 |
| `name` | `String?` | 사용자가 지은 이름. nil = 메타데이터에 이름 없음(기본 필사책은 화면 언어의 「첫 번째 필사」, 그 밖은 「이름 없는 필사책」) |
| `status` | `String?` | `NotebookStatus` rawValue(`active` · `completed`). **열거형 열이 아니다** — 모르는 값 · nil 은 active(혼재 ④) |
| `createdAt` | `Date?` | 만든 시각 — 책장 카드의 시작 월 · 정렬 |
| `updatedAt` | `Date?` | 이름 · 상태를 바꾼 시각 — 같은 `notebookID` 레코드가 둘 이상이면 이것이 최신인 것을 쓴다(§5-3) |
| `completedAt` | `Date?` | 완료로 표시한 시각. 완료 취소면 nil |
| `kind` | `String?` | 「personal」 — 그룹 · 챌린지 연결 고리. 1차는 늘 personal |
| `scopeData` | `String?` | **예약** — 말씀 범위 JSON. 1차 nil |
| `linkData` | `String?` | **예약** — 그룹 · 챌린지 연결 JSON. 1차 nil |

시각은 리듀서에서 `@Dependency(\.date)` 로 받아 저장소에 `now` 로 넘긴다(`create(id:name:now:)` · `rename(_:to:now:)` · `setCompleted(_:_:now:)`).

### 5-2. 예약 필드 — 그룹 · 챌린지 연결 고리

- `kind` 는 필사책의 종류다. 1차는 만들 때 「personal」 만 쓰고 이 값으로 동작을 가르지 않는다 — 모든 필사책이 개인 필사책이다. 그룹 공동 필사책 · 챌린지가 붙을 때 값이 는다.
  String 열이라 값이 늘어도 2.2 가 디코딩하다 죽지 않는다(혼재 ④ 와 같은 이유).
- `scopeData` 는 필사책의 말씀 범위(결정 4 — 1차는 성경 전체라 nil), `linkData` 는 그룹 · 챌린지와의 연결이다. 형식(JSON 스키마)은 그 기능을 설계할 때 정한다.
- 필드를 미리 두는 이유: V7 은 첫 TestFlight 뒤에는 필드를 고칠 수 없고(결정 16), CloudKit 에 배포한 필드는 지울 수 없다. 연결 고리를 V8 로 미루면 운영 배포 · 판독기 관측(G-2)을 다시 치른다.
- 1차 코드는 `scopeData` · `linkData` 를 읽지도 쓰지도 않는다. 백업 형식 2 의 필사책 목록은 그대로 옮겨 담는다(§7).

### 5-3. 같은 ID 레코드 · 메타데이터 없는 필사책

- **같은 `notebookID` 레코드가 둘 이상**(두 기기가 오프라인에서 기본 필사책 이름을 바꾸는 등 동기화 중복)이면 `updatedAt` 이 최신인 것을 쓴다(같으면 `name` 사전순).
  이름 바꾸기 · 완료 표시는 그 ID 의 레코드 **전부**를 갱신한다 — 중복을 지우는 파괴적 정리는 하지 않는다.
- **기본 필사책의 메타데이터 레코드는 이름을 바꾸거나 완료를 표시할 때만** `notebookID` 「default」 로 생긴다. 없으면 이름은 「첫 번째 필사」(화면 언어), 시작 시각은 접두 없는 행의 가장 이른 `creationDate`.
- **메타데이터 없이 행만 있는 필사책**(혼재 ⑥)은 `hasMetadata == false` 로 목록에 넣고 「이름 없는 필사책」 으로 보인다. 이름을 바꾸면 레코드가 생긴다.
- 지우기는 그 ID 의 `DrawingNotebook` 레코드 전부와 그 필사책의 `BibleDrawing` 행 전부를 한 트랜잭션으로 **물리 삭제**한다. 필사 저장소 세대(`DrawingStoreGeneration`)는 바꾸지 않는다 — 전체 삭제만 바꾼다.

계약(`Domain/Domain/Sources/Notebook/`):

| 타입 · 요구 | 뜻 |
|---|---|
| `NotebookSnapshot` | `id` · `name: String?` · `status` · `createdAt` · `completedAt` · `writtenVerseCount` · `hasMetadata` |
| `writtenVerseCount` | 그 필사책의 절별 **대표 행**(`DrawingRepresentativeRule`)에 잉크가 있는 절 수 — 모든 번역본 합산, 비운 대표 · 보관 행은 세지 않는다 |
| `notebooks()` | 기본이 늘 첫째, 나머지는 `createdAt` 오름차순 · nil 은 뒤. 메타데이터 레코드와 행 접두에서 모은 필사책을 합친다 |
| `create(id:name:now:)` | 레코드 하나(`kind` 「personal」 · `status` 「active」 · `createdAt` = `updatedAt` = now) |
| `rename(_:to:now:)` · `setCompleted(_:_:now:)` | 같은 ID 레코드 전부 갱신, 없으면 만든다(기본 포함). 완료 취소면 `completedAt` = nil |
| `delete(_:)` | 기본이면 `NotebookRepositoryError.cannotDeleteDefault` |
| `@Dependency(\.notebookRepository)` | liveValue = SwiftData 구현(공유 actor 경유), testValue = 공유 actor 를 쓰지 않는 빈 스텁(기본 하나 · 나머지 no-op) |

### 5-4. 스키마 · 마이그레이션

- `DrawingSchemaV7: VersionedSchema`(7.0.0) = V6 모델 전부 + `DrawingNotebook`. `AppStoreSchema.models = DrawingSchemaV7.models`.
- 마이그레이션 V6 → V7 은 **lightweight**(엔티티 추가뿐 — 필사 행은 그대로). V2 → V3 · V3 → V4 · V4 → V5 · V5 → V6 과 같은 꼴이다. 시험 `DrawingSchemaV7MigrationTesting`.
- 말씀 카드 엔티티가 합류하면 **첫 TestFlight 전에** 이 V7 에 더한다(결정 16). 그 밖에는 V7 필드를 바꾸지 않는다. TestFlight 에 한 번 나간 뒤에는 V8 로 올린다.
- V6 의 `VerseDrawingVersion` · `DrawingEraseEpoch` 는 여전히 쓰지 않는다(혼재 ③). 운영 컨테이너 Development 에도 이 두 타입은 만들어지지 않아 V7 을 배포해도 딸려 가지 않는다.

### 5-5. 소유 증명 판독기(C14) — G-2 전까지 보류

`LegacyRowLinkageReader.validatedSchemaMajors` 는 `[3, 6]` 이고 `validatedEntities` 는 `BibleDrawing` · `BiblePageDrawing` · `FavoriteVerse` 다(develop `Domain/Domain/Sources/SwiftData/LegacyRowLinkageReader.swift`).
`AppStoreSchema` 가 V7 이 되면 V7 저장소는 판독기가 **unknown(unvalidatedModel)** 으로 판정해 첫 로그인 · 계정 전환 · 1.3.0 업그레이드 증명이 보류된다 — **실패 닫힘이라 데이터 손실은 없다.**
관측 없이 7 을 더하지 않는다는 판독기 규칙에 따라 검증 범위는 DAG 안에서 바꾸지 않는다. 바뀐 흐름의 시험은 t0 이 `withKnownIssue("G-2: V7 판독기 관측 전")` 로 감싸고,
G-2 가 관측 뒤 범위를 넓히며 지운다(§9 G-2). 판독기 시험의 고정 저장소는 `DrawingSchemaV6` 모델로 고정해 「V6 저장소」 라는 뜻을 지킨다.

구현 중 알게 된 G-2 범위(2026-10-16):
- **보류되는 흐름이 판독기 하나보다 넓다.** `LegacyMigrationContentMatcher` 도 `[3, 6]` 만 받아 V7 사본의 내용 대조가 「지원 저장소 model profile 이 아님」 으로 실패한다 — G-2 는 둘을 함께 넓힌다.
- **로그인한 새 설치도 보류된다.** 빈 저장소의 소유 판정(`emptyLinkedStore`)도 판독기를 거치므로, G-2 전의 2.2 새 설치 사용자는 동기화가 연결되지 않고 로컬로만 연다.
  연결 표식이 이미 있는 기존 사용자의 재실행은 판독기를 거치지 않는다. 시뮬레이터에서도 로그인 계정 + 소유 주입 없이 실행하면 연결이 보류돼 필기가 기기 안 초안으로 갔다(§9 M7).
- **V6 → V7 에서 엔티티 번호(`Z_ENT`)가 밀린다** — 이름순으로 `DrawingNotebook` 이 끼어 `DrawingNotebook` 4 · `FavoriteVerse` 4 → 5 · `VerseDrawingVersion` 5 → 6 이다.
  시험 저장소와 시뮬레이터에서 2.1 저장소를 덮어 설치해 마이그레이션한 실제 저장소(§9 M1) 모두 같았다. 고정 번호를 가정하는 곳은 G-2 에서 확인한다.
- 시험에서 `withKnownIssue("G-2: V7 판독기 관측 전")` 로 감싼 것은 19개다 — `LegacySeparationGateTesting` 16 · `LegacyRowLinkageReaderTesting` 2 · `MigrationSyncReleaseTesting` 1.
- 말씀 카드 엔티티가 V7 에 합류하기로 해(2026-10-16, 카드 모델 10-24 동결) G-2 관측은 카드가 들어간 V7 로 한 번만 한다.

### 5-6. CloudKit 운영 배포 (출시 관문 G-3)

**시점: 2.1.0 출시 뒤 · 외부 TestFlight 전.** DAG 밖의 사람 작업이다. **배포한 레코드 타입 · 필드는 지울 수 없다.** Production 은 스키마에 없는 필드를 가진 레코드를 거절한다.
2.0.0 배포의 절차를 따른다([2.0.0 로드맵](./release-2.0.0-roadmap.md) §7 차단 5, 2026-09-29).

1. **운영 컨테이너의 Development 를 채운다.** 운영 컨테이너 ID 를 빌드 인자로만 덮은 Debug 빌드(파일 수정 없음)를 **새 iPad 시뮬레이터**에 설치하고 로그인한다 —
   컨테이너 ID 가 dev 를 담지 않으면 로컬 저장소가 운영 sqlite 라 실기기에는 하지 않는다. 실행 전 설치본 Info.plist 의 컨테이너 ID 를 확인한다(다른 빌드가 덮어 설치할 수 있다).
   필사책 만들기 · 이름 바꾸기 · 완료 표시 · 다른 필사책에 필기로 `CD_DrawingNotebook` 의 필드마다 값이 한 번 들어가게 한다. **`scopeData` · `linkData` 는 1차 코드가 값을 쓰지 않아 저절로 생기지 않는다** —
   콘솔 Record Types 에서 직접 더할지(2.0.0 `_ckAsset` 선례), 예약 필드를 나중 배포로 미룰지를 G-3 때 정해 여기에 적는다.
2. **확인한다.** V6 두 타입(`CD_VerseDrawingVersion` · `CD_DrawingEraseEpoch`)이 Development 에 생기지 않았는지 본다.
3. **배포 확인창의 변경 목록을 모델 선언과 대조한다** — `CD_DrawingNotebook` 과 그 필드(`CD_notebookID` · `CD_name` · `CD_status` · `CD_createdAt` · `CD_updatedAt` · `CD_completedAt` · `CD_kind` · 정한 경우 `CD_scopeData` · `CD_linkData`) 밖의 것이 없어야 한다.
4. **배포한다.** 그 뒤 TestFlight 두 기기로 동기화를 본다(G-5).

## 6. 화면

### 6-1. 책장 — `NotebookShelfFeature`

- 앱 스택 화면이다(`AppCoordinatorFeature.Path.notebooks`, 본보기 `FavoriteListFeature` · `FavoriteListView`). 진입은 셋(결정 9):
  ① 서재 열 아래 아이콘 줄의 「책장」(즐겨찾기 왼쪽) ② 번역본 팝오버 끝 「책장 열기」 ③ 실행 인자 `-UITestRoute notebooks`.
- 열릴 때 `notebookRepository.notebooks()` 를 읽고, iCloud 도착 신호가 오면 다시 읽는다.
- **카드 격자**: 필사책마다 카드 하나 — 이름 · 시작 월(`createdAt` 의 연 · 월, 환경 locale 서식, 없으면 생략) · 쓴 절 수(복수형 카탈로그) · 지금 필사책 표시 · 완료 배지. 마지막에 「새 필사책」 카드.
- **카드를 누르면** 그 필사책을 고르고 필사 화면으로 돌아간다(`Delegate.notebookChosen` → 코디네이터가 path 를 비우고 carve `switchNotebook`).
- **카드 메뉴**(컨텍스트 메뉴 또는 … 버튼): 이름 바꾸기 · 완료로 표시/완료 취소 · 지우기(기본 필사책에는 없음).
- **아래에 옛 기기 안내 한 줄**(결정 14, §6-7).
- **관리 동작의 쓰기 막음(구현 중 정함, 2026-10-16 — 사용자 검토 대상).** 만들기 · 이름 바꾸기 · 완료 표시/취소 · 지우기는 동기화 저장소에 쓰므로
  즐겨찾기 · 백업 불러오기 · 전체 삭제와 같은 규칙을 따른다 — 쓰기 전에 `SyncedWriteBlock.check(drawingEditEnvironment.current())` 를 보고, 막히면
  저장소 · 지금 필사책 키 · 위임을 그대로 두고 「지금은 필사책을 만들거나 고칠 수 없어요. <사유>」 를 알린다(사유 문장은 즐겨찾기와 같다).
  까닭: 연결이 보류됐거나(무계정 · 소유 미확인) 계정이 확인되지 않은 저장소는 CloudKit 없이 열려 있어, 거기 쓴 메타데이터 · 지운 행이 나중에 계정과 어긋난다(C14 ③ · D2).
  **고르기는 막지 않는다**(기기 안 키만 바꾼다). 그래서 **무계정 기기는 필사책을 만들 수 없다** — 2.1 무계정 기기가 즐겨찾기를 쓰지 못하고 필기가 기기 안 초안으로 가는 것과 같다.
- 서재 열 아래 「책장」 버튼의 아이콘은 **임시로 `CarveIcon.library`**(사이드바 단추와 같은 그림)다 — 책 모양 아이콘(Resources 에셋 + `CarveIcon` case)은 후속.

### 6-2. 헤더 부제 · 「책장 열기」

- 필사 화면 헤더의 부제 첫 칸에 지금 필사책 이름 — 「두 번째 필사 · 개역개정 · 구약」(`HeaderFeature.State.notebookName`). 시작 · 필사책 바꾸기 · iCloud 도착 때 이름을 다시 읽는다.
  이름을 읽기 전(시작 직후)에는 첫 칸을 두지 않는다. 기본 표시(「첫 번째 필사」 · 「이름 없는 필사책」)는 뷰가 환경 locale 로 만든다.
  지금 필사책의 이름을 바꾸면 책장이 `currentNotebookChanged(같은 ID)` 를 보내 필사 화면이 장은 다시 열지 않고 이름만 다시 읽는다.
  전체 삭제 뒤에는 목록을 읽지 않고 이름 없는 기본 필사책으로 둔다(모든 필사책 정보가 지워졌다).
- 헤더 제목을 눌러 여는 번역본 팝오버(`TranslationPickerView`) 끝에 「책장 열기」 한 줄 → `HeaderFeature.Action.View.notebooksTapped` → `CarveNavigationFeature` 가 `.view(.moveToNotebooks)` → 코디네이터가 push.

### 6-3. 만들기

- 「새 필사책」 카드 → 시트. 이름 입력란에 **제안 이름**(순수 함수): ko 「두 번째 필사」 … 「열 번째 필사」, 그 다음은 「11번째 필사」 꼴, en 「Notebook 2」 꼴(기본 필사책 하나뿐이면 「두 번째 필사」 · 「Notebook 2」). 제안일 뿐 고칠 수 있다.
- 만들기 → `NotebookID.make(uuid:)` → `create(id:name:now:)` → 지금 필사책 키를 새 ID 로 → 분석 `feature_complete`(`notebook`, 성공) → `notebookChosen(새 ID)`.
- **지금 보던 장이 빈 종이로 열린다**(결정 6) — 새 필사책에는 행이 없다. 시트에도 옛 기기 안내 한 줄.

### 6-4. 이름

- 앞뒤 공백을 자르고 빈 이름은 받지 않는다. **40자 상한**. 기본 필사책도 바꿀 수 있다(메타데이터가 없으면 이때 생긴다).
- 필사책 이름은 **사용자 입력이라 옮기지 않는다**(`Text(verbatim:)` 꼴). 이름이 없을 때만 화면 언어의 기본 표시 — 기본 필사책 「첫 번째 필사」, 그 밖 「이름 없는 필사책」.

### 6-5. 완료 표시

- 「완료로 표시」 / 「완료 취소」. **표시일 뿐이다** — 완료한 필사책도 고르고 계속 쓸 수 있다. 카드에 완료 배지, `completedAt` 기록.

### 6-6. 지우기

- 기본 필사책에는 없다(저장소도 `cannotDeleteDefault` 로 막는다). 보관(숨기기)은 없다(결정 7).
- 확인 대화상자 「『<이름>』 과 그 필기를 모두 지울까요? 되돌릴 수 없어요.」 → 순서:
  ① 지금 필사책이면 먼저 키를 「default」 로 하고 `Delegate.currentNotebookChanged(.default)`(책장에 머문 채 필사 화면이 기본 필사책으로 다시 읽는다)
  ② `notebookRepository.delete` — 그 필사책의 행 전부 + 메타데이터 레코드 전부 ③ 그 필사책의 기기 안 초안 `discardDrafts(notebook:)`.
- 다른 기기가 오프라인에서 그 필사책에 쓴 필기가 늦게 오면 「이름 없는 필사책」 으로 다시 보인다(혼재 ⑥) — 다시 지울 수 있다.

### 6-7. 옛 기기 안내

책장 아래와 만들기 시트에 한 줄: **「2.2 이전 버전을 쓰는 기기에서는 처음부터 있던 필사책만 보여요」**. 옛 기기에서 다른 필사책이 보이지 않는 것(§4-2)을 미리 알린다.

### 6-8. 지금 필사책 · 필사책 바꾸기

- 지금 필사책은 `@Shared(.currentNotebookID)` — `.appStorage("currentNotebookID")` String, 기본 「default」, **기기마다**(결정 13). 읽을 때 `NotebookID(rawValue:)` 가 nil 이면 기본.
- 목록에 없으면(다른 기기에서 지움) **시작 때와 iCloud 도착 때** 기본으로 되돌린다.
- **필사책 바꾸기 = 장 바꾸기와 같은 흐름**: 앞 필사책의 미저장분은 앞 필사책으로 저장된다(대기 명령 `PendingDrawingMutation` · `VerseEraseTask` 가 page 를 든다) → 새 page 를 다시 읽는다. 보던 절은 유지한다.
  저장 큐 · 저장소 세대 · 캔버스 합성 규칙은 바꾸지 않는다(D9 영역 — 결정 6 · 17).
- **번역본 바꾸기는 필사책을 유지한다**(결정 8) — 같은 필사책의 다른 번역본 page 를 연다. 그 번역본에 쓴 적이 없으면 빈 종이다.

### 6-9. 화면 이동 경계

| 경계 | 뜻 |
|---|---|
| `CarveNavigationFeature.Action.switchNotebook(NotebookID)` | 지금 필사책을 바꾸고 지금 장을 그 필사책으로 다시 연다 |
| `CarveNavigationFeature.Action.openPage(NotebookChapter, verse: Int?)` | 필사책과 장을 함께 연다 — 차트 최근 기록 |
| `CarveNavigationFeature.Action.View.moveToNotebooks` | 책장 열기 → 코디네이터 push |
| `moveToChapter(BibleChapter)` · `moveToVerse(BibleVerse)` | 그대로 — **지금 필사책**으로 연다(위젯 · 필사 알림 · 즐겨찾기, 결정 15) |
| `NotebookShelfFeature.Delegate` | `notebookChosen(id)` → path 비움 · carve `switchNotebook(id)` / `currentNotebookChanged(id)` → path 유지 · carve `switchNotebook(id)` / `backToWriting` → pop |
| ChartFeature 최근 기록 위임 | `openChapter(NotebookChapter)` · `openVerse(NotebookChapter, verse: Int)` → 코디네이터가 carve `openPage` |
| 실행 인자 | `-UITestRoute notebooks`([실기기 · 시뮬레이터 요령](./device-simulator-verification.md) 「화면 바로 열기」) |

### 6-10. 문구 · 영어 용어

새 문구는 모듈 `Resources/Localizable.xcstrings` 에 ko · en 둘 다 translated + comment(어디에 나오는지). 규칙은 룰북 `references/localization.md`.

| ko | en |
|---|---|
| 필사 | Writing |
| 필사책 | Notebook |
| 책장 | Notebooks |
| 첫 번째 필사(기본 필사책의 기본 이름) | First Notebook |
| 이름 없는 필사책 | Untitled Notebook |
| 두 번째 필사 … 열 번째 필사 · 11번째 필사 …(이름 제안) | Notebook 2 … |

수는 복수형 카탈로그(쓴 절 수), 날짜는 환경 locale 서식(시작 월). 새 영어 문구는 구현 보고의 한영 목록으로 사용자가 검토한다.

## 7. 다른 기능과의 관계

| 기능 | 2.2 의 동작 |
|---|---|
| **이전 필사 보기**(`VerseDrawingHistoryFeature`) | **필사책 안에서만** — 같은 page 의 `titleName` 을 가진 그 절의 행(보관 행 · 대표). `fetchVerseSnapshots(page:verse:)` · 고르면 `updatePresentDrawing(page:verse:presentRowID:)` 가 그 필사책 안에서 `isPresent` 를 옮긴다. State id 는 `StoredBookKey.titleName(for: page)` 기반 |
| **절 지우기**(`archiveAndReset`) | 그 필사책의 행만 보관 · 비운다. 보관 행은 활성 행의 `titleName` · `translation` 열을 그대로 복사한다(지금처럼). 다른 필사책의 `isPresent` 를 건드리지 않는다 |
| **탐색 장 칠하기** | 지금 필사책 · 번역본의 장 — `fetchDrawingRecord(notebook:title:translation:)`. 필사책을 바꾸면 칠한 장을 비우고 다시 읽는다 |
| **즐겨찾기 · 위젯** | **필사책 공통**(결정 11) — 키는 지금처럼 번역본 · 권 · 장 · 절, 추가할 때 **지금 필사책의 필기 사본**을 담는다. `FavoriteVerse` 에 접두를 쓰지 않는다(혼재 ③). 목록은 필사 행을 읽지 않아 키 · 스키마 변경이 없고 2.0 · 2.1 기기에도 그대로 보인다 |
| **위젯 · 필사 알림 · 즐겨찾기에서 열기** | 지금 필사책으로 연다(결정 15) — `moveToChapter` · `moveToVerse` 그대로 |
| **필사 알림**(2.2, `feat/2.2-reading-reminder`) | 알림을 누르면 필사 화면을 **지금 필사책**으로 연다. 필사책별 알림은 없다 |
| **차트 · 주간 요약** | **모든 필사책 합산**(결정 10). 날짜별 · 주간 수는 지금처럼 행 수, 장별 수 · 최다 장은 `BibleChapter`(번역본 포함) 키로 필사책을 합산. 활동 `DrawingActivity.page` 가 `decodeRow` 로 모든 필사책의 행을 푼다(2.1 은 접두 행이 장별 수에서 빠진다 · 깨진 접두 행은 날짜별 수에만 든다). 누르면 여는 필사책(2026-10-16 t2b 구현 — 위임 `openChapter(NotebookChapter)` · `openVerse(NotebookChapter, verse:)` → 코디네이터가 carve `openPage`): **최근 장**은 필사책을 합산해 같은 장(번역본 포함)을 한 줄로 보이고 그 장의 **가장 최근 행의 필사책**으로 연다(`recentChapters`). **가장 많이 쓴 장**(「이어서 쓰기」)은 **보이는 주에서 그 장을 마지막으로 쓴 필사책**으로 연다(`topChapterPage` — 날마다 그 장을 마지막으로 쓴 필사책 `chapterNotebooksByDay` 를 주의 끝날부터 거슬러 찾는다). **그 필사책을 모르면 열지 않는다** — 기본 필사책으로 바꿔 열지 않는다. **최근 절**은 그 행의 필사책으로 연다(`RecentVerseItem.notebook` — 기본값이 없다). 같은 절이 두 필사책에 있으면 최근 절 항목 id 가 다르다 |
| **초안 · 확인이 필요한 필기** | `VerseDraftKey` 에 필사책(옛 초안 · 키 없음 = 기본). 파일 이름은 기본 필사책이면 지금 그대로 `<번역~권~장~절>.json`, 그 밖은 앞에 `nb_<id>~`. 복구 · 가져오기는 그 page 의 대표와 견준다. 확인이 필요한 필기 화면(2026-10-16 t2c 구현)은 목록을 page 단위로 들고(항목 id 에 필사책), **기본 필사책이 아니면 절 · 장 이름 앞에 필사책 이름**을 붙인다(`DraftRecoveryCopy.place(_:notebookNames:locale:)` · `chapterName(_:notebookNames:locale:)` — 「<이름> · <자리>」). 이름이 없거나 지운 필사책이면 화면 언어의 「이름 없는 필사책」(혼재 ⑥ — 숨기거나 기본에 합치지 않는다). 이름은 기본이 아닌 필사책이 있을 때만 `notebooks()` 로 읽는다. 기본 필사책은 이름을 붙이지 않는다(2.1 과 같은 줄). 가져오기 뒤 알림은 page 로(`LocalDrawingChange(page:date:)`). 필사책을 지우면 그 필사책 초안을 버린다(`discardDrafts(notebook:)`) |
| **가져오기 도착**(`LocalDrawingChange`) | `page` 를 든다 — 캔버스는 `change.page == state.page` 일 때만 반영한다(다른 필사책의 도착은 무시) |
| **백업** | **형식 2**(혼재 ⑤ — [백업 설계](./backup-import-design.md) §10): `BackupVerseKey.notebook`(nil = 기본 필사책, 형식 1 은 늘 nil) + **필사책 목록은 별도 파일이 아니라 `manifest.json` 의 `notebooks` 키**(`BackupNotebookRecord` — `DrawingNotebook` 의 필드 전부, 예약 필드 포함, 필사책마다 하나). 별도 파일로 두지 않은 이유: 2.1 의 풀기는 `manifest` · `items` · `blobs/<hex>` 밖의 항목 이름을 **형식 확인 전에** 「손상」 으로 거부해(`BackupArchiveEntry`) 업데이트 안내가 뜨지 않는다. 내보내기는 `decodeRow` 로 모든 필사책의 행을 담고, **다른 필사책 초안도 담는다**(2026-10-16 t4 — 자리는 필사책 · 권 · 장, 초안 요약의 `pages`). 다른 필사책 초안의 id 원본 키에는 필사책 토큰을 더한다(`draftSourceKey(…notebook:)` — 같은 세션 · 절 · revision · 내용의 두 필사책 초안 id 가 겹쳐 한쪽이 조용히 빠지는 것을 막는다. 기본 필사책 초안의 키는 2.1 과 같다). 불러오기는 1 · 2 를 읽고 1 은 전부 기본, 판정 단위 · 장에 필사책을 더한다(같은 내용이라도 필사책이 다르면 다른 절). 필사책 목록은 장보다 먼저 쓰고 같은 ID 가 있으면 `updatedAt` 이 늦은 쪽. 형식 2 항목의 필사책 토큰이 `NotebookID` 형식이 아니면 그 항목만 건너뛰고 **`BackupUnsupportedReason` 이 아니라 미리보기 `preview.unknownNotebook` 으로 센다**(설정 화면이 그 열거형을 빠짐없이 `switch` 한다 — 「넣을 수 없는 것」 수에는 든다). 미리보기에 필사책 수. 불러오기 작업 기록은 **recordVersion 2**(끝난 장이 `NotebookChapter` — 2.1 기록은 기본 필사책의 장으로 읽어 이어 한다). 2.1 은 형식 2 파일을 거부하고 업데이트를 안내한다 |
| **모든 필사 삭제**(`DrawingDataEraser.eraseAll`) | 모든 필사책의 행 + `DrawingNotebook` — 순서 `BibleDrawing` → `BiblePageDrawing` → `FavoriteVerse` → `DrawingNotebook` → 기기 보존 영역. 저장소 세대를 바꾼다(지금처럼). 2026-10-16 t2c · t2a 구현: 설정이 지운 뒤 **지금 필사책 키를 기본(`default`)으로 되돌린다**(`iCloudSettingReducer.resetCurrentNotebook()` — 세대를 올리는 `DrawingDataRevision.bump` 보다 먼저). 지운 필사책을 가리킨 채 남으면 그 page 에 새로 쓴 행이 「이름 없는 필사책」 으로 다시 생긴다. **열린 필사 화면은 캔버스 정리 뒤 지금 키(기본)의 page 로 다시 연다**(`CarveDetailFeature.reopenInCurrentNotebookIfNeeded` — 보던 절 유지, 정리가 시작한 옛 page 의 다시 읽기는 새 요청으로 대체돼 버려진다). 확인 문구에 필사책 한 줄(「모든 필사책과 필사책 정보가 지워지고 처음부터 있던 필사책만 남는다」 뜻) |
| **필사책 지우기** | 그 필사책의 행 + 메타데이터만, 한 트랜잭션, 세대는 바꾸지 않는다(§5-3 · §6-6) |
| **iCloud 도착** | 열린 장을 다시 읽는다(지금처럼, page 로). 지금 필사책이 목록에 없으면 기본으로. 책장 · 헤더 이름을 다시 읽는다 |
| **V6 `VerseDrawingVersion` · `DrawingEraseEpoch`** | 손대지 않는다(혼재 ③) |
| **분석** | 만들 때 `feature_complete`(`AnalyticsFeatureName.notebook`, 성공). 책장 진입은 코디네이터의 `screen_view`(기존 Path 꼴) |

## 8. 알려진 한계

| 한계 | 이유 · 후속 |
|---|---|
| **옛 기기(2.0.0 · 2.1)에는 기본 필사책만 보인다** | 다른 필사책의 행은 옛 앱 술어에 맞지 않는다(§4-2) — 의도한 동작. 책장 · 만들기 시트의 안내 한 줄(§6-7)로 알린다 |
| **옛 기기 차트 날짜별 수 · 주간 합계에 다른 필사책도 든다** | 옛 활동 조회는 `updateDate` 술어로 권을 가리지 않는다. 2.2 차트는 의도대로 합산이라(결정 10) 같은 수다. 2.1 은 장별 수 · 최다 장에서 빠진다 |
| **2.0.0 주간 요약 「최근 절」 이 다른 필사책 행을 창세기로 보일 수 있다** | main `DrawingChartFeature.swift:212` 의 `BibleTitle(rawValue:) ?? .genesis` — 누르면 창세기 그 장 · 절로 간다. 쓰기 · 크래시는 없다(영어 행에서 EN-M4 로 확인한 것과 같은 경로). 이미 나간 버전이라 고칠 수 없다. 2.1 은 건너뛴다. 공존 C2 에서 기록한다 |
| **2.1 백업 내보내기에 다른 필사책 행이 빠진다** | 2.1 은 `decode` 가 nil 인 행을 담지 않고 수만 로그로 남긴다. 2.1 기기에서 만든 백업에는 기본 필사책만 있다 — 다른 필사책까지 담으려면 2.2 기기에서 백업한다 |
| **2.1 은 2.2 백업(형식 2)을 불러오지 못한다** | 형식이 다르면 파일 전체를 거부하고 업데이트를 안내한다(혼재 ⑤) — 기본 행에 합쳐지는 것보다 낫다. 공존 C4 |
| **옛 기기의 「모든 필사 삭제」 는 필사책 정보를 남긴다** | 옛 앱은 `DrawingNotebook` 을 모른다(1.3.0 의 F20 과 같은 성질). 필기는 모두 지워지지만 2.2 에 **빈 필사책 카드**(쓴 절 0)가 남는다. 2.2 에서 지우면 된다. 공존 C3 |
| **지운 필사책 · 늦게 온 행은 「이름 없는 필사책」 으로 보인다** | 다른 기기가 오프라인에서 쓴 필기가 지운 뒤에 오거나, 행이 메타데이터보다 먼저 오면 메타데이터가 없다(혼재 ⑥). 숨기거나 합치지 않는다 — 메타데이터가 오면 이름이 보이고, 지운 것이면 다시 지울 수 있다 |
| **지금 필사책은 기기마다다** | 다른 iPad 는 따라오지 않는다(결정 13). 마지막 장(`@Shared("title")`)과 같다 |
| **V7 저장소의 소유 증명이 G-2 전까지 보류된다** | 판독기가 V7 을 unknown 으로 판정한다(§5-5) — 첫 로그인 · 계정 전환 · 1.3.0 업그레이드 연결이 보류(실패 닫힘, 손실 없음). develop 병합 · TestFlight 전에 G-2 로 푼다 |
| **2.0.0 · 2.1 이 모르는 레코드 타입을 받는 실측이 아직 없다** | 1.3.0 만 실측(ENT-P1 · FAV-P0). 공존 C1 · C2 가 2.x 첫 실측이다 — 출시 관문 |

## 9. 확인 — 자동 · 수동 M · 공존 C · 출시 관문 G

### 9-1. 자동

레이어마다 통합 브랜치 전체 회귀 통과(기준선은 [회귀 기준선](./regression-baseline.md) 한 곳), 바뀐 파일 SwiftLint error 0, 새 시험 통과 —
행 키(`StoredBookKeyNotebookTesting` · `NotebookIDTesting`) · V7 마이그레이션(`DrawingSchemaV7MigrationTesting`) · 필사책 격리(`NotebookDrawingIsolationTesting`) ·
필사책 저장소(`NotebookRepositoryTesting`) · 초안(`NotebookDraftTesting`) · 백업 왕복(`BackupNotebookRoundTripTesting`) · 필사책 바꾸기(`NotebookSwitchTesting`) ·
책장(`NotebookShelfFeatureTesting`) · 코디네이터(`AppCoordinatorNotebookTesting`) · 차트. t0 이 더한 `withKnownIssue`(G-2)는 게이트 보고에 「예상 실패」 로 센다.
여러 런타임 회귀(17.5 · 18.6 · 26.2 · 27.0)는 출시 시험에서 한다.

**결과(2026-10-16, Xcode 27.0 27A266a · iPad mini (A17 Pro) iPadOS 26.2):** 레이어 게이트 L0 1642 → L1 1702 → L2 1746 → L3 **1779 통과** · 실패 0
(출발점 기준선 1636 → +143, 총 1810 · 건너뜀 8 · 예상 실패 23 = 원래 4 + G-2 19). 회귀 기준선 문서 갱신은 사람이 한다(G-6).

### 9-2. 수동 M — 전용 iPad 시뮬레이터(26.2, Xcode 27 Debug)

새 기기에서 하고 끝나면 지운다(업데이트 · CloudKit 표본이 든 기기는 쓰지 않는다). 화면은 실행 인자로 연다(`-UITestRoute notebooks` 등).

2026-10-16 실행: 새 기기 `Carve-Notebook-M-A`(iPad mini (A17 Pro) 26.2)에 iCloud 시험 계정으로 로그인하고(사용자) Debug `-ACC1InjectStoreOwnership` 으로 연결했다 —
무계정이나 소유 주입 없이는 연결이 보류돼 필기가 기기 안 초안으로만 가고 즐겨찾기 · 백업 불러오기 · 필사책 관리가 막힌다(§5-5 · §6-1).
2.1 은 출발점 `33fd09ed` 빌드, 2.2 는 통합 브랜치 `d4e9460a` 빌드. dev 컨테이너만 썼고, M8 전체 삭제는 사용자 허락 뒤 그 시험 계정의 dev 데이터에 했다.

| ID | 시나리오 | 확인할 것 | 결과 |
|---|---|---|---|
| M1 | 기존 필사 보존 | 2.1 데이터가 든 기기에 2.2 를 덮어 설치 → 책장에 「첫 번째 필사」 하나, 모든 필기 · 이전 필사 · 즐겨찾기 · 위젯 그대로, 차트 수 같음 | ✅ 책장 「첫 번째 필사」 하나(34절). 필사 행 59 · 대표 39 · 즐겨찾기 4 가 2.1 과 같고 시편 23편 행은 크기까지 같음, `DrawingNotebook` 0행(마이그레이션이 만들지 않음). 3절 이전 필사 2회 · 위젯 App Group 파일 해시 · 차트(이번 주 18절 · 최다 장) 모두 같음 |
| M2 | 새 필사책 | 시편 23편에서 「두 번째 필사」 만들기 → 같은 장이 빈 종이, 헤더 부제가 바뀜. 쓰고 → 책장에서 첫 번째로 → 원래 필기 → 다시 두 번째 → 새 필기. 이전 필사 보기가 필사책별. 탐색 칠하기가 필사책별 | ✅ 빈 종이 · 부제 「두 번째 필사 · 개역개정 · 구약 / 시편」. 획 직후(저장 대기 중) 첫 번째로 바꿔도 그 획은 `nb_<id>~` 행으로 저장. 이전 필사 · 절 지우기 보관 행이 필사책별. 장 목록 칠하기 필사책별(접근성 값 「필사 기록 있음」 으로 확인) |
| M3 | 관리 | 이름 바꾸기(기본 포함) · 완료 표시/취소 · 지금 필사책 지우기 → 첫 번째로 · 기본 필사책엔 지우기 없음 · 옛 기기 안내 보임 | ✅ 기본 필사책 이름 바꾸기(이때 메타데이터 「default」 가 생김) · 완료 배지 · 취소 · 기본 메뉴에 지우기 없음 · 지금 필사책(세 번째) 지우기 → 행 · 정보 삭제 · 키 default. 이름 제안 「세 번째 필사」. ⚠️ 확인창 「『세 번째 필사』 과」 조사(받침 없는 이름) — 문구 검토 |
| M4 | 번역본 | 두 번째에서 KJV 로 바꾸면 KJV 빈 종이, 개역개정으로 돌아오면 두 번째의 개역개정 필기 | ✅ 「두 번째 필사 · KJV」 빈 종이(첫 번째의 KJV 필기 안 보임), KJV 행 `nb_<id>~KJV-…` · 번역본 열 nil, 개역개정으로 돌아오면 두 번째 필기 |
| M5 | 차트 · 즐겨찾기 · 위젯 | 날짜 수 합산, 최근 절을 누르면 그 필사책으로, 즐겨찾기 사본 = 그때 필사책의 필기, 위젯에서 열면 지금 필사책 | ✅ 오늘 4 → 10 · 이번 주 24절 · 최다 장 합산. 첫 번째일 때 최근 절(두 번째의 시편 24:1) → 두 번째로 열림. 즐겨찾기 행 `1-19Psalms.txt`(접두 없음) · 사본 = 두 번째 잉크. 위젯 주소(`carve://verse?…`) → 지금 필사책(두 번째)으로 열림 |
| M6 | 백업 | 2.2 백업(형식 2) → 다른 시뮬레이터 2.2 에 불러오기 → 필사책 · 이름 · 필기 복원 · 섞이지 않음. 2.1 백업(형식 1) → 2.2 에 불러오기 → 첫 번째 필사로 | ✅(같은 기기 — 다른 기기 대신 M8 전체 삭제 뒤 불러오기) 2.2 백업 manifest formatVersion 2 · `notebooks` 키 2개 · 항목 64(필사책 토큰 6). 불러오기 → 미리보기 「필사책 2권」, 넣은 58 · 필사책 정보 · 행 접두 · 크기 복원, 섞임 없음. 2.1 백업(형식 1, 58개) → 「필사책 1권」 · 같은 필사 57 · 넣은 0 |
| M7 | 초안 · 확인이 필요한 필기 | 두 번째에서 초안을 남기고(저장 실패 흉내 또는 앱 종료) 설정 화면에 필사책 이름, 가져오기가 두 번째로 | 🟡 일부. 보류 상태에서 두 번째에 쓴 획 → 초안 파일 `nb_<id>~NKRV~1-19Psalms.txt~23~4.json`, 두 번째 화면에만 겹쳐 보이고 첫 번째에는 없음. 「확인이 필요한 필기」 목록은 2.1 규칙상 자동으로 겹쳐 보일 초안을 세지 않아 화면에서 만들지 못함 — 이름 · 가져오기는 `DraftRecoveryNotebookTesting` 6개가 본다 |
| M8 | 전체 삭제 | 모든 필사책 · 필기가 지워지고 첫 번째만 남음 | ✅ 확인창 새 줄 「필사책도 모두 지워지고 「첫 번째 필사」만 남아요.」. 필사 행 · 필사책 정보 · 즐겨찾기 0, 키 default, 두 번째를 보던 화면이 「첫 번째 필사」 로 다시 열리고 다음 획은 기본 행 |
| M9 | 영어 화면 | 책장 · 헤더 부제 · 만들기 · 안내 문구(en), 이름 제안 「Notebook 2」 | ✅ Notebooks · Current · Started September 2026 · 34 verses written · New Notebook · 옛 기기 안내 · 이름 제안 「Notebook 3」(필사책 둘) · Rename / Mark as Completed / Delete Notebook · 부제 · 「Open Notebooks」. 사용자 이름은 그대로 |

수동 확인에서 찾은 결함(후속): **책장에서 「새 필사책」 시트를 「취소」 로 닫고 책장을 닫으면, 필사 화면 하단 도구 막대가 유리 바탕만 남고 도구가 사라지는 일이 간헐적으로 있다**
(시뮬레이터 26.2, 한 · 영 모두 — 11회 중 6회). 기다리기 · 막대 누르기 · 장 넘기기로 돌아오지 않았다. 「만들기」 로 닫을 때 · 백업 암호 시트 뒤에는 보지 못했다.

### 9-3. 공존 C — 출시 관문

같은 계정 dev 저장소, **새 시뮬레이터 두 대**(업데이트 표본 기기는 쓰지 않는다). 두 기기 방식은 [호환성 시험 계획](./icloud-sync-compatibility-test-plan.md) 단계 A 와 2.1 EN-M4 와 같다.

| ID | 시나리오 | 확인할 것 | 결과 |
|---|---|---|---|
| C1 | 2.2 ↔ 2.1 Debug | 2.2 에서 두 번째 필사에 쓰기 → 2.1: 죽지 않음 · 그 장에 안 보임 · 첫 번째 필기 그대로. 2.1 에서 같은 절을 고쳐 쓰기 → 2.2 두 번째 필사는 그대로(덮이지 않음), 2.2 첫 번째에 2.1 수정이 보임. 2.1 로그에 `CD_DrawingNotebook` 을 모르는 타입으로 건너뜀(**2.x 첫 실측**). 2.1 차트 날짜 수에 합산(알려진 한계) | 미수행 |
| C2 | 2.2 ↔ 2.0.0(main) Debug | C1 과 같은 항목 + 주간 요약 「최근 절」 창세기 표시 여부 기록 | 미수행 |
| C3 | 옛 기기 전체 삭제 | 2.1 에서 전체 삭제 → 2.2 필기가 모두 사라지고 필사책 카드(메타데이터)는 남음 — 알려진 한계로 확인 | 미수행 |
| C4 | 백업 교차 | 2.1 이 2.2 백업(형식 2)을 불러오면 거부 + 업데이트 안내 | 미수행 |

### 9-4. 출시 관문 G

| ID | 무엇 | 확인할 것 | 결과 |
|---|---|---|---|
| G-1 | V7 마이그레이션 | 2.1 출시본 데이터(시뮬레이터 17.5 · 18.6 · 26.2 · 27.0, 실기기 iPad 하나) → 2.2 업데이트 → 첫 실행 · 동기화 · 필기 보존 | 미수행 |
| G-2 | 소유 증명 판독기 V7(**develop 병합 · TestFlight 전 필수**) | V7 미러링 저장소를 OS 주 버전별(17 · 18 · 26 · 27)로 무계정 · 로그인 상태에서 관측(메타데이터 키 · `Z_ENT` · 미러링 표)하고 `validatedSchemaMajors` 에 7, 관측한 엔티티를 `validatedEntities` 에 더한다(엔티티가 늘면 `Z_ENT` 번호가 바뀔 수 있다 — 고정 번호를 가정하는 곳 확인). t0 의 `withKnownIssue` 를 지운다. 1.3.0 무계정 → 2.2 업그레이드 · 첫 로그인 · 계정 전환을 시뮬레이터로 확인. 사람 관측이 필요한 단독 작업 — DAG 뒤 별도 세션 | 미수행 |
| G-3 | CloudKit 운영 배포(2.1.0 출시 뒤 · 외부 TestFlight 전) | §5-6 절차 — Development 채우기 → V6 두 타입 없음 확인 → 배포 확인창을 모델 선언과 대조 → 배포. 배포한 타입 · 필드는 지울 수 없다 | 미수행 |
| G-4 | 실기기 부분 D9(iPad, 결정 17) | 두 번째 필사에 쓰고 곧바로 책장 → 첫 번째로 바꾸기 → 강제 종료 → 재실행: 획이 두 번째에만 있고 첫 번째는 그대로. 절 지우기 직후 바꾸기 · 이전 필사 고르기 직후 바꾸기도 같은지. 실기기 UI 시험은 절 메뉴 항목을 누르지 않는다 — 손으로 한다. 절차 · 기록 양식은 `docs/phase-0a-d-device-test.md` §6-9 · §8-7 | 미수행 |
| G-5 | TestFlight 동기화 | 배포 뒤 TestFlight 두 기기(iPad · 맥)에서 필사책 만들기 · 이름 · 필기가 넘어가는지 | 미수행 |
| G-6 | 문서 | 회귀 기준선 갱신(사람이 마지막 게이트 뒤), 이 문서 §9 의 M · C · G 결과 기록 | 미수행 |
