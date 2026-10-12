//
//  LiveBackupExporter.swift
//  Domain
//
//  「백업 만들기」 의 구현 — 장마다 저장소 행 원본과 열 수 있는 초안을 읽어 평문 준비 폴더에 모으고, 암호화 파일 하나로 쓴 뒤 다시 열어 대조한다
//  (설계 docs/backup-import-design.md §3-2 · 정책 §6-1).
//

import CarveToolkit
import ClientInterfaces
import Dependencies
import Foundation

/// 필사 백업 내보내기 (`BackupExporting`).
///
/// 1. 시작할 때 환경(`DrawingEditEnvironmentClient.current()`)의 **계정 상태 · 저장소 소유 · 여는 초안 묶음**(`readableDraftScopes ∪
///    beforeConnectionDraftScopes`)을 적어 둔다.
/// 2. 장 목록 = 행이 있는 장(`backupChapterList` — 그때의 저장소 세대와 함께) ∪ 여는 묶음에 초안이 있는 장(`draftSummary(in:).chapters`)을
///    **권 · 장 자리**로 줄인 것(`BibleChapter.backupPlaces`) — 같은 권 · 장이 번역본별로 여러 번 와도 한 번이다.
/// 3. 자리마다: 환경을 다시 읽어 1 과 다르면 `accountChanged` → 번역본마다(`Translation.allCases` — 그 번역본의 장):
///    `backupRows(chapter:)` 의 세대가 장 목록 때와 다르면 `generationChanged` → 그 장의 초안을 「확인이 필요한 필기」 와 같은 규칙으로 고른다
///    (`BackupExportDraftSelection` — 그 번역본 초안만 읽는다) → 항목 · blob 을 준비 폴더에 쓴다. 자리를 마치면 진행.
///    번역본마다 따로 읽으므로 초안 요약이 장을 번역본별로 나누든(KJV 초안이 KJV 장으로 오든) 아니든 같은 초안을 한 번씩만 담는다.
/// 4. manifest · items 를 쓰고 `BackupArchive.write` 로 암호화 파일을 만든 뒤 평문 준비 폴더를 지운다.
/// 5. 그 파일을 같은 암호 · 같은 상한으로 다시 풀어 대조한다(`BackupExportVerification`). 맞을 때만 성공이다.
///
/// 일관성은 **장 단위**다 — 한 장은 한 actor 구간에서 읽으므로 한 행의 잉크와 메타데이터가 다른 시점에서 섞이지 않는다. 메모리에는 장 하나 분량의
/// 바이트만 든다. 평문은 작업 폴더(`BackupWorkDirectory`) 안에만 있고, 실패 · 취소면 작업 폴더째 지운다. 암호는 어디에도 남기지 않는다.
public struct LiveBackupExporter: BackupExporting {
    /// 장마다 다시 읽는 편집 환경.
    private let environment: any DrawingEditEnvironmentClient
    /// 초안 읽기(`LocalPreservationWriter`).
    private let drafts: any VerseDraftRecoveryReading
    /// 백업 전용 조회를 하는 저장소 actor — 「모든 필사 삭제」 와 같은 인스턴스여야 세대가 뜻을 가진다.
    private let database: SwiftDatabaseActor
    /// manifest 의 `appVersion`.
    private let appVersion: String
    /// 작업 폴더의 부모 — 앱은 `BackupWorkDirectory.rootURL`, 시험은 시험마다 따로 둔다.
    private let workRoot: URL
    /// 상한 — 재검증도 불러오기와 같은 값으로 푼다.
    private let limits: BackupLimits
    /// 지금 시각 — manifest 의 `createdAt` 과 기본 파일 이름의 날짜.
    private let now: @Sendable () -> Date

    /// - Parameters:
    ///   - environment: 편집 환경(앱의 `LiveDrawingEditEnvironment`).
    ///   - drafts: 초안 읽기 — 앱의 `LocalPreservationWriter`.
    ///   - database: 이 실행의 저장소 actor(편집 화면 · 「모든 필사 삭제」 와 같은 인스턴스).
    ///   - appVersion: 만든 앱 버전. nil 이면 `@Dependency(\.appVersion)`.
    ///   - now: 지금 시각.
    public init(
        environment: any DrawingEditEnvironmentClient,
        drafts: any VerseDraftRecoveryReading,
        database: SwiftDatabaseActor,
        appVersion: String? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.init(
            environment: environment,
            drafts: drafts,
            database: database,
            appVersion: appVersion,
            workRoot: BackupWorkDirectory.rootURL,
            limits: .default,
            now: now
        )
    }

    /// 작업 폴더의 부모 · 상한까지 정한다 — 시험이 쓴다(실제 `BackupWork` 를 건드리지 않는다).
    init(
        environment: any DrawingEditEnvironmentClient,
        drafts: any VerseDraftRecoveryReading,
        database: SwiftDatabaseActor,
        appVersion: String?,
        workRoot: URL,
        limits: BackupLimits,
        now: @escaping @Sendable () -> Date
    ) {
        self.environment = environment
        self.drafts = drafts
        self.database = database
        if let appVersion {
            self.appVersion = appVersion
        } else {
            @Dependency(\.appVersion) var current
            self.appVersion = current
        }
        self.workRoot = workRoot
        self.limits = limits
        self.now = now
    }

