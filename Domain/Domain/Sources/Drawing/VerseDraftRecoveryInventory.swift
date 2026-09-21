//
//  VerseDraftRecoveryInventory.swift
//  Domain
//
//  Created by Claude on 9/21/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import CarveToolkit
import Dependencies
import Foundation

// MARK: - 복구 화면이 읽는 경계

/// 복구 화면(④)이 **읽는** 것 — 묶음 · 요약 · 한 장의 초안 · 읽지 못해 옆으로 옮긴 파일. `LocalPreservationWriter` 가 구현한다.
///
/// 편집 화면의 경계(`VerseDraftStore`)와 나눈 까닭 — 읽기 전용 단계의 복구 화면은 **쓰지 않는다**(사용자 결정 2026-09-21).
/// 되살리기 · 귀속 동의는 ③ 과 같은 시기에 별도의 경계로 붙인다.
public protocol VerseDraftRecoveryReading: Sendable {
    /// 이 기기에 초안이 남은 묶음(계정 범위)들.
    func draftBuckets() async throws -> [AccountScope]
    /// 그 묶음의 개수 · 용량 · 초안이 남은 장.
    func draftSummary(in scope: AccountScope) async throws -> DraftBucketSummary
    /// 그 묶음의 한 장의 초안들. 그 장의 초안을 하나라도 읽지 못하면 던진다.
    func drafts(in scope: AccountScope, chapter: BibleChapter, translation: Translation) async throws -> [VerseDraft]
    /// 읽지 못해 옆으로 옮긴 파일들 — 되살릴 수 없고 내보내기만 한다.
    func unreadableDraftFiles(in scope: AccountScope) async throws -> [URL]
}

/// 복구 화면(④)이 **지울 수 있는 유일한 것** — 읽지 못해 옆으로 옮긴 파일(사용자 결정 2026-09-21).
///
/// 읽는 경계(`VerseDraftRecoveryReading`)와 나눠 둔다. 초안을 지우는 길은 이 화면에 **없다** — 되살리기(③)가 붙기 전에는
/// 그 초안이 유일한 사본일 수 있다(ACC-1 F29). 나누면 실수로 초안을 지우는 호출 자체가 만들어지지 않는다.
public protocol VerseDraftUnreadableCleaning: Sendable {
    /// - Returns: 실제로 지운 파일 수.
    func removeUnreadableDraftFiles(in scope: AccountScope) async throws -> Int
}

extension LocalPreservationWriter: VerseDraftRecoveryReading {}
extension LocalPreservationWriter: VerseDraftUnreadableCleaning {}

private enum VerseDraftUnreadableCleanerKey: DependencyKey {
    static let liveValue: (any VerseDraftUnreadableCleaning)? = nil
    static let testValue: (any VerseDraftUnreadableCleaning)? = nil
}

public extension DependencyValues {
    /// 복구 화면(④)의 읽지 못한 파일 지우기.
    var verseDraftUnreadableCleaner: (any VerseDraftUnreadableCleaning)? {
        get { self[VerseDraftUnreadableCleanerKey.self] }
        set { self[VerseDraftUnreadableCleanerKey.self] = newValue }
    }
}

private enum VerseDraftRecoveryReaderKey: DependencyKey {
    /// 앱이 `LocalPreservationWriter` 를 주입한다. 없으면 복구 화면은 "이 기기의 보존 영역을 열 수 없다" 로 막는다.
    static let liveValue: (any VerseDraftRecoveryReading)? = nil
    static let testValue: (any VerseDraftRecoveryReading)? = nil
}

public extension DependencyValues {
    /// 복구 화면(④)이 읽는 초안.
    var verseDraftRecoveryReader: (any VerseDraftRecoveryReading)? {
        get { self[VerseDraftRecoveryReaderKey.self] }
        set { self[VerseDraftRecoveryReaderKey.self] = newValue }
    }
}

// MARK: - 목록에 오르는 것

