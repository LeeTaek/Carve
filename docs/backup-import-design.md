# 필사 백업 · 불러오기 설계 (2.1)

작성: 2026-10-02 · 갱신: 2026-10-06(구현 반영 · 영어 현지화 번역본 규칙 — §1-1 4 · §2-4 · §4-3 · §5-1 · §5-3) · 2026-10-12(번역본 항목 순서 · 진행 단위를 구현에 맞춤 — §2-4 · §3-1 · §3-2 · §3-4 · §4-1 · §4-3 · §5-3) · 목표: **2.1** · 상태: **구현됨 / 기기 · 시뮬레이터 확인(시험 계획 단계 D · NCANVAS-U1) 남음** — 무엇이 어디 있고 어느 자동 시험이 보는지는 §9

> 이 문서는 [iCloud 동기화·오프라인 사용·외부 백업 정책](./icloud-sync-and-backup-policy.md) §6 · §7 의 결정을 2.1 에서 구현하는 **계약**이다.
> 정책 문서는 결정만, 이 문서는 파일 형식 · 흐름 · 판정 규칙 · 시험을 담는다. 「결정 n」 은 2026-10-02 사용자 결정(인터뷰 기록)의 번호이고
> 이 문서에서 다시 정하지 않는다. 코드와 함께 바뀌는 문서다 — **2026-10-06 에 구현 이름 · 상한 · 오류 · 문구 · 시험 대응을 코드(레이어 0 ~ 4 병합 `6916aa73`)와
> 맞췄다(§9).** 구현하며 바뀐 결정 — 암호 표기(§2-1) · 메타데이터 없는 v3 지원 · 범위 밖 장 · 절(§5-1) · 색인 파일 상한 · 풀 파일 수 상한(§2-8) ·
> 대표 고정(§4-3 · §5-1) — 은 그 절에 날짜와 함께 적었다.
>
> 관련: [시험 계획 단계 D](./icloud-sync-compatibility-test-plan.md) · [단일 Canvas 설계](./single-canvas-design.md) · [데이터 호환성 결정](./data-compatibility-decision.md)

## 1. 목적과 범위

iCloud 는 기기 간 동기화라 잘못된 수정 · 삭제도 퍼진다(정책 §1-1). 필사 백업은 **이 기기에 남은 필사의 한 시점**을 앱 밖 파일로 떼어 두고,
같은 기기 · 새 기기 · 다른 Apple 계정에서 되살리는 기능이다. 불러오기는 지금 필사를 지우거나 덮지 않고 **더하기만** 한다(정책 §1-6 · §1-8).

| 구분 | 2.1 |
|---|---|
| 화면 | 설정 사이드바 「저장」 섹션의 「필사 백업」(`SidebarItem.backup` · `Path.backup` · 실행 경로 `settings/backup`). 한 화면에 「백업 만들기」(`BackupExportFeature`) · 「백업 불러오기」(`BackupImportFeature`) |
| 권한 | 만들기는 광고 제거 구매(`@SharedReader(.isAdFree)`)가 있을 때만 — 판정은 Feature 가 한다. 검사 · 미리보기 · 불러오기는 구매와 무관하게 무료(정책 §6-4) |
| 담는 것 | `BibleDrawing` 행 전부(현재 · 보관 · 비운 행 — 원본 그대로) + 지금 환경이 여는 묶음의 **저장소에 반영되지 않은 초안** |
| 담지 않는 것 | 즐겨찾기(`FavoriteVerse`) 스냅샷 · 설정 · 위젯 · 구매 상태 · 계정 식별자 · 계정 해시 · 기기 이름 · CloudKit 메타데이터 · `BiblePageDrawing` · 다른 계정 묶음의 초안 · 원시 사본(`raw/`) · 분리본(`separation/`) · 읽지 못한 초안 파일(`*.unreadable-*`) · 권 · 장 · 절을 알 수 없는 행(§7) |
| 쓰는 곳 | 불러온 필사는 `BibleDrawing` 행으로 들어간다. V6 버전 엔티티(`VerseDrawingVersion` · `DrawingEraseEpoch` · `knownEraseEpochs`)는 쓰지도 읽지도 않고, 스키마 · 마이그레이션 플랜 · CloudKit 설정은 바꾸지 않는다 |
| 범위 밖 | 전체 덮어쓰기 복원 · 선택 백업 · 장 전체 · PDF 내보내기 · Files 앱에서 파일을 눌러 여는 문서 타입 · 백업 전용 상품 |

### 1-1. 이 설계를 정한 네 결정

1. **V6 를 열지 않는다(결정 1).** 2.1 도 `BibleDrawing` 에 쓴다. 2.0.x 는 `VerseDrawingVersion` 을 읽지 않아 2.1 이 거기 쓰면 2.0.x iPad 에서 새 필기가
   보이지 않고, 쓰기 전환에는 정책 §12-6 ③ 전체와 Production 스키마 배포가 따라온다. 정책 §12-2 대로 버전 분리는 **충돌 보호용**이고 파일 백업에 필수가 아니다.
   대신 파일 형식은 V6 버전 모양(논리 ID · 부모 · 종류 · 내용 지문)을 미리 담고 부모(`parents`)는 비워 둔다 — 버전 저장을 열 때 형식을 바꾸지 않고 계보를 채운다.
   2.1 은 N-Canvas 만 지운다(정책 §12-5 표 아래 2026-10-02 줄).
2. **초안을 담는다(결정 2).** iCloud 에 로그인하지 않은 기기의 2.0 필기는 저장소가 아니라 초안(`Preservation/<저장소>/drafts/acct-local/`)에만 있다 —
   로그인하지 않고 시작한 실행은 연결이 보류되고(`SyncedWriteBlock.connectionHeld`) 저장소 소유 근거도 없어 캔버스가 저장소에 쓰지 않는다
   (`ChapterCanvasDraftFeature.persistsToStore` 가 false). 저장소만 담으면 그 사용자의 2.0 필기가 통째로 빠진다.
   경계는 「확인이 필요한 필기」 와 같다 — 다른 계정의 필기를 지금 계정의 파일에 담지 않는다(P0-1).
3. **적용은 연결 뒤(결정 3).** 검사 · 미리보기는 언제나 되지만, 저장소에 쓰는 적용은 `SyncedWriteBlock.check(환경) == nil` 이고 저장소 소유가 검사 때 정한 계정과 같을
   때만이다. 2.0.0 은 소유 근거 없이 저장소에 쓰지 않고(F30), 미로그인 저장소에 행을 넣으면 첫 연결의 소유 증명(`StoreOwnershipClaimRule.emptyUnaccountedStore`
   의 행 0 · V3 원시 사본 일치)이 깨져 연결이 계속 보류될 수 있다. 불러온 필기는 **지금 연결된 계정의 것**이 되고, 파일을 만든 계정은 보지 않는다(§6).
4. **절 식별은 번역본 저장값 + USFM 권 코드(결정 9).** 번역본은 행 · 초안에 저장된 값 그대로(없으면 null — 미상을 NKRV 로 채우지 않는다, 정책 §8),
   권은 USFM 코드, 원본 파일 이름(`titleName`)도 함께 둔다. 불러오기는 아는 번역본과 null 만 넣고 모르는 번역본은 건너뛴다 — 나중에 다른
   번역본 필사가 든 파일을 한국어 절에 섞지 않는다. 권 코드 · 번역본 규칙은 영어 성경 작업(별도 브랜치)에 인터페이스로 넘긴다.
   **2026-10-06 영어 현지화([영어 현지화 설계](./english-localization-design.md) §3):** 아는 번역본은 NKRV · **KJV · BSB** 다. 영어 행은 SwiftData `translation` 열이
   늘 nil 이고 번역본을 `titleName` 접두(`KJV-1-01Genesis.txt`)로 지니므로, **영어 행의 백업 키 번역본은 열이 아니라 `titleName` 접두에서 온다**(`StoredBookKey.decode`).
   개역개정 행은 지금처럼 열 값 그대로(nil 은 null)이고 **nil · NKRV 한 묶음 규칙은 그대로다**(§5-1). 파일 형식(`formatVersion` 1)은 바꾸지 않는다.

### 1-2. 구현 위치

파일마다의 타입과 그것을 보는 자동 시험은 §9-1 이다.

| 모듈 | 위치 | 맡는 것 |
|---|---|---|
| Domain | `Domain/Domain/Sources/Backup/Format/` | 형식 — `BackupFormat`(상수 · JSON 인코더 · `UTType.carveBackup`) · `BackupManifest`(`BackupScope` · `BackupCounts` · `BackupBlobEntry`) · `BackupItem`(`BackupItemKind` · `BackupVerseKey` · `BackupItemSource`) · `BackupItemID` · `BibleBookCode` · `BackupLimits` · `BackupFormatError` · `BackupPayload` · `BackupPayloadValidator` · `BackupItemSupport`(`BackupUnsupportedReason`) · `BackupRowRecord`(`BackupRowLoad`) · `CanvasFlushOutcome` |
| Domain | `Sources/Backup/Archive/` | 컨테이너 — `BackupArchive`(`write` · `read`) · `BackupArchiveEntry`(허용 이름) · `BackupArchiveError` · `BackupArchivePassword`(암호 표기) · `BackupArchiveFileSink` · `BackupDiskSpace` · `BackupWorkDirectory` |
| Domain | `Sources/Backup/Export/` | 내보내기 — `BackupExporting`(`BackupExportResult` · `BackupExportError` · `BackupProgress` · `BackupExportFileName` · `\.backupExporter`) · `LiveBackupExporter` · `BackupExportItems` · `BackupExportDraftSelection` · `BackupExportStaging` · `BackupExportVerification` |
| Domain | `Sources/Backup/Import/` | 판정 — `BackupImportPlanner`(순수) · `BackupChapterPlan` · `BackupImportDecision` · `BackupRowInsertion` · `BackupRepresentativePin` · `BackupImportPreview`. 불러오기 — `BackupImporting`(`BackupInspection` · `BackupImportReport` · `BackupImportTally` · `BackupImportJob` · `BackupImportError` · `\.backupImporter`) · `LiveBackupImporter`(검사 · 이어 하기, 적용은 `LiveBackupImporter+Apply.swift`) · `BackupImportJobStore`. 복원 계약 — `DrawingBackupRestoring`(`BackupChapterRestoreCommand` · `BackupChapterRestoreOutcome` · `BackupChapterRestoreError` · `\.drawingBackupRestorer`) |
| Domain (SwiftData) | `Sources/SwiftData/SwiftDatabaseActor+Backup.swift` · `SwiftDataDrawingRepository+BackupRestore.swift` | 백업 전용 조회(`backupChapters()` · `backupRows(chapter:)` · 내보내기용 `backupChapterList()` · 유일한 변환 `BibleDrawing.backupRecord`)와 장 단위 복원 쓰기(`SwiftDataDrawingBackupRestorer(actor:)` → `SwiftDatabaseActor.restoreBackupChapter`). SwiftData API 는 이 폴더 밖에 두지 않는다 |
| CarveFeature | `ChapterCanvasBackupFlushFeature.swift` · `VerseDrawingHistoryDedup.swift` | flush 완료 신호(`ChapterCanvasFeature.Action.backupFlushRequested(id:)` → `Delegate.backupFlushFinished(id:outcome:)` — §5-2). 이전 필사 기록에서 같은 내용 행을 하나로 보이기(§7) |
| SettingsFeature | `Sources/Details/Backup/` | `BackupFeature` · `BackupExportFeature` · `BackupImportFeature`(effect 는 `BackupImportFeature+Work.swift`)와 뷰 · 문구(`BackupCopy` — 불러오기 문구는 `BackupImportFeature.swift` 의 `BackupCopy` 확장), 고른 파일의 보안 범위 접근 경계(`BackupFileAccessClient` · `\.backupFileAccess`). 설정의 연결은 `SettingsFeature.SidebarItem.backup` · `Path.backup` · `Action.canvasFlushFinished(id:outcome:)` |
| App | `AppCoordinatorFeature` · `App.swift` · 앱 Info.plist · 개인정보 매니페스트 | flush 중계(`relayBackupFlushRequest`), 실제 구현 주입(`\.backupExporter` · `\.backupImporter` · `\.drawingBackupRestorer` — `drawingVerseImporter` 선례, 「모든 필사 삭제」 와 같은 `SwiftDatabaseActor`), 시작 때 `BackupWorkDirectory.removeStale()`, 내보내는 형식 선언(`Plugins/ProjectDescriptionHelpers/InfoPlist.swift` 의 `UTExportedTypeDeclarations`), `PrivacyInfo.xcprivacy` 의 DiskSpace `E174.1` |

## 2. 파일 형식

### 2-1. 컨테이너

| 항목 | 값 |
|---|---|
| 확장자 | `.carvebackup` (`BackupFormat.fileExtension`) |
| 형식 식별자 | `kr.co.carve.leetaek.backup`(`BackupFormat.typeIdentifier`) — `public.data` · `public.content` 준수. Domain `UTType.carveBackup` = `UTType(exportedAs:conformingTo: .data)`, 앱 Info.plist 의 내보내는 형식 선언(`UTExportedTypeDeclarations` — 설명 「새기다 필사 백업」, `Plugins/ProjectDescriptionHelpers/InfoPlist.swift`)과 짝이다. 준수 목록의 원본은 그 선언이다 |
| 바깥 | **Apple Encrypted Archive** — `ArchiveEncryptionContext(profile: .hkdf_sha256_aesctr_hmac__scrypt__none, compressionAlgorithm: .lzfse)` + `setPassword(_:)`(AppleArchive, iOS 15+ — 최소 배포 17 에서 쓸 수 있다). 암호 기반 키 유도(scrypt · 파일마다 무작위 salt) · 암호화 · 세그먼트 무결성 · 압축 · 스트리밍을 SDK 가 한다 |
| 안 | Apple Archive. 항목은 `manifest.json` · `items.json` · `blobs`(폴더) · `blobs/<소문자 SHA-256 hex 64자>` 뿐이다(`BackupArchiveEntry`). 쓰는 순서는 manifest → items → `blobs` → blob 이름순이고, 헤더 필드는 TYP · PAT · DAT 만 쓴다 |
| 암호 | 늘 필요하다. 8자 이상(글자 수), 화면에서 두 번 입력해 맞아야 한다 |
| `setPassword` 에 넘기는 값 | 암호 원문이 아니라 **`hex(SHA-256("carve.backupPassword/1\|" + NFC(암호)))` 소문자 64자**다(`BackupArchivePassword.encoded` — 2026-10-02 사용자 결정, **파일 형식의 일부**라 바꾸면 이미 만든 백업을 열 수 없다). AEA 의 scrypt 모드는 UTF-8 **20 ~ 256바이트** 암호만 받아(밖이면 `setPassword` 가 `invalidValue`) 8 ~ 19바이트 암호를 그대로 쓸 수 없기 때문이다. NFC 정규화로 한글 암호는 입력 경로(조합형 · 완성형)와 상관없이 같은 파일을 연다. 호출부는 암호 원문을 `BackupArchive` 에 넘기기만 하고, 이 값은 저장 · 기록하지 않는다 |

- 암호 알고리즘 · 키 유도 · 컨테이너 형식을 직접 만들지 않는다(정책 §6-5) — 위 표기는 길이를 맞추는 고정 변환일 뿐이고 키 유도는 SDK 의 scrypt 다.
  같은 파일은 macOS 명령으로도 풀 수 있어 지원 · 진단에 쓴다(암호는 사용자가 넣는다 — 쉘의 `printf` 는 받은 바이트 그대로 해시하므로 한글 암호는 NFC 로 입력한다):
  `aea decrypt -i <파일> -o x.aar -password-value "$(printf '%s' 'carve.backupPassword/1|<암호>' | shasum -a 256 | cut -c1-64)"` → `aa extract -i x.aar -d <폴더>`.
- 쓰기 · 풀기 모두 동기 · 1 MiB 조각 스트리밍이다(부르는 쪽이 백그라운드 작업에서 부른다). 작업이 취소되면 조각 사이에서 `CancellationError` 로 멈추고 만들던 것을 지운다.
  쓰기는 같은 폴더의 임시 이름(`.<이름>.<UUID>.partial`)에 다 쓴 뒤 rename 으로 바꾸고, 쓰기 · 풀기 전에 남은 공간을 본다(`BackupDiskSpace` — §4-1 2단계).
