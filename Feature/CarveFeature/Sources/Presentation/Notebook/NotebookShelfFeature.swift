//
//  NotebookShelfFeature.swift
//  CarveFeature
//
//  Created by Claude on 10/15/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import CarveToolkit
import ClientInterfaces
import Domain
import Foundation

import ComposableArchitecture

/// 책장 — 필사책을 고르고 관리하는 화면(2.2 회차별 필사책, 설계 `docs/notebook-design.md` §6-1 ~ §6-7).
///
/// 차트 · 즐겨찾기처럼 앱 스택에 올라간다(`AppCoordinatorFeature.Path.notebooks`). 진입은 서재 열 아래 아이콘 줄의 「책장」 ·
/// 번역본 팝오버의 「책장 열기」 · 실행 인자 `-UITestRoute notebooks` 다. 다른 화면으로 가는 일은 위임(`Delegate`)으로만 알리고,
/// 코디네이터가 path 와 필사 화면(`CarveNavigationFeature.switchNotebook`)을 바꾼다.
///
/// - 목록은 나타날 때 · iCloud 도착 · 관리 동작 뒤에만 읽는다 — `notebookRepository.notebooks()` 는 모든 행을 훑는다(행 1만 개에 약 0.2초).
/// - **관리 동작(만들기 · 이름 바꾸기 · 완료 표시 · 지우기)은 동기화 저장소에 쓰기 전에 `SyncedWriteBlock` 을 본다** — 즐겨찾기 · 백업 불러오기와 같은 규칙이다.
///   막히면 저장소를 부르지 않고 지금 필사책 키 · 위임도 바꾸지 않은 채 사유를 알린다. 연결이 보류됐거나(무계정 · 소유 미확인) 계정을 확인하지 못한
///   저장소는 CloudKit 없이 열려 있어, 거기 쓴 필사책 정보 · 지운 행이 나중에 계정과 어긋난다(정책 §12-6 C14 ③ · D2).
///   그래서 무계정 기기는 필사책을 만들 수 없다(의도한 결과 — 2.1 무계정도 즐겨찾기 · 저장소 쓰기가 막혀 기기 안 초안으로 쓴다).
///   **고르기(카드 누르기)는 지금 필사책 키만 바꿔 막지 않는다.**
@Reducer
public struct NotebookShelfFeature: Sendable {
    public init() { }

    @ObservableState
    public struct State: Equatable, Sendable {
        /// 처음 상태. 지금 필사책 키(`@Shared`)를 담아 만들 때의 의존성(UserDefaults)에 묶이므로, 한 번만 만드는 `static let` 대신 부를 때마다 만든다.
        public static var initialState: Self { Self() }

        /// 책장의 필사책 — 저장소 순서(기본 필사책이 첫째, 나머지는 만든 순).
        var notebooks: IdentifiedArrayOf<NotebookSnapshot> = []
        /// 첫 조회가 끝났는가 — 조회 중에 실패 화면이 깜빡이지 않게 한다.
        var hasLoaded = false
        /// 조회가 실패했고 보일 목록이 없다 — 카드 대신 「다시 시도」 를 둔다.
        var loadFailed = false
        /// 마지막으로 목록을 읽기 시작한 시각 — 이보다 늦지 않은 iCloud 도착 신호는 이미 읽은 목록에 들어 있다.
        var listRequestedAt: Date?
        /// 지금 필사책의 `NotebookID.rawValue`(기기마다, 결정 13) — 카드의 「지금 쓰는 중」. 읽을 때는 `currentNotebook` 을 쓴다.
        @Shared(.currentNotebookID) var currentNotebookID: String
        /// 이름 시트(새 필사책 · 이름 바꾸기). nil 이면 닫혀 있다.
        var editor: NameEditor?
        /// 필사책 지우기 확인창.
        @Presents var deleteAlert: AlertState<Action.DeleteAlert>?
        /// 완료 표시 · 지우기를 저장하는 중 — 같은 동작이 겹치지 않게 카드를 막는다.
        var isWorking = false
        /// 책장 아래 결과 안내 — 저장소에 쓰지 않고 막음 · 완료 표시 · 지우기 실패. 저절로 사라진다.
        var notice: Notice?

        public init() { }