    public func export(password: String, progress: @Sendable (BackupProgress) async -> Void) async throws -> BackupExportResult {
        try await export(password: password, fileName: nil, progress: progress)
    }

    /// 백업 파일을 만든다 — 흐름은 타입 주석.
    /// - Parameters:
    ///   - password: 사용자 암호 원문. `BackupArchive` 에 넘기기만 한다.
    ///   - fileName: 파일 이름. nil 이거나 쓸 수 없으면 기본 이름(만든 날짜).
    ///   - progress: 장 단위 진행.
    /// - Returns: 다시 열어 대조까지 마친 파일(작업 폴더 안 — 저장 위치를 고른 뒤 `discard` 로 지운다).
    /// - Throws: `BackupExportError` · `CancellationError`. 부작용: 작업 폴더에 쓰기. 실패 · 취소면 작업 폴더를 지운다.
    public func export(
        password: String,
        fileName: String?,
        progress: @Sendable (BackupProgress) async -> Void
    ) async throws -> BackupExportResult {
        let startedAt = now()
        let name = BackupExportFileName.sanitized(fileName) ?? BackupExportFileName.defaultName(for: startedAt)
        let work: BackupWorkDirectory
        do {
            work = try BackupWorkDirectory.make(under: workRoot)
        } catch {
            throw BackupExportError.writeFailed
        }
        do {
            var staging = try BackupExportStaging(directory: work.url.appendingPathComponent("staged", isDirectory: true))
            try await collect(into: &staging, progress: progress)
            let manifest = try staging.finish(backupID: UUID().uuidString, createdAt: startedAt, appVersion: appVersion)
            let file = work.url.appendingPathComponent(name, isDirectory: false)
            try BackupArchive.write(stagedDirectory: staging.directory, to: file, password: password)
            // 평문 준비 폴더는 암호화 파일을 쓰자마자 지운다.
            try FileManager.default.removeItem(at: staging.directory)
            try BackupExportVerification.verify(
                file: file,
                password: password,
                manifest: manifest,
                items: staging.items,
                scratch: work.url.appendingPathComponent("verify", isDirectory: true),
                limits: limits
            )
            Log.info("백업 — 파일을 만들고 다시 열어 대조했다", "행=\(manifest.counts.rows)", "초안=\(manifest.counts.drafts)", "blob=\(manifest.counts.blobs)")
            return BackupExportResult(fileURL: file, counts: manifest.counts, backupID: manifest.backupID)
        } catch {
            work.remove()
            throw Self.reported(error)
        }
    }

    /// 내보낸 파일의 작업 폴더를 지운다 — 이 내보내기가 만든 작업 폴더(`<workRoot>/<UUID>/`) 안의 파일일 때만.
    /// - Parameter result: `export` 의 결과.
    /// - 부작용: 파일 삭제. 지우지 못하면 로그만 남긴다(다음 앱 시작의 `removeStale()` 이 지운다).
    public func discard(_ result: BackupExportResult) async {
        let folder = result.fileURL.deletingLastPathComponent()
        guard UUID(uuidString: folder.lastPathComponent) != nil,
              folder.deletingLastPathComponent().resolvingSymlinksInPath().path == workRoot.resolvingSymlinksInPath().path else {
            Log.error("백업 — 작업 폴더 밖의 파일은 지우지 않는다")
            return
        }
        BackupWorkDirectory(url: folder).remove()
    }

    // MARK: - 장 단위 읽기

    /// 장 목록을 정하고 권 · 장 자리마다 번역본별로 행 · 초안을 읽어 준비 폴더에 담는다(타입 주석 1 ~ 3).
    /// - 부작용: 준비 폴더에 blob 쓰기, 진행 알림(자리 단위).
    private func collect(into staging: inout BackupExportStaging, progress: @Sendable (BackupProgress) async -> Void) async throws {
        let basis = BackupExportEnvironmentBasis(await environment.current())
        let listed = try await chapters(opening: basis.draftScopes)
        await progress(BackupProgress(done: 0, total: listed.chapters.count))
        for (index, place) in listed.chapters.enumerated() {
            try Task.checkCancellation()
            let current = await environment.current()
            guard BackupExportEnvironmentBasis(current) == basis else {
                Log.error("백업 — 장 사이에 계정 상태 · 저장소 소유 · 여는 초안 묶음이 바뀌어 멈춘다", "\(place.title.rawValue).\(place.chapter)")
                throw BackupExportError.accountChanged
            }
            for chapter in place.backupTranslationChapters {
                try await stage(chapter, environment: current, generation: listed.generation, into: &staging)
            }
            await progress(BackupProgress(done: index + 1, total: listed.chapters.count))
        }
    }

