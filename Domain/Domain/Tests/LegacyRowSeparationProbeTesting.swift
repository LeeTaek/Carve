//
//  LegacyRowSeparationProbeTesting.swift
//  DomainTest
//
//  SEP-1 · SEP-2 의 손 — 저장소 사본을 **미러링 없이** 열어 판정하고, 행을 넣거나 지운다 (테스트 계획 §3-3).
//
//  C14 판독기의 첫 판이기도 하다. SEP-0 에서 공개 API(`recordID(for:)`)로는 대응을 읽지 못한다는 것을 확인했으므로(F34),
//  대응은 저장소의 `ANSCKRECORDMETADATA` 를 **읽기 전용 SQLite** 로 읽는다.
//      ZENTITYID = `Z_PRIMARYKEY.Z_ENT` · ZENTITYPK = 그 엔티티 표의 `Z_PK` (2026-09-21 실제 저장소에서 확인)
//
//  시험 프로세스에는 호스트 환경 변수가 닿지 않으므로(SEP-0 기록), **시험 번들 옆 `sep2/`** 를 쓴다.
//      sep2/<아무>.sqlite   — 작업할 저장소 사본(제자리에서 고친다)
//      sep2/plan.json       — {"op":"report"} · {"op":"insert","count":2} · {"op":"delete","select":"withoutRecordID","count":1}
//  `plan.json` 이 없으면 아무것도 하지 않는다.
//

import CoreData
import Foundation
import SQLite3
import SwiftData
import Testing

@testable import Domain

@Suite("SEP-1 · SEP-2 · 분리 판정과 손질")
struct LegacyRowSeparationProbeTesting {

    // MARK: 자리

    private final class BundleAnchor {}

    private static var dropbox: String {
        Bundle(for: BundleAnchor.self).bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("sep2", isDirectory: true).path
    }

