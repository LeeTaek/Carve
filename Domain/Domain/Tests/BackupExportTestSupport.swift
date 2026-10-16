//
//  BackupExportTestSupport.swift
//  DomainTest
//
//  필사 백업 내보내기 시험의 공용 세계 — 시험마다 따로인 인메모리 저장소 · 보존 영역(초안) · 작업 폴더 자리, 바꿀 수 있는 편집 환경, 고정 표본.
//

import Dependencies
import Foundation
import SwiftData
import Testing

@testable import Domain

/// 고정 표본. 잉크는 `PKDrawing` 이 아니라 고정 바이트다 — `PKDrawing` 바이트는 만들 때마다 달라진다.
enum BackupExportSample {
    static let password = "carve-1234"
    static let genesis1 = BibleChapter(title: .genesis, chapter: 1)
    static let genesis2 = BibleChapter(title: .genesis, chapter: 2)
    static let exodus3 = BibleChapter(title: .exodus, chapter: 3)

    /// 만든 시각(소수 초 — 손실 없이 왕복해야 한다).
    static let now = Date(timeIntervalSinceReferenceDate: 812_613_600.123_456_7)
    static let createdAt = Date(timeIntervalSinceReferenceDate: 795_142_923.5)
    static let updatedAt = Date(timeIntervalSinceReferenceDate: 811_600_496.789)
    static let archivedAt = Date(timeIntervalSinceReferenceDate: 812_023_200)
    static let clearedAt = Date(timeIntervalSinceReferenceDate: 812_460_000.25)
    static let draftSavedAt = Date(timeIntervalSinceReferenceDate: 812_600_000.5)

    /// `DrawingLayoutMetadata.decode` 로 풀리는 메타데이터 — 키 순서가 정렬도 기본 인코더 순서도 아니고 공백이 있다(원본 바이트 보존을 본다).
    static let metadata = Data("""
    { "layoutSignature" : "cl2-export", "baseUnderlineAnchors" : [0, 30], "metadataSchemaVersion" : 1, \
    "baseWritingHeight" : 400, "baseWritingWidth" : 300 }
    """.utf8)
    /// 다른 절의 메타데이터.
    static let otherMetadata = Data("""
    {"baseWritingWidth":320,"baseWritingHeight":60,"baseUnderlineAnchors":[0],"metadataSchemaVersion":1,"layoutSignature":"cl2-other"}
    """.utf8)

    /// 잉크 바이트.
    static func ink(_ name: String) -> Data { Data("ink-\(name)".utf8) }

    /// 원본 바이트로 만든 내용 지문 — 메타데이터가 풀리면 장 조회(`VerseDrawingSnapshot`)의 지문과 같다.
    static func fingerprint(_ ink: Data, drawingVersion: Int? = 3, metadata: Data? = metadata) -> String {
        VerseContentFingerprint.make(lineData: ink, drawingVersion: drawingVersion, layoutMetadataBlob: metadata)
    }

    // MARK: - 환경

    static let accountA = AccountScope(key: "acct-a")
    static let accountB = AccountScope(key: "acct-b")

    /// 확인된 계정 + 저장소 소유 근거가 그 계정인 환경.
    static func confirmed(_ scope: AccountScope) -> DrawingEditEnvironment {
        DrawingEditEnvironment(
            accountState: .confirmed(scope),
            serverWork: AccountServerWorkToken(scope: scope, generation: 1),
            knowledge: EraseEpochKnowledge(),
            storeOwnership: scope
        )
    }

    /// 로그인하지 않은 환경.
    static let signedOut = DrawingEditEnvironment(accountState: .noAccount, serverWork: nil, knowledge: EraseEpochKnowledge())

    // MARK: - 초안

    /// 초안 하나. 잉크에는 풀리는 메타데이터가 붙는다(화면에 겹칠 수 있는 초안). 필사책을 주지 않으면 기본 필사책의 초안이다.
    static func draft(
        chapter: BibleChapter = genesis1,
        notebook: NotebookID = .default,
        verse: Int,
        session: String = "session-1",
        ink: Data?,
        base: VerseEditBase = .empty,
        account: VerseEditAccountBasis,
        storeOwnership: AccountScope? = nil,
        revision: Int = 3,
        savedAt: Date = draftSavedAt
    ) -> VerseDraft {
        let baseFingerprint: String? = switch base {
        case .legacy(_, let contentFingerprint): contentFingerprint
        case .empty, .version: nil
        }
        return VerseDraft(
            key: VerseDraftKey(sessionID: session, page: NotebookChapter(notebook: notebook, chapter: chapter), verse: verse),
            revision: revision,
            rowID: BibleDrawingRowID(raw: "draft-row-\(verse)"),
            lineData: ink,
            drawingVersion: ink == nil ? nil : 3,
            layoutMetadataData: ink == nil ? nil : metadata,
            base: base,
            baseFingerprint: baseFingerprint,
            account: account,
            knownEpochs: [],
            storeOwnership: storeOwnership,
            eraseGeneration: 0,
            savedAt: savedAt
        )
    }
}

