//
//  SwiftDataNotebookRepository.swift
//  Domain
//
//  Created by Claude on 10/15/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation
import SwiftData

import Dependencies

/// `NotebookRepository` 의 SwiftData 구현 (2.2 「회차별 필사책」).
///
/// 모든 읽기 · 쓰기는 `SwiftDatabaseActor` 안에서 일어나고, 쓰기는 actor 메서드 하나가 한 트랜잭션이다 —
/// 변경을 모아 마지막에 `save()` 1회, 실패하면 `rollback()` (`SwiftDataFavoriteVerseRepository` 와 같은 경계).
///
/// - 필사책 목록은 메타데이터(`DrawingNotebook`)와 잉크 행(`BibleDrawing`)의 `titleName` 접두를 합친다 — 메타데이터가 없어도 행이 있으면 필사책이다
///   (혼재 버전 규칙 ⑥). 행의 필사책은 `StoredBookKey.decodeRow` 로만 푼다.
/// - 필사책을 지워도 필사 저장소 세대(`DrawingStoreGeneration`)는 바꾸지 않는다 — 세대를 올리는 곳은 전체 삭제 하나다.
public struct SwiftDataNotebookRepository: NotebookRepository {
    /// 주입한 actor. nil 이면 부를 때의 의존성 actor(`createSwiftDataActor`)를 쓴다.
    private let actor: SwiftDatabaseActor?

    /// - Parameter actor: 사용할 actor. 생략하면 **부를 때** 의존성의 actor 를 읽는다 — 기본값(`liveValue`)이 처음 읽힌 문맥의 컨테이너에
    ///   묶여 전역에 남지 않게 한다(`SwiftDataDrawingDataEraser` 와 같은 방식).
    public init(actor: SwiftDatabaseActor? = nil) {
        self.actor = actor
    }

    /// 이 호출이 쓸 actor.
    private var database: SwiftDatabaseActor {
        if let actor { return actor }
        @Dependency(\.createSwiftDataActor) var injected
        return injected
    }

    public func notebooks() async throws -> [NotebookSnapshot] {
        try await database.loadNotebooks()
    }

    public func create(id: NotebookID, name: String, now: Date) async throws {
        try await database.createNotebook(id: id, name: name, now: now)
    }

    public func rename(_ id: NotebookID, to name: String, now: Date) async throws {
        try await database.renameNotebook(id, to: name, now: now)
    }

    public func setCompleted(_ id: NotebookID, _ completed: Bool, now: Date) async throws {
        try await database.setNotebookCompleted(id, completed, now: now)
    }

    public func delete(_ id: NotebookID) async throws {
        guard !id.isDefault else { throw NotebookRepositoryError.cannotDeleteDefault }
        try await database.deleteNotebook(id)
    }
}

// MARK: - actor 안의 트랜잭션

extension SwiftDatabaseActor {
    /// 필사책 종류 — 1차는 늘 개인 필사책이다(`DrawingNotebook.kind`).
    private static let personalNotebookKind = "personal"

