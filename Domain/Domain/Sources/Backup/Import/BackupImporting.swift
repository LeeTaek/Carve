//
//  BackupImporting.swift
//  Domain
//
//  Created by Claude on 10/6/26.
//  Copyright © 2026 leetaek. All rights reserved.
//
//  「백업 불러오기」 의 계약 — 검사 · 적용 · 이어 하기와 그 결과 · 오류 (설계 docs/backup-import-design.md §4 · §6).
//

import Dependencies
import Foundation

/// 필사 백업 파일(`.carvebackup`) 불러오기 (설계 §4 · 정책 §7-1).
///
/// - **검사 · 미리보기는 언제나 무료이고 저장소를 바꾸지 않는다.** 검사 때 지금 환경으로 대상 계정 범위(`targetScope`)를 정한다 — 계정이
///   확인됐고 저장소 소유가 그 계정이며 `SyncedWriteBlock.check == nil` 일 때만 그 계정, 아니면 nil(미리보기만).
/// - **적용은 장마다 최신 환경을 다시 읽어** 쓰기 게이트가 열려 있고 저장소 소유가 `targetScope` 와 같을 때만 그 장을 쓴다. 아니면 그 장부터
///   멈춘다(이미 쓴 장은 그대로). 구매 여부를 묻지 않는다.
/// - 고른 파일의 **암호화 사본**과 작업 기록(대상 계정 · 끝난 장 · 수)을 기기 안(`BackupImportJobStore`)에 남겨 멈춘 불러오기를 잇는다.
///   평문 · 암호는 남기지 않는다 — 이어 할 때 암호를 다시 받는다. 다른 계정에서 시작한 작업은 잇지 않는다(버리기 · 처음부터만).
public protocol BackupImporting: Sendable {
    /// 파일을 검사하고 미리보기를 만든다 — 저장소를 바꾸지 않는다.
    /// - Parameters:
    ///   - fileURL: 사용자가 고른 파일. 보안 범위 접근은 부르는 쪽이 열고 닫는다 — 이 안에서 앱 작업 영역으로 먼저 복사하고 사본만 읽는다.
    ///   - password: 사용자 암호 원문. `BackupArchive` 에 넘기기만 하고 저장 · 기록하지 않는다.
    /// - Returns: 검사 결과 — 작업 id · 대상 계정 · 미리보기 · 평문 작업 폴더. 다 쓰면 `discard(_:)` 로 닫는다.
    /// - Throws: `BackupImportError`, 취소면 `CancellationError`. 실패하면 평문 작업 폴더와 새 작업 기록을 지운다.
    func inspect(fileURL: URL, password: String) async throws -> BackupInspection

    /// 검사 결과를 장 단위로 적용한다(필사책 → 권 순서 → 장 순서, 작업 기록의 끝난 장은 건너뛴다). 필사책 목록(형식 2)은 장보다 먼저 쓴다.
    ///
    /// 적용을 시작하면 이 작업 밖의 끝나지 않은 작업 기록은 지운다 — 새 적용이 앞선 작업을 대신한다(작업 기록은 늘 하나다).
    /// - Parameters:
    ///   - inspection: `inspect` · `resume` · `restart` 의 결과.
    ///   - progress: 장 단위 진행. 시작할 때 한 번(이미 끝난 장 수), 장을 마칠 때마다 한 번 부른다.
    /// - Returns: 다 썼으면 `.completed`, 멈췄으면 그 사유와 끝난 장. 어느 쪽이든 평문 작업 폴더는 지운다 — 다시 적용하려면 암호를 다시 받는다.
    /// - Throws: 저장소를 읽거나 쓰지 못하면 `BackupImportError`, 취소면 `CancellationError` — 쓴 장은 그대로 두고 작업 기록을 남긴다.
    func apply(_ inspection: BackupInspection, progress: @Sendable (BackupProgress) async -> Void) async throws -> BackupImportReport

    /// 검사 결과를 닫는다 — 평문 작업 폴더를 지우고, **적용을 시작하지 않은** 작업이면 작업 기록 · 암호화 사본도 지운다.
    /// 적용을 시작한(끝나지 않은) 작업의 기록은 남는다 — 이어 하기(`pendingJob`)로 잇거나 `discard(_ job:)` 로 버린다.
    func discard(_ inspection: BackupInspection) async

    /// 끝나지 않은 불러오기(적용을 시작했는데 끝나지 않은 작업) — 가장 최근 것 하나. 없으면 nil.
    /// 지금 환경의 계정 범위가 그 작업의 대상 계정과 같을 때만 `canResume` 이다.
    func pendingJob() async -> BackupImportJob?

