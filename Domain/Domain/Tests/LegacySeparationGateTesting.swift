//
//  LegacySeparationGateTesting.swift
//  DomainTest
//
//  C14 게이트 — 연결 직전의 판정 · 분리본 보존 · 작업 기록 · 연결 보류 (정책 §12-6 C14 ① ~ ④, 테스트 계획 §3-3).
//
//  파괴적 분리(저장소에서 행 삭제)는 아직 연결하지 않았다. 여기서 고정하는 것은 그 앞까지다 —
//  「모두 대응 있음」 만 연결하고, 대응 없는 행은 분리본 · 기록을 남긴 채 보류하며, 「알 수 없음」 · 보존 실패 · 1.0.x 저장소도 연결하지 않는다.
//  보류는 편집 환경의 독립된 쓰기 차단 사유이고, 시작 화면은 통과시킨다.
//

import Foundation
import SwiftData
import Testing

import Dependencies

@testable import Domain

@Suite("C14 게이트 — 판정 · 보존 · 연결 보류")
struct LegacySeparationGateTesting {

    private func withDirectory(_ body: (URL, PreservationArea) throws -> Void) throws {
        let directory = try LinkageFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let area = PreservationArea(root: directory.appendingPathComponent("Preservation", isDirectory: true), storeFileName: "Carve.sqlite")
        try body(directory, area)
    }

    private func gate(_ area: PreservationArea) -> LegacySeparationGate {
        var gate = LegacySeparationGate(area: area)
        gate.reader.osMajor = 26
        return gate
    }

    private func load(_ url: URL, _ area: PreservationArea) -> LocalStoreLoader.Outcome {
        LocalStoreLoader.load(at: url, cloudKitDatabase: .none, preservation: area, separationGate: gate(area))
    }

    private func tableExists(_ url: URL, _ table: String) throws -> Bool {
        try LinkageFixture.scalar(url, "SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name = '\(table)'") == 1
    }

    // MARK: 대응 없는 행 — 보존하고 보류

    @Test("1.3.0 무계정 저장소는 V6 로 옮긴 뒤 행마다 분리본 · 작업 기록을 남기고 연결을 보류한다")
    func noAccountV3StoreIsPreservedAndHeld() throws {
        try withDirectory { directory, area in
            let url = try LinkageFixture.makeV3Store(in: directory)

            let outcome = load(url, area)

            guard case .held(let container, let hold) = outcome else { Issue.record("보류가 아니다: \(outcome)"); return }
            #expect(hold.reason == .unlinkedRowsAwaitSeparation(count: 3))
            #expect(hold.readerVersion == LegacyRowLinkageReader.version)
            let jobID = try #require(hold.jobID)

            // 저장소는 옮겨졌고(C14 ① 단계 ②) 이 컨테이너로 읽힌다.
            #expect(try tableExists(url, "ZVERSEDRAWINGVERSION"))
            #expect(try ModelContext(container).fetchCount(FetchDescriptor<BibleDrawing>()) == 3)
            // 원시 사본도 먼저 떴다(C3 ①).
            #expect(((try? FileManager.default.contentsOfDirectory(atPath: area.rawSnapshotsDirectory.path)) ?? []).count == 1)

            // 작업 기록 — 대상 셋 · 보존 확인 · 삭제는 시작하지 않음 · 완료 아님.
            let records = LegacySeparationRecordStore(area: area)
            let jobs = try records.jobs()
            #expect(jobs.count == 1 && jobs.first?.jobID == jobID)
            let job = try #require(jobs.first)
            #expect(job.targets.count == 3 && job.allPreserved && !job.deletion.started && !job.completed)
            #expect(job.targets.map(\.identity.primaryKey) == [1, 2, 3])
            #expect(job.targets.allSatisfy { $0.identity.entity == .bibleDrawing && $0.verseContentFingerprint != nil })

            // 분리본 — 모든 열 원형 그대로, 필기 바이트는 원본과 같다.
            let rows = try records.rows(of: job)
            #expect(rows.count == 3)
            #expect(rows.allSatisfy { $0.blob("ZLINEDATA") == RealLegacyLineData.data })
            #expect(Set(rows.compactMap { $0.integer("ZVERSE") }) == [1, 2, 3])
            #expect(rows.first?.text("ZTITLENAME") == "1-01Genesis.txt")
            #expect(rows.first?.verseContentFingerprint == VerseContentFingerprint.make(lineData: RealLegacyLineData.data, drawingVersion: 1, layoutMetadataBlob: nil))
        }
    }

