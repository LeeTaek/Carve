//
//  BackupRestoreTestSupport.swift
//  DomainTest
//
//  불러오기 적용 시험의 공용 세계 — 시험마다 따로인 임시 폴더의 실제 저장소(디스크 ModelContainer) · 평문 작업 폴더 · 작업 기록 폴더,
//  형식 타입(BackupItem · BackupManifest · BackupArchive)으로 만든 백업 파일, 고정 표본.
//

import Dependencies
import Foundation
import SwiftData
import Testing

@testable import Domain

/// 고정 표본. 잉크는 `PKDrawing` 이 아니라 고정 바이트다 — `PKDrawing` 바이트는 만들 때마다 달라진다.
enum BackupRestoreSample {
    static let password = "carve-restore-1234"
    static let genesis1 = BibleChapter(title: .genesis, chapter: 1)
    static let genesis2 = BibleChapter(title: .genesis, chapter: 2)
    static let exodus3 = BibleChapter(title: .exodus, chapter: 3)

    /// 필사책 안의 장 — 판정 · 적용 · 작업 기록의 단위(`NotebookChapter`). 필사책을 주지 않으면 기본 필사책이다(시험 표본만의 편의).
    static func page(_ chapter: BibleChapter, notebook: NotebookID = .default) -> NotebookChapter {
        NotebookChapter(notebook: notebook, chapter: chapter)
    }

    /// 불러오는 시각(작업 기록 · `LocalDrawingChange`).
    static let now = Date(timeIntervalSinceReferenceDate: 813_000_000.5)
    /// 2026-09-01T00:00:00Z — 설계 §5-1 의 예(9/25 · 9/30 · 10/01)를 날짜로 읽게 한다.
    static let september1 = Date(timeIntervalSinceReferenceDate: 809_913_600)

    /// 2026년 9월 그날 0시(UTC)에 소수 초를 더한 시각 — 원본 시각이 손실 없이 들어가는지 본다.
    static func sep(_ day: Int, fraction: Double = 0.123_456_7) -> Date {
        september1.addingTimeInterval(Double(day - 1) * 86_400 + fraction)
    }

    /// 2026년 10월 그날.
    static func oct(_ day: Int) -> Date {
        sep(30 + day)
    }

    /// `DrawingLayoutMetadata.decode` 로 풀리는 메타데이터 — 키 순서가 정렬도 기본 인코더 순서도 아니고 공백이 있다(원본 바이트 보존을 본다).
    static let metadata = Data("""
    { "layoutSignature" : "cl2-restore", "baseUnderlineAnchors" : [0, 30], "metadataSchemaVersion" : 1, \
    "baseWritingHeight" : 400, "baseWritingWidth" : 300 }
    """.utf8)

    /// 잉크 바이트 — 이름이 같으면 같은 바이트다.
    static func ink(_ name: String) -> Data {
        Data("ink-\(name)".utf8)
    }

    /// 외부 저장으로 빠질 만큼 큰 잉크(256 KB).
    static let largeInk = Data((0..<262_144).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) })

    static let accountA = AccountScope(key: "acct-restore-a")
    static let accountB = AccountScope(key: "acct-restore-b")

    /// 확인된 계정 + 저장소 소유가 그 계정인 유효 환경.
    static func confirmed(_ scope: AccountScope, generation: UInt64 = 1) -> DrawingEditEnvironment {
        DrawingEditEnvironment(
            accountState: .confirmed(scope),
            serverWork: AccountServerWorkToken(scope: scope, generation: generation),
            knowledge: EraseEpochKnowledge(),
            storeOwnership: scope
        )
    }

    /// 확인된 계정이지만 이번 실행의 연결이 보류된 환경.
    static func connectionHeld(_ scope: AccountScope) -> DrawingEditEnvironment {
        var environment = confirmed(scope)
        environment.connectionHeld = true
        return environment
    }

    /// 로그인하지 않은 환경.
    static let signedOut = DrawingEditEnvironment(accountState: .noAccount, serverWork: nil, knowledge: EraseEpochKnowledge())
}

/// 백업 파일 항목 하나의 원본 — 형식 타입(`BackupItem`)과 그 blob 바이트를 만든다(내보내기와 같은 규칙: 지문 · id · blob 이름은 원본 바이트로).
struct BackupRestoreEntry {
    var kind: BackupItemKind = .row
    var chapter: BibleChapter = BackupRestoreSample.genesis1
    var verse: Int
    /// 행이면 `rowUUID ?? business id`, 초안이면 초안 원본 키의 자리.
    var sourceKey: String
    var ink: Data?
    var metadata: Data? = BackupRestoreSample.metadata
    var drawingVersion: Int? = 3
    var isCurrent: Bool
    var createdAt: Date?
    var updatedAt: Date?
    var translation: String? = "NKRV"
    /// 절 키의 필사책 토큰(형식 2). nil 이면 기본 필사책.
    var notebook: String?

