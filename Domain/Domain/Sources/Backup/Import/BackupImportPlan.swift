//
//  BackupImportPlan.swift
//  Domain
//
//  Created by Claude on 10/6/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

/// 백업 항목 하나를 어떻게 불러오는가 (설계 §5-1 표). 미리보기 수와 쓰기가 같은 결정을 쓴다.
public enum BackupImportDecision: Hashable, Sendable {
    /// 같은 내용이 지금 저장소에 있거나 이 절에 이미 넣기로 했다. 비운 항목이면 그 절의 대표가 이미 비운 행이다 — 쓰지 않는다(미리보기 same).
    case skipSame
    /// 비운 항목인데 잉크 있는 대표가 있거나 현재 후보가 아니다 — 지금 필사를 비우지 않고 기록에 빈 행을 더하지 않는다(미리보기 skippedEmpty).
    case skipEmpty
    /// 그 절의 현재 필사로 새 행을 넣는다(`isPresent = true`). 비운 현재 행도 여기다(미리보기 new).
    case insertCurrent
    /// 이전 필사 기록으로 새 행을 넣는다(`isPresent = false`, 미리보기 archived).
    case insertArchived
    /// 이 기기에서 백업보다 뒤에 지운 절 — 지운 것을 되살리지 않고 기록으로만 새 행을 넣는다(`isPresent = false`, 미리보기 protectedCleared).
    case protectCleared
    /// 이 앱이 해석할 수 없는 항목 — 건너뛰고 사유별로 센다(미리보기 unsupported).
    case unsupported(BackupUnsupportedReason)

    /// 저장소에 새 행을 넣는 결정인가.
    public var insertsRow: Bool {
        switch self {
        case .insertCurrent, .insertArchived, .protectCleared: true
        case .skipSame, .skipEmpty, .unsupported: false
        }
    }

    /// 넣는 행의 `isPresent` — `insertCurrent` 만 true 다.
    public var insertsAsPresent: Bool { self == .insertCurrent }
}

/// 항목 하나의 결정.
public struct BackupItemDecision: Equatable, Sendable {
    /// 결정한 항목의 id(`BackupItem.id`).
    public let itemID: String
    /// 항목의 절.
    public let verse: Int
    /// 결정.
    public let decision: BackupImportDecision

    /// 결정을 묶는다.
    public init(itemID: String, verse: Int, decision: BackupImportDecision) {
        self.itemID = itemID
        self.verse = verse
        self.decision = decision
    }
}

/// 판정기가 넣기로 한 행 하나 — 복원 쓰기가 blob 바이트를 읽어 `BibleDrawing` 행으로 만든다 (설계 §4-3 「넣는 행」).
///
/// 판정기는 파일을 읽지 않으므로 바이트 대신 blob 이름을 담는다. 값은 **항목 원본 그대로**다 — `drawingVersion` 을 승격 · 강등하지 않고,
/// `creationDate` · `updateDate` 를 now 로 덮지 않으며, 번역 저장값이 nil 이면 nil 이다. `isPresent` 만 결정에서 온다.
/// `rowUUID` 는 쓰는 쪽이 늘 새로 발급하고, business id 는 `BibleDrawing.init` 규칙대로다 — 그래서 여기에 없다.
public struct BackupRowInsertion: Equatable, Sendable {
    /// 넣을 항목의 id.
    public let itemID: String
    /// `insertCurrent` · `insertArchived` · `protectCleared` 중 하나.
    public let decision: BackupImportDecision
    /// 권 코드 · 번역본으로 찾은 장(`titleName` · `titleChapter`).
    public let chapter: BibleChapter
    /// 절.
    public let verse: Int
    /// 항목의 번역본 값 그대로(`Translation.rawValue`). nil 이면 nil — 개역개정 항목은 열에 이 값 그대로(nil 은 nil — NKRV 로 채우지 않는다),
    /// KJV · BSB 항목은 열에 nil 을 쓴다(`StoredBookKey.translationColumn` — 복원 쓰기가 정한다).
    public let translation: String?
    /// `isPresent` — `insertCurrent` 만 true.
    public let isPresent: Bool
    /// 좌표 형식 — 항목 값 그대로.
    public let drawingVersion: Int?
    /// `lineData` 원본 바이트의 blob 이름. 비운 행이면 nil.
    public let inkBlob: String?
    /// `layoutMetadataData` 원본 바이트의 blob 이름. 비운 행에도 남아 있으면 있다.
    public let metadataBlob: String?
    /// 내용 지문 — 잉크가 있을 때만. 쓴 뒤 대조에 쓴다.
    public let fingerprint: String?
    /// `creationDate` — 항목 `createdAt` 그대로(초안은 nil).
    public let creationDate: Date?
    /// `updateDate` — 항목 `updatedAt` 그대로.
    public let updateDate: Date?