- 읽을 때 허용 밖 이름(위 넷 밖 · 대문자 hex · 길이가 다른 이름), 링크 · 장치 파일 등 일반 파일이 아닌 항목, 종류가 맞지 않는 항목(파일 이름이 폴더로 · 폴더 이름이 파일로),
  같은 이름 두 번, DAT 밖의 바이트 필드(확장 속성 · ACL)가 붙은 항목은 바이트를 쓰기 전에 거부한다(`BackupArchiveError.entryRejected(name:)`). 경로 이탈(`..` · 절대 경로 ·
  겹친 `/`)처럼 정규형이 아닌 경로는 SDK 해독기가 헤더에서 먼저 거부해 `wrongPasswordOrDamaged` 로 올 수도 있다 — 어느 쪽이든 「파일 거부」 로 같게 다루고,
  풀던 폴더(`Unpacked-<UUID>`)를 지워 **저장소를 바꾸기 전에** 끝난다. 다른 프로필(키 · 서명)로 만든 파일도 받지 않는다(`wrongPasswordOrDamaged`).
- 잘못된 암호 · 변조 · 잘림은 컨테이너에서 하나의 오류(`BackupArchiveError.wrongPasswordOrDamaged`)로 묶고, 불러오기는 허용 밖 항목 · 형식 검증 실패까지 같은
  `BackupImportError.wrongPasswordOrDamaged` 로 알린다 — 「암호가 맞지 않거나 파일이 손상됐어요. 암호를 확인해 다시 입력해 주세요.」(§4-2).
- iOS 17 의 AppleArchive Swift 래퍼는 실패한 `close()` 뒤 해제 때 같은 스트림을 다시 닫아 프로세스가 죽는다(iPadOS 17.5 시뮬레이터 SIGBUS, 26.2 는 괜찮다).
  그래서 쓰기는 자체 싱크(`BackupArchiveFileSink`)가 파일 쓰기 실패를 AppleArchive 에 돌려주지 않고 첫 errno 만 남겼다가 스트림을 다 닫은 뒤 던지고,
  읽기 스트림은 명시적으로 닫지 않고 해제에 맡긴다. 무결성 검사는 읽는 도중에 끝난다 — 잘림 · 변조는 헤더 · 바이트를 읽다가 드러난다.

### 2-2. 인코딩 공통

- 인코더 · 디코더는 `BackupFormat.encoder` · `BackupFormat.decoder` 하나씩이다(부를 때마다 새로 만든다 — 작업 기록 `job.json` 도 같은 것으로 쓴다).
- `JSONEncoder.outputFormatting = [.sortedKeys]` — 같은 내용이면 같은 바이트다. 파일 안 JSON 은 줄바꿈 없는 한 줄이다(아래 예시는 읽기 쉽게 펼쳤다).
- 날짜는 `dateEncodingStrategy = .deferredToDate` — 2001-01-01T00:00:00Z 기준 초(Double)다. `Date` 를 손실 없이 왕복한다(ISO 8601 문자열은 소수 초를 잃는다).
- Optional 은 nil 이면 키가 빠진다(JSONEncoder 기본). 읽을 때는 키 없음과 `null` 을 같게 nil 로 읽는다 — 이 문서의 「null」 은 둘을 함께 말한다.
- 바이트(잉크 · 메타데이터)는 JSON 에 넣지 않고 blob 이름으로 가리킨다(§2-7).
- 읽을 때 모르는 키는 무시한다 — 뒤 버전이 키를 더해도 읽힌다. 단 `formatVersion` 이 1 이 아니면 `unsupportedFormat` 으로 **파일 전체**를 거부한다.
  `manifest.json` 을 `items.json` 보다 먼저 읽고, manifest 안에서도 `formatVersion` 을 가장 먼저 읽는다 — 다른 버전은 나머지 모양이 달라도 디코딩 실패(`malformed`)가
  아니라 `unsupportedFormat(formatVersion:)` 으로 보인다.

### 2-3. manifest.json — `BackupManifest`

| 키 | 타입 | 뜻 |
|---|---|---|
| `formatVersion` | Int | 백업 형식 버전 `BackupFormat.formatVersion` = 1. 앱 버전 · 스키마 버전과 별개다(정책 §6-3) |
| `backupID` | String | 이 백업의 UUID |
| `createdAt` | Date | 만든 시각(내보내기를 시작한 시각) |
| `appVersion` | String | 만든 앱 버전(예: `2.1.0` — `@Dependency(\.appVersion)`) |
| `scope` | `BackupScope` | `rows` · `drafts` — 행 · 초안을 담았는가. 2.1 은 전체 백업만 만들어 둘 다 true 다. 선택 백업의 자리(정책 §9-2) |
| `counts` | `BackupCounts` | `rows` · `drafts` · `blobs` 의 수 — 읽을 때 실제 수와 맞아야 한다 |
| `blobs` | [`BackupBlobEntry`] | blob 마다 `name`(64자 hex) · `size`(바이트) · `sha256`(64자 hex), 이름순. 읽을 때 실제 크기 · 해시가 맞아야 한다 |

**넣지 않는 것:** 계정 식별자 · 계정 해시(`AccountScope`) · 기기 이름 · 설정 · 즐겨찾기 · 위젯 · 구매 상태 · CloudKit 메타데이터. manifest 뿐 아니라 **파일 어디에도** 없다.
작업 기록에 쓰는 대상 계정 범위(§6-2)도 파일에는 넣지 않는다.

### 2-4. items.json — [`BackupItem`]

| 키 | 타입 | 행 항목(`kind = "row"`) | 초안 항목(`kind = "draft"`) |
|---|---|---|---|
| `id` | String | `BackupItemID.make` 의 `row-<hex>`(§2-5) | `draft-<hex>` |
| `kind` | `BackupItemKind` | `"row"` | `"draft"` |
| `parents` | [String] | formatVersion 1 은 늘 `[]` — V6 계보의 자리 | 같음 |
| `verse` | `BackupVerseKey` | 행의 번역본 · 권 · 장 · 절 | 초안 키(`VerseDraftKey`)의 번역본 · 권 · 장 · 절 |
| `drawingVersion` | Int? | 원본 그대로 nil · 1 · 2 · 3 — **승격 · 강등하지 않는다** | 초안의 값 |
| `inkBlob` | String? | `lineData` 원본 바이트의 blob. 비운 행이면 null | 초안의 `lineData` |
| `metadataBlob` | String? | `layoutMetadataData` 원본 바이트의 blob. 비운 행에도 남아 있으면 담는다 | 초안의 `layoutMetadataData` |
| `fingerprint` | String? | 잉크가 있을 때만 `VerseContentFingerprint.make(lineData:drawingVersion:layoutMetadataBlob:)` — **원본 바이트로**. 비운 행은 null | 같음 |
| `isCurrent` | Bool | 그 절의 `DrawingRepresentativeRule` 대표 행만 true — **대표가 비운 행(`lineData` nil)이어도 true**(지운 상태도 원본이다). 그 절에 화면에 겹치던 초안(shown)이 있으면 그 절의 행은 모두 false | 분류가 shown 이면 true, 그 밖은 false(§3-4) |
| `createdAt` | Date? | `creationDate` 원본 | null — 초안은 만든 시각을 따로 두지 않는다 |
| `updatedAt` | Date? | `updateDate` 원본 | 초안을 남긴 시각(`savedAt`) |
| `source` | `BackupItemSource` | 아래 | 아래 |

`BackupVerseKey`

| 키 | 뜻 |
|---|---|
| `translation` | String? — 행 · 초안에 저장된 값 그대로(`Translation.rawValue` — `NKRV` · `KJV` · `BSB`). 행에 값이 없으면 null — NKRV 로 채우지 않는다. **영어 행은 열이 nil 이므로 `titleName` 접두에서 온 값(`"KJV"` · `"BSB"`)을 쓴다**(2026-10-06 — `StoredBookKey.decode`). 접두가 없는 행만 열 값을 본다. 초안은 `VerseDraftKey.translation`(기기 안 파일이라 영어도 실제 값) |
| `book` | USFM 권 코드 `GEN` … `REV` — Domain `BibleBookCode` 가 `BibleTitle` 66권과 1:1 양방향(§2-6). 영어 행은 `titleName` 을 `StoredBookKey.decode` 로 푼 권이다 — 번역본마다 같은 코드다 |
| `chapter` · `verse` | Int |

`BackupItemSource`

| 키 | 뜻 |
|---|---|
| `titleName` | 행의 `titleName` 원문 — 개역개정 `1-01Genesis.txt`, 영어 `KJV-1-01Genesis.txt`(2026-10-06). 권 코드와 함께 원본을 보존한다. 불러오기는 이 값이 아니라 `book` · `translation` 으로 권 이름을 다시 짓는다(§4-3) |
| `rowKey` | 행: `rowUUID ?? business id`. 초안: 식별 · 판정에 쓰지 않는다(null 이어도 된다) |
| `draftScope` | 초안만. `"local"`(로그인하지 않은 동안 · `acct-local`) · `"unverified"`(계정을 확인하지 못한 동안 · `acct-unverified`) · `"account"`(확인된 계정 묶음) 중 하나. **계정 해시는 넣지 않는다** |
| `draftRevision` | 초안만. 그 세션 · 절의 revision |

- `isCurrent` 의 「그 절」 은 번역 저장값(null 은 NKRV 와 한 묶음, KJV · BSB 는 각자 — 영어 행은 `titleName` 접두의 번역본) + 절이다 — 불러오기 판정 단위(§5-1)와 같다(`BackupExportVerseSlot`).
- 항목 순서 — **권 → 장 → 번역본**(NKRV → KJV → BSB, `Translation.allCases` 순서 — `BibleChapter.backupOrder`)이고, 번역본 장마다 행(절 → 행 키) 다음 초안(절 → 묶음 → 세션 → revision)이다.
  같은 권 · 장의 번역본들은 연달아 온다(2026-10-12 구현에 맞춤 — 그 전 문서는 「장(권 → 장)마다」 만 적었다). 행 키와 내용이 같은 행이 둘이면(같은 id) 하나만 담는다(§3-3).

### 2-5. 항목 식별자 — `BackupItemID`

```
정규 문자열 = ["carve.backupItem/1", kind, sourceKey, fingerprint ?? "empty"]
              구성요소마다 "<UTF-8 바이트 길이>:<값>" 으로 바꿔 "|" 로 잇는다
id          = ("row-" | "draft-") + SHA-256(정규 문자열) 소문자 hex 64자
```

- `sourceKey` — 행: `rowKey`(`rowUUID ?? business id`). 초안: `"<draftScope>|<sessionID>|<translation>|<title>|<chapter>|<verse>|<revision>"`(`BackupItemID.draftSourceKey`).
- 구현: `BackupItemID.make(kind:sourceKey:fingerprint:)` · 이름공간 `BackupItemID.namespace` · 지문 자리 `BackupItemID.emptyFingerprint`(`"empty"`).
- `LegacyVersionID` 와 같은 방식이고(길이 접두로 경계를 고정 · 종류와 내용 지문을 넣는다) 이름공간(`carve.backupItem/1`)만 다르다 — 같은 행이 다른 내용이 되면
  다른 id 다(정책 §12-5 C5).
- 예: `18:carve.backupItem/1|3:row|36:5C0E5D0B-2F7A-4C55-9D51-0E1B9C2E7A10|68:vc1-<64자 hex>` 의 SHA-256 → `row-…`.
- id 는 **파일 안 항목의 이름**이다. 불러오기의 중복 판정은 id 가 아니라 내용 지문으로 한다(§5-1) — 다른 기기 · 다른 백업은 같은 필기를 다른 id 로 담는다.

### 2-6. 권 코드 (USFM) — `BibleBookCode`

`BibleTitle` 파일 이름의 번호 순서 그대로 1:1 이다.

| `BibleTitle` | 코드 |
|---|---|
| 1-01 ~ 1-10 | GEN · EXO · LEV · NUM · DEU · JOS · JDG · RUT · 1SA · 2SA |
| 1-11 ~ 1-20 | 1KI · 2KI · 1CH · 2CH · EZR · NEH · EST · JOB · PSA · PRO |
| 1-21 ~ 1-30 | ECC · SNG · ISA · JER · LAM · EZK · DAN · HOS · JOL · AMO |
| 1-31 ~ 1-39 | OBA · JON · MIC · NAM · HAB · ZEP · HAG · ZEC · MAL |
| 2-01 ~ 2-10 | MAT · MRK · LUK · JHN · ACT · ROM · 1CO · 2CO · GAL · EPH |
| 2-11 ~ 2-20 | PHP · COL · 1TH · 2TH · 1TI · 2TI · TIT · PHM · HEB · JAS |
| 2-21 ~ 2-27 | 1PE · 2PE · 1JN · 2JN · 3JN · JUD · REV |

### 2-7. blob

- 이름 = 그 바이트의 SHA-256 소문자 hex 64자, 아카이브 경로는 `blobs/<이름>`. manifest `blobs` 의 `name` · `sha256` 은 같은 값이고, 읽을 때 실제 바이트의
  크기 · 해시가 둘 다 맞아야 한다.
- 같은 바이트는 **한 번만** 쓴다 — 예: 지운 절의 비운 행과 보관 행은 같은 메타데이터를 든다(§2-9 의 2절).
- 항목이 가리키는 blob 은 manifest 에 있고 파일도 있어야 한다. 없는 blob 을 가리키는 항목 · 어느 항목도 가리키지 않는 blob 은 손상으로 본다.
- 내보내기는 blob 을 내용 이름으로 준비 폴더에 한 번씩 쓴다(`BackupBlobEntry(bytes:)` · `BackupExportStaging`). 읽을 때의 검사 전체와 순서는 §4-2.

### 2-8. 상한 — `BackupLimits`

| 상한 | `BackupLimits` | 값 | 넘으면(`BackupFormatError`) |
|---|---|---|---|
| blob 하나 | `maxBlobBytes` | 64 MB | `limitExceeded(.blobBytes)` |
| `manifest.json` · `items.json` 각각 | `maxIndexBytes` | 128 MB | `limitExceeded(.indexBytes)` — 디코딩 전에 |
| 풀린 합계 | `maxTotalBytes` | 4 GB | `limitExceeded(.totalBytes)` |
| 항목 수 | `maxItems` | 200,000 | `limitExceeded(.items)` |

- 넘으면 **저장소를 바꾸기 전에** 거부한다 — 불러오기는 모두 `BackupImportError.tooLarge`(「백업 파일이 너무 커서 불러올 수 없어요.」)로 알린다.
- 풀기(`BackupArchive.read(from:password:into:maxEntryBytes:maxTotalBytes:maxEntryCount:)`)는 `BackupLimits` 를 모르고 원시 값만 받는다 — 부르는 쪽이
  `maxEntryBytes` 에 `BackupLimits.archiveEntryLimit`(= blob 과 색인 파일 상한 중 큰 값, 128 MB), `maxTotalBytes` 에 4 GB, `maxEntryCount` 에
  `2 × maxItems + 2`(항목마다 blob 최대 둘 + manifest · items — 400,002)를 넘긴다. 컨테이너는 이름으로 종류를 가리지 않으므로 종류별 상한(blob 64 MB ·
  색인 128 MB · 항목 수)은 검증기(`BackupPayloadValidator`)가 따로 본다. 푸는 도중 넘으면 그 자리에서 멈추고(`BackupArchiveError.tooLarge`) 풀던 폴더를 지운다.
- **구현 중 더한 것(2026-10-02):** 색인 파일 상한(`maxIndexBytes`) — 항목 200,000 이면 `items.json` 이 blob 상한(64 MB)을 넘을 수 있어, blob 상한을 그대로
  풀기에 쓰면 정상 파일의 큰 `items.json` 을 풀지 못한다. 풀 파일 수 상한(`maxEntryCount`, 인자를 빼면 `.max`) — 정상 파일의 파일 수는 `2 × maxItems + 2` 를
  넘지 않으므로, 작은 blob 을 그보다 많이 든 파일은 디코딩 · 검증까지 가지 않고 푸는 도중에 멈춘다.
