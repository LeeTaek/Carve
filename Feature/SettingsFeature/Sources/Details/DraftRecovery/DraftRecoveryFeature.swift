//
//  DraftRecoveryFeature.swift
//  SettingsFeature
//
//  설정 → 「남은 필기」. 그 장을 다시 열어도 자동으로 표시되지 않는 초안을 보고 · 견주는 한 자리 (정책 §12-6 구현 순서 ④).
//

import CarveToolkit
import Domain
import Foundation

import ComposableArchitecture

/// 이 기기에 남아, 그 장을 다시 열어도 **자동으로 표시되지 않는 필사 초안**을 보이는 화면(2026-09-21 후속 리뷰 확정 기준).
///
/// - **읽기 전용이다**(사용자 결정 2026-09-21). 개수 · 용량 · 목록 · 출처까지 보이고, 되살리기 · 귀속 동의는 ③ 의 버전 쓰기와 같은 시기에
///   붙인다. 그동안에도 파일은 지우지 않는다 — 보이지 않는다는 것이 사라졌다는 뜻이 아니다.
/// - **판정은 편집 화면과 같은 규칙 · 같은 입력**을 쓴다(`VerseDraftRecoveryQuery`). 자동으로 표시되는 초안과 이미 저장소에 든 초안은 목록에
///   넣지 않는다.
/// - 다른 계정 묶음은 **저장소와 대조하지 않고** 세어 보이기만 한다. 그 계정으로 돌아왔을 때 연다.
@Reducer
public struct DraftRecoveryFeature {
    public init() { }

    /// 한 계정 묶음. 화면이 보는 값만 든다.
    public struct Bucket: Hashable, Identifiable {
        public var scope: AccountScope
        public var id: String { scope.key }
        /// 사람이 읽는 이름 — 지금 계정 · 계정 미확인 · 이 기기 전용 · 다른 계정.
        public var title: String
        public var draftCount: Int
        public var draftBytes: Int64
        /// 읽지 못해 옆으로 옮긴 파일 — 되살릴 수 없고 보관만 한다. 내보내고 지울 수 있는 **유일한** 것이다.
        public var unreadableCount: Int
        public var unreadableBytes: Int64
        /// 그 파일들의 자리 — 내보내기로 넘긴다.
        public var unreadableFiles: [URL]
        /// 저장소와 대조했는가. 아니면 분류 없이 세어 보이기만 한다.
        public var comparedWithStore: Bool
        /// 이 묶음을 아예 읽지 못했다 — **초안이 없다는 뜻이 아니다.**
        public var readFailed: Bool
        /// 자동으로 표시되지 않는 초안들. 최근에 쓴 것부터.
        public var items: [Item]
        /// 대조하지 못한 장 이름 — 그 장의 초안은 세어졌지만 분류하지 못했다.
        public var unreadChapters: [String]
    }

    /// 목록의 한 줄.
    public struct Item: Hashable, Identifiable {
        public var id: String
        /// "창세기 1:3".
        public var place: String
        /// 비교할 때 이 장만 읽는다.
        public var chapter: BibleChapter
        public var verse: Int
        public var savedAt: Date
        public var reason: VerseDraftRecoveryReason
        /// 그때의 계정 근거 한 줄.
        public var provenance: String
        /// 소유 근거가 시험용 주입이었다(DEBUG 전용) — 소유 증명이 아니다.
        public var injected: Bool
        /// 미리보기용 필기 바이트. 비운 절이면 nil.
        public var ink: Data?
        /// 그 절의 지금 필기가 언제 바뀌었는가. 대조하지 않은 묶음이면 nil.
        public var currentUpdatedAt: Date?
        /// 그 절이 지금 비어 있는가. 대조하지 않은 묶음이면 nil.
        public var currentIsEmpty: Bool?
    }

    /// 견주기 — 지금 필기와 보관된 것. **바꾸지 않는다**(읽기 전용 단계).
    public struct Comparison: Hashable {
        public var itemID: String
        public var isLoading: Bool = true
        /// 그 절의 지금 필기. nil 이면 지금 그 절에는 필기가 없다.
        public var currentInk: Data?
        public var currentUpdatedAt: Date?
        /// 지금 필기를 읽지 못했다 — 없다는 뜻이 아니다.
        public var failure: String?
    }

