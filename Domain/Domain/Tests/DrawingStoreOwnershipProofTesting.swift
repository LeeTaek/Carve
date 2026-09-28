//
//  DrawingStoreOwnershipProofTesting.swift
//  DomainTest
//

import Foundation
import SQLite3
import Testing

@testable import Domain

@Suite("기기 저장소 소유 근거")
struct DrawingStoreOwnershipProofTesting {
    private let containerID = "iCloud.Carve.SwiftData.iCloud.dev"

    private func scope(_ name: String) -> AccountScope {
        .make(containerID: containerID, userRecordName: name)
    }

    private func unlinkedV3() -> LegacyRowLinkageReading {
        let row = LegacyRowIdentity(entity: .bibleDrawing, primaryKey: 1, rowID: "Genesis.1.1")
        return LegacyRowLinkageReading(
            verdict: .hasVerifiedUnlinked([row]), readerVersion: LegacyRowLinkageReader.version,
            rows: [row: .verifiedUnlinked], needsUploadCount: 0, orphanCorrespondenceCount: 0,
            hasAccountIdentityKeys: false, metadataKeyCount: LegacyRowLinkageReader.unaccountedV3MetadataKeys.count,
            storeModel: "V3", mirroringAttached: true,
            localModelRowCount: 1, recordMetadataCount: 0,
            metadataKeys: Array(LegacyRowLinkageReader.unaccountedV3MetadataKeys),
            metadataEntryCount: LegacyRowLinkageReader.unaccountedV3MetadataKeys.count,
            metadataValueProfileComplete: true, metadataNeedsMigration: false
        )
    }

    private func linkedStore() -> LegacyRowLinkageReading {
        let row = LegacyRowIdentity(entity: .bibleDrawing, primaryKey: 1, rowID: "Genesis.1.1")
        return LegacyRowLinkageReading(
            verdict: .allLinked, readerVersion: LegacyRowLinkageReader.version,
            rows: [row: .linked], needsUploadCount: 0, orphanCorrespondenceCount: 0,
            hasAccountIdentityKeys: true, metadataKeyCount: 7, storeModel: "V6",
            mirroredRecordNames: ["CD_BibleDrawing_sample"], missingRecordNameCount: 0, unsettledRecordCount: 0,
            localModelRowCount: 1, recordMetadataCount: 1,
            metadataKeys: [
                "PFCloudKitMetadataClientVersionHashesKey",
                "PFCloudKitMetadataFrameworkVersionKey",
                "PFCloudKitMetadataModelVersionHashesKey",
                "PFCloudKitMetadataNeedsMetadataMigrationKey",
                "NSCloudKitMirroringDelegateCKIdentityRecordNameDefaultsKey",
                "NSCloudKitMirroringDelegateCheckedCKIdentityDefaultsKey",
                "NSCloudKitMirroringDelegateLastHistoryTokenKey"
            ],
            metadataEntryCount: 7, metadataValueProfileComplete: true,
            metadataNeedsMigration: false, metadataIdentityChecked: true
        )
    }

    @Test("첫 로그인 전송 예외는 계정 연결 없는 V3 원본에만 열린다")
    func firstLoginLegacyRequiresUnlinkedV3Evidence() {
        #expect(StoreOwnershipClaimRule.firstLoginLegacyV3(unlinkedV3()))

        var linked = linkedStore()
        linked.storeModel = "V3"
        #expect(!StoreOwnershipClaimRule.firstLoginLegacyV3(linked))

        var identityPresent = unlinkedV3()
        identityPresent.hasAccountIdentityKeys = true
        #expect(!StoreOwnershipClaimRule.firstLoginLegacyV3(identityPresent))

        var pending = unlinkedV3()
        pending.unsettledRecordCount = 1
        #expect(!StoreOwnershipClaimRule.firstLoginLegacyV3(pending))

        var unknownMetadata = unlinkedV3()
        unknownMetadata.metadataKeys.append("FutureCloudKitOwnershipKey")
        unknownMetadata.metadataKeyCount += 1
        unknownMetadata.metadataEntryCount += 1
        #expect(!StoreOwnershipClaimRule.firstLoginLegacyV3(unknownMetadata))

        var duplicateMetadata = unlinkedV3()
        duplicateMetadata.duplicateMetadataKeyCount = 1
        #expect(!StoreOwnershipClaimRule.firstLoginLegacyV3(duplicateMetadata))

        var incompleteMetadata = unlinkedV3()
        incompleteMetadata.metadataEntryCount += 1
        #expect(!StoreOwnershipClaimRule.firstLoginLegacyV3(incompleteMetadata))

        var migratorMarker = unlinkedV3()
        migratorMarker.metadataKeys.append("PFCloudKitMetadataModelMigratorMigrationBeganCommitKey")
        migratorMarker.metadataKeyCount += 1
        migratorMarker.metadataEntryCount += 1
        migratorMarker.migrationBeganCommitMarker = true
        #expect(StoreOwnershipClaimRule.firstLoginLegacyV3(migratorMarker))
        migratorMarker.migrationBeganCommitMarker = false
        #expect(StoreOwnershipClaimRule.firstLoginLegacyV3(migratorMarker))
        migratorMarker.migrationBeganCommitMarker = nil
        #expect(!StoreOwnershipClaimRule.firstLoginLegacyV3(migratorMarker))

        var migrating = unlinkedV3()
        migrating.metadataNeedsMigration = true
        #expect(!StoreOwnershipClaimRule.firstLoginLegacyV3(migrating))
    }

