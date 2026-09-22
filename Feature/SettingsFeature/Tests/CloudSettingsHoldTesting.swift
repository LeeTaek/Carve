//
//  CloudSettingsHoldTesting.swift
//  SettingsFeatureTest
//
//  설정 → 「모든 필사 데이터 삭제」 는 C14 연결 보류 중에 **시작하지 않는다**(정책 §12-6 C14 ③ · D6, 테스트 계획 §3-3 SEP-4).
//  실행 진입점(확인 팝업을 띄우는 곳)과 재시도 진입점(삭제를 부르는 곳)을 모두 막고, 예약했다가 연결 뒤 자동 실행하지 않는다.
//

import Domain
import Foundation
import Testing

import ComposableArchitecture

@testable import SettingsFeature

/// 불리면 안 되는 삭제.
private final class ForbiddenEraser: DrawingDataEraser, @unchecked Sendable {
    let calls = LockIsolated(0)

    func eraseAll() async -> DrawingEraseOutcome {
        calls.withValue { $0 += 1 }
        return .completed
    }
}

private struct SilentWidgetClient: WidgetVerseClient {
    func selection() async -> [FavoriteVerseKey] { [] }
    func select(_ favorites: [FavoriteVerseSnapshot]) async throws {}
    func add(_ favorite: FavoriteVerseSnapshot) async throws {}
    func remove(_ key: FavoriteVerseKey) async throws {}
    func clear() async throws {}
}

@Suite("설정 — 연결 보류 중 전체 삭제 차단 (D6)")
@MainActor
struct CloudSettingsHoldTesting {
    private let hold = LegacySeparationHold(reason: .unlinkedRowsAwaitSeparation(count: 2), jobID: "job")

    private func makeStore(_ eraser: ForbiddenEraser) -> TestStoreOf<CloudSettingsFeature> {
        TestStore(initialState: .initialState) {
            CloudSettingsFeature()
        } withDependencies: {
            $0.legacySeparationHoldState = LegacySeparationHoldState(hold: hold)
            $0.drawingDataEraser = eraser
            $0.widgetVerseClient = SilentWidgetClient()
        }
    }

    private var heldPopup: CloudSettingsFeature.Path.State {
        .popup(.init(
            title: nil, body: CloudSettingsFeature.eraseHeldBody, emphasis: nil, hint: nil,
            confirmTitle: "확인", cancelTitle: nil, role: .plain, confirmAction: .dismiss
        ))
    }

    @Test("실행 진입점 — 확인 팝업 대신 보류 안내를 띄우고 삭제를 부르지 않는다")
    func entryPointIsBlocked() async {
        let eraser = ForbiddenEraser()
        let store = makeStore(eraser)

        await store.send(.view(.databaseIsEmpty))
        await store.receive(\.presentPopover) { $0.path = heldPopup }

        #expect(eraser.calls.value == 0)
        #expect(CloudSettingsFeature.eraseHeldBody.contains("iCloud 연결이 보류되어 전체 삭제를 할 수 없어요"))
    }

    @Test("재시도 진입점 — 삭제 액션이 곧바로 들어와도 부르지 않는다")
    func retryPointIsBlocked() async {
        let eraser = ForbiddenEraser()
        let store = makeStore(eraser)

        await store.send(.removeAlliCloudData)
        await store.receive(\.presentPopover) { $0.path = heldPopup }

        #expect(eraser.calls.value == 0)
    }

    @Test("설정 목록은 화면이 뜰 때 보류를 읽는다 — iCloud 항목이 「보류」 로 보인다")
    func settingsListReadsHold() {
        // `SettingsFeature.State` 는 Equatable 이 아니라 TestStore 를 쓸 수 없다 — 리듀서를 직접 돌린다.
        for (hold, expected) in [(Optional(hold), true), (nil, false)] {
            var state = SettingsFeature.State.initialState
            withDependencies {
                $0.legacySeparationHoldState = LegacySeparationHoldState(hold: hold)
            } operation: {
                _ = SettingsFeature().reduce(into: &state, action: .view(.onAppear))
            }
            #expect(state.isConnectionHeld == expected)
        }
    }

    @Test("보류 안내는 지금은 이 기기에만 저장된다는 것 · 까닭 · 다시 시도를 말한다")
    func holdCopyExplains() {
        let unlinked = CloudSettingsFeature.holdCopy(hold)
        #expect(unlinked.title.contains("이 기기에만 저장돼요"))
        #expect(unlinked.detail.contains("옛 필사 2개") && unlinked.detail.contains("다시 실행하면 다시 확인해요"))

        let unknown = CloudSettingsFeature.holdCopy(LegacySeparationHold(reason: .linkageUnknown(.tableMissing("x"))))
        #expect(unknown.detail.contains("확인하지 못했어요"))
    }
}
