//
//  FavoriteListFeature.swift
//  CarveFeature
//
//  Created by Claude on 9/15/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import CarveToolkit
import Domain
import Foundation

import ComposableArchitecture

/// 즐겨찾기 목록(시안 N4 · N5). 사이드바의 별 버튼으로 들어온다.
///
/// 최근 추가순으로 권 · 장 · 절과 번역본, **추가할 때의** 본문 · 필기, 추가 날짜를 보여 준다.
/// 카드의 채운 별은 해제 버튼이고 해제 직후 「실행 취소」 를 준다. 해제는 즐겨찾기만 지운다 — 원래 필사와 이전 필사 기록은 그대로다.
/// 「말씀으로 이동」 은 그 장 · 절의 필사 화면으로 돌아가며, 보존한 필기를 캔버스에 덮어쓰지 않는다.
@Reducer
public struct FavoriteListFeature {
    public init() { }

    @ObservableState
    public struct State: Equatable {
        public static var initialState: Self { Self() }

        /// 최근 추가순 즐겨찾기.
        var favorites: IdentifiedArrayOf<FavoriteVerseSnapshot> = []
        /// 첫 조회가 끝났는가. 조회 중에 빈 상태가 깜빡이지 않게 한다.
        var hasLoaded = false
        /// 마지막 조회가 실패했다. 빈 목록과 구분해 「다시 시도」 를 둔다.
        var loadFailed = false
        /// 목록 아래 안내 — 해제 직후 실행 취소 · 저장 실패 · 위젯 변경 결과.
        var notice: Notice?
        /// 지금 위젯에 담긴 말씀들(시안 N4 배지 · N6 메뉴). 이 기기에만 둔다.
        var widgetKeys: Set<FavoriteVerseKey> = []
        /// 위젯에 담긴 말씀을 바꾸는 중. 같은 요청이 겹치지 않게 한다.
        var isChangingWidget = false
        /// 위젯에 담긴 말씀을 해제하려 할 때의 확인창(시안 N9).
        @Presents var removeConfirm: AlertState<Action.RemoveConfirm>?

        public init() { }
    }

    /// 목록 아래 안내. 버튼은 하나이고 무엇을 할지는 안내 종류가 정한다.
    public enum Notice: Equatable, Sendable {
        /// 방금 해제했다. 「실행 취소」 는 이 항목을 추가 시각 그대로 다시 저장한다.
        case removed(FavoriteVerseSnapshot)
        /// 해제하지 못했다 — 항목은 목록에 되돌려 두었다. 「다시 시도」 는 다시 해제한다.
        case removeFailed(FavoriteVerseKey)
        /// 실행 취소를 저장하지 못했다 — 항목은 목록에서 다시 빠졌다. 「다시 시도」 는 다시 되돌린다.
        case restoreFailed(FavoriteVerseSnapshot)
        /// 이 말씀을 위젯에 담았다.
        case widgetAdded
        /// 위젯에서 뺐다. 즐겨찾기는 남는다.
        case widgetRemoved
        /// 위젯이 꽉 차 담지 못했다.
        case widgetLimitReached
        /// 위젯에 담긴 말씀을 바꾸지 못했다. 「다시 시도」 는 같은 변경을 다시 보낸다.
        case widgetFailed(WidgetChange)
        /// 해제 · 되돌리기를 동기화 저장소에 쓰지 않고 막았다 — 사유를 보인다(정책 §12-6 결정 1). 목록은 그대로다.
        case blocked(SyncedWriteBlock)
    }

    /// 동기화 저장소에 쓰지 않고 막은 목록 변경. 먼저 바꿔 둔 목록 · 배지를 되돌린다.
    public enum BlockedWrite: Equatable, Sendable {
        /// 해제. `fromWidget` 이면 위젯에서도 빼려던 것이다.
        case remove(FavoriteVerseSnapshot, fromWidget: Bool)
        /// 실행 취소(다시 저장).
        case restore(FavoriteVerseSnapshot)
    }

    /// 위젯에 담긴 말씀의 변경 하나. 실패하면 이 값 그대로 다시 시도한다.
    public enum WidgetChange: Equatable, Sendable {
        /// 이 보관본을 위젯에 담는다 — 이미 담긴 말씀은 그대로 둔다.
        case add(FavoriteVerseSnapshot)
        /// 이 말씀을 위젯에서 뺀다.
        case remove(FavoriteVerseKey)
    }

