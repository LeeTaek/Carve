//
//  LocalPreservationWriter.swift
//  Domain
//
//  Created by Claude on 9/18/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import CarveToolkit
import Dependencies
import Foundation

/// 초안 하나를 가리키는 키 — 세션 · 번역 · 권 · 장 · 절 (정책 §12-6 구현 순서 ②).
public struct VerseDraftKey: Hashable, Codable, Sendable {
    public var sessionID: String
    public var translation: String
    public var title: String
    public var chapter: Int
    public var verse: Int

    public init(sessionID: String, translation: Translation = .NKRV, chapter: BibleChapter, verse: Int) {
        self.sessionID = sessionID
        self.translation = translation.rawValue
        self.title = chapter.title.rawValue
        self.chapter = chapter.chapter
        self.verse = verse
    }

    /// 파일 이름. 구성요소에 경로 구분자가 들어오지 않게 바꾼다.
    var fileName: String {
        Self.fileStem([translation, title, "\(chapter)", "\(verse)"]) + ".json"
    }

    /// 한 장의 초안 파일 이름이 모두 이것으로 시작한다 — 파일을 열지 않고 장으로 거른다.
    static func chapterFilePrefix(translation: Translation, chapter: BibleChapter) -> String {
        fileStem([translation.rawValue, chapter.title.rawValue, "\(chapter.chapter)"]) + "~"
    }

    private static func fileStem(_ components: [String]) -> String {
        components.map { $0.replacingOccurrences(of: "/", with: "_") }.joined(separator: "~")
    }

    /// 파일 이름이 가리키는 장 — 파일을 열지 않고 읽는다(깨진 초안도 어느 장인지는 안다). 모양이 다르면 nil.
    static func chapter(fromFileName name: String) -> BibleChapter? {
        let parts = name.replacingOccurrences(of: ".json", with: "").split(separator: "~", omittingEmptySubsequences: false)
        guard parts.count == 4, let title = BibleTitle(rawValue: String(parts[1])), let chapter = Int(parts[2]) else { return nil }
        return BibleChapter(title: title, chapter: chapter)
    }
}

/// 절 하나의 초안 — 그 절의 **완전한** 획 집합과, 그것을 쓴 편집 문맥의 근거를 함께 든다.
public struct VerseDraft: Codable, Equatable, Sendable {
    public var key: VerseDraftKey
    public var revision: Int
    /// 이 내용이 가는 행. 저장소에 행이 없던 절이면 편집이 미리 발급한 새 행이다 — 다시 열어도 같은 행으로 이어 쓴다.
    public var rowID: BibleDrawingRowID
    public var lineData: Data?
    public var drawingVersion: Int?
    public var layoutMetadataData: Data?
    /// 편집을 시작할 때 보던 기준과 그 내용 지문. 다시 열 때 저장소의 내용이 이 기준과 같을 때만 이어서 보여 준다.
    public var base: VerseEditBase
    public var baseFingerprint: String?
    public var account: VerseEditAccountBasis
    public var knownEpochs: Set<String>?
    public var storeOwnership: AccountScope?
    /// 이 초안이 기댄 로컬 삭제 세대. 그 뒤 전체 삭제가 있었으면 쓰지 않는다.
    public var eraseGeneration: UInt64
    public var savedAt: Date
    /// 이 revision 을 저장소(`BibleDrawing`)로 보냈는가 — 영속 표식이다. 어느 세션이 읽어도 그 행의 지금 내용과 견주어, 역할이 끝났는지 ·
    /// 되살릴 사본인지 · 저장 완료가 불확실한지를 가린다(`VerseDraftRecoveryRule`). **지우는 근거는 아니다**(ACC-1 F29). nil 이면 보낸 적 없다.
    public var storeState: VerseDraftStoreState?
    /// 소유 근거가 시험용 주입이었다(`DrawingEditEnvironment.ownershipInjected`). 주입 없는 실행은 이 초안의 소유 근거를 없는 것으로 읽는다.
    public var ownershipInjected: Bool?
    /// **저장소에 넣은 내용의 지문들**(최근 것부터). 표식을 남길 때마다 그때 넣은 내용을 적는다.
    ///
    /// 표식(`storeState`)만으로는 "무엇을 넣었는지" 를 모른다. 그래서 계정 전환으로 그 행이 **내가 앞서 넣은 내용**으로 돌아왔을 때
    /// (ACC-1 2차 ⑪ — 전송 전 수정이 사라지고 서버 내용이 돌아온다) 그 뒤 편집을 남의 변경과 구분하지 못해 감췄다. 이 목록이 있으면
    /// 돌아온 행이 내가 넣었던 내용인지 가려, 그 뒤 revision 을 유일한 사본으로 이어 보인다.
    public var sentFingerprints: [String]?

