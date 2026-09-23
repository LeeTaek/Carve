//
//  DrawingStoreOwnershipProofTesting.swift
//  DomainTest
//

import Foundation
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
        migratorMarker.metadataValueProfileComplete = false
        #expect(!StoreOwnershipClaimRule.firstLoginLegacyV3(migratorMarker))

        var migrating = unlinkedV3()
        migrating.metadataNeedsMigration = true
        #expect(!StoreOwnershipClaimRule.firstLoginLegacyV3(migrating))
    }

    @Test("기존 로그인 저장소는 현재 계정과의 미러링 일치와 서버 레코드 확인을 모두 요구한다")
    func existingStoreRequiresCloudProof() {
        let reading = linkedStore()
        let supportedOS: Set<Int> = [26]
        #expect(StoreOwnershipClaimRule.existingPrivateStore(reading, osMajor: 26, validatedOSMajors: supportedOS, identityMatches: true, allRecordsExist: true))
        #expect(!StoreOwnershipClaimRule.existingPrivateStore(reading, osMajor: 18, validatedOSMajors: supportedOS, identityMatches: true, allRecordsExist: true))
        #expect(!StoreOwnershipClaimRule.existingPrivateStore(reading, osMajor: 26, validatedOSMajors: supportedOS, identityMatches: false, allRecordsExist: true))
        #expect(!StoreOwnershipClaimRule.existingPrivateStore(reading, osMajor: 26, validatedOSMajors: supportedOS, identityMatches: true, allRecordsExist: false))

        var pending = reading
        pending.needsUploadCount = 1
        pending.unsettledRecordCount = 1
        #expect(!StoreOwnershipClaimRule.existingPrivateStore(pending, osMajor: 26, validatedOSMajors: supportedOS, identityMatches: true, allRecordsExist: true))

        var incompleteMetadata = reading
        incompleteMetadata.metadataEntryCount += 1
        #expect(!StoreOwnershipClaimRule.existingPrivateStore(incompleteMetadata, osMajor: 26, validatedOSMajors: supportedOS, identityMatches: true, allRecordsExist: true))

        var migratorMarker = reading
        migratorMarker.metadataKeys.append("PFCloudKitMetadataModelMigratorMigrationBeganCommitKey")
        migratorMarker.metadataKeyCount += 1
        migratorMarker.metadataEntryCount += 1
        migratorMarker.metadataValueProfileComplete = false
        #expect(!StoreOwnershipClaimRule.existingPrivateStore(migratorMarker, osMajor: 26, validatedOSMajors: supportedOS, identityMatches: true, allRecordsExist: true))

        var migrating = reading
        migrating.metadataNeedsMigration = true
        #expect(!StoreOwnershipClaimRule.existingPrivateStore(migrating, osMajor: 26, validatedOSMajors: supportedOS, identityMatches: true, allRecordsExist: true))

        var uncheckedIdentity = reading
        uncheckedIdentity.metadataIdentityChecked = false
        #expect(!StoreOwnershipClaimRule.existingPrivateStore(uncheckedIdentity, osMajor: 26, validatedOSMajors: supportedOS, identityMatches: true, allRecordsExist: true))
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
        guard case .owner(let stored) = await ledger.read() else {
            Issue.record("유효한 소유 표식이 남아 있어야 한다")
            return
        }
        #expect(stored == accountA)
    }

    @Test("실제 proof client는 무계정 V3 사본의 무결성과 정확한 메타데이터 모양 뒤에만 소유를 기록한다")
    func productionClientClaimsVerifiedLegacySnapshot() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ownership-v3-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storeDirectory = root.appendingPathComponent("Store", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        let storeURL = try LinkageFixture.makeV3Store(in: storeDirectory)
        let preservation = PreservationArea(root: root.appendingPathComponent("Preservation", isDirectory: true), storeFileName: "Carve.sqlite")
        guard case .success(.created) = RawStoreSnapshot.takeIfNeeded(storeURL: storeURL, area: preservation) else {
            Issue.record("업데이트 전 V3 원시 사본이 만들어지지 않았다")
            return
        }
        let reading = LegacyRowLinkageReader().judge(storeAt: storeURL)
        #expect(reading.metadataValueProfileComplete)
        #expect(reading.metadataNeedsMigration == false)
        #expect(Set(reading.metadataKeys) == LegacyRowLinkageReader.unaccountedV3MetadataKeys)
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

        #expect(await client.ownership(for: account) == account)
        guard case .owner(let recorded) = await StoreOwnershipLedger(area: ownershipArea).read() else {
            Issue.record("검증을 마친 소유 표식이 없다")
            return
        }
        #expect(recorded == account)
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

private struct NoStoreRecordLookup: StorePrivateRecordLookupClient {
    func allRecordsExist(_ recordNames: [String]) async -> Bool { false }
}

private extension StoreOwnershipLedger.ReadResult {
    var isAbsent: Bool {
        if case .absent = self { return true }
        return false
    }
}
