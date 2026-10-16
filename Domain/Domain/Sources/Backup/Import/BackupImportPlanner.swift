//
//  BackupImportPlanner.swift
//  Domain
//
//  Created by Claude on 10/6/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

/// 불러오기 판정기 — 백업 항목과 지금 저장소 행으로 절마다 무엇을 넣을지 정한다 (설계 §5-1, 정책 §7-1).
///
/// **순수 함수다.** 파일 · 저장소 · 시각을 모른다. 항목의 지원 판정(`BackupItemSupport`)은 호출부가 blob 을 읽어 미리 계산해 넘기고,
/// 지금 저장소는 백업 전용 조회(`BackupRowRecord` — 원본 바이트로 만든 지문)로 받는다. 미리보기와 쓰기 직전 재판정이 같은 함수를 쓴다.
///
/// - **판정 단위는 한 절이다** — 필사책 · 권 · 장 · 절과 번역 묶음이 같은 것. 묶음은 셋이다(영어 현지화 2026-10-06): 번역 nil 은 지금 앱에서
///   NKRV 화면에 보이므로 NKRV 와 한 묶음이고(넣는 행의 번역 저장값은 nil 그대로), KJV · BSB 는 각자 묶음이다. 장(`NotebookChapter`)이 필사책과
///   번역본을 지니므로 한 장의 항목 · 행은 한 필사책 · 한 묶음뿐이다 — 항목은 `page(of:)` 가 필사책 · 번역본까지 맞는 장에만 놓고, 행은 그 장의
///   `titleName`(`StoredBookKey.titleName(for: page)` — 다른 필사책은 `nb_<토큰>~` 접두)으로 고르고 묶음은 `titleName` 접두를 먼저 본다
///   (`BackupRowRecord.backupTranslation` — 영어 행은 열이 nil). 그래서 같은 내용이라도 필사책이 다르면 다른 절이다(같은 지문이어도 `skipSame` 이 아니다).
/// - 필사책 토큰이 `NotebookID` 형식이 아닌 항목(「알 수 없는 필사책」)은 어느 장에도 놓지 않고 따로 센다(`unknownNotebookCount`).
/// - `R` = 그 절의 지금 저장소 행 전부(현재 · 보관 · 비운 행), 대표 = `DrawingRepresentativeRule.pick(R)`. 같은 파일의 다른 항목이 넣을 행은
///   `R` 에 더하지 않는다 — 단 **같은 지문은 한 절에 한 번만** 넣는다.
/// - 처리 순서는 지원 판정 → 현재 후보 → 나머지(id 순)다. 현재 후보는 지원 판정을 통과한 `isCurrent` 항목 중 `updatedAt` 이 가장 늦은 하나다
///   (nil 은 가장 이른 시각, 같으면 id 사전순 앞). 나머지 `isCurrent` 항목은 현재 후보가 아닌 것으로 다룬다.
/// - 「잉크 있음」 은 `lineData` · `inkBlob` 이 있는 것이다(형식의 「비운 행」 정의와 같다). 판정기는 바이트를 풀지 않는다.
///
/// 결정(지원 판정을 통과한 항목):
/// - **잉크 있는 항목** — ① `R` 의 어느 행이나 이 절에 넣기로 한 것과 지문이 같으면 `skipSame` ② 현재 후보이고 잉크 있는 대표가 없으면
///   `insertCurrent` — 단 대표가 비운 행이고 그 `updateDate` 가 항목 `updatedAt` 보다 늦으면 `protectCleared` ③ 그 밖은 `insertArchived`.
/// - **비운 항목** — 현재 후보이고 `R` 이 비었으면 `insertCurrent`(비운 현재 행), 대표가 이미 비운 행이면 `skipSame`, 그 밖은 `skipEmpty`.
/// - **대표 고정** — `R` 이 있는데 `isPresent` 행이 없는 절(1.3.0 legacy)에 `insertCurrent` 없이 보관 행만 넣으면, 지금 대표를 `pins` 로 내
///   적용이 같은 트랜잭션에서 present 로 고정하게 한다(오케스트레이터 결정 2026-10-06). 결정과 미리보기 수는 바뀌지 않는다.
public enum BackupImportPlanner {
    /// 번역 nil 과 한 묶음으로 판정하는 번역본 — 지금 앱에서 nil 은 NKRV 화면에 보인다. KJV · BSB 는 각자 묶음이다.
    static let nilTranslationGroup = Translation.NKRV.rawValue

