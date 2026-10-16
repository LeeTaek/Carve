//
//  BackupImportPlanPreview.swift
//  Domain
//
//  Created by Claude on 10/6/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

/// 불러오기 미리보기 — 결정별 수 · 필사책 수와 판정할 장 (설계 §4-1 6단계).
///
/// 검사 시점의 값이다. 적용은 쓰기 직전에 장마다 다시 판정하므로(미리보기 뒤 동기화로 바뀐 것 반영) 실제로 넣은 수와 다를 수 있다.
/// 항목 하나는 정확히 한 번 센다 — 수를 모두 더하면(`itemCount`) 판정한 항목 수와 같다.
public struct BackupImportPreview: Equatable, Sendable {
    /// 그 절의 현재 필사로 넣는 수(`insertCurrent` — 비운 현재 행 포함).
    public var new: Int
    /// 같은 내용이 이미 있어 건너뛰는 수(`skipSame`).
    public var same: Int
    /// 이전 필사 기록으로 더하는 수(`insertArchived`).
    public var archived: Int
    /// 이 기기에서 뒤에 지운 절이라 기록으로만 넣는 수(`protectCleared`).
    public var protectedCleared: Int
    /// 비운 항목이라 넣지 않는 수(`skipEmpty`).
    public var skippedEmpty: Int
    /// 해석할 수 없어 건너뛰는 수 — 사유별. 어느 장에도 놓을 수 없는 항목(모르는 권 · 범위 밖 장)도 여기서 센다.
    public var unsupported: [BackupUnsupportedReason: Int]
    /// 필사책 토큰이 `NotebookID` 형식이 아니어서 건너뛰는 수(「알 수 없는 필사책」, 형식 2). `unsupportedCount` 에 든다.
    ///
    /// 사유 열거형(`BackupUnsupportedReason`)의 경우가 아니라 따로 센다 — 설정 화면이 그 열거형을 빠짐없이 `switch` 해 경우를 더하면 화면이
    /// 컴파일되지 않는다(`BackupItemSupport` 주석). 화면이 사유 문구를 더할 때 열거형으로 옮길 수 있다.
    public var unknownNotebook: Int
    /// 이 백업이 담은 필사책 수 — 항목의 필사책 ∪ 필사책 목록(`BackupImportPlanner.notebookCount`). 형식 1 은 항목이 있으면 1(기본 필사책)이다.
    /// 항목 수가 아니라서 `itemCount` 에 들지 않는다.
    public var notebooks: Int
    /// 지원 항목이 있는 장(필사책 · 번역본 포함) — 필사책(기본 먼저) → 권 순서 → 장 순서. 적용은 이 장들을 차례로 다시 판정한다.
    public var chapters: [NotebookChapter]

    /// 수를 그대로 지정해 만든다(기본은 빈 미리보기).
    public init(
        new: Int = 0,
        same: Int = 0,
        archived: Int = 0,
        protectedCleared: Int = 0,
        skippedEmpty: Int = 0,
        unsupported: [BackupUnsupportedReason: Int] = [:],
        unknownNotebook: Int = 0,
        notebooks: Int = 0,
        chapters: [NotebookChapter] = []
    ) {
        self.new = new
        self.same = same
        self.archived = archived
        self.protectedCleared = protectedCleared
        self.skippedEmpty = skippedEmpty
        self.unsupported = unsupported
        self.unknownNotebook = unknownNotebook
        self.notebooks = notebooks
        self.chapters = chapters
    }

    /// 장 판정들을 모은다.
    /// - Parameters:
    ///   - plans: 장마다의 판정. 같은 장을 두 번 넘기면 두 번 센다.
    ///   - unplaced: 어느 장에도 놓을 수 없는 항목의 사유별 수(`BackupImportPlanner.unplaced`).
    public init(plans: [BackupChapterPlan], unplaced: [BackupUnsupportedReason: Int] = [:]) {
        self.init(unsupported: unplaced)
        for plan in plans {
            add(plan)
        }
    }

    /// 장 판정 하나를 더한다 — 결정마다 세고, 지원 항목이 있으면 그 장을 `chapters` 에 순서대로 넣는다. 부작용 없음(값만 바꾼다).
    public mutating func add(_ plan: BackupChapterPlan) {
        for entry in plan.decisions {
            count(entry.decision)
        }
        if plan.hasSupportedItems, !chapters.contains(plan.page) {
            chapters = BackupImportPlanner.ordered(chapters + [plan.page])
        }
    }

    /// 결정 하나를 센다.
    mutating func count(_ decision: BackupImportDecision) {
        switch decision {
        case .insertCurrent: new += 1
        case .skipSame: same += 1
        case .insertArchived: archived += 1
        case .protectCleared: protectedCleared += 1
        case .skipEmpty: skippedEmpty += 1
        case .unsupported(let reason): unsupported[reason, default: 0] += 1
        }
    }

    /// 해석할 수 없는 항목 수의 합 — 사유별 수와 알 수 없는 필사책 수.
    public var unsupportedCount: Int { unsupported.values.reduce(0, +) + unknownNotebook }

    /// 새 행을 넣는 수 — 현재 · 보관 · 지운 절 보호.
    public var insertCount: Int { new + archived + protectedCleared }

    /// 센 항목 수의 합 — 파일의 항목 수와 같아야 한다.
    public var itemCount: Int { insertCount + same + skippedEmpty + unsupportedCount }
}
