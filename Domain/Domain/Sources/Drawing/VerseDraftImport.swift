//
//  VerseDraftImport.swift
//  Domain
//
//  Created by Claude on 9/29/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import CarveToolkit
import Dependencies
import Foundation

// MARK: - 가져온 기록

/// 사용자가 「확인이 필요한 필기」 에서 초안을 **현재 필사로 가져온 기록** — 무엇을 · 어느 계정의 어느 행으로 · 언제
/// (정책 §12-6 ④ 가져오기, 2026-09-29).
///
/// 초안 파일에 함께 남는다(`VerseDraft.imported`). 그 행이 저장소에 남아 있는 동안 그 초안은 역할이 끝났다 — 그 뒤 그 절을 이어 고쳐도
/// 다시 「확인이 필요한 필기」 로 오르지 않는다(`VerseDraftRecoveryRule.standing`). 행이 사라지면(전송 전 계정 전환 — ACC-1 F29) 기록을
/// 믿지 않고 다시 판정한다 — 그때 이 초안이 유일한 사본이다.
public struct VerseDraftImport: Codable, Equatable, Sendable {
    /// 가져온 내용이 들어간 행.
    public var rowID: BibleDrawingRowID
    /// 넣은 내용의 지문. 비운 절을 가져왔으면 nil.
    public var contentFingerprint: String?
    /// 가져온 계정.
    public var account: AccountScope
    public var importedAt: Date

    public init(rowID: BibleDrawingRowID, contentFingerprint: String?, account: AccountScope, importedAt: Date) {
        self.rowID = rowID
        self.contentFingerprint = contentFingerprint
        self.account = account
        self.importedAt = importedAt
    }
}

// MARK: - 가져오면 무엇이 되는가

/// 한 초안을 지금 필사로 가져오면 무엇이 되는가 — 비교 화면이 버튼과 안내를 고르는 판정.
public struct VerseDraftImportCheck: Hashable, Sendable {
    public enum Action: Hashable, Sendable {
        /// 지금 그 절에 필기가 없다 — 이 필기를 넣는다.
        case insert
        /// 지금 그 절에 다른 필기가 있다 — 이 필기로 바꾼다. 지금 필기는 이전 필사 기록으로 남는다.
        case replace
        /// 지금 필기와 같다 — 이미 반영됐다.
        case alreadyApplied
        /// 좌표 정보(놓을 자리)를 읽지 못해 넣을 수 없다.
        case unavailable
    }

    /// 곧바로 넣지 않고 한 번 더 묻는 까닭 — **지웠던 내용이 다시 들어갈 수 있다.**
    public enum Caution: Hashable, Sendable {
        /// 이 필기를 쓴 뒤 그 절이 비워졌다(지우기 · 다른 기기).
        case verseClearedAfterDraft
        /// 이 필기를 쓴 뒤 모든 필사 삭제가 있었다 — 이 필기가 모르던 삭제 기준점을 지금 계정이 안다.
        case eraseAfterDraft
        /// 삭제 기록(삭제 기준점)을 읽지 못했거나 이 필기가 그것을 모른 채 쓰였다 — 판단할 수 없다.
        case eraseHistoryUnknown
    }

    public let action: Action
    public let caution: Caution?
    /// 견준 지금 필기의 지문. 비었으면 nil — 넣을 때 저장소가 이 내용 그대로인지 다시 본다(`VerseDrawingImportCommand`).
    public let currentFingerprint: String?

    public init(action: Action, caution: Caution?, currentFingerprint: String?) {
        self.action = action
        self.caution = caution
        self.currentFingerprint = currentFingerprint
    }
}

