//
//  CarveDetailFeature+Favorite.swift
//  CarveFeature
//
//  Created by Claude on 9/15/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import CarveToolkit
import Domain
import Foundation

import ComposableArchitecture

/// 필사 화면의 즐겨찾기(시안 N1 · N2) — 장의 즐겨찾기 표시 · 절 메뉴에서 추가/해제 · 결과 안내.
///
/// 즐겨찾기는 **추가한 당시의 본문 · 필기를 보존한다** (2026-09-15 결정). 필기는 캔버스가 지금 보이는 것
/// (저장 대기 중인 획 포함, `ChapterCanvasFeature.currentInk`)을 넘기고, 본문은 이 장의 절 행에서 읽는다.
/// 표시는 저장을 기다리지 않고 먼저 바꾸며, 실패하면 되돌리고 「다시 시도」 를 둔다.
extension CarveDetailFeature {
    /// 필사 화면 아래 즐겨찾기 결과 안내.
    enum FavoriteNotice: Equatable {
        /// 「즐겨찾기에 추가했어요」 — 잠깐 보였다가 사라진다.
        case added
        /// 저장하지 못했다. 「다시 시도」 는 같은 변경을 다시 보낸다.
        case failed(FavoriteChange)
        /// 동기화 저장소에 쓰지 않고 막았다 — 사유를 보인다. 다시 시도해도 같은 사유로 막히므로 버튼을 두지 않는다.
        case blocked(FavoriteChange, SyncedWriteBlock)
    }

    /// 즐겨찾기 한 번의 변경. 실패하면 이 값 그대로 다시 시도한다.
    public enum FavoriteChange: Equatable, Sendable {
        /// 추가 — 추가할 때의 본문 · 필기를 담는다.
        case add(FavoriteVerseSnapshot)
        /// 해제. 원래 필사나 이전 필사 기록은 지우지 않는다.
        case remove(FavoriteVerseKey)

        var key: FavoriteVerseKey {
            switch self {
            case .add(let favorite): favorite.key
            case .remove(let key): key
            }
        }

        var isAdding: Bool {
            if case .add = self { return true }
            return false
        }
    }

    /// 추가 안내가 머무는 시간.
    static let favoriteAddedNoticeDuration: Duration = .seconds(2)
    /// 실패 안내가 머무는 시간 — 「다시 시도」 를 누를 수 있도록 더 길게 둔다.
    static let favoriteFailureNoticeDuration: Duration = .seconds(5)

