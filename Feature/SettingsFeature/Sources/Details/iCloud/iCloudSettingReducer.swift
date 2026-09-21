//
//  CloudSettingsFeature.swift
//  FeatureSettings
//
//  Created by 이택성 on 5/21/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import CarveToolkit
import Domain
import SwiftUI

import ComposableArchitecture

@Reducer
public struct CloudSettingsFeature {
    public init() { }
    
    @ObservableState
    public struct State: Hashable {
        public static let initialState = Self()
        @Presents public var path: Path.State?
        /// iCloud 계정을 쓸 수 있는지. **조회 전에는 `checking`** 이며, 확인하지 않은 상태를
        /// "연결됨" 으로 보여 주지 않는다. 이전 구현은 조작 불가능한 토글을 켜진 채로 두어
        /// 계정이 없는 기기에서도 동기화되는 것처럼 보였다.
        public var availability: CloudAccountAvailability = .checking
        /// 이번 실행에서의 동기화 활동. **앱을 방금 켰다면 비어 있으며, 그것이 동기화되지 않았다는 뜻은 아니다.**
        public var activity = CloudSyncActivity()
        public var isLoading: Bool = false
    }
    @Dependency(\.createSwiftDataActor) private var database
    @Dependency(\.cloudAccountStatus) private var accountStatus
    @Dependency(\.cloudSyncActivity) private var syncActivity

    /// 화면이 떠 있는 동안만 활동을 구독한다.
    private enum CancelID { case activity }
    @Dependency(\.widgetVerseClient) private var widgetVerseClient
    @Dependency(\.drawingDataEraser) private var drawingDataEraser
    /// 전체 삭제가 함께 지우는 **남은 필기**(보존 영역)를 세기 위해 읽는다.
    @Dependency(\.verseDraftRecoveryReader) private var draftReader

    public enum Action: ViewAction {
        case path(PresentationAction<Path.Action>)
        /// 계정 조회 결과가 도착했다.
        case accountChecked(CloudAccountAvailability)
        /// 동기화 활동이 바뀌었다.
        case activityChanged(CloudSyncActivity)
        case removeAlliCloudData
        /// 삭제가 끝났다 — 열려 있는 장에 알린다.
        case drawingDataCleared
        case presentPopover(
            title: String? = nil,
            body: String,
            emphasis: String? = nil,
            hint: String? = nil,
            confirmTitle: String,
            cancelTitle: String? = nil,
            role: PopupFeature.Role = .plain,
            action: PopupFeature.ConfirmAction
        )
        case popupDismiss
        case setLoading(Bool)
        case view(View)
        
