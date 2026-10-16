//
//  BackupExportItems.swift
//  Domain
//
//  내보내기의 한 장 — 저장소 행과 열 수 있는 초안을 백업 항목(`BackupItem`)으로 바꾼다 (설계 docs/backup-import-design.md §3-3 · §3-4).
//  장은 필사책 안의 장(`NotebookChapter`)이다 — 항목의 절 키에 필사책 토큰을 담는다(형식 2).
//  파일을 쓰지 않는다 — 항목과 그 항목이 가리키는 blob 바이트를 돌려주고, 쓰기는 `BackupExportStaging` 이 한다.
//

import CarveToolkit
import Foundation

/// 한 장 안의 절 묶음 — 번역본(없으면 NKRV 와 한 묶음) + 절 번호 (설계 §5-1 판정 단위와 같다).
///
/// 행의 번역본은 `BackupRowRecord.backupTranslation`(`titleName` 접두 먼저 — 영어 행은 열이 nil 이어도 KJV · BSB 묶음), 초안은 키의 값이다.
struct BackupExportVerseSlot: Hashable {
    /// 번역 — 값이 없으면 NKRV 로 본다(묶음 판정에만 쓰고, 항목에는 값 그대로 담는다).
    let translation: String
    /// 절.
    let verse: Int

    init(translation: String?, verse: Int) {
        self.translation = translation ?? Translation.NKRV.rawValue
        self.verse = verse
    }
}

/// 한 장에서 담기로 한 초안 하나 — 읽은 묶음과 「화면에 겹치던 것(shown)」 인지.
struct BackupExportDraft: Equatable {
    /// 읽은 묶음(`acct-local` · `acct-unverified` · 확인된 계정).
    let scope: AccountScope
    /// 초안 원본.
    let draft: VerseDraft
    /// 분류가 shown 이면 true — 그 절의 행은 모두 현재가 아니다.
    let isCurrent: Bool
}

/// 항목 하나와 그 항목이 가리키는 blob(이름 · 크기 · 해시와 바이트). 같은 이름의 blob 은 준비 폴더에 한 번만 쓴다.
struct BackupExportCandidate {
    /// blob 하나.
    struct Blob {
        let entry: BackupBlobEntry
        let bytes: Data
    }

    let item: BackupItem
    let blobs: [Blob]
}

/// 한 장의 행 · 초안을 항목으로 바꾸는 순수 규칙.
enum BackupExportItems {
    /// 한 장의 항목 — 행(절 → 행 키 순) 다음 초안(절 → 묶음 → 세션 → revision 순).
    ///
    /// - 행: 그 절(번역 · 절)의 `DrawingRepresentativeRule` 대표만 `isCurrent` — **비운 대표도 true**(지운 상태도 원본이다). 그 절에 shown 초안이
    ///   있으면 그 절의 행은 모두 false 다. 행의 번역은 `backupTranslation` 이다(영어 행은 `titleName` 접두).
    /// - 절 키의 필사책은 그 장의 필사책이다(`BackupVerseKey.token(for:)` — 기본 필사책은 키를 쓰지 않는다). 초안은 지금 기본 필사책 장에서만 고른다
    ///   (`LiveBackupExporter` — 다른 필사책 초안은 t4).
    /// - 같은 id(같은 행 키 · 같은 내용)의 행이 둘이면 하나만 담는다 — 대표였던 쪽, 없으면 앞의 것. 파일 안 id 는 겹칠 수 없다(설계 §4-2).
    /// - Parameters:
    ///   - page: 그 장(필사책 · 번역본 포함).
    ///   - rows: 그 장의 행 원본(`SwiftDatabaseActor.backupRows(page:)`).
    ///   - drafts: 담기로 한 초안(`BackupExportDraftSelection.select`).
    /// - Returns: 항목과 blob. 부작용 없음.
    static func candidates(page: NotebookChapter, rows: [BackupRowRecord], drafts: [BackupExportDraft]) -> [BackupExportCandidate] {
        let shownSlots = Set(drafts.filter(\.isCurrent).map { BackupExportVerseSlot(translation: $0.draft.key.translation, verse: $0.draft.key.verse) })
        let representatives = representativeIndices(rows)
        let notebook = BackupVerseKey.token(for: page.notebook)
        let title = page.chapter.title
        let rowCandidates = rows.enumerated().map { index, record in
            let slot = BackupExportVerseSlot(translation: record.backupTranslation, verse: record.verse)
            return rowCandidate(record, title: title, notebook: notebook, isCurrent: representatives.contains(index) && !shownSlots.contains(slot))
        }
        let draftCandidates = drafts.sorted(by: draftOrder).map { draftCandidate($0, title: title, notebook: notebook) }
        return uniqueByID(rowCandidates) + draftCandidates
    }