    @Test("기존 로그인 저장소는 현재 계정과의 미러링 일치와 서버 레코드 확인을 모두 요구한다")
    func existingStoreRequiresCloudProof() {
        let reading = linkedStore()
        let supportedOS = LegacyRowLinkageReader().validatedOSMajors
        #expect(StoreOwnershipClaimRule.existingPrivateStore(reading, osMajor: 26, validatedOSMajors: supportedOS, identityMatches: true, allRecordsExist: true))
        #expect(StoreOwnershipClaimRule.existingPrivateStore(reading, osMajor: 17, validatedOSMajors: supportedOS, identityMatches: true, allRecordsExist: true))
        #expect(StoreOwnershipClaimRule.existingPrivateStore(reading, osMajor: 18, validatedOSMajors: supportedOS, identityMatches: true, allRecordsExist: true))
        #expect(StoreOwnershipClaimRule.existingPrivateStore(reading, osMajor: 27, validatedOSMajors: supportedOS, identityMatches: true, allRecordsExist: true))
        #expect(!StoreOwnershipClaimRule.existingPrivateStore(reading, osMajor: 19, validatedOSMajors: supportedOS, identityMatches: true, allRecordsExist: true))
        #expect(!StoreOwnershipClaimRule.existingPrivateStore(reading, osMajor: 28, validatedOSMajors: supportedOS, identityMatches: true, allRecordsExist: true))
        #expect(!StoreOwnershipClaimRule.existingPrivateStore(reading, osMajor: 26, validatedOSMajors: supportedOS, identityMatches: false, allRecordsExist: true))
        #expect(!StoreOwnershipClaimRule.existingPrivateStore(reading, osMajor: 26, validatedOSMajors: supportedOS, identityMatches: true, allRecordsExist: false))

        var pending = reading
        pending.needsUploadCount = 1
        pending.unsettledRecordCount = 1
        pending.unsettledRecordNames = ["CD_BibleDrawing_sample"]
        #expect(StoreOwnershipClaimRule.existingPrivateStore(pending, osMajor: 26, validatedOSMajors: supportedOS, identityMatches: true, allRecordsExist: true))
        #expect(!StoreOwnershipClaimRule.existingPrivateStore(pending, osMajor: 26, validatedOSMajors: supportedOS, identityMatches: true, allRecordsExist: false))
        #expect(StoreOwnershipClaimRule.recordsRequiringServerProof(in: pending) == [])

        var malformedPending = pending
        malformedPending.unsettledRecordNames = []
        #expect(StoreOwnershipClaimRule.recordsRequiringServerProof(in: malformedPending) == nil)

        var unrelatedPending = pending
        unrelatedPending.unsettledRecordNames = ["CD_FavoriteVerse_other"]
        #expect(StoreOwnershipClaimRule.recordsRequiringServerProof(in: unrelatedPending) == nil)

        var duplicatePending = pending
        duplicatePending.unsettledRecordCount = 2
        duplicatePending.unsettledRecordNames = ["CD_BibleDrawing_sample", "CD_BibleDrawing_sample"]
        #expect(StoreOwnershipClaimRule.recordsRequiringServerProof(in: duplicatePending) == nil)

        var incompleteMetadata = reading
        incompleteMetadata.metadataEntryCount += 1
        #expect(!StoreOwnershipClaimRule.existingPrivateStore(incompleteMetadata, osMajor: 26, validatedOSMajors: supportedOS, identityMatches: true, allRecordsExist: true))

        var migratorMarker = reading
        migratorMarker.metadataKeys.append("PFCloudKitMetadataModelMigratorMigrationBeganCommitKey")
        migratorMarker.metadataKeyCount += 1
        migratorMarker.metadataEntryCount += 1
        migratorMarker.migrationBeganCommitMarker = true
        #expect(StoreOwnershipClaimRule.existingPrivateStore(migratorMarker, osMajor: 18, validatedOSMajors: [17, 18, 26], identityMatches: true, allRecordsExist: true))
        migratorMarker.migrationBeganCommitMarker = false
        #expect(StoreOwnershipClaimRule.existingPrivateStore(migratorMarker, osMajor: 18, validatedOSMajors: [17, 18, 26], identityMatches: true, allRecordsExist: true))
        migratorMarker.migrationBeganCommitMarker = nil
        #expect(!StoreOwnershipClaimRule.existingPrivateStore(migratorMarker, osMajor: 18, validatedOSMajors: [17, 18, 26], identityMatches: true, allRecordsExist: true))

        var migrating = reading
        migrating.metadataNeedsMigration = true
        #expect(!StoreOwnershipClaimRule.existingPrivateStore(migrating, osMajor: 26, validatedOSMajors: supportedOS, identityMatches: true, allRecordsExist: true))

        var uncheckedIdentity = reading
        uncheckedIdentity.metadataIdentityChecked = false
        #expect(!StoreOwnershipClaimRule.existingPrivateStore(uncheckedIdentity, osMajor: 26, validatedOSMajors: supportedOS, identityMatches: true, allRecordsExist: true))
    }