- 크기는 파일 크기를 묻는 API 가 아니라 읽은 바이트 수로 본다 — 상한 + 1 바이트까지만 읽는다(`BackupPayloadValidator`).
- 내보내기의 재검증(§3-1 6단계)도 같은 상한으로 푼다 — 불러올 수 없는 파일을 성공으로 내놓지 않는다.
- 초기값은 실측으로 조정한다(정책 §9-2 「대용량 파일」). **2026-10-06 구현 값은 초기값 그대로다(큰 파일 실측 전 — §9-2).** 참고 규모: 실사용 계정 271행 ·
  잉크 평균 15.3 KB · 최대 111 KB(정책 §3-2).

### 2-9. 예시

한 파일에 여러 경우를 모았다. 해시 · 식별자는 앞 몇 자만 적었다(실제는 64자 hex). 시각은 2001-01-01 기준 초다.

`manifest.json`

```json
{
  "appVersion" : "2.1.0",
  "backupID" : "8E5D2C1A-4B7F-4F0E-9C3D-6A1B2E3F4D5C",
  "blobs" : [
    { "name" : "0c7a…", "sha256" : "0c7a…", "size" : 15342 },
    { "name" : "3b1e…", "sha256" : "3b1e…", "size" : 412 },
    { "name" : "5f90…", "sha256" : "5f90…", "size" : 9876 },
    { "name" : "6a02…", "sha256" : "6a02…", "size" : 405 },
    { "name" : "8d24…", "sha256" : "8d24…", "size" : 7310 },
    { "name" : "c4e6…", "sha256" : "c4e6…", "size" : 4120 },
    { "name" : "e1a3…", "sha256" : "e1a3…", "size" : 398 }
  ],
  "counts" : { "blobs" : 7, "drafts" : 1, "rows" : 4 },
  "createdAt" : 812613600,
  "formatVersion" : 1,
  "scope" : { "drafts" : true, "rows" : true }
}
```

`items.json`

```json
[
  {
    "createdAt" : 811600400.5,
    "drawingVersion" : 3,
    "fingerprint" : "vc1-91d0…",
    "id" : "row-f767…",
    "inkBlob" : "0c7a…",
    "isCurrent" : true,
    "kind" : "row",
    "metadataBlob" : "3b1e…",
    "parents" : [ ],
    "source" : { "rowKey" : "5C0E5D0B-2F7A-4C55-9D51-0E1B9C2E7A10", "titleName" : "1-01Genesis.txt" },
    "updatedAt" : 811600496.789,
    "verse" : { "book" : "GEN", "chapter" : 1, "translation" : "NKRV", "verse" : 1 }
  },
  {
    "createdAt" : 812023100,
    "drawingVersion" : 3,
    "id" : "row-2a9b…",
    "isCurrent" : true,
    "kind" : "row",
    "metadataBlob" : "6a02…",
    "parents" : [ ],
    "source" : { "rowKey" : "A1F3C6E2-0B4D-4E8A-9F17-3C2D5B6A7E80", "titleName" : "1-01Genesis.txt" },
    "updatedAt" : 812460000.25,
    "verse" : { "book" : "GEN", "chapter" : 1, "translation" : "NKRV", "verse" : 2 }
  },
  {
    "createdAt" : 812460000.25,
    "drawingVersion" : 3,
    "fingerprint" : "vc1-47bc…",
    "id" : "row-7e15…",
    "inkBlob" : "5f90…",
    "isCurrent" : false,
    "kind" : "row",
    "metadataBlob" : "6a02…",
    "parents" : [ ],
    "source" : { "rowKey" : "D04B9A31-6C2E-4F5D-8B07-1E9A2C3D4F56", "titleName" : "1-01Genesis.txt" },
    "updatedAt" : 812023200,
    "verse" : { "book" : "GEN", "chapter" : 1, "translation" : "NKRV", "verse" : 2 }
  },
  {
    "createdAt" : 795142923.5,
    "drawingVersion" : 2,
    "fingerprint" : "vc1-d3e8…",
    "id" : "row-b0c4…",
    "inkBlob" : "8d24…",
    "isCurrent" : true,
    "kind" : "row",
    "parents" : [ ],
    "source" : { "rowKey" : "1-01Genesis.txt.1.3.1773450123", "titleName" : "1-01Genesis.txt" },
    "updatedAt" : 795142923.5,
    "verse" : { "book" : "GEN", "chapter" : 1, "translation" : "NKRV", "verse" : 3 }
  },
  {
    "drawingVersion" : 3,
    "fingerprint" : "vc1-5a6f…",
    "id" : "draft-c8d1…",
    "inkBlob" : "c4e6…",
    "isCurrent" : true,
    "kind" : "draft",
    "metadataBlob" : "e1a3…",
    "parents" : [ ],
    "source" : { "draftRevision" : 7, "draftScope" : "local", "titleName" : "1-01Genesis.txt" },
    "updatedAt" : 812600000,
    "verse" : { "book" : "GEN", "chapter" : 1, "translation" : "NKRV", "verse" : 4 }
  }
]
```

- 1절 — 대표 행(v3 · 메타데이터).
- 2절 — **「비운 현재 + 잉크 보관」**. 「지우기」(`archiveAndResetVerseDrawing`)는 대표 행의 잉크를 새 보관 행으로 옮기고 대표 행을 비운다 — 대표 행은 `lineData`
  만 nil 이 되고 좌표 형식 · 메타데이터는 남는다. 비운 대표 행은 잉크 · 지문 없이 `isCurrent = true`, 보관 행은 지운 잉크를 들고 `isCurrent = false` 다.
  두 행의 메타데이터는 같은 바이트라 blob `6a02…` 하나를 함께 가리킨다. 판정은 §5-1 의 예.
- 3절 — 1.3.0 이 만든 v2 행. `rowUUID` 가 없어 business id(`<titleName>.<장>.<절>.<초>`)가 행 키다. 메타데이터가 없다.
- 4절 — 로그인하지 않은 기기의 초안(`acct-local`)으로 화면에 겹치던 것(shown). 만든 시각이 없고 `updatedAt` 은 초안을 남긴 시각이다.

## 3. 내보내기 흐름 — 「백업 만들기」

### 3-1. 단계

| # | 단계 | 실패 · 취소 |
|---|---|---|
| 1 | **권한** — `BackupExportFeature` 가 `@SharedReader(.isAdFree)` 를 「만들기」 를 누를 때와 flush 를 요청할 때 다시 읽는다. 사지 않았으면 만들기 대신 「광고 제거를 구매하면 백업을 만들 수 있어요.」 + 「광고 제거 보기」(`Delegate.removeAdsRequested` → 설정이 광고 제거 화면을 연다). 불러오기는 그대로 열린다 | 암호를 받는 사이 구매가 풀리면 시작하지 않고 흐름을 닫는다 |
| 2 | **안내** — 「이 기기에 저장된 필사를 백업해요. 아직 동기화되지 않은 다른 기기의 필사는 포함되지 않을 수 있어요. 즐겨찾기 · 설정 · 위젯은 담지 않아요.」 · 「암호를 잊으면 Carve 도 이 파일을 열 수 없어요.」(`BackupCopy.exportScope` · `passwordWarning`) | — |
| 3 | **암호** — 「암호(8자 이상)」 · 「암호 확인」 두 칸, 8자 이상(글자 수 — 한글 8자도 된다), 둘이 같아야 한다. 시스템 암호 자동 완성은 막지 않는다(`textContentType(.newPassword)`). Carve 는 암호를 저장 · 기록하지 않고, 파일을 다 만들거나 흐름을 닫으면 상태에서도 지운다 | 그 자리에서 「암호는 8자 이상이어야 해요.」 · 「두 암호가 같지 않아요.」 |
| 4 | **flush** — 필사 화면의 마지막 편집이 이 기기에 내구성 있게 남았는지 확인한다(§5-2). 기다리는 동안 「마지막 필기를 저장하는 중이에요」 | `.durable` 이 아니면(`.failed` · `.timedOut` — 설정 쪽 시한 10초 포함) 시작하지 않는다 — 「필사 화면에 아직 저장하지 못한 필기가 있어요. 필사 화면에서 저장을 다시 시도한 뒤 백업해 주세요.」 + [다시 시도](새 id) |
| 5 | **장 단위 읽기 · 쓰기** — §3-2(`backupExporter.export(password:fileName:progress:)`). 진행은 「필사를 모으는 중이에요 · n/N장」(N 은 권 · 장 자리 수 — 한 장에 번역본이 여럿이어도 한 장으로 센다, §3-2) → 「암호를 걸어 파일을 쓰고, 다시 열어 확인하는 중이에요」. 평문은 작업 폴더(`BackupWorkDirectory` — `FileManager.temporaryDirectory/BackupWork/<UUID>/`)의 준비 폴더 `staged/` 에만 두고, 다 모으면 `BackupArchive.write(stagedDirectory:to:password:)` 로 같은 작업 폴더에 암호화 파일 하나를 만든 뒤 `staged/` 를 곧바로 지운다 | `BackupExportError` — `generationChanged` · `accountChanged` · `storeUnreadable` · `draftsUnreadable` · `insufficientSpace` · `writeFailed`(이 실행에 내보내기가 주입되지 않았으면 Feature 의 `unavailable`). 사유마다 문구(`BackupCopy.exportFailed`)와 [다시 시도] — flush 부터 새 id 로 한다 |
| 6 | **검증** — 다 쓴 파일을 같은 암호 · 같은 상한으로 작업 폴더의 `verify/` 에 다시 풀어 `BackupPayload.load`(counts · blob 크기 · SHA-256 · 항목이 가리키는 blob · blob 으로 다시 계산한 내용 지문)를 거친 뒤, 풀린 manifest · 항목이 쓴 것과 **같은지** 견준다(`BackupExportVerification`). 맞을 때만 성공이고 풀린 평문은 곧바로 지운다(정책 §6-1 3) | `verificationFailed` — 파일을 내놓지 않는다(「만든 파일을 다시 열어 확인했더니 내용이 맞지 않아 내놓지 않았어요. …」) |
| 7 | **저장 위치** — SwiftUI `fileExporter(isPresented:item:contentTypes: [.carveBackup] …)` 로 사용자가 고른다. 넘기는 것은 `BackupFileItem`(`Transferable` — `FileRepresentation(exportedContentType: .carveBackup)` 로 작업 폴더의 파일을 그대로 보낸다). 기본 이름 「새기다 필사 백업 YYYY-MM-DD.carvebackup」(`BackupExportFileName.defaultName(for:timeZone:)` — 날짜는 `@Dependency(\.date)` · `@Dependency(\.timeZone)`) | 사용자 취소 |
| 8 | **결과** — 저장 · 취소 · 실패를 따로 보인다. 저장: 「백업 파일을 저장했어요. 필사 기록 N개 · 남겨 둔 필기 M개를 담았어요.」 + 저장된 파일 이름 + 「iCloud Drive 같은 곳에 저장했다면, 그곳으로 올리는 일은 그 앱이 이어서 마쳐요.」(앱의 저장 성공과 그 제공자의 업로드 완료는 별개다 — 정책 §6-1). 수는 `BackupExportResult`(`fileURL` · `counts` · `backupID`)의 것이다 | 취소 「저장하지 않았어요. 만든 파일은 이 iPad에서 지웠어요.」 · 실패 「고른 곳에 저장하지 못했어요. …」 — 둘 다 [다시 만들기](암호부터) |
| 9 | **정리** — 저장 · 취소 · 실패 뒤와 시트를 닫을 때 `BackupExporting.discard(_:)` 로 작업 폴더를 지운다. 만들기가 실패 · 취소되면 내보내기가 스스로 지운다. 남은 것은 다음 앱 시작의 `BackupWorkDirectory.removeStale()` 이 지운다 | — |

네트워크 없이 만들 수 있다. 계정 상태도 묻지 않는다 — 미로그인 · 연결 보류 실행도 그 기기의 행과 열 수 있는 초안을 담는다(§6-4).
마지막 필기 저장 · 파일 만들기 · 저장 위치 고르기 중에는 시트를 쓸어서 닫지 못한다(닫기 버튼으로만 — 닫으면 기다리던 일을 멈추고 만든 파일을 지운다).

### 3-2. 장 단위 읽기 (`LiveBackupExporter.export(password:fileName:progress:)`)

`LiveBackupExporter(environment:drafts:database:)` — 편집 환경(`DrawingEditEnvironmentClient`) · 초안 읽기(`VerseDraftRecoveryReading` — 앱의 `LocalPreservationWriter`) ·
이 실행의 `SwiftDatabaseActor`(편집 화면 · 「모든 필사 삭제」 와 같은 인스턴스여야 세대가 뜻을 가진다)로 만든다. `export(password:progress:)` 는 기본 이름으로 같은 일을 한다.

1. 시작할 때 `DrawingEditEnvironmentClient.current()` 로 환경을 읽어 **계정 상태 · 저장소 소유 · 여는 묶음**(`readableDraftScopes ∪ beforeConnectionDraftScopes`, 겹치는 것은
   한 번)을 적어 둔다(`BackupExportEnvironmentBasis`).
2. 장 목록 = 행이 있는 장(`SwiftDatabaseActor.backupChapterList()` — `backupChapters()` 와 같은 목록을 **그때의 저장소 세대와 같은 actor 구간에서** 준다) ∪ 여는 묶음마다
   초안이 있는 장(`draftSummary(in:).chapters`)을 **권 · 장 자리**로 줄인 것(`BibleChapter.backupPlaces` — 같은 권 · 장이 번역본별로 여러 번 와도 한 번), 권 → 장 순서.
   진행은 `BackupProgress(done: 0, total: 자리 수)` 로 먼저 한 번 알린다.
3. 자리(권, 장)마다:
   1. `current()` 를 다시 읽는다. 계정 상태 · 저장소 소유 · 여는 묶음이 시작 때와 다르면 **`accountChanged` 로 실패**한다 — 다른 계정 초안이 한 파일에 섞이지 않게.
   2. 그 자리의 번역본 장마다(`backupTranslationChapters` — NKRV → KJV → BSB, `Translation.allCases` 순서) 아래 3 ~ 5 를 한다. 행 · 초안이 없는 번역본 장은 항목 없이 지나간다.
   3. `SwiftDatabaseActor.backupRows(chapter:)` 가 그 번역본 장의 `BackupRowRecord` 목록과 저장소 세대를 **같은 actor 구간에서** 돌려준다(`BackupRowLoad` — 행은 그 번역본의
      `StoredBookKey.titleName(for:)` 로 고르므로 다른 번역본 행이 섞이지 않는다). 세대가 장 목록을 읽은 때와 다르면(그 사이 「모든 필사 삭제」 — 첫 장 전의 삭제도 잡는다)
      **`generationChanged` 로 실패**한다. 행을 읽지 못하면 `storeUnreadable`.
   4. 그 번역본 장의 초안을 분류한다(§3-4 — `BackupExportDraftSelection.select(chapter:environment:rows:reader:)`, 환경은 1 에서 다시 읽은 것, 초안은 그 번역본 것만 읽는다) —
      위 행을 저장소 쪽 입력으로 쓴다. 그 장의 초안 파일을 하나라도 읽지 못하면 `draftsUnreadable` 로 실패한다.
   5. 항목과 blob 을 준비 폴더에 쓴다(`BackupExportItems.candidates` → `BackupExportStaging.add`). 같은 바이트의 blob 은 한 번만 쓰고, 같은 id 의 항목은 한 번만 담는다.
   6. 자리의 번역본을 다 돌면 진행을 알린다(`BackupProgress(done:total:)` — **진행 단위는 (권, 장) 자리**다).
   - 자리로 줄인 뒤 번역본마다 다시 읽으므로, 초안 요약이 장을 번역본별로 나누든 아니든 같은 초안을 한 번씩만 담는다(2026-10-12 구현에 맞춤 — `LiveBackupExporter.collect`).
