//
//  DraftRecoveryFeature.swift
//  SettingsFeature
//
//  설정 → 「확인이 필요한 필기」. 이 iPad 에 따로 남겨 둔 필기를 현재 필사와 견주고, 사용자가 고른 것을 현재 필사에 넣는 자리
//  (정책 §12-6 구현 순서 ④, 가져오기 2026-09-29).
//

import CarveToolkit
import Domain
import Foundation

import ComposableArchitecture

/// 이 iPad 에 남아, 그 장을 다시 열어도 **자동으로 표시되지 않는 필기**를 보이고 · 견주고 · 고른 것을 현재 필사에 넣는 화면.
///
/// - **자동으로 합치지 않는다 — 절마다 견주고 고른다**(2026-09-29). 계정이 확인됐다는 이유만으로 연결 전 필기를 그 계정의 것으로 보거나, 다른
///   기기에서 받은 필기를 덮지 않는다. 넣기 · 바꾸기는 사용자가 고른 절 하나만 하고, 바꿔도 지금 필기는 이전 필사 기록으로 남는다.
/// - **완료는 저장이 끝난 뒤에만** 알린다. 넣기 직전에 환경 · 초안 · 지금 필기를 다시 보고(`VerseDraftImporter`), 견준 뒤 바뀌었으면 다시 견주게
///   한다. 실패하면 지금 필기도 이 필기도 그대로다.
/// - **판정은 편집 화면과 같은 규칙 · 같은 입력**을 쓴다(`VerseDraftRecoveryQuery`). 자동으로 표시되는 필기와 이미 반영된 필기는 목록에 넣지 않고,
///   내용이 이미 저장소에 있었던 예전 필기는 확인이 필요한 것과 나눠 접어 둔다(사용자 결정 2026-09-29).
/// - 다른 계정 묶음은 **저장소와 대조하지 않고** 세어 보이기만 한다. 그 계정으로 돌아왔을 때 연다(P0-1). 연결 전 필기(로그인하지 않은 동안 ·
///   참고할 계정 없이 확인 전)는 확인된 계정에서 열어 가져올 수 있다.
@Reducer
public struct DraftRecoveryFeature {
    public init() { }

    /// 조회 결과가 기댄 계정 근거 — **이 도장이 지금과 다르면 그 결과(목록 상세 · 비교)를 버린다**(2026-09-21 후속 리뷰 P0-1).
    ///
    /// 접근 제한 · 계정이 바뀐 뒤의 무효화 · 늦은 응답 버리기 · 견주기 전후 재확인을 따로 만들지 않고 이 한 장치로 덮는다. 편집 환경이 초안을
    /// 적는 묶음(어느 묶음을 저장소와 대조하는가)과 참고하는 계정(확인 전 초안 가운데 무엇을 여는가), 계정 확인 세대를 든다 — 같은 계정이라도
    /// 다시 확인했으면 앞선 조회를 믿지 않는다. 동기화 저장소에 쓸 수 있는가(`importBlock`)도 든다 — 소유 근거 · 연결 보류가 바뀌면 넣기 버튼의
    /// 근거가 바뀐다.
    public struct Stamp: Hashable, Sendable {
        public let scope: AccountScope
        public let account: AccountScope?
        public let generation: UInt64
        /// 지금 현재 필사에 넣을 수 없는 사유. nil 이면 넣을 수 있다 — 넣기 직전에 한 번 더 본다(`VerseDraftImporter`).
        public let importBlock: SyncedWriteBlock?

        public init(_ environment: DrawingEditEnvironment) {
            scope = environment.accountBasis.preservationScope
            account = environment.accountBasis.referencedAccount
            generation = environment.generation
            importBlock = SyncedWriteBlock.check(environment)
        }
    }