    @Test("private 저장소는 확인된 현재 계정의 소유 증명 뒤에만 연결한다")
    func privateStorePreflightRequiresMatchingOwnership() async {
        let accountA = scope("_a")
        let accountB = scope("_b")
        let matchingIdentity = StubCloudAccountIdentityClient(.identified(userRecordName: "_a"))
        let matchingProof = StubStoreOwnershipProof(value: accountA)
        let noProof = StubStoreOwnershipProof(value: nil)

        #expect(await PrivateStoreAttachmentPreflight.decide(
            identity: matchingIdentity,
            containerID: containerID,
            ownershipProof: matchingProof
        ) == .attach(accountA))
        #expect(await PrivateStoreAttachmentPreflight.decide(
            identity: matchingIdentity,
            containerID: containerID,
            ownershipProof: StubStoreOwnershipProof(value: accountB)
        ) == .hold)
        #expect(await PrivateStoreAttachmentPreflight.decide(
            identity: matchingIdentity,
            containerID: containerID,
            ownershipProof: noProof
        ) == .hold)
        #expect(await PrivateStoreAttachmentPreflight.decide(
            identity: StubCloudAccountIdentityClient(.noAccount),
            containerID: containerID,
            ownershipProof: matchingProof
        ) == .hold)
        #expect(await PrivateStoreAttachmentPreflight.decide(
            identity: StubCloudAccountIdentityClient(.unavailable),
            containerID: containerID,
            ownershipProof: matchingProof
        ) == .hold)
    }

    @Test("소유 증명 대기 중 계정 변경·로그아웃·확인 실패는 private 연결을 보류한다")
    func privateStorePreflightRechecksAccountAfterProof() async {
        for changedIdentity in [CloudAccountIdentity.identified(userRecordName: "_b"), .noAccount, .unavailable] {
            let identity = SequencedOwnershipIdentity(values: [.identified(userRecordName: "_a"), changedIdentity])
            #expect(await PrivateStoreAttachmentPreflight.decide(
                identity: identity,
                containerID: containerID,
                ownershipProof: StubStoreOwnershipProof(value: scope("_a"))
            ) == .hold)
        }
    }

    @Test("한 번 기록한 저장소 소유자는 로그아웃 뒤 다른 계정으로 바뀌지 않는다")
    func ledgerDoesNotRebindToAnotherAccount() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("store-owner-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let ledger = StoreOwnershipLedger(area: StoreOwnershipArea(root: root, fileName: "owner.json"))
        let accountA = scope("_a")
        let accountB = scope("_b")

        #expect(await ledger.claim(accountA, proof: .firstRunHadNoStore) == accountA)
        #expect(await ledger.claim(accountB, proof: .firstLoginFromUnaccountedV3) == nil)
        guard case .owner(let stored, let storedProof) = await ledger.read() else {
            Issue.record("유효한 소유 표식이 남아 있어야 한다")
            return
        }
        #expect(stored == accountA)
        #expect(storedProof == .firstRunHadNoStore)
    }

    @Test("기존 ledger가 현재 저장소의 다른 CloudKit identity를 우회하지 않는다")
    func existingLedgerCannotBypassChangedPersistedIdentity() async throws {
        let root = try LinkageFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let storeURL = try LinkageFixture.makeV6Store(in: root)
        for primaryKey in 1...3 {
            try LinkageFixture.link(storeURL, entity: .bibleDrawing, primaryKey: Int64(primaryKey))
        }
        try LinkageFixture.addIdentityKeys(storeURL)
        try LinkageFixture.exec(storeURL, "UPDATE ANSCKMETADATAENTRY SET ZSTRINGVALUE = '_b' WHERE ZKEY = 'NSCloudKitMirroringDelegateCKIdentityRecordNameDefaultsKey';")

        let preservation = PreservationArea(root: root.appendingPathComponent("Preservation", isDirectory: true), storeFileName: storeURL.lastPathComponent)
        let ownershipArea = StoreOwnershipArea(root: root.appendingPathComponent("Owners", isDirectory: true), fileName: "owner.json")
        let accountA = scope("_a")
        #expect(await StoreOwnershipLedger(area: ownershipArea).claim(accountA, proof: .currentPrivateCloudRecords) == accountA)
        let lookup = CountingSuccessfulRecordLookup()
        let client = CloudKitStoreOwnershipProofClient(
            identity: StubCloudAccountIdentityClient(.identified(userRecordName: "_a")),
            containerID: containerID,
            storeURL: storeURL,
            preservation: preservation,
            ownershipArea: ownershipArea,
            privateRecordLookup: lookup
        )

        #expect(await client.ownership(for: accountA) == nil)
        #expect(await lookup.callCount() == 0)
    }

    @Test("실제 proof client는 무계정 V3 원시 사본을 보존하며 반복 확인한다", arguments: [false, true])
    func productionClientClaimsVerifiedLegacySnapshot(keepWALOpen: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ownership-v3-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storeDirectory = root.appendingPathComponent("Store", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        let storeURL = try LinkageFixture.makeV3Store(in: storeDirectory)
        var writer: OpaquePointer?
        defer { sqlite3_close(writer) }
        if keepWALOpen {
            #expect(sqlite3_open_v2(storeURL.path, &writer, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK)
            let database = try #require(writer)
            #expect(sqlite3_exec(database, "PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; UPDATE ZBIBLEDRAWING SET Z_OPT=Z_OPT+1", nil, nil, nil) == SQLITE_OK)
            #expect(try !Data(contentsOf: URL(fileURLWithPath: storeURL.path + "-wal")).isEmpty)
        }
        let preservation = PreservationArea(root: root.appendingPathComponent("Preservation", isDirectory: true), storeFileName: "Carve.sqlite")
        guard case .success(.created(let snapshot)) = RawStoreSnapshot.takeIfNeeded(storeURL: storeURL, area: preservation) else {
            Issue.record("업데이트 전 V3 원시 사본이 만들어지지 않았다")
            return
        }
        let reader = LegacyRowLinkageReader()
        let reading = reader.judge(storeAt: storeURL)
        let account = scope("_a")
        let ownershipArea = StoreOwnershipArea(root: root.appendingPathComponent("Owners", isDirectory: true), fileName: "owner.json")
        let client = CloudKitStoreOwnershipProofClient(
            identity: StubCloudAccountIdentityClient(.identified(userRecordName: "_a")),
            containerID: containerID,
            storeURL: storeURL,
            preservation: preservation,
            ownershipArea: ownershipArea,
            privateRecordLookup: NoStoreRecordLookup()
        )

        guard reader.validatedOSMajors.contains(reader.osMajor) else {
            #expect(reading.isUnknown)
            #expect(await client.ownership(for: account) == nil)
            #expect(await StoreOwnershipLedger(area: ownershipArea).read().isAbsent)
            return
        }

        #expect(reading.metadataValueProfileComplete)
        #expect(reading.metadataNeedsMigration == false)
        #expect(Set(reading.metadataKeys) == LegacyRowLinkageReader.unaccountedV3MetadataKeys)
        let snapshotFiles = try FileManager.default.contentsOfDirectory(at: snapshot, includingPropertiesForKeys: nil)
            .filter { !$0.hasDirectoryPath }
        let sealedBytes = try snapshotFiles.map { try Data(contentsOf: $0) }
        #expect(await client.ownership(for: account) == account)
        #expect(try snapshotFiles.map { try Data(contentsOf: $0) } == sealedBytes)
        #expect(RawStoreSnapshot.completedSnapshotStores(in: preservation).count == 1)
        // 첫 로그인 직후 private 연결 전 재시도해도 같은 원본 근거를 다시 사용할 수 있어야 한다.
        #expect(await client.ownership(for: account) == account)
        #expect(try snapshotFiles.map { try Data(contentsOf: $0) } == sealedBytes)
        guard case .owner(let recorded, let proof) = await StoreOwnershipLedger(area: ownershipArea).read() else {
            Issue.record("검증을 마친 소유 표식이 없다")
            return
        }
        #expect(recorded == account)
        #expect(proof == .firstLoginFromUnaccountedV3)
    }

    @Test("요청 계정과 실제 확인 계정이 다르면 V3 소유 표식을 만들지 않는다")
    func productionClientRejectsDifferentConfirmedAccount() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ownership-mismatch-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storeDirectory = root.appendingPathComponent("Store", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        let storeURL = try LinkageFixture.makeV3Store(in: storeDirectory)
        let preservation = PreservationArea(root: root.appendingPathComponent("Preservation", isDirectory: true), storeFileName: "Carve.sqlite")
        guard case .success(.created) = RawStoreSnapshot.takeIfNeeded(storeURL: storeURL, area: preservation) else {
            Issue.record("업데이트 전 V3 원시 사본이 만들어지지 않았다")
            return
        }
        let ownershipArea = StoreOwnershipArea(root: root.appendingPathComponent("Owners", isDirectory: true), fileName: "owner.json")
        let client = CloudKitStoreOwnershipProofClient(
            identity: StubCloudAccountIdentityClient(.identified(userRecordName: "_b")),
            containerID: containerID,
            storeURL: storeURL,
            preservation: preservation,
            ownershipArea: ownershipArea,
            privateRecordLookup: NoStoreRecordLookup()
        )

        #expect(await client.ownership(for: scope("_a")) == nil)
        #expect(await StoreOwnershipLedger(area: ownershipArea).read().isAbsent)
    }

    @Test("원시 사본 손상이나 미지 메타데이터 키는 계정 귀속을 막는다")
    func productionClientRejectsDamagedOrUnrecognizedLegacyEvidence() async throws {
        for addsUnknownKey in [false, true] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("ownership-unknown-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let storeDirectory = root.appendingPathComponent("Store", isDirectory: true)
            try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
            let storeURL = try LinkageFixture.makeV3Store(in: storeDirectory)
            if addsUnknownKey {
                try LinkageFixture.exec(storeURL, "INSERT INTO ANSCKMETADATAENTRY (Z_ENT, Z_OPT, ZKEY) VALUES (17009, 1, 'FutureCloudKitOwnershipKey');")
            }
            let preservation = PreservationArea(root: root.appendingPathComponent("Preservation", isDirectory: true), storeFileName: "Carve.sqlite")
            guard case .success(.created(let snapshot)) = RawStoreSnapshot.takeIfNeeded(storeURL: storeURL, area: preservation) else {
                Issue.record("업데이트 전 V3 원시 사본이 만들어지지 않았다")
                return
            }
            if !addsUnknownKey {
                var changedBytes = try Data(contentsOf: snapshot.appendingPathComponent("Carve.sqlite"))
                changedBytes[changedBytes.startIndex] ^= 1
                try changedBytes.write(to: snapshot.appendingPathComponent("Carve.sqlite"))
            }
            let ownershipArea = StoreOwnershipArea(root: root.appendingPathComponent("Owners", isDirectory: true), fileName: "owner.json")
            let client = CloudKitStoreOwnershipProofClient(
                identity: StubCloudAccountIdentityClient(.identified(userRecordName: "_a")),
                containerID: containerID,
                storeURL: storeURL,
                preservation: preservation,
                ownershipArea: ownershipArea,
                privateRecordLookup: NoStoreRecordLookup()
            )

            #expect(await client.ownership(for: scope("_a")) == nil)
            #expect(await StoreOwnershipLedger(area: ownershipArea).read().isAbsent)
        }
    }
}

