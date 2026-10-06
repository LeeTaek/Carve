//
//  BackupImportJobStore.swift
//  Domain
//
//  Created by Claude on 10/6/26.
//  Copyright © 2026 leetaek. All rights reserved.
//
//  불러오기 작업 기록 — Application Support/BackupImport/<jobID>/ 에 고른 파일의 암호화 사본과 job.json (설계 §6-3).
//

import CarveToolkit
import Foundation

/// 불러오기 작업 하나의 기록(`job.json`) — 대상 계정 범위 · 상태 · 끝난 장 · 수 (설계 §6-3).
///
/// **기기 안에만 둔다.** `AccountScope` 는 여기에만 있고 백업 파일에는 없다. 평문 필기 · 암호는 담지 않는다.
struct BackupImportJobRecord: Codable, Equatable, Sendable {
    /// 작업의 상태.
    enum Status: String, Codable, Sendable {
        /// 검사만 했다 — 적용을 시작하지 않았다. 이어 하기 대상이 아니고, 다음 적용이 시작될 때 지운다.
        case inspected
        /// 적용 중이다 — 앱이 이 상태로 끝났으면 이어 하기 대상이다.
        case applying
        /// 적용이 멈췄다(막힘 · 계정 바뀜 · 세대 바뀜 · 쓰기 실패 · 취소) — 이어 하기 대상이다.
        case stopped
    }

    /// 기록 형식 버전 — 바꾸면 올린다.
    var recordVersion = 1
    /// 작업 id(UUID 문자열) — 폴더 이름이다.
    let jobID: String
    /// 대상 계정 범위. nil 이면 미리보기만 할 수 있던 작업이다.
    var targetScope: AccountScope?
    /// 상태.
    var status: Status
    /// 끝난 장(쓴 순서).
    var doneChapters: [BibleChapter]
    /// 끝난 장들의 실제 결정 수.
    var tally: BackupImportTally
    /// 적용할 장 수(지원 항목이 있는 장).
    var totalChapters: Int
    /// 검사한 시각.
    let createdAt: Date
    /// 마지막으로 기록한 시각.
    var updatedAt: Date

    /// 적용을 시작한 끝나지 않은 작업인가 — 이어 하기 대상.
    var isPending: Bool { status != .inspected }
}

/// 불러오기 작업 기록 저장소 — `Application Support/BackupImport/<jobID>/` 아래 `job.json` 과 고른 파일의 **암호화 사본**(`backup.carvebackup`).
///
/// - 평문 작업 폴더(`BackupWork` — 앱 시작 때 통째로 지운다)와 따로 둔다. 이어 하려면 앱을 다시 열어도 남아야 하기 때문이다.
/// - `job.json` 은 `DurableFile` 로 쓴다(장치까지 내린 뒤 이름 바꾸기 — 기록이 있으면 내용도 끝까지 있다).
/// - 부모 폴더는 기기 백업에서 뺀다 — 이 기기의 작업 상태라 다른 기기로 옮겨 가지 않는다.
/// - 작업 id 는 UUID 문자열만 받는다 — 밖에서 받은 작업(`BackupImportJob`)의 id 로 폴더 밖을 가리키지 못하게.
public struct BackupImportJobStore: Sendable {
    /// 모든 작업의 부모 — 앱은 `Application Support/BackupImport`, 시험은 시험마다 따로 둔다.
    public let root: URL

    /// 작업 기록 파일 이름.
    static let recordFileName = "job.json"
    /// 암호화 사본 파일 이름.
    static let archiveFileName = "backup.carvebackup"

    /// 앱의 작업 부모 폴더 — `Application Support/BackupImport`.
    public static var defaultRoot: URL {
        URL.applicationSupportDirectory.appendingPathComponent("BackupImport", isDirectory: true)
    }

    /// - Parameter root: 작업 부모 폴더. 기본은 `defaultRoot`.
    public init(root: URL = BackupImportJobStore.defaultRoot) {
        self.root = root
    }

    // MARK: - 경로