    @ObservableState
    public struct State: Hashable, Sendable {
        public static let initialState = Self()
        public var isLoading = false
        /// 지금 들고 있는 목록 · 비교가 기댄 계정 근거. 바뀌면 목록 · 비교를 비우고 새 근거로 다시 읽는다.
        public var stamp: Stamp?
        /// 마지막으로 시작한 조회의 번호 — 그보다 앞선 조회의 응답은 버린다.
        public var loadSequence = 0
        /// 이 기기의 보존 영역을 열지 못했다 — **필기가 없다는 뜻이 아니다.**
        public var failure: String?
        public var buckets: [Bucket] = []
        /// 펼쳐 본 묶음.
        public var opened: AccountScope?
        /// 「보관만 하는 예전 필기」 를 펼친 묶음.
        public var archivedOpened: Set<AccountScope> = []
        /// 펼쳐 견주는 중인 필기.
        public var comparison: Comparison?
        /// 지웠던 내용이 다시 들어갈 수 있어 **한 번 더 묻는 중**인 주의 — 견주고 있는 필기의 것.
        public var pendingCaution: VerseDraftImportCheck.Caution?
        /// 넣는 중인 필기. 끝나기 전에는 다른 필기를 넣지 않는다.
        public var importingItemID: String?
        /// 방금 가져오기의 결과.
        public var importMessage: ImportMessage?
        /// 읽지 못한 파일 지우기를 묻는 중인 묶음.
        public var pendingRemoval: AccountScope?
        /// 방금 지운 결과 한 줄.
        public var removalResult: String?

        public var totalDraftCount: Int { buckets.reduce(0) { $0 + $1.draftCount } }
        public var totalDraftBytes: Int64 { buckets.reduce(0) { $0 + $1.draftBytes } }
        public var totalUnreadableCount: Int { buckets.reduce(0) { $0 + $1.unreadableCount } }
        public var totalUnreadableBytes: Int64 { buckets.reduce(0) { $0 + $1.unreadableBytes } }
        /// 목록에 오른 필기 — 확인이 필요한 것과 보관만 하는 예전 필기. 나머지는 자동으로 표시되거나 이미 반영된 것이거나, 지금 계정에서 열어
        /// 보지 않은 것(`unopenedCount`)이다.
        public var hiddenCount: Int { buckets.reduce(0) { $0 + $1.items.count } }
        /// 확인이 필요한 필기 — 절 메뉴의 「확인이 필요한 필기 N」 과 같은 판정이다.
        public var pendingCount: Int { buckets.reduce(0) { $0 + $1.pendingItems.count } }
        /// 보관만 하는 예전 필기.
        public var archivedCount: Int { buckets.reduce(0) { $0 + $1.archivedItems.count } }
        /// 지금 계정에서 열어 보지 않아 **분류하지 않은** 필기.
        public var unopenedCount: Int { buckets.reduce(0) { $0 + $1.inaccessibleCount } }
        /// 지금 현재 필사에 넣을 수 없는 사유. 목록을 읽기 전이면 nil 이지만 넣기 버튼도 없다.
        public var importBlock: SyncedWriteBlock? { stamp?.importBlock }

        /// 그 묶음의 파일(읽지 못한 파일 내보내기 · 지우기)을 다루는가 — 지금 근거로 저장소와 대조한 묶음만(P0-1).
        func opensFiles(in scope: AccountScope) -> Bool {
            buckets.contains { $0.scope == scope && $0.comparedWithStore }
        }

        /// 지금 근거로 불러와 **대조한 묶음**의 필기.
        func comparableItem(id: String) -> Item? {
            buckets.lazy.filter(\.comparedWithStore).flatMap(\.items).first { $0.id == id }
        }
    }

    public enum Action: ViewAction {
        /// 조회 결과. `sequence` 번째 조회가 `stamp` 의 근거로 읽었다.
        case loaded(sequence: Int, stamp: Stamp, [Bucket])
        case failed(sequence: Int, String)
        case view(View)
        /// 편집 환경의 계정 근거가 바뀌었을 수 있다 — 도장이 다르면 앞선 근거로 불러온 목록 · 비교를 버리고 다시 읽는다.
        case environmentChanged(Stamp)

        /// 그 절의 지금 필기를 읽었다 — `stamp` 의 근거로. `check` 는 넣으면 무엇이 되는가(남겨 둔 필기를 다시 읽어 판정한다).
        case currentLoaded(itemID: String, stamp: Stamp, ink: Data?, updatedAt: Date?, check: VerseDraftImportCheck? = nil)
        case currentFailed(itemID: String, stamp: Stamp, String)
        /// 견주려고 다시 읽었더니 그 필기가 바뀌었거나 사라졌다 — 목록을 다시 읽는다.
        case draftChanged(itemID: String, stamp: Stamp)
        /// 넣기 · 바꾸기의 결과.
        case imported(itemID: String, place: String, Result<VerseDraftImporter.Result, ImportFailure>)
        /// 읽지 못한 파일을 지웠다(또는 지우지 못했다).
        case removedUnreadable(String)