    public enum Action: ViewAction {
        case view(View)
        /// 목록을 읽었다.
        case favoritesLoaded(Result<[FavoriteVerseSnapshot], any Error>)
        /// 해제 저장이 끝났다.
        case removeFinished(FavoriteVerseSnapshot, failed: Bool)
        /// 실행 취소(다시 저장)가 끝났다.
        case restoreFinished(FavoriteVerseSnapshot, failed: Bool)
        /// 해제 · 되돌리기를 동기화 저장소에 쓰지 않고 막았다 — 소유가 확인되지 않았다(정책 §12-6 결정 1).
        case writeBlocked(BlockedWrite, SyncedWriteBlock)
        /// 안내를 내린다.
        case noticeExpired
        /// 지금 위젯에 담긴 말씀들을 읽었다.
        case widgetSelectionLoaded([FavoriteVerseKey])
        /// 위젯 변경이 끝났다.
        case widgetChangeFinished(WidgetChange, failed: Bool)
        /// 위젯에 담긴 말씀의 해제 확인창(시안 N9).
        case removeConfirm(PresentationAction<RemoveConfirm>)
        case delegate(Delegate)

        /// 해제 확인창의 버튼.
        public enum RemoveConfirm: Equatable, Sendable {
            /// 「해제하기」 — 즐겨찾기를 해제하고 위젯에서도 뺀다.
            case confirm(FavoriteVerseKey)
        }

        @CasePathable
        public enum View {
            /// 화면이 나타났다 — 목록을 읽는다.
            case task
            /// 조회 실패 상태의 「다시 시도」.
            case retryLoadTapped
            /// 카드의 채운 별 — 즐겨찾기 해제.
            case unfavoriteTapped(FavoriteVerseKey)
            /// 카드 더보기의 「위젯에 추가」 · 「위젯에서 빼기」(시안 N6).
            case widgetTapped(FavoriteVerseKey)
            /// 안내의 버튼 — 「실행 취소」 또는 「다시 시도」.
            case noticeActionTapped
            /// 카드의 「말씀으로 이동」.
            case openVerseTapped(FavoriteVerseKey)
            /// 빈 목록의 「말씀 보러 가기」.
            case backToWritingTapped
        }

        @CasePathable
        public enum Delegate {
            /// 필사 화면으로 돌아간다.
            case backToWriting
            /// 이 절의 필사 화면으로 이동한다.
            case openVerse(BibleVerse)
            /// 목록에서 즐겨찾기가 바뀌었다 — 필사 화면의 별 표시를 다시 읽게 한다.
            case favoritesChanged
        }
    }

    enum CancelID {
        /// 안내 자동 닫힘.
        case notice
    }

    /// 해제 안내가 머무는 시간 — 실행 취소를 누를 수 있을 만큼 둔다.
    static let removedNoticeDuration: Duration = .seconds(4)
    /// 실패 안내가 머무는 시간.
    static let failureNoticeDuration: Duration = .seconds(5)
    /// 위젯 변경 결과 안내가 머무는 시간.
    static let widgetNoticeDuration: Duration = .seconds(2)

    @Dependency(\.favoriteVerseRepository) var repository
    @Dependency(\.widgetVerseClient) var widgetVerseClient
    @Dependency(\.continuousClock) var clock
    @Dependency(\.drawingEditEnvironment) var drawingEditEnvironment

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .view(.task):
                // 배지(「위젯에 담김」)를 먼저 정하고 목록을 읽는다 — 순서를 고정해 둔다.
                return .run { [repository, widgetVerseClient] send in
                    await send(.widgetSelectionLoaded(await widgetVerseClient.selection()))
                    do {
                        await send(.favoritesLoaded(.success(try await repository.favorites())))
                    } catch {
                        await send(.favoritesLoaded(.failure(error)))
                    }
                }

            case .view(.retryLoadTapped):
                return .run { [repository] send in
                    do {
                        await send(.favoritesLoaded(.success(try await repository.favorites())))
                    } catch {
                        await send(.favoritesLoaded(.failure(error)))
                    }
                }

            case .widgetSelectionLoaded(let keys):
                state.widgetKeys = Set(keys)
                return .none

            case .favoritesLoaded(.success(let favorites)):
                // 저장소가 키마다 하나로 합쳐 주지만, 같은 키가 섞여 와도 목록이 깨지지 않게 먼저 온 것(더 최근 것)을 남긴다.
                state.favorites = IdentifiedArray(favorites, uniquingIDsWith: { newer, _ in newer })
                state.hasLoaded = true
                state.loadFailed = false
                return .none

            case .favoritesLoaded(.failure(let error)):
                Log.error("즐겨찾기 목록 조회 실패", error)
                state.hasLoaded = true
                state.loadFailed = true
                return .none