        /// 지금 필사책. 저장값이 필사책 ID 형식이 아니면(깨진 값) 기본 필사책이다.
        var currentNotebook: NotebookID {
            NotebookID(rawValue: currentNotebookID) ?? .default
        }
    }

    /// 이름 시트 — 새 필사책을 만들거나 이름을 바꾼다. 입력은 시트가 갖고, 저장할 때 리듀서로 보낸다.
    public struct NameEditor: Equatable, Sendable, Identifiable {
        /// 무엇을 위한 시트인가.
        public enum Purpose: Equatable, Sendable {
            /// 새 필사책 — 입력란에 제안 이름(`NotebookNaming.suggestedName`, 뷰가 화면 언어로 짓는다).
            case create
            /// 그 필사책의 이름 바꾸기(기본 필사책 포함) — 입력란에 지금 보이는 이름.
            case rename(NotebookID)
        }

        /// 무엇을 위한 시트인가.
        public var purpose: Purpose
        /// 저장하는 중 — 저장 · 취소 버튼과 끌어내려 닫기를 막는다.
        public var isSaving = false
        /// 저장하지 못했거나 막은 까닭 — 시트 안에 보인다. 다시 저장하면 지운다.
        public var failure: Failure?

        public var id: String {
            switch purpose {
            case .create: "create"
            case .rename(let notebook): "rename-\(notebook.rawValue)"
            }
        }
    }

    /// 이름 시트에서 저장소에 쓰지 못한 까닭.
    public enum Failure: Equatable, Sendable {
        /// 저장하지 못했다.
        case saveFailed
        /// 동기화 저장소에 쓰지 않고 막았다 — 계정 · 연결 근거가 없다(정책 §12-6 결정 1).
        case blocked(SyncedWriteBlock)
    }

    /// 책장 아래 결과 안내.
    public enum Notice: Equatable, Sendable {
        /// 저장소에 쓰지 않고 막았다 — 만들기 · 이름 바꾸기 · 완료 표시 · 지우기.
        case blocked(SyncedWriteBlock)
        /// 완료 표시를 바꾸지 못했다.
        case completionFailed
        /// 필사책을 지우지 못했다.
        case deleteFailed
    }

    /// 저장소에 쓰는 관리 동작 — 쓰기 전에 동기화 저장소에 써도 되는지 본다.
    public enum Write: Equatable, Sendable {
        /// 새 필사책 만들기.
        case create
        /// 이름 바꾸기.
        case rename(NotebookID)
        /// 완료로 표시 · 완료 취소.
        case completion(NotebookID)
        /// 지우기.
        case delete(NotebookID)
    }

    public enum Action: ViewAction {
        case view(View)
        case delegate(Delegate)
        /// 필사책 목록을 읽었다.
        case notebooksLoaded([NotebookSnapshot])
        /// 필사책 목록을 읽지 못했다.
        case notebooksLoadFailed
        /// iCloud 에서 받은 것이 저장소에 들어왔을 수 있다 — 그 import 가 끝난 시각(`CloudImportArrivalClient`).
        case cloudImportArrived(Date)
        /// 이름 시트를 열기 전에 동기화 저장소에 써도 되는지 봤다 — 막혔으면 그 사유(nil 이면 연다).
        case editorWriteChecked(NameEditor.Purpose, SyncedWriteBlock?)
        /// 관리 동작을 동기화 저장소에 쓰지 않고 막았다 — 저장소 · 지금 필사책 키 · 위임은 그대로다.
        case writeBlocked(Write, SyncedWriteBlock)
        /// 새 필사책을 만들었다.
        case created(NotebookID)
        /// 필사책 이름을 바꿨다.
        case renamed(NotebookID)
        /// 이름 시트의 저장(만들기 · 이름 바꾸기)이 실패했다.
        case editorSaveFailed
        /// 완료 표시를 바꿨다.
        case completionChanged(NotebookID)
        /// 완료 표시를 바꾸지 못했다.
        case completionFailed(NotebookID)
        /// 지우기 확인 뒤 동기화 저장소에 써도 된다 — 지금 필사책이면 기본으로 돌린 뒤 지운다.
        case deletePermitted(NotebookID)
        /// 필사책과 그 필기 · 기기 안 초안을 지웠다.
        case deleted(NotebookID)
        /// 필사책을 지우지 못했다.
        case deleteFailed(NotebookID)
        /// 책장 아래 안내를 내린다.
        case noticeExpired
        /// 필사책 지우기 확인창.
        case deleteAlert(PresentationAction<DeleteAlert>)