4. manifest(`backupID` 새 UUID · 시작 시각 · 앱 버전 · 수)와 `items.json` 을 쓰고(`BackupExportStaging.finish`), §3-1 5 · 6단계로 암호화 · 재검증한다.
   실패 · 취소면 작업 폴더째 지우고 던진다 — 컨테이너의 공간 부족은 `insufficientSpace`, 그 밖의 쓰기 실패는 `writeFailed` 다.
5. 일관성은 **장 단위**다. 절이 충돌 단위이고(정책 §12-3) 한 장은 한 actor 구간에서 읽으므로 한 행의 잉크와 메타데이터가 다른 시점에서 섞이지 않는다.
   장 사이에 iCloud 에서 받은 변경은 뒤 장에만 담길 수 있다 — 정책 §6-1 2 의 「일관된 읽기 스냅샷」 을 장 단위로 좁힌 것이다. 메모리에는 장 하나 분량의 바이트만 든다.

### 3-3. 행 항목

- 그 장의 모든 행(현재 · 보관 · 비운 행)을 `kind = "row"` 로 **원본 그대로** 담는다 — 바이트 · `drawingVersion` · 시각 · 번역 저장값을 바꾸지 않는다.
- 절마다 `DrawingRepresentativeRule.pick` 의 대표 행만 `isCurrent = true` 다(`isPresent` → `updateDate` → 행 키). 대표가 비운 행이어도 true 다(§5-1 「비운 대표 행」).
  그 절에 shown 초안이 있으면 그 절의 행은 모두 false 다 — 그 기기 화면에 보이던 것은 초안이기 때문이다.
- 지문은 `BackupRowRecord.contentFingerprint`(원본 바이트로 만든 것)이고 항목 id 는 `BackupItemID.make(kind: .row, sourceKey: rowKey, fingerprint:)` 다
  (`BackupExportItems.rowCandidate`). 행 키와 내용이 같은 행이 둘이면(1.3.0 의 같은 초 business id 등 — 같은 id) 하나만 담는다 — 대표였던 쪽, 없으면 앞의 것
  (파일 안 id 는 겹칠 수 없다 — §4-2). 겹친 수는 로그에 남긴다.
- 권 · 장 · 절을 알 수 없는 행은 절 키를 만들 수 없어 담지 못한다 — 수만 로그에 남긴다(§7).

### 3-4. 초안 분류

입력은 「확인이 필요한 필기」 목록(`VerseDraftRecoveryQuery.inventory`)과 같다. 편집 화면이 읽는 묶음은 `VerseDraftRecoveryRule.screenDrafts` →
`plan(sessionID: nil, …)` 로(지금 편집 세션 없이 — 모든 초안을 다른 세션의 것으로), 확인된 계정의 연결 전 묶음은 `beforeConnectionDrafts` → `importPlan` 으로 가른다
(`BackupExportDraftSelection.select` — 초안은 장의 번역본 하나로 `drafts(in:chapter:translation: chapter.translation)` 로 읽는다. 모든 번역본의 초안은 §3-2 가 자리마다
`Translation.allCases` 를 돌며 담는다 — 2.1 영어 현지화 전에는 `.NKRV` 고정이었다).
저장소 쪽 입력(절마다 대표 내용 · 행 · 이력 지문)은 §3-2 의 `BackupRowLoad` 에서 만든다 — 행을 장 조회(`loadDrawingSnapshots`)와 **같은 변환**
(`BackupRowRecord.recoveryRuleSnapshot` — 메타데이터를 해석한 `VerseDrawingSnapshot`)으로 바꿔 `VerseDraftStoreView` 에 넣는다. 편집 화면 · 「확인이 필요한 필기」 가
이 모양으로 견주므로 같은 판정이 되려면 같은 입력이어야 한다. 이 변환은 판정에만 쓰고, 항목은 원본(`BackupRowRecord`) 그대로 담는다.

| 분류 | 판정 | 담나 | `isCurrent` |
|---|---|---|---|
| `settled` — 내용이 이미 저장소에 있다 | `plan` | 뺀다 | — |
| `shown` — 그 장을 열면 화면에 겹친다 | `plan` | 담는다 | true (그 절의 행은 모두 false) |
| `kept` — `recoverable` · `uncertain` · `undisplayable` · `archived` 를 포함 | `plan` | 담는다 | false |
| 연결 전 필기 — `awaiting` · `undisplayable` · `archived` | `importPlan` | 담는다 | false |
| 연결 전 필기 — `settled`(지금 필사와 같거나 이미 가져옴) | `importPlan` | 뺀다 | — |
| 다른 계정 묶음 | 열지 않는다 | 뺀다 | — |
| 원시 사본(`raw/`) · 분리본(`separation/`) · 읽지 못한 초안 파일(`*.unreadable-*`) | — | 뺀다 | — |

- 보이지 않던 초안(`isCurrent = false`)은 **행이 있는 절에서는** 불러와도 대표가 되지 않고 이전 필사 기록(보관)으로 들어간다 — 원래 기기에서도 화면에 보이지
  않던 것이다(그 절에 `isPresent` 행이 없으면 지금 대표를 고정해 지킨다 — §4-3 · §5-1 「대표 고정」). **행이 하나도 없는 절**에서는 보관으로 넣어도 대표 규칙
  (`isPresent` 행이 없으면 전체에서 가장 늦은 것)대로 **가장 늦은 보관 항목이 보인다.** 이것을 막으려고 빈 자리(비운 현재) 행을 만들지 않는다 — 빈 자리 행은
  `isPresent` 라 나중에 다른 기기에서 도착하는 legacy 행(1.3.0 · `isPresent` 를 켜지 않는 행)을 가린다(§5-1 「행 없는 절」).
- 미로그인 기기의 여는 묶음은 `acct-local` 하나다. 확인된 계정 실행은 그 계정 묶음 + `acct-unverified`(편집 화면) + 연결 전 묶음(`acct-local` · 참고 계정 없는
  `acct-unverified`)이다. 묶음은 `source.draftScope` 에 `"local"` · `"unverified"` · `"account"` 로만 남는다.
- `acct-unverified` 는 두 판정에 모두 들지만 초안의 참고 계정(힌트)으로 갈려 겹치지 않는다 — 지금 계정 힌트는 편집 화면 쪽(`reachesScreen`), 힌트 없음은 연결 전
  필기(`awaitsImport`), **다른 계정 힌트는 어느 쪽에도 들지 않아 담지 않는다**(다른 사람의 필기일 수 있다 — P0-1).
- 초안 파일을 읽지 못한 장이 있으면 그 장을 조용히 빼지 않고 내보내기를 실패로 끝낸다(`BackupExportError.draftsUnreadable` — 「이 iPad에 남겨 둔 필기 일부를 읽지
  못해 멈췄어요. 설정의 ‘확인이 필요한 필기’에서 확인할 수 있어요.」) — 담았다고 말한 범위와 실제 파일이 달라지지 않게. 묶음 요약(장 목록)을 읽지 못해도 같다.
- 초안 항목의 id 는 `BackupItemID.make(kind: .draft, sourceKey: draftSourceKey(…), fingerprint:)`, 지문은 초안의 원본 바이트로 만든다(`BackupExportItems.draftCandidate`).

## 4. 불러오기 흐름 — 「백업 불러오기」

### 4-1. 단계

번호는 코드 주석이 가리키는 단계 이름이다. 실제 순서는 0 → 1 → 3(암호) → [`inspect(fileURL:password:)` 안에서 5(대상 계정) → 2(복사) → 4(검사) → 6(미리보기)]
→ 7 → 8 → 9 → 10 이다. 흐름은 `BackupImportFeature`(시트, effect 는 `BackupImportFeature+Work.swift`)와 `LiveBackupImporter` 가 나눠 맡는다.

| # | 단계 | 저장소 |
|---|---|---|
| 0 | **멈춘 작업** — 시트를 열면 끝나지 않은 불러오기(`pendingJob()`)부터 본다. 있으면 「이어서 불러오기」 · 「버리기」 또는 「버리기」 · 「이 계정으로 처음부터」(§6-3), 없으면 1 | 그대로 |
| 1 | **파일 고르기** — 「불러올 백업 파일(.carvebackup)을 골라 주세요. …」 + SwiftUI `fileImporter(isPresented:allowedContentTypes: [.carveBackup])` | 그대로 |
| 2 | **복사** — Feature 가 고른 파일의 보안 범위 접근을 열고(`BackupFileAccessClient` · `\.backupFileAccess` — 열었을 때만 닫는다) `inspect(fileURL:password:)` 를 부른 뒤 닫는다. 검사는 고른 파일을 **먼저** 작업 기록 폴더로 복사하고(`Application Support/BackupImport/<jobID>/backup.carvebackup` — 암호화 사본이자 이어 하기 사본, §6-3) 그 뒤로는 사본만 읽는다. 고른 파일의 크기 · 시각은 읽지 않는다(복사만 한다 — 개인정보 매니페스트 `C617.1` 범위 밖의 접근을 만들지 않는다). 남은 공간은 `BackupArchive` 가 쓰기 · 풀기 전에 `volumeAvailableCapacityForImportantUsage` 로만 본다(`BackupDiskSpace` — 매니페스트 DiskSpace `E174.1`). 복사 중 공간 부족은 쓰기 오류(ENOSPC)로 안다 | 그대로 |
| 3 | **암호** — 「백업 암호」 한 칸(`textContentType(.password)`). 암호는 검사에 넘기는 즉시 상태에서 지운다 | 그대로 |
| 4 | **검사** — `BackupArchive.read(…maxEntryBytes: archiveEntryLimit, maxTotalBytes:, maxEntryCount: 2 × maxItems + 2)` 로 평문 작업 폴더(`BackupWork/<UUID>/Unpacked-<UUID>/`)에 풀고 `BackupPayload.load(rootDirectory:limits:)` 가 디코딩 · 검증한다(§4-2) | 그대로 |
| 5 | **대상 계정** — 검사를 시작할 때 읽은 환경으로 `targetScope` 를 정한다(`LiveBackupImporter.targetScope(for:)` — §6-2). 작업 기록에 묶는다 | 그대로 |
| 6 | **미리보기** — 항목마다 지원 판정(`BackupItemSupport.reason(_:blobDirectory:)`)을 하고, 항목이 놓이는 장마다 `backupRows(chapter:)` 와 `BackupImportPlanner.plan` 으로 수를 센다(`BackupImportPreview` — `new` · `same` · `archived` · `protectedCleared` · `skippedEmpty` · `unsupported`(사유별) · `chapters`). 장 하나씩 읽고 놓는다. 화면은 만든 때 · 담은 수(manifest), 「새 필사」 · 「같은 필사」 · 「이전 필사 기록에 더할 것」 · 「지운 절이라 기록에만」 · 「넣을 수 없는 것」(사유별)과 안내 원문 「불러온 필사는 이 기기에 저장되고, 지금 연결된 iCloud 계정으로 동기화돼요. 지금 필사는 그대로 두고, 다른 내용은 이전 필사 기록에 더해요.」 · 「미리보기 수는 지금 기준이에요. …」 를 보인다(비운 항목 수 `skippedEmpty` 는 미리보기에 따로 보이지 않고 결과의 「건너뛴 것」 에 「비운 기록」 으로 보인다) | 그대로 |
| 7 | **쓰기 게이트** — `targetScope` 가 nil 이면(`BackupInspection.canApply == false`) 미리보기까지다. 적용 대신 「지금은 미리보기만 할 수 있어요. 」 + 사유와 할 일을 보인다 — 「확인이 필요한 필기」 가져오기(`DraftRecoveryCopy.importBlocked`)와 같은 `SyncedWriteBlock` 사유를 불러오기 말로 한다(`BackupCopy.importBlocked` — 미로그인 · 연결 보류는 하나로 「iCloud 에 로그인한 뒤 앱을 다시 열면 불러올 수 있어요.」) | 그대로 |
| 8 | **적용** — 「불러오기」 를 누르면 작업 기록을 「적용 중」 으로 바꾸고(다른 작업 기록은 지운다 — 작업 기록은 늘 하나다) 장 단위로 쓴다(§4-3). 진행 「필사를 넣는 중이에요 · n/N장」(N 은 번역본 장 수 — 내보내기와 달리 같은 권 · 장도 번역본마다 한 장으로 센다) | 장마다 한 트랜잭션 |
| 9 | **결과** — 실제로 넣은 수 · 건너뛴 수 · 넣지 못한 수 · 멈춘 사유(`BackupImportReport` — `.completed(tally)` · `.blocked(SyncedWriteBlock, doneChapters:, tally:)` · `.accountChanged(doneChapters:, tally:)` · `.generationChanged(doneChapters:, tally:)`, 저장 실패 등은 `BackupImportError`). 수는 `BackupImportTally`(`new` · `same` · `archived` · `protectedCleared` · 「비운 기록」 `skippedEmpty` · `unsupported` · 대표 고정 `pinned`)다. 쓰기 직전에 다시 판정하므로 미리보기 수와 다를 수 있다(정책 §7-1). 넣은 것이 있으면 「이 기기에 저장됐어요. iCloud 전송은 따로 진행돼요.」 — 로컬 반영과 iCloud 전송은 다르다(정책 §7-2 5) | — |
| 10 | **정리** — 평문 작업 폴더는 끝나면(성공 · 멈춤 · 실패 · 취소 · 닫기) 지운다(`apply` 가 끝날 때 · `discard(_ inspection:)`). 적용을 시작하지 않은 작업은 기록 · 암호화 사본도 지운다. 앱 시작 때 남은 `BackupWork` 를 지운다(`BackupWorkDirectory.removeStale()`) | — |

검사 · 미리보기는 구매 여부를 묻지 않고 저장소를 바꾸지 않는다. 미리보기 수는 검사 시점의 값이다. 검사 · 적용 중이거나 미리보기의 검사 결과를 들고 있으면
시트를 쓸어서 닫지 못한다(닫기 버튼으로만 — 닫으면 기다리던 일을 멈추고 검사 결과를 닫는다. 적용 중에 닫아도 쓴 장 · 작업 기록은 그대로다).

### 4-2. 검사 — 파일 전체를 거부하는 것

모두 **저장소를 바꾸기 전에** 거부하고, 평문 작업 폴더와 새 작업 기록(암호화 사본 포함)을 지운다. 이어 하기 · 처음부터의 검사가 실패하면 옛 작업 기록은 그대로 둔다.

| 거부 | 낸 곳의 오류 | 불러오기가 알리는 오류(`BackupImportError`) |
|---|---|---|
| 잘못된 암호 · 변조 · 잘림 · 백업 파일이 아님 · 다른 프로필 · SDK 가 헤더에서 거부한 비정규 경로(`..` · 절대 경로) | `BackupArchiveError.wrongPasswordOrDamaged` | `wrongPasswordOrDamaged` |
| 허용 밖 항목 이름 · 링크 · 일반 파일이 아닌 항목 · 종류 불일치 · 같은 이름 두 번 · DAT 밖 바이트 필드 | `BackupArchiveError.entryRejected(name:)` | `wrongPasswordOrDamaged`(「파일 거부」) |
| 푸는 도중 항목 하나 · 합계 · 파일 수 상한 초과(§2-8) | `BackupArchiveError.tooLarge` | `tooLarge` |
| 풀 공간 부족 · 입출력 실패 | `BackupArchiveError.insufficientSpace` · `.ioFailed` | `insufficientSpace` · `ioFailed` |
| `formatVersion` ≠ 1 | `BackupFormatError.unsupportedFormat(formatVersion:)` | `unsupportedFormat(formatVersion:)` |
| 색인 파일 · 항목 수 · blob 하나 · blob 합계 상한 초과 | `BackupFormatError.limitExceeded(.indexBytes · .items · .blobBytes · .totalBytes)` | `tooLarge` |
| manifest · items 가 없거나 디코딩 실패 | `malformed(fileName:)` | `wrongPasswordOrDamaged` |
| manifest blob 항목이 형식에 맞지 않음(이름 형식 · `name` ≠ `sha256` · 음수 크기) · 같은 blob 두 번 | `invalidBlobEntry(name:)` · `duplicateBlob(name:)` | `wrongPasswordOrDamaged` |
| `counts` 불일치 | `countsMismatch` | `wrongPasswordOrDamaged` |
| 겹치는 항목 id(같은 내용) · 같은 id 다른 지문 | `duplicateItemID` · `integrity(itemID:, .conflictingFingerprint)` | `wrongPasswordOrDamaged` |
| 없는 blob 을 가리키는 항목 · manifest 의 blob 파일이 없음 · 어느 항목도 가리키지 않는 blob | `missingBlob(name:)` · `unreferencedBlob(name:)` | `wrongPasswordOrDamaged` |
| blob 실제 크기 · SHA-256 불일치 | `blobSizeMismatch(name:)` · `blobHashMismatch(name:)` | `wrongPasswordOrDamaged` |
| blob 바이트로 다시 계산한 내용 지문이 항목 `fingerprint` 와 다름(잉크 없는 항목의 지문이 null 이 아님 포함) | `integrity(itemID:, .fingerprintMismatch)` | `wrongPasswordOrDamaged` |
| 고른 파일을 복사하지 못함 · 미리보기에서 저장소 행을 읽지 못함 | — | `fileUnreadable` · `storeUnreadable` |

