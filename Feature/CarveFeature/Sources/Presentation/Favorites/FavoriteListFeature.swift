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
        /// 목록 아래 안내 — 해제 직후 실행 취소 · 저장 실패.
        var notice: Notice?

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
    }

    public enum Action: ViewAction {
        case view(View)
        /// 목록을 읽었다.
        case favoritesLoaded(Result<[FavoriteVerseSnapshot], any Error>)
        /// 해제 저장이 끝났다.
        case removeFinished(FavoriteVerseSnapshot, failed: Bool)
        /// 실행 취소(다시 저장)가 끝났다.
        case restoreFinished(FavoriteVerseSnapshot, failed: Bool)
        /// 안내를 내린다.
        case noticeExpired
        case delegate(Delegate)

        @CasePathable
        public enum View {
            /// 화면이 나타났다 — 목록을 읽는다.
            case task
            /// 조회 실패 상태의 「다시 시도」.
            case retryLoadTapped
            /// 카드의 채운 별 — 즐겨찾기 해제.
            case unfavoriteTapped(FavoriteVerseKey)
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

    @Dependency(\.favoriteVerseRepository) var repository
    @Dependency(\.continuousClock) var clock

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .view(.task), .view(.retryLoadTapped):
                return .run { [repository] send in
                    do {
                        await send(.favoritesLoaded(.success(try await repository.favorites())))
                    } catch {
                        await send(.favoritesLoaded(.failure(error)))
                    }
                }

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
                guard let favorite = state.favorites.remove(id: key) else { return .none }
                return remove(favorite, state: &state)

            case let .removeFinished(favorite, failed):
                guard failed else { return .send(.delegate(.favoritesChanged)) }
                insert(favorite, into: &state)
                return showNotice(.removeFailed(favorite.key), duration: Self.failureNoticeDuration, state: &state)

            case let .restoreFinished(favorite, failed):
                guard failed else { return .send(.delegate(.favoritesChanged)) }
                state.favorites.remove(id: favorite.key)
                return showNotice(.restoreFailed(favorite), duration: Self.failureNoticeDuration, state: &state)

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
                case nil:
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

            case .delegate:
                return .none
            }
        }
    }
}

extension FavoriteListFeature {
    /// 저장소에서 지우고 실행 취소 안내를 띄운다. 목록에서는 이미 뺀 뒤다.
    private func remove(_ favorite: FavoriteVerseSnapshot, state: inout State) -> Effect<Action> {
        let notice = showNotice(.removed(favorite), duration: Self.removedNoticeDuration, state: &state)
        return .merge(
            notice,
            .run { [repository] send in
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

    /// 해제한 항목을 추가 시각 그대로 다시 저장한다. 목록에는 이미 되돌려 둔 뒤다.
    private func restore(_ favorite: FavoriteVerseSnapshot) -> Effect<Action> {
        .run { [repository] send in
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

    private func showNotice(_ notice: Notice, duration: Duration, state: inout State) -> Effect<Action> {
        state.notice = notice
        return .run { [clock] send in
            try await clock.sleep(for: duration)
            await send(.noticeExpired)
        }
        .cancellable(id: CancelID.notice, cancelInFlight: true)
    }
}