    // MARK: - 장 하나

    /// 필사책 안의 장 하나를 판정한다.
    /// - Parameters:
    ///   - items: 백업 항목. 이 장(필사책 · 권 코드 · 장 · 번역본 — `page(of:)`)에 놓이는 항목만 보고, 다른 장 항목은 결정에 넣지 않는다.
    ///   - unsupported: 항목 id → 해석할 수 없는 이유(호출부가 `BackupItemSupport.reason` 으로 계산). 여기 있는 항목은 `.unsupported` 다.
    ///   - current: 그 장의 지금 저장소 행 전부(`BackupRowLoad.rows`). 다른 장 행(`titleName` 이 그 장의 필사책 · 번역본 이름과 다르거나
    ///     `chapter` 가 다른 것 — 다른 필사책 · 번역본의 같은 권 · 장 행 포함)은 보지 않는다.
    ///   - page: 판정할 장(필사책 · 번역본 포함).
    /// - Returns: 항목마다의 결정과 넣을 행. 부작용 없음.
    public static func plan(
        items: [BackupItem],
        unsupported: [String: BackupUnsupportedReason],
        current: [BackupRowRecord],
        page: NotebookChapter
    ) -> BackupChapterPlan {
        var itemsByGroup: [VerseGroup: [BackupItem]] = [:]
        for item in items where Self.page(of: item) == page {
            itemsByGroup[VerseGroup(verse: item.verse.verse, translation: item.verse.translation), default: []].append(item)
        }
        var rowsByGroup: [VerseGroup: [BackupRowRecord]] = [:]
        let titleName = StoredBookKey.titleName(for: page)
        for row in current where row.titleName == titleName && row.chapter == page.chapter.chapter {
            rowsByGroup[VerseGroup(verse: row.verse, translation: row.backupTranslation), default: []].append(row)
        }

        var decisions: [BackupItemDecision] = []
        var insertions: [BackupRowInsertion] = []
        var pins: [BackupRepresentativePin] = []
        for group in itemsByGroup.keys.sorted() {
            let rows = rowsByGroup[group] ?? []
            let judged = decideVerse(itemsByGroup[group] ?? [], rows: rows, unsupported: unsupported)
            for (item, decision) in judged {
                decisions.append(BackupItemDecision(itemID: item.id, verse: item.verse.verse, decision: decision))
                if decision.insertsRow {
                    insertions.append(BackupRowInsertion(item: item, decision: decision, page: page))
                }
            }
            if let pin = representativePin(verse: group.verse, rows: rows, decisions: judged.map { $0.decision }) {
                pins.append(pin)
            }
        }
        return BackupChapterPlan(page: page, decisions: decisions, insertions: insertions, pins: pins)
    }

    /// 대표 고정 대상 — 지금 행이 있고, 그중 `isPresent` 행이 없고, 이 절에 `insertCurrent` 가 없는데 넣는 행이 있으면 지금 대표(`pick(R)`)다.
    ///
    /// `isPresent` 행이 없는 절(1.3.0 legacy)은 대표 규칙이 전체 행에서 고르므로, 보관 행만 넣어도 더 늦은 것이 대표로 올라간다(오케스트레이터 결정 2026-10-06).
    /// - Parameters:
    ///   - verse: 절.
    ///   - rows: 그 절의 지금 저장소 행(`R`).
    ///   - decisions: 그 절 항목들의 결정.
    /// - Returns: 고정할 행. 고정할 필요가 없으면(행 없음 · present 행 있음 · 현재로 넣음 · 넣는 행 없음) nil. 부작용 없음.
    static func representativePin(verse: Int, rows: [BackupRowRecord], decisions: [BackupImportDecision]) -> BackupRepresentativePin? {
        guard !rows.contains(where: { $0.representativeIsPresent }),
              !decisions.contains(.insertCurrent),
              decisions.contains(where: { $0.insertsRow }),
              let representative = DrawingRepresentativeRule.pick(rows) else { return nil }
        return BackupRepresentativePin(verse: verse, rowKey: representative.rowKey)
    }