            case .view(.unfavoriteTapped(let key)):
                guard !state.widgetKeys.contains(key) else {
                    // 위젯에 표시 중인 말씀이다 — 위젯에서도 빠진다는 것을 먼저 알린다(시안 N9).
                    state.removeConfirm = Self.removeDisplayedFavoriteAlert(key)
                    return .none
                }
                guard let favorite = state.favorites.remove(id: key) else { return .none }
                return remove(favorite, state: &state)

            case .removeConfirm(.presented(.confirm(let key))):
                guard let favorite = state.favorites.remove(id: key) else { return .none }
                // 해제하면 위젯에서도 뺀다. 다른 말씀을 자동으로 채우지는 않는다(2026-09-16 디자인 결정).
                state.widgetKeys.remove(key)
                return remove(favorite, fromWidget: true, state: &state)

            case .view(.widgetTapped(let key)):
                guard !state.isChangingWidget else { return .none }
                if state.widgetKeys.contains(key) {
                    return applyWidgetChange(.remove(key), state: &state)
                }
                guard let favorite = state.favorites[id: key] else { return .none }
                guard state.widgetKeys.count < WidgetVerseLimit.maximum else {
                    return showNotice(.widgetLimitReached, duration: Self.failureNoticeDuration, state: &state)
                }
                return applyWidgetChange(.add(favorite), state: &state)

            case let .widgetChangeFinished(change, failed):
                state.isChangingWidget = false
                guard failed else {
                    let notice: Notice = {
                        if case .remove = change { return .widgetRemoved }
                        return .widgetAdded
                    }()
                    return showNotice(notice, duration: Self.widgetNoticeDuration, state: &state)
                }
                // 먼저 바꿔 둔 배지를 위젯 쪽 값으로 되돌린다.
                return .merge(
                    showNotice(.widgetFailed(change), duration: Self.failureNoticeDuration, state: &state),
                    .run { [widgetVerseClient] send in
                        await send(.widgetSelectionLoaded(await widgetVerseClient.selection()))
                    }
                )

            case let .removeFinished(favorite, failed):
                guard failed else { return .send(.delegate(.favoritesChanged)) }
                insert(favorite, into: &state)
                return showNotice(.removeFailed(favorite.key), duration: Self.failureNoticeDuration, state: &state)

            case let .restoreFinished(favorite, failed):
                guard failed else { return .send(.delegate(.favoritesChanged)) }
                state.favorites.remove(id: favorite.key)
                return showNotice(.restoreFailed(favorite), duration: Self.failureNoticeDuration, state: &state)

            case let .writeBlocked(write, block):
                // 먼저 바꿔 둔 목록 · 배지를 되돌리고 막은 사유를 보인다.
                switch write {
                case let .remove(favorite, fromWidget):
                    insert(favorite, into: &state)
                    if fromWidget { state.widgetKeys.insert(favorite.key) }
                case .restore(let favorite):
                    state.favorites.remove(id: favorite.key)
                }
                return showNotice(.blocked(block), duration: Self.failureNoticeDuration, state: &state)

            case .view(.noticeActionTapped):
                let notice = state.notice
                state.notice = nil
                switch notice {
                case .removed(let favorite), .restoreFailed(let favorite):
                    insert(favorite, into: &state)
                    return .merge(.cancel(id: CancelID.notice), restore(favorite))
                case .removeFailed(let key):
                    guard let favorite = state.favorites.remove(id: key) else { return .cancel(id: CancelID.notice) }
                    return remove(favorite, state: &state)
                case .widgetFailed(let change):
                    return .merge(.cancel(id: CancelID.notice), applyWidgetChange(change, state: &state))
                case .widgetAdded, .widgetRemoved, .widgetLimitReached, .blocked, nil:
                    return .none
                }

            case .noticeExpired:
                state.notice = nil
                return .none

            case .view(.openVerseTapped(let key)):
                guard let favorite = state.favorites[id: key] else { return .none }
                let verse = BibleVerse(title: key.chapter, verse: key.verse, sentence: favorite.sentence)
                return .send(.delegate(.openVerse(verse)))

            case .view(.backToWritingTapped):
                return .send(.delegate(.backToWriting))

            case .removeConfirm:
                return .none

            case .delegate:
                return .none
            }
        }
        .ifLet(\.$removeConfirm, action: \.removeConfirm)
    }
}

