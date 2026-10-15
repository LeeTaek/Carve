//
//  NotebookRepositoryTesting.swift
//  DomainTest
//
//  2.2 「회차별 필사책」 — 필사책 저장소(`SwiftDataNotebookRepository`)와 전체 삭제.
//  목록(기본 필사책이 늘 첫째 · 메타데이터 없는 접두 행 · 같은 ID 레코드 둘 · 모르는 상태 · 쓴 절 수) · 만들기 · 이름 바꾸기 · 완료 표시/취소 ·
//  지우기(그 필사책의 행과 레코드만, 기본 필사책은 거절, 세대는 그대로) · 전체 삭제가 필사책 정보도 지우는지 고정한다.
//  시험마다 인메모리 컨테이너를 따로 연다 — 공유 actor(`createSwiftDataActor.testValue`)를 쓰지 않는다. @Model 은 컨테이너를 연 뒤 만든다.
//

@testable import Domain
import Foundation
import PencilKit
import SwiftData
import Testing

@Suite("회차별 필사책 — 필사책 저장소 (SwiftData)")
struct NotebookRepositoryTesting {
    fileprivate static let notebookA = NotebookID.make(uuid: UUID(uuidString: "0F3A9C2E-7B41-4D6A-9E15-2C8B7D04A1F3")!)
    fileprivate static let notebookB = NotebookID.make(uuid: UUID(uuidString: "A1B2C3D4-E5F6-4789-8ABC-DEF012345678")!)
    fileprivate static let notebookC = NotebookID.make(uuid: UUID(uuidString: "C0FFEE00-1234-4567-89AB-CDEF01234567")!)
    fileprivate static let notebookD = NotebookID.make(uuid: UUID(uuidString: "D00D0000-1111-4222-8333-444455556666")!)
    private static let base = Date(timeIntervalSince1970: 1_700_000_000)