    /// 끝나지 않은 작업을 잇는다 — 암호화 사본을 다시 검사해 끝난 장을 든 검사 결과를 만든다(같은 작업 id).
    /// - Throws: 지금 계정이 그 작업의 대상 계정이 아니면 `jobFromOtherAccount`, 작업이 없으면 `jobNotFound`, 그 밖은 `inspect` 와 같다.
    ///   실패해도 작업 기록은 남는다.
    func resume(_ job: BackupImportJob, password: String) async throws -> BackupInspection

    /// 끝나지 않은 작업의 암호화 사본으로 **지금 계정의 새 작업**을 시작한다(「이 계정으로 처음부터」). 새 검사가 되면 옛 작업을 지운다.
    /// - Throws: 작업이 없으면 `jobNotFound`, 그 밖은 `inspect` 와 같다. 실패하면 옛 작업은 그대로다.
    func restart(_ job: BackupImportJob, password: String) async throws -> BackupInspection

    /// 끝나지 않은 작업을 버린다(「버리기」) — 작업 기록과 암호화 사본을 지운다. 이미 넣은 행은 그대로다.
    func discard(_ job: BackupImportJob) async
}

public extension BackupImporting {
    /// 기본 구현 — 이을 작업이 없다(시험 대역용). `LiveBackupImporter` 는 실제로 잇는다.
    func resume(_ job: BackupImportJob, password: String) async throws -> BackupInspection {
        throw BackupImportError.jobNotFound
    }

    /// 기본 구현 — 처음부터 할 작업이 없다(시험 대역용).
    func restart(_ job: BackupImportJob, password: String) async throws -> BackupInspection {
        throw BackupImportError.jobNotFound
    }

    /// 기본 구현 — 아무것도 하지 않는다(시험 대역용).
    func discard(_ job: BackupImportJob) async {}
}

/// 검사 결과 (설계 §4-1 4 ~ 7단계). 적용 · 닫기에 그대로 넘긴다.
public struct BackupInspection: Equatable, Sendable {
    /// 작업 id(UUID 문자열) — 기기 안 작업 기록(`BackupImportJobStore`)의 이름.
    public let jobID: String
    /// 대상 계정 범위 — 적용은 저장소 소유가 이 계정일 때만 쓴다. nil 이면 미리보기까지다.
    public let targetScope: AccountScope?
    /// 검사 때의 쓰기 게이트 사유 — `targetScope` 가 nil 인 까닭(적용 버튼 대신 보일 사유). 쓸 수 있으면 nil.
    public let writeBlock: SyncedWriteBlock?
    /// 미리보기 — 검사 시점의 수. 적용은 쓰기 직전 다시 판정하므로 실제 수와 다를 수 있다.
    public let preview: BackupImportPreview
    /// 파일의 manifest(만든 시각 · 앱 버전 · 수). 시험 대역이 만든 검사 결과면 nil.
    public let manifest: BackupManifest?
    /// 작업 기록에 이미 끝난 장(필사책 · 번역본 포함) — 이어 하기면 적용이 건너뛴다.
    public let doneChapters: [NotebookChapter]
    /// 평문 작업 폴더(`BackupWork/<UUID>/`) — 적용이 끝나거나 `discard` 하면 지운다.
    public let workDirectory: BackupWorkDirectory?
    /// 검증을 마친 풀린 백업 — 적용이 장마다 항목 · blob 을 읽는다.
    let payload: BackupPayload?

    /// 검사 결과를 만든다 — 시험 대역용(풀린 백업 없이). `LiveBackupImporter.apply` 는 이 값으로 적용하지 않는다(`inspectionExpired`).
    public init(
        jobID: String,
        targetScope: AccountScope?,
        writeBlock: SyncedWriteBlock? = nil,
        preview: BackupImportPreview,
        manifest: BackupManifest? = nil,
        doneChapters: [NotebookChapter] = [],
        workDirectory: BackupWorkDirectory? = nil
    ) {
        self.init(
            jobID: jobID,
            targetScope: targetScope,
            writeBlock: writeBlock,
            preview: preview,
            manifest: manifest,
            doneChapters: doneChapters,
            workDirectory: workDirectory,
            payload: nil
        )
    }

    /// 검사 결과를 만든다 — 풀린 백업까지.
    init(
        jobID: String,
        targetScope: AccountScope?,
        writeBlock: SyncedWriteBlock?,
        preview: BackupImportPreview,
        manifest: BackupManifest?,
        doneChapters: [NotebookChapter],
        workDirectory: BackupWorkDirectory?,
        payload: BackupPayload?
    ) {
        self.jobID = jobID
        self.targetScope = targetScope
        self.writeBlock = writeBlock
        self.preview = preview
        self.manifest = manifest
        self.doneChapters = doneChapters
        self.workDirectory = workDirectory
        self.payload = payload
    }