- 검증(`BackupPayloadValidator.validate`)은 싼 것부터 한다 — 형식 버전 → 항목 수 → manifest blob 목록(이름 · 해시 · 중복 · 크기 상한) → `counts` → 항목(중복 id ·
  같은 id 다른 지문 · 없는 blob 참조) → 참조되지 않는 blob → blob 실제 크기 · SHA-256 → 내용 지문. 색인 파일 크기는 그 전에 `BackupPayload.load` 가 본다.
- 문구는 `BackupCopy.inspectFailed` — 「암호가 맞지 않거나 파일이 손상됐어요. …」 · 「이 버전의 앱이 읽을 수 없는 형식의 백업이에요. 앱을 업데이트한 뒤 …」 ·
  「백업 파일이 너무 커서 불러올 수 없어요.」 · 「고른 파일을 읽지 못했어요. 파일이 이 iPad에 내려받아져 있는지 확인해 주세요.」 … 와 「확인하는 단계에서 멈춰서
  필사는 바뀌지 않았어요.」. 다시 해 볼 만한 실패(`allowsRetry`)만 같은 출처로 암호부터 다시 받는다 — 미지원 형식 · 상한 초과는 파일이 그대로면 결과도 같다.

항목 하나만 해석할 수 없는 경우(모르는 번역본 · 권 · 범위 밖 장 · 절 · 좌표 형식 · 풀리지 않는 메타데이터)는 파일을 거부하지 않고 그 항목만 건너뛴다(§5-1 `unsupported`).

### 4-3. 장 단위 적용 (`LiveBackupImporter.apply(_:progress:)`)

`LiveBackupImporter(environment:restorer:database:changes:jobs:)` — 편집 환경 · 복원 쓰기(`SwiftDataDrawingBackupRestorer` — `database` 와 **같은** actor) ·
이 실행의 `SwiftDatabaseActor` · 이 기기의 필사 변경 알림(`LocalDrawingChangeClient` — 「확인이 필요한 필기」 와 같은 인스턴스) · 작업 기록 저장소로 만든다.

시작할 때: 검사 결과에 풀린 백업이 없거나 평문 작업 폴더가 이미 지워졌으면 `inspectionExpired`(다시 검사하거나 이어 하기로 암호를 다시 받는다), 작업 기록이
없으면 `jobNotFound` 다. 이 작업 밖의 작업 기록을 지우고(`removeAll(except:)`) 상태를 「적용 중」 으로 남긴 뒤, 저장소 세대를 **한 번** 읽는다
(`SwiftDatabaseActor.backupStoreGeneration()`). 진행은 이미 끝난 장 수로 먼저 한 번 알린다.

장마다(미리보기의 `chapters` — 지원 항목이 있는 장, 권 순서 → 장 순서 → 번역본 순서. 장은 번역본을 지니므로(`BackupImportPlanner.chapter(of:)` — nil · 모르는 번역본은
개역개정 장) 같은 권 · 장도 번역본마다 따로 쓰고 따로 진행을 센다. 2026-10-12 구현에 맞춤):

1. 작업 기록에 끝난 장이면 건너뛴다(이어 하기). 다시 써도 같은 지문은 `skipSame` 이라 결과는 같다.
2. `DrawingEditEnvironmentClient.current()` 로 **최신 환경**을 읽는다. `SyncedWriteBlock.check(env) != nil` 이면 그 장부터 멈추고 `.blocked(사유, doneChapters:, tally:)`,
   `env.storeOwnership != targetScope`(대상 계정이 없던 검사 포함)면 `.accountChanged(doneChapters:, tally:)` 다(`LiveBackupImporter.stopReason`). 이미 쓴 장은
   그대로 둔다 — 이미 동기화됐을 수 있어 되돌리지 않는다. 작업 기록은 「멈춤」 으로 남고(이어 하기 대상), **끝난 장 · 수를 비운다**
   (`LiveBackupImporter.forgetDoneChapters` — 이어 하면 처음부터 다시 판정한다. 2026-10-14 출시 시험 D12: iCloud 로그아웃 · 계정 전환은 시스템이 이 기기의
   동기화 데이터를 비워, 올라가기 전의 장이 사라졌는데 끝난 장으로 건너뛰어 빠진 채 끝났다. 다시 판정하면 남은 행은 `skipSame` 으로 건너뛴다). 장을 쓴 뒤
   서버 작업 표가 무효가 돼 `.accountChanged` 로 멈출 때(5 아래)도 같다. 멈춘 화면의 보고는 비우기 전에 만들어 이번에 넣은 수를 보인다.
3. 그 장의 항목과 항목이 가리키는 blob 바이트로 명령을 만든다(`BackupChapterRestoreCommand(items:blobs:)` — 지원 판정을 **이 바이트로** 다시 계산해 미리보기와 같다).
   `DrawingBackupRestoring.restore(command, chapter:, generation:)` — 같은 actor 구간에서 세대를 확인하고, 그 장의 행을 `BackupRowRecord` 로 **다시 읽어 판정을 다시 한
   뒤**(미리보기 뒤 동기화로 바뀐 것 반영) 넣을 행과 대표 고정을 **한 트랜잭션**으로 쓴다(아래). 세대가 적용을 시작할 때와 다르면(그 사이 「모든 필사 삭제」)
   아무것도 쓰지 않고 `DrawingRepositoryError.staleStoreGeneration` 을 던지고, 적용은 `.generationChanged` 로 멈춘다 — 앞서 쓴 장의 행도 지워졌으므로 작업 기록의
   끝난 장 · 수를 비운다(이어 하면 처음부터 다시 판정한다). 그 밖의 쓰기 실패는 `storeWriteFailed`(그 장은 rollback, 앞서 쓴 장은 그대로), 평문 blob 을 읽지 못하거나 복원이
   쓰기 전에 명령을 거절하면(`BackupChapterRestoreError`) `inspectionExpired` 를 던지고 작업 기록은 「멈춤」 으로 남는다. 취소면 `CancellationError` 그대로다.
4. 작업 기록에 그 장을 끝남으로 남긴다(끝난 장 · 실제 수 `tally`).
5. 그 장의 저장소가 바뀌었으면(넣은 행이나 대표 고정이 있으면 — `BackupChapterRestoreOutcome.changedStore`) `LocalDrawingChange(chapter:date:)` 를 보낸다 —
   설정 아래 열린 필사 화면이 그 장이면 다시 읽어 반영한다(늦게 도착한 필사와 같은 길). 같은 내용뿐인 장은 보내지 않는다.
6. 진행을 알린다. 다음 장이 남았으면 그 환경의 서버 작업 표가 아직 유효한지(`isCurrent(env.serverWork)`) 본다. 아니면 다음 장으로 가지 않는다(`.accountChanged`).

다 쓰면 작업 기록 · 암호화 사본을 지우고 `.completed(tally)` 다. 어느 쪽이든 평문 작업 폴더는 지운다.

넣는 행(`SwiftDatabaseActor.restoreBackupChapter` — 쓰기 전에 넣을 행의 blob 바이트(이름 = SHA-256 인지까지) · 번역값과 고정할 행을 **모두 확인**하고, 하나라도
어긋나면 아무것도 바꾸지 않고 `BackupChapterRestoreError`(`blobUnavailable(name:)` · `unknownTranslation`)를 던진다. iOS 17 SwiftData 의 rollback 이 외부 저장 Data 를
가진 기존 모델의 메모리 값을 복원하지 못할 수 있어서다. 그다음 넣기 · 고정을 하고 `save()` 한 번, 실패하면 `rollback()`):

| 필드 | 값 |
|---|---|
| `lineData` · `drawingVersion` · `layoutMetadataData` | blob 원본 바이트 · 원본 값 그대로 — 승격 · 강등 · 다시 인코딩하지 않는다. `drawingVersion` 이 null 이면 null 이다(모델 기본값 1 로 두지 않는다) |
| `creationDate` · `updateDate` | 항목의 `createdAt` · `updatedAt` 그대로(null 이면 null) — `now` 로 덮지 않는다(정책 §7-1). `BibleDrawing.init` 이 채운 now 를 넣은 뒤 덮는다. 차트 · 장 목록은 모든 행의 `updateDate` 로 세므로 원래 쓴 날짜로 보인다 |
| `isPresent` | `insertCurrent` 만 true. `insertArchived` · `protectCleared` 는 false |
| `rowUUID` | **늘 새로 발급**한다. 두 기기가 같은 파일을 넣어 같은 `rowUUID` 행이 둘 생기면 행 찾기(`rowUUID == raw \|\| id == raw`)가 깨진다 — 대신 같은 내용 행이 둘일 수 있다(§7) |
| business `id` | `BibleDrawing.init` 이 만드는 값 그대로(`<titleName>.<장>.<절>.<불러온 시각 초>`). 행 키는 `rowUUID` 라 이 값으로 찾지 않고, 쪼개 파싱하지 않는다 |
| `translation` | 개역개정 항목은 값 그대로 — null 이면 null(모델 기본값 NKRV 로 두지 않는다). **KJV · BSB 항목은 nil**(2026-10-06 — SwiftData 열에는 `.NKRV` · nil 만 쓴다, `StoredBookKey.translationColumn`) |
| `titleName` · `titleChapter` · `verse` | 권 코드 + 번역본으로 지은 `StoredBookKey.titleName(title:translation:)`(개역개정 · null 은 `BibleTitle.rawValue`, 영어는 `KJV-<rawValue>` 등) · 장 · 절. 복원 판정이 읽는 그 장의 행도 같은 이름으로 고른다 |

**있는 행은 고치지 않는다 — 넣기만 한다(정책 §1-6).** 재시도는 같은 규칙으로 **멱등**이다.

**예외 하나 — 대표 고정(2026-10-06 오케스트레이터 결정).** 대표 규칙은 `isPresent` 행이 없으면 전체 행에서 가장 늦은 것을 고르고, 1.3.0 legacy 행은 대개
`isPresent` 가 false · null 이다. 그래서 그런 절에 더 늦은 다른 내용을 보관 행으로 넣기만 해도 화면의 필사가 바뀐다 — 「지금 필사는 그대로 둔다」(정책 §7-1)를 어긴다.
그 절(`R`)에 `isPresent` 행이 없고 이번 판정에 `insertCurrent` 가 없는데 넣는 행이 있으면, **지금 대표 R0 의 `isPresent` 만 true 로 바꿔 지금 필사를 고정한다**
(`BackupChapterPlan.pins` — `BackupRepresentativePin(verse:rowKey:)`). 넣기와 같은 트랜잭션이고, 내용 · 시각은 그대로다. 비운 대표여도 같다(그 절은 비운 채로 남는다).
있는 행을 바꾸는 **유일한** 경우이고, 「이전 필사 내용 보기」 복원(`updatePresentDrawing`)과 같은 종류의 쓰기다 — 2.0 의 다른 쓰기도 늘 현재 행을 명시한다.
고정할 행은 그 절에서 행 키가 같은 행이고, 같은 키가 둘이면(1.3.0 의 같은 초 business id) 대표 규칙이 고르는 쪽이다. 찾지 못하면 고정만 건너뛰고 로그에 남긴다.
고정한 수는 결과의 `tally.pinned` 에만 있고 미리보기 수에는 들지 않는다. **행이 하나도 없는 절은 고정하지 않는다** — 빈 자리 행을 만들지 않는다(§5-1 「행 없는 절」).

## 5. 판정 규칙 · flush 계약 · 백업 전용 조회

### 5-1. 판정 규칙 — `BackupImportPlanner.plan(items:unsupported:current:chapter:)`

순수 함수다(파일 · 저장소 · 시각을 모른다). 미리보기(`LiveBackupImporter.preview(of:)` — 장마다 `plan` 을 모은다)와 쓰기 직전 재판정
(`SwiftDatabaseActor.restoreBackupChapter`)이 같은 함수를 쓴다. 항목의 지원 판정은 호출부가 blob 을 읽어 `BackupItemSupport.reason` 으로 계산해
`unsupported: [항목 id: BackupUnsupportedReason]` 로 넘기고, 지금 저장소는 백업 전용 조회(`BackupRowRecord` — 원본 바이트로 만든 지문)로 받는다.
결과는 `BackupChapterPlan` — 항목마다의 결정(`BackupItemDecision(itemID:verse:decision:)`, 절 오름차순 · 절 안에서는 처리 순서), 넣을 행(`BackupRowInsertion`),
대표 고정(`pins`)이다. 어느 장에도 놓을 수 없는 항목(모르는 권 · 범위 밖 장)은 장 판정에 들지 않고 미리보기에서만 사유별로 센다(`unplaced(items:unsupported:)` —
적용의 `tally.unsupported` 에는 들지 않는다).

**판정 단위 — 한 절.** 권 · 장 · 절이 같고 번역본이 같은 것. 번역 null 은 지금 앱에서 NKRV 화면에 보이므로(장 조회는 번역으로 거르지 않고, 즐겨찾기도
`translation ?? .NKRV` 로 본다) **NKRV 와 한 묶음**으로 판정한다 — 저장값은 null 그대로 넣는다. 번역본이 둘 이상이 되면 이 묶음을 다시 정한다(영어 성경 작업).

**2026-10-06 영어 현지화 — 묶음은 셋이다.** nil · NKRV 한 묶음은 **그대로**고, KJV · BSB 는 각자 묶음이다. 영어 행은 저장소에서 `translation` 열이 nil 이어도
`titleName` 접두로 KJV · BSB 로 읽힌다 — **행의 묶음은 `titleName` 접두를 먼저 보고(`StoredBookKey.decode`), 접두가 없는 행만 열 값으로 정한다.** 그래서 영어 행이
null 묶음(개역개정)에 섞이지 않는다. 장 단위 조회도 번역본별 `titleName` 으로 고르므로 한 장의 행은 한 번역본뿐이다.

- `R` = 그 절의 지금 저장소 행 전부(`BackupRowRecord` — 현재 · 보관 · 비운 행). `대표` = `DrawingRepresentativeRule.pick(R)`.
- `R` 은 쓰기 직전에 다시 읽은 저장소다. 같은 파일의 다른 항목이 넣을 행은 `R` 에 더하지 않는다 — 단 **같은 지문은 한 절에 한 번만** 넣는다.
- **현재 후보** = 그 절의 지원되는 `isCurrent` 항목 중 `updatedAt` 이 가장 늦은 하나(null 은 가장 이른 시각, 같으면 id 사전순 앞). 나머지 `isCurrent` 항목은
  현재 후보가 아닌 것으로 다룬다. 지원되지 않는 `isCurrent` 항목은 후보가 아니다 — 지원되는 다음 `isCurrent` 항목이 후보다.
- 시각 비교에서 null 은 가장 이른 시각이다(`DrawingRepresentativeRule` 과 같다).
- 순서: 지원 판정 → 현재 후보 → 나머지(id 순). 같은 지문이 둘이면 현재 후보가 먼저 자리를 잡는다.
- 「잉크 있음」 은 `inkBlob` 이 있는 것이다(형식의 「비운 행」 정의와 같다). 판정기는 바이트를 풀지 않는다.