    public init(
        key: VerseDraftKey,
        revision: Int,
        rowID: BibleDrawingRowID,
        lineData: Data?,
        drawingVersion: Int?,
        layoutMetadataData: Data?,
        base: VerseEditBase,
        baseFingerprint: String?,
        account: VerseEditAccountBasis,
        knownEpochs: Set<String>?,
        storeOwnership: AccountScope?,
        eraseGeneration: UInt64,
        savedAt: Date,
        storeState: VerseDraftStoreState? = nil,
        ownershipInjected: Bool? = nil,
        sentFingerprints: [String]? = nil
    ) {
        self.key = key
        self.revision = revision
        self.rowID = rowID
        self.lineData = lineData
        self.drawingVersion = drawingVersion
        self.layoutMetadataData = layoutMetadataData
        self.base = base
        self.baseFingerprint = baseFingerprint
        self.account = account
        self.knownEpochs = knownEpochs
        self.storeOwnership = storeOwnership
        self.eraseGeneration = eraseGeneration
        self.savedAt = savedAt
        self.storeState = storeState
        self.ownershipInjected = ownershipInjected
        self.sentFingerprints = sentFingerprints
    }

    /// 이 초안이 든 내용의 지문. 비운 절(`lineData == nil`)이면 nil — 저장소의 빈 절과 같다.
    public var contentFingerprint: String? {
        guard lineData != nil else { return nil }
        return VerseContentFingerprint.make(lineData: lineData, drawingVersion: drawingVersion, layoutMetadataBlob: layoutMetadataData)
    }

    /// 이 초안을 쓴 편집 문맥의 근거.
    public var provenance: VerseDraftProvenance {
        VerseDraftProvenance(account: account, knownEpochs: knownEpochs, storeOwnership: storeOwnership, ownershipInjected: ownershipInjected)
    }

    /// 이 초안의 이 revision.
    public var ref: VerseDraftRef { VerseDraftRef(key: key, revision: revision) }
}

/// 초안을 저장소로 보낸 단계.
public enum VerseDraftStoreState: String, Codable, Sendable {
    /// 저장소로 보낼 revision 으로 남겼다 — 보냈는지 · 들어갔는지 아직 모른다. 초안을 이 표식과 함께 **먼저** 남긴 뒤에만 저장소에 쓴다.
    case sending
    /// 저장소 저장이 끝난 것을 확인한 뒤 남겼다.
    case stored
}

/// 초안 하나의 한 revision — 이어받아 대신할 초안을 가리킨다. **그 revision 일 때만** 대신한다: 그 사이 더 새 revision 이 쓰였으면(닫은 세션의
/// 늦은 편집 등) 사용자가 보지 않은 내용이므로 남긴다.
public struct VerseDraftRef: Hashable, Codable, Sendable {
    public var key: VerseDraftKey
    public var revision: Int

    public init(key: VerseDraftKey, revision: Int) {
        self.key = key
        self.revision = revision
    }
}

/// 초안의 출처 — 그 초안을 쓴 편집 문맥의 계정 근거 · K · 저장소 소유 근거 (정책 §12-6 구현 순서 ②).
///
/// 보이기만 하는 초안(`VerseDraftRecoveryPlan.showOnly`)을 이어 그리면 새 초안은 **지금 세션이 아니라 이 출처를 잇는다.**
/// 한 획을 더한 것은 계정 간 가져오기 동의가 아니다 — 출처를 바꾸는 것은 ④ 의 명시적 가져오기뿐이다.
public struct VerseDraftProvenance: Codable, Equatable, Sendable {
    public var account: VerseEditAccountBasis
    public var knownEpochs: Set<String>?
    public var storeOwnership: AccountScope?
    /// 소유 근거가 시험용 주입이었다. 이어 쓴 초안에도 그대로 남는다.
    public var ownershipInjected: Bool?

    public init(account: VerseEditAccountBasis, knownEpochs: Set<String>?, storeOwnership: AccountScope?, ownershipInjected: Bool? = nil) {
        self.account = account
        self.knownEpochs = knownEpochs
        self.storeOwnership = storeOwnership
        self.ownershipInjected = ownershipInjected
    }
}