        /// 지우기 확인창의 버튼.
        public enum DeleteAlert: Equatable, Sendable {
            /// 「모두 지우기」 — 그 필사책과 필기를 지운다.
            case confirm(NotebookID)
        }

        @CasePathable
        public enum View {
            /// 책장이 화면에 나타났다 — 목록을 읽고 iCloud 도착을 듣는다.
            case onAppear
            /// 「닫기」 — 필사 화면으로 돌아간다.
            case backTapped
            /// 목록을 읽지 못한 화면의 「다시 시도」.
            case retryLoadTapped
            /// 필사책 카드를 눌렀다 — 그 필사책으로 필사 화면에 돌아간다.
            case notebookTapped(NotebookID)
            /// 「새 필사책」 카드를 눌렀다 — 이름 시트를 연다.
            case newNotebookTapped
            /// 카드 메뉴의 「이름 바꾸기」.
            case renameTapped(NotebookID)
            /// 카드 메뉴의 「완료로 표시」 · 「완료 취소」.
            case completionToggled(NotebookID)
            /// 카드 메뉴의 「필사책 지우기」 — 확인창을 띄운다(기본 필사책에는 없다).
            case deleteTapped(NotebookID)
            /// 이름 시트의 「만들기」 · 「저장」 — 입력한 이름(자르기 · 검사는 리듀서가 한다).
            case editorSaveTapped(String)
            /// 이름 시트를 닫았다(「취소」 · 끌어내림).
            case editorDismissed
        }

        @CasePathable
        public enum Delegate {
            /// 필사책을 골랐다(만든 필사책 포함) — 코디네이터가 책장을 닫고 필사 화면을 그 필사책으로 바꾼다.
            case notebookChosen(NotebookID)
            /// 책장에 머문 채 지금 필사책이 바뀌었다 — 지금 필사책을 지워 기본 필사책으로 돌아갈 때, 그리고 지금 필사책의 이름을 바꿨을 때(같은 ID —
            /// 필사 화면은 장을 다시 열지 않고 헤더 이름만 다시 읽는다). 코디네이터가 책장은 둔 채 필사 화면만 바꾼다.
            case currentNotebookChanged(NotebookID)
            /// 필사 화면으로 돌아간다 — 코디네이터가 책장을 닫는다.
            case backToWriting
        }
    }

    /// 비동기 작업 취소용 ID.
    enum CancelID: Hashable {
        /// 목록 조회 — 새로 읽으면 앞 조회를 버린다.
        case load
        /// iCloud 도착 구독 — 다시 나타나면 하나만 남긴다. 책장이 닫히면 코디네이터의 path 가 효과를 모두 끊는다.
        case arrivals
        /// 책장 아래 안내의 자동 닫힘.
        case notice
    }

    /// 책장 아래 안내가 머무는 시간.
    static let noticeDuration: Duration = .seconds(4)

    @Dependency(\.notebookRepository) var notebookRepository
    @Dependency(\.notebookDraftDiscarder) var notebookDraftDiscarder
    @Dependency(\.drawingEditEnvironment) var drawingEditEnvironment
    @Dependency(\.cloudImportArrivals) var cloudImportArrivals
    @Dependency(\.analyticsClient) var analyticsClient
    @Dependency(\.uuid) var uuid
    @Dependency(\.date) var date
    @Dependency(\.continuousClock) var clock

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .view(let viewAction):
                return reduceView(viewAction, state: &state)

            case .notebooksLoaded(let notebooks):
                // 저장소가 ID 마다 하나로 합쳐 주지만, 같은 ID 가 섞여 와도 목록이 깨지지 않게 앞의 것을 남긴다.
                state.notebooks = IdentifiedArray(notebooks, uniquingIDsWith: { first, _ in first })
                state.hasLoaded = true
                state.loadFailed = false
                return .none

