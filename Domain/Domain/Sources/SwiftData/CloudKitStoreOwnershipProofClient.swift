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

    enum Proof: String, Codable {
        case firstRunHadNoStore
        case firstLoginFromUnaccountedV3
        case currentPrivateCloudRecords
    }

    enum ReadResult {
        case absent
        case owner(AccountScope)
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
            return .owner(marker.owner)
        } catch {
            return .invalid
        }
    }

    func claim(_ scope: AccountScope, proof: Proof) -> AccountScope? {
        switch read() {
        case .owner(let owner): return owner == scope ? owner : nil
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
        guard case .hasVerifiedUnlinked(let rows) = reading.verdict else { return false }
        return reading.storeModel == "V3" && !rows.isEmpty && reading.unlinkedCount == rows.count && reading.linkedCount == 0
            && reading.mirroredRecordNames.isEmpty && reading.missingRecordNameCount == 0 && reading.unsettledRecordCount == 0
            && reading.localModelRowCount == rows.count && reading.recordMetadataCount == 0
            && reading.mirroringAttached && !reading.hasAccountIdentityKeys
            && reading.metadataEntryCount == reading.metadataKeyCount
            && reading.metadataKeyCount == LegacyRowLinkageReader.unaccountedV3MetadataKeys.count
            && reading.duplicateMetadataKeyCount == 0
            && Set(reading.metadataKeys) == LegacyRowLinkageReader.unaccountedV3MetadataKeys
            && reading.metadataValueProfileComplete && reading.metadataNeedsMigration == false
    }

    static func existingPrivateStore(
        _ reading: LegacyRowLinkageReading,
        osMajor: Int,
        validatedOSMajors: Set<Int>,
        identityMatches: Bool,
        allRecordsExist: Bool
    ) -> Bool {
        guard validatedOSMajors.contains(osMajor), case .allLinked = reading.verdict else { return false }
        return identityMatches && allRecordsExist && reading.localModelRowCount > 0
            && reading.localModelRowCount == reading.recordMetadataCount
            && reading.recordMetadataCount == reading.mirroredRecordNames.count
            && Set(reading.mirroredRecordNames).count == reading.mirroredRecordNames.count
            && reading.linkedCount == reading.rows.count
            && !reading.mirroredRecordNames.isEmpty && reading.missingRecordNameCount == 0 && reading.unsettledRecordCount == 0
            && reading.needsUploadCount == 0 && reading.orphanCorrespondenceCount == 0 && reading.hasAccountIdentityKeys
            && reading.metadataEntryCount == reading.metadataKeyCount && reading.duplicateMetadataKeyCount == 0
            && reading.metadataValueProfileComplete && reading.metadataNeedsMigration == false && reading.metadataIdentityChecked == true
            && reading.metadataKeyCount == LegacyRowLinkageReader.linkedPrivateStoreMetadataKeys.count
            && Set(reading.metadataKeys) == LegacyRowLinkageReader.linkedPrivateStoreMetadataKeys
            && reading.metadataKeys.filter { $0 == "NSCloudKitMirroringDelegateCKIdentityRecordNameDefaultsKey" }.count == 1
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
        switch await ledger.read() {
        case .owner(let owner): return owner == scope ? owner : nil
        case .invalid: return nil
        case .absent: break
        }

        if fileManager.fileExists(atPath: preservation.notNeededMarker.path) {
            guard await currentAccountMatches(scope) else { return nil }
            guard let reading = currentStoreReading() else { return nil }
            if reading.localModelRowCount == 0 {
                return await ledger.claim(scope, proof: .firstRunHadNoStore)
            }
            return await proveExistingPrivateStore(for: scope)
        }

        for snapshot in RawStoreSnapshot.completedSnapshotStores(in: preservation, fileManager: fileManager) {
            guard case .known(let version) = LocalStoreLoader.storeKind(at: snapshot), version.major == 3 else { continue }
            let reading = reader.judge(copyAt: snapshot)
            guard StoreOwnershipClaimRule.firstLoginLegacyV3(reading),
                  case .hasVerifiedUnlinked(let rows) = reading.verdict else { continue }
            guard await currentAccountMatches(scope) else { return nil }
            Log.info("저장소 소유 근거 — 계정 연결 없는 1.3.0 V3 원본을 출시 정책에 따라 첫 로그인 계정에 연결한다", "행 \(rows.count) · 계정 식별은 기록하지 않는다")
            return await ledger.claim(scope, proof: .firstLoginFromUnaccountedV3)
        }

        return await proveExistingPrivateStore(for: scope)
    }

    private func proveExistingPrivateStore(for scope: AccountScope) async -> AccountScope? {
        guard reader.validatedOSMajors.contains(reader.osMajor) else { return nil }
        guard case .identified(let userRecordName) = await identity.currentIdentity(),
              AccountScope.make(containerID: containerID, userRecordName: userRecordName) == scope else { return nil }

        let scratch = fileManager.temporaryDirectory.appendingPathComponent("store-ownership-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: scratch) }
        let copy: URL
        do {
            copy = try LegacyRowLinkageReader.copyStoreFiles(from: storeURL, into: scratch, fileManager: fileManager)
        } catch {
            return nil
        }

        let reading = reader.judge(copyAt: copy)
        return await proveExistingPrivateStore(for: scope, reading: reading, copy: copy, userRecordName: userRecordName)
    }

    private func proveExistingPrivateStore(
        for scope: AccountScope,
        reading: LegacyRowLinkageReading,
        copy: URL,
        userRecordName: String
    ) async -> AccountScope? {
        let identityMatches = reader.accountIdentityMatches(copyAt: copy, userRecordName: userRecordName)
        let allRecordsExist = await privateRecordLookup.allRecordsExist(reading.mirroredRecordNames)
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

    private func currentStoreReading() -> LegacyRowLinkageReading? {
        let scratch = fileManager.temporaryDirectory.appendingPathComponent("store-ownership-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: scratch) }
        guard let copy = try? LegacyRowLinkageReader.copyStoreFiles(from: storeURL, into: scratch, fileManager: fileManager) else {
            return nil
        }
        let reading = reader.judge(copyAt: copy)
        return reading.isUnknown ? nil : reading
    }

    private func currentAccountMatches(_ scope: AccountScope) async -> Bool {
        guard case .identified(let userRecordName) = await identity.currentIdentity() else { return false }
        return AccountScope.make(containerID: containerID, userRecordName: userRecordName) == scope
    }
}
