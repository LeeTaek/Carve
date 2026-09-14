//
//  AdSlotFeatureTesting.swift
//  UIComponentsTests
//
//  Created by Claude on 9/14/26.
//

import Testing
import UIKit

import ClientInterfaces
import ComposableArchitecture
@testable import UIComponents

/// 광고 한 자리의 로드 · 실패 · 만료 · 광고 제거 규칙(시안 K4, AdMob 네이티브 1시간 만료).
@MainActor
struct AdSlotFeatureTesting {
    @Test("받는 동안 자리를 비워 두고, 광고가 오면 그 뷰를 든다")
    func loadKeepsSpaceThenStoresView() async {
        let adView = UIView()
        let client = StubNativeAdClient(outcomes: [.success(adView)])
        let clock = TestClock()
        let store = makeStore(placement: .sidebarCard, client: client, clock: clock)

        await store.send(.startLoad) {
            $0.isLoading = true
        }
        #expect(store.state.occupiesSpace)
        #expect(!store.state.hasAd)

        await store.receive(\.adLoaded) {
            $0.isLoading = false
            $0.token = NativeAdToken(tokenId: "ad-0")
            $0.adView = adView
        }
        #expect(store.state.hasAd)

        // 만료 타이머까지 끝내 남은 효과가 없게 한다.
        await clock.advance(by: SponsorAdSlotFeature.adLifetime)
        await store.receive(\.adExpired) {
            $0.token = nil
            $0.adView = nil
        }
    }

    @Test("광고를 받지 못하면 자리를 없앤다")
    func loadFailureRemovesSpace() async {
        let client = StubNativeAdClient(outcomes: [.failure])
        let store = makeStore(placement: .headerStrip, client: client, clock: TestClock())

        await store.send(.startLoad) {
            $0.isLoading = true
        }
        await store.receive(\.adFailed) {
            $0.isLoading = false
            $0.errorMessage = String(describing: NativeAdClientError.adLoaderFailed(code: 1, message: "no fill"))
        }
        #expect(!store.state.occupiesSpace)
    }

    @Test("토큰은 왔는데 그릴 뷰가 없으면 자리를 없애고 만료 타이머를 걸지 않는다")
    func loadWithoutViewRemovesSpace() async {
        let client = StubNativeAdClient(outcomes: [.tokenWithoutView])
        let store = makeStore(placement: .headerStrip, refreshesOnExpiry: true, client: client, clock: TestClock())

        await store.send(.startLoad) {
            $0.isLoading = true
        }
        await store.receive(\.adLoaded) {
            $0.isLoading = false
            $0.errorMessage = "광고 뷰를 찾지 못함"
        }
        #expect(!store.state.occupiesSpace)
        #expect(client.invalidatedTokenIDs == ["ad-0"])
    }

    @Test("계속 보이는 자리는 만료되면 새로 받고, 새 광고가 올 때까지 이전 광고를 둔다")
    func expiryReplacesAdWhileVisible() async {
        let first = UIView()
        let second = UIView()
        let client = StubNativeAdClient(outcomes: [.success(first), .success(second)])
        let clock = TestClock()
        let store = makeStore(placement: .headerStrip, refreshesOnExpiry: true, client: client, clock: clock)

        await store.send(.startLoad) {
            $0.isLoading = true
        }
        await store.receive(\.adLoaded) {
            $0.isLoading = false
            $0.token = NativeAdToken(tokenId: "ad-0")
            $0.adView = first
        }

        await clock.advance(by: SponsorAdSlotFeature.adLifetime)
        await store.receive(\.adExpired) {
            $0.isLoading = true
        }
        #expect(store.state.adView === first)

        await store.receive(\.adLoaded) {
            $0.isLoading = false
            $0.token = NativeAdToken(tokenId: "ad-1")
            $0.adView = second
        }
        #expect(client.invalidatedTokenIDs == ["ad-0"])

        // 새 광고의 만료 타이머는 또 새로 받기로 이어지므로 여기서 검증을 멈춘다.
        store.exhaustivity = .off(showSkippedAssertions: false)
    }

    @Test("가끔 보이는 자리는 만료되면 비우고, 다음에 열 때 새로 받는다")
    func expiryClearsAdUntilNextLoad() async {
        let first = UIView()
        let second = UIView()
        let client = StubNativeAdClient(outcomes: [.success(first), .success(second)])
        let clock = TestClock()
        let store = makeStore(placement: .sidebarCard, client: client, clock: clock)

        await store.send(.startLoad) {
            $0.isLoading = true
        }
        await store.receive(\.adLoaded) {
            $0.isLoading = false
            $0.token = NativeAdToken(tokenId: "ad-0")
            $0.adView = first
        }

        await clock.advance(by: SponsorAdSlotFeature.adLifetime)
        await store.receive(\.adExpired) {
            $0.token = nil
            $0.adView = nil
        }
        #expect(client.invalidatedTokenIDs == ["ad-0"])

        await store.send(.startLoad) {
            $0.isLoading = true
        }
        await store.receive(\.adLoaded) {
            $0.isLoading = false
            $0.token = NativeAdToken(tokenId: "ad-1")
            $0.adView = second
        }

        await clock.advance(by: SponsorAdSlotFeature.adLifetime)
        await store.receive(\.adExpired) {
            $0.token = nil
            $0.adView = nil
        }
    }

    // MARK: - 광고 제거