            case .notebooksLoadFailed:
                state.hasLoaded = true
                // 이미 보인 목록이 있으면 그대로 둔다 — 도착 · 관리 동작 뒤에 다시 읽는다.
                state.loadFailed = state.notebooks.isEmpty
                return .none

            case .cloudImportArrived(let arrival):
                // 구독할 때 오는 마지막 import 처럼 목록을 읽기 시작한 때보다 이른 도착은 이미 읽은 목록에 들어 있다.
                if let requested = state.listRequestedAt, arrival <= requested { return .none }
                return loadNotebooks(state: &state)

            case let .editorWriteChecked(purpose, block):
                if let block { return showNotice(.blocked(block), state: &state) }
                state.editor = NameEditor(purpose: purpose)
                return .none

            case let .writeBlocked(write, block):
                return reduceBlocked(write, block: block, state: &state)

            case .created(let notebook):
                return finishCreate(notebook, state: &state)

            case .renamed(let notebook):
                state.editor = nil
                let reload = loadNotebooks(state: &state)
                // 지금 필사책의 이름이 바뀌었다 — 필사 화면 헤더가 이름을 다시 읽게 알린다. 같은 ID 라 필사 화면은 장을 다시 열지 않는다.
                guard notebook == state.currentNotebook else { return reload }
                return .concatenate(.send(.delegate(.currentNotebookChanged(notebook))), reload)

            case .editorSaveFailed:
                state.editor?.isSaving = false
                state.editor?.failure = .saveFailed
                return .none

            case .completionChanged:
                state.isWorking = false
                return loadNotebooks(state: &state)

            case .completionFailed:
                state.isWorking = false
                return showNotice(.completionFailed, state: &state)

            case .deletePermitted(let notebook):
                return delete(notebook, state: &state)

            case .deleted(let notebook):
                state.isWorking = false
                state.notebooks.remove(id: notebook)
                return loadNotebooks(state: &state)

            case .deleteFailed:
                state.isWorking = false
                return showNotice(.deleteFailed, state: &state)

            case .noticeExpired:
                state.notice = nil
                return .none

            case .deleteAlert(.presented(.confirm(let notebook))):
                return confirmDelete(notebook, state: &state)

            case .deleteAlert:
                return .none

            case .delegate:
                return .none
            }
        }
        .ifLet(\.$deleteAlert, action: \.deleteAlert)
    }
}

// MARK: - 화면 동작

extension NotebookShelfFeature {
    /// 역할: 화면에서 온 동작을 처리한다.
    /// 입력 · 출력: 화면 동작 · 상태 → 효과(목록 조회 · 저장 · 위임).
    /// 부작용: 상태를 바꾼다. 저장소 호출은 돌려준 효과가 한다.
    private func reduceView(_ action: Action.View, state: inout State) -> Effect<Action> {
        switch action {
        case .onAppear:
            // 다시 나타나도(가려졌다 돌아옴) 구독은 하나만 남는다 — 같은 취소 ID 로 앞 구독을 끊는다.
            return .merge(loadNotebooks(state: &state), observeCloudImports())

        case .backTapped:
            return .send(.delegate(.backToWriting))

        case .retryLoadTapped:
            return loadNotebooks(state: &state)

        case .notebookTapped(let notebook):
            // 고르기는 지금 필사책 키만 바꾸므로 동기화 저장소 쓰기 검사를 하지 않는다. 지우는 중에는 고르지 않는다.
            guard !state.isWorking, state.notebooks[id: notebook] != nil else { return .none }
            return .send(.delegate(.notebookChosen(notebook)))

        case .newNotebookTapped:
            guard state.editor == nil else { return .none }
            return checkEditorWrite(.create)

        case .renameTapped(let notebook):
            guard state.editor == nil, state.notebooks[id: notebook] != nil else { return .none }
            return checkEditorWrite(.rename(notebook))

        case .completionToggled(let notebook):
            return toggleCompletion(notebook, state: &state)

        case .deleteTapped(let notebook):
            // 기본 필사책은 지울 수 없다(결정 7) — 카드 메뉴에도 없다.
            guard !state.isWorking, !notebook.isDefault, let snapshot = state.notebooks[id: notebook] else { return .none }
            state.deleteAlert = Self.deleteAlert(snapshot, locale: AppLanguage.displayLocale())
            return .none

        case .editorSaveTapped(let input):
            return saveEditor(input, state: &state)

        case .editorDismissed:
            state.editor = nil
            return .none
        }
    }
}