/// 가져오기 판정 — 순수 함수라 표로 시험한다.
///
/// - **넣기 · 바꾸기는 그 절의 지금 대표 필기로 가른다.** 행이 없거나 비운 행이면 넣기, 필기가 있으면 바꾸기다. 바꿔도 지금 필기는 지우지 않고
///   이전 필사 기록으로 남는다(`DrawingVerseImporting`).
/// - **지웠던 내용이 다시 들어갈 수 있으면 자동으로 넣지 않고 묻는다**(`Caution`) — 이 필기를 쓴 뒤 그 절이 비워졌거나, 이 필기가 모르던 모든
///   필사 삭제를 지금 계정이 알거나, 그것을 판단할 수 없을 때다.
/// - 한계 — 2.0.0 은 모든 필사 삭제를 삭제 기준점(K)으로 남기지 않는다. 그래서 **다른 기기의 「모든 필사 삭제」 는 이 판정이 알 수 없다.**
public enum VerseDraftImportRule {
    /// - Parameters:
    ///   - draft: 가져올 초안.
    ///   - current: 그 절의 지금 대표 행(`VerseDraftStoreView.representatives`). 없으면 그 절에 행이 없다.
    ///   - knowledge: 지금 계정의 `K(기기)`. nil 은 읽지 못함.
    public static func check(draft: VerseDraft, current: VerseDrawingSnapshot?, knowledge: EraseEpochKnowledge?) -> VerseDraftImportCheck {
        let currentFingerprint = current?.contentFingerprint
        guard VerseDraftRecoveryRule.isDisplayable(draft) else {
            return VerseDraftImportCheck(action: .unavailable, caution: nil, currentFingerprint: currentFingerprint)
        }
        guard draft.contentFingerprint != currentFingerprint else {
            return VerseDraftImportCheck(action: .alreadyApplied, caution: nil, currentFingerprint: currentFingerprint)
        }
        return VerseDraftImportCheck(
            action: currentFingerprint == nil ? .insert : .replace,
            caution: caution(draft: draft, current: current, knowledge: knowledge),
            currentFingerprint: currentFingerprint
        )
    }

    static func caution(draft: VerseDraft, current: VerseDrawingSnapshot?, knowledge: EraseEpochKnowledge?) -> VerseDraftImportCheck.Caution? {
        guard let knowledge else { return .eraseHistoryUnknown }
        if let known = draft.knownEpochs {
            guard EraseEpochRule.isValid(recordKnown: known, device: knowledge) else { return .eraseAfterDraft }
        } else if !knowledge.all.isEmpty {
            return .eraseHistoryUnknown
        }
        // 비운 행이 대표다 — 그 절이 비워진 때(`updateDate`)가 이 필기보다 늦으면 이 필기를 쓴 뒤 지운 것이다.
        if let current, current.lineData == nil, let clearedAt = current.updateDate, clearedAt > draft.savedAt {
            return .verseClearedAfterDraft
        }
        return nil
    }
}

// MARK: - 저장소 쓰기

/// 가져오기의 저장소 쓰기 한 번.
public struct VerseDrawingImportCommand: Equatable, Sendable {
    public let verse: Int
    /// 가져온 내용이 들어갈 **새 행**. 가져오기 한 번에 한 번 발급한다.
    public let rowID: BibleDrawingRowID
    /// 넣을 필기. nil 이면 비운 절이다.
    public let lineData: Data?
    /// 필기의 좌표 정보. 필기가 있으면 있어야 한다.
    public let metadata: DrawingLayoutMetadata?
    /// 사용자가 견준 지금 필기의 지문(비었으면 nil). 저장소가 이 내용 그대로일 때만 쓴다.
    public let expectedCurrentFingerprint: String?

    public init(
        verse: Int, rowID: BibleDrawingRowID, lineData: Data?, metadata: DrawingLayoutMetadata?, expectedCurrentFingerprint: String?
    ) {
        self.verse = verse
        self.rowID = rowID
        self.lineData = lineData
        self.metadata = metadata
        self.expectedCurrentFingerprint = expectedCurrentFingerprint
    }
}