        public enum View {
            case databaseIsEmpty
            /// 화면이 나타났다. 계정 상태를 **그때 조회한다** — 미리 켜 두지 않는다.
            case onAppear
            /// 화면이 사라졌다. 활동 구독을 멈춘다.
            case onDisappear
        }
    }
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .view(.onAppear):
                state.availability = .checking
                return .merge(
                    .run { send in
                        await send(.accountChecked(await accountStatus.availability()))
                    },
                    .run { send in
                        for await activity in syncActivity.activities() {
                            await send(.activityChanged(activity))
                        }
                    }
                    .cancellable(id: CancelID.activity, cancelInFlight: true)
                )
            case .view(.onDisappear):
                return .cancel(id: CancelID.activity)
            case .accountChecked(let availability):
                state.availability = availability
            case .activityChanged(let activity):
                state.activity = activity
            case .view(.databaseIsEmpty):
                return .run { [widgetVerseClient, draftReader] send in
                    // 「필사 데이터」 에는 즐겨찾기에 복사해 둔 필기와 위젯에 담은 말씀도 포함된다 — 셋을 함께 본다.
                    let hasDrawings = !(try await database.databaseIsEmpty(BibleDrawing.self))
                    let hasFavorites = !(try await database.databaseIsEmpty(FavoriteVerse.self))
                    let hasWidgetVerses = !(await widgetVerseClient.selection().isEmpty)
                    // 전체 삭제는 이 기기의 보존 영역(남은 필기)도 지운다 — 저장소가 비어도 초안만 남아 있을 수 있다(ACC-1 2차 ㉓).
                    let remainingDrafts = await Self.remainingDraftCount(draftReader)
                    // 세지 못했으면(nil) 있을 수 있다고 본다 — 없다고 단정해 지울 것이 없다고 말하지 않는다.
                    if hasDrawings || hasFavorites || hasWidgetVerses || (remainingDrafts ?? 1) > 0 {
                        // 문구와 구성은 시안 F2 를 따른다 — 지워지는 범위 · 되돌릴 수 없다는 경고 · 한 절만 비우는 대안.
                        await send(.presentPopover(
                            title: "모든 필사 데이터를 지울까요?",
                            body: Self.eraseConfirmBody(remainingDrafts: remainingDrafts),
                            emphasis: "지운 데이터는 되돌릴 수 없어요.",
                            hint: "한 절만 비우려면 해당 절을 길게 눌러\n지우기를 선택해 주세요.",
                            confirmTitle: "모두 지우기",
                            cancelTitle: "취소",
                            role: .destructive,
                            action: .deleteAllData
                        ))
                    } else {
                        await send(.presentPopover(
                            body: "지울 필사 데이터가 없어요.",
                            confirmTitle: "확인",
                            action: .dismiss
                        ))
                    }
                }
            case let .presentPopover(title, body, emphasis, hint, confirmTitle, cancelTitle, role, action):
                state.path = .popup(.init(
                    title: title,
                    body: body,
                    emphasis: emphasis,
                    hint: hint,
                    confirmTitle: confirmTitle,
                    cancelTitle: cancelTitle,
                    role: role,
                    confirmAction: action
                ))
            case .removeAlliCloudData:
                return .run { [widgetVerseClient, drawingDataEraser] send in
                    await send(.setLoading(true))
                    // 필사 행 · 구 구조 잔존 행 · 즐겨찾기(필기 복사본)를 지운다. 필사 행이 가장 먼저다.
                    let outcome = await drawingDataEraser.eraseAll()

                    var widgetCleared = false
                    if outcome.drawingsCleared {
                        // 위젯은 별도 저장소라 실패해도 DB 삭제를 되돌릴 수 없다. 남으면 홈 화면에 옛 말씀이 남는다.
                        do {
                            try await widgetVerseClient.clear()
                            widgetCleared = true
                        } catch {
                            // 로그만 남기고 완료로 보지 않는다 — 이전 구현은 여기서 "모든 필사 데이터를 지웠어요" 를 띄웠다.
                            Log.error("전체 삭제 — 위젯 내용을 비우지 못했다", "\(error)")
                        }
                        // 뒤따른 삭제가 실패했더라도 필사 행은 사라졌다. 열린 장이 옛 잉크를 버리지 않으면
                        // 다음 저장이 방금 지운 필사를 되살린다.
                        await send(.drawingDataCleared)
                    }
                    // 필사 행 삭제가 실패했다면 신호를 보내지 않는다. 지워졌는지 확인하지 못했을 때 미저장분을 버리면,
                    // 실제로 지워지지 않았을 경우 사용자가 쓴 필사를 잃는다(`DrawingEraseOutcome.failed`).

                    // 결과와 무관하게 잠금을 푼다. 이전 구현은 삭제가 실패하면 여기에 오지 못해 화면이 멈췄다.
                    await send(.setLoading(false))

                    guard outcome == .completed, widgetCleared else {
                        // 「다시 시도」 는 같은 삭제를 다시 부른다. DB 삭제와 위젯 비우기 모두 멱등이다.
                        await send(.presentPopover(
                            title: "필사 데이터를 모두 지우지 못했어요",
                            body: Self.eraseFailureBody(outcome: outcome, widgetCleared: widgetCleared),
                            confirmTitle: "다시 시도",
                            cancelTitle: "닫기",
                            role: .destructive,
                            action: .deleteAllData
                        ))
                        return
                    }
                    await send(.presentPopover(
                        body: "모든 필사 데이터를 지웠어요.",
                        confirmTitle: "확인",
                        action: .dismiss
                    ))
                }

