//
//  BackupExportStaging.swift
//  Domain
//
//  내보내기의 평문 준비 폴더(`<작업 폴더>/staged/`)와, 다 쓴 파일의 재검증 (설계 docs/backup-import-design.md §3-1 5 · 6단계 · §2-7).
//  준비 폴더에는 허용 이름(manifest.json · items.json · blobs/<소문자 SHA-256 hex 64자>)만 쓴다 — `BackupArchive.write` 가 그 밖의 것을 거부한다.
//

import CarveToolkit
import Foundation

/// 내보내기의 평문 준비 폴더 — blob 은 내용 이름으로 **한 번씩** 쓰고, 항목을 모아 마지막에 manifest · items 를 쓴다.
///
/// 바이트는 장마다 곧바로 파일로 내보내고 들고 있지 않는다(메모리에는 장 하나 분량만). 항목(바이트 없는 JSON 값)만 모은다.
struct BackupExportStaging {
    /// 준비 폴더 — `BackupArchive.write(stagedDirectory:)` 에 넘긴다.
    let directory: URL
    /// `blobs/` 폴더.
    private let blobDirectory: URL
    /// 이미 쓴 blob — 이름 → manifest 항목.
    private(set) var blobs: [String: BackupBlobEntry] = [:]
    /// 모은 항목(담은 순서).
    private(set) var items: [BackupItem] = []
    /// 이미 담은 항목 id — 파일 안 id 는 겹칠 수 없다(설계 §4-2).
    private var itemIDs: Set<String> = []

    /// 빈 준비 폴더(`blobs/` 포함)를 만든다.
    /// - Parameter directory: 만들 준비 폴더(작업 폴더 안).
    /// - Throws: 폴더를 만들지 못하면 그 오류. 부작용: 폴더 생성.
    init(directory: URL) throws {
        self.directory = directory
        self.blobDirectory = directory.appendingPathComponent(BackupFormat.blobDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: blobDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    /// 항목을 담고 그 항목의 blob 을 쓴다. 같은 이름의 blob 은 다시 쓰지 않는다(같은 내용 한 번).
    ///
    /// 이미 같은 id 의 항목이 있으면 담지 않고 blob 도 쓰지 않는다 — 어느 항목도 가리키지 않는 blob 을 남기지 않는다(설계 §2-7).
    /// - Parameter candidate: 항목과 그 blob.
    /// - Throws: blob 을 쓰지 못하면 그 오류. 부작용: 파일 쓰기.
    mutating func add(_ candidate: BackupExportCandidate) throws {
        guard !itemIDs.contains(candidate.item.id) else {
            Log.error("백업 — 같은 id 의 항목이 이미 있어 하나만 담는다")
            return
        }
        for blob in candidate.blobs where blobs[blob.entry.name] == nil {
            try blob.bytes.write(to: blobDirectory.appendingPathComponent(blob.entry.name, isDirectory: false), options: [.withoutOverwriting])
            blobs[blob.entry.name] = blob.entry
        }
        itemIDs.insert(candidate.item.id)
        items.append(candidate.item)
    }

    /// 모은 항목 · blob 으로 manifest 를 만들고 `manifest.json` · `items.json` 을 백업 인코더(키 정렬 · 2001 기준 초)로 쓴다.
    /// - Parameters:
    ///   - backupID: 이 백업의 UUID 문자열.
    ///   - createdAt: 만든 시각.
    ///   - appVersion: 만든 앱 버전.
    /// - Returns: 쓴 manifest — 재검증이 파일에서 다시 읽은 것과 견준다.
    /// - Throws: 인코딩 · 쓰기 실패. 부작용: 파일 쓰기.
    func finish(backupID: String, createdAt: Date, appVersion: String) throws -> BackupManifest {
        let rows = items.filter { $0.kind == .row }.count
        let entries = blobs.values.sorted { $0.name < $1.name }
        let manifest = BackupManifest(
            backupID: backupID,
            createdAt: createdAt,
            appVersion: appVersion,
            scope: BackupScope(rows: true, drafts: true),
            counts: BackupCounts(rows: rows, drafts: items.count - rows, blobs: entries.count),
            blobs: entries
        )
        try BackupFormat.encoder.encode(manifest)
            .write(to: directory.appendingPathComponent(BackupFormat.manifestFileName, isDirectory: false), options: [.withoutOverwriting])
        try BackupFormat.encoder.encode(items)
            .write(to: directory.appendingPathComponent(BackupFormat.itemsFileName, isDirectory: false), options: [.withoutOverwriting])
        return manifest
    }
}

/// 다 쓴 백업 파일을 같은 암호로 다시 열어 대조한다 — 맞을 때만 내보내기가 성공이다 (설계 §3-1 6단계 · 정책 §6-1 3).
enum BackupExportVerification {
    /// 파일을 `scratch` 에 풀고 형식 검증(`BackupPayload.load` — counts · blob 크기 · SHA-256 · 내용 지문 · 항목이 가리키는 blob)을 거친 뒤,
    /// 풀린 manifest · 항목이 쓴 것과 **같은지** 견준다. 맞으면 풀린 평문을 곧바로 지운다.
    /// - Parameters:
    ///   - file: 다 쓴 백업 파일.
    ///   - password: 쓸 때의 암호.
    ///   - manifest: 쓴 manifest.
    ///   - items: 쓴 항목.
    ///   - scratch: 풀 곳(작업 폴더 안). 맞으면 지운다 — 어긋나면 부르는 쪽이 작업 폴더째 지운다.
    ///   - limits: 상한 — 불러오기와 같은 값으로 푼다(불러올 수 없는 파일을 성공으로 내놓지 않는다).
    /// - Throws: 어긋나면 `BackupExportError.verificationFailed`, 풀 공간이 모자라면 `.insufficientSpace`, 취소면 `CancellationError`.
    ///   부작용: `scratch` 에 풀고 지운다.
    static func verify(
        file: URL,
        password: String,
        manifest: BackupManifest,
        items: [BackupItem],
        scratch: URL,
        limits: BackupLimits
    ) throws {
        let root: URL
        do {
            root = try BackupArchive.read(
                from: file,
                password: password,
                into: scratch,
                maxEntryBytes: limits.archiveEntryLimit,
                maxTotalBytes: limits.maxTotalBytes,
                maxEntryCount: 2 * limits.maxItems + 2
            )
        } catch let error as CancellationError {
            throw error
        } catch BackupArchiveError.insufficientSpace {
            throw BackupExportError.insufficientSpace
        } catch {
            Log.error("백업 — 다 쓴 파일을 다시 풀지 못했다", "\(error)")
            throw BackupExportError.verificationFailed
        }
        let payload: BackupPayload
        do {
            payload = try BackupPayload.load(rootDirectory: root, limits: limits)
        } catch {
            Log.error("백업 — 다 쓴 파일의 형식 검증이 맞지 않는다", "\(error)")
            throw BackupExportError.verificationFailed
        }
        guard payload.manifest == manifest else {
            Log.error("백업 — 다 쓴 파일의 manifest 가 쓴 것과 다르다")
            throw BackupExportError.verificationFailed
        }
        guard payload.items == items else {
            Log.error("백업 — 다 쓴 파일의 항목이 쓴 것과 다르다", "쓴 수=\(items.count)", "읽은 수=\(payload.items.count)")
            throw BackupExportError.verificationFailed
        }
        try FileManager.default.removeItem(at: scratch)
    }
}