    @Test("광고 제거를 샀으면 광고를 요청하지 않고 자리도 두지 않는다")
    func adFreeSkipsLoad() async throws {
        let suite = "AdSlotFeatureTesting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        adFreeShared(in: defaults).withLock { $0 = true }

        let client = StubNativeAdClient(outcomes: [])
        let store = makeStore(placement: .headerStrip, refreshesOnExpiry: true, client: client, clock: TestClock(), appStorage: defaults)

        #expect(!store.state.occupiesSpace)
        await store.send(.startLoad)
        #expect(client.loadCount == 0)
        #expect(!store.state.occupiesSpace)
    }

    @Test("광고가 떠 있는 동안 광고 제거를 사면 자리가 바로 사라지고, 만료돼도 새로 받지 않고 정리한다")
    func purchaseWhileVisibleRemovesAdWithoutRefresh() async throws {
        let suite = "AdSlotFeatureTesting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let isAdFree = adFreeShared(in: defaults)

        let adView = UIView()
        let client = StubNativeAdClient(outcomes: [.success(adView)])
        let clock = TestClock()
        let store = makeStore(placement: .headerStrip, refreshesOnExpiry: true, client: client, clock: clock, appStorage: defaults)

        await store.send(.startLoad) {
            $0.isLoading = true
        }
        await store.receive(\.adLoaded) {
            $0.isLoading = false
            $0.token = NativeAdToken(tokenId: "ad-0")
            $0.adView = adView
        }
        #expect(store.state.occupiesSpace)

        // 설정에서 구매가 끝나 앱의 구매 클라이언트가 권한을 썼다 — 액션 없이도 화면에서 자리가 사라진다.
        isAdFree.withLock { $0 = true }
        #expect(!store.state.occupiesSpace)
        #expect(!store.state.hasAd)

        // 헤더처럼 계속 보이는 자리여도 만료 때 새로 받지 않고 남은 광고를 정리한다.
        await clock.advance(by: SponsorAdSlotFeature.adLifetime)
        await store.receive(\.adExpired) {
            $0.token = nil
            $0.adView = nil
        }
        #expect(client.invalidatedTokenIDs == ["ad-0"])
        #expect(client.loadCount == 1)
    }

    @Test("받는 사이에 광고 제거를 샀으면 도착한 광고를 버린다")
    func adArrivingAfterPurchaseIsDiscarded() async throws {
        let suite = "AdSlotFeatureTesting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        adFreeShared(in: defaults).withLock { $0 = true }

        let client = StubNativeAdClient(outcomes: [])
        let store = makeStore(placement: .sidebarCard, isLoading: true, client: client, clock: TestClock(), appStorage: defaults)

        await store.send(.adLoaded(NativeAdToken(tokenId: "late"))) {
            $0.isLoading = false
        }
        #expect(client.invalidatedTokenIDs == ["late"])
        #expect(!store.state.occupiesSpace)
    }

    /// 광고 제거 여부는 테스트마다 따로 둔다 — 기본 저장소를 함께 쓰면 다른 테스트의 광고 자리까지 사라진다.
    private func adFreeShared(in defaults: UserDefaults) -> Shared<Bool> {
        withDependencies {
            $0.defaultAppStorage = defaults
        } operation: {
            Shared<Bool>(.isAdFree)
        }
    }

    private func makeStore(
        placement: NativeAdPlacement,
        refreshesOnExpiry: Bool = false,
        isLoading: Bool = false,
        client: StubNativeAdClient,
        clock: TestClock<Duration>,
        appStorage: UserDefaults? = nil
    ) -> TestStoreOf<SponsorAdSlotFeature> {
        withDependencies {
            if let appStorage {
                $0.defaultAppStorage = appStorage
            }
        } operation: {
            TestStore(
                initialState: SponsorAdSlotFeature.State(
                    placement: placement,
                    refreshesOnExpiry: refreshesOnExpiry,
                    isLoading: isLoading
                )
            ) {
                SponsorAdSlotFeature()
            } withDependencies: {
                $0.nativeAdClient = client
                $0.continuousClock = clock
            }
        }
    }
}

/// 정해 둔 순서대로 광고를 돌려주는 대역. 토큰은 요청 순번으로 `ad-<순번>` 이다.
@MainActor
private final class StubNativeAdClient: NativeAdClient {
    enum Outcome {
        case success(UIView)
        /// 로드는 성공했지만 뷰 캐시에 없음(테스트용 기본 클라이언트와 같은 모양)
        case tokenWithoutView
        case failure
    }

    private var outcomes: [Outcome]
    private var views: [String: UIView] = [:]
    private(set) var loadCount = 0
    private(set) var invalidatedTokenIDs: [String] = []

    init(outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func load(placement: NativeAdPlacement, adUnitId: String) async throws(NativeAdClientError) -> NativeAdToken {
        let outcome = outcomes.removeFirst()
        let tokenId = "ad-\(loadCount)"
        loadCount += 1
        switch outcome {
        case .success(let view):
            views[tokenId] = view
            return NativeAdToken(tokenId: tokenId)
        case .tokenWithoutView:
            return NativeAdToken(tokenId: tokenId)
        case .failure:
            throw .adLoaderFailed(code: 1, message: "no fill")
        }
    }

    func view(for token: NativeAdToken) -> UIView? {
        views[token.tokenId]
    }

    func invalidate(token: NativeAdToken) {
        invalidatedTokenIDs.append(token.tokenId)
    }
}