    /// 모든 필사책을 읽는다 — 기본이 늘 첫째, 나머지는 `createdAt` 오름차순이고 nil 은 뒤다(같으면 ID 사전순).
    ///
    /// | 값 | 어디서 |
    /// |---|---|
    /// | 이름 · 상태 · 완료 시각 · 만든 시각 | 같은 `notebookID` 레코드 중 `updatedAt` 최신(같으면 이름 사전순) 하나 — `representativeNotebookRecord(_:)` |
    /// | 메타데이터 없는 필사책 | 행의 `titleName` 접두(`StoredBookKey.decodeRow`)에서 모은 ID — `hasMetadata == false`, 이름 · 만든 시각 nil |
    /// | 기본 필사책의 만든 시각 | 메타데이터가 있으면 그 값, 없으면(또는 값이 nil 이면) 접두 없는 행의 가장 이른 `creationDate` |
    /// | 쓴 절 수 | `writtenVerseScan()` |
    ///
    /// 형식이 맞지 않는 `notebookID` 레코드와 `titleName` 을 풀지 못하는 행은 건너뛴다.
    /// - Returns: 필사책 목록. 저장소가 비어도 기본 필사책 하나는 있다.
    public func loadNotebooks() throws -> [NotebookSnapshot] {
        let records = try modelContext.fetch(FetchDescriptor<DrawingNotebook>())
        var recordsByID: [NotebookID: [DrawingNotebook]] = [:]
        for record in records {
            guard let raw = record.notebookID, let notebook = NotebookID(rawValue: raw) else { continue }
            recordsByID[notebook, default: []].append(record)
        }
        let metadata = recordsByID.compactMapValues(Self.representativeNotebookRecord)
        let scan = try writtenVerseScan()

        func snapshot(_ notebook: NotebookID) -> NotebookSnapshot {
            let record = metadata[notebook]
            let createdAt = notebook.isDefault
                ? (record?.createdAt ?? scan.earliestCreation[notebook])
                : record?.createdAt
            return NotebookSnapshot(
                id: notebook,
                name: record?.name,
                status: NotebookStatus(stored: record?.status),
                createdAt: createdAt,
                completedAt: record?.completedAt,
                writtenVerseCount: scan.writtenVerses[notebook, default: 0],
                hasMetadata: record != nil
            )
        }

        let others = Set(metadata.keys).union(scan.notebooks).subtracting([NotebookID.default])
        let sortedOthers = others.map(snapshot).sorted { lhs, rhs in
            switch (lhs.createdAt, rhs.createdAt) {
            case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
                return lhsDate < rhsDate
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            default:
                return lhs.id.rawValue < rhs.id.rawValue
            }
        }
        return [snapshot(.default)] + sortedOthers
    }