// MARK: - 목록

extension NotebookShelfFeature {
    /// 역할: 필사책 목록을 읽는다.
    /// 입력 · 출력: 상태 → 조회 효과(`notebooksLoaded` · `notebooksLoadFailed`). 새로 읽으면 앞 조회를 버린다.
    /// 부작용: 읽기 시작한 시각(`listRequestedAt`)을 남긴다.
    private func loadNotebooks(state: inout State) -> Effect<Action> {
        state.listRequestedAt = date.now
        return .run { send in
            do {
                await send(.notebooksLoaded(try await notebookRepository.notebooks()))
            } catch {
                Log.error("필사책 목록을 읽지 못했다", error)
                await send(.notebooksLoadFailed)
            }
        }
        .cancellable(id: CancelID.load, cancelInFlight: true)
    }

    /// 역할: iCloud 에서 받은 것이 저장소에 들어올 때마다 알린다(`cloudImportArrived`). 구독 시점의 마지막 도착도 한 번 온다.
    /// 입력 · 출력: 없음 → 구독 효과. 책장이 닫히면 코디네이터의 path 가 끊는다.
    /// 부작용: 없음.
    private func observeCloudImports() -> Effect<Action> {
        .run { send in
            for await arrival in cloudImportArrivals.arrivals() {
                await send(.cloudImportArrived(arrival))
            }
        }
        .cancellable(id: CancelID.arrivals, cancelInFlight: true)
    }
}

// MARK: - 관리 동작

extension NotebookShelfFeature {
    /// 역할: 지금 환경에서 동기화 저장소에 쓰면 안 되는 사유를 본다(정책 §12-6 결정 1 — 즐겨찾기 · 백업 불러오기와 같은 판정).
    /// 입력 · 출력: 없음 → 막는 사유, 써도 되면 nil.
    /// 부작용: 없음(편집 환경을 읽기만 한다).
    private func writeBlock() async -> SyncedWriteBlock? {
        SyncedWriteBlock.check(await drawingEditEnvironment.current())
    }

    /// 역할: 이름 시트를 열기 전에 쓸 수 있는지 본다 — 막혔으면 이름을 쓰게 하지 않고 바로 사유를 알린다. 저장할 때 다시 본다.
    /// 입력 · 출력: 시트 용도 → 판정 효과(`editorWriteChecked`).
    /// 부작용: 없음.
    private func checkEditorWrite(_ purpose: NameEditor.Purpose) -> Effect<Action> {
        .run { send in
            let block = await writeBlock()
            await send(.editorWriteChecked(purpose, block))
        }
    }

    /// 역할: 이름 시트의 저장 — 새 필사책을 만들거나 이름을 바꾼다.
    /// 입력 · 출력: 입력한 이름 · 상태 → 저장 효과(`created` · `renamed` · `editorSaveFailed` · `writeBlocked`).
    ///   앞뒤 공백을 자르고, 비었거나 40자를 넘으면 받지 않는다(효과 없음). 이름을 바꾸지 않았으면 쓰지 않고 시트를 닫는다.
    /// 부작용: 시트를 저장 중으로 둔다. 새 필사책 ID 는 `@Dependency(\.uuid)`, 시각은 `@Dependency(\.date)` 로 지금 정해 효과에 넘긴다.
    private func saveEditor(_ input: String, state: inout State) -> Effect<Action> {
        guard var editor = state.editor, !editor.isSaving else { return .none }
        guard let name = NotebookNaming.validatedName(input) else { return .none }
        let now = date.now
        switch editor.purpose {
        case .create:
            let notebook = NotebookID.make(uuid: uuid())
            editor.isSaving = true
            editor.failure = nil
            state.editor = editor
            return .run { send in
                if let block = await writeBlock() {
                    await send(.writeBlocked(.create, block))
                    return
                }
                do {
                    try await notebookRepository.create(id: notebook, name: name, now: now)
                    await send(.created(notebook))
                } catch {
                    Log.error("새 필사책을 만들지 못했다", error)
                    await send(.editorSaveFailed)
                }
            }

        case .rename(let notebook):
            if state.notebooks[id: notebook]?.name == name {
                state.editor = nil
                return .none
            }
            editor.isSaving = true
            editor.failure = nil
            state.editor = editor
            return .run { send in
                if let block = await writeBlock() {
                    await send(.writeBlocked(.rename(notebook), block))
                    return
                }
                do {
                    try await notebookRepository.rename(notebook, to: name, now: now)
                    await send(.renamed(notebook))
                } catch {
                    Log.error("필사책 이름을 바꾸지 못했다", error)
                    await send(.editorSaveFailed)
                }
            }
        }
    }

