# 필사 백업 · 불러오기 설계 (2.1)

작성: 2026-10-02 · 목표: **2.1** · 상태: **설계 확정 / 미구현**

> 이 문서는 [iCloud 동기화·오프라인 사용·외부 백업 정책](./icloud-sync-and-backup-policy.md) §6 · §7 의 결정을 2.1 에서 구현하는 **계약**이다.
> 정책 문서는 결정만, 이 문서는 파일 형식 · 흐름 · 판정 규칙 · 시험을 담는다. 「결정 n」 은 2026-10-02 사용자 결정(인터뷰 기록)의 번호이고
> 이 문서에서 다시 정하지 않는다. 코드와 함께 바뀌는 문서다 — 구현 이름 · 상한 실측 · 시험 대응은 구현을 마치며 고친다.
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
| 담지 않는 것 | 즐겨찾기(`FavoriteVerse`) 스냅샷 · 설정 · 위젯 · 구매 상태 · 계정 식별자 · 계정 해시 · 기기 이름 · CloudKit 메타데이터 · `BiblePageDrawing` · 다른 계정 묶음의 초안 · 원시 사본(`raw/`) · 분리본(`separation/`) · 읽지 못한 초안 파일(`*.unreadable-*`) |
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
   권은 USFM 코드, 원본 파일 이름(`titleName`)도 함께 둔다. 불러오기는 아는 번역본(지금 NKRV)과 null 만 넣고 모르는 번역본은 건너뛴다 — 나중에 다른
   번역본 필사가 든 파일을 한국어 절에 섞지 않는다. 권 코드 · 번역본 규칙은 영어 성경 작업(별도 브랜치)에 인터페이스로 넘긴다.

### 1-2. 구현 위치

| 모듈 | 위치 | 맡는 것 |
|---|---|---|
| Domain | `Domain/Domain/Sources/Backup/` | 형식(`BackupFormat` · `BackupManifest` · `BackupItem` · `BackupItemID` · `BibleBookCode` · `BackupLimits` · `BackupPayload` · `BackupRowRecord` · `CanvasFlushOutcome`), 컨테이너(`BackupArchive` · `BackupWorkDirectory`), 내보내기(`BackupExporting` · `LiveBackupExporter`), 판정(`BackupImportPlanner` — 순수), 불러오기(`BackupImporting` · `LiveBackupImporter` · `BackupImportJobStore`) |
| Domain (SwiftData) | `Sources/SwiftData/SwiftDatabaseActor+Backup.swift` · `SwiftDataDrawingRepository+BackupRestore.swift` | 백업 전용 조회(`backupChapters()` · `backupRows(chapter:)`)와 장 단위 복원 쓰기(`DrawingBackupRestoring`). SwiftData API 는 이 폴더 밖에 두지 않는다 |
| CarveFeature | `ChapterCanvasFeature` | flush 완료 신호(`backupFlushRequested` → `backupFlushFinished`) — §5-2 |
| SettingsFeature | `Sources/Details/Backup/` | `BackupFeature` · `BackupExportFeature` · `BackupImportFeature` 와 뷰 · 문구(`BackupCopy`) |
| App | `AppCoordinatorFeature` · `App.swift` | flush 중계, 실제 구현 주입(`\.backupExporter` · `\.backupImporter` · `\.drawingBackupRestorer` — `drawingVerseImporter` 선례), 시작 때 `BackupWorkDirectory.removeStale()`, 개인정보 매니페스트 |

## 2. 파일 형식

### 2-1. 컨테이너

| 항목 | 값 |
|---|---|
| 확장자 | `.carvebackup` (`BackupFormat.fileExtension`) |
| 형식 식별자 | `kr.co.carve.leetaek.backup`(`BackupFormat.typeIdentifier`) — `public.data` · `public.content` 준수. Domain `UTType.carveBackup` = `UTType(exportedAs:)`, 앱 Info.plist 의 내보내는 형식 선언과 짝이다 |
| 바깥 | **Apple Encrypted Archive** — `ArchiveEncryptionContext(profile: .hkdf_sha256_aesctr_hmac__scrypt__none, compressionAlgorithm: .lzfse)` + `setPassword(_:)`(AppleArchive, iOS 15+ — 최소 배포 17 에서 쓸 수 있다). 암호 기반 키 유도(scrypt) · 암호화 · 세그먼트 무결성 · 압축 · 스트리밍을 SDK 가 한다 |
| 안 | Apple Archive. 항목 이름은 `manifest.json` · `items.json` · `blobs/<소문자 SHA-256 hex 64자>` 셋뿐이다 |
| 암호 | 늘 필요하다. 8자 이상, 화면에서 두 번 입력해 맞아야 한다 |

- 암호 알고리즘 · 키 유도 · 컨테이너 형식을 직접 만들지 않는다(정책 §6-5). 같은 파일은 macOS `aea` 명령으로도 풀 수 있어 지원 · 진단에 쓴다(암호는 사용자가 넣는다).
- 읽을 때 위 셋 밖의 이름, 경로 이탈(`..` · 절대 경로), 링크, 풀 폴더 밖을 가리키는 항목은 **저장소를 바꾸기 전에** 거부한다.
- 잘못된 암호 · 변조 · 잘림은 하나의 오류(`wrongPasswordOrDamaged` — 「암호가 맞지 않거나 파일이 손상됐어요」)로 묶어 알린다.