/// 심을 행 하나 — `BibleDrawing` 의 원본 필드 그대로.
///
/// 권 이름은 장의 필사책 · 번역본으로 짓는다(`StoredBookKey.titleName(title:translation:notebook:)` — 영어 장은 `KJV-…`,
/// 다른 필사책은 `nb_<토큰>~…`). 영어 행의 번역 열은 부르는 쪽이 nil 로 준다.
struct BackupExportRowSeed {
    var chapter: BibleChapter = BackupExportSample.genesis1
    /// 행의 필사책 — 기본은 기본 필사책(접두 없음).
    var notebook: NotebookID = .default
    var verse: Int?
    /// nil 이면 1.3.0 행(business id 가 행 키).
    var rowUUID: String?
    var businessID: String
    var translation: Translation? = .NKRV
    var isPresent: Bool? = true
    var creationDate: Date? = BackupExportSample.createdAt
    var updateDate: Date? = BackupExportSample.updatedAt
    var drawingVersion: Int? = 3
    var lineData: Data?
    var layoutMetadataData: Data?
    /// 권 이름을 바꿔 심는다(알 수 없는 권 시험).
    var titleNameOverride: String?
    /// 장을 지운다(장 없는 행 시험).
    var dropsChapter = false

    init(
        chapter: BibleChapter = BackupExportSample.genesis1,
        verse: Int?,
        rowUUID: String?,
        businessID: String? = nil,
        translation: Translation? = .NKRV,
        isPresent: Bool? = true,
        creationDate: Date? = BackupExportSample.createdAt,
        updateDate: Date? = BackupExportSample.updatedAt,
        drawingVersion: Int? = 3,
        lineData: Data?,
        layoutMetadataData: Data?
    ) {
        self.chapter = chapter
        self.verse = verse
        self.rowUUID = rowUUID
        self.businessID = businessID ?? "\(chapter.title.rawValue).\(chapter.chapter).\(verse ?? 0).\(rowUUID ?? "legacy")"
        self.translation = translation
        self.isPresent = isPresent
        self.creationDate = creationDate
        self.updateDate = updateDate
        self.drawingVersion = drawingVersion
        self.lineData = lineData
        self.layoutMetadataData = layoutMetadataData
    }

    /// 행 키 — `rowUUID ?? business id`.
    var rowKey: String { rowUUID ?? businessID }

    /// 심는 `titleName` — 바꿔 심지 않았으면 장의 필사책 · 번역본으로 지은 이름.
    var titleName: String {
        titleNameOverride ?? StoredBookKey.titleName(title: chapter.title, translation: chapter.translation, notebook: notebook)
    }

    /// 이 행이 놓이는 필사책 안의 장.
    var page: NotebookChapter { NotebookChapter(notebook: notebook, chapter: chapter) }

    /// 이 행이 백업 전용 조회에서 보일 원본.
    var record: BackupRowRecord {
        BackupRowRecord(
            rowUUID: rowUUID,
            businessID: businessID,
            titleName: titleName,
            chapter: chapter.chapter,
            verse: verse ?? 0,
            translation: translation?.rawValue,
            isPresent: isPresent,
            creationDate: creationDate,
            updateDate: updateDate,
            drawingVersion: drawingVersion,
            lineData: lineData,
            layoutMetadataData: layoutMetadataData
        )
    }

    /// 모델을 만든다 — 컨테이너가 이미 있어야 한다(iOS 17).
    func makeRow() -> BibleDrawing {
        let row = BibleDrawing(
            page: page,
            verse: verse ?? 0,
            lineData: lineData,
            updateDate: updateDate,
            layoutMetadataData: layoutMetadataData,
            rowUUID: rowUUID
        )
        row.id = businessID
        row.verse = verse
        row.creationDate = creationDate
        row.translation = translation
        row.isPresent = isPresent
        row.drawingVersion = drawingVersion
        // init 규칙에 기대지 않고 권 이름을 적는다(영어 장은 `KJV-…`).
        row.titleName = titleName
        if dropsChapter { row.titleChapter = nil }
        return row
    }
}

/// 시험이 바꿀 수 있는 편집 환경 — 장 사이 계정 변경을 재현한다.
struct SwitchableBackupEnvironment: DrawingEditEnvironmentClient {
    private let box: LockIsolated<DrawingEditEnvironment>

    init(_ environment: DrawingEditEnvironment) {
        box = LockIsolated(environment)
    }