        public enum View {
            case onAppear
            /// 화면이 사라졌다 — 편집 환경 구독을 멈춘다.
            case onDisappear
            case reload
            /// 묶음을 펼치거나 접는다.
            case open(AccountScope?)
            /// 「보관만 하는 예전 필기」 를 펼치거나 접는다.
            case toggleArchived(AccountScope)
            /// 필기를 지금 필기와 견주어 본다(다시 누르면 접는다).
            case compare(Item)
            /// 「나중에 확인하기」 — 견주기를 접는다. 필기는 그대로 남는다.
            case closeComparison
            /// 견주고 있는 필기를 넣는다(넣기 · 바꾸기). 지웠던 내용이 다시 들어갈 수 있으면 먼저 묻는다.
            case importTapped
            /// 물은 주의를 확인했다 — 그래도 넣는다.
            case cautionConfirmed
            /// 물은 주의를 닫는다 — 넣지 않는다.
            case cautionCancelled
            /// 읽지 못한 파일 지우기를 묻는다(nil 이면 묻기를 닫는다).
            case askRemoveUnreadable(AccountScope?)
            /// 묻고 받은 뒤 실제로 지운다 — **읽지 못한 파일만**이다.
            case removeUnreadableConfirmed(AccountScope)
        }
    }

    @Dependency(\.verseDraftRecoveryReader) var reader
    @Dependency(\.verseDraftUnreadableCleaner) private var cleaner
    @Dependency(\.drawingRepository) var repository
    @Dependency(\.drawingEditEnvironment) var editEnvironment
    @Dependency(\.drawingVerseImporter) var verseImporter
    @Dependency(\.verseDraftImportMarker) var importMarker
    @Dependency(\.localDrawingChanges) var localChanges
    @Dependency(\.date) var date