    @Test("외부 저장으로 빠진 큰 필기도 분리본 안에 바이트로 든다")
    func externalBlobIsInlinedIntoTheCopy() throws {
        try withDirectory { directory, area in
            let url = try LinkageFixture.makeV6Store(in: directory)
            let large = RealLegacyLineData.makeLargeDrawingData()
            try seedLargeRow(at: url, lineData: large)

            guard case .held(_, let hold) = load(url, area), let jobID = hold.jobID else { Issue.record("보류가 아니다"); return }
            let records = LegacySeparationRecordStore(area: area)
            let job = try #require(try records.jobs().first { $0.jobID == jobID })
            let rows = try records.rows(of: job)

            #expect(rows.count == 4)
            #expect(rows.contains { $0.blob("ZLINEDATA") == large })
            #expect(rows.filter { $0.blob("ZLINEDATA") == RealLegacyLineData.data }.count == 3)
        }
    }

    @Test("같은 대상이면 다시 실행해도 같은 작업 기록이다 — 폴더가 늘지 않는다(멱등)")
    func rerunReusesTheSameJob() throws {
        try withDirectory { directory, area in
            let url = try LinkageFixture.makeV3Store(in: directory)

            guard case .held(_, let first) = load(url, area), case .held(_, let second) = load(url, area) else { Issue.record("보류가 아니다"); return }

            #expect(first.jobID != nil && first.jobID == second.jobID)
            let folders = try FileManager.default.contentsOfDirectory(atPath: area.separationDirectory.path)
            #expect(folders == [first.jobID!])
        }
    }

    // MARK: 중단 복구 (SEP-3 — 보존 단계까지)

