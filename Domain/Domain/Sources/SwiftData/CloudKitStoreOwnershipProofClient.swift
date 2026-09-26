//
//  CloudKitStoreOwnershipProofClient.swift
//  Domain
//
//  로그인 계정과 기기 저장소를 최초 한 번 안전하게 연결한다.
//

import CarveToolkit
import CloudKit
import Foundation

/// CloudKit 미러링 밖에 둔 저장소 소유 표식. 전체 로컬 데이터 삭제 뒤에도 남겨 계정 변경으로 소유권이 바뀌지 않게 한다.
struct StoreOwnershipArea: Sendable {
    let root: URL
    let fileName: String

    var marker: URL { root.appendingPathComponent(fileName) }

    static func live(localDBPath: String) -> StoreOwnershipArea {
        StoreOwnershipArea(
            root: URL.applicationSupportDirectory.appending(path: "StoreOwnership", directoryHint: .isDirectory),
            fileName: localDBPath + ".json"
        )
    }
}

protocol StorePrivateRecordLookupClient: Sendable {
    func allRecordsExist(_ recordNames: [String]) async -> Bool
}

private struct CloudKitPrivateRecordLookupClient: StorePrivateRecordLookupClient {
    private let database: CKDatabase

    init(containerID: String) {
        database = CKContainer(identifier: containerID).privateCloudDatabase
    }

    func allRecordsExist(_ recordNames: [String]) async -> Bool {
        guard !recordNames.isEmpty else { return false }
        let zoneID = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName)
        let recordIDs = Set(recordNames.map { CKRecord.ID(recordName: $0, zoneID: zoneID) })
        let ids = Array(recordIDs)
        for start in stride(from: 0, to: ids.count, by: 200) {
            let batch = Array(ids[start..<min(start + 200, ids.count)])
            do {
                let results = try await database.records(for: batch, desiredKeys: [])
                guard results.count == batch.count,
                      results.values.allSatisfy({ if case .success = $0 { true } else { false } }) else { return false }
            } catch {
                Log.info("저장소 소유 근거 — private DB 레코드 확인을 마치지 못했다", "계정 식별은 기록하지 않는다", "\(error)")
                return false
            }
        }
        return true
    }
}

/// 소유 표식은 이 기기의 설치 영역에만 저장한다. 다른 계정의 표식은 자동으로 바꾸지 않는다.
actor StoreOwnershipLedger {
    private struct Marker: Codable {
        var formatVersion: Int
        var owner: AccountScope
        var proof: Proof
    }

    enum Proof: String, Codable, Equatable {
        case firstRunHadNoStore
        case firstLoginFromUnaccountedV3
        case currentPrivateCloudRecords
    }

    enum ReadResult {
        case absent
        case owner(AccountScope, Proof)
        case invalid
    }

    private let area: StoreOwnershipArea
    private let fileManager: FileManager

    init(area: StoreOwnershipArea, fileManager: FileManager = .default) {
        self.area = area
        self.fileManager = fileManager
    }

    func read() -> ReadResult {
        guard fileManager.fileExists(atPath: area.marker.path) else { return .absent }
        do {
            let marker = try JSONDecoder().decode(Marker.self, from: Data(contentsOf: area.marker))
            guard marker.formatVersion == 1 else { return .invalid }
            return .owner(marker.owner, marker.proof)
        } catch {
            return .invalid
        }
    }

    func claim(_ scope: AccountScope, proof: Proof) -> AccountScope? {
        switch read() {
        case .owner(let owner, _): return owner == scope ? owner : nil
        case .invalid: return nil
        case .absent: break
        }

        do {
            try fileManager.createDirectory(at: area.root, withIntermediateDirectories: true)
            var attributes = try fileManager.attributesOfItem(atPath: area.root.path)
            attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
            try fileManager.setAttributes(attributes, ofItemAtPath: area.root.path)
            let marker = Marker(formatVersion: 1, owner: scope, proof: proof)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try DurableFile.write(try encoder.encode(marker), to: area.marker)
            return scope
        } catch {
            Log.error("저장소 소유 근거를 기록하지 못했다", "계정 식별은 기록하지 않는다", "\(error)")
            return nil
        }
    }
}