/// 복구 화면이 한 초안을 목록에 올리는 까닭 — **왜 이 초안이 그 장을 다시 열어도 자동으로 표시되지 않는가.**
///
/// 자동으로 표시되는 초안(`VerseDraftRecoveryPlan.shown`)과 역할이 끝난 초안(`settled`)은 목록에 넣지 않는다. 남아 있다는 이유만으로 모두 안내하면
/// 사용자가 판단할 것과 판단할 필요 없는 것이 섞인다(사용자 결정 2026-09-21).
public enum VerseDraftRecoveryReason: String, Equatable, Sendable, CaseIterable {
    /// 그 행이 **내가 앞서 넣은 내용**으로 돌아왔다 — 그 뒤 편집은 이 초안에만 있다(F29). 되살릴 수 있는 후보다.
    case recoverable
    /// 저장소로 보내던 중에 앱이 끝났고 그 행이 그 뒤로 바뀌어, **들어갔는지 가릴 수 없다.**
    case uncertain
    /// 저장소의 그 절이 그 뒤로 바뀌었다(다른 기기 · 지우기 · 복원) — 겹치면 그 내용을 본 척 가린다.
    case storeMoved
    /// 근거가 지금 환경과 다르다 — 그 뒤 알게 된 삭제 · 그때 K 를 모름 등. 다른 계정의 초안은 여기 오르지 않는다 — 상세를 만들지 않고
    /// 수만 센다(`VerseDraftRecoveryInventory.inaccessibleCount`).
    case otherBasis
    /// 같은 절의 **더 새 초안**이 화면에 올라 이것은 보이지 않는다.
    case newerDraftShown
}

/// 비교의 한쪽 — 그 절의 지금 저장소 내용. 저장소와 대조하지 않은 묶음이면 없다.
public struct VerseDraftCurrentVerse: Equatable, Sendable {
    public let rowID: BibleDrawingRowID?
    public let contentFingerprint: String?
    public let updatedAt: Date?

    public init(rowID: BibleDrawingRowID?, contentFingerprint: String?, updatedAt: Date?) {
        self.rowID = rowID
        self.contentFingerprint = contentFingerprint
        self.updatedAt = updatedAt
    }

    /// 지금 그 절에 필기가 없다(행이 없거나 비운 행).
    public var isEmpty: Bool { contentFingerprint == nil }
}

/// 목록의 한 줄.
public struct VerseDraftRecoveryEntry: Equatable, Sendable {
    public let draft: VerseDraft
    public let reason: VerseDraftRecoveryReason
    /// 그 절의 지금 필기 — 비교의 한쪽.
    public let current: VerseDraftCurrentVerse?

    public init(draft: VerseDraft, reason: VerseDraftRecoveryReason, current: VerseDraftCurrentVerse?) {
        self.draft = draft
        self.reason = reason
        self.current = current
    }
}

/// 한 묶음의 조회 결과.
public struct VerseDraftRecoveryInventory: Equatable, Sendable {
    public let scope: AccountScope
    /// 파일만 보고 센 것 — 개수 · 용량 · 읽지 못한 파일 · 초안이 남은 장.
    public let summary: DraftBucketSummary
    /// 이 묶음을 지금 환경에서 저장소와 대조했는가. 대조하지 않았으면(다른 계정 · 이 기기 전용) 분류 없이 세어 보이기만 한다 —
    /// 그 계정으로 돌아왔을 때 연다.
    public let comparedWithStore: Bool
    /// 그 장을 다시 열어도 자동으로 표시되지 않는 초안들. 최근에 쓴 것부터. **이 환경에서 열어 볼 수 있는 초안만** 든다.
    public let entries: [VerseDraftRecoveryEntry]
    /// 이 환경에서 **열어 보지 않은** 초안 수 — 다른 계정 · 로그인하지 않은 동안의 묶음 전부, 다른 계정을 참고하던 확인 전 초안.
    /// 상세(잉크 · 자리 · 시각)를 만들지 않고 수만 센다(2026-09-21 후속 리뷰 P0-1). **분류하지 않았다** — "자동으로 표시되지 않는 것" 에 넣지 않는다.
    public let inaccessibleCount: Int
    /// 대조하지 못한 장 — 초안이나 저장소를 읽지 못했다. **파일은 그대로 남는다**(지우지 않는다).
    public let unreadChapters: [BibleChapter]

    public init(
        scope: AccountScope, summary: DraftBucketSummary, comparedWithStore: Bool,
        entries: [VerseDraftRecoveryEntry], inaccessibleCount: Int = 0, unreadChapters: [BibleChapter]
    ) {
        self.scope = scope
        self.summary = summary
        self.comparedWithStore = comparedWithStore
        self.entries = entries
        self.inaccessibleCount = inaccessibleCount
        self.unreadChapters = unreadChapters
    }
}

// MARK: - 조회

