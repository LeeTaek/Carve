//
//  CarveDetailFeature+Widget.swift
//  CarveFeature
//
//  Created by Claude on 9/16/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import CarveToolkit
import Domain
import Foundation

import ComposableArchitecture

/// 필사 화면의 「위젯에 추가」(시안 N6) — 절 메뉴에서 고른 절을 홈 화면 위젯이 돌릴 말씀에 더한다.
///
/// 즐겨찾기가 보관함이다(2026-09-16 디자인 결정). 즐겨찾기에 없는 절은 **지금 모습 그대로** 보관한 뒤 담고,
/// 이미 보관된 절은 보관본을 그대로 쓴다 — 그래서 이후 필사를 고치거나 지워도 위젯은 바뀌지 않는다.
/// 위젯은 담은 말씀을 1시간마다 한 바퀴씩 돌며 보여 준다(`WidgetVerseRotation`).
extension CarveDetailFeature {
    /// 위젯에 담은 결과.
    public enum WidgetAddOutcome: Equatable, Sendable {
        /// 담았다. `addedToFavorites` 면 즐겨찾기에도 새로 담았다.
        case added(addedToFavorites: Bool)
        /// 이미 담겨 있었다 — 아무것도 바꾸지 않았다.
        case alreadyAdded
        /// 위젯이 꽉 찼다. 즐겨찾기에도 담지 않았다.
        case limitReached
        /// 담지 못했다.
        case failed
    }

    /// 필사 화면 아래 위젯 안내.
    enum WidgetNotice: Equatable {
        /// 위젯에 담았다. `addedToFavorites` 면 즐겨찾기에도 새로 담았다.
        case added(addedToFavorites: Bool)
        /// 이미 담겨 있다.
        case alreadyAdded
        /// 위젯이 꽉 찼다.
        case limitReached
        /// 담지 못했다. 「다시 시도」 는 같은 절을 다시 보낸다.
        case failed(WidgetDisplayRequest)
    }

    /// 위젯에 담기 요청 한 번. 실패하면 이 값 그대로 다시 시도한다.
    public struct WidgetDisplayRequest: Equatable, Sendable {
        /// 절 번호.
        let verse: Int
        /// 요청할 때 캔버스에 보이던 필기. 즐겨찾기에 없던 절이면 이대로 보관한다.
        let ink: Data?
    }

    /// 표시 안내가 머무는 시간.
    static let widgetNoticeDuration: Duration = .seconds(2)
    /// 실패 안내가 머무는 시간 — 「다시 시도」 를 누를 수 있도록 더 길게 둔다.
    static let widgetFailureNoticeDuration: Duration = .seconds(5)

    func reduceWidget(state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case let .widgetAddFinished(request, outcome):
            state.isAddingToWidget = false
            switch outcome {
            case .added(let addedToFavorites):
                if addedToFavorites {
                    // 보관하면서 즐겨찾기가 됐다 — 절 번호 아래 별도 함께 켠다(시안 N2).
                    state.favoriteEditCount += 1
                    state.favoriteVerses.insert(request.verse)
                }
                return showWidgetNotice(
                    state: &state,
                    .added(addedToFavorites: addedToFavorites),
                    duration: Self.widgetNoticeDuration
                )

            case .alreadyAdded:
                return showWidgetNotice(state: &state, .alreadyAdded, duration: Self.widgetNoticeDuration)

            case .limitReached:
                return showWidgetNotice(state: &state, .limitReached, duration: Self.widgetFailureNoticeDuration)

            case .failed:
                return showWidgetNotice(state: &state, .failed(request), duration: Self.widgetFailureNoticeDuration)
            }

        case .widgetNoticeExpired:
            state.widgetNotice = nil
            return .none

        case .view(.widgetRetryTapped):
            guard case .failed(let request) = state.widgetNotice else { return .none }
            return startWidgetAdd(state: &state, request)

        default:
            return .none
        }
    }

    /// 절 메뉴의 「위젯에 추가」.
    /// - Parameters:
    ///   - state: Feature 상태.
    ///   - verse: 절 번호.
    ///   - ink: 캔버스가 지금 보이는 그 절의 필기. 즐겨찾기에 없던 절이면 이대로 보관한다.
    func addVerseToWidget(state: inout State, verse: Int, ink: Data?) -> Effect<Action> {
        startWidgetAdd(state: &state, WidgetDisplayRequest(verse: verse, ink: ink))
    }

    private func startWidgetAdd(state: inout State, _ request: WidgetDisplayRequest) -> Effect<Action> {
        // 담는 동안 다시 누르면 무시한다 — 같은 절을 두 번 보관하지 않게.
        guard !state.isAddingToWidget, let chapter = state.favoriteChapter else { return .none }
        let key = FavoriteVerseKey(chapter: chapter, verse: request.verse)
        let sentence = state.sentenceWithDrawingState.first { $0.sentence.verse == request.verse }?.sentence.sentenceScript ?? ""
        let createdDate = date.now
        state.isAddingToWidget = true
        state.widgetNotice = nil
        state.favoriteNotice = nil
        state.imageSaveNotice = nil
        return .merge(
            .cancel(id: CancelID.widgetNotice),
            .cancel(id: CancelID.favoriteNotice),
            .cancel(id: CancelID.imageSaveNotice),
            .run { [favoriteRepository, widgetVerseClient] send in
                do {
                    let selection = await widgetVerseClient.selection()
                    guard !selection.contains(key) else {
                        await send(.widgetAddFinished(request, .alreadyAdded))
                        return
                    }
                    // 꽉 찬 것을 먼저 본다 — 담지도 못할 절을 즐겨찾기에만 남기지 않는다.
                    guard selection.count < WidgetVerseLimit.maximum else {
                        await send(.widgetAddFinished(request, .limitReached))
                        return
                    }
                    // 이미 보관돼 있으면 보관본을 그대로 쓴다 — 위젯은 「보관 당시 모습」 을 보여 준다.
                    let stored = try await favoriteRepository.favorites().first { $0.key == key }
                    let favorite = stored ?? FavoriteVerseSnapshot(
                        key: key, sentence: sentence, lineData: request.ink, createdDate: createdDate
                    )
                    if stored == nil {
                        try await favoriteRepository.save(favorite)
                    }
                    try await widgetVerseClient.add(favorite)
                    await send(.widgetAddFinished(request, .added(addedToFavorites: stored == nil)))
                } catch is WidgetVerseLimitExceeded {
                    await send(.widgetAddFinished(request, .limitReached))
                } catch {
                    Log.error("위젯에 담지 못했다", error)
                    await send(.widgetAddFinished(request, .failed))
                }
            }
        )
    }

    private func showWidgetNotice(state: inout State, _ notice: WidgetNotice, duration: Duration) -> Effect<Action> {
        // 안내 자리는 하나다 — 다른 안내가 떠 있으면 내린다.
        state.favoriteNotice = nil
        state.imageSaveNotice = nil
        state.widgetNotice = notice
        return .merge(
            .cancel(id: CancelID.favoriteNotice),
            .cancel(id: CancelID.imageSaveNotice),
            .run { [clock] send in
                try await clock.sleep(for: duration)
                await send(.widgetNoticeExpired)
            }
            .cancellable(id: CancelID.widgetNotice, cancelInFlight: true)
        )
    }
}