    enum CancelID {
        case environment
        case load
        case compare
    }

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .view(.onAppear):
                // 편집 환경의 변화를 구독한다 — 계정이 바뀌면 목록 · 비교를 버리고 다시 읽는다(P0-1).
                let observe = observeEnvironment()
                guard !state.isLoading else { return observe }
                return .merge(observe, startLoad(&state))
            case .view(.onDisappear):
                return .cancel(id: CancelID.environment)
            case .view(.reload):
                guard !state.isLoading else { return .none }
                return startLoad(&state)
            case .environmentChanged(let stamp):
                guard stamp != state.stamp else { return .none }
                Log.info("확인이 필요한 필기 — 계정 근거가 바뀌었다. 불러온 목록 · 비교를 버리고 다시 읽는다")
                invalidate(&state, for: stamp)
                return .merge(.cancel(id: CancelID.compare), startLoad(&state))
            case .view(.open(let scope)):
                state.opened = state.opened == scope ? nil : scope
                closeComparison(&state)
            case .view(.toggleArchived(let scope)):
                if state.archivedOpened.remove(scope) == nil { state.archivedOpened.insert(scope) }
            case .view(.compare(let item)):
                // 넣는 중에는 견줄 필기를 바꾸지 않는다 — 그 결과가 어느 필기의 것인지 흐려진다.
                guard state.importingItemID == nil else { return .none }
                guard state.comparison?.itemID != item.id else {
                    closeComparison(&state)
                    return .cancel(id: CancelID.compare)
                }
                // 지금 근거로 불러온, 저장소와 대조한 묶음의 항목만 견준다.
                guard let stamp = state.stamp, state.comparableItem(id: item.id) != nil else { return .none }
                state.comparison = Comparison(itemID: item.id)
                state.pendingCaution = nil
                return compare(item, stamp: stamp)
            case .view(.closeComparison):
                guard state.importingItemID == nil else { return .none }
                closeComparison(&state)
                return .cancel(id: CancelID.compare)
            case .currentLoaded(let itemID, let stamp, let ink, let updatedAt, let check):
                // 다른 근거로 읽은 필기는 담지 않는다 — 계정이 바뀐 뒤 늦게 온 응답이다.
                guard stamp == state.stamp, state.comparison?.itemID == itemID else { return .none }
                state.comparison?.isLoading = false
                state.comparison?.currentInk = ink
                state.comparison?.currentUpdatedAt = updatedAt
                state.comparison?.check = check
            case .currentFailed(let itemID, let stamp, let message):
                guard stamp == state.stamp, state.comparison?.itemID == itemID else { return .none }
                state.comparison?.isLoading = false
                state.comparison?.failure = message
            case .draftChanged(let itemID, let stamp):
                guard stamp == state.stamp, state.comparison?.itemID == itemID else { return .none }
                closeComparison(&state)
                state.importMessage = ImportMessage(text: DraftRecoveryCopy.draftChanged, needsAttention: true)
                return startLoad(&state)
            case .view(.importTapped):
                return importTapped(&state)
            case .view(.cautionConfirmed):
                return cautionConfirmed(&state)
            case .view(.cautionCancelled):
                state.pendingCaution = nil
            case .imported(let itemID, let place, let result):
                return finishImport(&state, itemID: itemID, place: place, result: result)
            case .view(.askRemoveUnreadable(let scope)):
                // 대조한 묶음의 파일만 다룬다 — 지금 계정에서 열어 보지 않는 묶음은 수 · 용량만 보인다(P0-1).
                guard scope.map({ state.opensFiles(in: $0) }) ?? true else { return .none }
                state.pendingRemoval = state.pendingRemoval == scope ? nil : scope
                state.removalResult = nil
            case .view(.removeUnreadableConfirmed(let scope)):
                guard state.opensFiles(in: scope) else { return .none }
                state.pendingRemoval = nil
                state.isLoading = true
                return removeUnreadable(in: scope)
            case .removedUnreadable(let message):
                state.removalResult = message
                // 지운 뒤에는 다시 세어 보인다 — 남은 것이 있으면 그대로 보여야 한다.
                return startLoad(&state)
            case .loaded(let sequence, let stamp, let buckets):
                // 앞선 조회의 늦은 응답은 버린다 — 더 새 조회가 돌고 있다.
                guard sequence == state.loadSequence else { return .none }
                if stamp != state.stamp {
                    // 이 조회가 본 근거가 들고 있던 목록의 근거와 다르다 — 앞선 근거로 불러온 비교 · 펼침을 먼저 버린다.
                    invalidate(&state, for: stamp)
                }
                state.isLoading = false
                state.buckets = buckets
                if let comparison = state.comparison, !buckets.contains(where: { $0.items.contains { $0.id == comparison.itemID } }) {
                    closeComparison(&state)
                }
                if let opened = state.opened, !buckets.contains(where: { $0.scope == opened }) {
                    state.opened = nil
                }
            case .failed(let sequence, let message):
                guard sequence == state.loadSequence else { return .none }
                state.isLoading = false
                state.failure = message
                state.buckets = []
                closeComparison(&state)
            }
            return .none
        }
    }

    /// 계정 근거가 바뀌었다 — 앞선 근거로 불러온 것을 **모두** 버린다. 다른 계정의 필기 · 자리가 화면 상태에 남지 않게.
    private func invalidate(_ state: inout State, for stamp: Stamp) {
        state.stamp = stamp
        state.buckets = []
        state.opened = nil
        state.archivedOpened = []
        closeComparison(&state)
        state.importingItemID = nil
        state.importMessage = nil
        state.pendingRemoval = nil
        state.removalResult = nil
        state.failure = nil
    }

    /// 견주기를 접는다 — 물은 주의도 함께 닫는다.
    func closeComparison(_ state: inout State) {
        state.comparison = nil
        state.pendingCaution = nil
    }

    /// 새 조회를 시작한다. 앞선 조회는 끊고, 그 응답이 와도 번호가 달라 버린다.
    func startLoad(_ state: inout State) -> Effect<Action> {
        state.loadSequence += 1
        state.isLoading = true
        state.failure = nil
        return load(sequence: state.loadSequence)
    }

    /// 편집 환경의 변화를 구독한다.
    private func observeEnvironment() -> Effect<Action> {
        .run { [editEnvironment] send in
            for await _ in editEnvironment.changes() {
                await send(.environmentChanged(Stamp(await editEnvironment.current())))
            }
        }
        .cancellable(id: CancelID.environment, cancelInFlight: true)
    }

    /// 묶음마다 조회한다. **한 묶음을 읽지 못해도 나머지는 보인다** — 목록 전체를 막으면 멀쩡한 필기까지 보이지 않는다.
    ///
    /// 조회 **전후로** 계정 근거를 본다 — 그 사이 바뀌었으면 결과를 내지 않고 새 근거로 다시 읽게 알린다(P0-1).
    private func load(sequence: Int) -> Effect<Action> {
        .run { [reader, repository, editEnvironment] send in
            guard let reader else {
                await send(.failed(sequence: sequence, "이 iPad의 보존 영역을 열지 못했어요. 앱을 다시 켜 보세요."))
                return
            }
            let environment = await editEnvironment.current()
            let stamp = Stamp(environment)
            let query = VerseDraftRecoveryQuery(reader: reader, repository: repository)
            let scopes: [AccountScope]
            do {
                scopes = try await reader.draftBuckets()
            } catch {
                Log.error("확인이 필요한 필기 — 묶음 목록을 읽지 못했다", "\(error)")
                await send(.failed(sequence: sequence, "이 iPad에 남겨 둔 필기를 읽지 못했어요. 파일은 그대로 있어요."))
                return
            }
            var buckets: [Bucket] = []
            for scope in scopes {
                do {
                    let inventory = try await query.inventory(in: scope, environment: environment)
                    // 내보낼 파일 자리는 목록과 함께 읽는다 — **대조한 묶음만.** 지금 계정에서 열어 보지 않는 묶음은 파일 자리도 들지 않는다(P0-1).
                    // 읽지 못하면 내보내기만 못 하고 나머지는 그대로 보인다.
                    let files = inventory.comparedWithStore ? (try? await reader.unreadableDraftFiles(in: scope)) ?? [] : []
                    buckets.append(Bucket(inventory, files: files, environment: environment))
                } catch {
                    Log.error("확인이 필요한 필기 — 이 묶음을 읽지 못했다", scope.key, "\(error)")
                    buckets.append(Bucket(unreadable: scope, environment: environment))
                }
            }
            let after = Stamp(await editEnvironment.current())
            guard after == stamp else {
                Log.info("확인이 필요한 필기 — 조회하는 사이 계정 근거가 바뀌었다. 이 결과를 버리고 다시 읽는다")
                await send(.environmentChanged(after))
                return
            }
            // 볼 것이 있는 묶음을 먼저, 그 안에서는 지금 계정 · 계정 미확인 · 이 기기 전용 · 다른 계정 차례로.
            await send(.loaded(sequence: sequence, stamp: stamp, buckets.sorted { Self.order($0, $1) }))
        }
        .cancellable(id: CancelID.load, cancelInFlight: true)
    }

    /// **읽지 못한 파일만** 지운다. 필기를 지우는 길은 이 화면에 없다(사용자 결정 2026-09-21).
    private func removeUnreadable(in scope: AccountScope) -> Effect<Action> {
        .run { [cleaner] send in
            guard let cleaner else {
                await send(.removedUnreadable("이 iPad의 보존 영역을 열지 못해 지우지 못했어요."))
                return
            }
            do {
                let removed = try await cleaner.removeUnreadableDraftFiles(in: scope)
                await send(.removedUnreadable("읽지 못한 파일 \(removed)개를 지웠어요."))
            } catch {
                Log.error("확인이 필요한 필기 — 읽지 못한 파일을 지우지 못했다", scope.key, "\(error)")
                await send(.removedUnreadable("읽지 못한 파일을 지우지 못했어요. 파일은 그대로 있어요."))
            }
        }
    }

    private static func order(_ lhs: Bucket, _ rhs: Bucket) -> Bool {
        if lhs.comparedWithStore != rhs.comparedWithStore { return lhs.comparedWithStore }
        return lhs.scope.key < rhs.scope.key
    }
}