    @Test("분리본을 쓰다 끊겨 남은 .partial 폴더는 다음 실행이 치우고 처음부터 다시 쓴다")
    func abandonedStagingIsReplaced() throws {
        try withDirectory { directory, area in
            let url = try LinkageFixture.makeV3Store(in: directory)
            let partial = area.separationDirectory.appendingPathComponent("deadbeef.partial/rows", isDirectory: true)
            try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true)
            try Data("{ 잘린".utf8).write(to: partial.appendingPathComponent("rows-000.json"))

            guard case .held(_, let hold) = load(url, area), let jobID = hold.jobID else { Issue.record("보류가 아니다"); return }

            let folders = try FileManager.default.contentsOfDirectory(atPath: area.separationDirectory.path)
            #expect(folders == [jobID])
            let records = LegacySeparationRecordStore(area: area)
            #expect(try records.rows(of: try #require(try records.jobs().first)).count == 3)
        }
    }

    @Test("분리본 파일이 손상되면 다음 실행이 알아채고 같은 작업 ID 로 다시 쓴다 — 손상된 사본을 보존으로 치지 않는다")
    func corruptedCopyIsRewritten() throws {
        try withDirectory { directory, area in
            let url = try LinkageFixture.makeV3Store(in: directory)
            guard case .held(_, let first) = load(url, area), let jobID = first.jobID else { Issue.record("보류가 아니다"); return }
            let rowsFile = area.separationDirectory.appendingPathComponent(jobID).appendingPathComponent("rows/rows-000.json")
            var bytes = try Data(contentsOf: rowsFile)
            bytes[bytes.count / 2] ^= 0x5A
            try bytes.write(to: rowsFile)
            let records = LegacySeparationRecordStore(area: area)
            #expect((try? records.rows(of: try #require(try records.jobs().first))) == nil)

            guard case .held(_, let second) = load(url, area) else { Issue.record("보류가 아니다"); return }

            #expect(second.jobID == jobID)
            #expect(try records.rows(of: try #require(try records.jobs().first)).count == 3)
        }
    }

    @Test("작업 기록이 없는 분리본 폴더는 기록으로 치지 않고, 다음 실행이 온전한 기록을 남긴다")
    func folderWithoutJobIsIgnoredThenCompleted() throws {
        try withDirectory { directory, area in
            let url = try LinkageFixture.makeV3Store(in: directory)
            guard case .held(_, let first) = load(url, area), let jobID = first.jobID else { Issue.record("보류가 아니다"); return }
            try FileManager.default.removeItem(at: area.separationDirectory.appendingPathComponent(jobID).appendingPathComponent("job.json"))
            let records = LegacySeparationRecordStore(area: area)
            #expect(try records.jobs().isEmpty)

            guard case .held(_, let second) = load(url, area) else { Issue.record("보류가 아니다"); return }

            let jobs = try records.jobs()
            #expect(second.jobID == jobID && jobs.count == 1)
        }
    }

    @Test("500행을 넘으면 분리본을 여러 파일로 나눠 쓰고, 읽을 때 대상 순서대로 모두 돌려준다")
    func largeTargetSetIsChunked() throws {
        try withDirectory { directory, area in
            let url = directory.appendingPathComponent("Carve.sqlite")
            let container = try ModelContainer(
                for: Schema(DrawingSchemaV3.models), configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
            )
            let context = ModelContext(container)
            for verse in 1...1_203 {
                context.insert(DrawingSchemaV3.BibleDrawing(bibleTitle: LinkageFixture.chapter, verse: verse, lineData: Data("v\(verse)".utf8)))
            }
            try context.save()
            try LinkageFixture.ensureMirroringTables(url)

            guard case .held(_, let hold) = load(url, area), let jobID = hold.jobID else { Issue.record("보류가 아니다"); return }

            let files = try FileManager.default.contentsOfDirectory(atPath: area.separationDirectory.appendingPathComponent(jobID).appendingPathComponent("rows").path).sorted()
            #expect(files == ["rows-000.json", "rows-001.json", "rows-002.json"])
            let records = LegacySeparationRecordStore(area: area)
            let job = try #require(try records.jobs().first)
            let rows = try records.rows(of: job)
            #expect(rows.count == 1_203 && rows.map(\.identity) == job.targets.map(\.identity))
        }
    }

    // MARK: 연결

    @Test("모든 행에 대응이 있으면 연결한다 — 기록을 남기지 않는다")
    func allLinkedStoreConnects() throws {
        try withDirectory { directory, area in
            let url = try LinkageFixture.makeV6Store(in: directory)
            for pk in 1...3 { try LinkageFixture.link(url, entity: .bibleDrawing, primaryKey: Int64(pk)) }
            try LinkageFixture.addIdentityKeys(url)

            let outcome = load(url, area)

            guard case .ready = outcome else { Issue.record("연결이 아니다: \(outcome)"); return }
            #expect(try LegacySeparationRecordStore(area: area).jobs().isEmpty)
        }
    }

    @Test("저장소가 없는 새 설치는 게이트가 CloudKit 없이 저장소를 만든 뒤에도 연결한다 — 다음 실행도 같다")
    func freshInstallConnects() throws {
        try withDirectory { directory, area in
            let url = directory.appendingPathComponent("Carve.sqlite")

            let first = load(url, area)
            guard case .ready = first else { Issue.record("새 설치를 연결하지 않았다: \(first)"); return }
            // 시험은 `.none` 으로 열어 미러링 표가 끝내 생기지 않는다 — 앱은 `.private` 로 열며 표가 생긴다. 표 없이 다시 열어도 연결해야 한다.
            let second = load(url, area)
            guard case .ready = second else { Issue.record("두 번째 실행을 연결하지 않았다: \(second)"); return }
            #expect(!FileManager.default.fileExists(atPath: area.separationDirectory.path))
        }
    }

    @Test("검증 밖 OS 의 새 설치도 연결한다 — legacy 행이 없다")
    func freshInstallConnectsOnUnvalidatedOS() throws {
        try withDirectory { directory, area in
            let url = directory.appendingPathComponent("Carve.sqlite")
            var elsewhere = LegacySeparationGate(area: area)
            elsewhere.reader.osMajor = 18

            let outcome = LocalStoreLoader.load(at: url, cloudKitDatabase: .none, preservation: area, separationGate: elsewhere)

            guard case .ready = outcome else { Issue.record("검증 밖 OS 의 새 설치를 연결하지 않았다: \(outcome)"); return }
        }
    }

    // MARK: 알 수 없음 · 실패 — 기록 없이 보류

    @Test("판정이 「알 수 없음」 이면 기록 없이 보류한다")
    func unknownVerdictHoldsWithoutRecord() throws {
        try withDirectory { directory, area in
            let url = try LinkageFixture.makeV6Store(in: directory)
            try LinkageFixture.exec(url, "DROP TABLE ANSCKRECORDMETADATA;")

            let outcome = load(url, area)

            guard case .held(_, let hold) = outcome else { Issue.record("보류가 아니다: \(outcome)"); return }
            #expect(hold.reason == .linkageUnknown(.tableMissing("ANSCKRECORDMETADATA")))
            #expect(hold.jobID == nil && hold.allowsConditionalConsent)
            #expect(!FileManager.default.fileExists(atPath: area.separationDirectory.path))
        }
    }

    @Test("분리본을 남기지 못하면 보류하고, 조건부 연결 동의도 내지 않는다")
    func preservationFailureHolds() throws {
        try withDirectory { directory, area in
            let url = try LinkageFixture.makeV3Store(in: directory)
            // 분리본 자리를 파일로 막아 폴더를 만들지 못하게 한다.
            try FileManager.default.createDirectory(at: area.storeDirectory, withIntermediateDirectories: true)
            #expect(FileManager.default.createFile(atPath: area.separationDirectory.path, contents: Data()))

            let outcome = load(url, area)

            guard case .held(_, let hold) = outcome, case .preservationFailed = hold.reason else { Issue.record("보존 실패 보류가 아니다: \(outcome)"); return }
            #expect(hold.jobID == nil && !hold.allowsConditionalConsent)
        }
    }

    @Test("앱이 쓰는 기본 게이트는 실행 중인 OS 를 따른다 — 검증 범위 밖 OS 면 모두 대응이 있어도 연결하지 않는다")
    func defaultGateHoldsOnUnvalidatedOS() throws {
        try withDirectory { directory, area in
            let url = try LinkageFixture.makeV6Store(in: directory)
            for pk in 1...3 { try LinkageFixture.link(url, entity: .bibleDrawing, primaryKey: Int64(pk)) }
            try LinkageFixture.addIdentityKeys(url)
            let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion

            let outcome = LocalStoreLoader.load(at: url, cloudKitDatabase: .none, preservation: area, separationGate: LegacySeparationGate(area: area))

            if LegacyRowLinkageReader().validatedOSMajors.contains(major) {
                guard case .ready = outcome else { Issue.record("검증한 OS 인데 연결하지 않았다: \(outcome)"); return }
            } else {
                guard case .held(_, let hold) = outcome else { Issue.record("검증 밖 OS 인데 보류하지 않았다: \(outcome)"); return }
                #expect(hold.reason == .linkageUnknown(.unvalidatedEnvironment(osMajor: major)))
                #expect(!FileManager.default.fileExists(atPath: area.separationDirectory.path))
            }
        }
    }

    @Test("1.0.x 저장소는 V1 로 옮기되 연결하지 않는다 — 게이트를 지나지 않은 저장소다")
    func unversionedStoreIsMigratedButHeld() throws {
        try withDirectory { directory, area in
            let url = directory.appendingPathComponent("Carve.sqlite")
            try seedUnversioned(at: url)

            let outcome = load(url, area)

            guard case .legacyMigrationHeld(let container, let hold) = outcome else { Issue.record("V1 보류가 아니다: \(outcome)"); return }
            guard case .linkageUnknown = hold.reason else { Issue.record("까닭이 다르다: \(hold.reason)"); return }
            #expect(try ModelContext(container).fetchCount(FetchDescriptor<DrawingVO>()) == 1)
        }
    }

    @Test("이 기기의 전체 삭제는 분리본 · 기록도 함께 지운다 — 보존 영역 안이다(C11 단계 ④)")
    func fullEraseRemovesSeparationRecords() throws {
        try withDirectory { directory, area in
            let url = try LinkageFixture.makeV3Store(in: directory)
            guard case .held = load(url, area) else { Issue.record("보류가 아니다"); return }
            #expect(area.separationDirectory.path.hasPrefix(area.storeDirectory.path))
            #expect(FileManager.default.fileExists(atPath: area.separationDirectory.path))

            try area.removeAll()

            #expect(!FileManager.default.fileExists(atPath: area.separationDirectory.path))
        }
    }

    // MARK: 표본

    private func seedLargeRow(at url: URL, lineData: Data) throws {
        let container = try ModelContainer(
            for: AppStoreSchema.schema, migrationPlan: DrawingDataMigrationPlan.self,
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        context.insert(BibleDrawing(bibleTitle: LinkageFixture.chapter, verse: 9, lineData: lineData, rowUUID: "row-9"))
        try context.save()
    }

    private func seedUnversioned(at url: URL) throws {
        let container = try ModelContainer(
            for: Schema([UnversionedDrawingStore.Release104.DrawingVO.self]),
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        let row = UnversionedDrawingStore.Release104.DrawingVO()
        row.id = "1-01Genesis.txt.1.1.1700000000"
        row.titleName = "1-01Genesis.txt"
        row.titleChapter = 1
        row.section = 1
        row.creationDate = Date(timeIntervalSince1970: 1_700_000_000)
        row.updateDate = Date(timeIntervalSince1970: 1_700_000_000)
        row.lineData = RealLegacyLineData.data
        row.isWritten = true
        context.insert(row)
        try context.save()
    }
}

// MARK: - 보류 상태가 앱의 다른 규칙에 미치는 것

@Suite("C14 연결 보류 — 쓰기 차단 · 시작 화면 · 편집 환경")
struct LegacySeparationHoldTesting {

    private let hold = LegacySeparationHold(reason: .unlinkedRowsAwaitSeparation(count: 2), jobID: "job")

    @Test("보류는 소유 근거가 있어도 가장 먼저 막는 독립된 쓰기 차단 사유다")
    func holdBlocksSyncedWritesRegardlessOfOwnership() {
        let scope = AccountScope(key: "acct-a")
        let token = AccountServerWorkToken(scope: scope, generation: 1)
        let open = DrawingEditEnvironment(accountState: .confirmed(scope), serverWork: token, knowledge: EraseEpochKnowledge(), storeOwnership: scope)
        #expect(SyncedWriteBlock.check(open) == nil)

        var held = open
        held.connectionHeld = true
        #expect(SyncedWriteBlock.check(held) == .connectionHeld)

        var heldAndSignedOut = held
        heldAndSignedOut.accountState = .noAccount
        #expect(SyncedWriteBlock.check(heldAndSignedOut) == .connectionHeld)
    }

    @Test("보류 상태는 시작 화면을 통과시키고, 초기 복원을 기다리지도 「먼저 시작하기」 를 내지도 않는다")
    func heldStateEntersWithoutWaiting() {
        let state = PersistentCloudKitContainer.CloudSyncState.connectionHeld(hold)
        #expect(state.launchRoute == .enterWriting)
        #expect(!state.isInProgress)
        #expect(LaunchWaitRule.route(state, mode: .initialRestore, startedFirst: false) == .enterWriting)
        #expect(LaunchWaitRule.route(state, mode: .normal, startedFirst: false) == .enterWriting)
        #expect(LaunchWaitRule.route(state, mode: nil, startedFirst: false) == .enterWriting)
        #expect(!LaunchWaitRule.offersStartFirst(state, mode: .initialRestore))
        // 초기 복원의 결과로 남기지 않는다 — 보류가 풀린 실행이 초기 복원을 한다.
        #expect(LaunchWaitRule.outcome(entering: state, mode: .initialRestore, startedFirst: false) == nil)
        #expect(PersistentCloudKitContainer.migrationOutcome(state) == state)
    }

    private actor FixedIdentityClient: CloudAccountIdentityClient {
        func currentIdentity() async -> CloudAccountIdentity { .identified(userRecordName: "_a") }
    }

    @Test("편집 환경은 이번 실행의 보류를 그대로 싣는다 — 확인된 계정이어도 막힌다")
    func liveEnvironmentCarriesTheHold() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hold-env-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileEraseStateStore(area: EraseStateArea(root: root, storeFileName: "Carve.sqlite"))
        let environment = LiveDrawingEditEnvironment(
            identity: FixedIdentityClient(), containerID: "iCloud.Carve.SwiftData.iCloud.dev", stateStore: store, notificationCenter: NotificationCenter()
        )
        await environment.start()

        let held = await withDependencies {
            $0.legacySeparationHoldState = LegacySeparationHoldState(hold: hold)
        } operation: {
            await environment.current()
        }
        let open = await withDependencies {
            $0.legacySeparationHoldState = LegacySeparationHoldState(hold: nil)
        } operation: {
            await environment.current()
        }

        #expect(held.connectionHeld && SyncedWriteBlock.check(held) == .connectionHeld)
        #expect(!open.connectionHeld && SyncedWriteBlock.check(open) != .connectionHeld)
    }

    @Test("보류 값은 실행 중에 비워지지 않는 자리에 두고, 조건부 동의 가능 여부를 까닭으로 가른다")
    func holdStateAndConsent() {
        let state = LegacySeparationHoldState()
        #expect(!state.isHeld)
        state.hold = hold
        #expect(state.isHeld && state.hold == hold)

        #expect(LegacySeparationHold(reason: .linkageUnknown(.tableMissing("x"))).allowsConditionalConsent)
        #expect(!LegacySeparationHold(reason: .unlinkedRowsAwaitSeparation(count: 1)).allowsConditionalConsent)
        #expect(!LegacySeparationHold(reason: .preservationFailed("x")).allowsConditionalConsent)
    }
}