    /// 절 묶음마다 대표 행의 위치. 같은 값의 행이 둘이면 앞의 것 하나만.
    static func representativeIndices(_ rows: [BackupRowRecord]) -> Set<Int> {
        var groups: [BackupExportVerseSlot: [Int]] = [:]
        for (index, row) in rows.enumerated() {
            groups[BackupExportVerseSlot(translation: row.backupTranslation, verse: row.verse), default: []].append(index)
        }
        var result: Set<Int> = []
        for indices in groups.values {
            guard let picked = DrawingRepresentativeRule.pick(indices.map { rows[$0] }),
                  let index = indices.first(where: { rows[$0] == picked }) else { continue }
            result.insert(index)
        }
        return result
    }

    /// 행 항목 — 바이트 · `drawingVersion` · 시각 · 번역 저장값을 원본 그대로 담는다. 지문은 원본 바이트로 만든 `contentFingerprint` 다.
    ///
    /// 절 키의 번역본은 `backupTranslation`(영어 행은 `titleName` 접두의 `"KJV"` · `"BSB"`, 개역개정 행은 열 값 그대로 — nil 은 null)이고,
    /// 권은 `titleName` 을 `StoredBookKey.decodeRow` 로 푼 권이다(풀 수 없으면 장의 권). 필사책은 장의 필사책 토큰(기본은 nil)이다.
    /// 출처의 `titleName` 은 원문 그대로 남긴다(다른 필사책 행은 `nb_<토큰>~` 접두 포함).
    static func rowCandidate(_ record: BackupRowRecord, title: BibleTitle, notebook: String?, isCurrent: Bool) -> BackupExportCandidate {
        let ink = blob(record.lineData)
        let metadata = blob(record.layoutMetadataData)
        let book = StoredBookKey.decodeRow(record.titleName)?.title ?? title
        let item = BackupItem(
            id: BackupItemID.make(kind: .row, sourceKey: record.rowKey, fingerprint: record.contentFingerprint),
            kind: .row,
            verse: BackupVerseKey(
                translation: record.backupTranslation, title: book, chapter: record.chapter, verse: record.verse, notebook: notebook
            ),
            drawingVersion: record.drawingVersion,
            inkBlob: ink?.entry.name,
            metadataBlob: metadata?.entry.name,
            fingerprint: record.contentFingerprint,
            isCurrent: isCurrent,
            createdAt: record.creationDate,
            updatedAt: record.updateDate,
            source: BackupItemSource(titleName: record.titleName, rowKey: record.rowKey)
        )
        return BackupExportCandidate(item: item, blobs: [ink, metadata].compactMap { $0 })
    }