/// 이미 연결한 저장소의 재실행 판정(시험 계획 2026-09-28). 첫 연결 판정을 매 실행 다시 요구하면 빈 저장소 · 대응 전 행 · 오프라인에서 영구 보류된다.
@Suite("이미 연결한 저장소의 재실행 소유 판정")
struct StoreOwnershipRelaunchTesting {
    private let containerID = "iCloud.Carve.SwiftData.iCloud.dev"

    enum StoreShape: String, CaseIterable, Sendable {
        /// 전체 삭제 뒤 · 필사 없이 로그인만 한 저장소.
        case empty
        /// 저장한 뒤 CloudKit 대응이 생기기 전에 앱이 끝난 행이 있다.
        case unlinkedRow
        /// 모든 행이 대응돼 있지만 서버에 닿지 못한다(오프라인).
        case serverUnreachable
    }

    private func scope(_ name: String) -> AccountScope {
        .make(containerID: containerID, userRecordName: name)
    }

    /// `persistedAccount` 로 연결된 적 있는 V6 저장소. 절 1 · 2 · 3 중 `linked` 만 대응을 붙이고, `empty` 면 행을 모두 지운다.
    private func linkedV6Store(in root: URL, persistedAccount: String, linked: [Int64], empty: Bool = false) throws -> URL {
        let storeURL = try LinkageFixture.makeV6Store(in: root)
        if empty {
            try LinkageFixture.exec(storeURL, "DELETE FROM ZBIBLEDRAWING;")
        }
        for primaryKey in linked {
            try LinkageFixture.link(storeURL, entity: .bibleDrawing, primaryKey: primaryKey)
        }
        try LinkageFixture.addIdentityKeys(storeURL)
        try LinkageFixture.exec(
            storeURL,
            "UPDATE ANSCKMETADATAENTRY SET ZSTRINGVALUE = '\(persistedAccount)' WHERE ZKEY = 'NSCloudKitMirroringDelegateCKIdentityRecordNameDefaultsKey';"
        )
        return storeURL
    }

