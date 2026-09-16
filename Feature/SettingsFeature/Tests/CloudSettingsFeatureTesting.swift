//
//  CloudSettingsFeatureTesting.swift
//  SettingsFeatureTest
//
//  설정 → iCloud — 확인하지 않은 상태를 "연결됨" 으로 보여 주지 않는다 (정책 §4-1).
//

import Domain
import Foundation
import Testing

import ComposableArchitecture

@testable import SettingsFeature

/// 이전 화면은 계정을 **한 번도 조회하지 않으면서** 조작 불가능한 토글을 켜진 채로 보여 줬다.
/// iCloud 에 로그인하지 않은 기기에서도 "iCloud를 저장공간으로 사용" 이 켜져 보였다는 뜻이다.
/// 이 파일은 그 회귀를 막는다.
@Suite("설정 — iCloud 계정 상태")
struct CloudSettingsFeatureTesting {

    @Test("조회하기 전에는 확인 중이다 — 연결됐다고 먼저 말하지 않는다")
    func startsAsChecking() {
        let state = CloudSettingsFeature.State.initialState

        #expect(state.availability == .checking)
        #expect(!state.availability.canSync)
    }

    @Test("화면이 열리면 계정을 조회해 그 결과를 그대로 반영한다",
          arguments: [CloudAccountAvailability.available,
                      .noAccount,
                      .restricted,
                      .unknown])
    func onAppearReflectsAccountStatus(reported: CloudAccountAvailability) async {
        let store = await TestStore(initialState: CloudSettingsFeature.State.initialState) {
            CloudSettingsFeature()
        } withDependencies: {
            $0.cloudAccountStatus = StubCloudAccountStatusClient(reported)
        }

        await store.send(.view(.onAppear))
        await store.receive(\.accountChecked) { $0.availability = reported }
    }

    @Test("로그인하지 않은 기기는 동기화 가능으로 보지 않는다")
    func signedOutDeviceCannotSync() async {
        let store = await TestStore(initialState: CloudSettingsFeature.State.initialState) {
            CloudSettingsFeature()
        } withDependencies: {
            $0.cloudAccountStatus = StubCloudAccountStatusClient(.noAccount)
        }

        await store.send(.view(.onAppear))
        await store.receive(\.accountChecked) { $0.availability = .noAccount }

        #expect(!store.state.availability.canSync)
    }

    /// 조회 실패와 "계정 없음" 은 다르다. 전자를 후자로 표시하면 사용자가 로그인돼 있는데도
    /// 로그인하라는 안내를 보게 된다.
    @Test("확인하지 못한 것과 계정이 없는 것은 다른 상태다")
    func unknownIsNotSignedOut() {
        #expect(CloudAccountAvailability.unknown != .noAccount)
        #expect(!CloudAccountAvailability.unknown.canSync)
        #expect(CloudAccountAvailability.available.canSync)
    }
}