    /// 초안 항목 — 만든 시각은 없고(`createdAt` nil) `updatedAt` 은 초안을 남긴 시각이다. 묶음은 종류(local · unverified · account)로만 남긴다.
    /// 필사책은 장의 필사책 토큰(기본은 nil)이다.
    static func draftCandidate(_ selected: BackupExportDraft, title: BibleTitle, notebook: String?) -> BackupExportCandidate {
        let draft = selected.draft
        let scope = BackupItemSource.DraftScope(scope: selected.scope)
        let fingerprint = draft.lineData.map {
            VerseContentFingerprint.make(lineData: $0, drawingVersion: draft.drawingVersion, layoutMetadataBlob: draft.layoutMetadataData)
        }
        let sourceKey = BackupItemID.draftSourceKey(
            draftScope: scope.rawValue,
            sessionID: draft.key.sessionID,
            translation: draft.key.translation,
            title: draft.key.title,
            chapter: draft.key.chapter,
            verse: draft.key.verse,
            revision: draft.revision
        )
        let ink = blob(draft.lineData)
        let metadata = blob(draft.layoutMetadataData)
        let item = BackupItem(
            id: BackupItemID.make(kind: .draft, sourceKey: sourceKey, fingerprint: fingerprint),
            kind: .draft,
            verse: BackupVerseKey(
                translation: draft.key.translation, title: title, chapter: draft.key.chapter, verse: draft.key.verse, notebook: notebook
            ),
            drawingVersion: draft.drawingVersion,
            inkBlob: ink?.entry.name,
            metadataBlob: metadata?.entry.name,
            fingerprint: fingerprint,
            isCurrent: selected.isCurrent,
            createdAt: nil,
            updatedAt: draft.savedAt,
            source: BackupItemSource(titleName: draft.key.title, draftScope: scope.rawValue, draftRevision: draft.revision)
        )
        return BackupExportCandidate(item: item, blobs: [ink, metadata].compactMap { $0 })
    }

    /// 바이트의 blob(이름 · 크기 · 해시). 바이트가 없으면 nil.
    private static func blob(_ bytes: Data?) -> BackupExportCandidate.Blob? {
        bytes.map { BackupExportCandidate.Blob(entry: BackupBlobEntry(bytes: $0), bytes: $0) }
    }

    /// 같은 id 의 행 항목은 하나만 — 대표였던 쪽, 없으면 앞의 것. 남는 순서는 그대로다.
    private static func uniqueByID(_ candidates: [BackupExportCandidate]) -> [BackupExportCandidate] {
        var keep: [String: Int] = [:]
        for (index, candidate) in candidates.enumerated() {
            guard let kept = keep[candidate.item.id] else {
                keep[candidate.item.id] = index
                continue
            }
            if candidate.item.isCurrent, !candidates[kept].item.isCurrent {
                keep[candidate.item.id] = index
            }
        }
        let kept = Set(keep.values)
        if kept.count < candidates.count {
            Log.error("백업 — 행 키와 내용이 같은 행이 겹쳐 하나만 담는다", "겹친 수=\(candidates.count - kept.count)")
        }
        return candidates.enumerated().filter { kept.contains($0.offset) }.map(\.element)
    }

    /// 초안 항목 순서 — 절 → 묶음 → 세션 → revision.
    private static func draftOrder(_ lhs: BackupExportDraft, _ rhs: BackupExportDraft) -> Bool {
        (lhs.draft.key.verse, lhs.scope.key, lhs.draft.key.sessionID, lhs.draft.revision)
            < (rhs.draft.key.verse, rhs.scope.key, rhs.draft.key.sessionID, rhs.draft.revision)
    }
}