| 결정 | 언제 | 쓰기 | 미리보기 | 근거 |
|---|---|---|---|---|
| `unsupported(사유)` | 판정 순서대로 첫 사유 하나(`BackupUnsupportedReason`): 번역본이 null 도 아니고 `Translation` 의 값도 아님(`unknownTranslation` — 2026-10-06 부터 `KJV` · `BSB` 는 아는 값, 예: `"ESV"`) · 권 코드가 `BibleBookCode` 에 없음(`unknownBook`) · 장이 `1...그 권의 lastChapter` 밖이거나 절이 1 미만(`outOfRange` — 2026-10-02 더함) · `drawingVersion` 이 nil · 1 · 2 · 3 밖(`unknownDrawingVersion`) · `drawingVersion` 3 이고 잉크가 있고 **메타데이터 blob 이 있는데** `DrawingLayoutMetadata.decode` 로 풀리지 않음(`undecodableMetadata` — 뒤 버전의 `metadataSchemaVersion` 일 수 있다). **메타데이터 blob 이 없는 v3 잉크 항목은 지원한다**(2026-10-02 — 원본 그대로 넣는다. `DrawingCodec` 이 이미 첫 밑줄 `storageOrigin` 기준으로 보여 주는 상태라 건너뛰면 필기를 잃는다). 비운 항목은 메타데이터가 없거나 깨져도 지원 밖이 아니다 | 없음 | unsupported(사유별 수 — 「모르는 번역본」 · 「모르는 성경 권」 · 「성경에 없는 장이나 절」 · 「모르는 필기 형식」 · 「읽지 못하는 위치 정보」) | 모르는 형식을 조용히 바꾸거나 버리지 않는다 — 건너뛰고 알린다(정책 §6-2 · §8) |
| **잉크 있는 항목** | | | | |
| `skipSame` | `R` 의 어느 행(대표 · 보관)과 `fingerprint` 가 같다, 또는 이 절에 같은 지문을 이미 넣기로 했다 | 없음 | same | 같은 내용은 한 번만 — 같은 파일을 다시 불러오면 0건(정책 §7-1) |
| `protectCleared` | 현재 후보 · 대표가 비운 행 · 대표의 `updateDate` 가 항목 `updatedAt` 보다 늦다 | 새 행, `isPresent = false` | protectedCleared | 이 기기에서 백업보다 뒤에 지운 절 — 지운 것을 되살리지 않고 기록에만 둔다(`VerseDraftImportCheck.Caution.verseClearedAfterDraft` 선례) |
| `insertCurrent` | 현재 후보 · 잉크 있는 대표가 없다(`R` 이 비었거나 대표가 비운 행) · 위가 아님 | 새 행, `isPresent = true` | new | 비어 있던 절은 백업의 현재 필사로 채운다. 새 행이 `isPresent` 행 중 가장 늦어 대표가 된다(같은 시각이면 행 키 순) |
| `insertArchived` | 그 밖 — 잉크 있는 대표가 있는데 내용이 다르다, 또는 현재 후보가 아니다 | 새 행, `isPresent = false` | archived | 지금 필사를 유지하고 다른 내용은 이전 필사 기록에 더한다(정책 §7-1). **행이 있는 절에서는** 넣은 보관 행이 대표가 되지 않는다(`isPresent` 행이 있으면 그 행이 이기고, 없으면 대표 고정). **행이 없는 절에서는** 대표 규칙대로 가장 늦은 보관 항목이 보인다 — 아래 「행 없는 절」 |
| **비운 항목(`inkBlob` null)** | | | | |
| `insertCurrent` | 현재 후보 · `R` 이 비었다 | 비운 새 행(`lineData` nil), `isPresent = true` | new | 백업에서 지운 상태였던 절 — 아래 「비운 대표 행」 |
| `skipSame` | 대표가 이미 비운 행 | 없음 | same | 이미 지운 상태다 |
| `skipEmpty` | 그 밖 — 잉크 있는 대표가 있다, 또는 현재 후보가 아니다 | 없음 | skippedEmpty | 지금 필사를 비우지 않고, 기록에 빈 행을 더하지 않는다 |

**비운 대표 행.** `DrawingRepresentativeRule.pick` 은 `isPresent` 행이 없으면 **전체에서** 고른다. 그래서 지운 절을 담을 때 비운 대표 행을 빼거나, 불러올 때
건너뛰면 같은 백업의 잉크 있는 보관 행(`isPresent = false`)이 대표로 올라가 **지운 필기가 되살아난다.** 내보내기는 비운 대표 행도 `isCurrent = true` 로 담고(§3-3),
불러오기는 그 절에 행이 하나도 없을 때 비운 현재 행으로 넣는다.

**대표 고정(2026-10-06 오케스트레이터 결정 — §4-3).** `R` 이 있는데 그중 `isPresent` 행이 없고(1.3.0 legacy 절), 이 절의 결정에 `insertCurrent` 가 없는데 새 행을
넣는 결정(`insertArchived` · `protectCleared`)이 있으면, 지금 대표 R0(`pick(R)`)를 `pins` 로 낸다(`BackupImportPlanner.representativePin`). 적용이 넣기와 같은
트랜잭션에서 R0 의 `isPresent` 만 true 로 바꿔, 더 늦은 보관 행이 그 절의 대표를 바꾸지 못하게 한다. 결정과 미리보기 수는 바뀌지 않는다.
`isPresent` 행이 있는 절 · 넣는 행이 없는 절 · `insertCurrent` 로 넣는 절(새 present 행이 대표가 된다)은 고정하지 않는다.

**행 없는 절.** `R` 이 비었는데 현재 후보가 없으면(예: 원래 기기에서 보이지 않던 초안만 있는 절, 현재 항목이 지원 밖인 절) 잉크 있는 항목은 모두 `insertArchived` 로
들어가고(비운 항목은 `skipEmpty`), `isPresent` 행이 없으므로 대표 규칙대로 **가장 늦은 보관 항목이 그 절에 보인다.** 이것을 막으려고 빈 자리(비운 현재) 행을
만들거나 고정하지 않는다 — 빈 자리 행은 `isPresent` 라, 나중에 다른 기기에서 도착하는 legacy 행(1.3.0 · `isPresent` 를 켜지 않는 행)을 대표에서 가려 그 절이
비어 보이게 한다. 빈 절에 원래 보이지 않던 필기가 보이는 것은 받아들인다(지우거나 덮는 것이 아니고, 그 절에는 다른 필사가 없다).

**예 — 「비운 현재 + 잉크 보관」(§2-9 의 2절).** 백업: (a) 비운 행 `isCurrent = true` · `updatedAt` 9/30(지운 시각), (b) 잉크 있는 보관 행 `isCurrent = false` · 9/25.

| 지금 이 기기의 그 절 | (a) | (b) | 결과 |
|---|---|---|---|
| 행 없음(빈 저장소) | `insertCurrent`(비운 행, present) | `insertArchived` | 대표 = (a) — 절은 비어 보이고 지운 필기는 「이전 필사 내용 보기」 에만 있다. (a) 를 건너뛰었다면 (b) 가 대표가 됐다 |
| 잉크 있는 대표 X(9/28) | `skipEmpty` | `insertArchived`(지문이 다르면) | X 그대로 |
| 비운 대표(10/01 에 지움) | `skipSame` | `insertArchived`(지문이 다르면) | 비운 상태 그대로 |

**예 — 지운 절 보호.** 백업의 현재 필기 Y(`updatedAt` 9/20)를, 이 기기에서 9/29 에 지운 절에 불러오면 `protectCleared`(보관으로만). 9/10 에 지운 절이면 Y 가 더 늦으므로
`insertCurrent` — Y 가 대표가 된다.

### 5-2. 캔버스 flush 계약

정책 §6-1 1단계(「진행 중 편집을 먼저 반영하고, 실패하면 백업으로 넘어가지 않는다」)의 구현이다. `flushPending` 은 인계(`handoffToken`) 요청과 저장 시작뿐이고
**끝났다는 신호가 없다** — 보내기만 하고 백업을 시작하면 마지막 revision 이 초안 · 저장소에 닿기 전의 상태를 읽는다. 그래서 **요청 → 완료 대기**로 한다.

```
① BackupExportFeature ── Delegate.canvasFlushRequested(id) ──▶ (설정 · BackupFeature) ──▶ AppCoordinatorFeature
                        암호를 확인한 뒤 새 id(@Dependency(\.uuid))로 묻고, 설정 쪽 시한 10초(canvasFlushTimeout)를 잰다
② AppCoordinatorFeature  relayBackupFlushRequest — 필사 화면 있음 → ChapterCanvasFeature.Action.backupFlushRequested(id:)
                                                   없음(시작 화면) → 곧바로 .durable
③ ChapterCanvasFeature   flushPending 과 같은 인계(handoffToken)를 요청하고 저장을 시작한다(ChapterCanvasBackupFlushFeature.swift)
                        인계가 끝나고 saveRetryCount != nil                                → Delegate.backupFlushFinished(id:outcome: .failed(retryCount:))
                        인계가 끝나고 hasUnsavedChanges == false                            → .durable
                        5초(ChapterCanvasFeature.backupFlushTimeout) 안에 정해지지 않음      → .timedOut
④ AppCoordinatorFeature ── SettingsFeature.Action.canvasFlushFinished(id:outcome:) ──▶ 설정(path 가 「필사 백업」 일 때만)
                        → BackupFeature.export(.canvasFlushFinished) → 그 id 를 기다리는 BackupExportFeature
                        (설정 쪽 10초 시한이 먼저 지나면 canvasFlushTimedOut → .timedOut)
```

- `.durable` 의 뜻 — **마지막 revision 까지 이 기기에 남았다.** 저장소로 갈 것은 저장소에, 그 밖(소유 근거 없음 · 연결 보류 · 보이기만 하는 절 · 닫는 세션)은 초안에.
  `hasUnsavedChanges` 는 획을 긋는 중(`isEditing`) · 디바운스 구간 · 편집 큐 · 저장 대기 · 닫은 세션의 늦은 편집까지 본다. 판정은 캔버스의 저장 상태 표시와 같은 값으로
  하고 새 조건을 만들지 않는다.
- 캔버스 쪽(`BackupFlushRequest` — State `backupFlush`): 요청 때의 인계 토큰을 들고, 그 토큰 **이후**의 인계가 끝나면(`editHandoffCompleted` — `>=`) 판정한다.
  캔버스가 없거나 지킬 편집이 없으면 인계를 기다리지 않는다(캔버스가 없어도 도는 초안 · 저장은 끝을 기다린다). 닫는 중인 세션이면 `flushPending` 의 재시도 경로
  (`retrySessionEnd`)와 같다. 판정은 요청 · 인계 완료 · 초안 저장 결과(`draftsSaved`) · 저장 결과(`saveFinished`) · 캔버스 분리(`canvasDetached`) · 시한에서 하고,
  시한이 지나면 마지막으로 한 번 판정한 뒤에도 정해지지 않았을 때만 `.timedOut` 이다. **요청마다 한 번만 답한다** — 같은 id 가 다시 오면 아무것도 하지 않고,
  기다리는 중에 새 id 가 오면 앞 요청은 `.timedOut` 으로 끝낸다. 앞 요청의 늦은 인계 · 시한 알림은 새 요청에 답하지 않는다.
- `.durable` 이 아니면 백업을 시작하지 않는다 — 「필사 화면에 아직 저장하지 못한 필기가 있어요. 필사 화면에서 저장을 다시 시도한 뒤 백업해 주세요.」 +
  [다시 시도](새 id). 다른 id 의 늦은 결과는 버린다(설정 쪽도 기다리는 `.flushing(id:)` 와 같은 id 만 받는다). 「필사 백업」 화면이 아니면 설정이 결과를 버린다.
- 캔버스 쪽 시한(5초)이 설정 쪽(10초)보다 짧아 설정이 먼저 포기하지 않는다.
- 설정이 열려 있는 동안 캔버스 입력은 이미 막혀 있다(`AppCoordinatorView` 의 `allowsHitTesting`) — flush 뒤에 새 획이 끼지 않는다.
- 결과 타입 `CanvasFlushOutcome`(`.durable` · `.failed(retryCount: Int)` · `.timedOut`)은 CarveFeature 와 SettingsFeature 가 함께 쓰므로 Domain 에 둔다.
  Feature 끼리 import 하지 않고 코디네이터가 중계한다.
- 리듀서의 시간 제한은 `@Dependency(\.continuousClock)` 이다 — 시험은 `TestClock`.
- 한계: 인계가 받는 것은 PencilKit 이 이미 반영한 획이다(§7). `ChapterCanvasFeature` 본체에는 State 필드 하나 · Action 둘(`backupFlushRequested` · `backupFlushTimedOut`) ·
  판정 호출 넷만 더했다(기존 처리 순서 그대로) — 그래도 `type_body_length` 경고가 났다(§7).

### 5-3. 백업 전용 조회 — `BackupRowRecord`

행 읽기는 `DrawingRepository.load` 가 아니라 백업 전용 조회다. `VerseDrawingSnapshot` 은 캔버스 표시용이라 원본 보존 계약을 지킬 수 없다.

| 필요한 것 | `VerseDrawingSnapshot` | `BackupRowRecord` |
|---|---|---|
| 만든 시각 | 없다 | `creationDate` 원본 |
| 번역 저장값(nil 포함) | 없다 | `translation: String?` |
| `rowUUID` · business id 구분 | `rowID.raw` 하나(= 행 키) | `rowKey` · `rowUUID` · `businessID` |
| `isPresent` 원본(nil 포함) | `Bool` 로 접힘 | `isPresent: Bool?` |
| 메타데이터 | 해석된 `DrawingLayoutMetadata?` — 풀지 못하면 nil | `layoutMetadataData` 원본 바이트 |
| 내용 지문 | 해석값을 다시 인코딩해야 만든다 — 풀지 못한 메타데이터는 nil 이 돼 원본 바이트 지문과 달라진다 | `contentFingerprint: String?` — 잉크가 있을 때만, 원본 바이트로 |

- 필드: `rowKey` · `rowUUID` · `businessID` · `titleName` · `chapter` · `verse` · `translation` · `isPresent` · `creationDate` · `updateDate` · `drawingVersion` ·
  `lineData` · `layoutMetadataData` — `BibleDrawing` 원본 그대로. `rowKey`(비어 있지 않은 `rowUUID`, 아니면 business id)와 `contentFingerprint` 는 만들 때 계산하고,
  디코딩할 때도 원본 필드로 다시 계산한다(저장된 계산값을 믿지 않는다). `DrawingRepresentativeCandidate` 를 따른다(`isPresent` null 은 false — 대표 규칙을 그대로 쓴다).
- `SwiftDatabaseActor.backupRows(chapter:)` 가 장마다 `BackupRowLoad(rows:generation:)` 를 **같은 actor 구간에서** 돌려준다 — 따로 읽으면 그 사이의 전체 삭제를 놓친다.
  행은 절 → 행 키 순이다. 세대(`DrawingStoreGeneration`)는 앱 실행 동안만 뜻이 있어 `BackupRowLoad` 는 Codable 이 아니다(파일에 쓰지 않는다).
- `backupChapters()` 는 행이 있는 장 목록(번역본 포함 — 권 순서 → 장 순서 → 번역본 순서, 번역본은 `titleName` 접두)이고, 내보내기는 같은 목록을 그때의 세대와 **같은 actor 구간에서** 주는 internal
  `backupChapterList()` 를 쓴다(첫 장을 읽기 전의 「모든 필사 삭제」 도 잡는다). 권 · 장 두 속성만 읽는다(`propertiesToFetch` — 잉크 바이트를 메모리에 올리지 않는다).
- `BackupRowRecord.translation` 은 열 원본이다 — 영어 행은 nil 이다. 백업 키 · 판정 묶음의 번역본은 `titleName` 접두에서 정한다(§2-4 · §5-1, 2026-10-06).
- 권 이름을 풀 수 없거나(`StoredBookKey.decode` 가 nil — 2026-10-06 전에는 `BibleTitle` 에 없는 이름) 장이 없는 행은 어느 장에도 들지 않고, 절 번호가 없는 행은 `backupRows` 에서 빠진다 — 절 키를 만들 수 없어 담지 못하고
  **수만 로그에 남긴다**(편집 화면 · 이력 화면에도 보이지 않는 행이다 — §7).