    private func store(_ shape: StoreShape, in root: URL, persistedAccount: String) throws -> URL {
        switch shape {
        case .empty: try linkedV6Store(in: root, persistedAccount: persistedAccount, linked: [], empty: true)
        case .unlinkedRow: try linkedV6Store(in: root, persistedAccount: persistedAccount, linked: [1, 2])
        case .serverUnreachable: try linkedV6Store(in: root, persistedAccount: persistedAccount, linked: [1, 2, 3])
        }
    }

    private func makeClient(
        storeURL: URL,
        root: URL,
        currentAccount: String,
        lookup: any StorePrivateRecordLookupClient
    ) -> (client: CloudKitStoreOwnershipProofClient, ownershipArea: StoreOwnershipArea) {
        let preservation = PreservationArea(root: root.appendingPathComponent("Preservation", isDirectory: true), storeFileName: storeURL.lastPathComponent)
        let ownershipArea = StoreOwnershipArea(root: root.appendingPathComponent("Owners", isDirectory: true), fileName: "owner.json")
        let client = CloudKitStoreOwnershipProofClient(
            identity: StubCloudAccountIdentityClient(.identified(userRecordName: currentAccount)),
            containerID: containerID,
            storeURL: storeURL,
            preservation: preservation,
            ownershipArea: ownershipArea,
            privateRecordLookup: lookup
        )
        return (client, ownershipArea)
    }