    @ObservableState
    public struct State: Hashable {
        public static let initialState = Self()
        public var isLoading = false
        /// 이 기기의 보존 영역을 열지 못했다 — **초안이 없다는 뜻이 아니다.**
        public var failure: String?
        public var buckets: [Bucket] = []
        /// 펼쳐 본 묶음.
        public var opened: AccountScope?
        /// 펼쳐 견주는 중인 초안.
        public var comparison: Comparison?
        /// 읽지 못한 파일 지우기를 묻는 중인 묶음.
        public var pendingRemoval: AccountScope?
        /// 방금 지운 결과 한 줄.
        public var removalResult: String?

        public var totalDraftCount: Int { buckets.reduce(0) { $0 + $1.draftCount } }
        public var totalDraftBytes: Int64 { buckets.reduce(0) { $0 + $1.draftBytes } }
        public var totalUnreadableCount: Int { buckets.reduce(0) { $0 + $1.unreadableCount } }
        public var totalUnreadableBytes: Int64 { buckets.reduce(0) { $0 + $1.unreadableBytes } }
        /// 그중 그 장을 다시 열어도 **자동으로 표시되지 않는** 초안 — 나머지는 자동으로 표시되거나 이미 저장된 것이다.
        public var hiddenCount: Int { buckets.reduce(0) { $0 + $1.items.count } }
        /// 사용자가 판단할 것이 있는가 — 되살릴 수 있음 · 저장 완료 불확실.
        public var needsAttentionCount: Int {
            buckets.reduce(0) { count, bucket in
                count + bucket.items.count { $0.reason == .recoverable || $0.reason == .uncertain }
            }
        }
    }

    public enum Action: ViewAction {
        case loaded([Bucket])
        case failed(String)
        case view(View)

        /// 그 절의 지금 필기를 읽었다.
        case currentLoaded(itemID: String, ink: Data?, updatedAt: Date?)
        case currentFailed(itemID: String, String)
        /// 읽지 못한 파일을 지웠다(또는 지우지 못했다).
        case removedUnreadable(String)

        public enum View {
            case onAppear
            case reload
            /// 묶음을 펼치거나 접는다.
            case open(AccountScope?)
            /// 초안을 지금 필기와 견주어 본다(다시 누르면 접는다).
            case compare(Item)
            /// 읽지 못한 파일 지우기를 묻는다(nil 이면 묻기를 닫는다).
            case askRemoveUnreadable(AccountScope?)
            /// 묻고 받은 뒤 실제로 지운다 — **읽지 못한 파일만**이다.
            case removeUnreadableConfirmed(AccountScope)
        }
    }