public extension DrawingEditEnvironment {
    /// 이 환경의 편집 화면이 **읽는** 초안 묶음 — 지금 근거의 묶음과, 확인된 계정이면 확인 전 묶음(힌트가 같은 초안만 올라온다).
    ///
    /// 그 밖의 묶음(다른 계정 · 이 기기 전용)은 읽지 않는다. 지금 저장소의 내용은 그 묶음의 계정 것이 아니라, 견주면 엉뚱한 판정이 된다 —
    /// 복구 화면(④)도 그 묶음은 세어 보이기만 하고 저장소와 대조하지 않는다.
    var readableDraftScopes: [AccountScope] {
        let scope = accountBasis.preservationScope
        guard case .confirmed = accountBasis else { return [scope] }
        return [scope, .unverified]
    }

    /// 이 환경에서 쓰는 초안의 출처.
    var draftProvenance: VerseDraftProvenance {
        VerseDraftProvenance(
            account: accountBasis, knownEpochs: knowledge?.all, storeOwnership: storeOwnership, ownershipInjected: ownershipInjected ? true : nil
        )
    }
}

public extension VerseEditAccountBasis {
    /// 이 근거로 만든 로컬 보존의 묶음. 확인된 계정이면 그 계정 범위, 아니면 "계정 미확인" · "이 기기 전용" 묶음이다.
    var preservationScope: AccountScope {
        switch self {
        case .confirmed(let token): token.scope
        case .unverified: .unverified
        case .localOnly: .localOnly
        }
    }

    /// 이 근거가 **참고하는 계정** — 확인됐으면 그 계정, 확인 전이면 그때의 마지막 확인 힌트, 로그인하지 않았으면 없다.
    /// 확인 전 묶음의 초안을 화면에 올릴지 가리는 기준이다(`VerseDraftRecoveryRule.reachesScreen`).
    var referencedAccount: AccountScope? {
        switch self {
        case .confirmed(let token): token.scope
        case .unverified(let hint): hint
        case .localOnly: nil
        }
    }
}

/// 복구 화면(④)이 쓰는 묶음 요약 — **파일만 보고 센다.** 저장소를 읽지 않으므로 깨진 초안이 있어도 개수 · 용량은 나온다.
public struct DraftBucketSummary: Equatable, Sendable {
    public let scope: AccountScope
    /// 읽을 수 있는 초안 파일 수와 바이트.
    public let draftCount: Int
    public let draftBytes: Int64
    /// 읽지 못해 옆으로 옮긴 파일(`*.unreadable-*`) — 되살릴 수 없고 내보내기만 한다.
    public let unreadableCount: Int
    public let unreadableBytes: Int64
    /// 초안이 남아 있는 장. 분류(저장소 대조)는 이 장만 읽으면 된다.
    public let chapters: [BibleChapter]

    public init(
        scope: AccountScope, draftCount: Int, draftBytes: Int64, unreadableCount: Int, unreadableBytes: Int64, chapters: [BibleChapter]
    ) {
        self.scope = scope
        self.draftCount = draftCount
        self.draftBytes = draftBytes
        self.unreadableCount = unreadableCount
        self.unreadableBytes = unreadableBytes
        self.chapters = chapters
    }
}

