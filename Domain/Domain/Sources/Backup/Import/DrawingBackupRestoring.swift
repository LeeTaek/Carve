//
//  DrawingBackupRestoring.swift
//  Domain
//
//  Created by Claude on 10/6/26.
//  Copyright © 2026 leetaek. All rights reserved.
//
//  불러오기의 장 단위 복원 쓰기 — 계약 · 명령 · 결과 (설계 docs/backup-import-design.md §4-3 · §5-1).
//

import Dependencies
import Foundation

/// 백업 항목을 저장소(`BibleDrawing`)에 넣는 **유일한 길** — 필사책 안의 장 하나가 한 트랜잭션이다 (설계 §4-3).
///
/// 구현(`SwiftDataDrawingBackupRestorer`)은 같은 actor 구간에서 ① 세대를 확인하고 ② 그 장의 행을 백업 전용 조회(`BackupRowRecord` —
/// 내보내기와 같은 변환)로 다시 읽어 ③ `BackupImportPlanner` 로 **다시 판정한 결과만** 쓴다(미리보기 뒤 동기화로 바뀐 것 반영).
/// 넣는 행은 바이트 · `drawingVersion` · 시각 · 번역 저장값을 원본 그대로 두고 `rowUUID` 만 새로 발급한다(KJV · BSB 항목은 `titleName` 접두로
/// 번역본을 지니고 열은 nil, 다른 필사책 항목은 그 앞에 `nb_<토큰>~` — `StoredBookKey`). 있는 행은 고치지 않는다 —
/// 대표 고정(`BackupRepresentativePin`)의 `isPresent` 하나만 예외다(오케스트레이터 결정 2026-10-06).
/// 재시도는 같은 규칙으로 멱등이다 — 이미 넣은 내용은 같은 지문이라 `skipSame` 이다.
///
/// 필사책 목록(`DrawingNotebook`)도 이 길로만 쓴다(`restoreNotebooks`) — 같은 ID 가 있으면 `updatedAt` 이 늦은 쪽을 남기고, 없으면 넣는다.
public protocol DrawingBackupRestoring: Sendable {
    /// 필사책 안의 장 하나를 복원한다.
    /// - Parameters:
    ///   - command: 그 장의 백업 항목과 blob 바이트.
    ///   - page: 쓸 장(필사책 · 번역본 포함). **기본값이 없다** — 필사책을 빠뜨리면 다른 필사책 항목이 기본 필사책에 써진다.
    ///   - generation: 적용을 시작할 때 읽은 저장소 세대. 지금 세대와 다르면(그 사이 「모든 필사 삭제」) **아무것도 쓰지 않고**
    ///     `DrawingRepositoryError.staleStoreGeneration` 을 던진다.
    /// - Returns: 쓰기 직전 다시 판정한 실제 결정과 적용한 대표 고정.
    /// - Throws: 세대가 다르면 `staleStoreGeneration`, 쓰기 전 확인에 실패하면 `BackupChapterRestoreError`, 저장에 실패하면
    ///   `DrawingRepositoryError.persistenceFailed` — 어느 경우든 그 장에는 아무것도 남지 않는다(rollback).
    func restore(
        _ command: BackupChapterRestoreCommand,
        page: NotebookChapter,
        generation: DrawingStoreGeneration
    ) async throws -> BackupChapterRestoreOutcome

    /// 필사책 목록을 복원한다 — 한 트랜잭션.
    ///
    /// 필사책마다(같은 ID 가 목록에 둘이면 `BackupNotebookRecord.isNewer(than:)` 로 이기는 하나): 저장소에 그 ID 의 레코드가 없으면 백업 값
    /// 그대로 새 레코드를 넣고, 있으면 저장소의 최신 레코드와 견줘 백업이 **늦을 때만** 그 ID 의 레코드 전부를 백업 값으로 바꾼다(같거나 이르면
    /// 그대로 — 다시 불러와도 멱등). 레코드를 지우지 않는다. ID 가 `NotebookID` 형식이 아닌 레코드는 건너뛴다.
    /// - Parameters:
    ///   - records: 필사책 목록(`BackupManifest.notebooks`).
    ///   - generation: 적용을 시작할 때 읽은 저장소 세대. 다르면 아무것도 쓰지 않고 `staleStoreGeneration` 을 던진다.
    /// - Returns: 넣은 · 바꾼 · 그대로 둔 · 건너뛴 수.
    /// - Throws: 세대가 다르면 `staleStoreGeneration`, 저장에 실패하면 `persistenceFailed`(rollback).
    func restoreNotebooks(_ records: [BackupNotebookRecord], generation: DrawingStoreGeneration) async throws -> BackupNotebookRestoreOutcome
}

/// 필사책 목록 복원의 결과.
public struct BackupNotebookRestoreOutcome: Equatable, Sendable {
    /// 저장소에 없어 새로 넣은 필사책 수.
    public let inserted: Int
    /// 백업이 더 늦어 저장소 레코드를 바꾼 필사책 수.
    public let updated: Int
    /// 저장소가 같거나 더 늦어 그대로 둔 필사책 수.
    public let unchanged: Int
    /// ID 가 `NotebookID` 형식이 아니어서 건너뛴 레코드 수.
    public let skipped: Int

    /// 결과를 묶는다.
    public init(inserted: Int = 0, updated: Int = 0, unchanged: Int = 0, skipped: Int = 0) {
        self.inserted = inserted
        self.updated = updated
        self.unchanged = unchanged
        self.skipped = skipped
    }

    /// 저장소가 바뀌었는가.
    public var changedStore: Bool { inserted > 0 || updated > 0 }
}

