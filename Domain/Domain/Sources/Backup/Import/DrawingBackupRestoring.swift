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

/// 백업 항목을 저장소(`BibleDrawing`)에 넣는 **유일한 길** — 장 하나가 한 트랜잭션이다 (설계 §4-3).
///
/// 구현(`SwiftDataDrawingBackupRestorer`)은 같은 actor 구간에서 ① 세대를 확인하고 ② 그 장의 행을 백업 전용 조회(`BackupRowRecord` —
/// 내보내기와 같은 변환)로 다시 읽어 ③ `BackupImportPlanner` 로 **다시 판정한 결과만** 쓴다(미리보기 뒤 동기화로 바뀐 것 반영).
/// 넣는 행은 바이트 · `drawingVersion` · 시각 · 번역 저장값을 원본 그대로 두고 `rowUUID` 만 새로 발급한다(KJV · BSB 항목은 `titleName` 접두로
/// 번역본을 지니고 열은 nil — `StoredBookKey`). 있는 행은 고치지 않는다 —
/// 대표 고정(`BackupRepresentativePin`)의 `isPresent` 하나만 예외다(오케스트레이터 결정 2026-10-06).
/// 재시도는 같은 규칙으로 멱등이다 — 이미 넣은 내용은 같은 지문이라 `skipSame` 이다.
public protocol DrawingBackupRestoring: Sendable {
    /// 장 하나를 복원한다.
    /// - Parameters:
    ///   - command: 그 장의 백업 항목과 blob 바이트.
    ///   - chapter: 쓸 장.
    ///   - generation: 적용을 시작할 때 읽은 저장소 세대. 지금 세대와 다르면(그 사이 「모든 필사 삭제」) **아무것도 쓰지 않고**
    ///     `DrawingRepositoryError.staleStoreGeneration` 을 던진다.
    /// - Returns: 쓰기 직전 다시 판정한 실제 결정과 적용한 대표 고정.
    /// - Throws: 세대가 다르면 `staleStoreGeneration`, 쓰기 전 확인에 실패하면 `BackupChapterRestoreError`, 저장에 실패하면
    ///   `DrawingRepositoryError.persistenceFailed` — 어느 경우든 그 장에는 아무것도 남지 않는다(rollback).
    func restore(
        _ command: BackupChapterRestoreCommand,
        chapter: BibleChapter,
        generation: DrawingStoreGeneration
    ) async throws -> BackupChapterRestoreOutcome
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

/// 장 하나를 복원한 결과 — 쓰기 직전 다시 판정한 **실제** 결정과 적용한 대표 고정.
///
/// 미리보기 뒤 동기화로 저장소가 바뀌었으면 미리보기의 결정과 다를 수 있다(정책 §7-1).
public struct BackupChapterRestoreOutcome: Equatable, Sendable {
    /// 복원한 장.
    public let chapter: BibleChapter
    /// 항목마다의 실제 결정 — 절 오름차순, 절 안에서는 판정 순서(`BackupChapterPlan.decisions` 그대로).
    public let decisions: [BackupItemDecision]
    /// 실제로 `isPresent` 를 true 로 바꾼 지금 행(대표 고정).
    public let pins: [BackupRepresentativePin]

    /// 결과를 묶는다.
    public init(chapter: BibleChapter, decisions: [BackupItemDecision], pins: [BackupRepresentativePin]) {
        self.chapter = chapter
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
        BackupImportPreview(plans: [BackupChapterPlan(chapter: chapter, decisions: decisions, insertions: [], pins: pins)])
    }

    /// 한 절의 결정별 수.
    /// - Parameter verse: 절.
    /// - Returns: 그 절 항목들의 결정별 수. 부작용 없음.
    public func counts(verse: Int) -> BackupImportPreview {
        let verseDecisions = decisions.filter { $0.verse == verse }
        return BackupImportPreview(plans: [BackupChapterPlan(chapter: chapter, decisions: verseDecisions, insertions: [])])
    }
}

/// 복원 쓰기가 **쓰기 전에** 거절한 명령 — 그 장에는 아무것도 쓰지 않았다.
public enum BackupChapterRestoreError: Error, Equatable, Sendable {
    /// 넣을 행의 blob 바이트가 명령에 없거나, 바이트가 이름(SHA-256)과 다르다.
    case blobUnavailable(name: String)
    /// 넣을 행의 번역본을 이 앱이 모르거나 장의 번역본과 다르다 — 명령이 지원 판정을 계산하고 판정기가 장의 번역본 항목만 넣으므로 생기지 않아야 한다.
    case unknownTranslation
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