    @Test("이 계정으로 표식을 남긴 저장소는 재실행 때 행 · 대응 · 서버 조회 없이 연결한다", arguments: StoreShape.allCases)
    func ledgerOwnerAttachesWithoutFirstConnectionProof(shape: StoreShape) async throws {
        let root = try LinkageFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let storeURL = try store(shape, in: root, persistedAccount: "_a")
        let lookup = CountingFailingRecordLookup()
        let (client, ownershipArea) = makeClient(storeURL: storeURL, root: root, currentAccount: "_a", lookup: lookup)
        let account = scope("_a")
        #expect(await StoreOwnershipLedger(area: ownershipArea).claim(account, proof: .currentPrivateCloudRecords) == account)

        #expect(await client.ownership(for: account) == account)
        #expect(await client.ownership(for: account) == account)
        #expect(await lookup.callCount() == 0)
    }

    @Test("표식이 없는 빈 연결 저장소는 빈 저장소 근거를 남기고 연결한다")
    func emptyLinkedStoreClaimsWithoutServerProof() async throws {
        let root = try LinkageFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let storeURL = try store(.empty, in: root, persistedAccount: "_a")
        let lookup = CountingFailingRecordLookup()
        let (client, ownershipArea) = makeClient(storeURL: storeURL, root: root, currentAccount: "_a", lookup: lookup)
        let account = scope("_a")

        #expect(await client.ownership(for: account) == account)
        #expect(await lookup.callCount() == 0)
        guard case .owner(let recorded, let proof) = await StoreOwnershipLedger(area: ownershipArea).read() else {
            Issue.record("빈 연결 저장소의 소유 표식이 없다")
            return
        }
        #expect(recorded == account)
        #expect(proof == .emptyLinkedStore)
    }