/// 복구 화면(④)의 조회 — **초안이 남은 장만** 저장소와 대조해, 편집 화면과 같은 규칙(`VerseDraftRecoveryRule`)으로 분류한다.
///
/// 목록의 기준은 **"그 장을 다시 열어도 자동으로 표시되지 않는 초안"** 이다(2026-09-21 후속 리뷰 확정). 열려 있는 캔버스의 일시적 상태로
/// 목록이 흔들리지 않게 지금 편집 세션 없이(`sessionID: nil`) 판정하고, 판정 입력은 편집 화면과 같게 **읽는 묶음을 모두 합친다**
/// (`VerseDraftRecoveryRule.screenDrafts`).
///
/// - 저장소를 먼저 훑지 않는다. 초안 파일 이름이 어느 장인지 알려 주므로(`DraftBucketSummary.chapters`) 그 장만 읽는다.
/// - **아무것도 쓰지 않는다.** 읽지 못한 장이 있어도 다른 장은 그대로 알리고, 그 장의 파일은 남긴다.
/// - 편집 화면이 읽지 않는 묶음은 저장소와 대조하지 않고 **상세도 만들지 않는다** — 지금 저장소의 내용은 그 계정의 것이 아니고, 그 계정의
///   필기를 이 계정의 화면 상태에 담지 않는다(P0-1). 수 · 용량만 둔다.
public struct VerseDraftRecoveryQuery: Sendable {
    private let reader: any VerseDraftRecoveryReading
    private let repository: any DrawingRepository

    public init(reader: any VerseDraftRecoveryReading, repository: any DrawingRepository) {
        self.reader = reader
        self.repository = repository
    }

    /// 한 묶음에서 그 장을 다시 열어도 **자동으로 표시되지 않는** 초안.
    /// - Parameters:
    ///   - scope: 볼 묶음.
    ///   - environment: 지금 편집 환경 — 무엇이 화면에 보이는지를 가리는 기준이다.
    public func inventory(
        in scope: AccountScope,
        environment: DrawingEditEnvironment,
        translation: Translation = .NKRV
    ) async throws -> VerseDraftRecoveryInventory {
        let summary = try await reader.draftSummary(in: scope)
        guard environment.readableDraftScopes.contains(scope) else {
            // 이 환경이 읽지 않는 묶음(다른 계정 · 로그인하지 않은 동안 등) — **상세를 만들지 않는다.** 초안 파일을 열지도 않고 수 · 용량만 둔다.
            // 잉크를 화면 상태에 담으면 가려 그려도 다른 계정의 필기가 이 계정의 화면 상태에 남는다(2026-09-21 후속 리뷰 P0-1).
            return VerseDraftRecoveryInventory(
                scope: scope, summary: summary, comparedWithStore: false, entries: [], inaccessibleCount: summary.draftCount, unreadChapters: []
            )
        }
        var entries: [VerseDraftRecoveryEntry] = []
        var inaccessible = 0
        var unread: [BibleChapter] = []
        for chapter in summary.chapters {
            do {
                let result = try await self.entries(chapter: chapter, scope: scope, environment: environment, translation: translation)
                entries += result.entries
                inaccessible += result.inaccessible
            } catch {
                // 한 장을 읽지 못해도 나머지는 알린다 — 목록 전체를 막으면 멀쩡한 초안까지 보이지 않는다. 파일은 그대로 둔다.
                Log.error("초안 복구 — 이 장을 대조하지 못했다", "\(chapter.title.rawValue).\(chapter.chapter)", "\(error)")
                unread.append(chapter)
            }
        }
        return VerseDraftRecoveryInventory(
            scope: scope, summary: summary, comparedWithStore: true,
            entries: entries.sorted(by: Self.newestFirst), inaccessibleCount: inaccessible, unreadChapters: unread
        )
    }

    /// 비교의 한쪽 — 그 절의 **지금 대표 행**(필기 바이트까지).
    ///
    /// 목록은 지금 필기의 바이트를 들고 있지 않다(절마다 들면 목록 하나가 장 전체를 메모리에 올린다). 카드를 열어 견줄 때
    /// 그 장만 읽는다. 행이 없거나 비운 절이면 nil 이다 — "지금 그 절에는 필기가 없다" 는 뜻이다.
    public func currentVerse(chapter: BibleChapter, verse: Int) async throws -> VerseDrawingSnapshot? {
        VerseDraftStoreView(snapshots: try await repository.load(chapter: chapter).snapshots).representatives[verse]
    }

    /// 한 장의 결과 — 목록에 오를 초안과, 이 환경에서 열어 보지 않은 초안 수.
    private struct ChapterEntries {
        var entries: [VerseDraftRecoveryEntry] = []
        var inaccessible = 0
    }