/// CloudKit 접근과 분리된 소유 주장 규칙. 계정 확인만으로는 두 분기 모두 통과하지 않는다.
enum StoreOwnershipClaimRule {
    static func firstLoginLegacyV3(_ reading: LegacyRowLinkageReading) -> Bool {
        unaccountedLegacyRows(reading, modelMajors: [3])
    }

    private static func unaccountedLegacyRows(_ reading: LegacyRowLinkageReading, modelMajors: Set<Int>) -> Bool {
        guard case .hasVerifiedUnlinked(let rows) = reading.verdict,
              let modelMajor = Int(reading.storeModel.dropFirst()),
              modelMajors.contains(modelMajor) else { return false }
        return !rows.isEmpty && reading.unlinkedCount == rows.count && reading.linkedCount == 0
            && reading.mirroredRecordNames.isEmpty && reading.missingRecordNameCount == 0 && reading.unsettledRecordCount == 0
            && reading.localModelRowCount == rows.count && reading.recordMetadataCount == 0
            && reading.mirroringAttached && !reading.hasAccountIdentityKeys
            && reading.metadataEntryCount == reading.metadataKeyCount
            && reading.duplicateMetadataKeyCount == 0
            && LegacyRowLinkageReader.observedUnaccountedV3MetadataProfiles.contains(Set(reading.metadataKeys))
            && reading.metadataKeyCount == reading.metadataKeys.count
            && migratorMarkerHasObservedStructure(reading)
            && reading.metadataValueProfileComplete && reading.metadataNeedsMigration == false
    }

    /// 관측된 private key의 존재와 저장 형식만 확인한다. true/false 어느 값에도 완료·진행 의미를 부여하지 않는다.
    private static func migratorMarkerHasObservedStructure(_ reading: LegacyRowLinkageReading) -> Bool {
        let keyIsPresent = reading.metadataKeys.contains(LegacyRowLinkageReader.migrationBeganCommitKey)
        return keyIsPresent == (reading.migrationBeganCommitMarker != nil)
    }

    /// 원시 V3 사본과 아직 private에 연결하지 않은 로컬 저장소가 같은 미계정 행 집합인지 교차 확인한다.
    static func currentStoreCanUseUnaccountedSnapshot(
        _ current: LegacyRowLinkageReading,
        source: LegacyRowLinkageReading
    ) -> Bool {
        guard unaccountedLegacyRows(source, modelMajors: [3]),
              unaccountedLegacyRows(current, modelMajors: [3, 6]) else { return false }
        return Set(current.rows.keys) == Set(source.rows.keys)
    }

    /// 처음 저장소가 없었다는 ledger는 비어 있고 미확인 대기 작업도 없는 현재 저장소에서만 재사용한다.
    static func emptyUnaccountedStore(_ reading: LegacyRowLinkageReading) -> Bool {
        guard reading.verdict == .allLinked, reading.rows.isEmpty,
              reading.localModelRowCount == 0, reading.recordMetadataCount == 0,
              reading.mirroredRecordNames.isEmpty, reading.missingRecordNameCount == 0,
              reading.unsettledRecordCount == 0, reading.unsettledRecordNames.isEmpty,
              reading.orphanCorrespondenceCount == 0, reading.needsUploadCount == 0,
              !reading.hasAccountIdentityKeys,
              reading.metadataEntryCount == reading.metadataKeyCount,
              reading.duplicateMetadataKeyCount == 0 else { return false }

        guard reading.mirroringAttached else {
            return reading.metadataEntryCount == 0 && reading.metadataKeyCount == 0
        }
        return reading.metadataValueProfileComplete && reading.metadataNeedsMigration == false
            && LegacyRowLinkageReader.observedUnaccountedV3MetadataProfiles.contains(Set(reading.metadataKeys))
            && reading.metadataKeyCount == reading.metadataKeys.count
            && migratorMarkerHasObservedStructure(reading)
    }