    /// 적용할 수 있는가 — 대상 계정이 있을 때만. 적용 중 환경이 바뀌면 그래도 멈출 수 있다.
    public var canApply: Bool { targetScope != nil }
}

/// 적용의 결과 (설계 §4-1 9단계). 멈춰도 이미 쓴 장은 그대로다 — 이미 동기화됐을 수 있어 되돌리지 않는다.
///
/// `doneChapters` 는 이 작업에서 끝난 장 전부(이어 한 앞 실행 포함, 필사책 → 권 → 장 순서), `tally` 는 그 장들의 실제 결정 수다.
public enum BackupImportReport: Equatable, Sendable {
    /// 모든 장을 썼다. 작업 기록 · 암호화 사본을 지웠다.
    case completed(BackupImportTally)
    /// 쓰기 게이트가 막혀 그 장부터 멈췄다(로그아웃 · 계정 확인 중 · 소유 근거 없음 · 연결 보류 등).
    case blocked(SyncedWriteBlock, doneChapters: [NotebookChapter], tally: BackupImportTally)
    /// 저장소 소유가 대상 계정과 달라졌거나 서버 작업 표가 무효가 돼 멈췄다 — 다른 계정의 저장소에 잇지 않는다.
    case accountChanged(doneChapters: [NotebookChapter], tally: BackupImportTally)
    /// 적용 중 「모든 필사 삭제」 로 저장소 세대가 바뀌어 멈췄다. 앞서 쓴 장도 지워졌으므로 끝난 장은 비운다.
    case generationChanged(doneChapters: [NotebookChapter], tally: BackupImportTally)

    /// 끝난 장들의 실제 결정 수.
    public var tally: BackupImportTally {
        switch self {
        case .completed(let tally): tally
        case .blocked(_, _, let tally), .accountChanged(_, let tally), .generationChanged(_, let tally): tally
        }
    }
}

/// 적용한 장들의 **실제** 결정 수 — 쓰기 직전 다시 판정한 것이라 미리보기 수와 다를 수 있다. 기기 안 작업 기록(`job.json`)에도 남는다.
public struct BackupImportTally: Codable, Equatable, Sendable {
    /// 그 절의 현재 필사로 넣은 수(`insertCurrent` — 비운 현재 행 포함).
    public var new: Int
    /// 같은 내용이 있어 건너뛴 수(`skipSame`).
    public var same: Int
    /// 이전 필사 기록으로 넣은 수(`insertArchived`).
    public var archived: Int
    /// 이 기기에서 뒤에 지운 절이라 기록으로만 넣은 수(`protectCleared`).
    public var protectedCleared: Int
    /// 비운 항목이라 넣지 않은 수(`skipEmpty`).
    public var skippedEmpty: Int
    /// 적용한 장 안에서 해석할 수 없어 건너뛴 수. 어느 장에도 놓을 수 없는 항목은 세지 않는다 — 그 수는 미리보기에 있다.
    public var unsupported: Int
    /// 대표를 고정한 지금 행 수(`isPresent` 만 true 로 — 미리보기 수에는 들지 않는다).
    public var pinned: Int

    /// 수를 만든다(기본은 0).
    public init(
        new: Int = 0,
        same: Int = 0,
        archived: Int = 0,
        protectedCleared: Int = 0,
        skippedEmpty: Int = 0,
        unsupported: Int = 0,
        pinned: Int = 0
    ) {
        self.new = new
        self.same = same
        self.archived = archived
        self.protectedCleared = protectedCleared
        self.skippedEmpty = skippedEmpty
        self.unsupported = unsupported
        self.pinned = pinned
    }

    /// 새로 넣은 행 수 — 현재 · 보관 · 지운 절 보호.
    public var insertCount: Int { new + archived + protectedCleared }

    /// 장 하나의 결과를 더한다. 부작용 없음(값만 바꾼다).
    public mutating func add(_ outcome: BackupChapterRestoreOutcome) {
        for entry in outcome.decisions {
            switch entry.decision {
            case .insertCurrent: new += 1
            case .skipSame: same += 1
            case .insertArchived: archived += 1
            case .protectCleared: protectedCleared += 1
            case .skipEmpty: skippedEmpty += 1
            case .unsupported: unsupported += 1
            }
        }
        pinned += outcome.pins.count
    }
}