    /// 실제 획이 하나 있는 `PKDrawing` 데이터 — 한 번 만들어 재사용한다(만들 때마다 바이트가 다르다).
    private static let inkData: Data = {
        let path = PKStrokePath(
            controlPoints: [PKStrokePoint(location: CGPoint(x: 5, y: 5), timeOffset: 0,
                                          size: CGSize(width: 2, height: 2), opacity: 1,
                                          force: 1, azimuth: 0, altitude: 0)],
            creationDate: Date(timeIntervalSince1970: 0)
        )
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: path)]).dataRepresentation()
    }()

    private static func at(_ seconds: TimeInterval) -> Date {
        base.addingTimeInterval(seconds)
    }

    private static func page(_ notebook: NotebookID, chapter: Int = 1, translation: Translation = .NKRV) -> NotebookChapter {
        NotebookChapter(notebook: notebook, chapter: BibleChapter(title: .psalms, chapter: chapter, translation: translation))
    }

    /// 메타데이터 없는 기본 필사책 — 빈 저장소의 목록.
    private static let bareDefault = NotebookSnapshot(
        id: .default, name: nil, status: .active, createdAt: nil, completedAt: nil, writtenVerseCount: 0, hasMetadata: false
    )

    // MARK: 목록

    @Test("빈 저장소 — 메타데이터 없는 기본 필사책 하나")
    func emptyStoreListsDefaultOnly() async throws {
        let harness = try NotebookRepositoryHarness()

        #expect(try await harness.repository.notebooks() == [Self.bareDefault])
    }

    @Test("목록 — 기본이 늘 첫째, 나머지는 만든 시각 오름차순이고 만든 시각이 없는(메타데이터 없는) 필사책은 뒤에 ID 순")
    func notebooksAreOrderedDefaultFirstThenCreation() async throws {
        let harness = try NotebookRepositoryHarness()
        // 기본 필사책 메타데이터는 가장 늦게 만들었어도 첫째다.
        try harness.seedRecord(.default, name: "처음", createdAt: Self.at(900), updatedAt: Self.at(900))
        try harness.seedRecord(Self.notebookB, name: "셋째", createdAt: Self.at(300), updatedAt: Self.at(300))
        try harness.seedRecord(Self.notebookA, name: "둘째", createdAt: Self.at(100), updatedAt: Self.at(100))
        // 메타데이터 없이 행만 있는 필사책 둘 — D 가 먼저 들어가도 ID 순(C < D)이다.
        try harness.seedRow(Self.page(Self.notebookD), verse: 1, lineData: Self.inkData, updateDate: Self.at(10))
        try harness.seedRow(Self.page(Self.notebookC), verse: 1, lineData: Self.inkData, updateDate: Self.at(10))

        let notebooks = try await harness.repository.notebooks()

        #expect(notebooks.map(\.id) == [.default, Self.notebookA, Self.notebookB, Self.notebookC, Self.notebookD])
        #expect(notebooks.map(\.name) == ["처음", "둘째", "셋째", nil, nil])
    }

    @Test("메타데이터 없이 접두 행만 있는 필사책은 hasMetadata false · 이름 · 만든 시각 nil 로 들고, 풀 수 없는 행 · 레코드는 건너뛴다")
    func rowsWithoutMetadataAppearAsUnnamedNotebook() async throws {
        let harness = try NotebookRepositoryHarness()
        try harness.seedRow(Self.page(Self.notebookC), verse: 3, lineData: Self.inkData, updateDate: Self.at(10), creationDate: Self.at(5))
        // 깨진 접두(대문자 토큰) 행과 형식이 맞지 않는 ID 의 레코드 — 필사책이 아니다.
        try harness.seedRow(
            Self.page(Self.notebookD), verse: 1, lineData: Self.inkData, updateDate: Self.at(10),
            titleName: "nb_0F3A9C2E7B414D6A9E152C8B7D04A1F3~1-19Psalms.txt"
        )
        try harness.seedRecord(rawID: "not-a-notebook", name: "깨진 레코드", createdAt: Self.at(1), updatedAt: Self.at(1))

        let notebooks = try await harness.repository.notebooks()

        #expect(notebooks == [
            Self.bareDefault,
            NotebookSnapshot(id: Self.notebookC, name: nil, status: .active, createdAt: nil, completedAt: nil, writtenVerseCount: 1, hasMetadata: false)
        ])
    }

    @Test("같은 ID 레코드가 둘이면(동기화 중복) updatedAt 최신 하나, 같으면 이름 사전순을 쓴다")
    func duplicateRecordsResolveToLatest() async throws {
        let harness = try NotebookRepositoryHarness()
        try harness.seedRecord(
            Self.notebookA, name: "기기 A", status: "completed", createdAt: Self.at(1), updatedAt: Self.at(100), completedAt: Self.at(100)
        )
        try harness.seedRecord(Self.notebookA, name: "기기 B", status: "active", createdAt: Self.at(2), updatedAt: Self.at(200))
        try harness.seedRecord(Self.notebookB, name: "나", createdAt: Self.at(3), updatedAt: Self.at(300))
        try harness.seedRecord(Self.notebookB, name: "가", createdAt: Self.at(3), updatedAt: Self.at(300))

        let notebooks = try await harness.repository.notebooks()

        #expect(notebooks.count == 3)
        #expect(notebooks[1] == NotebookSnapshot(
            id: Self.notebookA, name: "기기 B", status: .active, createdAt: Self.at(2), completedAt: nil, writtenVerseCount: 0, hasMetadata: true
        ))
        #expect(notebooks[2].id == Self.notebookB)
        #expect(notebooks[2].name == "가")
    }

    @Test("모르는 상태 값 · 상태 없음은 active 로 읽는다")
    func unknownStatusReadsActive() async throws {
        let harness = try NotebookRepositoryHarness()
        try harness.seedRecord(Self.notebookA, name: "보관", status: "archived", createdAt: Self.at(1), updatedAt: Self.at(1))
        try harness.seedRecord(Self.notebookB, name: "상태 없음", status: nil, createdAt: Self.at(2), updatedAt: Self.at(2))

        let notebooks = try await harness.repository.notebooks()

        #expect(notebooks.map(\.status) == [.active, .active, .active])
        #expect(notebooks.map(\.hasMetadata) == [false, true, true])
    }

    @Test("기본 필사책의 만든 시각 — 메타데이터가 없으면 접두 없는 행의 가장 이른 creationDate(다른 필사책 행은 보지 않는다)")
    func defaultCreatedAtFallsBackToEarliestUnprefixedRow() async throws {
        let harness = try NotebookRepositoryHarness()
        try harness.seedRow(Self.page(.default), verse: 1, lineData: Self.inkData, updateDate: Self.at(50), creationDate: Self.at(40))
        try harness.seedRow(Self.page(.default, translation: .KJV), verse: 1, lineData: nil, updateDate: Self.at(30), creationDate: Self.at(20))
        try harness.seedRow(Self.page(Self.notebookA), verse: 1, lineData: Self.inkData, updateDate: Self.at(10), creationDate: Self.at(5))

        let notebooks = try await harness.repository.notebooks()

        #expect(notebooks.first?.createdAt == Self.at(20))
        #expect(notebooks.first?.hasMetadata == false)
        // 메타데이터 없는 다른 필사책은 행이 있어도 만든 시각이 없다.
        #expect(notebooks.last?.id == Self.notebookA)
        #expect(notebooks.last?.createdAt == nil)
    }

    // MARK: 쓴 절 수

    @Test("쓴 절 수 — 절마다 대표 행에 잉크가 있는 것만, 번역본은 합산하고 비운 대표 · 보관 행 · 다른 필사책은 세지 않는다")
    func writtenVerseCountUsesRepresentativeInk() async throws {
        let harness = try NotebookRepositoryHarness()
        let psalm = Self.page(.default)
        // 1절: 잉크가 있는 대표 — 센다. 같은 절에 잉크 행이 둘이어도 한 절이다.
        try harness.seedRow(psalm, verse: 1, lineData: Self.inkData, updateDate: Self.at(10))
        try harness.seedRow(psalm, verse: 1, lineData: Self.inkData, updateDate: Self.at(5), isPresent: false)
        // 2절: 지우기 — 잉크는 보관 행(isPresent false)에만 있고 대표는 비었다. 세지 않는다.
        try harness.seedRow(psalm, verse: 2, lineData: Self.inkData, updateDate: Self.at(10), isPresent: false)
        try harness.seedRow(psalm, verse: 2, lineData: nil, updateDate: Self.at(20))
        // 3절: 비운 행뿐 — 세지 않는다.
        try harness.seedRow(psalm, verse: 3, lineData: nil, updateDate: Self.at(10))
        // 4절: 대표 행이 둘(CloudKit 충돌) — 최신이 비었으면 세지 않는다.
        try harness.seedRow(psalm, verse: 4, lineData: Self.inkData, updateDate: Self.at(10))
        try harness.seedRow(psalm, verse: 4, lineData: nil, updateDate: Self.at(30))
        // 5절: 대표가 없으면(isPresent 행 없음) updateDate 최신 — 잉크가 있으면 센다.
        try harness.seedRow(psalm, verse: 5, lineData: nil, updateDate: Self.at(10), isPresent: false)
        try harness.seedRow(psalm, verse: 5, lineData: Self.inkData, updateDate: Self.at(40), isPresent: false)
        // 다른 장 · 다른 번역본의 같은 절 — 따로 센다.
        try harness.seedRow(Self.page(.default, chapter: 2), verse: 1, lineData: Self.inkData, updateDate: Self.at(10))
        try harness.seedRow(Self.page(.default, translation: .KJV), verse: 1, lineData: Self.inkData, updateDate: Self.at(10))
        try harness.seedRow(Self.page(.default, translation: .BSB), verse: 1, lineData: nil, updateDate: Self.at(10))
        // 필사책 A 의 같은 절 — 기본 필사책 수에 들지 않는다.
        try harness.seedRow(Self.page(Self.notebookA), verse: 1, lineData: Self.inkData, updateDate: Self.at(10))
        try harness.seedRow(Self.page(Self.notebookA), verse: 2, lineData: Self.inkData, updateDate: Self.at(10))
        try harness.seedRow(Self.page(Self.notebookA, translation: .KJV), verse: 2, lineData: Self.inkData, updateDate: Self.at(10))

        let notebooks = try await harness.repository.notebooks()

        // 기본: 1절 · 5절 · 2장 1절 · KJV 1절 = 4. A: 1절 · 2절 · KJV 2절 = 3.
        #expect(notebooks.map(\.id) == [.default, Self.notebookA])
        #expect(notebooks.map(\.writtenVerseCount) == [4, 3])
    }

    @Test("쓴 절 수 — 저장소 경로의 지우기(보관 후 비움)를 한 절은 세지 않는다")
    func archivedVerseIsNotCounted() async throws {
        let harness = try NotebookRepositoryHarness()
        let drawings = SwiftDataDrawingRepository(actor: harness.actor)
        let page = Self.page(Self.notebookA)
        let first = BibleDrawingRowID.issue()
        let second = BibleDrawingRowID.issue()
        let generation = try await drawings.load(page).generation
        try await drawings.apply([
            .create(verse: 1, rowID: first, data: Self.inkData, metadata: NotebookRepositoryHarness.metadata(verse: 1)),
            .create(verse: 2, rowID: second, data: Self.inkData, metadata: NotebookRepositoryHarness.metadata(verse: 2))
        ], page: page, generation: generation)
        #expect(try await harness.repository.notebooks().last?.writtenVerseCount == 2)

        let outcome = try await drawings.archiveAndReset(
            VerseDrawingArchiveCommand(verse: 2, activeRowID: second, archiveRowID: .issue()), page: page
        )

        #expect(outcome == .archived)
        #expect(try await harness.repository.notebooks().last?.writtenVerseCount == 1)
    }

    // MARK: 만들기 · 이름 · 완료

    @Test("만들기 — 레코드 하나(종류 personal · 상태 active · 만든 시각 = 바꾼 시각 = now · 예약 필드 nil)")
    func createInsertsActivePersonalRecord() async throws {
        let harness = try NotebookRepositoryHarness()

        try await harness.repository.create(id: Self.notebookA, name: "두 번째 필사", now: Self.at(100))

        #expect(try harness.records() == [NotebookRecordValue(
            notebookID: Self.notebookA.rawValue, name: "두 번째 필사", status: "active", createdAt: Self.at(100), updatedAt: Self.at(100),
            completedAt: nil, kind: "personal", scopeData: nil, linkData: nil
        )])
        #expect(try await harness.repository.notebooks() == [
            Self.bareDefault,
            NotebookSnapshot(
                id: Self.notebookA, name: "두 번째 필사", status: .active, createdAt: Self.at(100), completedAt: nil,
                writtenVerseCount: 0, hasMetadata: true
            )
        ])
    }

    @Test("이름 바꾸기 · 완료 표시 · 완료 취소 — 바꾼 시각을 남기고 만든 시각 · 이름은 그대로 둔다")
    func renameAndCompletionUpdateRecord() async throws {
        let harness = try NotebookRepositoryHarness()
        try await harness.repository.create(id: Self.notebookA, name: "두 번째 필사", now: Self.at(100))

        try await harness.repository.rename(Self.notebookA, to: "시편 묵상", now: Self.at(200))
        var notebook = try #require(try await harness.repository.notebooks().last)
        #expect(notebook.name == "시편 묵상")
        #expect(notebook.createdAt == Self.at(100))
        #expect(try harness.records().map(\.updatedAt) == [Self.at(200)])

        try await harness.repository.setCompleted(Self.notebookA, true, now: Self.at(300))
        notebook = try #require(try await harness.repository.notebooks().last)
        #expect(notebook.status == .completed)
        #expect(notebook.completedAt == Self.at(300))
        #expect(notebook.name == "시편 묵상")
        #expect(try harness.records().map(\.status) == ["completed"])
        #expect(try harness.records().map(\.updatedAt) == [Self.at(300)])

        try await harness.repository.setCompleted(Self.notebookA, false, now: Self.at(400))
        notebook = try #require(try await harness.repository.notebooks().last)
        #expect(notebook.status == .active)
        #expect(notebook.completedAt == nil)
        #expect(try harness.records().map(\.status) == ["active"])
        #expect(try harness.records().map(\.updatedAt) == [Self.at(400)])
        #expect(try harness.records().count == 1)
    }

    @Test("기본 필사책 이름 바꾸기 — 메타데이터가 없으면 「default」 레코드를 만들고 만든 시각은 접두 없는 행의 가장 이른 creationDate")
    func renamingDefaultCreatesMetadata() async throws {
        let harness = try NotebookRepositoryHarness()
        try harness.seedRow(Self.page(.default), verse: 1, lineData: Self.inkData, updateDate: Self.at(50), creationDate: Self.at(40))
        try harness.seedRow(Self.page(.default, chapter: 3), verse: 2, lineData: Self.inkData, updateDate: Self.at(30), creationDate: Self.at(20))
        try harness.seedRow(Self.page(Self.notebookA), verse: 1, lineData: Self.inkData, updateDate: Self.at(10), creationDate: Self.at(5))

        try await harness.repository.rename(.default, to: "나의 첫 필사", now: Self.at(500))

        #expect(try harness.records() == [NotebookRecordValue(
            notebookID: "default", name: "나의 첫 필사", status: "active", createdAt: Self.at(20), updatedAt: Self.at(500),
            completedAt: nil, kind: "personal", scopeData: nil, linkData: nil
        )])
        #expect(try await harness.repository.notebooks().first == NotebookSnapshot(
            id: .default, name: "나의 첫 필사", status: .active, createdAt: Self.at(20), completedAt: nil, writtenVerseCount: 2, hasMetadata: true
        ))
    }

    @Test("완료 표시 — 메타데이터도 행도 없으면 레코드를 만들고 만든 시각은 now")
    func completingWithoutMetadataCreatesRecord() async throws {
        let harness = try NotebookRepositoryHarness()

        try await harness.repository.setCompleted(.default, true, now: Self.at(700))

        #expect(try harness.records() == [NotebookRecordValue(
            notebookID: "default", name: nil, status: "completed", createdAt: Self.at(700), updatedAt: Self.at(700),
            completedAt: Self.at(700), kind: "personal", scopeData: nil, linkData: nil
        )])
        let notebook = try #require(try await harness.repository.notebooks().first)
        #expect(notebook.name == nil)
        #expect(notebook.status == .completed)
    }

    @Test("같은 ID 레코드가 둘일 때 이름을 바꾸면 둘 다 지금 보이는 값으로 맞춘 뒤 바꾼다")
    func renameConvergesDuplicateRecords() async throws {
        let harness = try NotebookRepositoryHarness()
        try harness.seedRecord(
            Self.notebookA, name: "기기 A", status: "completed", createdAt: Self.at(1), updatedAt: Self.at(100), completedAt: Self.at(100)
        )
        try harness.seedRecord(Self.notebookA, name: "기기 B", status: "active", createdAt: Self.at(2), updatedAt: Self.at(200))

        try await harness.repository.rename(Self.notebookA, to: "합친 이름", now: Self.at(300))

        let records = try harness.records()
        #expect(records.count == 2)
        #expect(records.allSatisfy {
            $0.name == "합친 이름" && $0.status == "active" && $0.completedAt == nil
                && $0.createdAt == Self.at(2) && $0.updatedAt == Self.at(300)
        })
        let notebook = try #require(try await harness.repository.notebooks().last)
        #expect(notebook.name == "합친 이름")
        #expect(notebook.status == .active)
    }

}