### 2-2. 인코딩 공통

- `JSONEncoder.outputFormatting = [.sortedKeys]` — 같은 내용이면 같은 바이트다. 파일 안 JSON 은 줄바꿈 없는 한 줄이다(아래 예시는 읽기 쉽게 펼쳤다).
- 날짜는 `dateEncodingStrategy = .deferredToDate` — 2001-01-01T00:00:00Z 기준 초(Double)다. `Date` 를 손실 없이 왕복한다(ISO 8601 문자열은 소수 초를 잃는다).
- Optional 은 nil 이면 키가 빠진다(JSONEncoder 기본). 읽을 때는 키 없음과 `null` 을 같게 nil 로 읽는다 — 이 문서의 「null」 은 둘을 함께 말한다.
- 바이트(잉크 · 메타데이터)는 JSON 에 넣지 않고 blob 이름으로 가리킨다(§2-7).
- 읽을 때 모르는 키는 무시한다 — 뒤 버전이 키를 더해도 읽힌다. 단 `formatVersion` 이 1 이 아니면 `unsupportedFormat` 으로 **파일 전체**를 거부한다.

### 2-3. manifest.json — `BackupManifest`

| 키 | 타입 | 뜻 |
|---|---|---|
| `formatVersion` | Int | 백업 형식 버전 `BackupFormat.formatVersion` = 1. 앱 버전 · 스키마 버전과 별개다(정책 §6-3) |
| `backupID` | String | 이 백업의 UUID |
| `createdAt` | Date | 만든 시각 |
| `appVersion` | String | 만든 앱 버전(예: `2.1.0`) |
| `scope` | `BackupScope` | `rows` · `drafts` — 행 · 초안을 담았는가. 2.1 은 전체 백업만 만들어 둘 다 true 다. 선택 백업의 자리(정책 §9-2) |
| `counts` | `BackupCounts` | `rows` · `drafts` · `blobs` 의 수 — 읽을 때 실제 수와 맞아야 한다 |
| `blobs` | [`BackupBlobEntry`] | blob 마다 `name`(64자 hex) · `size`(바이트) · `sha256`(64자 hex). 읽을 때 실제 크기 · 해시가 맞아야 한다 |

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
| `translation` | String? — 행 · 초안에 저장된 값 그대로(`Translation.rawValue`, 지금 `NKRV`). 행에 값이 없으면 null — NKRV 로 채우지 않는다 |
| `book` | USFM 권 코드 `GEN` … `REV` — Domain `BibleBookCode` 가 `BibleTitle` 66권과 1:1 양방향(§2-6) |
| `chapter` · `verse` | Int |

`BackupItemSource`

| 키 | 뜻 |
|---|---|
| `titleName` | `BibleTitle.rawValue` 원문(예: `1-01Genesis.txt`) — 권 코드와 함께 원본을 보존한다 |
| `rowKey` | 행: `rowUUID ?? business id`. 초안: 식별 · 판정에 쓰지 않는다(null 이어도 된다) |
| `draftScope` | 초안만. `"local"`(로그인하지 않은 동안 · `acct-local`) · `"unverified"`(계정을 확인하지 못한 동안 · `acct-unverified`) · `"account"`(확인된 계정 묶음) 중 하나. **계정 해시는 넣지 않는다** |
| `draftRevision` | 초안만. 그 세션 · 절의 revision |

### 2-5. 항목 식별자 — `BackupItemID`

```
정규 문자열 = ["carve.backupItem/1", kind, sourceKey, fingerprint ?? "empty"]
              구성요소마다 "<UTF-8 바이트 길이>:<값>" 으로 바꿔 "|" 로 잇는다
id          = ("row-" | "draft-") + SHA-256(정규 문자열) 소문자 hex 64자
```

- `sourceKey` — 행: `rowKey`(`rowUUID ?? business id`). 초안: `"<draftScope>|<sessionID>|<translation>|<title>|<chapter>|<verse>|<revision>"`.
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

### 2-8. 상한 — `BackupLimits`

| 상한 | 초기값 |
|---|---|
| blob 하나 | 64 MB |
| 풀린 합계 | 4 GB |
| 항목 수 | 200,000 |

- 넘으면 **저장소를 바꾸기 전에** 거부한다. 풀기(`BackupArchive.read(from:password:into:maxEntryBytes:maxTotalBytes:)`)는 `BackupLimits` 를 모르고 원시 값만 받아,
  푸는 도중 넘으면 멈춘다.