/// 한 장에서 담을 초안을 고른다 — 「확인이 필요한 필기」 목록(`VerseDraftRecoveryQuery.inventory`)과 **같은 입력 · 같은 판정**이다 (설계 §3-4).
///
/// | 분류 | 판정 | 담나 | `isCurrent` |
/// |---|---|---|---|
/// | settled | `plan` | 뺀다 | — |
/// | shown | `plan` | 담는다 | true(그 절의 행은 false) |
/// | kept(recoverable · uncertain · undisplayable · archived 포함) | `plan` | 담는다 | false |
/// | 연결 전 필기 — awaiting · undisplayable · archived | `importPlan` | 담는다 | false |
/// | 연결 전 필기 — settled | `importPlan` | 뺀다 | — |
///
/// 편집 화면이 읽는 묶음은 `screenDrafts` 로 **모두 합쳐** 지금 편집 세션 없이(`sessionID: nil`) 판정하고, 확인된 계정의 연결 전 묶음은
/// `beforeConnectionDrafts` → `importPlan` 으로 가른다. 다른 계정 묶음 · 다른 계정을 참고하던 확인 전 초안은 두 판정 어디에도 들지 않아 담지 않는다(P0-1).
/// 원시 사본 · 분리본은 초안 폴더 밖이고, 읽지 못해 옆으로 옮긴 파일(`*.unreadable-*`)은 초안 읽기가 열지 않는다.
///
/// 초안은 **장의 번역본 하나**로 읽는다(`drafts(in:chapter:translation: chapter.translation)`) — 저장소 쪽 입력(`rows`)도 그 번역본 장의 행이라
/// 같은 번역본끼리 견준다. 모든 번역본의 초안을 담는 것은 부르는 쪽(`LiveBackupExporter`)이 권 · 장마다 `Translation.allCases` 를 돌며 한다.
enum BackupExportDraftSelection {
    /// - Parameters:
    ///   - chapter: 그 장(번역본 포함 — 이 번역본의 초안만 읽는다).
    ///   - environment: 그 장을 읽을 때의 편집 환경(장마다 다시 읽은 것).
    ///   - rows: 그 장(같은 번역본)의 저장소 행 원본 — 판정의 저장소 쪽 입력(절마다 대표 내용 · 행 · 이력 지문)을 만든다.
    ///   - reader: 초안 읽기(`LocalPreservationWriter`).
    /// - Returns: 담을 초안. 부작용 없음(읽기만 한다).
    /// - Throws: 그 장의 초안 파일을 하나라도 읽지 못하면 그 오류 — 부르는 쪽이 내보내기를 실패로 끝낸다(조용히 빼지 않는다, 설계 §3-4).
    static func select(
        chapter: BibleChapter,
        environment: DrawingEditEnvironment,
        rows: [BackupRowRecord],
        reader: any VerseDraftRecoveryReading
    ) async throws -> [BackupExportDraft] {
        let read: (AccountScope) async throws -> [VerseDraft] = { scope in
            try await reader.drafts(in: scope, chapter: chapter, translation: chapter.translation)
        }
        let screen = try await VerseDraftRecoveryRule.screenDrafts(environment: environment, read: read)
        let beforeConnection = try await VerseDraftRecoveryRule.beforeConnectionDrafts(environment: environment, read: read)
        guard !screen.isEmpty || !beforeConnection.isEmpty else { return [] }
        let view = VerseDraftStoreView(snapshots: rows.map(\.recoveryRuleSnapshot))
        var selected: [BackupExportDraft] = []
        if !screen.isEmpty {
            let plan = VerseDraftRecoveryRule.plan(
                drafts: screen.map(\.draft), storeContent: view.verseContent, environment: environment, sessionID: nil,
                storeRows: view.rows, storeHistory: view.history
            )
            for scoped in screen where !plan.settled.contains(scoped.draft) {
                selected.append(BackupExportDraft(scope: scoped.scope, draft: scoped.draft, isCurrent: plan.shown.contains(scoped.draft)))
            }
        }
        if !beforeConnection.isEmpty {
            let plan = VerseDraftRecoveryRule.importPlan(drafts: beforeConnection.map(\.draft), view: view)
            for scoped in beforeConnection where !plan.settled.contains(scoped.draft) {
                selected.append(BackupExportDraft(scope: scoped.scope, draft: scoped.draft, isCurrent: false))
            }
        }
        return selected
    }
}

extension BackupRowRecord {
    /// 초안 분류(`VerseDraftRecoveryRule`)의 저장소 쪽 입력 — 장 조회(`loadDrawingSnapshots`)와 **같은 변환**이다.
    ///
    /// 편집 화면 · 「확인이 필요한 필기」 가 같은 행을 이 모양(해석한 메타데이터로 만든 지문)으로 견주므로, 같은 판정을 하려면 같은 입력이어야 한다.
    /// 판정에만 쓴다 — 백업 항목은 원본(`BackupRowRecord`) 그대로 담는다.
    var recoveryRuleSnapshot: VerseDrawingSnapshot {
        VerseDrawingSnapshot(
            verse: verse,
            rowID: BibleDrawingRowID(raw: rowKey),
            isPresent: isPresent ?? false,
            updateDate: updateDate,
            lineData: lineData,
            drawingVersion: drawingVersion,
            metadata: DrawingLayoutMetadata.decode(blob: layoutMetadataData)
        )
    }
}

