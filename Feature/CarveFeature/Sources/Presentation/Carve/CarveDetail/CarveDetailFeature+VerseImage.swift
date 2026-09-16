//
//  CarveDetailFeature+VerseImage.swift
//  CarveFeature
//
//  Created by Claude on 9/15/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import CarveToolkit
import ClientInterfaces
import Domain
import UIKit

import ComposableArchitecture

/// 필사 화면의 절 이미지 저장(시안 G1 · G2) — 절 메뉴 → 이미지 그리기 → 사진 보관함에 추가 → 결과 안내.
///
/// 이미지는 요청한 순간의 본문 · 필기로 만든다 — 캔버스가 넘긴 필기 칸은 저장 대기 중인 획까지 담는다.
/// 결과는 셋이다(시안 G2). 성공은 잠깐 뜨는 안내, 실패는 「다시 시도」 가 있는 안내, 사진 추가 권한이 꺼져 있으면
/// 어디서 켜는지 말하는 확인창이다 — 권한은 지나가는 알림으로 두지 않는다.
extension CarveDetailFeature {
    /// 필사 화면 아래 이미지 저장 결과 안내.
    enum ImageSaveNotice: Equatable {
        /// 「사진에 저장했어요」 — 잠깐 보였다가 사라진다.
        case saved
        /// 저장하지 못했다. 「다시 시도」 는 같은 내용으로 이미지를 다시 만든다.
        case failed(VerseImageContent)
    }

    /// 이미지를 사진 보관함에 넣은 결과.
    public enum VerseImageSaveResult: Equatable, Sendable {
        /// 사진 보관함에 추가했다.
        case saved
        /// 사진 추가 권한이 꺼져 있다.
        case permissionDenied
        /// 이미지를 그리지 못했거나 사진 보관함에 넣지 못했다.
        case failed
    }

    /// 성공 안내가 머무는 시간.
    static let imageSavedNoticeDuration: Duration = .seconds(2)
    /// 실패 안내가 머무는 시간 — 「다시 시도」 를 누를 수 있도록 더 길게 둔다.
    static let imageSaveFailureNoticeDuration: Duration = .seconds(5)

    func reduceVerseImage(state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case let .verseImageSaveFinished(content, result):
            state.isSavingVerseImage = false
            switch result {
            case .saved:
                return showImageSaveNotice(state: &state, .saved, duration: Self.imageSavedNoticeDuration)
            case .permissionDenied:
                state.photoPermissionAlert = Self.photoPermissionDeniedAlert
                return .none
            case .failed:
                return showImageSaveNotice(state: &state, .failed(content), duration: Self.imageSaveFailureNoticeDuration)
            }

        case .imageSaveNoticeExpired:
            state.imageSaveNotice = nil
            return .none

        case .view(.imageSaveRetryTapped):
            guard case .failed(let content) = state.imageSaveNotice else { return .none }
            return startVerseImageSave(state: &state, content)

        case .photoPermissionAlert(.presented(.openSettings)):
            return .run { [openURL] _ in
                guard let url = await MainActor.run(body: { URL(string: UIApplication.openSettingsURLString) }) else { return }
                _ = await openURL(url)
            }

        default:
            return .none
        }
    }

    /// 절 메뉴의 「이미지 저장」 — 캔버스가 넘긴 필기 칸에 그 절의 본문 · 지금 본문 모양 · 출처를 더해 저장을 시작한다.
    /// - Parameters:
    ///   - state: Feature 상태.
    ///   - handwriting: 캔버스에 보이는 그 절의 필기 칸.
    func saveVerseImage(state: inout State, handwriting: VerseImageHandwriting) -> Effect<Action> {
        guard let verse = state.sentenceWithDrawingState.first(where: { $0.sentence.verse == handwriting.verse })?.sentence else {
            return .none
        }
        let content = VerseImageContent(
            sentence: verse.sentenceScript,
            setting: state.sentenceSetting,
            reference: VerseImageContent.reference(chapter: verse.title, verse: verse.verse),
            handwriting: handwriting
        )
        return startVerseImageSave(state: &state, content)
    }

    private func startVerseImageSave(state: inout State, _ content: VerseImageContent) -> Effect<Action> {
        // 저장하는 동안 다시 누르면 무시한다 — 같은 이미지가 두 장 들어가지 않게.
        guard !state.isSavingVerseImage else { return .none }
        state.isSavingVerseImage = true
        state.imageSaveNotice = nil
        return .merge(
            .cancel(id: CancelID.imageSaveNotice),
            .run { [verseImageRenderer, photoLibraryClient] send in
                guard let imageData = await verseImageRenderer.render(content) else {
                    Log.error("절 이미지를 그리지 못했다", content.reference)
                    await send(.verseImageSaveFinished(content, .failed))
                    return
                }
                do {
                    switch try await photoLibraryClient.addImage(imageData) {
                    case .added:
                        await send(.verseImageSaveFinished(content, .saved))
                    case .permissionDenied:
                        await send(.verseImageSaveFinished(content, .permissionDenied))
                    }
                } catch {
                    Log.error("절 이미지를 사진에 넣지 못했다", error)
                    await send(.verseImageSaveFinished(content, .failed))
                }
            }
        )
    }

    private func showImageSaveNotice(state: inout State, _ notice: ImageSaveNotice, duration: Duration) -> Effect<Action> {
        // 안내 자리는 하나다 — 다른 안내가 떠 있으면 내린다.
        state.favoriteNotice = nil
        state.widgetNotice = nil
        state.imageSaveNotice = notice
        return .merge(
            .cancel(id: CancelID.favoriteNotice),
            .cancel(id: CancelID.widgetNotice),
            .run { [clock] send in
                try await clock.sleep(for: duration)
                await send(.imageSaveNoticeExpired)
            }
            .cancellable(id: CancelID.imageSaveNotice, cancelInFlight: true)
        )
    }

    /// 사진 추가 권한이 꺼져 있다는 확인창(시안 G2) — 저장을 조용히 실패시키지 않고 어디서 켜는지 말한다.
    static var photoPermissionDeniedAlert: AlertState<Action.PhotoPermissionAlert> {
        AlertState {
            TextState("사진 접근이 꺼져 있어요")
        } actions: {
            ButtonState(role: .cancel) { TextState("나중에") }
            ButtonState(action: .openSettings) { TextState("설정 열기") }
        } message: {
            TextState("설정에서 사진 추가 권한을 켜면 저장할 수 있어요.")
        }
    }
}