- 초기값은 실측으로 조정한다(정책 §9-2 「대용량 파일」). 참고 규모: 실사용 계정 271행 · 잉크 평균 15.3 KB · 최대 111 KB(정책 §3-2).

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
| 1 | **권한** — `isAdFree` 가 아니면 만들기 대신 광고 제거 안내를 보인다. 불러오기는 그대로 열린다 | — |
| 2 | **안내** — 「이 기기에 저장된 필사를 백업해요. 아직 동기화되지 않은 다른 기기의 필사는 포함되지 않을 수 있어요. 즐겨찾기 · 설정 · 위젯은 담지 않아요.」 · 「암호를 잊으면 Carve 도 이 파일을 열 수 없어요.」 | — |
| 3 | **암호** — 두 번 입력, 8자 이상, 둘이 같아야 한다. 시스템 암호 자동 완성(새 암호 제안 · 암호 관리자 저장)은 막지 않는다. Carve 는 암호를 저장 · 기록하지 않는다 | 맞지 않으면 그 자리에서 안내 |
| 4 | **flush** — 필사 화면의 마지막 편집이 이 기기에 내구성 있게 남았는지 확인한다(§5-2) | `.durable` 이 아니면 시작하지 않는다 — 「필사 화면에 아직 저장하지 못한 필기가 있어요. 필사 화면에서 저장을 다시 시도한 뒤 백업해 주세요.」 + [다시 시도] |
| 5 | **장 단위 읽기 · 쓰기** — §3-2. 평문은 작업 폴더(`BackupWorkDirectory` — `FileManager.temporaryDirectory/BackupWork/<UUID>/`)에만 두고, 다 모으면 `BackupArchive.write(stagedDirectory:to:password:)` 로 암호화 파일 하나를 만든다 | `generationChanged` · `accountChanged` · 쓰기 실패 · 공간 부족 — 사유와 [다시 시도] |
| 6 | **검증** — 다 쓴 파일을 같은 암호로 다시 열어 manifest · 건수 · blob 크기 · 체크섬 · 항목이 가리키는 blob 을 대조한다. 맞을 때만 성공이다(정책 §6-1 3) | 검증 실패 — 파일을 내놓지 않는다 |
| 7 | **저장 위치** — SwiftUI `fileExporter` 로 사용자가 고른다. 기본 이름 「새기다 필사 백업 YYYY-MM-DD.carvebackup」(날짜는 `@Dependency(\.date)`) | 사용자 취소 |
| 8 | **결과** — 저장 · 취소 · 실패를 따로 보인다(`BackupExportResult` 의 `fileURL` · `counts` · `backupID`). iCloud Drive 같은 제공자에 저장하면 앱의 저장 성공과 그 제공자의 업로드 완료는 별개다(정책 §6-1) | — |
| 9 | **정리** — 성공 · 실패 · 취소 모두 작업 폴더를 지운다 | — |

네트워크 없이 만들 수 있다. 계정 상태도 묻지 않는다 — 미로그인 · 연결 보류 실행도 그 기기의 행과 열 수 있는 초안을 담는다(§6-4).

### 3-2. 장 단위 읽기 (`LiveBackupExporter.export(password:progress:)`)

1. 시작할 때 `DrawingEditEnvironmentClient.current()` 로 환경을 읽어 **계정 상태 · 저장소 소유 · 여는 묶음**(`readableDraftScopes ∪ beforeConnectionDraftScopes`)을 적어 둔다.
2. 장 목록 = `SwiftDatabaseActor.backupChapters()`(행이 있는 장) ∪ 여는 묶음에 초안이 있는 장.
3. 장마다:
   1. `current()` 를 다시 읽는다. 계정 상태 · 저장소 소유 · 여는 묶음이 시작 때와 다르면 **`accountChanged` 로 실패**한다 — 다른 계정 초안이 한 파일에 섞이지 않게.
   2. `SwiftDatabaseActor.backupRows(chapter:)` 가 그 장의 `BackupRowRecord` 목록과 저장소 세대를 **같은 actor 구간에서** 돌려준다(`BackupRowLoad`).
      세대가 첫 장과 다르면(그 사이 「모든 필사 삭제」) **`generationChanged` 로 실패**한다.
   3. 그 장의 초안을 분류한다(§3-4) — 위 행을 저장소 쪽 입력으로 쓴다.
   4. 항목과 blob 을 작업 폴더에 쓴다. 같은 바이트의 blob 은 한 번만 쓴다.
   5. 진행을 알린다(`BackupProgress(done:total:)`).
4. 일관성은 **장 단위**다. 절이 충돌 단위이고(정책 §12-3) 한 장은 한 actor 구간에서 읽으므로 한 행의 잉크와 메타데이터가 다른 시점에서 섞이지 않는다.
   장 사이에 iCloud 에서 받은 변경은 뒤 장에만 담길 수 있다 — 정책 §6-1 2 의 「일관된 읽기 스냅샷」 을 장 단위로 좁힌 것이다.

### 3-3. 행 항목

- 그 장의 모든 행(현재 · 보관 · 비운 행)을 `kind = "row"` 로 **원본 그대로** 담는다 — 바이트 · `drawingVersion` · 시각 · 번역 저장값을 바꾸지 않는다.
- 절마다 `DrawingRepresentativeRule.pick` 의 대표 행만 `isCurrent = true` 다(`isPresent` → `updateDate` → 행 키). 대표가 비운 행이어도 true 다(§5-1 「비운 대표 행」).
  그 절에 shown 초안이 있으면 그 절의 행은 모두 false 다 — 그 기기 화면에 보이던 것은 초안이기 때문이다.