extension BackupItemSource.DraftScope {
    /// 읽은 묶음의 종류 — 계정 해시는 남기지 않는다.
    init(scope: AccountScope) {
        if scope == .localOnly {
            self = .local
        } else if scope == .unverified {
            self = .unverified
        } else {
            self = .account
        }
    }
}

extension BibleChapter {
    /// 백업의 장 순서 — 권 순서(`BibleTitle.allCases`) → 장 순서 → 번역본 순서(`Translation.allCases`).
    static func backupOrder(_ lhs: BibleChapter, _ rhs: BibleChapter) -> Bool {
        let left = backupTitleOrder[lhs.title] ?? 0
        let right = backupTitleOrder[rhs.title] ?? 0
        if left != right { return left < right }
        if lhs.chapter != rhs.chapter { return lhs.chapter < rhs.chapter }
        return (backupTranslationOrder[lhs.translation] ?? 0) < (backupTranslationOrder[rhs.translation] ?? 0)
    }

    /// 권 · 장 자리 — 번역본을 개역개정으로 맞춘 장. 내보내기는 이 자리마다 번역본을 모두 돈다.
    var backupPlace: BibleChapter {
        BibleChapter(title: title, chapter: chapter)
    }

    /// 이 자리의 번역본별 장 — `Translation.allCases` 순서.
    var backupTranslationChapters: [BibleChapter] {
        Translation.allCases.map { BibleChapter(title: title, chapter: chapter, translation: $0) }
    }

    /// 장 목록을 권 · 장 자리로 줄인다 — 같은 권 · 장이 번역본별로 여러 번 와도(초안 요약 · 행 목록) 한 번만, 권 → 장 순서.
    /// - Parameter chapters: 번역본이 섞인 장 목록.
    /// - Returns: 자리 목록(번역본은 개역개정으로 맞춘다). 부작용 없음.
    static func backupPlaces(_ chapters: some Sequence<BibleChapter>) -> [BibleChapter] {
        Set(chapters.map(\.backupPlace)).sorted(by: backupOrder)
    }

    /// 권 → 순서.
    private static let backupTitleOrder: [BibleTitle: Int] = Dictionary(
        uniqueKeysWithValues: BibleTitle.allCases.enumerated().map { ($1, $0) }
    )

    /// 번역본 → 순서.
    private static let backupTranslationOrder: [Translation: Int] = Dictionary(
        uniqueKeysWithValues: Translation.allCases.enumerated().map { ($1, $0) }
    )
}

extension NotebookChapter {
    /// 백업의 장 순서 — 필사책(기본 먼저 · 나머지 토큰 순) → 권 순서 → 장 순서 → 번역본 순서(`BibleChapter.backupOrder`).
    static func backupOrder(_ lhs: NotebookChapter, _ rhs: NotebookChapter) -> Bool {
        if lhs.notebook != rhs.notebook { return NotebookID.backupOrder(lhs.notebook, rhs.notebook) }
        return BibleChapter.backupOrder(lhs.chapter, rhs.chapter)
    }

    /// 필사책 · 권 · 장 자리 — 번역본을 개역개정으로 맞춘 장. 내보내기는 이 자리마다 번역본을 모두 돈다.
    var backupPlace: NotebookChapter {
        NotebookChapter(notebook: notebook, chapter: chapter.backupPlace)
    }

    /// 이 자리의 번역본별 장 — `Translation.allCases` 순서, 필사책은 그대로.
    var backupTranslationPages: [NotebookChapter] {
        chapter.backupTranslationChapters.map { NotebookChapter(notebook: notebook, chapter: $0) }
    }

    /// 장 목록을 필사책 · 권 · 장 자리로 줄인다 — 같은 필사책의 같은 권 · 장이 번역본별로 여러 번 와도 한 번만, 필사책 → 권 → 장 순서.
    /// - Parameter pages: 번역본이 섞인 장 목록.
    /// - Returns: 자리 목록(번역본은 개역개정으로 맞춘다). 부작용 없음.
    static func backupPlaces(_ pages: some Sequence<NotebookChapter>) -> [NotebookChapter] {
        Set(pages.map(\.backupPlace)).sorted(by: backupOrder)
    }
}