/// 이 기기의 비동기화 보존 쓰기(초안 · 격리본)와 전체 삭제를 **한 줄로 세우는 곳** (정책 §12-6 구현 순서 ②).
///
/// - 모든 쓰기는 요청이 기댄 **로컬 삭제 세대**를 들고 온다. 세대 검사와 파일 반영 사이에 `await` 를 두지 않는다 — actor 는 `await`
///   사이에 재진입하므로, 검사와 쓰기를 한 동기 구간에서 한다. 전체 삭제 뒤의 늦은 쓰기는 거절된다.
/// - 삭제 세대는 메모리가 아니라 파일에 남는다(`EraseStateArea` — 전체 삭제가 지우지 않는 곳). 재시작 뒤의 늦은 쓰기도 거절한다.
/// - 전체 삭제는 **세대를 먼저 올리고 → 보존 폴더를 한 번에 옮긴 뒤 지운다.** 중간에 끊겨 남은 폴더는 표식의 세대가 낮아 다음 실행에서
///   지운다.
public actor LocalPreservationWriter {
    public enum WriteOutcome: Equatable, Sendable {
        case written
        /// 요청이 기댄 세대 뒤에 전체 삭제가 있었다. 쓰지 않았다.
        case rejectedByErase(current: UInt64)
    }

    public enum WriterError: Error, Equatable {
        /// 삭제 세대를 읽지 못했다. 늦은 쓰기를 가려낼 수 없으므로 쓰지 않는다.
        case generationUnreadable(String)
        /// 초안 폴더를 훑지 못했다(폴더가 아닌 것이 있음 · 열거 오류).
        case draftsUnreadable(String)
    }

    /// 초안에 남기는 "넣은 내용" 지문의 최대 개수. 왕복 한두 번을 덮을 만큼만 둔다.
    static let sentFingerprintLimit = 5

    /// 넣은 내용 지문 목록을 합친다 — 앞이 최근이고, 같은 지문은 한 번만, 최대 `sentFingerprintLimit` 개.
    static func merged(_ first: [String], _ second: [String]) -> [String]? {
        var seen: Set<String> = []
        let list = (first + second).filter { seen.insert($0).inserted }.prefix(sentFingerprintLimit)
        return list.isEmpty ? nil : Array(list)
    }

    private static let generationFile = "local-erase-generation.json"
    private static let markerFile = "local-generation.json"
    private static let trashPrefix = ".erasing-"

    private let area: PreservationArea
    private let generationURL: URL
    private let fileManager: FileManager
    private var generation: UInt64?
    private let now: @Sendable () -> Date

    public init(area: PreservationArea, eraseState: EraseStateArea, fileManager: FileManager = .default,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.area = area
        self.generationURL = eraseState.root.appendingPathComponent(eraseState.storeFileName, isDirectory: true)
            .appendingPathComponent(Self.generationFile)
        self.fileManager = fileManager
        self.now = now
        let loaded = Self.loadGeneration(at: generationURL, fileManager: fileManager)
        self.generation = loaded
        Self.removeTrash(in: area.root, fileManager: fileManager)
        if let loaded {
            Self.removeLeftover(area: area, generation: loaded, fileManager: fileManager)
        }
    }

    /// 지금 로컬 삭제 세대. 읽지 못했으면 nil — 그동안 쓰기는 거절된다. 읽지 못한 채였으면 다시 읽어 본다.
    public func currentGeneration() -> UInt64? {
        try? requireGeneration()
    }

    // MARK: - 초안

    /// 초안을 저장한다. 같은 키에 더 새 revision 이 이미 있으면 덮지 않는다(늦게 도착한 옛 쓰기).
    ///
    /// - Parameter superseding: 이 초안이 이어받은 **다른 세션의** 초안과 그 revision. 새 초안이 내구성 있게 저장된 **뒤에**, 그 파일이 아직
    ///   그 revision 일 때만 지운다 — 그 사이에 끊기면 둘 다 남을 뿐 어느 쪽도 잃지 않고, 더 새 revision 이 쓰였으면 남긴다. 같은 세션의 키는
    ///   지우지 않는다(방금 쓴 초안이다).
    public func saveDraft(_ draft: VerseDraft, superseding: [VerseDraftRef] = []) throws -> WriteOutcome {
        let current = try requireGeneration()
        guard draft.eraseGeneration == current else { return .rejectedByErase(current: current) }
        try stampLiveDirectory(current)
        let scope = draft.account.preservationScope
        let url = draftURL(draft.key, scope: scope)
        var draft = draft
        // 이어받는 다른 세션의 초안이 저장소에 넣었던 지문도 물려받는다 — 그 파일은 곧 지워지지만, 복구 후보 판정의 근거는 이어져야 한다.
        var carried: [String] = []
        for ref in superseding where ref.key.sessionID != draft.key.sessionID {
            carried += (try? readDraft(at: draftURL(ref.key, scope: scope)))?.sentFingerprints ?? []
        }
        if fileManager.fileExists(atPath: url.path) {
            do {
                let existing = try readDraft(at: url)
                if existing.revision > draft.revision { return .written }
                // 앞선 revision 이 저장소에 넣은 내용의 지문을 이어받는다 — 이 키의 "무엇을 넣었는지" 기록은 revision 을 넘어 이어진다.
                carried = (existing.sentFingerprints ?? []) + carried
            } catch {
                // 같은 키의 초안을 읽지 못한다 — 덮지 않고 옆으로 옮겨 남긴다(`.json` 이 아니라 읽기에서 빠진다). 복구는 ④ 에서 다룬다.
                let aside = url.deletingPathExtension().appendingPathExtension("unreadable-\(UUID().uuidString)")
                Log.error("로컬 보존 — 읽지 못하는 초안을 덮지 않고 옆으로 옮긴다", "\(error)")
                try fileManager.moveItem(at: url, to: aside)
            }
        }
        draft.sentFingerprints = Self.merged(draft.sentFingerprints ?? [], carried)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try DurableFile.write(try encoder.encode(draft), to: url)
        for ref in superseding where ref.key.sessionID != draft.key.sessionID {
            let old = draftURL(ref.key, scope: scope)
            guard let existing = try? readDraft(at: old), existing.revision == ref.revision else { continue }
            do {
                try fileManager.removeItem(at: old)
            } catch {
                // 남아도 잃는 것은 없다 — 다음에 불러올 때 다시 판정한다.
                Log.error("로컬 보존 — 이어받은 초안을 지우지 못했다", "\(error)")
            }
        }
        return .written
    }

    /// 역할을 마친 초안을 지운다. **그 revision 일 때만** 지운다 — 그 사이 더 새 편집이 저장됐으면 남긴다.
    ///
    /// 부르는 곳은 ③ 의 확정뿐이다 — 복구 사본 → 버전 로컬 커밋을 마친 revision 을 정리한다(정책 §12-3). 저장소(`BibleDrawing`) 저장만으로는
    /// 부르지 않는다: 전송 전에 계정이 바뀌면 미러링이 그 행을 지우고 되살리지 않는다(ACC-1 F29). 그때 초안이 유일한 사본이다.
    public func removeDraft(_ key: VerseDraftKey, scope: AccountScope, ifRevision revision: Int) throws {
        let url = draftURL(key, scope: scope)
        guard let existing = try? readDraft(at: url), existing.revision == revision else { return }
        try fileManager.removeItem(at: url)
    }

    /// 그 revision 까지의 초안 내용이 저장소(`BibleDrawing`)에 들어갔다는 표식을 남긴다(`VerseDraft.storeState = .stored`).
    /// **지우지 않는다.** 더 새 revision 이 이미 쓰였으면 건드리지 않는다 — 그 revision 은 아직 저장소에 없다. 지금 세대의 파일만 바꾼다.
    public func markDraftStored(
        _ key: VerseDraftKey,
        scope: AccountScope,
        throughRevision revision: Int,
        contentFingerprint: String? = nil
    ) throws {
        let current = try requireGeneration()
        let url = draftURL(key, scope: scope)
        guard var existing = try? readDraft(at: url), existing.eraseGeneration == current else { return }
        var changed = false
        // **무엇을 넣었는지**는 파일이 이미 더 새 revision 이어도 남긴다 — 그 내용이 저장소에 들어간 사실은 파일의 revision 과 별개다.
        // 부르는 쪽이 보낸 내용을 주면 그것을, 주지 않으면 그 revision 까지의 파일 내용을 적는다(11차 리뷰 P1).
        if let sent = contentFingerprint ?? (existing.revision <= revision ? existing.contentFingerprint : nil),
           existing.sentFingerprints?.first != sent {
            existing.sentFingerprints = Self.merged([sent], existing.sentFingerprints ?? [])
            changed = true
        }
        if existing.revision <= revision, existing.storeState != .stored {
            existing.storeState = .stored
            changed = true
        }
        guard changed else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try DurableFile.write(try encoder.encode(existing), to: url)
    }

    /// 한 묶음의 초안들. 지금 세대의 것만 준다. 초안 파일을 하나라도 읽지 · 풀지 못하면 던진다.
    public func drafts(in scope: AccountScope) throws -> [VerseDraft] {
        let current = try requireGeneration()
        return try draftFiles(in: scope) { _ in true }
            .map { try readDraft(at: $0) }
            .filter { $0.eraseGeneration == current }
            .sorted { ($0.key.sessionID, $0.key.chapter, $0.key.verse) < ($1.key.sessionID, $1.key.chapter, $1.key.verse) }
    }

    /// 한 묶음에서 한 장의 초안들. 파일 이름으로 먼저 거르므로 다른 장의 초안은 열지 않는다. 지금 세대의 것만 준다.
    ///
    /// **그 장의 초안 파일을 하나라도 읽지 · 풀지 못하면 던진다.** 없는 것으로 치면 편집 화면이 그 초안을 보이지 않은 채 열리고, 같은 키 ·
    /// 더 새 revision 의 초안이 그 위에 덮인다(초안 전용 세션에서는 그것이 유일한 사본이다). 묶음 폴더가 아예 없으면(초안을 쓴 적 없음) 빈 목록이다.
    public func drafts(in scope: AccountScope, chapter: BibleChapter, translation: Translation = .NKRV) throws -> [VerseDraft] {
        let current = try requireGeneration()
        let prefix = VerseDraftKey.chapterFilePrefix(translation: translation, chapter: chapter)
        return try draftFiles(in: scope) { $0.lastPathComponent.hasPrefix(prefix) }
            .map { try readDraft(at: $0) }
            .filter {
                $0.eraseGeneration == current && $0.key.translation == translation.rawValue
                    && $0.key.title == chapter.title.rawValue && $0.key.chapter == chapter.chapter
            }
            .sorted { ($0.key.verse, $0.key.sessionID) < ($1.key.verse, $1.key.sessionID) }
    }

    // MARK: - 복구 화면(④)이 보는 것

    /// 이 기기에 초안이 남아 있는 묶음(계정 범위)들. 폴더가 없으면 빈 목록이다.
    public func draftBuckets() throws -> [AccountScope] {
        let root = area.draftsDirectory
        var status = stat()
        guard lstat(root.path, &status) == 0 else {
            if errno == ENOENT { return [] }
            throw WriterError.draftsUnreadable(root.lastPathComponent)
        }
        do {
            return try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .map { AccountScope(key: $0.lastPathComponent) }
                .sorted { $0.key < $1.key }
        } catch {
            Log.error("로컬 보존 — 초안 묶음 목록을 읽지 못했다", "\(error)")
            throw WriterError.draftsUnreadable(root.lastPathComponent)
        }
    }

    /// 그 묶음의 개수 · 용량 · 남은 장. **지금 세대의 것만** 세지 않는다 — 옛 세대의 잔여도 자리를 차지하므로 함께 보인다.
    public func draftSummary(in scope: AccountScope) throws -> DraftBucketSummary {
        let files = try draftEntries(in: scope)
        var draftCount = 0, unreadableCount = 0
        var draftBytes: Int64 = 0, unreadableBytes: Int64 = 0
        var chapters: Set<BibleChapter> = []
        for url in files {
            let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            if url.lastPathComponent.contains("unreadable-") {
                unreadableCount += 1
                unreadableBytes += size
            } else if url.pathExtension == "json" {
                draftCount += 1
                draftBytes += size
            } else {
                continue
            }
            if let chapter = VerseDraftKey.chapter(fromFileName: url.lastPathComponent) { chapters.insert(chapter) }
        }
        return DraftBucketSummary(
            scope: scope, draftCount: draftCount, draftBytes: draftBytes, unreadableCount: unreadableCount,
            unreadableBytes: unreadableBytes,
            chapters: chapters.sorted { ($0.title.rawValue, $0.chapter) < ($1.title.rawValue, $1.chapter) }
        )
    }

    /// 읽지 못해 옆으로 옮긴 파일들 — 복구 화면이 내보내기로 넘긴다.
    public func unreadableDraftFiles(in scope: AccountScope) throws -> [URL] {
        try draftEntries(in: scope).filter { $0.lastPathComponent.contains("unreadable-") }.sorted { $0.path < $1.path }
    }

    // MARK: - 격리

    /// 무효가 된 편집 세션의 미저장분을 격리본으로 남긴다. 세션이 기댄 세대 뒤에 전체 삭제가 있었으면 쓰지 않는다.
    public func quarantine(
        _ items: [DrawingQuarantineItem],
        environment: DrawingEditEnvironment,
        batchID: String,
        deviceID: String
    ) throws -> WriteOutcome {
        let current = try requireGeneration()
        guard environment.eraseGeneration == current else { return .rejectedByErase(current: current) }
        try stampLiveDirectory(current)
        try FileDrawingQuarantine.write(
            items, environment: environment, batchID: batchID, deviceID: deviceID,
            store: FileRecoveryCopyStore(root: area.recoveryCopiesDirectory, fileManager: fileManager), now: now()
        )
        return .written
    }

    // MARK: - 전체 삭제

    /// 이 기기의 보존 영역(원시 사본 · 복구 사본 · 격리본 · 초안)을 지운다. **사용자가 이 기기에서 전체 삭제를 요청했을 때만** 부른다.
    /// - Returns: 올린 뒤의 세대.
    @discardableResult
    public func eraseAllLocal() throws -> UInt64 {
        let next = try requireGeneration() + 1
        // ★ 세대를 먼저 올린다 — 폴더를 지우다 끊겨도 남은 것은 표식의 세대가 낮아 다음 실행에서 지워진다.
        try writeGeneration(next)
        generation = next
        try Self.moveToTrashAndDelete(area.storeDirectory, root: area.root, fileManager: fileManager)
        return next
    }

    // MARK: - 파일

    /// 지금 세대. 시작할 때 읽지 못했으면(일시적인 입출력 오류 · 첫 잠금 해제 전의 파일 보호 등) **다시 읽어 본다** — 한 번 못 읽었다고 이 실행 내내
    /// 쓰기를 막으면 초안을 읽지 못한 장의 「다시 시도」가 끝내 성공하지 못한다. 여전히 못 읽으면 쓰지 않는다.
    private func requireGeneration() throws -> UInt64 {
        if let generation { return generation }
        guard let loaded = Self.loadGeneration(at: generationURL, fileManager: fileManager) else {
            throw WriterError.generationUnreadable(generationURL.lastPathComponent)
        }
        generation = loaded
        Self.removeLeftover(area: area, generation: loaded, fileManager: fileManager)
        return loaded
    }

    private func writeGeneration(_ value: UInt64) throws {
        try fileManager.createDirectory(at: generationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try DurableFile.write(try JSONEncoder().encode(value), to: generationURL)
    }

    /// 보존 폴더에 지금 세대 표식을 붙인다. 표식이 없으면(첫 실행 · 원시 사본만 있음) 지금 세대로 붙이고, 낮으면 지난 삭제의 잔여다.
    private func stampLiveDirectory(_ current: UInt64) throws {
        let marker = area.storeDirectory.appendingPathComponent(Self.markerFile)
        if let stamped = Self.readMarker(at: marker, fileManager: fileManager) {
            guard stamped < current else { return }
            try Self.moveToTrashAndDelete(area.storeDirectory, root: area.root, fileManager: fileManager)
        }
        try fileManager.createDirectory(at: area.storeDirectory, withIntermediateDirectories: true)
        try DurableFile.write(try JSONEncoder().encode(current), to: marker)
    }

    /// 묶음 폴더의 초안 파일(`묶음/세션/*.json`, 쓰다 남은 임시 파일 · 옆으로 옮긴 파일은 빼고).
    ///
    /// **묶음 폴더가 없을 때만(ENOENT) 빈 목록이다.** 권한 · 입출력 오류로 폴더를 보지 못하는 것을 "없음" 으로 치면 보이지 않는 초안 위에
    /// 새 초안이 덮인다 — 폴더가 아니거나, 어느 세션 폴더든 목록을 읽지 못하면 던진다.
    private func draftEntries(in scope: AccountScope) throws -> [URL] {
        let root = area.draftsDirectory.appendingPathComponent(scope.key, isDirectory: true)
        var status = stat()
        guard lstat(root.path, &status) == 0 else {
            if errno == ENOENT { return [] }
            Log.error("로컬 보존 — 초안 묶음 폴더를 보지 못했다", "errno=\(errno)")
            throw WriterError.draftsUnreadable(scope.key)
        }
        guard status.st_mode & S_IFMT == S_IFDIR else { throw WriterError.draftsUnreadable(scope.key) }
        do {
            var files: [URL] = []
            for session in try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) {
                guard try session.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { continue }
                files += try fileManager.contentsOfDirectory(at: session, includingPropertiesForKeys: [.fileSizeKey])
            }
            return files
        } catch {
            Log.error("로컬 보존 — 초안 폴더를 끝까지 읽지 못했다", "\(error)")
            throw WriterError.draftsUnreadable(scope.key)
        }
    }

    /// 묶음의 초안 파일(`.json`, 쓰다 남은 임시 · 옆으로 옮긴 파일은 빼고).
    private func draftFiles(in scope: AccountScope, matching include: (URL) -> Bool) throws -> [URL] {
        try draftEntries(in: scope).filter { $0.pathExtension == "json" && include($0) }
    }

    private func draftURL(_ key: VerseDraftKey, scope: AccountScope) -> URL {
        area.draftsDirectory
            .appendingPathComponent(scope.key, isDirectory: true)
            .appendingPathComponent(key.sessionID, isDirectory: true)
            .appendingPathComponent(key.fileName)
    }

    private func readDraft(at url: URL) throws -> VerseDraft {
        try JSONDecoder().decode(VerseDraft.self, from: Data(contentsOf: url))
    }

    private static func loadGeneration(at url: URL, fileManager: FileManager) -> UInt64? {
        guard fileManager.fileExists(atPath: url.path) else { return 0 }
        do {
            return try JSONDecoder().decode(UInt64.self, from: Data(contentsOf: url))
        } catch {
            Log.error("로컬 보존 — 삭제 세대를 읽지 못했다. 쓰기를 멈춘다", "\(error)")
            return nil
        }
    }

    private static func readMarker(at url: URL, fileManager: FileManager) -> UInt64? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try? JSONDecoder().decode(UInt64.self, from: Data(contentsOf: url))
    }

    /// 지난 삭제가 끝내지 못한 보존 폴더(표식의 세대가 지금보다 낮음)를 지운다.
    private static func removeLeftover(area: PreservationArea, generation: UInt64, fileManager: FileManager) {
        let marker = area.storeDirectory.appendingPathComponent(markerFile)
        guard let stamped = readMarker(at: marker, fileManager: fileManager), stamped < generation else { return }
        do {
            try moveToTrashAndDelete(area.storeDirectory, root: area.root, fileManager: fileManager)
        } catch {
            Log.error("로컬 보존 — 지난 전체 삭제의 잔여를 지우지 못했다", "\(error)")
        }
    }

    private static func removeTrash(in root: URL, fileManager: FileManager) {
        guard let children = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for child in children where child.lastPathComponent.hasPrefix(trashPrefix) {
            try? fileManager.removeItem(at: child)
        }
    }

    /// 폴더를 같은 부모 안의 휴지통 이름으로 한 번에 옮긴 뒤 지운다. 옮기기는 원자적이라 반쯤 지운 폴더가 제자리에 남지 않는다.
    private static func moveToTrashAndDelete(_ directory: URL, root: URL, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        let trash = root.appendingPathComponent(trashPrefix + UUID().uuidString, isDirectory: true)
        try fileManager.moveItem(at: directory, to: trash)
        try? fileManager.removeItem(at: trash)
    }
}

