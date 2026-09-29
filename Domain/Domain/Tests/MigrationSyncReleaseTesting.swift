//  2.0.0 필사 이전·동기화 출시 경로.
//  C14 분리·삭제 실험과 별개로 원본 보존, V3 → 현재 스키마, 새 초안 경계를 고정한다.

import Foundation
import SwiftData
import Testing

@testable import Domain

@Suite("2.0.0 필사 이전·동기화 출시 경로", .serialized)
struct MigrationSyncReleaseTesting {
    private enum TestFailure: Error { case notReady }

    private func withStore(_ body: (URL, PreservationArea) throws -> Void) throws {
        let directory = try LinkageFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let area = PreservationArea(root: directory.appendingPathComponent("Preservation"), storeFileName: "Carve.sqlite")
        try body(directory, area)
    }

    /// 앱과 같은 출시 진입점이다. C14 행별 대응 판독은 연결 조건으로 삼지 않는다.
    private func open(_ url: URL, area: PreservationArea) throws -> ModelContainer {
        let outcome = LocalStoreLoader.loadForRelease(at: url, cloudKitDatabase: .none, preservation: area)
        guard case .ready(let container) = outcome else {
            Issue.record("출시 경로가 연결 준비를 마치지 못했다: \(outcome)")
            throw TestFailure.notReady
        }
        return container
    }

    @Test("무계정 V3 절·장 필기를 보존하고 재실행해도 내용과 식별자가 같다")
    func v3RowsSurviveReleaseAndReopen() throws {
        try withStore { directory, area in
            let url = directory.appendingPathComponent("Carve.sqlite")
            try seedV3(url)
            let before = try Data(contentsOf: url)

            for _ in 0..<2 {
                let context = ModelContext(try open(url, area: area))
                let verses = try context.fetch(FetchDescriptor<BibleDrawing>())
                let pages = try context.fetch(FetchDescriptor<BiblePageDrawing>())
                #expect(verses.count == 1 && pages.count == 1)
                #expect(verses.first?.id == "release-v3-verse")
                #expect(verses.first?.lineData == RealLegacyLineData.data)
                #expect(verses.first?.drawingVersion == 1)
                #expect(verses.first?.layoutMetadataData == nil)
                #expect(pages.first?.id == "release-v3-page")
                #expect(pages.first?.fullLineData == RealLegacyLineData.data)
            }

            let snapshots = try FileManager.default.contentsOfDirectory(at: area.rawSnapshotsDirectory, includingPropertiesForKeys: nil)
            #expect(snapshots.count == 1)
            #expect(try Data(contentsOf: snapshots[0].appendingPathComponent("Carve.sqlite")) == before)
        }
    }

    @Test("첫 로그인 소유 증명은 V3 원본과 마이그레이션된 필기 내용을 모두 대조한다")
    func migratedV3ContentMustMatchPreservedSnapshot() throws {
        let directory = try LinkageFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = try LinkageFixture.makeV3Store(in: directory)
        let area = PreservationArea(root: directory.appendingPathComponent("Preservation", isDirectory: true), storeFileName: storeURL.lastPathComponent)
        guard case .success(.created(let snapshotDirectory)) = RawStoreSnapshot.takeIfNeeded(storeURL: storeURL, area: area) else {
            Issue.record("업데이트 전 V3 원본 사본이 만들어지지 않았다")
            return
        }
        let snapshotURL = snapshotDirectory.appendingPathComponent(storeURL.lastPathComponent)

        func migrateAndReleaseContainer() throws {
            guard case .ready(let container) = LocalStoreLoader.loadForRelease(at: storeURL, cloudKitDatabase: .none, preservation: area) else {
                Issue.record("V3 로컬 마이그레이션이 준비되지 않았다")
                throw TestFailure.notReady
            }
            let context = ModelContext(container)
            #expect(try context.fetchCount(FetchDescriptor<BibleDrawing>()) == 3)
        }
        try migrateAndReleaseContainer()
        let mismatch = LegacyMigrationContentMatcher.mismatchSummary(sourceSnapshot: snapshotURL, currentStore: storeURL)
        #expect(mismatch == "")
        #expect(LegacyMigrationContentMatcher.matches(sourceSnapshot: snapshotURL, currentStore: storeURL))

        func changePayloadAndReleaseContainer() throws {
            let container = try open(storeURL, area: area)
            let context = ModelContext(container)
            guard let row = try context.fetch(FetchDescriptor<BibleDrawing>()).first else {
                Issue.record("마이그레이션된 legacy 필기가 없다")
                throw TestFailure.notReady
            }
            row.lineData = Data("changed drawing payload".utf8)
            try context.save()
        }
        try changePayloadAndReleaseContainer()
        #expect(!LegacyMigrationContentMatcher.matches(sourceSnapshot: snapshotURL, currentStore: storeURL))
    }