    /// 역할: 새 필사책을 만든 뒤 — 지금 필사책 키를 새 ID 로 쓰고, 분석을 남기고, 고른 것을 알린다(결정 6 — 지금 보던 장이 빈 종이로 열린다).
    /// 입력 · 출력: 새 필사책 · 상태 → 분석 · 위임(`notebookChosen`) 효과. 코디네이터가 책장을 닫고 필사 화면을 그 필사책으로 다시 연다.
    /// 부작용: 지금 필사책 키(UserDefaults)를 쓴다.
    private func finishCreate(_ notebook: NotebookID, state: inout State) -> Effect<Action> {
        state.editor = nil
        state.$currentNotebookID.withLock { $0 = notebook.rawValue }
        return .concatenate(
            .run { _ in
                analyticsClient.trackFeatureComplete(.notebook, success: true)
            },
            .send(.delegate(.notebookChosen(notebook)))
        )
    }

    /// 역할: 완료로 표시하거나 완료를 취소한다 — 표시일 뿐 계속 쓸 수 있다(결정 7).
    /// 입력 · 출력: 필사책 · 상태 → 저장 효과(`completionChanged` · `completionFailed` · `writeBlocked`).
    /// 부작용: 저장하는 동안 카드를 막는다.
    private func toggleCompletion(_ notebook: NotebookID, state: inout State) -> Effect<Action> {
        guard !state.isWorking, let snapshot = state.notebooks[id: notebook] else { return .none }
        state.isWorking = true
        let completed = snapshot.status != .completed
        let now = date.now
        return .run { send in
            if let block = await writeBlock() {
                await send(.writeBlocked(.completion(notebook), block))
                return
            }
            do {
                try await notebookRepository.setCompleted(notebook, completed, now: now)
                await send(.completionChanged(notebook))
            } catch {
                Log.error("필사책 완료 표시를 바꾸지 못했다", error)
                await send(.completionFailed(notebook))
            }
        }
    }

    /// 역할: 지우기 확인 뒤 — 쓰기 전에 동기화 저장소에 써도 되는지 본다. 막혔으면 키 · 위임도 바꾸지 않는다(보류 중에 필사 행을 지우지 않는다).
    /// 입력 · 출력: 필사책 · 상태 → 판정 효과(`deletePermitted` · `writeBlocked`). 기본 필사책이면 없음.
    /// 부작용: 지우는 동안 카드를 막는다.
    private func confirmDelete(_ notebook: NotebookID, state: inout State) -> Effect<Action> {
        guard !state.isWorking, !notebook.isDefault else { return .none }
        state.isWorking = true
        return .run { send in
            if let block = await writeBlock() {
                await send(.writeBlocked(.delete(notebook), block))
                return
            }
            await send(.deletePermitted(notebook))
        }
    }