// MARK: - 화면의 값

extension DraftRecoveryFeature {
    /// 한 계정 묶음. 화면이 보는 값만 든다.
    public struct Bucket: Hashable, Identifiable, Sendable {
        public var scope: AccountScope
        public var id: String { scope.key }
        /// 사람이 읽는 이름 — 지금 계정 · 계정을 확인하지 못한 동안 · 로그인하지 않은 동안 · 다른 계정.
        public var title: String
        public var draftCount: Int
        public var draftBytes: Int64
        /// 읽지 못해 옆으로 옮긴 파일 — 넣을 수 없고 보관만 한다. 내보내고 지울 수 있는 **유일한** 것이다.
        public var unreadableCount: Int
        public var unreadableBytes: Int64
        /// 그 파일들의 자리 — 내보내기로 넘긴다.
        public var unreadableFiles: [URL]
        /// 저장소와 대조했는가. 아니면 분류 없이 **수 · 용량만** 보인다 — 상세(잉크 · 자리 · 파일 자리)를 만들지 않는다(P0-1).
        public var comparedWithStore: Bool
        /// 지금 계정에서 **열어 보지 않은** 필기 수 — 대조하지 않은 묶음은 전부, 대조한 묶음은 다른 계정을 참고하던 확인 전 필기.
        /// 분류한 적 없는 수다 — "확인이 필요한 필기" 로 부르지 않는다.
        public var inaccessibleCount: Int
        /// 이 묶음을 아예 읽지 못했다 — **필기가 없다는 뜻이 아니다.**
        public var readFailed: Bool
        /// 자동으로 표시되지 않는 필기들. 최근에 쓴 것부터. 확인이 필요한 것과 보관만 하는 예전 필기가 함께 든다.
        public var items: [Item]
        /// 대조하지 못한 장 이름 — 그 장의 필기는 세어졌지만 분류하지 못했다.
        public var unreadChapters: [String]