    func reduceFavorite(state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case let .favoritesLoaded(chapter, editCount, verses):
            // 장이 바뀌었거나 조회를 시작한 뒤 이 화면에서 바꾼 것이 있으면 버린다 — 방금 바꾼 표시가 옛 값으로 돌아가지 않게.
            guard chapter == state.favoriteChapter, editCount == state.favoriteEditCount else { return .none }
            state.favoriteVerses = verses
            return .none

        case .reloadFavorites:
            guard let chapter = state.favoriteChapter else { return .none }
            return loadFavorites(state: &state, chapter: chapter)

        case let .favoriteChangeFinished(change, failed):
            if failed {
                // 먼저 바꿔 둔 표시를 저장소와 같게 되돌린다.
                setFavoriteMark(state: &state, key: change.key, isFavorite: !change.isAdding)
                return showFavoriteNotice(state: &state, .failed(change), duration: Self.favoriteFailureNoticeDuration)
            }
            guard change.isAdding else {
                // 해제한 말씀이 위젯에 담겨 있었다면 위젯에서도 뺀다(시안 N9 와 같은 규칙).
                return .run { [widgetVerseClient] _ in
                    guard await widgetVerseClient.selection().contains(change.key) else { return }
                    do {
                        try await widgetVerseClient.remove(change.key)
                    } catch {
                        Log.error("위젯에서 빼지 못했다", error)
                    }
                }
            }
            return showFavoriteNotice(state: &state, .added, duration: Self.favoriteAddedNoticeDuration)

        case let .favoriteChangeBlocked(change, block):
            Log.info("즐겨찾기 — 동기화 저장소에 쓰지 않고 막았다", "\(block)")
            // 먼저 바꿔 둔 표시를 되돌리고 막은 사유를 보인다.
            setFavoriteMark(state: &state, key: change.key, isFavorite: !change.isAdding)
            return showFavoriteNotice(state: &state, .blocked(change, block), duration: Self.favoriteFailureNoticeDuration)

        case .favoriteNoticeExpired:
            state.favoriteNotice = nil
            return .none

        case .view(.favoriteRetryTapped):
            guard case .failed(let change) = state.favoriteNotice else { return .none }
            return applyFavoriteChange(state: &state, change)

        default:
            return .none
        }
    }

    /// 장의 즐겨찾기 표시를 읽는다. 다른 장이면 이전 장의 표시부터 비운다.
    func loadFavorites(state: inout State, chapter: BibleChapter) -> Effect<Action> {
        if state.favoriteChapter != chapter {
            // 이전 장의 별 표시를 새 장 본문에 남기지 않는다.
            state.favoriteVerses = []
            state.favoriteChapter = chapter
        }
        let editCount = state.favoriteEditCount
        return .run { [favoriteRepository] send in
            do {
                // 번역본은 아직 하나뿐이다. BIBLE-EN 이 들어오면 지금 보는 번역본을 넘긴다.
                let verses = try await favoriteRepository.favoriteVerses(in: chapter, translation: .NKRV)
                await send(.favoritesLoaded(chapter: chapter, editCount: editCount, verses: verses))
            } catch {
                // 읽지 못하면 별 표시 없이 둔다 — 필사에는 영향이 없다.
                Log.error("즐겨찾기 조회 실패", "\(chapter.title.rawValue).\(chapter.chapter)", error)
            }
        }
        .cancellable(id: CancelID.loadFavorites, cancelInFlight: true)
    }

    /// 절 메뉴의 즐겨찾기 — 이미 있으면 해제하고, 없으면 지금 본문 · 필기로 추가한다.
    /// - Parameters:
    ///   - state: Feature 상태.
    ///   - verse: 절 번호.
    ///   - ink: 캔버스가 지금 보이는 그 절의 필기. 획이 없으면 nil.
    func toggleFavorite(state: inout State, verse: Int, ink: Data?) -> Effect<Action> {
        guard let chapter = state.favoriteChapter else {
            // 이 장의 즐겨찾기를 아직 읽지 못했다 — 누른 것이 아무 일도 하지 않으므로 그 사실을 남긴다.
            Log.error("즐겨찾기 — 이 장을 아직 읽지 못해 누름을 무시했다", "verse=\(verse)")
            return .none
        }
        let key = FavoriteVerseKey(chapter: chapter, verse: verse)
        guard !state.favoriteVerses.contains(verse) else {
            return applyFavoriteChange(state: &state, .remove(key))
        }
        let sentence = state.sentenceWithDrawingState.first { $0.sentence.verse == verse }?.sentence.sentenceScript ?? ""
        let favorite = FavoriteVerseSnapshot(key: key, sentence: sentence, lineData: ink, createdDate: date.now)
        // 보이기만 하는 초안(다른 계정 · 확인 전)을 이어 보는 절이다 — 그 잉크를 즐겨찾기로 옮기지 않는다(11차 리뷰 P0-2).
        guard !state.usesSingleCanvas || !state.chapterCanvas.inheritsOtherSessionInk(verse: verse) else {
            return showFavoriteNotice(state: &state, .blocked(.add(favorite), .verseFromOtherSession),
                                      duration: Self.favoriteFailureNoticeDuration)
        }
        return applyFavoriteChange(state: &state, .add(favorite))
    }

    private func applyFavoriteChange(state: inout State, _ change: FavoriteChange) -> Effect<Action> {
        state.favoriteEditCount += 1
        // 저장을 기다리지 않고 표시부터 바꾼다 — 실패하면 `favoriteChangeFinished` 가 되돌린다.
        setFavoriteMark(state: &state, key: change.key, isFavorite: change.isAdding)
        state.favoriteNotice = nil
        return .merge(
            .cancel(id: CancelID.favoriteNotice),
            .run { [favoriteRepository, drawingEditEnvironment] send in
                // 즐겨찾기는 동기화 저장소에 바로 쓴다 — 쓰기 직전에 소유가 확인됐는지 다시 본다(정책 §12-6 결정 1, ACC-1 F30).
                if let block = SyncedWriteBlock.check(await drawingEditEnvironment.current()) {
                    await send(.favoriteChangeBlocked(change, block))
                    return
                }
                do {
                    switch change {
                    case .add(let favorite):
                        try await favoriteRepository.save(favorite)
                    case .remove(let key):
                        try await favoriteRepository.remove(key)
                    }
                    await send(.favoriteChangeFinished(change, failed: false))
                } catch {
                    Log.error("즐겨찾기 저장 실패", error)
                    await send(.favoriteChangeFinished(change, failed: true))
                }
            }
        )
    }

    /// 지금 장의 표시만 바꾼다. 다른 장으로 떠난 뒤 도착한 결과는 그 장을 다시 열 때 저장소에서 읽는다.
    private func setFavoriteMark(state: inout State, key: FavoriteVerseKey, isFavorite: Bool) {
        guard key.chapter == state.favoriteChapter else { return }
        if isFavorite {
            state.favoriteVerses.insert(key.verse)
        } else {
            state.favoriteVerses.remove(key.verse)
        }
    }

    private func showFavoriteNotice(state: inout State, _ notice: FavoriteNotice, duration: Duration) -> Effect<Action> {
        // 안내 자리는 하나다 — 다른 안내가 떠 있으면 내린다.
        state.imageSaveNotice = nil
        state.widgetNotice = nil
        state.favoriteNotice = notice
        return .merge(
            .cancel(id: CancelID.imageSaveNotice),
            .cancel(id: CancelID.widgetNotice),
            .run { [clock] send in
                try await clock.sleep(for: duration)
                await send(.favoriteNoticeExpired)
            }
            .cancellable(id: CancelID.favoriteNotice, cancelInFlight: true)
        )
    }
}