/// 장 하나를 복원하라는 명령 — 그 장의 백업 항목과, 항목이 가리키는 blob 바이트.
///
/// 지원 판정(`unsupported`)은 만들 때 **이 바이트로** 계산한다 — 검사(미리보기)가 같은 blob 파일로 계산한 것과 같고, 부르는 쪽이 사전을 따로
/// 맞추지 않아도 된다. 그래서 바이트에는 지원하지 않는 항목의 메타데이터 blob 도 들어 있어야 판정이 미리보기와 같다.
public struct BackupChapterRestoreCommand: Equatable, Sendable {
    /// 그 장의 백업 항목 — 다른 장 항목이 섞여 있어도 판정기가 보지 않는다.
    public let items: [BackupItem]
    /// blob 이름(소문자 SHA-256 hex) → 원본 바이트.
    public let blobs: [String: Data]
    /// 항목 id → 해석할 수 없는 이유(`BackupItemSupport`) — `blobs` 로 계산했다.
    public let unsupported: [String: BackupUnsupportedReason]

    /// 명령을 만든다 — 지원 판정을 여기서 한 번 계산한다.
    /// - Parameters:
    ///   - items: 그 장의 백업 항목(검증을 마친 payload 의 것).
    ///   - blobs: 항목이 가리키는 blob 이름 → 바이트. 넣을 행의 바이트가 빠져 있으면 복원이 쓰기 전에 거절한다.
    public init(items: [BackupItem], blobs: [String: Data]) {
        self.items = items
        self.blobs = blobs
        var unsupported: [String: BackupUnsupportedReason] = [:]
        for item in items {
            if let reason = BackupItemSupport.reason(item, metadataBytes: { blobs[$0] }) {
                unsupported[item.id] = reason
            }
        }
        self.unsupported = unsupported
    }
}

/// 필사책 안의 장 하나를 복원한 결과 — 쓰기 직전 다시 판정한 **실제** 결정과 적용한 대표 고정.
///
/// 미리보기 뒤 동기화로 저장소가 바뀌었으면 미리보기의 결정과 다를 수 있다(정책 §7-1).
public struct BackupChapterRestoreOutcome: Equatable, Sendable {
    /// 복원한 장(필사책 · 번역본 포함).
    public let page: NotebookChapter
    /// 항목마다의 실제 결정 — 절 오름차순, 절 안에서는 판정 순서(`BackupChapterPlan.decisions` 그대로).
    public let decisions: [BackupItemDecision]
    /// 실제로 `isPresent` 를 true 로 바꾼 지금 행(대표 고정).
    public let pins: [BackupRepresentativePin]

    /// 결과를 묶는다.
    public init(page: NotebookChapter, decisions: [BackupItemDecision], pins: [BackupRepresentativePin]) {
        self.page = page
        self.decisions = decisions
        self.pins = pins
    }

    /// 새로 넣은 행 수(`insertCurrent` · `insertArchived` · `protectCleared`).
    public var insertedCount: Int {
        decisions.filter { $0.decision.insertsRow }.count
    }

    /// 이 장의 저장소가 바뀌었는가 — 넣은 행이나 대표 고정이 있으면 true. 그때만 `LocalDrawingChange` 를 보낸다.
    public var changedStore: Bool {
        insertedCount > 0 || !pins.isEmpty
    }

    /// 결정별 수 — 미리보기와 같은 모양(`BackupImportPreview`)이다.
    public var counts: BackupImportPreview {
        BackupImportPreview(plans: [BackupChapterPlan(page: page, decisions: decisions, insertions: [], pins: pins)])
    }

    /// 한 절의 결정별 수.
    /// - Parameter verse: 절.
    /// - Returns: 그 절 항목들의 결정별 수. 부작용 없음.
    public func counts(verse: Int) -> BackupImportPreview {
        let verseDecisions = decisions.filter { $0.verse == verse }
        return BackupImportPreview(plans: [BackupChapterPlan(page: page, decisions: verseDecisions, insertions: [])])
    }
}

/// 복원 쓰기가 **쓰기 전에** 거절한 명령 — 그 장에는 아무것도 쓰지 않았다.
public enum BackupChapterRestoreError: Error, Equatable, Sendable {
    /// 넣을 행의 blob 바이트가 명령에 없거나, 바이트가 이름(SHA-256)과 다르다.
    case blobUnavailable(name: String)
    /// 넣을 행의 번역본을 이 앱이 모르거나 장의 번역본과 다르다 — 명령이 지원 판정을 계산하고 판정기가 장의 번역본 항목만 넣으므로 생기지 않아야 한다.
    case unknownTranslation
    /// 넣을 행의 필사책이 장의 필사책과 다르다 — 판정기가 장의 필사책 항목만 넣으므로 생기지 않아야 한다.
    case notebookMismatch
}

private enum DrawingBackupRestorerKey: DependencyKey {
    /// 앱이 이 실행의 저장소 actor 로 만든 구현(`SwiftDataDrawingBackupRestorer`)을 주입한다. 없으면 불러오기를 적용하지 않는다.
    static let liveValue: (any DrawingBackupRestoring)? = nil
    /// 시험 기본값 — 저장소를 건드리지 않는다(공유 SwiftData actor 를 쓰지 않는다). 복원을 보는 시험이 자기 컨테이너로 만든 구현을 넣는다.
    static let testValue: (any DrawingBackupRestoring)? = nil
}

public extension DependencyValues {
    /// 「백업 불러오기」 의 장 단위 복원 쓰기.
    var drawingBackupRestorer: (any DrawingBackupRestoring)? {
        get { self[DrawingBackupRestorerKey.self] }
        set { self[DrawingBackupRestorerKey.self] = newValue }
    }
}