    @Test("표식이 없고 행이 있으면 첫 연결 판정을 그대로 요구한다", arguments: [StoreShape.unlinkedRow, .serverUnreachable])
    func unmarkedStoreWithRowsKeepsFirstConnectionProof(shape: StoreShape) async throws {
        let root = try LinkageFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let storeURL = try store(shape, in: root, persistedAccount: "_a")
        let (client, ownershipArea) = makeClient(storeURL: storeURL, root: root, currentAccount: "_a", lookup: CountingFailingRecordLookup())

        #expect(await client.ownership(for: scope("_a")) == nil)
        #expect(await StoreOwnershipLedger(area: ownershipArea).read().isAbsent)
    }

    @Test("저장소의 계정 식별이 다르면 비어 있어도 · 표식이 있어도 연결하지 않는다", arguments: [false, true])
    func differentPersistedAccountStaysHeld(hasLedger: Bool) async throws {
        let root = try LinkageFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let storeURL = try store(.empty, in: root, persistedAccount: "_b")
        let (client, ownershipArea) = makeClient(storeURL: storeURL, root: root, currentAccount: "_a", lookup: CountingFailingRecordLookup())
        let account = scope("_a")
        if hasLedger {
            #expect(await StoreOwnershipLedger(area: ownershipArea).claim(account, proof: .emptyLinkedStore) == account)
        }

        #expect(await client.ownership(for: account) == nil)
        #expect(await StoreOwnershipLedger(area: ownershipArea).read().isAbsent == !hasLedger)
    }
}

private struct NoStoreRecordLookup: StorePrivateRecordLookupClient {
    func allRecordsExist(_ recordNames: [String]) async -> Bool { false }
}

/// 서버에 닿지 못하는 조회 — 불렸는지 센다.
private actor CountingFailingRecordLookup: StorePrivateRecordLookupClient {
    private var calls = 0

    func allRecordsExist(_ recordNames: [String]) async -> Bool {
        calls += 1
        return false
    }

    func callCount() -> Int { calls }
}

private actor SequencedOwnershipIdentity: CloudAccountIdentityClient {
    private var values: [CloudAccountIdentity]

    init(values: [CloudAccountIdentity]) { self.values = values }

    func currentIdentity() async -> CloudAccountIdentity {
        guard !values.isEmpty else { return .unavailable }
        return values.removeFirst()
    }
}

private actor CountingSuccessfulRecordLookup: StorePrivateRecordLookupClient {
    private var calls = 0

    func allRecordsExist(_ recordNames: [String]) async -> Bool {
        calls += 1
        return true
    }

    func callCount() -> Int { calls }
}

private struct StubStoreOwnershipProof: StoreOwnershipProofClient {
    let value: AccountScope?

    func ownership(for scope: AccountScope) async -> AccountScope? {
        value == scope ? value : nil
    }
}

private extension StoreOwnershipLedger.ReadResult {
    var isAbsent: Bool {
        if case .absent = self { return true }
        return false
    }
}