    @Dependency(\.verseDraftRecoveryReader) private var reader
    @Dependency(\.verseDraftUnreadableCleaner) private var cleaner
    @Dependency(\.drawingRepository) private var repository
    @Dependency(\.drawingEditEnvironment) private var editEnvironment

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .view(.onAppear), .view(.reload):
                guard !state.isLoading else { return .none }
                state.isLoading = true
                state.failure = nil
                return load()
            case .view(.open(let scope)):
                state.opened = state.opened == scope ? nil : scope
                state.comparison = nil
            case .view(.compare(let item)):
                guard state.comparison?.itemID != item.id else {
                    state.comparison = nil
                    return .none
                }
                state.comparison = Comparison(itemID: item.id)
                return compare(item)
            case .currentLoaded(let itemID, let ink, let updatedAt):
                guard state.comparison?.itemID == itemID else { return .none }
                state.comparison?.isLoading = false
                state.comparison?.currentInk = ink
                state.comparison?.currentUpdatedAt = updatedAt
            case .currentFailed(let itemID, let message):
                guard state.comparison?.itemID == itemID else { return .none }
                state.comparison?.isLoading = false
                state.comparison?.failure = message
            case .view(.askRemoveUnreadable(let scope)):
                state.pendingRemoval = state.pendingRemoval == scope ? nil : scope
                state.removalResult = nil
            case .view(.removeUnreadableConfirmed(let scope)):
                state.pendingRemoval = nil
                state.isLoading = true
                return removeUnreadable(in: scope)
            case .removedUnreadable(let message):
                state.removalResult = message
                // 지운 뒤에는 다시 세어 보인다 — 남은 것이 있으면 그대로 보여야 한다.
                return load()
            case .loaded(let buckets):
                state.isLoading = false
                state.buckets = buckets
                if let comparison = state.comparison, !buckets.contains(where: { $0.items.contains { $0.id == comparison.itemID } }) {
                    state.comparison = nil
                }
                if let opened = state.opened, !buckets.contains(where: { $0.scope == opened }) {
                    state.opened = nil
                }
            case .failed(let message):
                state.isLoading = false
                state.failure = message
                state.buckets = []
                state.comparison = nil
            }
            return .none
        }
    }

    /// 묶음마다 조회한다. **한 묶음을 읽지 못해도 나머지는 보인다** — 목록 전체를 막으면 멀쩡한 초안까지 보이지 않는다.
    private func load() -> Effect<Action> {
        .run { [reader, repository, editEnvironment] send in
            guard let reader else {
                await send(.failed("이 기기의 보존 영역을 열지 못했어요. 앱을 다시 켜 보세요."))
                return
            }
            let environment = await editEnvironment.current()
            let query = VerseDraftRecoveryQuery(reader: reader, repository: repository)
            let scopes: [AccountScope]
            do {
                scopes = try await reader.draftBuckets()
            } catch {
                Log.error("남은 필기 — 묶음 목록을 읽지 못했다", "\(error)")
                await send(.failed("이 기기에 남은 필기를 읽지 못했어요. 파일은 그대로 있어요."))
                return
            }
            var buckets: [Bucket] = []
            for scope in scopes {
                do {
                    let inventory = try await query.inventory(in: scope, environment: environment)
                    // 내보낼 파일 자리는 목록과 함께 읽는다. 읽지 못하면 내보내기만 못 하고 나머지는 그대로 보인다.
                    let files = (try? await reader.unreadableDraftFiles(in: scope)) ?? []
                    buckets.append(Bucket(inventory, files: files, environment: environment))
                } catch {
                    Log.error("남은 필기 — 이 묶음을 읽지 못했다", scope.key, "\(error)")
                    buckets.append(Bucket(unreadable: scope, environment: environment))
                }
            }
            // 볼 것이 있는 묶음을 먼저, 그 안에서는 지금 계정 · 계정 미확인 · 이 기기 전용 · 다른 계정 차례로.
            await send(.loaded(buckets.sorted { Self.order($0, $1) }))
        }
    }

    /// 견줄 때 그 장만 읽는다 — 목록은 지금 필기의 바이트를 들고 있지 않다.
    private func compare(_ item: Item) -> Effect<Action> {
        .run { [reader, repository] send in
            guard let reader else {
                await send(.currentFailed(itemID: item.id, "이 기기의 보존 영역을 열지 못했어요."))
                return
            }
            do {
                let current = try await VerseDraftRecoveryQuery(reader: reader, repository: repository)
                    .currentVerse(chapter: item.chapter, verse: item.verse)
                await send(.currentLoaded(itemID: item.id, ink: current?.lineData, updatedAt: current?.updateDate))
            } catch {
                Log.error("남은 필기 — 지금 필기를 읽지 못했다", item.place, "\(error)")
                await send(.currentFailed(itemID: item.id, "지금 그 절의 필기를 읽지 못했어요. 없다는 뜻은 아니에요."))
            }
        }
    }

    /// **읽지 못한 파일만** 지운다. 초안을 지우는 길은 이 화면에 없다(사용자 결정 2026-09-21).
    private func removeUnreadable(in scope: AccountScope) -> Effect<Action> {
        .run { [cleaner] send in
            guard let cleaner else {
                await send(.removedUnreadable("이 기기의 보존 영역을 열지 못해 지우지 못했어요."))
                return
            }
            do {
                let removed = try await cleaner.removeUnreadableDraftFiles(in: scope)
                await send(.removedUnreadable("읽지 못한 파일 \(removed)개를 지웠어요."))
            } catch {
                Log.error("남은 필기 — 읽지 못한 파일을 지우지 못했다", scope.key, "\(error)")
                await send(.removedUnreadable("읽지 못한 파일을 지우지 못했어요. 파일은 그대로 있어요."))
            }
        }
    }

    private static func order(_ lhs: Bucket, _ rhs: Bucket) -> Bool {
        if lhs.comparedWithStore != rhs.comparedWithStore { return lhs.comparedWithStore }
        return lhs.scope.key < rhs.scope.key
    }
}