    /// 작업 폴더. 작업 id 가 UUID 문자열이 아니면 nil.
    func folder(for jobID: String) -> URL? {
        guard UUID(uuidString: jobID) != nil else { return nil }
        return root.appendingPathComponent(jobID, isDirectory: true)
    }

    /// 고른 파일의 암호화 사본 위치. 작업 id 가 UUID 문자열이 아니면 nil.
    func archiveURL(for jobID: String) -> URL? {
        folder(for: jobID)?.appendingPathComponent(Self.archiveFileName, isDirectory: false)
    }

    // MARK: - 쓰기

    /// 새 작업을 만든다 — 폴더 · `job.json` 을 먼저 쓰고 고른 파일을 암호화 사본으로 복사한다(사본은 장치까지 내린다).
    /// - Parameters:
    ///   - record: 새 작업 기록(상태 `inspected`).
    ///   - source: 고른 파일(보안 범위 접근은 부르는 쪽이 열어 둔다). 크기 · 시각을 읽지 않고 복사만 한다.
    /// - Throws: 폴더 · 기록 · 복사에 실패하면 그 오류. 실패하면 만든 폴더를 지운다.
    func create(_ record: BackupImportJobRecord, copying source: URL) throws {
        guard let folder = folder(for: record.jobID), let archive = archiveURL(for: record.jobID) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        try prepareRoot()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            try save(record)
            try FileManager.default.copyItem(at: source, to: archive)
            try DurableFile.flush(archive)
        } catch {
            remove(record.jobID)
            throw error
        }
    }

    /// 작업 기록을 쓴다(`DurableFile` — 기존 기록은 한 번에 바뀐다).
    /// - Throws: 인코딩 · 쓰기 실패, 작업 id 가 UUID 문자열이 아니면 `fileWriteInvalidFileName`.
    func save(_ record: BackupImportJobRecord) throws {
        guard let folder = folder(for: record.jobID) else { throw CocoaError(.fileWriteInvalidFileName) }
        let data = try BackupFormat.encoder.encode(record)
        try DurableFile.write(data, to: folder.appendingPathComponent(Self.recordFileName, isDirectory: false))
    }

    /// 작업 폴더를 통째로 지운다(기록 · 암호화 사본). 없으면 아무것도 하지 않는다.
    /// - 부작용: 파일 삭제. 지우지 못하면 로그만 남긴다.
    func remove(_ jobID: String) {
        guard let folder = folder(for: jobID) else { return }
        do {
            try FileManager.default.removeItem(at: folder)
        } catch CocoaError.fileNoSuchFile {
            return
        } catch {
            Log.error("불러오기 작업 기록을 지우지 못했다", "\(error)")
        }
    }

    /// 이 작업을 뺀 다른 작업을 모두 지운다 — 새 적용이 시작되면 앞선 작업은 대신된다.
    func removeAll(except jobID: String) {
        for other in jobIDs() where other != jobID {
            remove(other)
        }
    }

    // MARK: - 읽기

    /// 작업 기록. 없거나 읽지 못하면 nil.
    func load(_ jobID: String) -> BackupImportJobRecord? {
        guard let folder = folder(for: jobID),
              let data = try? Data(contentsOf: folder.appendingPathComponent(Self.recordFileName, isDirectory: false)),
              let record = try? BackupFormat.decoder.decode(BackupImportJobRecord.self, from: data),
              record.jobID == jobID else { return nil }
        return record
    }

    /// 읽을 수 있는 모든 작업 기록.
    func records() -> [BackupImportJobRecord] {
        jobIDs().compactMap(load)
    }

    /// 부모 폴더 안의 작업 id(UUID 이름의 폴더만).
    private func jobIDs() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.filter { UUID(uuidString: $0) != nil }.sorted()
    }

    /// 부모 폴더를 만들고(소유자만 접근) 기기 백업에서 뺀다.
    private func prepareRoot() throws {
        var url = root
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        do {
            try url.setResourceValues(values)
        } catch {
            Log.error("불러오기 작업 폴더를 기기 백업에서 빼지 못했다", "\(error)")
        }
    }
}