public enum VerseDrawingImportOutcome: Equatable, Sendable {
    /// 새 행으로 넣었다. `previousKept` 면 지금까지의 필기가 이전 필사 기록으로 남았다.
    case imported(previousKept: Bool)
    /// 그 절이 이미 이 내용이다 — 쓰지 않았다.
    case alreadyApplied
    /// 견준 뒤 그 절의 필기가 바뀌었다 — 쓰지 않았다. 다시 견주어야 한다.
    case currentChanged
}

/// 가져오기가 저장소(`BibleDrawing`)에 쓰는 **유일한 길**. `SwiftDataDrawingRepository` 가 구현한다.
///
/// 편집 화면의 저장(`DrawingRepository`)과 나눈 까닭 — 이 쓰기는 사용자가 견주고 고른 뒤에만 일어나고, 읽는 경계(`VerseDraftRecoveryReading`)
/// 와 따로 둬야 목록 조회가 저장소에 쓰는 호출 자체가 만들어지지 않는다.
///
/// **한 트랜잭션**이다 — 가져온 내용을 **새 행**(대표)으로 넣고 그 절의 다른 행은 대표에서 내린다(`isPresent = false`). 지금 필기는 지우지도
/// 덮지도 않는다 — 그 행 그대로 「이전 필사 내용 보기」 에 남아 다시 고를 수 있다. 제자리에서 덮지 않으므로, 가져오기를 모르고 열려 있던
/// 화면이 옛 행에 이어 써도 가져온 필기가 지워지지 않는다(그 획은 옛 행 — 이전 필사 기록에 남는다).
public protocol DrawingVerseImporting: Sendable {
    /// - Parameter generation: 견줄 때 읽은 저장소 세대. 그 뒤 전체 삭제가 있었으면 쓰지 않고 던진다(`staleStoreGeneration`).
    func importVerse(
        _ command: VerseDrawingImportCommand,
        chapter: BibleChapter,
        generation: DrawingStoreGeneration
    ) async throws -> VerseDrawingImportOutcome
}

private enum DrawingVerseImporterKey: DependencyKey {
    /// 앱이 이 실행의 저장소로 만든 구현을 주입한다. 없으면 가져오기를 막는다.
    static let liveValue: (any DrawingVerseImporting)? = nil
    static let testValue: (any DrawingVerseImporting)? = nil
}

/// 가져온 기록을 초안에 남긴다 — `LocalPreservationWriter` 가 구현한다. 초안을 지우는 길은 여기에도 없다.
public protocol VerseDraftImportMarking: Sendable {
    /// - Returns: 기록을 남겼으면 true. 그 사이 초안이 바뀌었거나 사라졌으면 false.
    func markDraftImported(_ key: VerseDraftKey, scope: AccountScope, revision: Int, record: VerseDraftImport) async throws -> Bool
}

extension LocalPreservationWriter: VerseDraftImportMarking {}

private enum VerseDraftImportMarkerKey: DependencyKey {
    static let liveValue: (any VerseDraftImportMarking)? = nil
    static let testValue: (any VerseDraftImportMarking)? = nil
}

public extension DependencyValues {
    /// 「확인이 필요한 필기」 의 가져오기 — 저장소 쓰기.
    var drawingVerseImporter: (any DrawingVerseImporting)? {
        get { self[DrawingVerseImporterKey.self] }
        set { self[DrawingVerseImporterKey.self] = newValue }
    }

    /// 「확인이 필요한 필기」 의 가져오기 — 초안에 남기는 기록.
    var verseDraftImportMarker: (any VerseDraftImportMarking)? {
        get { self[VerseDraftImportMarkerKey.self] }
        set { self[VerseDraftImportMarkerKey.self] = newValue }
    }
}

// MARK: - 가져오기