    /// 번역본 장 하나의 행 · 초안을 읽어 준비 폴더에 담는다 — 행과 세대는 같은 actor 구간에서 읽는다(장 단위 일관성).
    /// - Parameters:
    ///   - chapter: 번역본 장.
    ///   - environment: 그 자리를 읽기 전에 다시 읽은 편집 환경.
    ///   - generation: 장 목록을 읽은 때의 저장소 세대.
    ///   - staging: 준비 폴더.
    /// - Throws: `storeUnreadable` · `generationChanged` · `draftsUnreadable` · 취소. 부작용: 준비 폴더에 blob 쓰기.
    private func stage(
        _ chapter: BibleChapter,
        environment current: DrawingEditEnvironment,
        generation: DrawingStoreGeneration,
        into staging: inout BackupExportStaging
    ) async throws {
        let label = "\(StoredBookKey.titleName(for: chapter)).\(chapter.chapter)"
        let load: BackupRowLoad
        do {
            load = try await database.backupRows(chapter: chapter)
        } catch {
            Log.error("백업 — 이 장의 필사 행을 읽지 못했다", label, "\(error)")
            throw BackupExportError.storeUnreadable
        }
        guard load.generation == generation else {
            Log.error("백업 — 장 사이에 저장소 세대가 바뀌어(모든 필사 삭제) 멈춘다", "목록 세대=\(generation.raw)", "지금 세대=\(load.generation.raw)")
            throw BackupExportError.generationChanged
        }
        let selected: [BackupExportDraft]
        do {
            selected = try await BackupExportDraftSelection.select(chapter: chapter, environment: current, rows: load.rows, reader: drafts)
        } catch let error as CancellationError {
            throw error
        } catch {
            Log.error("백업 — 이 장의 초안을 읽지 못해 멈춘다(조용히 빼지 않는다)", label, "\(error)")
            throw BackupExportError.draftsUnreadable
        }
        for candidate in BackupExportItems.candidates(chapter: chapter, rows: load.rows, drafts: selected) {
            try staging.add(candidate)
        }
    }

    /// 장 목록 — 행이 있는 장 ∪ 여는 묶음에 초안이 있는 장을 권 · 장 자리로 줄인 것(번역본은 개역개정으로 맞춘다), 권 → 장 순서.
    /// 세대는 행이 있는 장을 읽은 때의 것이다.
    /// - Parameter scopes: 여는 초안 묶음.
    /// - Throws: 저장소를 읽지 못하면 `storeUnreadable`, 묶음 요약을 읽지 못하면 `draftsUnreadable`.
    private func chapters(opening scopes: [AccountScope]) async throws -> (chapters: [BibleChapter], generation: DrawingStoreGeneration) {
        let stored: (chapters: [BibleChapter], generation: DrawingStoreGeneration)
        do {
            stored = try await database.backupChapterList()
        } catch {
            Log.error("백업 — 필사 행이 있는 장을 읽지 못했다", "\(error)")
            throw BackupExportError.storeUnreadable
        }
        var chapters = stored.chapters
        for scope in scopes {
            do {
                chapters += try await drafts.draftSummary(in: scope).chapters
            } catch {
                Log.error("백업 — 초안 묶음을 읽지 못했다", "\(error)")
                throw BackupExportError.draftsUnreadable
            }
        }
        return (BibleChapter.backupPlaces(chapters), stored.generation)
    }

    /// 사용자에게 알릴 오류 — 이미 정한 오류 · 취소는 그대로, 컨테이너 공간 부족은 `insufficientSpace`, 그 밖의 쓰기 실패는 `writeFailed`.
    static func reported(_ error: any Error) -> any Error {
        switch error {
        case is CancellationError, is BackupExportError:
            return error
        case let archive as BackupArchiveError:
            return archive == .insufficientSpace ? BackupExportError.insufficientSpace : BackupExportError.writeFailed
        default:
            return isOutOfSpace(error) ? BackupExportError.insufficientSpace : BackupExportError.writeFailed
        }
    }

    /// 파일 쓰기의 공간 부족(`NSFileWriteOutOfSpaceError` · `ENOSPC`)인가.
    private static func isOutOfSpace(_ error: any Error) -> Bool {
        if let cocoa = error as? CocoaError, cocoa.code == .fileWriteOutOfSpace { return true }
        let nsError = error as NSError
        return nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOSPC)
    }
}

/// 내보내기가 장마다 견주는 환경 — 계정 상태 · 저장소 소유 · 여는 초안 묶음. 이 셋이 시작 때와 같아야 한 파일에 한 계정의 초안만 든다.
struct BackupExportEnvironmentBasis: Equatable {
    /// 계정 상태.
    let accountState: AccountScopeState
    /// 저장소 소유 근거.
    let storeOwnership: AccountScope?
    /// 여는 초안 묶음 — 편집 화면이 읽는 묶음 ∪ 연결 전 묶음(겹치는 것은 한 번).
    let draftScopes: [AccountScope]

    init(_ environment: DrawingEditEnvironment) {
        accountState = environment.accountState
        storeOwnership = environment.storeOwnership
        var scopes: [AccountScope] = []
        for scope in environment.readableDraftScopes + environment.beforeConnectionDraftScopes where !scopes.contains(scope) {
            scopes.append(scope)
        }
        draftScopes = scopes
    }
}