- `BibleDrawing` → `BackupRowRecord` 변환은 `SwiftDatabaseActor+Backup.swift` 한 곳(`DrawingSchemaV4.BibleDrawing.backupRecord` — internal 확장)이다.
  **내보내기 · 판정 · 복원 쓰기가 같은 변환으로 견준다** — 지문이 한쪽만 다시 인코딩되면 같은 필기를 다른 것으로 본다. 복원 쓰기는 같은 조건으로 그 장의 행을
  모델로 다시 읽어 이 변환으로 판정한다(`restoreBackupChapter`).

## 6. 귀속과 계정

### 6-1. 원칙

- 불러온 필기는 **지금 연결된 계정(저장소 소유자)의 것**이다. 파일을 만든 계정은 보지 않는다 — 파일에 계정 정보가 없다(§2-3). 다른 Apple 계정이 만든 파일도
  파일과 암호가 있으면 불러온다(정책 §7-4). 개인정보는 암호화로 다루고, 계정 문자열 비교를 접근 통제로 삼지 않는다.
- **연결되지 않은 실행**(로그인 안 함 · 계정 미확인 · 소유 근거 없음 · 삭제 기준점을 읽지 못함 · 연결 보류)은 **검사 · 미리보기만** 한다. 적용 버튼 대신 사유와
  할 일을 보인다 — 대개 「iCloud 에 로그인한 뒤 앱을 다시 열면 불러올 수 있어요.」 다(2.0.0 은 실행 중에 저장소 연결을 바꾸지 않는다 — 다시 열면 연결된다).

### 6-2. 대상 계정 범위 — `targetScope`

- 검사 때 환경에서 정한다(`LiveBackupImporter.targetScope(for:)`): 계정이 확인됐고(`.confirmed(scope)`) `storeOwnership == scope` 이며 `SyncedWriteBlock.check(env) == nil`
  이면 그 `AccountScope`, 아니면 nil(미리보기만 — 그때의 사유는 `BackupInspection.writeBlock`).
- `BackupInspection` 과 기기 안 작업 기록에 묶는다. **백업 파일에는 넣지 않는다.**
- 적용은 **장마다 최신 환경**(`current()`)을 읽어 `check == nil` 이고 `storeOwnership == targetScope` 일 때만 그 장을 쓴다(§4-3). 검사 때 읽은 환경 하나로는
  적용 도중의 로그아웃 · 계정 변경을 모른다.
- 장을 쓴 뒤 서버 작업 표가 무효(`isCurrent == false`)면 다음 장으로 가지 않는다.

### 6-3. 작업 기록과 이어 하기 — `BackupImportJobStore`

- 위치: `Application Support/BackupImport/<jobID>/` 아래 `job.json`(`BackupImportJobRecord`)과 `backup.carvebackup`(고른 파일의 **암호화된 사본**). 평문 작업 폴더
  (`BackupWork` — 앱 시작 때 통째로 지운다)와 따로 둔다 — 이어 하려면 앱을 다시 열어도 남아야 해서다. `job.json` 은 `DurableFile` 로 쓰고(장치까지 내린 뒤 이름
  바꾸기), 부모 폴더는 기기 백업에서 뺀다(이 기기의 작업 상태다). 작업 id 는 UUID 문자열만 받는다 — 밖에서 받은 id 로 폴더 밖을 가리키지 못하게.
- 남기는 것: `jobID` · `targetScope` · 상태(`inspected` · `applying` · `stopped`) · 끝난 장(`doneChapters`) · 실제 수(`tally`) · 적용할 장 수 · 시각, 그리고 암호화 사본.
  평문 · 암호는 남기지 않는다 — 그래서 이어 할 때 암호를 다시 묻는다. `AccountScope` 는 이 기기 안 작업 기록에만 있다.
- 검사가 작업 기록을 만들고(`inspected` — 미리보기만 하는 검사도), 적용을 시작하지 않고 닫으면 지운다. 적용을 시작하면 `applying`, 멈추면(막힘 · 계정 바뀜 ·
  세대 바뀜 · 쓰기 실패 · 취소) `stopped` 이고 둘 다 이어 하기 대상이다. 적용을 시작하면 이 작업 밖의 기록은 지운다 — 작업 기록은 늘 하나다.
- `pendingJob()` 은 적용을 시작한 끝나지 않은 작업 중 가장 최근 것 하나(`BackupImportJob`)를 내놓고, **지금 환경의 계정 범위가 `targetScope` 와 같을 때만**
  `canResume` 이다 — 「이어서 불러오기」: 암호 → `resume(_:password:)`(같은 작업 id 로 사본을 다시 검사) → 끝난 장을 건너뛰고 적용.
  끝난 장이 남는 것은 쓰기 실패 · 취소 · 앱 종료로 멈춘 경우뿐이다 — 막힘 · 계정 바뀜 · 세대 바뀜은 끝난 장을 비워 처음부터 다시 판정한다(위 2 · 3).
- 다르면 이어 하지 않는다 — **A 계정에서 일부 적용한 작업을 B 계정 저장소에 잇지 않는다**(`resume` 은 `jobFromOtherAccount`). 「버리기」(`discard(_ job:)`) 또는
  「이 계정으로 처음부터」(`restart(_:password:)` — 사본을 새로 검사해 새 작업 · 새 `targetScope` 를 만들고, 새 검사가 되면 옛 작업을 지운다)만 보인다(지금 연결되지
  않았으면 처음부터 해도 미리보기까지다).
- 화면(`BackupCopy.pendingJob…`): 같은 계정이면 「멈춘 불러오기가 있어요」 와 「N장 중 M장까지 넣었어요 · 넣은 필사 K개」 · 「이어서 불러오면 남은 장부터 넣어요.
  암호는 저장하지 않아서 백업 암호를 다시 입력해야 해요.」. 지금 연결된 다른 계정이면 「다른 iCloud 계정에서 시작한 불러오기예요」. 지금 연결되지 않았으면 어느
  계정인지 견줄 수 없어 다른 계정이라 단정하지 않고 「멈춘 불러오기를 지금은 이어서 할 수 없어요」 + 사유. 버리기는 「버리면 멈춘 불러오기의 기록과 이 iPad에 남겨
  둔 백업 사본만 지워요. 이미 넣은 필사는 그대로 있어요.」
- 끝나거나(`.completed`) 버리면 암호화 사본과 기록을 지운다.

### 6-4. 내보내기의 계정

- 계정 상태를 묻지 않고 만든다 — 미로그인 · 연결 보류 실행도 그 기기의 행과 `acct-local` 초안을 담는다(결정 2).
- 시작 때 계정 상태 · 저장소 소유 · 여는 묶음을 적어 두고(`BackupExportEnvironmentBasis`) **장마다 다시 읽어 다르면 `accountChanged` 로 멈춘다**(§3-2) — 계정이
  바뀌면 여는 초안 묶음이 바뀌어, 두 계정의 초안이 한 파일에 섞일 수 있기 때문이다. 계정은 그대로인데 저장소 소유 근거가 바뀌거나 로그아웃해도 같다.

## 7. 알려진 한계 · 후속

| 한계 | 내용 |
|---|---|
| 두 기기가 오프라인으로 같은 파일을 넣음 | 각 기기가 자기 저장소로 판정해 둘 다 넣는다. `rowUUID` 를 늘 새로 발급하므로 연결 뒤 **같은 내용 행이 둘**이 된다. 「이전 필사 내용 보기」 는 같은 내용 행을 하나로 보이고(`VerseDrawingHistoryDedup` — 목록에서만, 남기는 행은 대표 규칙으로 고른다. 저장소 행은 그대로이고, 남긴 행을 고르면 `updatePresentDrawing` 이 숨긴 같은 내용 행도 대표에서 내린다), 둘 다 현재 행이어도 대표 규칙이 결정적이라 화면은 같다. 파괴적인 중복 정리는 하지 않는다(정책 §7-3) |
| 권 · 장 · 절을 알 수 없는 행은 담지 않는다 | 권 이름을 풀 수 없거나(2026-10-06 부터 `StoredBookKey.decode` — 영어 행 `KJV-…` · `BSB-…` 는 풀린다) 장 · 절 번호가 없는 `BibleDrawing` 행은 절 키(권 코드 · 장 · 절)를 만들 수 없어 내보내기에서 빠지고, **수만 로그에 남긴다**(`backupChapterList` · `backupRows` — 2026-10-06 내보내기 구현 때 정함). 편집 화면 · 이력 화면에도 보이지 않는 행이라 사용자가 보던 필사가 빠지지는 않지만, 「원본 그대로 전부」 의 예외다. **후속:** 실사용 저장소에 그런 행이 있는지 로그 수로 보고, 있으면 다음 `formatVersion` 에서 원본 키를 그대로 담을지 정한다 |
| 절 번호의 상한은 보지 않는다 | 지원 판정의 `outOfRange` 는 장이 `1...lastChapter` 인지와 절이 1 이상인지만 본다. 그 장의 마지막 절은 본문(`BibleText`)을 읽어야 알 수 있어 순수 판정에서 보지 않는다 — 손으로 고친 파일에 마지막 절보다 큰 절 항목이 있으면 화면에 보이지 않는 행으로 들어갈 수 있다 |
| 행 없는 절에 보이지 않던 필기가 보임 | 그 절에 행이 하나도 없고 현재 후보가 없으면, 원래 기기에서 보이지 않던 초안 · 보관 항목도 보관 행으로 들어가 대표 규칙대로 가장 늦은 것이 보인다. 빈 자리 행은 나중에 도착하는 legacy 행을 가려 만들지 않는다(§5-1 「행 없는 절」) |
| `ChapterCanvasFeature` 의 `type_body_length` 경고 | flush 완료 신호를 넣으며 리듀서 본체가 **308줄**(경고 300 · 에러 400)이 됐다 — State 필드 하나 · Action 둘 · 판정 호출 넷만 더하고 처리는 `ChapterCanvasBackupFlushFeature.swift` 로 뺐지만 경고는 피하지 못했다(2026-10-06 flush 신호 구현). lint error 는 아니다(`file_length` 경고는 그 전부터 있었다). **후속:** 2.1 백업 범위 밖의 별도 리팩토링에서 본체의 다른 갈래를 `ChapterCanvas*Feature.swift` 로 나눈다 |
| 내보내기 직전 0.3초 안의 미보고 획 | flush 인계는 획이 끝난 뒤 PencilKit 반영 시간(`editSettleInterval` 0.3초)을 두고 캔버스 내용을 찍는다. 그 안에 PencilKit 이 아직 반영하지 않은 획은 단일 캔버스의 기존 한계와 같아 빠질 수 있다(정책 §12-1 · §12-3 「디스크 커밋 전 마지막 변경까지 저장됐다고 약속하지 않는다」). 계약이 보장하는 것은 **보고된 마지막 revision** 까지다 |
| CloudKit 원자성 아님 | 장 하나의 트랜잭션은 이 기기 저장소의 원자성이다. 다른 기기는 한 장의 행을 나눠 · 순서 없이 받을 수 있고, 이미 올라간 행은 로컬 되돌리기로 모든 기기에서 거두지 못한다(정책 §7-2). 그래서 멈춰도 쓴 장은 되돌리지 않는다 |
| V6 미개방이라 계보 없음 | `parents` 가 비어 있다. 두 기기의 분기를 계보로 가리지 못하고 대표 규칙(`isPresent` → `updateDate`)이 정한다 — 현재 후보 선택 · 지운 절 보호도 기기 시각 비교라 시계가 크게 어긋나면 틀릴 수 있다(정책 §8 시계 차이). 버전 저장을 열면 이 행들은 legacy 원본으로 수용된다(정책 §12-6 C3) |
| 즐겨찾기 스냅샷 제외 | 즐겨찾기 · 위젯은 추가할 때의 사본이라 담지 않는다. 즐겨찾기에만 남은 필사는 이 백업으로 되살릴 수 없다 — 안내 문구가 「즐겨찾기 · 설정 · 위젯은 담지 않아요」 라고 말한다(정책 §6-3) |
| Files 앱에서 눌러 열기 없음 | 문서 타입 선언 · 「이 앱으로 열기」 는 2.1 범위 밖이다. 설정 → 필사 백업 → 「백업 불러오기」 에서 파일을 고른다 |
| 「모든 필사 삭제」 뒤의 옛 백업 | 전체 삭제는 기준점을 남기지 않으므로(V6 미개방) 그 뒤 옛 백업을 불러오면 지운 필사가 그대로 들어온다. 사용자가 고른 명시적 복구로 본다(정책 §8 「영구 삭제와 과거 백업」). 오프라인 기기가 옛 행을 다시 올리는 재등장(정책 §12-5 C11)과는 별개다 |

## 8. 시험

### 8-1. 단위 · 저장소 시험 (Swift Testing, 시뮬레이터 iPad)

각 칸을 실제로 보는 스위트는 §9-1 이다.

| 영역 | 확인할 것 |
|---|---|
| 형식 | 인코딩 왕복(`sortedKeys` · 같은 내용 같은 바이트 · `Date` 소수 초 손실 없음), 모르는 키 무시, `formatVersion` ≠ 1 거부, 이름 허용 목록 · 경로 이탈, 상한, `counts` · blob 크기 · 해시 불일치 거부, `BibleBookCode` 66권 양방향, `BackupItemID` 의 안정성과 구성요소 경계(길이 접두) |
| 컨테이너 | 암호 왕복, 잘못된 암호 · 변조 · 잘림 → `wrongPasswordOrDamaged`, 링크 · 이탈 항목 거부, 푸는 도중 상한, 작업 폴더 정리 · `removeStale()`, **iPadOS 17.5 에서 scrypt 프로필 동작** |
| 내보내기 | 행 원본 보존(v1 · v2 · v3 · nil · 비운 · 보관), 대표 행 `isCurrent`(비운 대표 포함), 초안 분류 표(§3-4) 전 칸, 다른 계정 묶음 · `raw/` · `separation/` · `*.unreadable-*` 제외, 장 사이 세대 변경 → `generationChanged`, 장 사이 계정 변경 → `accountChanged`, 같은 바이트 blob 한 번, 다시 열어 대조 |
| 판정기 | §5-1 표의 모든 칸, 「비운 현재 + 잉크 보관」 세 경우, 지운 절 보호의 앞뒤 시각, 현재 후보 여럿(시각 · id 동률), 같은 지문 항목 둘, 번역 null 과 NKRV 한 묶음, 지원하지 않는 항목 사유별 수 |
| 복원 · 불러오기 | 넣은 행의 바이트 · `drawingVersion` · 시각 · 번역값 원본 그대로, `rowUUID` 새 발급, 있는 행 무변경, 장 한 트랜잭션, 세대가 다르면 쓰지 않음, 쓰기 직전 재판정, 장마다 환경 — 차단 · 계정 변경이면 그 장부터 0건, 쓴 뒤 표 무효면 멈춤, `LocalDrawingChange` 발신, 반복 불러오기 추가 0건, 작업 기록 · `pendingJob` 의 계정 일치 |
| flush | 미저장분 없음 → `.durable`, 디바운스 · 인계 대기 뒤 `.durable`, 저장 실패 → `.failed`, 5초 → `.timedOut`(`TestClock`), 다른 id 무시 — 경쟁이 있어 **세 번 반복**해 흔들리지 않음을 본다 |
| 설정 리듀서 | 구매 게이트, 암호 두 번 · 8자, flush 대기 · 10초 시간 제한 · 다시 시도, 저장 · 취소 · 실패 구분, 기본 파일 이름 날짜(`$0.date = .constant(…)`), 미리보기 · 쓰기 게이트 사유, 이어 하기 · 버리기 · 처음부터 |

시각은 `@Dependency(\.date)` · `TestClock` 으로 고정한다. 시험 잉크는 고정 바이트 `Data` 로 충분하다(`PKDrawing` 바이트는 만들 때마다 달라진다).
iOS 17 에서 `@Model` 은 `ModelContainer` 안에서만 만든다. 의존성 `testValue` 에 공유 SwiftData actor 를 쓰지 않는다.