/// 가져올 초안 하나 — 사용자가 견주고 고른 것.
public struct VerseDraftImportRequest: Equatable, Sendable {
    public let key: VerseDraftKey
    /// 초안이 든 묶음.
    public let scope: AccountScope
    /// 사용자가 본 revision. 그 사이 바뀌었으면 가져오지 않는다.
    public let revision: Int
    /// 사용자가 견준 지금 필기의 지문(비었으면 nil).
    public let expectedCurrentFingerprint: String?
    /// 사용자가 확인한 주의 — 지금 판정의 주의와 같아야 넣는다.
    public let acknowledgedCaution: VerseDraftImportCheck.Caution?

    public init(
        key: VerseDraftKey, scope: AccountScope, revision: Int, expectedCurrentFingerprint: String?,
        acknowledgedCaution: VerseDraftImportCheck.Caution? = nil
    ) {
        self.key = key
        self.scope = scope
        self.revision = revision
        self.expectedCurrentFingerprint = expectedCurrentFingerprint
        self.acknowledgedCaution = acknowledgedCaution
    }

    /// 초안 키가 가리키는 장. 모르는 권이면 nil.
    public var chapter: BibleChapter? {
        BibleTitle(rawValue: key.title).map { BibleChapter(title: $0, chapter: key.chapter) }
    }
}

/// 「확인이 필요한 필기」 의 가져오기 — **넣기 직전에 모든 것을 다시 본다**(2026-09-29).
///
/// 1. 지금 환경이 동기화 저장소에 써도 되는가(`SyncedWriteBlock`) — 로그아웃 · 확인 전 · 소유 근거 없음 · 연결 보류면 쓰지 않는다.
/// 2. 이 환경이 **열어도 되는** 초안인가 — 지금 계정 · 연결 전 필기만(다른 계정 · 다른 계정을 참고하던 필기는 아니다, P0-1).
/// 3. 초안이 사용자가 본 그 revision 그대로인가 — 바뀌었으면 다시 보게 한다.
/// 4. 그 절이 사용자가 견준 내용 그대로인가 — 바뀌었으면 쓰지 않고 다시 견주게 한다. 저장소 트랜잭션 안에서 한 번 더 본다.
/// 5. 지웠던 내용이 다시 들어갈 수 있으면 사용자가 그 주의를 확인했는가.
///
/// **완료는 저장소 저장이 끝난 뒤에만** 알린다. 가져온 기록(초안 표식)을 남기지 못해도 필기는 이미 들어갔으므로 성공이다 — 기록이 없으면 그
/// 절을 나중에 고쳤을 때 그 초안이 다시 오를 뿐 잃는 것은 없다.
public struct VerseDraftImporter: Sendable {
    public enum Result: Equatable, Sendable {
        /// 넣었다. `previousKept` 면 지금까지의 필기가 이전 필사 기록으로 남았다. `recorded` 는 가져온 기록을 남겼는가.
        case imported(previousKept: Bool, recorded: Bool)
        /// 그 절이 이미 이 필기다 — 쓰지 않았다.
        case alreadyApplied
        /// 견준 뒤 그 절의 필기가 바뀌었다 — 쓰지 않았다.
        case currentChanged
        /// 그 사이 초안이 바뀌었거나 사라졌거나 이미 가져왔다 — 쓰지 않았다.
        case draftChanged
        /// 좌표 정보를 읽지 못해 넣을 수 없다.
        case unavailable
        /// 지웠던 내용이 다시 들어갈 수 있다 — 사용자가 이 주의를 확인해야 넣는다.
        case cautionRequired(VerseDraftImportCheck.Caution)
        /// 지금 동기화 저장소에 쓸 수 없다.
        case blocked(SyncedWriteBlock)
    }

    private let reader: any VerseDraftRecoveryReading
    private let repository: any DrawingRepository
    private let writer: any DrawingVerseImporting
    private let marker: any VerseDraftImportMarking
    private let now: @Sendable () -> Date

    public init(
        reader: any VerseDraftRecoveryReading,
        repository: any DrawingRepository,
        writer: any DrawingVerseImporting,
        marker: any VerseDraftImportMarking,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.reader = reader
        self.repository = repository
        self.writer = writer
        self.marker = marker
        self.now = now
    }

