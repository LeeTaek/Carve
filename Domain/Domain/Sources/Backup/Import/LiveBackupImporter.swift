//
//  LiveBackupImporter.swift
//  Domain
//
//  Created by Claude on 10/6/26.
//  Copyright © 2026 leetaek. All rights reserved.
//
//  「백업 불러오기」 의 구현 — 검사 · 미리보기 · 이어 하기 (설계 docs/backup-import-design.md §4-1 · §4-2 · §6). 적용은 LiveBackupImporter+Apply.swift.
//

import CarveToolkit
import Foundation

/// 필사 백업 불러오기 (`BackupImporting`).
///
/// **검사** — 지금 환경으로 대상 계정 범위를 정하고 → 고른 파일을 작업 기록 폴더로 복사(암호화 사본)하고 → 평문 작업 폴더(`BackupWorkDirectory`)에
/// 풀어(`BackupArchive.read` — 상한은 `BackupLimits`) → 디코딩 · 검증(`BackupPayload.load` — 형식 1 · 2)하고 → 항목마다 지원 판정 → 필사책 안의
/// 장마다 저장소 행(`backupRows(page:)`)과 판정기로 미리보기를 만든다. 저장소는 바꾸지 않는다. 형식 1 파일은 전부 기본 필사책이다.
///
/// **적용** — 필사책 목록을 먼저 쓰고, 장마다 최신 환경 · 쓰기 게이트 · 대상 계정을 다시 보고 `DrawingBackupRestoring` 으로 한 트랜잭션씩 쓴다
/// (LiveBackupImporter+Apply.swift).
///
/// 평문은 작업 폴더에만 있고 적용이 끝나거나(성공 · 멈춤 · 실패) `discard` 하면 지운다. 앱 시작의 `BackupWorkDirectory.removeStale()` 이 남은 것을 지운다.
/// 암호는 어디에도 남기지 않는다 — 이어 할 때 다시 받는다.
public struct LiveBackupImporter: BackupImporting {
    /// 검사 · 장마다 다시 읽는 편집 환경.
    let environment: any DrawingEditEnvironmentClient
    /// 장 단위 복원 쓰기 — `database` 와 같은 actor 로 만든 것이어야 세대가 뜻을 가진다.
    let restorer: any DrawingBackupRestoring
    /// 미리보기의 백업 전용 조회 · 적용 시작 때의 세대를 읽는 저장소 actor.
    let database: SwiftDatabaseActor
    /// 장을 쓴 뒤 열린 필사 화면에 알리는 길.
    let changes: any LocalDrawingChangeClient
    /// 작업 기록(암호화 사본 · `job.json`).
    let jobs: BackupImportJobStore
    /// 평문 작업 폴더의 부모 — 앱은 `BackupWorkDirectory.rootURL`, 시험은 시험마다 따로 둔다.
    let workRoot: URL
    /// 상한.
    let limits: BackupLimits
    /// 지금 시각 — 작업 기록 · `LocalDrawingChange` 의 시각.
    let now: @Sendable () -> Date