        /// 확인이 필요한 필기.
        public var pendingItems: [Item] { items.filter(\.needsConfirmation) }
        /// 보관만 하는 예전 필기 — 목록 아래에 접어 둔다.
        public var archivedItems: [Item] { items.filter { !$0.needsConfirmation } }
    }

    /// 목록의 한 줄.
    public struct Item: Hashable, Identifiable, Sendable {
        public var id: String
        /// "창세기 1:3".
        public var place: String
        /// 비교할 때 이 장만 읽는다.
        public var chapter: BibleChapter
        public var verse: Int
        /// 가져올 때 그 초안을 다시 찾는다 — 묶음 · 키 · 사용자가 본 revision.
        public var scope: AccountScope
        public var key: VerseDraftKey
        public var revision: Int
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

        /// 사용자가 확인해야 하는가. 아니면 보관만 하는 예전 필기다.
        public var needsConfirmation: Bool { reason.needsConfirmation }
    }

    /// 견주기 — 지금 필기와 남겨 둔 필기, 그리고 넣으면 무엇이 되는가.
    public struct Comparison: Hashable, Sendable {
        public var itemID: String
        public var isLoading: Bool = true
        /// 그 절의 지금 필기. nil 이면 지금 그 절에는 필기가 없다.
        public var currentInk: Data?
        public var currentUpdatedAt: Date?
        /// 지금 필기를 읽지 못했다 — 없다는 뜻이 아니다.
        public var failure: String?
        /// 넣으면 무엇이 되는가(넣기 · 바꾸기 · 이미 반영됨 · 넣을 수 없음)와 한 번 더 물을 주의. 견주기 전에는 없다.
        public var check: VerseDraftImportCheck?
    }

    /// 가져오기 결과 한 줄.
    public struct ImportMessage: Hashable, Sendable {
        public var text: String
        /// 넣지 못했다 · 다시 확인해야 한다 — 강조한다.
        public var needsAttention: Bool
    }

    /// 가져오기 실패 — 저장소 · 보존 영역을 읽거나 쓰지 못했다. 필기는 그대로다.
    public struct ImportFailure: Error, Hashable {
        public var message: String
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
            inaccessibleCount: inventory.inaccessibleCount,
            readFailed: false,
            items: inventory.entries.map { DraftRecoveryFeature.Item($0, scope: inventory.scope, environment: environment) },
            unreadChapters: inventory.unreadChapters.map { "\($0.title.koreanTitle()) \($0.chapter)장" }
        )
    }

    /// 묶음을 아예 읽지 못했다. 개수도 세지 못하므로 0 이 아니라 "읽지 못함" 으로 보인다.
    init(unreadable scope: AccountScope, environment: DrawingEditEnvironment) {
        self.init(
            scope: scope, title: DraftRecoveryCopy.bucketTitle(scope, environment: environment),
            draftCount: 0, draftBytes: 0, unreadableCount: 0, unreadableBytes: 0, unreadableFiles: [],
            comparedWithStore: false, inaccessibleCount: 0, readFailed: true, items: [], unreadChapters: []
        )
    }
}

extension DraftRecoveryFeature.Item {
    init(_ entry: VerseDraftRecoveryEntry, scope: AccountScope, environment: DrawingEditEnvironment) {
        let key = entry.draft.key
        self.init(
            id: "\(scope.key)/\(key.sessionID)/\(key.title)/\(key.chapter)/\(key.verse)",
            place: DraftRecoveryCopy.place(key),
            chapter: BibleChapter(title: BibleTitle(rawValue: key.title) ?? .genesis, chapter: key.chapter),
            verse: key.verse,
            scope: scope,
            key: key,
            revision: entry.draft.revision,
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