    /// 새 필사책의 메타데이터 레코드 하나를 만든다 — 종류 「personal」 · 상태 「active」 · `createdAt` = `updatedAt` = `now`.
    /// - Parameters:
    ///   - id: 새 필사책 ID.
    ///   - name: 이름(사용자 입력).
    ///   - now: 만든 시각.
    public func createNotebook(id: NotebookID, name: String, now: Date) throws {
        do {
            let record = DrawingNotebook()
            record.notebookID = id.rawValue
            record.name = name
            record.status = NotebookStatus.active.rawValue
            record.createdAt = now
            record.updatedAt = now
            record.kind = Self.personalNotebookKind
            modelContext.insert(record)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// 필사책의 이름을 바꾼다 — 같은 ID 레코드 전부, 없으면 만든다(기본 필사책 포함). `updateNotebook(_:now:change:)` 의 규칙을 따른다.
    /// - Parameters:
    ///   - id: 필사책 ID.
    ///   - name: 새 이름(사용자 입력).
    ///   - now: 바꾼 시각(`updatedAt`).
    public func renameNotebook(_ id: NotebookID, to name: String, now: Date) throws {
        try updateNotebook(id, now: now) { record in
            record.name = name
        }
    }

    /// 완료를 표시하거나 취소한다 — 상태 「completed」 · `completedAt = now`, 취소는 「active」 · `completedAt = nil`.
    /// 같은 ID 레코드 전부, 없으면 만든다(기본 필사책 포함). `updateNotebook(_:now:change:)` 의 규칙을 따른다.
    /// - Parameters:
    ///   - id: 필사책 ID.
    ///   - completed: 완료면 true.
    ///   - now: 바꾼 시각(`updatedAt` · 완료면 `completedAt`).
    public func setNotebookCompleted(_ id: NotebookID, _ completed: Bool, now: Date) throws {
        try updateNotebook(id, now: now) { record in
            record.status = (completed ? NotebookStatus.completed : NotebookStatus.active).rawValue
            record.completedAt = completed ? now : nil
        }
    }

    /// 같은 ID 의 메타데이터 레코드 **전부**를 바꾼다 — 이름 바꾸기 · 완료 표시/취소가 쓴다. 없으면 하나 만든다(기본 필사책 포함).
    ///
    /// 레코드가 둘 이상이면(두 기기가 따로 만듦) 먼저 지금 보이는 레코드(`representativeNotebookRecord(_:)`)의 값으로 모두 맞춘 뒤 바꾼다 —
    /// 바꾼 뒤에는 어느 레코드를 골라도 같은 값이다. 바꾼 레코드는 `updatedAt = now` 다.
    ///
    /// 새로 만드는 레코드의 `createdAt` 은 그 필사책 행의 가장 이른 `creationDate`(행이 없으면 `now`)다 — 기본 필사책의 이름을 처음 바꿔도
    /// 책장 카드의 시작 월이 바뀌지 않는다.
    /// - Parameters:
    ///   - id: 필사책 ID.
    ///   - now: 바꾼 시각.
    ///   - change: 레코드마다 적용할 변경. actor 안에서 동기로 부른다.
    private func updateNotebook(_ id: NotebookID, now: Date, change: (DrawingNotebook) -> Void) throws {
        do {
            let raw = id.rawValue
            let predicate = #Predicate<DrawingNotebook> { $0.notebookID == raw }
            var records = try modelContext.fetch(FetchDescriptor(predicate: predicate))
            if let current = Self.representativeNotebookRecord(records) {
                for record in records where record !== current {
                    record.name = current.name
                    record.status = current.status
                    record.createdAt = current.createdAt
                    record.completedAt = current.completedAt
                    record.kind = current.kind
                }
            } else {
                let record = DrawingNotebook()
                record.notebookID = raw
                record.status = NotebookStatus.active.rawValue
                record.createdAt = try earliestRowCreation(of: id) ?? now
                record.kind = Self.personalNotebookKind
                modelContext.insert(record)
                records = [record]
            }
            for record in records {
                change(record)
                record.updatedAt = now
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// 필사책 하나를 지운다 — 그 필사책의 `BibleDrawing` 행 전부와 `DrawingNotebook` 레코드 전부를 **한 트랜잭션**으로.
    ///
    /// 배치 삭제(`delete(model:where:)`)는 `save()` 를 기다리지 않고 바로 반영돼 둘을 한 트랜잭션으로 묶을 수 없으므로, 행을 가져와 하나씩 지우고
    /// 마지막에 `save()` 1회 한다. 행은 그 필사책의 `titleName` 목록(`rowTitleNames(of:)`)으로 한 번에 가져온다 —
    /// SwiftData 는 행을 가져오면 잉크 열까지 읽으므로(`writtenVerseScan()` 의 측정) 그 필사책의 행만 가져온다.
    /// 필사 저장소 세대는 바꾸지 않는다 — 다른 필사책에 열린 장의 저장을 막지 않는다.
    /// - Parameter id: 지울 필사책. 기본 필사책이면 아무것도 지우지 않고 `cannotDeleteDefault` 를 던진다.
    public func deleteNotebook(_ id: NotebookID) throws {
        guard !id.isDefault else { throw NotebookRepositoryError.cannotDeleteDefault }
        do {
            let titleNames = Self.rowTitleNames(of: id)
            let rowPredicate = #Predicate<BibleDrawing> { row in
                if let titleName = row.titleName {
                    return titleNames.contains(titleName)
                } else {
                    return false
                }
            }
            for row in try modelContext.fetch(FetchDescriptor(predicate: rowPredicate)) {
                modelContext.delete(row)
            }
            let raw = id.rawValue
            let recordPredicate = #Predicate<DrawingNotebook> { $0.notebookID == raw }
            for record in try modelContext.fetch(FetchDescriptor(predicate: recordPredicate)) {
                modelContext.delete(record)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    // MARK: 내부

    /// 같은 `notebookID` 레코드 중 지금 보이는 하나 — `updatedAt` 최신, 같으면 이름 사전순(nil 은 빈 이름), 그래도 같으면 상태 · 만든 시각 순.
    /// - Parameter records: 같은 ID 의 레코드들. 순서는 결과에 영향을 주지 않는다.
    /// - Returns: 고른 레코드. 비었으면 nil.
    private static func representativeNotebookRecord(_ records: [DrawingNotebook]) -> DrawingNotebook? {
        records.min { lhs, rhs in
            let lhsUpdated = lhs.updatedAt ?? .distantPast
            let rhsUpdated = rhs.updatedAt ?? .distantPast
            if lhsUpdated != rhsUpdated { return lhsUpdated > rhsUpdated }
            let lhsName = lhs.name ?? ""
            let rhsName = rhs.name ?? ""
            if lhsName != rhsName { return lhsName < rhsName }
            let lhsStatus = lhs.status ?? ""
            let rhsStatus = rhs.status ?? ""
            if lhsStatus != rhsStatus { return lhsStatus < rhsStatus }
            return (lhs.createdAt ?? .distantPast) < (rhs.createdAt ?? .distantPast)
        }
    }

    /// 필사책의 행이 가질 수 있는 `titleName` 전부 — 모든 권 × 번역본을 `StoredBookKey` 로 짓는다.
    ///
    /// `decodeRow` 가 그 필사책으로 푸는 `titleName` 과 정확히 같은 집합이다. 접두 문자열을 직접 잇지 않으려고 이렇게 짓는다.
    private static func rowTitleNames(of notebook: NotebookID) -> [String] {
        BibleTitle.allCases.flatMap { title in
            Translation.allCases.map { translation in
                StoredBookKey.titleName(title: title, translation: translation, notebook: notebook)
            }
        }
    }

    /// 필사책 행의 가장 이른 `creationDate`. 행이 없거나 모두 nil 이면 nil.
    private func earliestRowCreation(of notebook: NotebookID) throws -> Date? {
        let titleNames = Self.rowTitleNames(of: notebook)
        let predicate = #Predicate<BibleDrawing> { row in
            if let titleName = row.titleName {
                return row.creationDate != nil && titleNames.contains(titleName)
            } else {
                return false
            }
        }
        var descriptor = FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.creationDate)])
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.creationDate
    }

    /// 행을 한 번 훑어 필사책마다 쓴 절 수 · 행이 있는 필사책 · 가장 이른 `creationDate` 를 모은다.
    ///
    /// 1. 잉크가 있는 행은 `lineData != nil` 술어로 **ID 만** 조회한다(`fetchIdentifiers` — SQL 은 `ZLINEDATA IS NOT NULL` 이고 행을 읽지 않는다).
    /// 2. 행은 한 번의 조회(SELECT 1회)로 가져오고 **`lineData` · `layoutMetadataData` 프로퍼티는 읽지 않는다** — 잉크를 디코딩하지 않고,
    ///    외부 파일로 나간 큰 잉크(externalStorage)도 열지 않는다.
    /// 3. 절(필사책 · 번역본 · 권 · 장 · 절)마다 대표 행을 `DrawingRepresentativeRule` 로 고르고, 대표 행이 1 의 집합에 들면 쓴 절이다.
    ///
    /// 비운 대표(지우기 · `clear` — `lineData == nil`)는 세지 않고, 보관 행(`isPresent == false`)은 대표가 아니라 세지 않는다. 번역본은 합산한다.
    ///
    /// - Important: **SwiftData 로는 잉크 열을 빼고 행 값을 읽을 수 없다**(2026-10-15 SQL 로그 실측, `-com.apple.CoreData.SQLDebug 1`).
    ///   `FetchDescriptor.propertiesToFetch` 는 첫 SELECT 의 열만 줄이고, SwiftData 가 `fetch` 안에서 행마다 fault 를 채워
    ///   잉크 열을 포함한 SELECT 를 행 수만큼 더 보낸다(N+1). `fetchIdentifiers` 뒤 `model(for:)` 도 같다. 그래서 부분 조회를 쓰지 않고
    ///   SELECT 1회로 가져온다 — SQLite 안에 담긴 작은 잉크(행 안 저장)는 행과 함께 메모리로 읽히지만 쓰지 않는다. 외부 파일로 나간 잉크는
    ///   프로퍼티를 읽을 때 열린다(같은 날 실측 — 조회 뒤 외부 파일을 지워도 조회는 되고 `lineData` 를 읽을 때 실패한다).
    ///   행 1만 개 측정(iPad 시뮬레이터 26.2 · 잉크 5KB × 7,500행, `NotebookRepositoryTesting` 성능 시험): 이 방법 약 0.21초,
    ///   부분 조회 약 0.27초, 대표 행 잉크 디코딩(`hasStrokes`) 약 0.33초 — 디코딩은 잉크가 클수록 더 든다.
    /// - Note: 획 판정을 `DrawingContentRule.hasStrokes`(디코딩) 대신 「`lineData` 가 nil 이 아닌가」 로 한다. 지금 저장 경로는 보이는 획이 없는
    ///   절을 `clear`(nil)로 저장하므로 둘이 같다. 다른 것은 획이 0개인 잉크를 남긴 옛 행(2.0 이전에 지우개로 전부 지운 행)뿐이고, 그 절은 쓴 절로 센다.
    private func writtenVerseScan() throws -> NotebookRowScan {
        let inkedRows = Set(try modelContext.fetchIdentifiers(
            FetchDescriptor<BibleDrawing>(predicate: #Predicate<BibleDrawing> { $0.lineData != nil })
        ))

        var scan = NotebookRowScan()
        var candidates: [NotebookVerseKey: [NotebookVerseCandidate]] = [:]
        for row in try modelContext.fetch(FetchDescriptor<BibleDrawing>()) {
            guard let titleName = row.titleName, let key = StoredBookKey.decodeRow(titleName) else { continue }
            scan.notebooks.insert(key.notebook)
            if let creation = row.creationDate, creation < scan.earliestCreation[key.notebook, default: .distantFuture] {
                scan.earliestCreation[key.notebook] = creation
            }
            guard let chapter = row.titleChapter, let verse = row.verse else { continue }
            candidates[NotebookVerseKey(row: key, chapter: chapter, verse: verse), default: []].append(NotebookVerseCandidate(
                representativeIsPresent: row.isPresent ?? false,
                representativeUpdateDate: row.updateDate,
                representativeRowKey: row.rowKey,
                hasInk: inkedRows.contains(row.persistentModelID)
            ))
        }
        for (key, verseCandidates) in candidates where DrawingRepresentativeRule.pick(verseCandidates)?.hasInk == true {
            scan.writtenVerses[key.row.notebook, default: 0] += 1
        }
        return scan
    }
}

/// 행을 한 번 훑은 결과 — `writtenVerseScan()` 이 채운다.
private struct NotebookRowScan {
    /// 행이 하나라도 있는 필사책.
    var notebooks: Set<NotebookID> = []
    /// 필사책마다 대표 행에 잉크가 있는 절 수(번역본 합산).
    var writtenVerses: [NotebookID: Int] = [:]
    /// 필사책마다 행의 가장 이른 `creationDate`.
    var earliestCreation: [NotebookID: Date] = [:]
}

/// 절 하나 — 필사책 · 번역본 · 권 · 장 · 절. 대표 행은 이 단위로 고른다.
private struct NotebookVerseKey: Hashable {
    let row: StoredRowKey
    let chapter: Int
    let verse: Int
}

/// 대표 선택에 필요한 행의 값과 잉크 유무 — 모델을 들고 다니지 않는다.
private struct NotebookVerseCandidate: DrawingRepresentativeCandidate {
    let representativeIsPresent: Bool
    let representativeUpdateDate: Date?
    let representativeRowKey: String
    /// `lineData` 가 nil 이 아닌가.
    let hasInk: Bool
}