// MARK: - 지우기 · 전체 삭제 · 성능

extension NotebookRepositoryTesting {

    @Test("지우기 — 그 필사책의 행(모든 번역본)과 레코드 전부만 사라지고 기본 · 다른 필사책은 그대로, 저장소 세대도 그대로")
    func deleteRemovesOnlyThatNotebook() async throws {
        let harness = try NotebookRepositoryHarness()
        try harness.seedRow(Self.page(.default), verse: 1, lineData: Self.inkData, updateDate: Self.at(10))
        try harness.seedRow(Self.page(.default, translation: .KJV), verse: 1, lineData: Self.inkData, updateDate: Self.at(10))
        try harness.seedRow(Self.page(Self.notebookA), verse: 1, lineData: Self.inkData, updateDate: Self.at(10))
        try harness.seedRow(Self.page(Self.notebookA), verse: 1, lineData: nil, updateDate: Self.at(5), isPresent: false)
        try harness.seedRow(Self.page(Self.notebookA, chapter: 9, translation: .BSB), verse: 4, lineData: Self.inkData, updateDate: Self.at(10))
        try harness.seedRow(Self.page(Self.notebookB), verse: 1, lineData: Self.inkData, updateDate: Self.at(10))
        try harness.seedRecord(Self.notebookA, name: "A 기기 1", createdAt: Self.at(1), updatedAt: Self.at(1))
        try harness.seedRecord(Self.notebookA, name: "A 기기 2", createdAt: Self.at(1), updatedAt: Self.at(2))
        try harness.seedRecord(Self.notebookB, name: "B", createdAt: Self.at(3), updatedAt: Self.at(3))
        try harness.seedRecord(.default, name: "처음", createdAt: Self.at(0), updatedAt: Self.at(0))
        let drawings = SwiftDataDrawingRepository(actor: harness.actor)
        let generation = try await drawings.load(Self.page(Self.notebookB)).generation

        try await harness.repository.delete(Self.notebookA)

        let prefixA = StoredBookKey.titleName(title: .psalms, translation: .NKRV, notebook: Self.notebookA)
        let titleNames = try harness.rowTitleNames()
        #expect(titleNames.count == 3)
        #expect(!titleNames.contains(prefixA))
        #expect(titleNames.allSatisfy { StoredBookKey.decodeRow($0 ?? "")?.notebook != Self.notebookA })
        #expect(try harness.records().map(\.notebookID).sorted { ($0 ?? "") < ($1 ?? "") } == ["a1b2c3d4e5f647898abcdef012345678", "default"])
        let notebooks = try await harness.repository.notebooks()
        #expect(notebooks.map(\.id) == [.default, Self.notebookB])
        #expect(notebooks.map(\.writtenVerseCount) == [2, 1])
        // 필사책 하나를 지워도 세대는 그대로 — 다른 필사책에 열린 장의 저장이 막히지 않는다.
        #expect(try await drawings.load(Self.page(Self.notebookB)).generation == generation)
        let rowID = BibleDrawingRowID.issue()
        try await drawings.apply(
            [.create(verse: 2, rowID: rowID, data: Self.inkData, metadata: NotebookRepositoryHarness.metadata(verse: 2))],
            page: Self.page(Self.notebookB), generation: generation
        )
    }