    /// 판정한 항목에서 만든다.
    /// - Parameters:
    ///   - item: 넣을 항목.
    ///   - decision: 새 행을 넣는 결정(`insertsRow`).
    ///   - chapter: 항목의 권 코드 · 장 · 번역본으로 찾은 장(`BackupImportPlanner.chapter(of:)`).
    public init(item: BackupItem, decision: BackupImportDecision, chapter: BibleChapter) {
        self.itemID = item.id
        self.decision = decision
        self.chapter = chapter
        self.verse = item.verse.verse
        self.translation = item.verse.translation
        self.isPresent = decision.insertsAsPresent
        self.drawingVersion = item.drawingVersion
        self.inkBlob = item.inkBlob
        self.metadataBlob = item.metadataBlob
        self.fingerprint = item.fingerprint
        self.creationDate = item.createdAt
        self.updateDate = item.updatedAt
    }

    /// `BibleDrawing.titleName` 에 넣을 값 — 장의 권 · 번역본으로 지은 `StoredBookKey.titleName(for:)`(개역개정 `BibleTitle.rawValue`, 영어 `KJV-…`).
    public var titleName: String { StoredBookKey.titleName(for: chapter) }
}

/// 대표 고정 — 적용할 때 이 지금 행의 `isPresent` 만 true 로 바꿔, 넣는 보관 행이 그 절의 대표를 바꾸지 못하게 한다(오케스트레이터 결정 2026-10-06).
///
/// 1.3.0 은 `isPresent` 를 켜지 않아 legacy 행은 대개 false · nil 이다. `isPresent` 행이 없는 절은 대표 규칙이 **전체 행에서** 고르므로,
/// 더 늦은 다른 내용을 보관 행(`insertArchived` · `protectCleared`)으로 넣기만 해도 화면의 필사가 바뀐다 — 「지금 필사는 그대로 둔다」(정책 §7-1)를
/// 어긴다. 그래서 그 절의 지금 대표를 넣기와 같은 트랜잭션에서 present 로 고정한다. 비운 대표여도 같다(그 절은 비운 채로 남는다).
/// 행이 없는 절은 고정하지 않는다 — 빈 자리 행을 만들면 나중에 다른 기기에서 도착하는 legacy 행을 가린다.
public struct BackupRepresentativePin: Hashable, Sendable {
    /// 절.
    public let verse: Int
    /// 고정할 지금 대표 행의 키(`BackupRowRecord.rowKey` — `rowUUID ?? business id`).
    public let rowKey: String

    /// 고정 대상을 만든다.
    public init(verse: Int, rowKey: String) {
        self.verse = verse
        self.rowKey = rowKey
    }
}

/// 장 하나의 판정 결과 — 항목마다의 결정, 넣을 행, 대표 고정 (설계 §5-1). `BackupImportPlanner.plan` 이 만든다.
public struct BackupChapterPlan: Equatable, Sendable {
    /// 판정한 장.
    public let chapter: BibleChapter
    /// 이 장 항목마다의 결정 — 절 오름차순, 절 안에서는 처리 순서(지원 안 됨 → 현재 후보 → 나머지, 각각 id 순).
    public let decisions: [BackupItemDecision]
    /// 넣을 행 — `decisions` 중 새 행을 넣는 결정만, 같은 순서로.
    public let insertions: [BackupRowInsertion]
    /// 대표 고정 — 적용할 때 넣기와 같은 트랜잭션에서 `isPresent` 만 true 로 바꿀 지금 행(절 오름차순). 미리보기 수에는 들지 않는다.
    public let pins: [BackupRepresentativePin]

    /// 판정 결과를 묶는다.
    public init(
        chapter: BibleChapter,
        decisions: [BackupItemDecision],
        insertions: [BackupRowInsertion],
        pins: [BackupRepresentativePin] = []
    ) {
        self.chapter = chapter
        self.decisions = decisions
        self.insertions = insertions
        self.pins = pins
    }

    /// 항목 id 의 결정. 이 장에서 판정하지 않은 항목이면 nil.
    public func decision(for itemID: String) -> BackupImportDecision? {
        decisions.first { $0.itemID == itemID }?.decision
    }

    /// 지원 판정을 통과한 항목이 있는가 — 없으면 적용할 때 다시 판정할 것이 없다.
    public var hasSupportedItems: Bool {
        decisions.contains { decision in
            if case .unsupported = decision.decision { return false }
            return true
        }
    }

    /// 이 장 하나의 결정별 수.
    public var preview: BackupImportPreview {
        BackupImportPreview(plans: [self])
    }
}