### 3-4. 초안 분류

입력은 「확인이 필요한 필기」 목록(`VerseDraftRecoveryQuery.inventory`)과 같다. 편집 화면이 읽는 묶음은 `VerseDraftRecoveryRule.screenDrafts` →
`plan(sessionID: nil, …)` 로(지금 편집 세션 없이 — 모든 초안을 다른 세션의 것으로), 확인된 계정의 연결 전 묶음은 `beforeConnectionDrafts` → `importPlan` 으로 가른다.
저장소 쪽 입력(절마다 대표 내용 · 행 · 이력 지문)은 §3-2 의 `BackupRowLoad` 에서 만든다.

| 분류 | 판정 | 담나 | `isCurrent` |
|---|---|---|---|
| `settled` — 내용이 이미 저장소에 있다 | `plan` | 뺀다 | — |
| `shown` — 그 장을 열면 화면에 겹친다 | `plan` | 담는다 | true (그 절의 행은 모두 false) |
| `kept` — `recoverable` · `uncertain` · `undisplayable` · `archived` 를 포함 | `plan` | 담는다 | false |
| 연결 전 필기 — `awaiting` · `undisplayable` · `archived` | `importPlan` | 담는다 | false |
| 연결 전 필기 — `settled`(지금 필사와 같거나 이미 가져옴) | `importPlan` | 뺀다 | — |
| 다른 계정 묶음 | 열지 않는다 | 뺀다 | — |
| 원시 사본(`raw/`) · 분리본(`separation/`) · 읽지 못한 초안 파일(`*.unreadable-*`) | — | 뺀다 | — |

- 보이지 않던 초안(`isCurrent = false`)은 불러와도 대표가 되지 않고 이전 필사 기록(보관)으로 들어간다 — 원래 기기에서도 화면에 보이지 않던 것이다.
- 미로그인 기기의 여는 묶음은 `acct-local` 하나다. 확인된 계정 실행은 그 계정 묶음 + `acct-unverified`(편집 화면) + 연결 전 묶음(`acct-local` · 참고 계정 없는
  `acct-unverified`)이다. 묶음은 `source.draftScope` 에 `"local"` · `"unverified"` · `"account"` 로만 남는다.
- `acct-unverified` 는 두 판정에 모두 들지만 초안의 참고 계정(힌트)으로 갈려 겹치지 않는다 — 지금 계정 힌트는 편집 화면 쪽(`reachesScreen`), 힌트 없음은 연결 전
  필기(`awaitsImport`), **다른 계정 힌트는 어느 쪽에도 들지 않아 담지 않는다**(다른 사람의 필기일 수 있다 — P0-1).
- 초안 파일을 읽지 못한 장이 있으면 그 장을 조용히 빼지 않고 내보내기를 실패로 끝낸다(구현에서 오류 이름을 정한다) — 담았다고 말한 범위와 실제 파일이 달라지지 않게.

## 4. 불러오기 흐름 — 「백업 불러오기」

### 4-1. 단계

| # | 단계 | 저장소 |
|---|---|---|
| 1 | **파일 고르기** — SwiftUI `fileImporter(allowedContentTypes: [.carveBackup])` | 그대로 |
| 2 | **복사** — 보안 범위 접근 동안 앱 작업 영역으로 먼저 복사하고 접근을 닫는다. 크기 · 시각은 **사본에서만** 본다(개인정보 매니페스트 `C617.1` 범위). 남은 공간은 `volumeAvailableCapacityForImportantUsage` 로만 본다(DiskSpace 사유를 매니페스트에 더한다) | 그대로 |
| 3 | **암호** — 한 번 입력 | 그대로 |
| 4 | **검사** — `BackupArchive.read` 로 작업 폴더에 풀고 `BackupPayload.load(rootDirectory:limits:)` 가 디코딩 · 검증한다(§4-2) | 그대로 |
| 5 | **대상 계정** — 환경에서 `targetScope` 를 정한다(§6-2) | 그대로 |
| 6 | **미리보기** — 장마다 `backupRows(chapter:)` 와 `BackupImportPlanner.plan` 으로 수를 센다(`BackupImportPreview` — new · same · archived · protectedCleared · skippedEmpty · unsupported · chapters). 안내 「불러온 필사는 이 기기에 저장되고, 지금 연결된 iCloud 계정으로 동기화돼요. 지금 필사는 그대로 두고, 다른 내용은 이전 필사 기록에 더해요.」 | 그대로 |
| 7 | **쓰기 게이트** — `targetScope` 가 nil 이면 미리보기까지다. 적용 대신 사유와 할 일(로그인 → 앱 다시 열기)을 보인다 — 사유 문구는 「확인이 필요한 필기」 가져오기(`DraftRecoveryCopy`)와 같은 `SyncedWriteBlock` 사유를 쓴다 | 그대로 |
| 8 | **적용** — 사용자가 확인하면 작업 기록(`BackupImportJobStore`)을 남기고 장 단위로 쓴다(§4-3) | 장마다 한 트랜잭션 |
| 9 | **결과** — 실제로 넣은 수 · 건너뛴 수 · 멈춘 사유(`BackupImportReport` — `.completed` · `.blocked(사유, doneChapters)` · `.accountChanged(doneChapters)` …). 쓰기 직전에 다시 판정하므로 미리보기 수와 다를 수 있다(정책 §7-1). 로컬 반영과 iCloud 전송은 다르다(정책 §7-2 5) | — |
| 10 | **정리** — 평문 작업 폴더는 끝나면(성공 · 실패 · 취소) 지운다. 앱 시작 때 남은 `BackupWork` 를 지운다(`BackupWorkDirectory.removeStale()`) | — |