    /// 원본 바이트로 만든 지문 — 잉크가 있을 때만.
    var fingerprint: String? {
        ink.map { VerseContentFingerprint.make(lineData: $0, drawingVersion: drawingVersion, layoutMetadataBlob: metadata) }
    }

    /// 불러온 행의 `titleName` — 항목의 필사책 · 권 · 번역본으로 지은 이름(nil · 모르는 번역본은 개역개정 이름, 다른 필사책은 `nb_<토큰>~` 접두).
    var storedTitleName: String {
        StoredBookKey.titleName(
            title: chapter.title,
            translation: BackupImportPlanner.placementTranslation(translation),
            notebook: notebook.flatMap(NotebookID.init(rawValue:)) ?? .default
        )
    }

    /// 불러온 행의 `translation` 열 — 개역개정은 값 그대로(nil 은 nil), KJV · BSB 는 nil.
    var storedTranslation: String? {
        translation.flatMap(Translation.init(rawValue:)).flatMap(StoredBookKey.translationColumn(for:))?.rawValue
    }

    /// 백업 항목.
    var item: BackupItem {
        let titleName = storedTitleName
        let source = kind == .row
            ? BackupItemSource(titleName: titleName, rowKey: sourceKey)
            : BackupItemSource(titleName: titleName, draftScope: BackupItemSource.DraftScope.local.rawValue, draftRevision: 1)
        return BackupItem(
            id: BackupItemID.make(kind: kind, sourceKey: sourceKey, fingerprint: fingerprint),
            kind: kind,
            verse: BackupVerseKey(translation: translation, title: chapter.title, chapter: chapter.chapter, verse: verse, notebook: notebook),
            drawingVersion: drawingVersion,
            inkBlob: ink.map(BackupFormat.sha256Hex),
            metadataBlob: metadata.map(BackupFormat.sha256Hex),
            fingerprint: fingerprint,
            isCurrent: isCurrent,
            createdAt: kind == .draft ? nil : createdAt,
            updatedAt: updatedAt,
            source: source
        )
    }

    /// 이 항목이 가리키는 blob 바이트.
    var blobs: [Data] {
        [ink, metadata].compactMap { $0 }
    }
}

/// 넣은 내용을 기록하는 `LocalDrawingChange` 대역.
struct RecordingLocalDrawingChanges: LocalDrawingChangeClient {
    private let box = LockIsolated<[LocalDrawingChange]>([])

    /// 보낸 변경(보낸 순서).
    var posted: [LocalDrawingChange] { box.value }

    func post(_ change: LocalDrawingChange) {
        box.withValue { $0.append(change) }
    }

    func changes() -> AsyncStream<LocalDrawingChange> { AsyncStream { $0.finish() } }
}

/// 한 장에서 한 번만 쓰기에 실패하는 복원 쓰기 — 중간 장 실패 뒤 재시도를 재현한다. 나머지는 실제 구현에 넘긴다.
struct FailingOnceRestorer: DrawingBackupRestoring {
    let base: any DrawingBackupRestoring
    let failing: NotebookChapter
    private let failed = LockIsolated(false)

    init(base: any DrawingBackupRestoring, failing: NotebookChapter) {
        self.base = base
        self.failing = failing
    }

    func restore(
        _ command: BackupChapterRestoreCommand,
        page: NotebookChapter,
        generation: DrawingStoreGeneration
    ) async throws -> BackupChapterRestoreOutcome {
        if page == failing {
            let firstTime = failed.withValue { alreadyFailed -> Bool in
                let first = !alreadyFailed
                alreadyFailed = true
                return first
            }
            if firstTime {
                throw DrawingRepositoryError.persistenceFailed("시험 — 이 장을 쓰지 못했다")
            }
        }
        return try await base.restore(command, page: page, generation: generation)
    }

    func restoreNotebooks(_ records: [BackupNotebookRecord], generation: DrawingStoreGeneration) async throws -> BackupNotebookRestoreOutcome {
        try await base.restoreNotebooks(records, generation: generation)
    }
}

/// 불러오기 시험 하나의 세계 — 임시 폴더 안의 디스크 저장소 · 평문 작업 폴더 자리 · 작업 기록 자리 · 백업 파일 자리. 끝나면 `remove()`.
///
/// 실제 `BackupWork` · `Application Support/BackupImport` 를 쓰지 않는다(병렬 시험끼리 간섭하지 않게).
struct BackupRestoreHarness {
    let root: URL
    let container: ModelContainer
    let database: SwiftDatabaseActor
    let restorer: SwiftDataDrawingBackupRestorer
    let changes = RecordingLocalDrawingChanges()