private enum LocalPreservationWriterKey: DependencyKey {
    /// 앱이 주입한다. 없으면 초안 · 격리를 쓸 수 없다 — 호출부는 미저장분을 지킨 채 실패로 둔다.
    static let liveValue: LocalPreservationWriter? = nil
    static let testValue: LocalPreservationWriter? = nil
}

public extension DependencyValues {
    /// 이 기기의 비동기화 보존 쓰기와 전체 삭제의 직렬화 경계.
    var localPreservationWriter: LocalPreservationWriter? {
        get { self[LocalPreservationWriterKey.self] }
        set { self[LocalPreservationWriterKey.self] = newValue }
    }
}

/// 편집 화면이 쓰는 절 초안 저장 — 이 기기의 비동기화 보존 영역(`LocalPreservationWriter`)이 구현한다 (정책 §12-6 구현 순서 ②).
///
/// 편집 화면은 초안을 쓰고 · 장 단위로 읽고 · 저장소에 들어간 revision 에 표식을 남길 뿐이다(지우기는 ③ 의 확정이 한다). 전체 삭제 · 격리는
/// 이 경계 밖이다.
public protocol VerseDraftStore: Sendable {
    func saveDraft(_ draft: VerseDraft, superseding: [VerseDraftRef]) async throws -> LocalPreservationWriter.WriteOutcome
    func drafts(in scope: AccountScope, chapter: BibleChapter, translation: Translation) async throws -> [VerseDraft]
    func removeDraft(_ key: VerseDraftKey, scope: AccountScope, ifRevision revision: Int) async throws
    /// 그 revision 까지의 초안 내용이 저장소에 들어갔다는 표식을 남긴다(지우지 않는다).
    /// - Parameter contentFingerprint: 저장소에 **실제로 넣은 내용**의 지문. 파일이 그 사이 더 새 revision 이어도 이 지문은 남긴다.
    func markDraftStored(_ key: VerseDraftKey, scope: AccountScope, throughRevision revision: Int, contentFingerprint: String?) async throws
    /// 지금 로컬 삭제 세대. 읽지 못하면 nil.
    func currentGeneration() async -> UInt64?
}

extension LocalPreservationWriter: VerseDraftStore {}

private enum VerseDraftStoreKey: DependencyKey {
    /// 앱이 `LocalPreservationWriter` 를 주입한다. 없으면 초안을 남기지 못한다 — 편집 화면은 초안이 유일한 보존일 때 실패로 알린다.
    static let liveValue: (any VerseDraftStore)? = nil
    static let testValue: (any VerseDraftStore)? = nil
}

public extension DependencyValues {
    /// 편집 화면의 절 초안 저장.
    var verseDraftStore: (any VerseDraftStore)? {
        get { self[VerseDraftStoreKey.self] }
        set { self[VerseDraftStoreKey.self] = newValue }
    }
}