    @Test("기본 필사책 지우기는 cannotDeleteDefault 로 거절하고 아무것도 지우지 않는다")
    func deletingDefaultIsRejected() async throws {
        let harness = try NotebookRepositoryHarness()
        try harness.seedRow(Self.page(.default), verse: 1, lineData: Self.inkData, updateDate: Self.at(10))
        try harness.seedRow(Self.page(Self.notebookA), verse: 1, lineData: Self.inkData, updateDate: Self.at(10))
        try harness.seedRecord(.default, name: "처음", createdAt: Self.at(0), updatedAt: Self.at(0))

        await #expect(throws: NotebookRepositoryError.cannotDeleteDefault) {
            try await harness.repository.delete(.default)
        }
        await #expect(throws: NotebookRepositoryError.cannotDeleteDefault) {
            try await harness.actor.deleteNotebook(.default)
        }

        #expect(try harness.rowTitleNames().count == 2)
        #expect(try harness.records().map(\.notebookID) == ["default"])
    }

    // MARK: 전체 삭제

    @Test("전체 삭제는 필사책 정보(DrawingNotebook)도 지운다 — 지운 뒤 목록은 메타데이터 없는 기본 필사책 하나")
    func eraseAllRemovesNotebookRecords() async throws {
        let harness = try NotebookRepositoryHarness()
        try harness.seedRow(Self.page(.default), verse: 1, lineData: Self.inkData, updateDate: Self.at(10))
        try harness.seedRow(Self.page(Self.notebookA), verse: 1, lineData: Self.inkData, updateDate: Self.at(10))
        try await harness.repository.create(id: Self.notebookA, name: "두 번째 필사", now: Self.at(100))
        try await harness.repository.rename(.default, to: "나의 첫 필사", now: Self.at(200))
        try #require(try harness.records().count == 2)

        #expect(await SwiftDataDrawingDataEraser(actor: harness.actor).eraseAll() == .completed)

        #expect(try harness.records().isEmpty)
        #expect(try harness.rowTitleNames().isEmpty)
        #expect(try await harness.repository.notebooks() == [Self.bareDefault])
    }

    // MARK: 성능

    /// 행 1만 개(필사책 둘 × 번역본 둘 × 절 1,250개 × 절마다 보관 행 + 활성 행)에서 목록을 읽는다. 디스크 저장소다.
    ///
    /// 잉크는 획 여러 개의 실제 `PKDrawing`(약 5KB)이다. 목록은 처음(차가운 캐시) · 다시 두 번 재고, 비교로 모든 행의 잉크 바이트를 읽는 시간도 잰다 —
    /// 수치는 첨부 `NotebookPerf.txt` 다. 부분 조회(`propertiesToFetch`) · 대표 잉크 디코딩과의 비교는 `writtenVerseScan()` 주석에 적었다.
    @Test("성능 — 행 1만 개의 목록 · 쓴 절 수")
    func notebooksScaleToTenThousandRows() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("NotebookPerf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let harness = try NotebookRepositoryHarness(storeURL: directory.appendingPathComponent("Notebooks.sqlite"))
        let ink = Self.makeInk(strokes: 12, points: 24)
        let pages = [NotebookID.default, Self.notebookA].flatMap { notebook in
            [Translation.NKRV, .KJV].map { (notebook: notebook, translation: $0) }
        }
        try harness.seedBulk { context in
            for bucket in pages {
                for index in 0..<1_250 {
                    let page = Self.page(bucket.notebook, chapter: 1 + index / 10, translation: bucket.translation)
                    let verse = 1 + index % 10
                    // 보관 행 — 잉크가 있지만 대표가 아니다.
                    let archived = BibleDrawing(page: page, verse: verse, lineData: ink, updateDate: Self.at(10), rowUUID: UUID().uuidString)
                    archived.isPresent = false
                    context.insert(archived)
                    // 활성 행 — 짝수 절만 잉크가 남았다.
                    let active = BibleDrawing(
                        page: page, verse: verse, lineData: index.isMultiple(of: 2) ? ink : nil, updateDate: Self.at(20), rowUUID: UUID().uuidString
                    )
                    active.isPresent = true
                    context.insert(active)
                }
            }
        }
        try #require(try harness.rowCount() == 10_000)
        let container = harness.actor.modelContainer

        // 이 저장소의 방법 — 새 actor(새 문맥)에서 잰다. 처음 한 번 · 다시 한 번.
        let clock = ContinuousClock()
        let coldStart = clock.now
        let notebooks = try await SwiftDataNotebookRepository(actor: SwiftDatabaseActor(modelContainer: container)).notebooks()
        let cold = clock.now - coldStart
        let warmStart = clock.now
        let again = try await SwiftDataNotebookRepository(actor: SwiftDatabaseActor(modelContainer: container)).notebooks()
        let warm = clock.now - warmStart
        // 비교 — 모든 행의 잉크 바이트를 읽는다.
        let inkReadStart = clock.now
        let inkBytes = try await SwiftDatabaseActor(modelContainer: container).totalInkBytes()
        let inkRead = clock.now - inkReadStart

        let report = """
        rows=10000 inkBytesPerRow=\(ink.count) inkRows=7500
        notebooks() cold=\(cold) warm=\(warm)
        fullInkRead=\(inkRead) bytes=\(inkBytes)
        """
        Attachment.record(report, named: "NotebookPerf.txt")

        #expect(notebooks.map(\.id) == [.default, Self.notebookA])
        #expect(notebooks.map(\.writtenVerseCount) == [1_250, 1_250])
        #expect(again == notebooks)
        #expect(inkBytes == 7_500 * ink.count)
        #expect(cold < .seconds(10))
    }

    /// 획 여러 개의 `PKDrawing` 데이터.
    private static func makeInk(strokes: Int, points: Int) -> Data {
        let drawing = PKDrawing(strokes: (0..<strokes).map { strokeIndex in
            let controlPoints = (0..<points).map { pointIndex in
                PKStrokePoint(location: CGPoint(x: CGFloat(pointIndex * 3), y: CGFloat(strokeIndex * 5)), timeOffset: TimeInterval(pointIndex) * 0.01,
                              size: CGSize(width: 2, height: 2), opacity: 1, force: 1, azimuth: 0, altitude: 0)
            }
            return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: controlPoints, creationDate: Date(timeIntervalSince1970: 0)))
        })
        return drawing.dataRepresentation()
    }
}