// MARK: - 마이그레이션과 엔티티 번호

/// 게이트는 **옮긴 뒤의** 사본을 판정한다. 옮기는 동안 엔티티 번호(`Z_ENT`)가 바뀌면 미러링 대응(`ZENTITYID`)이 따라오는지 본다.
@Suite("C14 — 마이그레이션과 엔티티 번호")
struct LegacyEntityNumberingTesting {

    @Test("V5 → V6 는 FavoriteVerse 의 Z_ENT 를 3 → 4 로 바꾸고, CloudKit 없이 옮겨도 미러링 대응의 엔티티 번호가 함께 옮겨진다")
    func v5ToV6RenumbersFavoriteVerse() throws {
        let directory = try LinkageFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Carve.sqlite")
        do {
            let container = try ModelContainer(
                for: Schema(versionedSchema: DrawingSchemaV5.self), configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
            )
            let context = ModelContext(container)
            context.insert(DrawingSchemaV4.BibleDrawing(bibleTitle: LinkageFixture.chapter, verse: 1, lineData: RealLegacyLineData.data, rowUUID: "row-1"))
            context.insert(DrawingSchemaV5.FavoriteVerse(
                chapter: LinkageFixture.chapter, verse: 1, translation: .NKRV, sentence: "태초에", lineData: RealLegacyLineData.data, createdDate: Date(), favoriteID: "fav-1"
            ))
            try context.save()
        }
        try LinkageFixture.ensureMirroringTables(url)
        let favoriteBefore = try LinkageFixture.entityID(url, .favoriteVerse)
        let drawingBefore = try LinkageFixture.entityID(url, .bibleDrawing)
        try LinkageFixture.link(url, entity: .favoriteVerse, primaryKey: 1)
        try LinkageFixture.link(url, entity: .bibleDrawing, primaryKey: 1)
        #expect(LocalStoreLoader.storeKind(at: url) == .known(Schema.Version(5, 0, 0)))

        _ = try ModelContainer(for: AppStoreSchema.schema, migrationPlan: DrawingDataMigrationPlan.self, configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))