    /// 한 절(같은 번역 묶음)의 항목을 처리 순서대로 판정한다.
    /// - Parameters:
    ///   - items: 그 절의 항목.
    ///   - rows: 그 절의 지금 저장소 행(`R`).
    ///   - unsupported: 항목 id → 해석할 수 없는 이유.
    /// - Returns: 처리 순서(지원 안 됨 → 현재 후보 → 나머지, 각각 id 순)대로의 항목과 결정. 부작용 없음.
    static func decideVerse(
        _ items: [BackupItem],
        rows: [BackupRowRecord],
        unsupported: [String: BackupUnsupportedReason]
    ) -> [(item: BackupItem, decision: BackupImportDecision)] {
        var judged: [(item: BackupItem, decision: BackupImportDecision)] = []
        var supported: [BackupItem] = []
        for item in items.sorted(by: { $0.id < $1.id }) {
            if let reason = unsupported[item.id] {
                judged.append((item: item, decision: .unsupported(reason)))
            } else {
                supported.append(item)
            }
        }

        // 현재 후보를 맨 앞으로 — 같은 지문이 둘이면 현재 후보가 먼저 자리를 잡는다.
        let candidateIndex = currentCandidateIndex(in: supported)
        var ordered = supported
        if let candidateIndex {
            let candidate = ordered.remove(at: candidateIndex)
            ordered.insert(candidate, at: 0)
        }
        var verse = VerseJudge(rows: rows)
        for (offset, item) in ordered.enumerated() {
            let isCandidate = candidateIndex != nil && offset == 0
            judged.append((item: item, decision: verse.decide(item, isCandidate: isCandidate)))
        }
        return judged
    }

    /// 현재 후보의 자리 — `isCurrent` 항목 중 `updatedAt` 이 가장 늦은 하나(nil 은 가장 이른 시각, 같으면 id 사전순 앞).
    /// - Parameter items: 지원 판정을 통과한 그 절의 항목.
    /// - Returns: `items` 안의 자리. `isCurrent` 항목이 없으면 nil.
    static func currentCandidateIndex(in items: [BackupItem]) -> Int? {
        items.indices.filter { items[$0].isCurrent }.min { lhs, rhs in
            let lhsDate = items[lhs].updatedAt ?? .distantPast
            let rhsDate = items[rhs].updatedAt ?? .distantPast
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            return items[lhs].id < items[rhs].id
        }
    }

    // MARK: - 장 나누기 · 미리보기

    /// 항목이 놓일 장 — 필사책 토큰이 `NotebookID` 형식(없으면 기본 필사책)이고 권 코드가 `BibleBookCode` 에 있고 장이 `1...권.lastChapter`
    /// 일 때만. 번역본은 `placementTranslation` 이다.
    /// - Returns: 장(필사책 · 번역본 포함). 어느 장에도 놓을 수 없으면 nil(미리보기가 알 수 없는 필사책 · 지원 안 됨으로 센다).
    public static func page(of item: BackupItem) -> NotebookChapter? {
        guard let notebook = item.verse.notebookID,
              let title = item.verse.title,
              (1...title.lastChapter).contains(item.verse.chapter) else { return nil }
        let chapter = BibleChapter(title: title, chapter: item.verse.chapter, translation: placementTranslation(item.verse.translation))
        return NotebookChapter(notebook: notebook, chapter: chapter)
    }

    /// 항목이 놓일 장의 번역본 — nil · `NKRV` 는 개역개정(한 묶음), `KJV` · `BSB` 는 그 번역본.
    ///
    /// 모르는 번역본(예: `"ESV"`)은 개역개정 장에 놓는다 — 그 장의 판정에서 지원 안 됨(`unknownTranslation`)으로 세기만 하고 쓰지 않는다
    /// (지원 판정이 먼저라 행을 넣는 결정이 나지 않는다). 2.1 이전과 같은 자리에서 센다.
    /// - Parameter translation: 항목의 번역본 값.
    /// - Returns: 번역본. 부작용 없음.
    static func placementTranslation(_ translation: String?) -> Translation {
        translation.flatMap(Translation.init(rawValue:)) ?? .NKRV
    }

    /// 항목을 장으로 나눈다 — 어느 장에도 놓을 수 없는 항목(알 수 없는 필사책 포함)은 빠진다. 부작용 없음.
    public static func itemsByPage(_ items: [BackupItem]) -> [NotebookChapter: [BackupItem]] {
        var grouped: [NotebookChapter: [BackupItem]] = [:]
        for item in items {
            guard let placed = Self.page(of: item) else { continue }
            grouped[placed, default: []].append(item)
        }
        return grouped
    }