            case .drawingDataCleared:
                // 열려 있는 장이 이 값을 보고 다시 조회한다 (`CarveDetailFeature`).
                // 상태에 두지 않는 이유는 `State` 가 `Hashable` 이기 때문이다 — `@Shared` 는 그 합성을 깬다.
                DrawingDataRevision.bump()
            case .path(.presented(.popup(.view(.confirm)))):
                guard state.path?.popup?.confirmAction == .deleteAllData else {
                    return .send(.popupDismiss)
                }
                // 지울 것이 있는지는 확인 팝업을 띄울 때 이미 봤다. 이전 구현은 여기서 **필사 행만** 다시 확인해서,
                // 즐겨찾기만 남은 경우와 부분 삭제 뒤 「다시 시도」 가 아무것도 지우지 않고 닫혔다.
                // 삭제는 멱등이므로 다시 확인하지 않는다.
                return .send(.removeAlliCloudData)
            case .path(.presented(.popup(.view(.cancel)))):
                state.path = nil
            case .popupDismiss:
                state.path = nil
            case .setLoading(let isLoading):
                state.isLoading = isLoading
            default: break
            }
            return .none
        }
        .ifLet(\.$path, action: \.path)
    }
}

extension CloudSettingsFeature {
    /// 전체 삭제가 함께 지우는 **이 기기의 초안 파일 수** — 모든 묶음(다른 계정 · 계정 미확인 · 로그인하지 않은 동안)의 초안과 읽지 못해 옆으로
    /// 옮긴 파일. 화면에 자동으로 표시되는 초안도 든다 — 전체 삭제는 보존 영역을 통째로 지운다(`LocalPreservationWriter.eraseAllLocal`).
    /// **읽지 못하면 nil** — 없다고 단정하지 않는다.
    static func remainingDraftCount(_ reader: (any VerseDraftRecoveryReading)?) async -> Int? {
        guard let reader else { return nil }
        do {
            var total = 0
            for scope in try await reader.draftBuckets() {
                let summary = try await reader.draftSummary(in: scope)
                total += summary.draftCount + summary.unreadableCount
            }
            return total
        } catch {
            Log.error("전체 삭제 — 남은 필기를 세지 못했다. 없다고 보지 않는다", "\(error)")
            return nil
        }
    }

    /// 지워지는 범위를 적는다. **이 기기의 초안도 모두 지워진다** — 세지 못했으면 수 없이 말한다(정책 §12-5 C11 문구 규칙).
    ///
    /// 수는 `remainingDraftCount` 그대로 — **실제로 지워지는 초안 파일 수**다. 예전 문구는 "화면에 보이지 않게 남은 필기 N개" 라 해, 자동으로
    /// 표시되는 초안 · 다른 계정의 초안 · 읽지 못한 파일까지 센 수와 말이 달랐다(2026-09-21 후속 리뷰 P1-4).
    static func eraseConfirmBody(remainingDrafts: Int?) -> String {
        var lines = [
            "모든 장의 필기와 이전 필사 기록이 지워져요.",
            "즐겨찾기와 위젯에 담은 말씀도 함께 사라져요."
        ]
        switch remainingDrafts {
        case .some(let remaining) where remaining > 0:
            lines.append("이 기기의 필사 초안 \(remaining)개도 모두 지워져요(다른 계정에서 쓴 것 · 읽지 못한 파일 포함).")
        case .none:
            lines.append("이 기기의 필사 초안도 모두 지워져요(다른 계정에서 쓴 것 · 읽지 못한 파일 포함).")
        default:
            break
        }
        return lines.joined(separator: "\n")
    }

    /// 전체 삭제가 끝나지 못했을 때 **확인된 범위만** 말한다. 남은 것을 뭉뚱그리지도, 확인하지 못한 것을 단정하지도 않는다.
    ///
    /// 필사 행 삭제가 실패하면(`.failed`) 일부가 지워졌는지 증명하지 못한다(`DrawingEraseOutcome.failed`). 미저장분을
    /// 지키기로 한 판단과 "아무것도 지우지 않았다" 는 보장은 별개라, 이전 문구("아직 아무것도 지우지 않았어요")를 쓰지 않는다.
    static func eraseFailureBody(outcome: DrawingEraseOutcome, widgetCleared: Bool) -> String {
        guard outcome.drawingsCleared else { return "삭제를 완료하지 못했어요. 다시 시도해 주세요." }
        switch (outcome, widgetCleared) {
        case (.partiallyFailed, false):
            return "필기는 지웠지만 즐겨찾기와 위젯에 담은 말씀이 남았을 수 있어요."
        case (.partiallyFailed, true):
            return "필기는 지웠지만 즐겨찾기가 남았을 수 있어요."
        default:
            return "필기와 즐겨찾기는 지웠지만 위젯에 담은 말씀이 남았을 수 있어요."
        }
    }

    @Reducer
    public enum Path {
        case popup(PopupFeature)
    }
}

extension CloudSettingsFeature.Path.State: Hashable {}