        let favoriteAfter = try LinkageFixture.entityID(url, .favoriteVerse)
        let drawingAfter = try LinkageFixture.entityID(url, .bibleDrawing)
        let epochAfter = try LinkageFixture.scalar(url, "SELECT Z_ENT FROM Z_PRIMARYKEY WHERE Z_NAME = 'DrawingEraseEpoch'")
        let staleFavorite = try LinkageFixture.scalar(url, "SELECT count(*) FROM ANSCKRECORDMETADATA WHERE ZENTITYID = \(favoriteBefore)")
        let movedFavorite = try LinkageFixture.scalar(url, "SELECT count(*) FROM ANSCKRECORDMETADATA WHERE ZENTITYID = \(favoriteAfter)")
        print("V5→V6 엔티티 번호: FavoriteVerse \(favoriteBefore)→\(favoriteAfter) · BibleDrawing \(drawingBefore)→\(drawingAfter) · DrawingEraseEpoch →\(epochAfter)"
              + " · 대응 ZENTITYID \(favoriteBefore) 남음 \(staleFavorite) · \(favoriteAfter) 로 옮김 \(movedFavorite)")

        #expect(drawingBefore == drawingAfter)
        #expect(favoriteBefore != favoriteAfter)
        #expect(epochAfter == favoriteBefore, "옛 FavoriteVerse 번호를 다른 엔티티가 받는다")
        // 2026-09-22 관측: 가벼운 마이그레이션은 `ANSCKRECORDMETADATA.ZENTITYID` 도 새 번호로 옮긴다(낡은 번호 0건).
        #expect(staleFavorite == 0 && movedFavorite == 1, "대응의 엔티티 번호가 새 번호를 따라와야 한다")
    }

    @Test("V2 → V6 (가벼운 마이그레이션만) 뒤에도 BibleDrawing 의 (엔티티, 기본 키) 대응과 행 ID 가 그대로다")
    func v2ToV6KeepsCorrespondences() throws {
        let directory = try LinkageFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Carve.sqlite")
        do {
            let container = try ModelContainer(
                for: Schema(versionedSchema: DrawingSchemaV2.self), configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
            )
            let context = ModelContext(container)
            for verse in 1...3 {
                context.insert(DrawingSchemaV2.BibleDrawing(bibleTitle: LinkageFixture.chapter, verse: verse, lineData: RealLegacyLineData.data))
            }
            try context.save()
        }
        try LinkageFixture.ensureMirroringTables(url)
        for pk in 1...3 { try LinkageFixture.link(url, entity: .bibleDrawing, primaryKey: Int64(pk)) }
        let before = try pairs(url)
        #expect(LocalStoreLoader.storeKind(at: url) == .known(Schema.Version(2, 0, 0)))

        _ = try ModelContainer(for: AppStoreSchema.schema, migrationPlan: DrawingDataMigrationPlan.self, configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))

        let after = try pairs(url)
        print("V2→V6 대응(엔티티 · 기본 키 · 행 ID): 앞 \(before.sorted()) · 뒤 \(after.sorted())")
        #expect(before == after)
    }

    @Test("V1 → V6 (행을 새로 만드는 사용자 정의 마이그레이션) 뒤의 대응을 기록한다 — 원본 모델을 판정에 넣을지 가르는 관측")
    func v1ToV6Correspondences() throws {
        let directory = try LinkageFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Carve.sqlite")
        do {
            let container = try ModelContainer(
                for: Schema(versionedSchema: DrawingSchemaV1.self), configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
            )
            let context = ModelContext(container)
            for verse in 1...3 {
                context.insert(DrawingSchemaV1.DrawingVO(bibleTitle: LinkageFixture.chapter, verse: verse, lineData: RealLegacyLineData.data))
            }
            try context.save()
        }
        try LinkageFixture.ensureMirroringTables(url)
        let voEntity = try LinkageFixture.scalar(url, "SELECT Z_ENT FROM Z_PRIMARYKEY WHERE Z_NAME = 'DrawingVO'")
        for pk in 1...3 { try LinkageFixture.linkRaw(url, entityID: voEntity, primaryKey: Int64(pk)) }
        try LinkageFixture.addIdentityKeys(url)
        #expect(LocalStoreLoader.storeKind(at: url) == .known(Schema.Version(1, 0, 0)))

        _ = try ModelContainer(for: AppStoreSchema.schema, migrationPlan: DrawingDataMigrationPlan.self, configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))

        let drawingEntity = try LinkageFixture.entityID(url, .bibleDrawing)
        let rows = try LinkageFixture.scalar(url, "SELECT count(*) FROM ZBIBLEDRAWING")
        let correspondences = try LinkageFixture.scalar(url, "SELECT count(*) FROM ANSCKRECORDMETADATA")
        let matching = try LinkageFixture.scalar(
            url, "SELECT count(*) FROM ANSCKRECORDMETADATA m JOIN ZBIBLEDRAWING d ON m.ZENTITYPK = d.Z_PK WHERE m.ZENTITYID = \(drawingEntity)"
        )
        let voLeft = try LinkageFixture.scalar(url, "SELECT count(*) FROM Z_PRIMARYKEY WHERE Z_NAME = 'DrawingVO'")
        var reader = LegacyRowLinkageReader()
        reader.osMajor = 26
        let reading = reader.judge(storeAt: url)
        print("V1→V6: DrawingVO 번호 \(voEntity) → BibleDrawing 번호 \(drawingEntity) · 행 \(rows) · 대응 \(correspondences)"
              + " · 대응이 새 행을 가리킴 \(matching) · DrawingVO 등록 남음 \(voLeft) · 판독 \(reading.summary)")
        // 2026-09-22 관측: 옛 행과 함께 그 대응도 지워지고(0), 새 행은 「검증된 대응 없음」 이다 — 낡은 대응이 새 행을 가리키지 않는다.
        #expect(rows == 3 && correspondences == 0 && matching == 0 && voLeft == 0)
        #expect(reading.unlinkedCount == 3)
    }

    private func pairs(_ url: URL) throws -> Set<String> {
        var result: Set<String> = []
        for pk in 1...3 {
            let id = try LinkageFixture.scalar(url, """
            SELECT count(*) FROM ANSCKRECORDMETADATA m JOIN ZBIBLEDRAWING d ON m.ZENTITYPK = d.Z_PK
            WHERE d.Z_PK = \(pk) AND m.ZENTITYID = (SELECT Z_ENT FROM Z_PRIMARYKEY WHERE Z_NAME = 'BibleDrawing')
            """)
            result.insert("pk\(pk):\(id)")
        }
        return result
    }
}