    /// - Parameters:
    ///   - environment: 편집 환경(앱의 `LiveDrawingEditEnvironment`).
    ///   - restorer: 장 단위 복원 쓰기(`SwiftDataDrawingBackupRestorer` — `database` 와 같은 actor).
    ///   - database: 이 실행의 저장소 actor(편집 화면 · 「모든 필사 삭제」 와 같은 인스턴스).
    ///   - changes: 이 기기의 필사 변경 알림(앱의 `LiveLocalDrawingChangeClient` 인스턴스).
    ///   - jobs: 작업 기록 저장소. 기본은 `Application Support/BackupImport`.
    ///   - now: 지금 시각.
    public init(
        environment: any DrawingEditEnvironmentClient,
        restorer: any DrawingBackupRestoring,
        database: SwiftDatabaseActor,
        changes: any LocalDrawingChangeClient,
        jobs: BackupImportJobStore = BackupImportJobStore(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.init(
            environment: environment,
            restorer: restorer,
            database: database,
            changes: changes,
            jobs: jobs,
            workRoot: BackupWorkDirectory.rootURL,
            limits: .default,
            now: now
        )
    }

    /// 작업 폴더의 부모 · 상한까지 정한다 — 시험이 쓴다(실제 `BackupWork` 를 건드리지 않는다).
    init(
        environment: any DrawingEditEnvironmentClient,
        restorer: any DrawingBackupRestoring,
        database: SwiftDatabaseActor,
        changes: any LocalDrawingChangeClient,
        jobs: BackupImportJobStore,
        workRoot: URL,
        limits: BackupLimits,
        now: @escaping @Sendable () -> Date
    ) {
        self.environment = environment
        self.restorer = restorer
        self.database = database
        self.changes = changes
        self.jobs = jobs
        self.workRoot = workRoot
        self.limits = limits
        self.now = now
    }

    // MARK: - 검사

    /// 고른 파일을 검사한다 — 흐름은 타입 주석.
    /// - Parameters:
    ///   - fileURL: 사용자가 고른 파일(보안 범위 접근은 부르는 쪽이 연다). 복사만 하고 크기 · 시각을 읽지 않는다.
    ///   - password: 사용자 암호 원문.
    /// - Returns: 검사 결과(새 작업 id · 대상 계정 · 미리보기 · 평문 작업 폴더).
    /// - Throws: `BackupImportError` · `CancellationError`. 부작용: 작업 기록 폴더 · 평문 작업 폴더 쓰기 — 실패하면 둘 다 지운다.
    public func inspect(fileURL: URL, password: String) async throws -> BackupInspection {
        let current = await environment.current()
        let startedAt = now()
        var record = BackupImportJobRecord(
            jobID: UUID().uuidString,
            targetScope: Self.targetScope(for: current),
            status: .inspected,
            doneChapters: [],
            tally: BackupImportTally(),
            totalChapters: 0,
            createdAt: startedAt,
            updatedAt: startedAt
        )
        do {
            try jobs.create(record, copying: fileURL)
        } catch {
            Log.error("불러오기 — 고른 파일을 작업 영역으로 복사하지 못했다", "\(error)")
            throw Self.isOutOfSpace(error) ? BackupImportError.insufficientSpace : BackupImportError.fileUnreadable
        }
        do {
            let inspection = try await examine(record, password: password, environment: current)
            record.totalChapters = inspection.preview.chapters.count
            record.updatedAt = now()
            persist(record)
            Log.info("불러오기 — 검사를 마쳤다", "장=\(record.totalChapters)", "항목=\(inspection.preview.itemCount)")
            return inspection
        } catch {
            jobs.remove(record.jobID)
            throw error
        }
    }

    /// 작업의 암호화 사본을 평문 작업 폴더에 풀어 검증하고 미리보기를 만든다 — 검사 · 이어 하기가 함께 쓴다.
    /// - Parameters:
    ///   - record: 작업 기록(대상 계정 · 끝난 장).
    ///   - password: 사용자 암호 원문.
    ///   - current: 지금 환경 — 쓰기 게이트 사유를 담는다.
    /// - Returns: 검사 결과.
    /// - Throws: `BackupImportError` · `CancellationError`. 부작용: 평문 작업 폴더 쓰기 — 실패하면 지운다(작업 기록은 그대로).
    func examine(_ record: BackupImportJobRecord, password: String, environment current: DrawingEditEnvironment) async throws -> BackupInspection {
        guard let archive = jobs.archiveURL(for: record.jobID) else { throw BackupImportError.jobNotFound }
        let work: BackupWorkDirectory
        do {
            work = try BackupWorkDirectory.make(under: workRoot)
        } catch {
            throw BackupImportError.ioFailed
        }
        do {
            let unpacked = try BackupArchive.read(
                from: archive,
                password: password,
                into: work.url,
                maxEntryBytes: limits.archiveEntryLimit,
                maxTotalBytes: limits.maxTotalBytes,
                maxEntryCount: 2 * limits.maxItems + 2
            )
            let payload = try BackupPayload.load(rootDirectory: unpacked, limits: limits)
            let preview = try await preview(of: payload)
            return BackupInspection(
                jobID: record.jobID,
                targetScope: record.targetScope,
                writeBlock: SyncedWriteBlock.check(current),
                preview: preview,
                manifest: payload.manifest,
                doneChapters: BackupImportPlanner.ordered(record.doneChapters),
                workDirectory: work,
                payload: payload
            )
        } catch {
            work.remove()
            throw Self.reported(error)
        }
    }

    /// 미리보기 — 항목마다 지원 판정(blob 파일로 메타데이터를 푼다)을 하고, 필사책 안의 장마다 지금 저장소 행과 판정기로 결정별 수를 모은다.
    ///
    /// 장 하나씩 읽고 놓는다 — 저장소 전체의 바이트를 한꺼번에 들지 않는다. 결과는 `BackupImportPlanner.preview` 와 같다
    /// (파일 수준 수 — 놓을 수 없는 항목 · 알 수 없는 필사책 · 필사책 수 — 는 `BackupImportPlanner.filePreview`).
    /// - Throws: 저장소를 읽지 못하면 `storeUnreadable`, 취소면 `CancellationError`. 부작용 없음(읽기만 한다).
    func preview(of payload: BackupPayload) async throws -> BackupImportPreview {
        var unsupported: [String: BackupUnsupportedReason] = [:]
        for item in payload.items {
            if let reason = BackupItemSupport.reason(item, blobDirectory: payload.blobDirectory) {
                unsupported[item.id] = reason
            }
        }
        var preview = BackupImportPlanner.filePreview(items: payload.items, unsupported: unsupported, notebooks: payload.manifest.notebooks)
        let grouped = BackupImportPlanner.itemsByPage(payload.items)
        for page in BackupImportPlanner.ordered(Array(grouped.keys)) {
            try Task.checkCancellation()
            let load: BackupRowLoad
            do {
                load = try await database.backupRows(page: page)
            } catch {
                Log.error("불러오기 — 미리보기에서 이 장의 필사 행을 읽지 못했다", Self.label(page), "\(error)")
                throw BackupImportError.storeUnreadable
            }
            preview.add(BackupImportPlanner.plan(items: grouped[page] ?? [], unsupported: unsupported, current: load.rows, page: page))
        }
        return preview
    }

    /// 로그에 남길 장 이름 — 저장소 행의 `titleName`(필사책 접두 포함)과 장 번호.
    static func label(_ page: NotebookChapter) -> String {
        "\(StoredBookKey.titleName(for: page)).\(page.chapter.chapter)"
    }

    // MARK: - 닫기 · 이어 하기

    /// 검사 결과를 닫는다 — 평문 작업 폴더를 지우고, 적용을 시작하지 않은 작업이면 작업 기록 · 암호화 사본도 지운다.
    /// - 부작용: 파일 삭제. 적용을 시작한 작업의 기록은 남긴다(이어 하기).
    public func discard(_ inspection: BackupInspection) async {
        if let work = inspection.workDirectory {
            removeWorkDirectory(work)
        }
        if let record = jobs.load(inspection.jobID), !record.isPending {
            jobs.remove(record.jobID)
        }
    }

    /// 끝나지 않은 작업 중 가장 최근 것 — 지금 환경의 계정 범위와 견줘 이어 할 수 있는지를 담는다.
    /// - Returns: 작업. 적용을 시작한 끝나지 않은 작업이 없으면 nil. 부작용 없음.
    public func pendingJob() async -> BackupImportJob? {
        let pending = jobs.records().filter(\.isPending)
        guard let record = pending.max(by: { ($0.updatedAt, $0.jobID) < ($1.updatedAt, $1.jobID) }) else { return nil }
        return Self.job(from: record, environment: await environment.current())
    }

    /// 끝나지 않은 작업을 잇는다 — 지금 계정이 그 작업의 대상 계정일 때만 암호화 사본을 다시 검사한다(같은 작업 id · 끝난 장 유지).
    /// - Throws: `jobNotFound` · `jobFromOtherAccount`, 그 밖은 검사와 같다. 실패해도 작업 기록은 남는다.
    public func resume(_ job: BackupImportJob, password: String) async throws -> BackupInspection {
        guard let record = jobs.load(job.jobID) else { throw BackupImportError.jobNotFound }
        let current = await environment.current()
        guard let target = record.targetScope, target == Self.targetScope(for: current) else {
            Log.error("불러오기 — 다른 계정에서 시작한 작업은 잇지 않는다")
            throw BackupImportError.jobFromOtherAccount
        }
        return try await examine(record, password: password, environment: current)
    }

    /// 끝나지 않은 작업의 암호화 사본으로 지금 계정의 새 작업을 시작한다 — 새 검사가 되면 옛 작업을 지운다.
    /// - Throws: `jobNotFound`, 그 밖은 검사와 같다. 실패하면 옛 작업은 그대로다.
    public func restart(_ job: BackupImportJob, password: String) async throws -> BackupInspection {
        guard jobs.load(job.jobID) != nil, let archive = jobs.archiveURL(for: job.jobID) else { throw BackupImportError.jobNotFound }
        let inspection = try await inspect(fileURL: archive, password: password)
        jobs.remove(job.jobID)
        return inspection
    }

    /// 끝나지 않은 작업을 버린다 — 작업 기록과 암호화 사본을 지운다. 이미 넣은 행은 그대로다.
    public func discard(_ job: BackupImportJob) async {
        jobs.remove(job.jobID)
    }

    // MARK: - 규칙

    /// 대상 계정 범위 — 계정이 확인됐고 저장소 소유가 그 계정이며 쓰기 게이트가 열려 있을 때만 그 계정, 아니면 nil(미리보기만).
    /// - Parameter environment: 판정할 환경.
    /// - Returns: 계정 범위. 부작용 없음.
    static func targetScope(for environment: DrawingEditEnvironment) -> AccountScope? {
        guard case .confirmed(let scope) = environment.accountState,
              environment.storeOwnership == scope,
              SyncedWriteBlock.check(environment) == nil else { return nil }
        return scope
    }

    /// 작업 기록과 지금 환경으로 밖에 내놓을 작업을 만든다 — 지금 계정 범위가 대상 계정과 같을 때만 이어 할 수 있다.
    static func job(from record: BackupImportJobRecord, environment: DrawingEditEnvironment) -> BackupImportJob {
        let currentScope = targetScope(for: environment)
        return BackupImportJob(
            jobID: record.jobID,
            targetScope: record.targetScope,
            doneChapters: BackupImportPlanner.ordered(record.doneChapters),
            totalChapters: record.totalChapters,
            tally: record.tally,
            updatedAt: record.updatedAt,
            canResume: record.targetScope != nil && record.targetScope == currentScope,
            writeBlock: SyncedWriteBlock.check(environment)
        )
    }

    // MARK: - 정리 · 오류

    /// 작업 기록을 쓴다 — 실패해도 불러오기는 계속한다(이어 하기가 그 장을 다시 판정할 뿐 — 같은 지문은 `skipSame`).
    func persist(_ record: BackupImportJobRecord) {
        do {
            try jobs.save(record)
        } catch {
            Log.error("불러오기 — 작업 기록을 쓰지 못했다", "\(error)")
        }
    }

    /// 평문 작업 폴더를 지운다 — 이 불러오기의 작업 폴더 부모(`workRoot`) 바로 아래의 UUID 폴더일 때만.
    func removeWorkDirectory(_ work: BackupWorkDirectory) {
        let parent = work.url.deletingLastPathComponent().resolvingSymlinksInPath().path
        guard UUID(uuidString: work.url.lastPathComponent) != nil, parent == workRoot.resolvingSymlinksInPath().path else {
            Log.error("불러오기 — 작업 폴더 밖은 지우지 않는다")
            return
        }
        work.remove()
    }

    /// 검사 오류를 알릴 오류로 바꾼다 — 잘못된 암호 · 변조 · 잘림 · 허용 밖 항목 · 형식 검증 실패는 같은 「파일 거부」 다.
    static func reported(_ error: any Error) -> any Error {
        switch error {
        case is CancellationError, is BackupImportError:
            return error
        case let archive as BackupArchiveError:
            switch archive {
            case .wrongPasswordOrDamaged, .entryRejected: return BackupImportError.wrongPasswordOrDamaged
            case .tooLarge: return BackupImportError.tooLarge
            case .insufficientSpace: return BackupImportError.insufficientSpace
            case .ioFailed: return BackupImportError.ioFailed
            }
        case let format as BackupFormatError:
            switch format {
            case .unsupportedFormat(let version): return BackupImportError.unsupportedFormat(formatVersion: version)
            case .limitExceeded: return BackupImportError.tooLarge
            default: return BackupImportError.wrongPasswordOrDamaged
            }
        default:
            return BackupImportError.ioFailed
        }
    }

    /// 파일 쓰기의 공간 부족(`NSFileWriteOutOfSpaceError` · `ENOSPC`)인가.
    static func isOutOfSpace(_ error: any Error) -> Bool {
        if let cocoa = error as? CocoaError, cocoa.code == .fileWriteOutOfSpace { return true }
        let nsError = error as NSError
        return nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOSPC)
    }
}