    /// 한 장에서 자동으로 표시되지 않는 이 묶음의 초안들. 초안이나 저장소를 읽지 못하면 던진다 — 부르는 쪽이 "대조하지 못한 장" 으로 남긴다.
    private func entries(
        chapter: BibleChapter,
        scope: AccountScope,
        environment: DrawingEditEnvironment,
        translation: Translation
    ) async throws -> ChapterEntries {
        let drafts = try await reader.drafts(in: scope, chapter: chapter, translation: translation)
        // 힌트가 다른 확인 전 초안은 편집 화면에도 오르지 않는다 — 다른 계정의 필기일 수 있어 **상세를 만들지 않고 수만 센다**(P0-1).
        var result = ChapterEntries(inaccessible: drafts.count { !VerseDraftRecoveryRule.reachesScreen($0, environment: environment) })
        guard result.inaccessible < drafts.count else { return result }
        // 편집 화면과 **같은 입력**으로 판정한다 — 이 환경이 읽는 묶음을 모두 합쳐 한 번(2026-09-21 후속 리뷰 P0-2a). 이 묶음만 넣으면 다른 묶음의
        // 더 새 초안에 밀려 캔버스에 보이지 않는 초안이 여기서는 유일한 후보라 "보인다" 로 빠진다.
        let screen = try await VerseDraftRecoveryRule.screenDrafts(environment: environment) { readable in
            readable == scope ? drafts : try await reader.drafts(in: readable, chapter: chapter, translation: translation)
        }
        // 결과는 묶음별로 나눈다 — 이 묶음의 초안만 이 묶음의 목록에 오른다.
        let mine = screen.filter { $0.scope == scope }.map(\.draft)
        let view = VerseDraftStoreView(snapshots: try await repository.load(chapter: chapter).snapshots)
        // 지금 편집 세션은 없다 — 복구 화면은 캔버스가 아니다. 열려 있는 세션의 초안도 "그 장을 다시 열면 자동으로 표시되는가" 로 같이 가린다.
        let plan = VerseDraftRecoveryRule.plan(
            drafts: screen.map(\.draft), storeContent: view.verseContent, environment: environment, sessionID: nil, storeRows: view.rows
        )
        let recoverable = Set(plan.recoverable.map(\.ref))
        let uncertain = Set(plan.uncertain.map(\.ref))
        for draft in plan.kept where mine.contains(draft) {
            result.entries.append(VerseDraftRecoveryEntry(
                draft: draft,
                reason: Self.reason(for: draft, recoverable: recoverable, uncertain: uncertain, view: view, environment: environment),
                current: view.currentVerse(draft.key.verse)
            ))
        }
        return result
    }

    /// 왜 이 초안이 자동으로 표시되지 않는가 — 판정 자체는 편집 화면과 같은 규칙이 이미 했다. 여기서는 그 까닭만 읽는다.
    private static func reason(
        for draft: VerseDraft,
        recoverable: Set<VerseDraftRef>,
        uncertain: Set<VerseDraftRef>,
        view: VerseDraftStoreView,
        environment: DrawingEditEnvironment
    ) -> VerseDraftRecoveryReason {
        if recoverable.contains(draft.ref) { return .recoverable }
        if uncertain.contains(draft.ref) { return .uncertain }
        guard VerseDraftRecoveryRule.continuation(of: draft, environment: environment) != nil else { return .otherBasis }
        let verseContent = view.verseContent[draft.key.verse]
        switch VerseDraftRecoveryRule.standing(of: draft, verseContent: verseContent, rows: view.rows) {
        case .candidate where draft.baseFingerprint == verseContent,
             .orphaned where verseContent == nil || verseContent == draft.baseFingerprint:
            // 근거도 기준도 맞았다 — 같은 절의 더 새 초안이 화면에 올라 이것이 밀렸다.
            return .newerDraftShown
        default:
            return .storeMoved
        }
    }

    /// 최근에 쓴 초안부터. 같은 시각이면 권 · 장 · 절 · 세션 순이다(같은 목록을 두 번 열어도 순서가 같다).
    private static func newestFirst(_ lhs: VerseDraftRecoveryEntry, _ rhs: VerseDraftRecoveryEntry) -> Bool {
        if lhs.draft.savedAt != rhs.draft.savedAt { return lhs.draft.savedAt > rhs.draft.savedAt }
        let left = lhs.draft.key, right = rhs.draft.key
        return (left.title, left.chapter, left.verse, left.sessionID) < (right.title, right.chapter, right.verse, right.sessionID)
    }
}

public extension VerseDraftStoreView {
    /// 그 절의 지금 필기 — 비교의 한쪽.
    func currentVerse(_ verse: Int) -> VerseDraftCurrentVerse {
        VerseDraftCurrentVerse(
            rowID: representatives[verse]?.rowID, contentFingerprint: verseContent[verse], updatedAt: representatives[verse]?.updateDate
        )
    }
}