    static func existingPrivateStore(
        _ reading: LegacyRowLinkageReading,
        osMajor: Int,
        validatedOSMajors: Set<Int>,
        identityMatches: Bool,
        allRecordsExist: Bool
    ) -> Bool {
        guard validatedOSMajors.contains(osMajor), case .allLinked = reading.verdict else { return false }
        guard pendingRecordNames(in: reading) != nil else { return false }
        return identityMatches && allRecordsExist && reading.localModelRowCount > 0
            && reading.localModelRowCount == reading.recordMetadataCount
            && reading.recordMetadataCount == reading.mirroredRecordNames.count
            && Set(reading.mirroredRecordNames).count == reading.mirroredRecordNames.count
            && reading.linkedCount == reading.rows.count
            && !reading.mirroredRecordNames.isEmpty && reading.missingRecordNameCount == 0
            && reading.orphanCorrespondenceCount == 0 && reading.hasAccountIdentityKeys
            && reading.metadataEntryCount == reading.metadataKeyCount && reading.duplicateMetadataKeyCount == 0
            && reading.metadataValueProfileComplete && reading.metadataNeedsMigration == false && reading.metadataIdentityChecked == true
            && LegacyRowLinkageReader.observedLinkedPrivateMetadataProfiles.contains(Set(reading.metadataKeys))
            && reading.metadataKeyCount == reading.metadataKeys.count
            && migratorMarkerHasObservedStructure(reading)
            && reading.metadataKeys.filter { $0 == "NSCloudKitMirroringDelegateCKIdentityRecordNameDefaultsKey" }.count == 1
    }

    /// 미완료 작업은 해당 CloudKit 레코드의 서버 존재를 요구하지 않는다. 작업 대상 이름은 로컬 미러 행과 일치해야 한다.
    static func pendingRecordNames(in reading: LegacyRowLinkageReading) -> Set<String>? {
        let names = reading.unsettledRecordNames
        guard reading.unsettledRecordCount == names.count,
              Set(names).count == names.count,
              Set(names).isSubset(of: Set(reading.mirroredRecordNames)) else { return nil }
        return Set(names)
    }

    /// 서버에 이미 정착한 레코드만 확인한다. 새로 만들어지는 중인 레코드가 없어도 정상 작업으로 소유 증명할 수 있다.
    static func recordsRequiringServerProof(in reading: LegacyRowLinkageReading) -> [String]? {
        guard let pending = pendingRecordNames(in: reading) else { return nil }
        return reading.mirroredRecordNames.filter { !pending.contains($0) }
    }
}

/// `.private` 컨테이너를 열기 전에 계정 식별과 저장소 소유 증명을 모두 확인한다.
enum PrivateStoreAttachmentPreflight {
    enum Decision: Equatable {
        case attach(AccountScope)
        case hold
    }

    static func decide(
        identity: any CloudAccountIdentityClient,
        containerID: String,
        ownershipProof: any StoreOwnershipProofClient,
        injectsOwnership: Bool = false
    ) async -> Decision {
        guard case .identified(let userRecordName) = await identity.currentIdentity() else { return .hold }
        let scope = AccountScope.make(containerID: containerID, userRecordName: userRecordName)
        if injectsOwnership { return .attach(scope) }
        guard await ownershipProof.ownership(for: scope) == scope else { return .hold }
        // 서버 조회를 기다리는 동안 로그아웃·계정 전환이 일어났다면 이전 계정의 proof로 연결하지 않는다.
        guard case .identified(let confirmedName) = await identity.currentIdentity(),
              AccountScope.make(containerID: containerID, userRecordName: confirmedName) == scope else { return .hold }
        return .attach(scope)
    }
}