    private static var storePath: String? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dropbox)) ?? []
        return names.filter { $0.hasSuffix(".sqlite") }.sorted().first.map { dropbox + "/" + $0 }
    }

    private struct Plan: Decodable {
        var op: String
        var count: Int?
        var select: String?
        /// 지울 행을 `id` 로 집는다 — 원래 있던 행은 건드리지 않고 시험용 행만 지우기 위해서다.
        var id: String?
    }

    private static var plan: Plan? {
        guard let data = FileManager.default.contents(atPath: dropbox + "/plan.json") else { return nil }
        return try? JSONDecoder().decode(Plan.self, from: data)
    }

    // MARK: 판독기 (읽기 전용 SQLite)

    /// 저장소에서 읽은 미러링 상태. **값은 읽지 않는다** — 계정 식별 원문을 기록에 남기지 않기 위해 키 이름만 본다.
    struct MirroringState {
        /// 엔티티 이름 → `Z_ENT`.
        var entityIDs: [String: Int64] = [:]
        /// 대응이 있는 행 — (Z_ENT, Z_PK).
        var correspondences: Set<Pair> = []
        /// 대응은 있는데 아직 올리지 않은 행.
        var needsUpload: Set<Pair> = []
        /// 저장소 메타데이터의 키 이름들.
        var metadataKeys: [String] = []
        /// 이력 트랜잭션 수.
        var transactions: Int = 0

        struct Pair: Hashable { var entity: Int64; var pk: Int64 }

        func hasCorrespondence(entity: String, pk: Int64) -> Bool {
            guard let ent = entityIDs[entity] else { return false }
            return correspondences.contains(Pair(entity: ent, pk: pk))
        }
    }

    private func readMirroringState(at path: String) throws -> MirroringState {
        var handle: OpaquePointer?
        let uri = "file:\(path)?mode=ro"
        guard sqlite3_open_v2(uri, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK, let db = handle else {
            throw ProbeFailure.cannotOpenSQLite(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_close(db) }

        func rows(_ sql: String, _ body: (OpaquePointer) -> Void) {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let stmt = statement else { return }
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW { body(stmt) }
        }

        var state = MirroringState()
        rows("select Z_ENT, Z_NAME from Z_PRIMARYKEY where Z_NAME is not null") { stmt in
            guard let name = sqlite3_column_text(stmt, 1) else { return }
            state.entityIDs[String(cString: name)] = sqlite3_column_int64(stmt, 0)
        }
        rows("select ZENTITYID, ZENTITYPK, ZNEEDSUPLOAD, ZCKRECORDNAME from ANSCKRECORDMETADATA") { stmt in
            let pair = MirroringState.Pair(entity: sqlite3_column_int64(stmt, 0), pk: sqlite3_column_int64(stmt, 1))
            // 레코드 이름이 있는 항목만 "대응 있음" 으로 센다.
            if sqlite3_column_type(stmt, 3) != SQLITE_NULL { state.correspondences.insert(pair) }
            if sqlite3_column_int64(stmt, 2) != 0 { state.needsUpload.insert(pair) }
        }
        rows("select ZKEY from ANSCKMETADATAENTRY order by ZKEY") { stmt in
            guard let key = sqlite3_column_text(stmt, 0) else { return }
            state.metadataKeys.append(String(cString: key))
        }
        rows("select count(*) from ATRANSACTION") { stmt in
            state.transactions = Int(sqlite3_column_int64(stmt, 0))
        }
        return state
    }

    enum ProbeFailure: Error, CustomStringConvertible {
        case cannotOpenSQLite(String)
        case noStore
        case modelUnavailable

        var description: String {
            switch self {
            case .cannotOpenSQLite(let message): "저장소를 읽기 전용으로 열지 못했다: \(message)"
            case .noStore: "sep2/ 에 저장소가 없다"
            case .modelUnavailable: "앱 스키마로 모델을 만들지 못했다"
            }
        }
    }

    // MARK: 손질 (미러링 없이 열고, 이력 추적은 켠 채)

    private func open(_ path: String) throws -> NSPersistentContainer {
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: AppStoreSchema.models) else {
            throw ProbeFailure.modelUnavailable
        }
        let container = NSPersistentContainer(name: "SEP2Surgery", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: URL(fileURLWithPath: path))
        description.cloudKitContainerOptions = nil
        // 이력 추적은 **켠다** — 1.3.0 이 쓰던 저장소와 같은 조건이어야 삭제 전파를 제대로 본다.
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.shouldMigrateStoreAutomatically = false
        description.shouldInferMappingModelAutomatically = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        return container
    }

    /// 객체의 `Z_PK` — `x-coredata://<UUID>/<엔티티>/p5` 의 끝에서 읽는다.
    private func primaryKey(of objectID: NSManagedObjectID) -> Int64? {
        let last = objectID.uriRepresentation().lastPathComponent
        guard last.hasPrefix("p") else { return nil }
        return Int64(last.dropFirst())
    }

    private func insertRows(_ container: NSPersistentContainer, count: Int) throws -> [String] {
        let context = container.newBackgroundContext()
        var made: [String] = []
        var thrown: Error?
        context.performAndWait {
            for index in 0 ..< count {
                let object = NSEntityDescription.insertNewObject(forEntityName: "BibleDrawing", into: context)
                let identifier = "SEP2-\(UUID().uuidString.prefix(8))"
                object.setValue(identifier, forKey: "id")
                object.setValue("1-01Genesis.txt", forKey: "titleName")
                object.setValue(1, forKey: "titleChapter")
                object.setValue(10 + index, forKey: "verse")
                object.setValue(Date(), forKey: "creationDate")
                object.setValue(Date(), forKey: "updateDate")
                object.setValue(true, forKey: "isPresent")
                object.setValue(1, forKey: "drawingVersion")
                object.setValue(Data("SEP2-대응없는-행".utf8), forKey: "lineData")
                made.append(identifier)
            }
            do { try context.save() } catch { thrown = error }
        }
        if let thrown { throw thrown }
        return made
    }

    private func deleteRows(_ container: NSPersistentContainer, state: MirroringState, select: String, count: Int, id: String? = nil) throws -> [String] {
        let context = container.newBackgroundContext()
        var removed: [String] = []
        var thrown: Error?
        context.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "BibleDrawing")
            guard let objects = try? context.fetch(request) else { return }
            let wanted = objects.filter { object in
                if let id { return (object.value(forKey: "id") as? String) == id }
                guard let pk = primaryKey(of: object.objectID) else { return false }
                let has = state.hasCorrespondence(entity: "BibleDrawing", pk: pk)
                return select == "withRecordID" ? has : has == false
            }
            for object in wanted.prefix(count) {
                let pk = primaryKey(of: object.objectID).map(String.init) ?? "?"
                let identifier = (object.value(forKey: "id") as? String) ?? "?"
                removed.append("Z_PK \(pk) · id \(identifier)")
                context.delete(object)
            }
            do { try context.save() } catch { thrown = error }
        }
        if let thrown { throw thrown }
        return removed
    }

    // MARK: 시험

    @Test("저장소를 판정하고, 지시서가 있으면 손질한다 — sep2/ 에 표본이 있을 때만 돈다")
    func runPlan() throws {
        guard let path = Self.storePath, let plan = Self.plan else {
            withKnownIssue("sep2/ 에 저장소나 plan.json 이 없다", isIntermittent: true) { Issue.record("표본 없음") }
            return
        }

        let before = try readMirroringState(at: path)
        var lines = ["SEP 손질 — 지시서 \(plan.op)"]
        lines.append(describe(before, title: "손질 전"))

        switch plan.op {
        case "report":
            break
        case "insert":
            let container = try open(path)
            let made = try insertRows(container, count: plan.count ?? 1)
            lines.append("  넣은 행: \(made.joined(separator: ", "))")
        case "delete":
            let container = try open(path)
            let removed = try deleteRows(container, state: before, select: plan.select ?? "withoutRecordID", count: plan.count ?? 1, id: plan.id)
            lines.append("  지운 행(\(plan.id ?? plan.select ?? "withoutRecordID")): \(removed.isEmpty ? "없음" : removed.joined(separator: " / "))")
        default:
            lines.append("  모르는 지시서다")
        }

        let after = try readMirroringState(at: path)
        lines.append(describe(after, title: "손질 후"))
        let report = lines.joined(separator: "\n")
        print(report)
        try? report.write(toFile: Self.dropbox + "/report.txt", atomically: true, encoding: .utf8)

        #expect(after.entityIDs.isEmpty == false)
    }

    private func describe(_ state: MirroringState, title: String) -> String {
        var text = "  \(title): 대응 \(state.correspondences.count)개 · 업로드 대기 \(state.needsUpload.count)개 · 이력 \(state.transactions)건"
        text += "\n    저장소 메타데이터 키 \(state.metadataKeys.count)개"
        let identity = state.metadataKeys.filter { $0.contains("CKIdentity") }
        text += " (계정 식별 키 \(identity.isEmpty ? "없음" : "있음"))"
        return text
    }
}