// MARK: - 하네스

/// 시험 하나의 저장소 — actor 와 필사책 저장소가 같은 컨테이너를 본다. 행 · 레코드는 새 문맥으로 직접 심고 읽는다(모델은 actor 로 넘기지 않는다).
private struct NotebookRepositoryHarness {
    let actor: SwiftDatabaseActor
    let repository: SwiftDataNotebookRepository

    /// - Parameter storeURL: 디스크 저장소 경로. nil 이면 인메모리.
    init(storeURL: URL? = nil) throws {
        let configuration = storeURL.map { ModelConfiguration(url: $0, cloudKitDatabase: .none) }
            ?? ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: AppStoreSchema.schema, configurations: configuration)
        actor = SwiftDatabaseActor(modelContainer: container)
        repository = SwiftDataNotebookRepository(actor: actor)
    }

    static func metadata(verse: Int) -> DrawingLayoutMetadata {
        DrawingLayoutMetadata(
            baseWritingWidth: 372,
            baseWritingHeight: 60,
            baseUnderlineAnchors: [0, 30],
            layoutSignature: "cl1-notebook-\(verse)"
        )
    }

    /// 필사 행 하나를 심는다 — 다른 기기가 실어 온 행처럼 저장소를 거치지 않는다.
    /// - Parameters:
    ///   - creationDate: 넣으면 행의 `creationDate` 를 이 값으로 덮는다.
    ///   - titleName: 넣으면 `titleName` 을 이 값으로 덮는다(깨진 접두 흉내).
    func seedRow(
        _ page: NotebookChapter,
        verse: Int,
        lineData: Data?,
        updateDate: Date,
        isPresent: Bool = true,
        creationDate: Date? = nil,
        titleName: String? = nil
    ) throws {
        try seedBulk { context in
            let row = BibleDrawing(page: page, verse: verse, lineData: lineData, updateDate: updateDate, rowUUID: UUID().uuidString)
            row.isPresent = isPresent
            if let creationDate {
                row.creationDate = creationDate
            }
            if let titleName {
                row.titleName = titleName
            }
            context.insert(row)
        }
    }

    /// 새 문맥에 여러 모델을 넣고 한 번 저장한다.
    func seedBulk(_ insert: (ModelContext) throws -> Void) throws {
        let context = ModelContext(actor.modelContainer)
        context.autosaveEnabled = false
        try insert(context)
        try context.save()
    }

    /// 필사책 메타데이터 레코드 하나를 심는다.
    func seedRecord(
        _ notebook: NotebookID,
        name: String?,
        status: String? = "active",
        createdAt: Date?,
        updatedAt: Date?,
        completedAt: Date? = nil
    ) throws {
        try seedRecord(rawID: notebook.rawValue, name: name, status: status, createdAt: createdAt, updatedAt: updatedAt, completedAt: completedAt)
    }

    /// 형식 검사 없이 `notebookID` 문자열 그대로 레코드를 심는다.
    func seedRecord(
        rawID: String?,
        name: String?,
        status: String? = "active",
        createdAt: Date?,
        updatedAt: Date?,
        completedAt: Date? = nil
    ) throws {
        try seedBulk { context in
            let record = DrawingNotebook()
            record.notebookID = rawID
            record.name = name
            record.status = status
            record.createdAt = createdAt
            record.updatedAt = updatedAt
            record.completedAt = completedAt
            record.kind = "personal"
            context.insert(record)
        }
    }

    /// 저장된 레코드를 값으로 읽는다 — 새 문맥에서 읽는다.
    func records() throws -> [NotebookRecordValue] {
        try ModelContext(actor.modelContainer).fetch(FetchDescriptor<DrawingNotebook>()).map(NotebookRecordValue.init(record:))
    }

    /// 저장된 필사 행의 `titleName`.
    func rowTitleNames() throws -> [String?] {
        try ModelContext(actor.modelContainer).fetch(FetchDescriptor<BibleDrawing>()).map(\.titleName)
    }

    /// 저장된 필사 행 수.
    func rowCount() throws -> Int {
        try ModelContext(actor.modelContainer).fetchCount(FetchDescriptor<BibleDrawing>())
    }
}

/// 레코드 한 줄의 값.
private struct NotebookRecordValue: Equatable {
    let notebookID: String?
    let name: String?
    let status: String?
    let createdAt: Date?
    let updatedAt: Date?
    let completedAt: Date?
    let kind: String?
    let scopeData: String?
    let linkData: String?
}

extension NotebookRecordValue {
    init(record: DrawingNotebook) {
        self.init(
            notebookID: record.notebookID,
            name: record.name,
            status: record.status,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            completedAt: record.completedAt,
            kind: record.kind,
            scopeData: record.scopeData,
            linkData: record.linkData
        )
    }
}

private extension SwiftDatabaseActor {
    /// 비교용 — 모든 필사 행의 잉크 바이트를 읽어 길이를 더한다(행마다 `lineData` 를 실제로 읽는다).
    func totalInkBytes() throws -> Int {
        try modelContext.fetch(FetchDescriptor<BibleDrawing>()).reduce(0) { total, row in
            total + (row.lineData?.count ?? 0)
        }
    }
}