/// 끝나지 않은 불러오기 하나 (설계 §6-3) — 기기 안 작업 기록과, 지금 환경에서 이어 할 수 있는지.
public struct BackupImportJob: Equatable, Sendable {
    /// 작업 id(UUID 문자열).
    public let jobID: String
    /// 그 작업의 대상 계정 범위. nil 이면 미리보기만 하던 작업이다.
    public let targetScope: AccountScope?
    /// 끝난 장(필사책 → 권 → 장 순서).
    public let doneChapters: [NotebookChapter]
    /// 적용할 장 수(지원 항목이 있는 장).
    public let totalChapters: Int
    /// 끝난 장들의 실제 결정 수.
    public let tally: BackupImportTally
    /// 마지막으로 기록한 시각.
    public let updatedAt: Date
    /// 지금 환경의 계정 범위가 대상 계정과 같은가 — 그때만 「이어서 불러오기」(암호를 다시 받는다). 아니면 「버리기」 · 「이 계정으로 처음부터」 만.
    public let canResume: Bool
    /// 지금 환경의 쓰기 게이트 사유 — 이어 하든 처음부터 하든 지금은 미리보기까지인 까닭. 쓸 수 있으면 nil.
    public let writeBlock: SyncedWriteBlock?

    /// 작업을 만든다(시험 대역 · 구현).
    public init(
        jobID: String,
        targetScope: AccountScope?,
        doneChapters: [NotebookChapter],
        totalChapters: Int,
        tally: BackupImportTally,
        updatedAt: Date,
        canResume: Bool,
        writeBlock: SyncedWriteBlock?
    ) {
        self.jobID = jobID
        self.targetScope = targetScope
        self.doneChapters = doneChapters
        self.totalChapters = totalChapters
        self.tally = tally
        self.updatedAt = updatedAt
        self.canResume = canResume
        self.writeBlock = writeBlock
    }
}

/// 불러오기 실패 (설계 §4-2). 암호 · 평문 바이트는 담지 않는다. 검사 단계의 오류는 모두 저장소를 바꾸기 전이다.
public enum BackupImportError: Error, Equatable, Sendable {
    /// 고른 파일을 앱 작업 영역으로 복사하지 못했다(읽을 수 없음 · 내려받지 않은 파일 등).
    case fileUnreadable
    /// 암호가 맞지 않거나 파일이 손상 · 변조 · 잘렸다. 허용 밖 항목 · 경로 이탈 · 형식 검증 실패도 같은 「파일 거부」 다.
    case wrongPasswordOrDamaged
    /// 이 앱이 읽지 못하는 형식 버전이다.
    case unsupportedFormat(formatVersion: Int)
    /// 상한(항목 수 · blob 하나 · 풀린 합계)을 넘었다.
    case tooLarge
    /// 사본 · 작업 폴더를 쓸 공간이 모자란다.
    case insufficientSpace
    /// 작업 폴더 · 작업 기록을 만들거나 쓰지 못했다(공간 부족 밖의 입출력).
    case ioFailed
    /// 저장소의 필사 행을 읽지 못했다.
    case storeUnreadable
    /// 저장소에 쓰지 못했다 — 그 장은 아무것도 쓰지 않았고(rollback) 앞서 쓴 장은 그대로다. 이어 하기로 남은 장을 잇는다.
    case storeWriteFailed
    /// 이 검사 결과로는 더 적용할 수 없다(평문 작업 폴더를 이미 지웠다) — 다시 검사하거나 이어 하기로 암호를 다시 받는다.
    case inspectionExpired
    /// 그 작업이 없다(이미 끝났거나 버렸다).
    case jobNotFound
    /// 다른 계정에서(또는 대상 계정 없이) 시작한 작업이라 이 환경에서 잇지 않는다 — 버리기 · 이 계정으로 처음부터만.
    case jobFromOtherAccount
}

private enum BackupImporterKey: DependencyKey {
    /// 앱이 이 실행의 편집 환경 · 저장소 actor · 복원 쓰기 · 작업 기록으로 만든 `LiveBackupImporter` 를 주입한다. 없으면 불러올 수 없다.
    static let liveValue: (any BackupImporting)? = nil
    /// 시험 기본값 — 저장소를 건드리지 않는다(공유 SwiftData actor 를 쓰지 않는다). 불러오기를 보는 시험이 대역을 넣는다.
    static let testValue: (any BackupImporting)? = nil
}

public extension DependencyValues {
    /// 「백업 불러오기」 — 필사 백업 파일 검사 · 적용.
    var backupImporter: (any BackupImporting)? {
        get { self[BackupImporterKey.self] }
        set { self[BackupImporterKey.self] = newValue }
    }
}