    @Test("종전 C14에서 보류한 V6 행도 삭제하지 않고 연결 준비한다")
    func previouslyHeldRowsRemainInStore() throws {
        try withStore { directory, area in
            let url = try LinkageFixture.makeV6Store(in: directory, page: true, favorite: true)
            #expect(LegacySeparationGate(area: area).decide(storeURL: url).hold != nil)
            let context = ModelContext(try open(url, area: area))
            #expect(try context.fetchCount(FetchDescriptor<BibleDrawing>()) == 3)
            #expect(try context.fetchCount(FetchDescriptor<BiblePageDrawing>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<FavoriteVerse>()) == 1)
        }
    }

    @Test("2.0.0 별도 로컬 초안은 출시 저장소 열기로 가져오거나 변경하지 않는다")
    func releaseDoesNotImportLocalDraftFiles() throws {
        try withStore { directory, area in
            let url = directory.appendingPathComponent("Carve.sqlite")
            try FileManager.default.createDirectory(at: area.draftsDirectory, withIntermediateDirectories: true)
            let draft = area.draftsDirectory.appendingPathComponent("local-only.json")
            let bytes = Data("로컬 초안 영역".utf8)
            try bytes.write(to: draft)
            let context = ModelContext(try open(url, area: area))
            #expect(try context.fetchCount(FetchDescriptor<BibleDrawing>()) == 0)
            #expect(try Data(contentsOf: draft) == bytes)
        }
    }

    @Test("원시 사본을 못 쓰면 V3 원본을 열거나 마이그레이션하지 않는다")
    func preservationFailureBlocksBeforeMigration() throws {
        try withStore { directory, area in
            let url = directory.appendingPathComponent("Carve.sqlite")
            try seedV3(url)
            let before = try Data(contentsOf: url)
            try Data("보존 경로를 막는 파일".utf8).write(to: area.root)
            let outcome = LocalStoreLoader.loadForRelease(at: url, cloudKitDatabase: .none, preservation: area)
            guard case .unavailable(.preservationFailed) = outcome else {
                Issue.record("보존 실패가 아니다: \(outcome)")
                return
            }
            #expect(try Data(contentsOf: url) == before)
        }
    }

    @Test("계정이 확인돼도 ownership proof 실패는 local-only로 열어 V3 필사를 보존한다")
    func ownershipFailureKeepsV3ReadableWithoutCloudKit() async throws {
        let directory = try LinkageFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Carve.sqlite")
        let area = PreservationArea(root: directory.appendingPathComponent("Preservation"), storeFileName: "Carve.sqlite")
        try seedV3(url)

        let outcome = await LocalStoreLoader.loadForRelease(
            at: url,
            containerID: "iCloud.Carve.SwiftData.iCloud.dev",
            preservation: area,
            identity: StubCloudAccountIdentityClient(.identified(userRecordName: "_current")),
            ownershipProof: DenyStoreOwnershipProof()
        )
        guard case .held(let container, let hold) = outcome else {
            Issue.record("소유 증명 실패 시 연결이 보류되어야 한다: \(outcome)")
            return
        }

        #expect(hold.reason == .ownershipUnverified)
        let context = ModelContext(container)
        let verses = try context.fetch(FetchDescriptor<BibleDrawing>())
        let pages = try context.fetch(FetchDescriptor<BiblePageDrawing>())
        #expect(verses.count == 1)
        #expect(verses.first?.id == "release-v3-verse")
        #expect(verses.first?.lineData == RealLegacyLineData.data)
        #expect(pages.count == 1)
        #expect(pages.first?.id == "release-v3-page")
        #expect(pages.first?.fullLineData == RealLegacyLineData.data)
        #expect(RawStoreSnapshot.completedSnapshotStores(in: area).count == 1)
    }

    @Test("손상된 기존 저장소는 빈 새 설치로 취급하지 않는다")
    func corruptedStoreBlocksAndKeepsBytes() throws {
        try withStore { directory, area in
            let url = directory.appendingPathComponent("Carve.sqlite")
            let bytes = Data("손상된 기존 저장소".utf8)
            try bytes.write(to: url)
            let outcome = LocalStoreLoader.loadForRelease(at: url, cloudKitDatabase: .none, preservation: area)
            guard case .unavailable = outcome else {
                Issue.record("손상 저장소가 차단되지 않았다: \(outcome)")
                return
            }
            #expect(try Data(contentsOf: url) == bytes)
        }
    }

    private func seedV3(_ url: URL) throws {
        let container = try ModelContainer(
            for: Schema(DrawingSchemaV3.models),
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        let verse = DrawingSchemaV3.BibleDrawing(bibleTitle: LinkageFixture.chapter, verse: 1, lineData: RealLegacyLineData.data)
        verse.id = "release-v3-verse"
        let page = DrawingSchemaV3.BiblePageDrawing(bibleTitle: LinkageFixture.chapter, fullLineData: RealLegacyLineData.data)
        page.id = "release-v3-page"
        context.insert(verse)
        context.insert(page)
        try context.save()
        try V4StoreHarness.settleWAL(at: url)
    }
}

private struct DenyStoreOwnershipProof: StoreOwnershipProofClient {
    func ownership(for scope: AccountScope) async -> AccountScope? { nil }
}