검사 · 미리보기는 구매 여부를 묻지 않고 저장소를 바꾸지 않는다. 미리보기 수는 검사 시점의 값이다.

### 4-2. 검사 — 파일 전체를 거부하는 것

모두 **저장소를 바꾸기 전에** 거부하고, 평문 작업 폴더를 지운다.

- 잘못된 암호 · 변조 · 잘림 → `wrongPasswordOrDamaged`
- 허용 밖 항목 이름 · 경로 이탈 · 링크 · 풀 폴더 밖 항목
- 상한 초과(§2-8)
- `formatVersion` ≠ 1 → `unsupportedFormat`
- manifest · items 디코딩 실패, `counts` 불일치, blob 크기 · 해시 불일치, 없는 blob 을 가리키는 항목, 겹치는 항목 id

항목 하나만 해석할 수 없는 경우(모르는 번역본 · 권 · 좌표 형식 · 풀리지 않는 메타데이터)는 파일을 거부하지 않고 그 항목만 건너뛴다(§5-1 `unsupported`).

### 4-3. 장 단위 적용 (`LiveBackupImporter.apply(_:progress:)`)

장마다(권 순서 → 장 순서):

1. 작업 기록에 끝난 장이면 건너뛴다(이어 하기). 다시 써도 같은 지문은 `skipSame` 이라 결과는 같다.
2. `DrawingEditEnvironmentClient.current()` 로 **최신 환경**을 읽는다. `SyncedWriteBlock.check(env) != nil` 이면 그 장부터 멈추고 `.blocked(사유, doneChapters)`,
   `env.storeOwnership != targetScope` 면 `.accountChanged(doneChapters)` 다. 이미 쓴 장은 그대로 둔다 — 이미 동기화됐을 수 있어 되돌리지 않는다.
3. `DrawingBackupRestoring.restore(command, chapter:, generation:)` — 같은 actor 구간에서 세대를 확인하고, 그 장의 행을 `BackupRowRecord` 로 **다시 읽어 판정을 다시 한
   뒤**(미리보기 뒤 동기화로 바뀐 것 반영) 넣을 행을 **한 트랜잭션**으로 쓴다. 세대가 적용을 시작할 때와 다르면(그 사이 「모든 필사 삭제」) 그 장을 쓰지 않고 멈춘다.
4. `LocalDrawingChange(chapter:date:)` 를 보낸다 — 설정 아래 열린 필사 화면이 그 장이면 다시 읽어 반영한다(늦게 도착한 필사와 같은 길).
5. 작업 기록에 그 장을 끝남으로 남긴다.
6. 그 환경의 서버 작업 표가 아직 유효한지(`isCurrent(env.serverWork)`) 본다. 아니면 다음 장으로 가지 않는다(`.accountChanged`).

넣는 행:

| 필드 | 값 |
|---|---|
| `lineData` · `drawingVersion` · `layoutMetadataData` | blob 원본 바이트 · 원본 값 그대로 — 승격 · 강등 · 다시 인코딩하지 않는다 |
| `creationDate` · `updateDate` | 항목의 `createdAt` · `updatedAt` 그대로(null 이면 null) — `now` 로 덮지 않는다(정책 §7-1). 차트 · 장 목록은 모든 행의 `updateDate` 로 세므로 원래 쓴 날짜로 보인다 |
| `isPresent` | `insertCurrent` 만 true. `insertArchived` · `protectCleared` 는 false |
| `rowUUID` | **늘 새로 발급**한다. 두 기기가 같은 파일을 넣어 같은 `rowUUID` 행이 둘 생기면 행 찾기(`rowUUID == raw \|\| id == raw`)가 깨진다 — 대신 같은 내용 행이 둘일 수 있다(§7) |
| business `id` | `BibleDrawing.init` 이 만드는 값 그대로(불러온 시각 기준). 행 키는 `rowUUID` 라 이 값으로 찾지 않고, 쪼개 파싱하지 않는다 |
| `translation` | 항목 값 그대로 — null 이면 null |
| `titleName` · `titleChapter` · `verse` | 권 코드로 찾은 `BibleTitle.rawValue` · 장 · 절 |

있는 행은 고치지 않는다 — 넣기만 한다(정책 §1-6). 재시도는 같은 규칙으로 **멱등**이다.

## 5. 판정 규칙 · flush 계약 · 백업 전용 조회

