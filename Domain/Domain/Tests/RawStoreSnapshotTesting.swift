//
//  RawStoreSnapshotTesting.swift
//  DomainTest
//
//  원시 사본 — 새 모델로 저장소를 열기 전에 그대로 떠 두고, 뜨지 못하면 열지 않는다 (정책 §12-6 C3 ①).
//

import Foundation
import SwiftData
import Testing

@testable import Domain

/// 이 파일이 막는 것은 **보호되지 않은 채 새 모델로 여는 것**이다. 마이그레이션 · 가져오기가 저장소를 바꾸기 전의
/// legacy 원본이 어디에도 남지 않으면, 그 뒤 덮인 필기는 되살릴 수 없다.
@Suite("원시 사본")
struct RawStoreSnapshotTesting {

    private let chapter = BibleChapter(title: .genesis, chapter: 1)

    private func withDirectory(_ body: (URL) async throws -> Void) async throws {
        let directory = try V4StoreHarness.makeStoreDirectory()
        defer { V4StoreHarness.removeStoreDirectory(directory) }
        try await body(directory)
    }

    private func area(in directory: URL) -> PreservationArea {
        PreservationArea(root: directory.appendingPathComponent("Preservation", isDirectory: true), storeFileName: "Carve.sqlite")
    }

    /// 앱 스키마로 필사 행을 남긴다. `largeInk` 면 외부 저장으로 빠질 만큼 큰 획을 하나 더 넣는다.
    private func seedStore(at url: URL, largeInk: Bool = false) throws {
        let container = try ModelContainer(
            for: AppStoreSchema.schema,
            migrationPlan: DrawingDataMigrationPlan.self,
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        context.insert(BibleDrawing(bibleTitle: chapter, verse: 1, lineData: RealLegacyLineData.data, rowUUID: "row-1"))
        if largeInk {
            let ink = Data((0..<1_048_576).map { UInt8($0 % 251) })
            context.insert(BibleDrawing(bibleTitle: chapter, verse: 2, lineData: ink, rowUUID: "row-2"))
        }
        try context.save()
    }

    /// 저장소 본체와 WAL 의 바이트. `-shm` 은 읽기만 해도 바뀌는 공유 메모리 색인이라 비교하지 않는다.
    private func storeBytes(at url: URL) throws -> [Data] {
        [try Data(contentsOf: url), (try? Data(contentsOf: URL(fileURLWithPath: url.path + "-wal"))) ?? Data()]
    }

    private func snapshotFolders(in area: PreservationArea) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: area.rawSnapshotsDirectory.path)) ?? []).sorted()
    }

    /// 사본을 건드리지 않으려고 복제본을 떠서 앱 스키마로 연다.
    private func drawingsInSnapshot(_ snapshot: URL, scratch: URL) throws -> [String: Data] {
        try FileManager.default.copyItem(at: snapshot, to: scratch)
        let container = try ModelContainer(
            for: AppStoreSchema.schema,
            migrationPlan: DrawingDataMigrationPlan.self,
            configurations: ModelConfiguration(url: scratch.appendingPathComponent("Carve.sqlite"), cloudKitDatabase: .none)
        )
        let rows = try ModelContext(container).fetch(FetchDescriptor<BibleDrawing>())
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.rowUUID ?? "-", $0.lineData ?? Data()) })
    }

    // MARK: - 뜨기

    @Test("저장소를 열기 전에 그대로 떠 두고, 원본은 바꾸지 않는다")
    func takesSnapshotWithoutTouchingTheStore() async throws {
        try await withDirectory { directory in
            let url = V4StoreHarness.storeURL(in: directory)
            try seedStore(at: url)
            let before = try storeBytes(at: url)
            let area = area(in: directory)

            let outcome = RawStoreSnapshot.takeIfNeeded(storeURL: url, area: area)

            guard case .success(.created(let snapshot)) = outcome else {
                Issue.record("사본을 뜨지 않았다: \(outcome)")
                return
            }
            #expect(try storeBytes(at: url) == before)
            #expect(try Data(contentsOf: snapshot.appendingPathComponent("Carve.sqlite")) == before[0])
            #expect(FileManager.default.fileExists(atPath: snapshot.appendingPathComponent("manifest.json").path))
            let rows = try drawingsInSnapshot(snapshot, scratch: directory.appendingPathComponent("scratch", isDirectory: true))
            #expect(rows == ["row-1": RealLegacyLineData.data])
        }
    }

    /// 이미 새 모델로 연 저장소를 "원본" 으로 다시 뜨면 원본이 덮인다.
    @Test("한 번 뜨면 다시 뜨지 않는다")
    func takesOnlyOnce() async throws {
        try await withDirectory { directory in
            let url = V4StoreHarness.storeURL(in: directory)
            try seedStore(at: url)
            let area = area(in: directory)

            guard case .success(.created(let first)) = RawStoreSnapshot.takeIfNeeded(storeURL: url, area: area) else {
                Issue.record("첫 사본을 뜨지 않았다")
                return
            }
            let second = RawStoreSnapshot.takeIfNeeded(storeURL: url, area: area)

            #expect(second == .success(.alreadyTaken(first)))
            #expect(snapshotFolders(in: area).count == 1)
        }
    }

    @Test("처음 실행할 때 저장소가 없으면 뜨지 않고, 그 결정을 기억한다")
    func missingStoreIsRememberedAsNotNeeded() async throws {
        try await withDirectory { directory in
            let url = V4StoreHarness.storeURL(in: directory)
            let area = area(in: directory)

            #expect(RawStoreSnapshot.takeIfNeeded(storeURL: url, area: area) == .success(.notNeeded))

            // 그 뒤 이 버전이 만든 저장소는 원본이 아니다 — 가져오기 뒤의 보존은 지속 대조(C3 ③)가 맡는다.
            try seedStore(at: url)
            #expect(RawStoreSnapshot.takeIfNeeded(storeURL: url, area: area) == .success(.notNeeded))
            #expect(snapshotFolders(in: area).isEmpty)
        }
    }

    @Test("외부 저장으로 빠진 획도 함께 뜬다")
    func copiesExternalData() async throws {
        try await withDirectory { directory in
            let url = V4StoreHarness.storeURL(in: directory)
            try seedStore(at: url, largeInk: true)
            let external = V4StoreHarness.externalDataFiles(in: directory)
            try #require(!external.isEmpty, "1 MB 획이 외부 저장으로 빠지지 않았다 — 이 시험의 전제가 바뀌었다")
            let area = area(in: directory)

            guard case .success(.created(let snapshot)) = RawStoreSnapshot.takeIfNeeded(storeURL: url, area: area) else {
                Issue.record("사본을 뜨지 않았다")
                return
            }

            let copied = V4StoreHarness.externalDataFiles(in: snapshot)
            #expect(copied.count == external.count)
            let rows = try drawingsInSnapshot(snapshot, scratch: directory.appendingPathComponent("scratch", isDirectory: true))
            #expect(rows["row-2"]?.count == 1_048_576)
        }
    }

    // MARK: - 완료 조건

    @Test("외부 저장 파일이 빠져 있으면 사본을 남기지 않는다")
    func missingExternalDataFails() async throws {
        try await withDirectory { directory in
            let url = V4StoreHarness.storeURL(in: directory)
            try seedStore(at: url, largeInk: true)
            let external = V4StoreHarness.externalDataFiles(in: directory)
            try #require(!external.isEmpty, "1 MB 획이 외부 저장으로 빠지지 않았다 — 이 시험의 전제가 바뀌었다")
            try FileManager.default.removeItem(at: external[0])
            let area = area(in: directory)

            let outcome = RawStoreSnapshot.takeIfNeeded(storeURL: url, area: area)

            guard case .failure(.externalDataMissing(let names)) = outcome else {
                Issue.record("빠진 외부 저장을 잡지 못했다: \(outcome)")
                return
            }
            #expect(names == [external[0].lastPathComponent])
            #expect(snapshotFolders(in: area).isEmpty)
        }
    }

    @Test("무결성 검사를 통과하지 못하면 사본을 남기지 않는다")
    func corruptStoreFails() async throws {
        try await withDirectory { directory in
            let url = V4StoreHarness.storeURL(in: directory)
            try Data(repeating: 0x5A, count: 8_192).write(to: url)
            let area = area(in: directory)

            let outcome = RawStoreSnapshot.takeIfNeeded(storeURL: url, area: area)

            guard case .failure(.integrityCheckFailed) = outcome else {
                Issue.record("손상을 잡지 못했다: \(outcome)")
                return
            }
            #expect(snapshotFolders(in: area).isEmpty)
        }
    }

    // MARK: - 저장소 열기와의 연결

    @Test("원시 사본을 뜨지 못하면 저장소를 열지 않고 막는다")
    func loaderBlocksWhenSnapshotFails() async throws {
        try await withDirectory { directory in
            let url = V4StoreHarness.storeURL(in: directory)
            try seedStore(at: url)
            let before = try storeBytes(at: url)
            // 보존 영역 자리에 일반 파일이 있으면 폴더를 만들 수 없다 — 쓰지 못하는 상황을 그대로 재현한다.
            let blocker = directory.appendingPathComponent("Blocked")
            try Data("파일".utf8).write(to: blocker)
            let area = PreservationArea(root: blocker, storeFileName: "Carve.sqlite")

            let outcome = LocalStoreLoader.load(at: url, cloudKitDatabase: .none, preservation: area)

            guard case .unavailable(let failure) = outcome else {
                Issue.record("막지 않았다: \(outcome)")
                return
            }
            #expect(failure == .preservationFailed)
            #expect(try storeBytes(at: url) == before)
            #expect(PersistentCloudKitContainer.CloudSyncState.storeUnavailable(failure).launchRoute == .blocked(.preservationFailed))
        }
    }

    @Test("사본을 뜬 뒤에는 평소처럼 연다")
    func loaderOpensAfterSnapshot() async throws {
        try await withDirectory { directory in
            let url = V4StoreHarness.storeURL(in: directory)
            try seedStore(at: url)
            let area = area(in: directory)

            let outcome = LocalStoreLoader.load(at: url, cloudKitDatabase: .none, preservation: area)

            guard case .ready = outcome else {
                Issue.record("열지 않았다: \(outcome)")
                return
            }
            #expect(snapshotFolders(in: area).count == 1)
        }
    }

    // MARK: - 전체 삭제

    /// 사용자가 이 기기에서 전체 삭제를 요청했으면 숨은 사본을 남기지 않는다(§12-6 C11 단계 ④).
    @Test("전체 삭제는 보존 영역도 지운다")
    func eraseAllRemovesPreservationArea() async throws {
        try await withDirectory { directory in
            let url = V4StoreHarness.storeURL(in: directory)
            try seedStore(at: url)
            let area = area(in: directory)
            _ = RawStoreSnapshot.takeIfNeeded(storeURL: url, area: area)
            try #require(snapshotFolders(in: area).count == 1)
            let harness = try RepositoryHarness()
            let eraser = SwiftDataDrawingDataEraser(actor: harness.actor, preservationArea: { area })

            #expect(await eraser.eraseAll() == .completed)
            #expect(!FileManager.default.fileExists(atPath: area.storeDirectory.path))
        }
    }

    @Test("보존 영역을 지우지 못하면 부분 실패로 알린다")
    func eraseAllReportsPreservationFailure() async throws {
        try await withDirectory { directory in
            let area = area(in: directory)
            try FileManager.default.createDirectory(at: area.rawSnapshotsDirectory, withIntermediateDirectories: true)
            // 부모 폴더에 쓰기 권한이 없으면 그 안의 폴더를 지울 수 없다.
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: area.root.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: area.root.path) }
            let harness = try RepositoryHarness()
            let eraser = SwiftDataDrawingDataEraser(actor: harness.actor, preservationArea: { area })

            #expect(await eraser.eraseAll() == .partiallyFailed)
        }
    }
}