/// 출시 앱이 쓰는 소유 근거. 계정 확인만으로는 표식을 만들지 않는다.
///
/// - 처음 없던 저장소: 첫 실행 때 원본 파일이 없었다는 원시 보존 표식으로 확인한다.
/// - 1.3.0 무계정 저장소: 업데이트 전 V3 사본에서 미러링 대응이 하나도 없는 경우에만 출시 결정의 첫 로그인 전송을 허용한다.
/// - 기존 로그인 저장소: 미러링 계정 키가 현재 CloudKit 계정과 같고, 모든 행이 동기화된 뒤 현재 계정의 private DB에서 레코드가 확인될 때만 허용한다.
/// 판정할 근거가 없거나 읽기·네트워크가 실패하면 소유를 인정하지 않는다.
public actor CloudKitStoreOwnershipProofClient: StoreOwnershipProofClient {
    private let identity: any CloudAccountIdentityClient
    private let containerID: String
    private let storeURL: URL
    private let preservation: PreservationArea
    private let privateRecordLookup: any StorePrivateRecordLookupClient
    private let reader: LegacyRowLinkageReader
    private let ledger: StoreOwnershipLedger
    private let fileManager: FileManager

    public init(
        identity: any CloudAccountIdentityClient,
        containerID: String,
        storeURL: URL,
        preservation: PreservationArea,
        fileManager: FileManager = .default
    ) {
        self.identity = identity
        self.containerID = containerID
        self.storeURL = storeURL
        self.preservation = preservation
        self.privateRecordLookup = CloudKitPrivateRecordLookupClient(containerID: containerID)
        self.reader = LegacyRowLinkageReader()
        self.ledger = StoreOwnershipLedger(area: .live(localDBPath: preservation.storeFileName), fileManager: fileManager)
        self.fileManager = fileManager
    }

    init(
        identity: any CloudAccountIdentityClient,
        containerID: String,
        storeURL: URL,
        preservation: PreservationArea,
        ownershipArea: StoreOwnershipArea,
        privateRecordLookup: any StorePrivateRecordLookupClient,
        fileManager: FileManager = .default
    ) {
        self.identity = identity
        self.containerID = containerID
        self.storeURL = storeURL
        self.preservation = preservation
        self.privateRecordLookup = privateRecordLookup
        self.reader = LegacyRowLinkageReader()
        self.ledger = StoreOwnershipLedger(area: ownershipArea, fileManager: fileManager)
        self.fileManager = fileManager
    }

    public func ownership(for scope: AccountScope) async -> AccountScope? {
        let storedProof: StoreOwnershipLedger.Proof?
        switch await ledger.read() {
        case .owner(let owner, let proof):
            guard owner == scope else { return nil }
            storedProof = proof
        case .invalid: return nil
        case .absent: storedProof = nil
        }

        guard case .identified(let userRecordName) = await identity.currentIdentity(),
              AccountScope.make(containerID: containerID, userRecordName: userRecordName) == scope,
              let (scratch, copy) = currentStoreCopy() else { return nil }
        defer { try? fileManager.removeItem(at: scratch) }

        let currentReading = reader.judge(copyAt: copy)
        switch LegacyStoreAccountIdentityReader.status(copyAt: copy, userRecordName: userRecordName) {
        case .matches:
            return await proveExistingPrivateStore(for: scope, reading: currentReading, copy: copy, userRecordName: userRecordName)
        case .mismatch, .invalid:
            // 기존 ledger나 과거 unaccounted snapshot이 현재 저장소의 다른 계정 identity를 덮을 수 없다.
            return nil
        case .absent:
            break
        }

        // ledger는 계정 확인을 대신하지 않는다. 실제 metadata identity가 아직 없는 두 설치 증명만 재평가한다.
        if storedProof == .currentPrivateCloudRecords { return nil }
        if storedProof == .firstRunHadNoStore {
            guard fileManager.fileExists(atPath: preservation.notNeededMarker.path),
                  StoreOwnershipClaimRule.emptyUnaccountedStore(currentReading) else { return nil }
            return await ledger.claim(scope, proof: .firstRunHadNoStore)
        }

        if fileManager.fileExists(atPath: preservation.notNeededMarker.path) {
            if StoreOwnershipClaimRule.emptyUnaccountedStore(currentReading) {
                return await ledger.claim(scope, proof: .firstRunHadNoStore)
            }
            return nil
        }

        for snapshot in RawStoreSnapshot.completedSnapshotStores(in: preservation, fileManager: fileManager) {
            guard case .known(let version) = LocalStoreLoader.storeKind(at: snapshot), version.major == 3 else { continue }
            let reading = reader.judge(copyAt: snapshot)
            guard (storedProof == nil || storedProof == .firstLoginFromUnaccountedV3),
                  StoreOwnershipClaimRule.firstLoginLegacyV3(reading),
                  case .hasVerifiedUnlinked(let rows) = reading.verdict else { continue }
            guard StoreOwnershipClaimRule.currentStoreCanUseUnaccountedSnapshot(currentReading, source: reading),
                  LegacyMigrationContentMatcher.matches(sourceSnapshot: snapshot, currentStore: copy, fileManager: fileManager),
                  await currentAccountMatches(scope) else { return nil }
            Log.info("저장소 소유 근거 — 계정 연결 없는 1.3.0 V3 원본을 출시 정책에 따라 첫 로그인 계정에 연결한다", "행 \(rows.count) · 계정 식별은 기록하지 않는다")
            return await ledger.claim(scope, proof: .firstLoginFromUnaccountedV3)
        }

        guard storedProof == nil else { return nil }
        return await proveExistingPrivateStore(for: scope, reading: currentReading, copy: copy, userRecordName: userRecordName)
    }

    private func proveExistingPrivateStore(for scope: AccountScope) async -> AccountScope? {
        guard reader.validatedOSMajors.contains(reader.osMajor) else { return nil }
        guard case .identified(let userRecordName) = await identity.currentIdentity(),
              AccountScope.make(containerID: containerID, userRecordName: userRecordName) == scope else { return nil }

        guard let (scratch, copy) = currentStoreCopy() else { return nil }
        defer { try? fileManager.removeItem(at: scratch) }
        let reading = reader.judge(copyAt: copy)
        return await proveExistingPrivateStore(for: scope, reading: reading, copy: copy, userRecordName: userRecordName)
    }

    private func proveExistingPrivateStore(
        for scope: AccountScope,
        reading: LegacyRowLinkageReading,
        copy: URL,
        userRecordName: String
    ) async -> AccountScope? {
        let identityMatches = LegacyStoreAccountIdentityReader.status(copyAt: copy, userRecordName: userRecordName) == .matches
        guard let settledRecordNames = StoreOwnershipClaimRule.recordsRequiringServerProof(in: reading) else { return nil }
        let allRecordsExist: Bool
        if settledRecordNames.isEmpty {
            allRecordsExist = true
        } else {
            allRecordsExist = await privateRecordLookup.allRecordsExist(settledRecordNames)
        }
        guard StoreOwnershipClaimRule.existingPrivateStore(
            reading,
            osMajor: reader.osMajor,
            validatedOSMajors: reader.validatedOSMajors,
            identityMatches: identityMatches,
            allRecordsExist: allRecordsExist
        ),
              await currentAccountMatches(scope) else { return nil }

        return await ledger.claim(scope, proof: .currentPrivateCloudRecords)
    }

    private func currentStoreCopy() -> (scratch: URL, copy: URL)? {
        let scratch = fileManager.temporaryDirectory.appendingPathComponent("store-ownership-\(UUID().uuidString)", isDirectory: true)
        guard let copy = try? LegacyRowLinkageReader.copyStoreFiles(from: storeURL, into: scratch, fileManager: fileManager) else {
            try? fileManager.removeItem(at: scratch)
            return nil
        }
        let support = RawStoreSnapshot.supportDirectory(for: storeURL)
        if fileManager.fileExists(atPath: support.path) {
            do {
                try fileManager.copyItem(at: support, to: RawStoreSnapshot.supportDirectory(for: copy))
            } catch {
                try? fileManager.removeItem(at: scratch)
                return nil
            }
        }
        return (scratch, copy)
    }

    private func currentAccountMatches(_ scope: AccountScope) async -> Bool {
        guard case .identified(let userRecordName) = await identity.currentIdentity() else { return false }
        return AccountScope.make(containerID: containerID, userRecordName: userRecordName) == scope
    }
}