    /// 항목이 놓이는 장 — 필사책(기본 먼저) → 권 순서 → 장 순서 → 번역본 순서, 겹치지 않게. 검사가 장마다 저장소 행을 읽는 순서다.
    public static func pages(of items: [BackupItem]) -> [NotebookChapter] {
        ordered(Array(itemsByPage(items).keys))
    }

    /// 어느 장에도 놓을 수 없는 항목(모르는 권 · 범위 밖 장)의 사유별 수. 알 수 없는 필사책 항목은 여기서 세지 않는다(`unknownNotebookCount`).
    /// - Parameters:
    ///   - items: 백업의 모든 항목.
    ///   - unsupported: 항목 id → 해석할 수 없는 이유. 없으면 `BackupItemSupport` 와 같은 순서(번역본 → 권 → 범위)로 정한다.
    /// - Returns: 사유별 수. 부작용 없음.
    public static func unplaced(items: [BackupItem], unsupported: [String: BackupUnsupportedReason]) -> [BackupUnsupportedReason: Int] {
        var counts: [BackupUnsupportedReason: Int] = [:]
        for item in items where Self.page(of: item) == nil && !BackupItemSupport.hasUnknownNotebook(item) {
            counts[unsupported[item.id] ?? placementReason(item), default: 0] += 1
        }
        return counts
    }

    /// 필사책 토큰이 `NotebookID` 형식이 아니어서 건너뛰는 항목 수(「알 수 없는 필사책」). 권 · 번역본이 함께 틀려도 여기서 한 번만 센다.
    /// - Parameter items: 백업의 모든 항목.
    /// - Returns: 수. 부작용 없음.
    public static func unknownNotebookCount(items: [BackupItem]) -> Int {
        items.filter(BackupItemSupport.hasUnknownNotebook).count
    }

    /// 백업이 담은 필사책 수 — 항목의 필사책(형식이 맞는 토큰 · 없으면 기본 필사책) ∪ 필사책 목록의 필사책(형식이 맞는 ID).
    /// - Parameters:
    ///   - items: 백업의 모든 항목.
    ///   - notebooks: 필사책 목록(`BackupManifest.notebooks`).
    /// - Returns: 수. 항목도 목록도 없으면 0. 부작용 없음.
    public static func notebookCount(items: [BackupItem], notebooks: [BackupNotebookRecord]) -> Int {
        Set(items.compactMap(\.verse.notebookID) + notebooks.compactMap(\.notebookID)).count
    }

    /// 장에 놓을 수 없는 항목의 사유 — 호출부가 넘기지 않았을 때만 쓴다.
    ///
    /// `BackupItemSupport` 와 같은 순서(번역본 → 권 → 범위)다. 장에 놓이지 않는 항목은 권 · 범위 판정에서 끝나 메타데이터를 읽지 않는다.
    static func placementReason(_ item: BackupItem) -> BackupUnsupportedReason {
        BackupItemSupport.reason(item, metadataBytes: { _ in nil }) ?? .outOfRange
    }

    /// 장을 판정하기 전의 파일 수준 미리보기 — 어느 장에도 놓을 수 없는 항목(사유별) · 알 수 없는 필사책 항목 · 필사책 수.
    /// 검사(`LiveBackupImporter`)는 여기에 장마다의 판정을 더한다(`BackupImportPreview.add`).
    /// - Parameters:
    ///   - items: 백업의 모든 항목.
    ///   - unsupported: 항목 id → 해석할 수 없는 이유.
    ///   - notebooks: 필사책 목록.
    /// - Returns: 장 판정이 빠진 미리보기. 부작용 없음.
    public static func filePreview(
        items: [BackupItem],
        unsupported: [String: BackupUnsupportedReason],
        notebooks: [BackupNotebookRecord]
    ) -> BackupImportPreview {
        BackupImportPreview(
            unsupported: unplaced(items: items, unsupported: unsupported),
            unknownNotebook: unknownNotebookCount(items: items),
            notebooks: notebookCount(items: items, notebooks: notebooks)
        )
    }