    public func importDraft(_ request: VerseDraftImportRequest, environment: DrawingEditEnvironment) async throws -> Result {
        if let block = SyncedWriteBlock.check(environment) { return .blocked(block) }
        guard let chapter = request.chapter else { return .draftChanged }
        let translation = Translation(rawValue: request.key.translation) ?? .NKRV
        guard let draft = try await reader.drafts(in: request.scope, chapter: chapter, translation: translation)
            .first(where: { $0.key == request.key }), draft.revision == request.revision else {
            return .draftChanged
        }
        guard Self.opens(draft, in: request.scope, environment: environment) else { return .blocked(.verseFromOtherSession) }

        let load = try await repository.load(chapter: chapter)
        let view = VerseDraftStoreView(snapshots: load.snapshots)
        if let imported = draft.imported, view.rows[imported.rowID] != nil { return .draftChanged }
        let verse = request.key.verse
        let check = VerseDraftImportRule.check(draft: draft, current: view.representatives[verse], knowledge: environment.knowledge)
        switch check.action {
        case .unavailable:
            return .unavailable
        case .alreadyApplied:
            await record(draft, request: request, rowID: view.representatives[verse]?.rowID, environment: environment)
            return .alreadyApplied
        case .insert, .replace:
            break
        }
        guard check.currentFingerprint == request.expectedCurrentFingerprint else { return .currentChanged }
        if let caution = check.caution, caution != request.acknowledgedCaution { return .cautionRequired(caution) }
        var metadata: DrawingLayoutMetadata?
        if draft.lineData != nil {
            guard let decoded = DrawingLayoutMetadata.decode(blob: draft.layoutMetadataData) else { return .unavailable }
            metadata = decoded
        }
        let command = VerseDrawingImportCommand(
            verse: verse, rowID: .issue(), lineData: draft.lineData, metadata: metadata, expectedCurrentFingerprint: check.currentFingerprint
        )
        switch try await writer.importVerse(command, chapter: chapter, generation: load.generation) {
        case .currentChanged:
            return .currentChanged
        case .alreadyApplied:
            await record(draft, request: request, rowID: view.representatives[verse]?.rowID, environment: environment)
            return .alreadyApplied
        case .imported(let previousKept):
            let recorded = await record(draft, request: request, rowID: command.rowID, environment: environment)
            return .imported(previousKept: previousKept, recorded: recorded)
        }
    }

    /// 이 환경의 「확인이 필요한 필기」 가 여는 초안인가 — 편집 화면이 읽는 묶음의 화면에 오르는 초안, 또는 연결 전 필기.
    static func opens(_ draft: VerseDraft, in scope: AccountScope, environment: DrawingEditEnvironment) -> Bool {
        if environment.readableDraftScopes.contains(scope), VerseDraftRecoveryRule.reachesScreen(draft, environment: environment) { return true }
        return environment.beforeConnectionDraftScopes.contains(scope) && VerseDraftRecoveryRule.awaitsImport(draft, environment: environment)
    }

    /// 가져온 기록을 남긴다. 남기지 못해도 가져오기는 끝났다 — 기록만 없다.
    @discardableResult
    private func record(_ draft: VerseDraft, request: VerseDraftImportRequest, rowID: BibleDrawingRowID?, environment: DrawingEditEnvironment) async -> Bool {
        guard let rowID else { return false }
        let record = VerseDraftImport(
            rowID: rowID, contentFingerprint: draft.contentFingerprint, account: environment.accountBasis.preservationScope, importedAt: now()
        )
        do {
            return try await marker.markDraftImported(request.key, scope: request.scope, revision: request.revision, record: record)
        } catch {
            Log.error("가져오기 — 필기는 넣었지만 초안에 가져온 기록을 남기지 못했다(초안은 남는다)", "\(error)")
            return false
        }
    }
}