    /// 평문 작업 폴더의 부모.
    var workRoot: URL { root.appendingPathComponent("BackupWork", isDirectory: true) }
    /// 작업 기록의 부모.
    var jobRoot: URL { root.appendingPathComponent("BackupImport", isDirectory: true) }
    /// 작업 기록 저장소.
    var jobs: BackupImportJobStore { BackupImportJobStore(root: jobRoot) }
    /// 백업 파일을 두는 곳(사용자가 고른 파일 자리).
    var files: URL { root.appendingPathComponent("files", isDirectory: true) }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("backup-restore-\(UUID().uuidString)", isDirectory: true)
        let store = root.appendingPathComponent("store", isDirectory: true)
        try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("files", isDirectory: true),
            withIntermediateDirectories: true
        )
        container = try ModelContainer(
            for: AppStoreSchema.schema,
            configurations: ModelConfiguration(url: store.appendingPathComponent("Carve.sqlite"), cloudKitDatabase: .none)
        )
        database = SwiftDatabaseActor(modelContainer: container)
        restorer = SwiftDataDrawingBackupRestorer(actor: database)
    }

    /// 이 시험의 폴더를 모두 지운다.
    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    /// 이 세계의 불러오기.
    func importer(_ environment: any DrawingEditEnvironmentClient, restorer: (any DrawingBackupRestoring)? = nil) -> LiveBackupImporter {
        LiveBackupImporter(
            environment: environment,
            restorer: restorer ?? self.restorer,
            database: database,
            changes: changes,
            jobs: jobs,
            workRoot: workRoot,
            limits: .default,
            now: { BackupRestoreSample.now }
        )
    }

    /// 형식 타입으로 백업 파일을 만든다 — 준비 폴더에 manifest · items · blob 을 쓰고 `BackupArchive.write` 로 암호화한다.
    /// - Parameters:
    ///   - formatVersion: manifest 의 형식 버전(옛 · 뒤 버전 파일 시험만 바꾼다).
    ///   - notebooks: manifest 의 필사책 목록(형식 2).
    /// - Returns: 백업 파일(사용자가 고른 파일 자리).
    func writeBackup(
        _ entries: [BackupRestoreEntry],
        password: String = BackupRestoreSample.password,
        formatVersion: Int = BackupFormat.formatVersion,
        notebooks: [BackupNotebookRecord] = []
    ) throws -> URL {
        let staged = root.appendingPathComponent("staged-\(UUID().uuidString)", isDirectory: true)
        let blobDirectory = staged.appendingPathComponent(BackupFormat.blobDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: blobDirectory, withIntermediateDirectories: true)
        var blobs: [String: BackupBlobEntry] = [:]
        for bytes in entries.flatMap(\.blobs) {
            let entry = BackupBlobEntry(bytes: bytes)
            guard blobs[entry.name] == nil else { continue }
            try bytes.write(to: blobDirectory.appendingPathComponent(entry.name, isDirectory: false))
            blobs[entry.name] = entry
        }
        let items = entries.map(\.item)
        let rows = items.filter { $0.kind == .row }.count
        let manifest = BackupManifest(
            formatVersion: formatVersion,
            backupID: UUID().uuidString,
            createdAt: BackupRestoreSample.now,
            appVersion: "2.1.0",
            scope: BackupScope(rows: true, drafts: true),
            counts: BackupCounts(rows: rows, drafts: items.count - rows, blobs: blobs.count),
            blobs: blobs.values.sorted { $0.name < $1.name },
            notebooks: notebooks
        )
        try BackupFormat.encoder.encode(manifest).write(to: staged.appendingPathComponent(BackupFormat.manifestFileName, isDirectory: false))
        try BackupFormat.encoder.encode(items).write(to: staged.appendingPathComponent(BackupFormat.itemsFileName, isDirectory: false))
        let file = files.appendingPathComponent("backup-\(UUID().uuidString).carvebackup", isDirectory: false)
        try BackupArchive.write(stagedDirectory: staged, to: file, password: password)
        try FileManager.default.removeItem(at: staged)
        return file
    }

    /// 행을 심는다 — 같은 컨테이너의 새 문맥에 넣고 저장한다(모델을 actor 로 넘기지 않는다).
    func seed(_ rows: [BackupExportRowSeed]) throws {
        let context = ModelContext(container)
        for seed in rows {
            context.insert(seed.makeRow())
        }
        try context.save()
    }

    /// **기본 필사책** 그 장의 행 원본(백업 전용 조회 — 절 → 행 키 순).
    func rows(_ chapter: BibleChapter = BackupRestoreSample.genesis1) async throws -> [BackupRowRecord] {
        try await rows(page: BackupRestoreSample.page(chapter))
    }

    /// 필사책 안의 그 장의 행 원본(백업 전용 조회 — 절 → 행 키 순).
    func rows(page: NotebookChapter) async throws -> [BackupRowRecord] {
        try await database.backupRows(page: page).rows
    }

    /// **기본 필사책** 그 절의 대표 — 화면(`representativesByVerse`)과 같은 규칙.
    func representative(_ chapter: BibleChapter = BackupRestoreSample.genesis1, verse: Int) async throws -> BackupRowRecord? {
        try await representative(page: BackupRestoreSample.page(chapter), verse: verse)
    }

    /// 필사책 안의 그 절의 대표 — 화면(`representativesByVerse`)과 같은 규칙.
    func representative(page: NotebookChapter, verse: Int) async throws -> BackupRowRecord? {
        DrawingRepresentativeRule.pick(try await rows(page: page).filter { $0.verse == verse })
    }

    /// 필사책 정보를 심는다 — 같은 컨테이너의 새 문맥에 넣고 저장한다. 레코드 값은 그대로다(같은 ID 둘도 심을 수 있다).
    func seedNotebooks(_ records: [BackupNotebookRecord]) throws {
        let context = ModelContext(container)
        for record in records {
            context.insert(BackupNotebookSeed.makeNotebook(record))
        }
        try context.save()
    }

    /// 저장소의 필사책 정보 전부 — ID → 순서. 같은 ID 레코드가 둘이면 둘 다(ID → 이름 순).
    func storedNotebooks() throws -> [BackupNotebookRecord] {
        try ModelContext(container).fetch(FetchDescriptor<DrawingNotebook>()).map(BackupNotebookSeed.record)
            .sorted { ($0.id, $0.name ?? "") < ($1.id, $1.name ?? "") }
    }

    /// 지금 저장소 세대.
    func generation() async -> DrawingStoreGeneration {
        await database.backupStoreGeneration()
    }

    /// 평문 작업 폴더 부모에 남은 것.
    func workLeftovers() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: workRoot.path)) ?? []).sorted()
    }

    /// 작업 기록 부모에 남은 작업 폴더.
    func jobLeftovers() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: jobRoot.path)) ?? []).filter { UUID(uuidString: $0) != nil }.sorted()
    }
}