    /// 파일 전체의 미리보기 — 파일 수준 수(`filePreview`)에 장마다 `plan` 을 돌려 결정별 수를 더한다.
    /// - Parameters:
    ///   - items: 백업의 모든 항목.
    ///   - unsupported: 항목 id → 해석할 수 없는 이유.
    ///   - current: 장마다 지금 저장소 행(`backupRows(page:)` 의 `rows`). 없는 장은 행이 없는 장으로 본다.
    ///   - notebooks: 필사책 목록(필사책 수에만 쓴다).
    /// - Returns: 미리보기. 어느 장에도 놓을 수 없는 항목은 지원 안 됨 · 알 수 없는 필사책으로 센다. 부작용 없음.
    public static func preview(
        items: [BackupItem],
        unsupported: [String: BackupUnsupportedReason],
        current: [NotebookChapter: [BackupRowRecord]],
        notebooks: [BackupNotebookRecord] = []
    ) -> BackupImportPreview {
        var preview = filePreview(items: items, unsupported: unsupported, notebooks: notebooks)
        for (page, pageItems) in itemsByPage(items) {
            preview.add(plan(items: pageItems, unsupported: unsupported, current: current[page] ?? [], page: page))
        }
        return preview
    }

    /// 장을 필사책(기본 먼저 · 나머지 토큰 순) → 권 순서(`BibleTitle.allCases`) → 장 순서 → 번역본 순서(`Translation.allCases`)로 늘어놓는다.
    /// 겹치는 장(같은 필사책 · 번역본)은 하나로.
    static func ordered(_ pages: [NotebookChapter]) -> [NotebookChapter] {
        Array(Set(pages)).sorted(by: NotebookChapter.backupOrder)
    }
}

// MARK: - 절 판정

/// 판정 단위 — 절과 번역 묶음(nil 은 NKRV 와 한 묶음, KJV · BSB 는 각자). 행의 번역은 `backupTranslation`(`titleName` 접두 먼저)이다.
private struct VerseGroup: Hashable, Comparable {
    let verse: Int
    let translation: String

    init(verse: Int, translation: String?) {
        self.verse = verse
        self.translation = translation ?? BackupImportPlanner.nilTranslationGroup
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.verse, lhs.translation) < (rhs.verse, rhs.translation)
    }
}

/// 한 절의 판정 상태 — 지금 저장소의 대표와 이미 있는(또는 넣기로 한) 지문.
private struct VerseJudge {
    /// `DrawingRepresentativeRule.pick(R)`. `R` 이 비었으면 nil.
    let representative: BackupRowRecord?
    /// 지금 행의 지문 + 이 절에 넣기로 한 지문 — 같은 지문은 한 절에 한 번만.
    var fingerprints: Set<String>

    init(rows: [BackupRowRecord]) {
        representative = DrawingRepresentativeRule.pick(rows)
        fingerprints = Set(rows.compactMap(\.contentFingerprint))
    }

    /// 항목 하나를 판정하고, 새 행을 넣기로 했으면 그 지문을 이 절에 넣은 것으로 남긴다.
    mutating func decide(_ item: BackupItem, isCandidate: Bool) -> BackupImportDecision {
        let decision = item.hasInk ? inked(item, isCandidate: isCandidate) : cleared(isCandidate: isCandidate)
        if decision.insertsRow, let fingerprint = item.fingerprint {
            fingerprints.insert(fingerprint)
        }
        return decision
    }

    /// 잉크 있는 항목 — ① 같은 지문 ② 현재 후보 · 잉크 있는 대표 없음(지운 절 보호) ③ 그 밖.
    private func inked(_ item: BackupItem, isCandidate: Bool) -> BackupImportDecision {
        if let fingerprint = item.fingerprint, fingerprints.contains(fingerprint) { return .skipSame }
        guard isCandidate else { return .insertArchived }
        guard let representative else { return .insertCurrent }
        guard !representative.hasInk else { return .insertArchived }
        // 대표가 비운 행 — 이 기기에서 백업보다 뒤에 지웠으면 되살리지 않는다(nil 은 가장 이른 시각).
        let clearedAt = representative.updateDate ?? .distantPast
        let writtenAt = item.updatedAt ?? .distantPast
        return clearedAt > writtenAt ? .protectCleared : .insertCurrent
    }

    /// 비운 항목 — 비어 있던 절만 비운 현재 행으로 채운다. 같은 백업의 잉크 있는 보관 행이 대표로 올라가 지운 필기가 되살아나는 것을 막는다.
    private func cleared(isCandidate: Bool) -> BackupImportDecision {
        guard let representative else { return isCandidate ? .insertCurrent : .skipEmpty }
        return representative.hasInk ? .skipEmpty : .skipSame
    }
}