### 8-2. 왕복 (자동)

v1 · v2 · v3 · nil · 비운 · 보관 행 · 초안 → 내보내기 → 빈 저장소에 불러오기:

- `lineData` · 메타데이터 바이트(키 순서까지) · `drawingVersion` · `creationDate` · `updateDate` · 번역 저장값 · 지문이 같다. 대표가 규칙대로다.
- **비운 현재 + 잉크 보관 → 비운 행이 대표로 남는다.**
- 같은 파일을 다시 불러오면 추가 0건이다.
- 적용 중 계정 변경 → 그 장부터 0건 · A 계정 작업을 B 계정에서 이어 하지 않는다. 내보내기 장 사이 계정 변경 → 실패.
- flush 결과가 `.durable` 이 아니면 내보내기를 시작하지 않는다.
- 잘못된 암호 · 변조 · 잘림 · 상한 초과는 저장소를 바꾸기 전에 거부한다.

구현(2026-10-06): `BackupRestoreRoundTripTesting` 이 ① 형식 타입으로 만든 파일(v3 · 「비운 현재 + 잉크 보관」 · v2 · 좌표 형식과 번역 null · 초안 · v1 · 외부 저장으로
빠질 큰 잉크)과 ② `LiveBackupExporter` 가 만든 파일(v3 대표와 보관 · 「비운 현재 + 잉크 보관」 · business id 행 키의 v2 · 번역 · 좌표 형식 · 시각 null)을 빈 저장소에
불러와 원본 · 대표를 본다. 초안을 내보내는 쪽은 `BackupExportDraftTesting` 이 따로 본다(②에는 초안이 없다). 나머지 줄은 §9-1 의 불러오기 · 내보내기 · flush 스위트다.

### 8-3. 기기 · 시뮬레이터 — [시험 계획](./icloud-sync-compatibility-test-plan.md) 단계 D

새 iPad 시뮬레이터에서 하고 끝나면 지운다(CloudKit 표본이 든 기기는 쓰지 않는다). 결과는 시험 계획의 ID 로 적는다. 화면은 실행 인자 `-UITestRoute settings/backup` 으로
바로 연다. ID 마다 대응하는 자동 시험은 시험 계획 단계 D 표의 「자동 시험 대응」 열에 있고, 기기에서만 볼 수 있는 것은 §9-2 다.

| ID | 무엇을 보나 |
|---|---|
| BACKUP-D1 · D2 | 빈 저장소 왕복 · 기존 필사 위에 불러오기 · 반복 0건 |
| BACKUP-D3 | 두 기기 오프라인 같은 파일 — 같은 내용 행 둘, 기록에서 하나 |
| BACKUP-D4 | 잘못된 암호 · 변조 · 잘림 · 미지원 형식 · 상한 |
| BACKUP-D5 | 미로그인 · 보류 실행은 미리보기까지, 연결 뒤 적용 |
| BACKUP-D6 | 중단 → 「이어서 불러오기」 |
| BACKUP-D7 | 구매자 · 미구매 |
| BACKUP-D8 | 미로그인 기기의 초안(`acct-local`)이 담기고 다른 기기에서 불러진다 |
| BACKUP-D9 | 모르는 번역본 · 권 · 좌표 형식 항목은 건너뛰고 수로 보인다 |
| BACKUP-D10 | 지운 절(비운 대표가 더 늦음)에는 보관으로만 |
| BACKUP-D11 | 비운 현재 + 잉크 보관 → 비운 상태가 대표로 남는다 |
| BACKUP-D12 | 적용 중 로그아웃 · 계정 변경 → 그 장부터 멈춤, 다른 계정에서 이어 하지 않음 |
| BACKUP-D13 | 마지막 획 직후 내보내기 — flush 완료 뒤에만 시작, 저장 실패면 막힘 |
| NCANVAS-U1 | 토글 OFF 2.0.x → 2.1 업데이트(N-Canvas 제거 — 백업과 같은 2.1 검증이라 함께 둔다) |

## 9. 구현 상태 (2026-10-06)

통합 브랜치 `claude/dag-carve-21-backup` 의 레이어 0 ~ 4(형식 코어 · 컨테이너 · 내보내기 · flush 신호 · 판정기 · 복원과 작업 기록 · 설정 화면 · 앱 연결 ·
이전 필사 기록 중복 표시)가 들어간 코드를 이 문서와 대조했다. 공통 규칙(plan 노트 「Carve 2.1 N-Canvas 제거 · 필사 백업 · 불러오기」)과 이 문서가 다르던 곳은
공통 규칙을 따라 위 절을 고쳤다 — 암호 표기(§2-1) · 메타데이터 없는 v3 · `outOfRange`(§5-1) · `maxIndexBytes` · `maxEntryCount`(§2-8) · 대표 고정(§4-3 · §5-1).
룰북 예외는 늘지 않았다 — `.swiftlint.yml` 의 `excluded` 는 N-Canvas 제거로 셋 줄었고, 새 코드에 `nonisolated(unsafe)` · `@unchecked Sendable` · `UncheckedSendable` ·
`@preconcurrency` · `MainActor.assumeIsolated` 가 없다. 기준선 수는 [회귀 기준선](./regression-baseline.md) 한 곳에 둔다.

### 9-1. 무엇이 어디 · 자동 시험

시험 타깃은 `DomainTest` · `CarveFeatureTest` · `SettingsFeatureTest` · `CarveAppTest` 이고, 이름은 Swift Testing 스위트 타입이다(`-only-testing:<타깃>/<스위트>`).

| 영역 | 구현 | 자동 시험 |
|---|---|---|
| 형식 상수 · 인코딩 · 항목 id · 권 코드 | `Sources/Backup/Format/` — `BackupFormat` · `UTType.carveBackup` · `BackupManifest` · `BackupItem` · `BackupItemID` · `BibleBookCode` | `DomainTest` — `BackupFormatEncodingTesting` · `BackupFormatItemIDTesting` · `BackupFormatBookCodeTesting` |
| 형식 검증 · 상한 · 지원 판정 | `BackupPayload` · `BackupPayloadValidator` · `BackupLimits` · `BackupFormatError` · `BackupItemSupport` | `DomainTest` — `BackupFormatValidatorTesting` · `BackupFormatSupportTesting` |
| 백업 전용 조회 | `BackupRowRecord` · `BackupRowLoad` · `SwiftDatabaseActor+Backup.swift`(`backupChapters()` · `backupRows(chapter:)` · `backupChapterList()` · `BibleDrawing.backupRecord`) | `DomainTest` — `BackupFormatRowRecordTesting` · `BackupExportRowTesting`(「백업 전용 조회 — …」) |
| 컨테이너 · 암호 표기 · 작업 폴더 | `Sources/Backup/Archive/` — `BackupArchive` · `BackupArchiveEntry` · `BackupArchivePassword` · `BackupArchiveFileSink` · `BackupDiskSpace` · `BackupWorkDirectory` | `DomainTest` — `BackupArchiveRoundTripTesting` · `BackupArchiveDamageTesting` · `BackupArchiveRejectionTesting` · `BackupArchiveWriteFailureTesting` · `BackupArchiveWorkDirectoryTesting` |
| 내보내기 | `Sources/Backup/Export/` — `BackupExporting` · `LiveBackupExporter` · `BackupExportItems` · `BackupExportDraftSelection` · `BackupExportStaging` · `BackupExportVerification` · `BackupExportFileName` | `DomainTest` — `BackupExportRowTesting` · `BackupExportDraftTesting` · `BackupExportFlowTesting` |
| 판정기 · 미리보기 · 대표 고정 | `Sources/Backup/Import/` — `BackupImportPlanner` · `BackupImportPlan.swift`(`BackupImportDecision` · `BackupRowInsertion` · `BackupRepresentativePin` · `BackupChapterPlan`) · `BackupImportPreview` | `DomainTest` — `BackupImportPlanInkTesting` · `BackupImportPlanClearedTesting` · `BackupImportPlanPinTesting` · `BackupImportPlanPreviewTesting` |
| 장 단위 복원 쓰기 | `DrawingBackupRestoring` · `SwiftDataDrawingRepository+BackupRestore.swift`(`SwiftDataDrawingBackupRestorer` · `restoreBackupChapter`) | `DomainTest` — `BackupRestoreTransactionTesting` |
| 불러오기 · 작업 기록 · 왕복 | `BackupImporting` · `LiveBackupImporter`(+`Apply`) · `BackupImportJobStore` | `DomainTest` — `BackupImporterFlowTesting` · `BackupImporterCleanupTesting` · `BackupRestoreRoundTripTesting` |
| 캔버스 flush 신호 | `ChapterCanvasBackupFlushFeature.swift`(`BackupFlushRequest` · `backupFlushTimeout` 5초) · `ChapterCanvasFeature`(State `backupFlush` · Action 둘 · 판정 호출 넷) · `ChapterCanvasVerseMenu.swift`(`Delegate.backupFlushFinished`) | `CarveFeatureTest` — `ChapterCanvasBackupFlushTesting` · `ChapterCanvasBackupFlushOutcomeTesting` |
| flush 중계 · 실행 경로 | `AppCoordinatorFeature`(`relayBackupFlushRequest` · `settings/backup`) | `CarveAppTest` — `AppCoordinatorBackupFlushTesting` · `AppCoordinatorLaunchRouteTesting`(「settings/backup — …」) |
| 설정 「필사 백업」 화면 | `BackupFeature` · `BackupView` · `SettingsFeature`(`SidebarItem.backup` · `Path.backup` · `canvasFlushFinished`) · 2.1 패치노트 | `SettingsFeatureTest` — `BackupFeatureTesting` |
| 「백업 만들기」 | `BackupExportFeature` · `BackupExportView`(`BackupFileItem`) · `BackupCopy` | `SettingsFeatureTest` — `BackupExportFeatureTesting` · `BackupExportFlushTesting` |
| 「백업 불러오기」 | `BackupImportFeature`(+`Work`) · `BackupImportView` · `BackupFileAccessClient` · 불러오기 문구(`BackupCopy` 확장) | `SettingsFeatureTest` — `BackupImportFeatureTesting` · `BackupImportOutcomeTesting` · `BackupImportResumeTesting` |
| 이전 필사 기록의 같은 내용 하나로 | `VerseDrawingHistoryDedup` · `VerseDrawingHistoryFeature` | `CarveFeatureTest` — `VerseDrawingHistoryDedupTesting` |
| 앱 조립 | `App.swift`(같은 `SwiftDatabaseActor` 로 `\.drawingBackupRestorer` · `\.backupExporter` · `\.backupImporter` 주입, 시작 때 `removeStale()`) · `InfoPlist.swift`(`UTExportedTypeDeclarations`) · `PrivacyInfo.xcprivacy`(DiskSpace `E174.1`) | 자동 시험 없음 — `CarveAppTest` 는 `App.swift` 를 컴파일하지 않는다. 각 태스크 커밋 기록: 앱 Debug 빌드, 새 기기 스모크(`-UITestRoute settings/backup` 로 화면 표시 · 시작 때 `tmp/BackupWork` 정리), 빌드된 앱 Info.plist 의 형식 선언(위젯 appex 에는 없음) |
| N-Canvas 제거(NCANVAS-U1 의 자동 부분) | 단일 캔버스가 2.0.x 의 N-Canvas 행(v1 · v2 · v3→v2)을 읽고 이어 쓰는 경로, `AppCoordinatorFeature` 의 「필사 캔버스」 를 끈 사용자 안내(한 번 · 키 정리) | `CarveFeatureTest` — `NCanvasRowsAfterRemovalTesting` · `CarveAppTest` — `AppCoordinatorCanvasRemovalNoticeTesting` |

- 시각은 `@Dependency(\.date)` · `TestClock`, 저장소 시험은 시험마다 자기 컨테이너 · 작업 폴더(`removeStale(under:)` — 실제 `removeStale()` 은 병렬 시험을 간섭해
  부르지 않는다)를 쓴다. 의존성 `testValue` 셋(`\.backupExporter` · `\.backupImporter` · `\.drawingBackupRestorer`)은 nil 이다 — 공유 SwiftData actor 를 쓰지 않는다.
- iPadOS 17.5 새 기기에서도 돌렸다(각 태스크 커밋 기록): 컨테이너 5 스위트 38/38(scrypt 프로필 · iOS 17 `close()` 우회), 내보내기 3 스위트와 `BackupFormatRowRecordTesting`
  25/25(`propertiesToFetch` 포함), 불러오기 · 복원 4 스위트 29/29. flush 시험은 경쟁이 있어 `CarveFeatureTest` 를 세 번 잇달아 돌려 흔들리지 않음을 봤다(§8-1).

### 9-2. 남은 수동 확인

자동 시험은 규칙 · 흐름 · 저장소 쓰기를 본다. 아래는 기기(새 iPad 시뮬레이터 · 실기기)에서만 볼 수 있어 남았다 — 결과는 [시험 계획](./icloud-sync-compatibility-test-plan.md)
단계 D 의 ID 로 적는다.

| 남은 것 | 시험 계획 ID | 왜 자동 시험으로 끝나지 않나 |
|---|---|---|
| 실제 시스템 창 — 저장 창(`fileExporter` · iCloud Drive 제공자에 저장), 파일 고르기 창(`fileImporter`) · 보안 범위 접근 · 내려받지 않은 파일 | D1 · D2 · D4 · D8 | 리듀서 시험은 창의 결과를 액션으로 넣는다 — 창 · 제공자 · 실제 보안 범위 URL 은 기기에서만 있다 |
| 화면의 대표 · 「이전 필사 내용 보기」 표시(왕복 · 반복 0건 · 지운 절 · 비운 현재 + 잉크 보관 · 대표 고정) | D1 · D2 · D10 · D11 | 저장소 행과 대표 규칙은 시험이 보지만, 캔버스 · 이력 화면에 실제로 그렇게 보이는지는 화면에서 본다 |
| 두 기기 오프라인 같은 파일 → 연결 | D3 | 실제 CloudKit 동기화와 두 번째 기기가 필요하다 |
| 미로그인 · 연결 보류 → 로그인 · 앱 다시 열기 → 적용, 적용 중 로그아웃 · 계정 변경, A → B 계정 이어 하기 금지 | D5 · D6 · D12 | 환경은 시험 대역으로 바꿨다 — 실제 계정 전환 · 연결 보류 · 앱 재실행은 기기에서만 있다 |
| 광고 제거 기존 구매자 · 미구매 · 구매 복원 실패 | D7 | 시험은 공유 값(`isAdFree`)만 바꾼다 — 실제 StoreKit 상태는 `CarveApp-StoreKit` 스킴 · 기기에서 본다 |
| 미로그인 기기의 `acct-local` 초안을 다른 기기에서 불러오기 | D8 | 초안 분류 · 담기는 시험이 보지만, 두 기기 사이 파일 전달과 표시는 기기에서 본다 |
| 시험 도구로 만든 모르는 번역본 · 권 · 좌표 형식 · 메타데이터 파일 | D9 | 판정 · 미리보기 사유별 수는 시험이 보지만, 그런 파일을 만드는 도구와 화면 표시는 아직 기기에서 확인하지 않았다 |
| 마지막 획 직후 · 저장 실패 상태에서 백업 만들기 | D13 | 실제 PencilKit 획 · 0.3초 반영 시간 · 공간 부족 주입은 기기에서만 있다 |
| 2.0.x(「필사 캔버스」 끔) → 2.1 덮어 설치 | NCANVAS-U1 | 실제 2.0.x 빌드와 업데이트가 필요하다 |
| 상한 실측 — 큰 백업(행 · blob 수 · 크기)을 만들고 불러올 때의 시간 · 메모리 · 남은 공간 | D4(상한) · §2-8 | 초기값을 실측으로 조정하기로 했고(정책 §9-2) 아직 재지 않았다 |
| 실사용 저장소의 「권 · 장을 알 수 없는 행」 로그 수 | — (§7) | 실사용 저장소 로그로만 안다 |