    /// 역할: 필사책을 지운다(설계 §6-6). 순서 — ① 지금 필사책이면 먼저 키를 기본으로 하고 `currentNotebookChanged(.default)` 를 알린다
    ///   (코디네이터가 필사 화면에 `switchNotebook(.default)` 를 보내 앞 page 의 미저장분을 앞 page 로 저장하고 기본 필사책을 다시 읽는다)
    ///   ② `notebookRepository.delete` — 그 필사책의 행 전부 + 정보 레코드 전부 ③ 그 필사책의 기기 안 초안 `discardDrafts(notebook:)`.
    /// - Important: 알려진 한계 — ① 의 늦은 저장(앞 page 의 미저장분)과 ② 의 지우기는 같은 SwiftData actor 에서 순서가 보장되지 않는다.
    ///   저장이 지우기 뒤에 들어가면 그 행이 「이름 없는 필사책」 으로 되살아난다(혼재 규칙 ⑥ — 숨기거나 합치지 않고, 다시 지울 수 있다).
    /// 입력 · 출력: 필사책 · 상태 → 위임 · 지우기 효과(`deleted` · `deleteFailed`).
    /// 부작용: 지금 필사책이면 키(UserDefaults)를 기본으로 쓴다.
    private func delete(_ notebook: NotebookID, state: inout State) -> Effect<Action> {
        var steps: [Effect<Action>] = []
        if notebook == state.currentNotebook {
            state.$currentNotebookID.withLock { $0 = NotebookID.default.rawValue }
            steps.append(.send(.delegate(.currentNotebookChanged(.default))))
        }
        steps.append(.run { send in
            do {
                try await notebookRepository.delete(notebook)
            } catch {
                Log.error("필사책을 지우지 못했다", error)
                await send(.deleteFailed(notebook))
                return
            }
            // 그 필사책의 기기 안 초안도 버린다 — 남기면 설정의 「확인이 필요한 필기」 에 지운 필사책의 필기로 남는다.
            // 초안을 다 버리지 못해도 지우기는 끝났다(다시 지우면 지운다).
            if let discarder = notebookDraftDiscarder {
                do {
                    _ = try await discarder.discardDrafts(notebook: notebook)
                } catch {
                    Log.error("지운 필사책의 기기 안 초안을 다 버리지 못했다", error)
                }
            }
            await send(.deleted(notebook))
        })
        return .concatenate(steps)
    }

    /// 역할: 동기화 저장소에 쓰지 않고 막은 관리 동작을 정리하고 사유를 알린다.
    /// 입력 · 출력: 막은 동작 · 사유 · 상태 → 안내 효과. 이름 시트의 저장이면 시트 안에 보인다(입력은 그대로).
    /// 부작용: 저장 중 표시를 푼다.
    private func reduceBlocked(_ write: Write, block: SyncedWriteBlock, state: inout State) -> Effect<Action> {
        switch write {
        case .create, .rename:
            guard state.editor != nil else { return showNotice(.blocked(block), state: &state) }
            state.editor?.isSaving = false
            state.editor?.failure = .blocked(block)
            return .none
        case .completion, .delete:
            state.isWorking = false
            return showNotice(.blocked(block), state: &state)
        }
    }

    /// 역할: 책장 아래 안내를 띄우고 잠시 뒤 내린다.
    /// 입력 · 출력: 안내 · 상태 → 자동 닫힘 효과(`noticeExpired`). 새 안내가 오면 앞 타이머를 버린다.
    /// 부작용: 없음(`clock` 으로 기다린다).
    private func showNotice(_ notice: Notice, state: inout State) -> Effect<Action> {
        state.notice = notice
        return .run { send in
            try await clock.sleep(for: Self.noticeDuration)
            await send(.noticeExpired)
        }
        .cancellable(id: CancelID.notice, cancelInFlight: true)
    }

    /// 역할: 필사책 지우기 확인창(설계 §6-6) — 「『<이름>』 과 그 필기를 모두 지울까요?」 · 「되돌릴 수 없어요.」.
    /// 입력 · 출력: 필사책 · 로케일(리듀서는 띄우는 순간의 `AppLanguage.displayLocale()`, 시험은 고른 로케일) → 확인창.
    /// 부작용: 없음.
    static func deleteAlert(_ notebook: NotebookSnapshot, locale: Locale) -> AlertState<Action.DeleteAlert> {
        let name = NotebookNaming.displayName(of: notebook, locale: locale)
        return AlertState {
            TextState(verbatim: CarveFeatureCatalog.string("『\(name)』 과 그 필기를 모두 지울까요?", locale: locale))
        } actions: {
            ButtonState(role: .cancel) {
                TextState(verbatim: CarveFeatureCatalog.string("취소", locale: locale))
            }
            ButtonState(role: .destructive, action: .confirm(notebook.id)) {
                TextState(verbatim: CarveFeatureCatalog.string("모두 지우기", locale: locale))
            }
        } message: {
            TextState(verbatim: CarveFeatureCatalog.string("되돌릴 수 없어요.", locale: locale))
        }
    }
}