### 5-1. 판정 규칙 — `BackupImportPlanner.plan(items:unsupported:current:chapter:)`

순수 함수다(저장소 · 시각을 모른다). 미리보기와 쓰기 직전 재판정이 같은 함수를 쓴다.

**판정 단위 — 한 절.** 권 · 장 · 절이 같고 번역본이 같은 것. 번역 null 은 지금 앱에서 NKRV 화면에 보이므로(장 조회는 번역으로 거르지 않고, 즐겨찾기도
`translation ?? .NKRV` 로 본다) **NKRV 와 한 묶음**으로 판정한다 — 저장값은 null 그대로 넣는다. 번역본이 둘 이상이 되면 이 묶음을 다시 정한다(영어 성경 작업).

- `R` = 그 절의 지금 저장소 행 전부(`BackupRowRecord` — 현재 · 보관 · 비운 행). `대표` = `DrawingRepresentativeRule.pick(R)`.
- `R` 은 쓰기 직전에 다시 읽은 저장소다. 같은 파일의 다른 항목이 넣을 행은 `R` 에 더하지 않는다 — 단 **같은 지문은 한 절에 한 번만** 넣는다.
- **현재 후보** = 그 절의 `isCurrent` 항목 중 `updatedAt` 이 가장 늦은 하나(null 은 가장 이른 시각, 같으면 id 사전순 앞). 나머지 `isCurrent` 항목은 현재 후보가 아닌 것으로 다룬다.
- 시각 비교에서 null 은 가장 이른 시각이다(`DrawingRepresentativeRule` 과 같다).
- 순서: 지원 판정 → 현재 후보 → 나머지(id 순).

| 결정 | 언제 | 쓰기 | 미리보기 | 근거 |
|---|---|---|---|---|
| `unsupported(사유)` | 번역본이 null 도 아니고 `Translation` 의 값도 아님 · 권 코드가 `BibleBookCode` 에 없음 · `drawingVersion` 이 nil · 1 · 2 · 3 밖 · `drawingVersion` 3 이고 잉크가 있는데 메타데이터가 `DrawingLayoutMetadata.decode` 로 풀리지 않음 | 없음 | unsupported(사유별 수) | 모르는 형식을 조용히 바꾸거나 버리지 않는다 — 건너뛰고 알린다(정책 §6-2 · §8) |
| **잉크 있는 항목** | | | | |
| `skipSame` | `R` 의 어느 행(대표 · 보관)과 `fingerprint` 가 같다, 또는 이 절에 같은 지문을 이미 넣기로 했다 | 없음 | same | 같은 내용은 한 번만 — 같은 파일을 다시 불러오면 0건(정책 §7-1) |
| `protectCleared` | 현재 후보 · 대표가 비운 행 · 대표의 `updateDate` 가 항목 `updatedAt` 보다 늦다 | 새 행, `isPresent = false` | protectedCleared | 이 기기에서 백업보다 뒤에 지운 절 — 지운 것을 되살리지 않고 기록에만 둔다(`VerseDraftImportCheck.Caution.verseClearedAfterDraft` 선례) |
| `insertCurrent` | 현재 후보 · 잉크 있는 대표가 없다(`R` 이 비었거나 대표가 비운 행) · 위가 아님 | 새 행, `isPresent = true` | new | 비어 있던 절은 백업의 현재 필사로 채운다. 새 행이 `isPresent` 행 중 가장 늦어 대표가 된다(같은 시각이면 행 키 순) |
| `insertArchived` | 그 밖 — 잉크 있는 대표가 있는데 내용이 다르다, 또는 현재 후보가 아니다 | 새 행, `isPresent = false` | archived | 지금 필사를 유지하고 다른 내용은 이전 필사 기록에 더한다(정책 §7-1) |
| **비운 항목(`inkBlob` null)** | | | | |
| `insertCurrent` | 현재 후보 · `R` 이 비었다 | 비운 새 행(`lineData` nil), `isPresent = true` | new | 백업에서 지운 상태였던 절 — 아래 「비운 대표 행」 |
| `skipSame` | 대표가 이미 비운 행 | 없음 | same | 이미 지운 상태다 |
| `skipEmpty` | 그 밖 — 잉크 있는 대표가 있다, 또는 현재 후보가 아니다 | 없음 | skippedEmpty | 지금 필사를 비우지 않고, 기록에 빈 행을 더하지 않는다 |

**비운 대표 행.** `DrawingRepresentativeRule.pick` 은 `isPresent` 행이 없으면 **전체에서** 고른다. 그래서 지운 절을 담을 때 비운 대표 행을 빼거나, 불러올 때
건너뛰면 같은 백업의 잉크 있는 보관 행(`isPresent = false`)이 대표로 올라가 **지운 필기가 되살아난다.** 내보내기는 비운 대표 행도 `isCurrent = true` 로 담고(§3-3),
불러오기는 그 절에 행이 하나도 없을 때 비운 현재 행으로 넣는다.

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
BackupExportFeature ── Delegate.canvasFlushRequested(id) ──▶ (설정) ──▶ AppCoordinatorFeature
AppCoordinatorFeature   필사 화면 있음 → ChapterCanvasFeature.Action.backupFlushRequested(id)
                        없음          → 곧바로 .durable