    /// 다음 `current()` 부터 이 환경을 돌려준다.
    func set(_ environment: DrawingEditEnvironment) {
        box.setValue(environment)
    }

    func current() async -> DrawingEditEnvironment { box.value }
    func isCurrent(_ token: AccountServerWorkToken) async -> Bool { box.value.serverWork == token }
    func changes() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

/// 진행 기록.
struct BackupProgressRecorder {
    private let box = LockIsolated<[BackupProgress]>([])

    var events: [BackupProgress] { box.value }

    func record(_ progress: BackupProgress) {
        box.withValue { $0.append(progress) }
    }
}

/// 내보내기 시험 하나의 세계 — 인메모리 저장소 · 이 시험만의 보존 영역 · 작업 폴더 자리(실제 `BackupWork` 를 쓰지 않는다). 끝나면 `remove()`.
struct BackupExportHarness {
    let container: ModelContainer
    let database: SwiftDatabaseActor
    let root: URL
    let writer: LocalPreservationWriter

    /// 이 시험의 작업 폴더 부모.
    var workRoot: URL { root.appendingPathComponent("BackupWork", isDirectory: true) }
    /// 보존 영역.
    var preservation: PreservationArea {
        PreservationArea(root: root.appendingPathComponent("Preservation", isDirectory: true), storeFileName: "Carve.sqlite")
    }

    init() throws {
        container = try ModelContainer(for: AppStoreSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        database = SwiftDatabaseActor(modelContainer: container)
        root = FileManager.default.temporaryDirectory.appendingPathComponent("backup-export-\(UUID().uuidString)", isDirectory: true)
        writer = LocalPreservationWriter(
            area: PreservationArea(root: root.appendingPathComponent("Preservation", isDirectory: true), storeFileName: "Carve.sqlite"),
            eraseState: EraseStateArea(root: root.appendingPathComponent("EraseState", isDirectory: true), storeFileName: "Carve.sqlite")
        )
    }

    /// 이 시험의 폴더를 모두 지운다.
    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    /// 이 세계의 내보내기.
    func exporter(_ environment: any DrawingEditEnvironmentClient) -> LiveBackupExporter {
        LiveBackupExporter(
            environment: environment,
            drafts: writer,
            database: database,
            appVersion: "2.1.0",
            workRoot: workRoot,
            limits: .default,
            now: { BackupExportSample.now }
        )
    }

    /// 행을 심는다 — 같은 컨테이너의 새 문맥에 넣고 저장한다(모델을 actor 로 넘기지 않는다).
    func seed(_ rows: [BackupExportRowSeed]) throws {
        let context = ModelContext(container)
        for seed in rows {
            context.insert(seed.makeRow())
        }
        try context.save()
    }

    /// 필사책 정보를 심는다 — 같은 컨테이너의 새 문맥에 넣고 저장한다. 레코드 값은 그대로다(같은 ID 둘 · 형식이 아닌 ID 도 심을 수 있다).
    func seedNotebooks(_ records: [BackupNotebookRecord]) throws {
        let context = ModelContext(container)
        for record in records {
            context.insert(BackupNotebookSeed.makeNotebook(record))
        }
        try context.save()
    }

    /// 초안을 남긴다(묶음은 초안의 계정 근거가 정한다).
    func save(_ drafts: [VerseDraft]) async throws {
        for draft in drafts {
            #expect(try await writer.saveDraft(draft) == .written)
        }
    }

    /// 만든 파일을 시험이 따로 푼다 — 내보내기의 재검증과 별개로 담긴 것을 본다.
    func open(_ result: BackupExportResult, password: String = BackupExportSample.password) throws -> BackupPayload {
        let unpacked = try BackupArchive.read(
            from: result.fileURL,
            password: password,
            into: root.appendingPathComponent("opened-\(UUID().uuidString)", isDirectory: true),
            maxEntryBytes: BackupLimits.default.archiveEntryLimit,
            maxTotalBytes: BackupLimits.default.maxTotalBytes
        )
        return try BackupPayload.load(rootDirectory: unpacked, limits: .default)
    }

    /// 작업 폴더 부모에 남은 것.
    func leftovers() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: workRoot.path)) ?? []).sorted()
    }
}

extension BackupPayload {
    /// 행 키로 찾은 행 항목.
    func row(_ rowKey: String) -> BackupItem? {
        items.first { $0.kind == .row && $0.source.rowKey == rowKey }
    }

    /// 절로 찾은 초안 항목들.
    func drafts(verse: Int) -> [BackupItem] {
        items.filter { $0.kind == .draft && $0.verse.verse == verse }
    }

    /// blob 바이트(없으면 nil).
    func bytes(_ name: String?) -> Data? {
        name.flatMap { try? blob(named: $0) }
    }
}