extension FavoriteListFeature {
    /// 저장소에서 지우고 실행 취소 안내를 띄운다. 목록에서는 이미 뺀 뒤다. `fromWidget` 이면 위젯에서도 뺀다 — 실패해도 목록 동작은 막지 않는다.
    /// 즐겨찾기는 동기화 저장소다 — 쓰기 직전에 소유가 확인됐는지 다시 보고, 막히면 위젯도 건드리지 않는다(정책 §12-6 결정 1, ACC-1 F30).
    private func remove(_ favorite: FavoriteVerseSnapshot, fromWidget: Bool = false, state: inout State) -> Effect<Action> {
        let notice = showNotice(.removed(favorite), duration: Self.removedNoticeDuration, state: &state)
        return .merge(
            notice,
            .run { [repository, widgetVerseClient, drawingEditEnvironment] send in
                if let block = SyncedWriteBlock.check(await drawingEditEnvironment.current()) {
                    await send(.writeBlocked(.remove(favorite, fromWidget: fromWidget), block))
                    return
                }
                if fromWidget {
                    do {
                        try await widgetVerseClient.remove(favorite.key)
                    } catch {
                        Log.error("위젯에서 빼지 못했다", error)
                    }
                }
                do {
                    try await repository.remove(favorite.key)
                    await send(.removeFinished(favorite, failed: false))
                } catch {
                    Log.error("즐겨찾기 해제 실패", error)
                    await send(.removeFinished(favorite, failed: true))
                }
            }
        )
    }

    /// 해제한 항목을 추가 시각 그대로 다시 저장한다. 목록에는 이미 되돌려 둔 뒤다. 소유가 확인되지 않았으면 쓰지 않는다(정책 §12-6 결정 1).
    private func restore(_ favorite: FavoriteVerseSnapshot) -> Effect<Action> {
        .run { [repository, drawingEditEnvironment] send in
            if let block = SyncedWriteBlock.check(await drawingEditEnvironment.current()) {
                await send(.writeBlocked(.restore(favorite), block))
                return
            }
            do {
                try await repository.save(favorite)
                await send(.restoreFinished(favorite, failed: false))
            } catch {
                Log.error("즐겨찾기 되돌리기 실패", error)
                await send(.restoreFinished(favorite, failed: true))
            }
        }
    }

    /// 최근 추가순을 지키며 넣는다 — 해제 전 자리로 돌아간다. 이미 있으면 그대로 둔다.
    private func insert(_ favorite: FavoriteVerseSnapshot, into state: inout State) {
        guard state.favorites[id: favorite.key] == nil else { return }
        let index = state.favorites.firstIndex { $0.createdDate < favorite.createdDate } ?? state.favorites.endIndex
        state.favorites.insert(favorite, at: index)
    }

    /// 위젯에 담긴 말씀을 바꾼다. 배지는 저장을 기다리지 않고 먼저 바꾸고, 실패하면 위젯 쪽 값으로 되돌린다.
    private func applyWidgetChange(_ change: WidgetChange, state: inout State) -> Effect<Action> {
        state.isChangingWidget = true
        state.notice = nil
        switch change {
        case .add(let favorite): state.widgetKeys.insert(favorite.key)
        case .remove(let key): state.widgetKeys.remove(key)
        }
        return .merge(
            .cancel(id: CancelID.notice),
            .run { [widgetVerseClient] send in
                do {
                    switch change {
                    case .add(let favorite): try await widgetVerseClient.add(favorite)
                    case .remove(let key): try await widgetVerseClient.remove(key)
                    }
                    await send(.widgetChangeFinished(change, failed: false))
                } catch {
                    Log.error("위젯 변경 실패", error)
                    await send(.widgetChangeFinished(change, failed: true))
                }
            }
        )
    }

    /// 위젯에 담긴 말씀을 해제하기 전 확인(시안 N9).
    static func removeDisplayedFavoriteAlert(_ key: FavoriteVerseKey) -> AlertState<Action.RemoveConfirm> {
        AlertState {
            TextState("즐겨찾기를 해제할까요?")
        } actions: {
            ButtonState(role: .cancel) { TextState("취소") }
            ButtonState(role: .destructive, action: .confirm(key)) { TextState("해제하기") }
        } message: {
            TextState("""
            이 말씀은 위젯에 담겨 있어요. 해제하면 위젯에서도 빠져요.
            원래 필사와 이전 필사 기록은 남아요.
            """)
        }
    }

    private func showNotice(_ notice: Notice, duration: Duration, state: inout State) -> Effect<Action> {
        state.notice = notice
        return .run { [clock] send in
            try await clock.sleep(for: duration)
            await send(.noticeExpired)
        }
        .cancellable(id: CancelID.notice, cancelInFlight: true)
    }
}