// MARK: - 조회 결과를 화면의 값으로

extension DraftRecoveryFeature.Bucket {
    init(_ inventory: VerseDraftRecoveryInventory, files: [URL], environment: DrawingEditEnvironment) {
        self.init(
            scope: inventory.scope,
            title: DraftRecoveryCopy.bucketTitle(inventory.scope, environment: environment),
            draftCount: inventory.summary.draftCount,
            draftBytes: inventory.summary.draftBytes,
            unreadableCount: inventory.summary.unreadableCount,
            unreadableBytes: inventory.summary.unreadableBytes,
            unreadableFiles: files,
            comparedWithStore: inventory.comparedWithStore,
            readFailed: false,
            items: inventory.entries.map { DraftRecoveryFeature.Item($0, environment: environment) },
            unreadChapters: inventory.unreadChapters.map { "\($0.title.koreanTitle()) \($0.chapter)장" }
        )
    }

    /// 묶음을 아예 읽지 못했다. 개수도 세지 못하므로 0 이 아니라 "읽지 못함" 으로 보인다.
    init(unreadable scope: AccountScope, environment: DrawingEditEnvironment) {
        self.init(
            scope: scope, title: DraftRecoveryCopy.bucketTitle(scope, environment: environment),
            draftCount: 0, draftBytes: 0, unreadableCount: 0, unreadableBytes: 0, unreadableFiles: [],
            comparedWithStore: false, readFailed: true, items: [], unreadChapters: []
        )
    }
}

extension DraftRecoveryFeature.Item {
    init(_ entry: VerseDraftRecoveryEntry, environment: DrawingEditEnvironment) {
        let key = entry.draft.key
        self.init(
            id: "\(key.sessionID)/\(key.title)/\(key.chapter)/\(key.verse)",
            place: DraftRecoveryCopy.place(key),
            chapter: BibleChapter(title: BibleTitle(rawValue: key.title) ?? .genesis, chapter: key.chapter),
            verse: key.verse,
            savedAt: entry.draft.savedAt,
            reason: entry.reason,
            provenance: DraftRecoveryCopy.provenance(of: entry.draft, environment: environment),
            injected: entry.draft.ownershipInjected == true,
            ink: entry.draft.lineData,
            currentUpdatedAt: entry.current?.updatedAt,
            currentIsEmpty: entry.current.map(\.isEmpty)
        )
    }
}

// MARK: - 문구

/// 화면 문구를 한곳에 둔다 — 같은 사실을 화면마다 다르게 말하지 않게.
public enum DraftRecoveryCopy {
    /// 목록이 모으는 것 — **"그 장을 다시 열어도 자동으로 표시되지 않는 필사 초안"**(2026-09-21 후속 리뷰 확정). 열린 캔버스의 일시적 상태가
    /// 아니라 다시 열었을 때를 기준으로 삼는다. 이전 문구("화면에 보이지 않는 것")는 지금 캔버스에 겹쳐 보이는 초안까지 떠올리게 했다.
    public static let hiddenKind = "자동으로 표시되지 않는 필사 초안"

    /// 화면 첫 줄.
    public static let introduction = "이 기기에 남아 있는 필사 초안이에요. 그중 그 장을 다시 열어도 **\(hiddenKind)**을 여기서 찾아볼 수 있어요."

    /// 전체 요약 — 파일 수와 "자동으로 표시되지 않는 것" 을 따로 적는다. 같은 수로 뭉뚱그리면 표시되는 초안까지 사라진 것처럼 읽힌다.
    public static func totalLine(draftCount: Int, draftBytes: Int64, hiddenCount: Int) -> String {
        "초안 \(draftCount)개 · \(bytesText(draftBytes)) · 자동으로 표시되지 않는 것 \(hiddenCount)개"
    }