ChapterCanvasFeature    flushPending 과 같은 인계(handoffToken)를 요청하고 저장을 시작한다
                        인계가 끝나고 hasUnsavedChanges == false && saveRetryCount == nil → Delegate.backupFlushFinished(id, .durable)
                        초안 · 저장 실패(saveRetryCount != nil)                        → .failed(retryCount:)
                        5초 안에 정해지지 않음(continuousClock)                         → .timedOut
AppCoordinatorFeature ── SettingsFeature.Action.canvasFlushFinished(id:outcome:) ──▶ 설정 → 그 id 를 기다리는 BackupExportFeature
                        (설정 쪽도 10초 시간 제한 → .timedOut)
```

- `.durable` 의 뜻 — **마지막 revision 까지 이 기기에 남았다.** 저장소로 갈 것은 저장소에, 그 밖(소유 근거 없음 · 연결 보류 · 보이기만 하는 절)은 초안에.
  `hasUnsavedChanges` 는 획을 긋는 중(`isEditing`) · 디바운스 구간 · 편집 큐 · 저장 대기 · 닫은 세션의 늦은 편집까지 본다.
- `.durable` 이 아니면 백업을 시작하지 않는다 — 「필사 화면에 아직 저장하지 못한 필기가 있어요. 필사 화면에서 저장을 다시 시도한 뒤 백업해 주세요.」 +
  [다시 시도](새 id). 다른 id 의 늦은 결과는 버린다.
- 설정이 열려 있는 동안 캔버스 입력은 이미 막혀 있다(`AppCoordinatorView` 의 `allowsHitTesting`) — flush 뒤에 새 획이 끼지 않는다.
- 결과 타입 `CanvasFlushOutcome`(`.durable` · `.failed(retryCount: Int)` · `.timedOut`)은 CarveFeature 와 SettingsFeature 가 함께 쓰므로 Domain 에 둔다.
  Feature 끼리 import 하지 않고 코디네이터가 중계한다.
- 리듀서의 시간 제한은 `@Dependency(\.continuousClock)` 이다 — 시험은 `TestClock`.
- 한계: 인계가 받는 것은 PencilKit 이 이미 반영한 획이다(§7).

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
  `lineData` · `layoutMetadataData` — `BibleDrawing` 원본 그대로. `DrawingRepresentativeCandidate` 를 따른다(대표 규칙을 그대로 쓴다).
- `SwiftDatabaseActor.backupRows(chapter:)` 가 장마다 `BackupRowLoad(rows:generation:)` 를 **같은 actor 구간에서** 돌려준다 — 따로 읽으면 그 사이의 전체 삭제를 놓친다.
  `backupChapters()` 는 행이 있는 장 목록이다.
- `BibleDrawing` → `BackupRowRecord` 변환은 `SwiftDatabaseActor+Backup.swift` 한 곳(internal 확장)이다. **내보내기 · 판정 · 복원 쓰기가 같은 변환으로 견준다** —
  지문이 한쪽만 다시 인코딩되면 같은 필기를 다른 것으로 본다.

## 6. 귀속과 계정

### 6-1. 원칙

- 불러온 필기는 **지금 연결된 계정(저장소 소유자)의 것**이다. 파일을 만든 계정은 보지 않는다 — 파일에 계정 정보가 없다(§2-3). 다른 Apple 계정이 만든 파일도
  파일과 암호가 있으면 불러온다(정책 §7-4). 개인정보는 암호화로 다루고, 계정 문자열 비교를 접근 통제로 삼지 않는다.
- **연결되지 않은 실행**(로그인 안 함 · 계정 미확인 · 소유 근거 없음 · 삭제 기준점을 읽지 못함 · 연결 보류)은 **검사 · 미리보기만** 한다. 적용 버튼 대신 사유와
  할 일을 보인다 — 대개 「iCloud 에 로그인한 뒤 앱을 다시 열어 주세요」 다(2.0.0 은 실행 중에 저장소 연결을 바꾸지 않는다 — 다시 열면 연결된다).

### 6-2. 대상 계정 범위 — `targetScope`

- 검사 때 환경에서 정한다: 계정이 확인됐고(`.confirmed(scope)`) `storeOwnership == scope` 이며 `SyncedWriteBlock.check(env) == nil` 이면 그 `AccountScope`, 아니면 nil(미리보기만).
- `BackupInspection` 과 기기 안 작업 기록에 묶는다. **백업 파일에는 넣지 않는다.**
- 적용은 **장마다 최신 환경**(`current()`)을 읽어 `check == nil` 이고 `storeOwnership == targetScope` 일 때만 그 장을 쓴다(§4-3). 검사 때 읽은 환경 하나로는
  적용 도중의 로그아웃 · 계정 변경을 모른다.
- 장을 쓴 뒤 서버 작업 표가 무효(`isCurrent == false`)면 다음 장으로 가지 않는다.

### 6-3. 작업 기록과 이어 하기 — `BackupImportJobStore`

- 남기는 것: `jobID` · `targetScope` · 끝난 장(`doneChapters`) · 고른 파일의 **암호화된 사본**. 평문 · 암호는 남기지 않는다 — 그래서 이어 할 때 암호를 다시 묻는다.
  `AccountScope` 는 이 기기 안 작업 기록에만 있다.
- `pendingJob()` 은 **지금 환경의 계정 범위가 `targetScope` 와 같을 때만** 「이어서 불러오기」 로 내놓는다 — 암호 → 다시 검사 → 끝난 장을 건너뛰고 적용.
- 다르면 이어 하지 않는다 — **A 계정에서 일부 적용한 작업을 B 계정 저장소에 잇지 않는다.** 「버리기」 또는 「이 계정으로 처음부터」(새 검사 · 새 `targetScope`)만
  보인다(지금 연결되지 않았으면 처음부터 해도 미리보기까지다).
- 끝나거나 버리면 암호화 사본과 기록을 지운다.

### 6-4. 내보내기의 계정

- 계정 상태를 묻지 않고 만든다 — 미로그인 · 연결 보류 실행도 그 기기의 행과 `acct-local` 초안을 담는다(결정 2).
- 시작 때 계정 상태 · 저장소 소유 · 여는 묶음을 적어 두고 **장마다 다시 읽어 다르면 `accountChanged` 로 멈춘다**(§3-2) — 계정이 바뀌면 여는 초안 묶음이 바뀌어,
  두 계정의 초안이 한 파일에 섞일 수 있기 때문이다.

## 7. 알려진 한계

| 한계 | 내용 |
|---|---|
| 두 기기가 오프라인으로 같은 파일을 넣음 | 각 기기가 자기 저장소로 판정해 둘 다 넣는다. `rowUUID` 를 늘 새로 발급하므로 연결 뒤 **같은 내용 행이 둘**이 된다. 「이전 필사 내용 보기」 는 같은 내용 행을 하나로 보이고, 둘 다 현재 행이어도 대표 규칙이 결정적이라 화면은 같다. 파괴적인 중복 정리는 하지 않는다(정책 §7-3) |
| 내보내기 직전 0.3초 안의 미보고 획 | flush 인계는 획이 끝난 뒤 PencilKit 반영 시간(`editSettleInterval` 0.3초)을 두고 캔버스 내용을 찍는다. 그 안에 PencilKit 이 아직 반영하지 않은 획은 단일 캔버스의 기존 한계와 같아 빠질 수 있다(정책 §12-1 · §12-3 「디스크 커밋 전 마지막 변경까지 저장됐다고 약속하지 않는다」). 계약이 보장하는 것은 **보고된 마지막 revision** 까지다 |
| CloudKit 원자성 아님 | 장 하나의 트랜잭션은 이 기기 저장소의 원자성이다. 다른 기기는 한 장의 행을 나눠 · 순서 없이 받을 수 있고, 이미 올라간 행은 로컬 되돌리기로 모든 기기에서 거두지 못한다(정책 §7-2). 그래서 멈춰도 쓴 장은 되돌리지 않는다 |
| V6 미개방이라 계보 없음 | `parents` 가 비어 있다. 두 기기의 분기를 계보로 가리지 못하고 대표 규칙(`isPresent` → `updateDate`)이 정한다 — 현재 후보 선택 · 지운 절 보호도 기기 시각 비교라 시계가 크게 어긋나면 틀릴 수 있다(정책 §8 시계 차이). 버전 저장을 열면 이 행들은 legacy 원본으로 수용된다(정책 §12-6 C3) |
| 즐겨찾기 스냅샷 제외 | 즐겨찾기 · 위젯은 추가할 때의 사본이라 담지 않는다. 즐겨찾기에만 남은 필사는 이 백업으로 되살릴 수 없다 — 안내 문구가 「즐겨찾기 · 설정 · 위젯은 담지 않아요」 라고 말한다(정책 §6-3) |
| Files 앱에서 눌러 열기 없음 | 문서 타입 선언 · 「이 앱으로 열기」 는 2.1 범위 밖이다. 설정 → 필사 백업 → 「백업 불러오기」 에서 파일을 고른다 |
| 「모든 필사 삭제」 뒤의 옛 백업 | 전체 삭제는 기준점을 남기지 않으므로(V6 미개방) 그 뒤 옛 백업을 불러오면 지운 필사가 그대로 들어온다. 사용자가 고른 명시적 복구로 본다(정책 §8 「영구 삭제와 과거 백업」). 오프라인 기기가 옛 행을 다시 올리는 재등장(정책 §12-5 C11)과는 별개다 |

## 8. 시험

### 8-1. 단위 · 저장소 시험 (Swift Testing, 시뮬레이터 iPad)

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

### 8-3. 기기 · 시뮬레이터 — [시험 계획](./icloud-sync-compatibility-test-plan.md) 단계 D

새 iPad 시뮬레이터에서 하고 끝나면 지운다(CloudKit 표본이 든 기기는 쓰지 않는다). 결과는 시험 계획의 ID 로 적는다.

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