extension BackupChapterRestoreCommand {
    /// 항목 원본으로 명령을 만든다 — blob 은 이름(SHA-256)대로.
    init(entries: [BackupRestoreEntry]) {
        var blobs: [String: Data] = [:]
        for bytes in entries.flatMap(\.blobs) {
            blobs[BackupFormat.sha256Hex(bytes)] = bytes
        }
        self.init(items: entries.map(\.item), blobs: blobs)
    }
}

extension BackupRowRecord {
    /// 불러온 행이 원본 항목과 같은 값인가 — 바이트 · 좌표 형식 · 시각 · 번역 저장값 · 권 이름 · 장 · 절(행 식별자는 새로 발급하므로 보지 않는다).
    /// 영어 항목은 열이 nil 이고 권 이름이 `KJV-…` 다(`storedTranslation` · `storedTitleName`).
    func matchesOriginal(_ entry: BackupRestoreEntry) -> Bool {
        lineData == entry.ink
            && layoutMetadataData == entry.metadata
            && drawingVersion == entry.drawingVersion
            && creationDate == (entry.kind == .draft ? nil : entry.createdAt)
            && updateDate == entry.updatedAt
            && translation == entry.storedTranslation
            && titleName == entry.storedTitleName
            && chapter == entry.chapter.chapter
            && verse == entry.verse
    }
}

/// 필사책 정보(`DrawingNotebook`)를 시험 레코드 값으로 만들고 읽는다 — 저장소 구현의 변환(`backupRecord` · `applyBackupRecord`)에 기대지 않고 필드를 하나씩 옮긴다.
enum BackupNotebookSeed {
    /// 모델을 만든다 — 컨테이너가 이미 있어야 한다(iOS 17).
    static func makeNotebook(_ record: BackupNotebookRecord) -> DrawingNotebook {
        let notebook = DrawingNotebook()
        notebook.notebookID = record.id
        notebook.name = record.name
        notebook.status = record.status
        notebook.createdAt = record.createdAt
        notebook.updatedAt = record.updatedAt
        notebook.completedAt = record.completedAt
        notebook.kind = record.kind
        notebook.scopeData = record.scopeData
        notebook.linkData = record.linkData
        return notebook
    }

    /// 모델의 값 그대로.
    static func record(_ notebook: DrawingNotebook) -> BackupNotebookRecord {
        BackupNotebookRecord(
            id: notebook.notebookID ?? "",
            name: notebook.name,
            status: notebook.status,
            createdAt: notebook.createdAt,
            updatedAt: notebook.updatedAt,
            completedAt: notebook.completedAt,
            kind: notebook.kind,
            scopeData: notebook.scopeData,
            linkData: notebook.linkData
        )
    }
}