    /// 대조한 묶음에 목록이 비었을 때.
    public static let nothingHidden = "남은 초안은 모두 그 장을 열면 자동으로 표시되거나 이미 저장된 것이에요."

    /// 묶음 이름. **로그인하지 않은 동안 · 계정을 확인하지 못한 동안을 먼저 가린다** — 로그아웃 상태에서는 이 기기 전용 묶음이
    /// "지금 근거의 묶음" 이라 「지금 계정」 으로 읽히는데, 그때는 계정이 없다(2026-09-21 기기 확인).
    public static func bucketTitle(_ scope: AccountScope, environment: DrawingEditEnvironment) -> String {
        switch scope {
        case .unverified: return "계정을 확인하지 못한 동안"
        case .localOnly: return "로그인하지 않은 동안"
        default: return scope == environment.accountBasis.preservationScope ? "지금 계정" : "다른 계정 · \(scope.key.suffix(6))"
        }
    }

    /// 그때의 계정 근거 한 줄. **귀속을 올리지 않는다** — 다른 근거의 초안을 지금 계정의 것처럼 쓰지 않는다.
    public static func provenance(of draft: VerseDraft, environment: DrawingEditEnvironment) -> String {
        let reference = environment.accountBasis.referencedAccount
        var text: String
        switch draft.account {
        case .confirmed(let token):
            text = token.scope == reference ? "이 계정에서 씀" : "다른 계정에서 씀"
        case .unverified(let hint):
            if hint == nil {
                text = "계정을 확인하기 전에 씀"
            } else {
                text = hint == reference ? "계정을 확인하기 전에 씀 · 이 계정을 참고" : "계정을 확인하기 전에 씀 · 다른 계정을 참고"
            }
        case .localOnly:
            text = "로그인하지 않고 씀"
        }
        // K 를 읽지 못한 채 쓴 초안은 알려진 삭제보다 앞인지 가릴 수 없다 — 그 사실을 숨기지 않는다.
        if draft.knownEpochs == nil { text += " · 삭제 기준점을 모름" }
        return text
    }

    public static func reasonTitle(_ reason: VerseDraftRecoveryReason) -> String {
        switch reason {
        case .recoverable: "되살릴 수 있음"
        case .uncertain: "저장 완료 불확실"
        case .storeMoved: "다른 내용이 들어옴"
        case .otherBasis: "다른 계정 근거"
        case .newerDraftShown: "더 새 초안이 보임"
        }
    }

    public static func reasonDetail(_ reason: VerseDraftRecoveryReason) -> String {
        switch reason {
        case .recoverable:
            "저장소의 그 절이 앞서 넣은 내용으로 돌아왔어요. 그 뒤에 쓴 이 필기는 이 기기에만 있어요."
        case .uncertain:
            "저장소로 보내던 중에 앱이 끝났고, 그 절은 그 뒤로 바뀌었어요. 들어갔는지 가릴 수 없어 그대로 남겨 둬요."
        case .storeMoved:
            "이 필기를 쓴 뒤 그 절에 다른 내용이 들어왔어요. 겹쳐 보이면 그 내용을 가리게 돼 자동으로 표시하지 않아요."
        case .otherBasis:
            "그 계정으로 돌아오면 다시 볼 수 있어요. 지금 계정으로 자동으로 가져오지 않아요."
        case .newerDraftShown:
            "같은 절에 더 늦게 쓴 초안이 있어 그쪽이 화면에 보여요. 이 필기도 지우지 않고 남겨 둬요."
        }
    }

    /// "창세기 1:3". 책 이름을 읽지 못하면(모르는 원본 이름) 그 값을 그대로 보인다 — 어디인지 숨기지 않는다.
    public static func place(_ key: VerseDraftKey) -> String {
        let title = BibleTitle(rawValue: key.title)?.koreanTitle() ?? key.title
        return "\(title) \(key.chapter):\(key.verse)"
    }

    public static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월 d일 HH:mm"
        return formatter.string(from: date)
    }

    public static func bytesText(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }
}
