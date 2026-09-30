//
//  RemoveAdsStoreKitUITests.swift
//  CarveAppUITests
//
//  광고 제거 구매 · 복원 시험 (2026-09-30). 로컬 StoreKit(`SKTestSession`)으로 시뮬레이터에서 돈다.
//
//  - 실행은 `CarveApp-StoreKit` 스킴의 테스트다 — 스킴이 `CARVE_STOREKIT_UITEST=1` 을 넣는다.
//    표준 `Carve-Workspace` 실행에서는 건너뛴다(Debug 시험 광고를 받아 수 분 걸린다).
//    `xcodebuild test -workspace Carve.xcworkspace -scheme CarveApp-StoreKit -destination '<iPad 시뮬레이터>'`
//    `-only-testing:CarveAppUITests/RemoveAdsStoreKitUITests`
//  - 설정은 이 번들에 넣은 `Support/Carve.storekit` 이다 — 상품 ID · 가격을 앱 실행 설정과 한 곳에서 관리한다.
//  - 로컬 StoreKit 은 앱을 지우면 거래도 지운다. 재설치는 흉내 낼 수 없어 「앱을 끈 사이 산 구매를 다시 열어 알아보는지」로 대신한다.
//  - 이미 산 상태에서는 「구매 복원」 버튼이 숨는다. 「복원 성공 → 구매함」 전환은 `RemoveAdsFeatureTesting` 단위 시험이 맡는다.
//

import StoreKit
import StoreKitTest
import XCTest

@MainActor
final class RemoveAdsStoreKitUITests: XCTestCase {
    private static let productID = "kr.co.carve.leetaek.adfree"
    private var session: SKTestSession?

    override func setUp() async throws {
        continueAfterFailure = false
        #if !targetEnvironment(simulator)
        throw XCTSkip("로컬 StoreKit 시험은 시뮬레이터 전용")
        #else
        guard ProcessInfo.processInfo.environment["CARVE_STOREKIT_UITEST"] == "1" else {
            throw XCTSkip("CarveApp-StoreKit 스킴(CARVE_STOREKIT_UITEST=1)에서만 실행")
        }
        let url = Bundle(for: Self.self).url(forResource: "Carve", withExtension: "storekit")
        let session = try SKTestSession(contentsOf: try XCTUnwrap(url, "UI 테스트 번들에 Carve.storekit 이 없다"))
        session.disableDialogs = true
        session.clearTransactions()
        self.session = session
        #endif
    }

    override func tearDown() async throws {
        session?.clearTransactions()
        session = nil
    }

    /// 산 적 없음 → 복원 실패 · 취소 → 다른 기기 구매 → 환불 → 앱에서 구매 → 재실행을 차례로 본다.
    func testRestoreRefundAndPurchaseFlow() async throws {
        let session = try XCTUnwrap(session)
        let app = launch()
        openRemoveAds(app)

        // 1. 로컬 설정의 상품이 보인다 — 세션이 앱에 적용됐다.
        expect(app, contains: "2.99", step: "01-price")

        // 2. 산 적이 없으면 복원할 내역이 없다고 알린다.
        tapRestore(app)
        expect(app, contains: "복원할 구매 내역이 없어요", step: "02-nothing-to-restore")

        // 3. 동기화가 실패하면 다시 시도하라고 알린다.
        let networkError = SKTestFailures.AppStoreSync.generic(.networkError(URLError(.notConnectedToInternet)))
        try await session.setSimulatedError(networkError, forAPI: .appStoreSync)
        tapRestore(app)
        expect(app, contains: "구매 내역을 확인하지 못했어요", step: "03-restore-failed")

        // 4. Apple 계정 확인을 취소하면 아무 안내도 하지 않는다(앞 안내도 지운다).
        try await session.setSimulatedError(SKTestFailures.AppStoreSync.generic(.userCancelled), forAPI: .appStoreSync)
        tapRestore(app)
        waitUntilIdle(app)
        XCTAssertFalse(labelContains(app, "복원할 구매 내역이 없어요").exists, "취소인데 내역 없음 안내가 떴다")
        XCTAssertFalse(labelContains(app, "구매 내역을 확인하지 못했어요").exists, "취소인데 실패 안내가 남았다")
        capture(app, "04-restore-cancelled")
        try await session.setSimulatedError(nil as SKTestFailures.AppStoreSync?, forAPI: .appStoreSync)

        // 5. 켜 둔 동안 다른 기기에서 산 구매가 들어오면 구매함으로 바뀐다(Transaction.updates).
        try await session.buyProduct(identifier: Self.productID)
        expect(app, contains: "광고 없이 쓰는 중", step: "05-purchased-elsewhere")

        // 6. 환불되면 권한이 사라지고 구매 · 구매 복원 버튼이 돌아온다.
        let bought = session.allTransactions().first { $0.productIdentifier == Self.productID }
        let transaction = try XCTUnwrap(bought, "거래가 없다")
        try session.refundTransaction(identifier: transaction.identifier)
        XCTAssertTrue(app.buttons["구매 복원"].waitForExistence(timeout: 20), "환불 뒤 버튼이 돌아오지 않았다")
        capture(app, "06-refunded")

        // 7. 환불한 구매는 복원되지 않는다.
        tapRestore(app)
        expect(app, contains: "복원할 구매 내역이 없어요", step: "07-refunded-not-restored")

        // 8. 앱에서 사면 구매함이 된다.
        dismissAdValidator(app)
        app.buttons["구매"].tap()
        expect(app, contains: "광고 없이 쓰는 중", step: "08-purchased")

        // 9. 다시 실행해도 구매함이다.
        app.terminate()
        app.launch()
        openRemoveAds(app)
        expect(app, contains: "광고 없이 쓰는 중", step: "09-relaunched")
    }

    /// 앱을 끈 사이 산 구매(다른 기기 · 지우기 전 설치)를 다시 열 때 복원 없이 알아본다.
    func testLaunchRecognizesPurchaseMadeWhileClosed() async throws {
        let session = try XCTUnwrap(session)
        let app = launch()
        openRemoveAds(app)
        expect(app, contains: "2.99", step: "10-before")

        app.terminate()
        try await session.buyProduct(identifier: Self.productID)
        app.launch()
        openRemoveAds(app)
        expect(app, contains: "광고 없이 쓰는 중", step: "11-recognized-on-launch")
        XCTAssertFalse(app.buttons["구매 복원"].exists, "이미 샀는데 복원 버튼이 보인다")
    }

    // MARK: - 도구

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenFirstRunGuide", "YES"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "앱이 전면으로 오지 않았다")
        return app
    }

    /// 설정 › 광고 제거를 연다. 세로 iPad 에서 앱 설정은 성경 목록 사이드바 아래 버튼 줄에 있다.
    /// 본문 → 「성경 탐색 열기」(장 목록 열) → 「사이드바 보기」(성경 목록 열) → 「앱 설정」(시트) → 목록을 올려 「광고 제거」.
    private func openRemoveAds(_ app: XCUIApplication) {
        if app.buttons["건너뛰기"].waitForExistence(timeout: 5) {
            app.buttons["건너뛰기"].tap()
        }
        if app.buttons["먼저 시작하기"].waitForExistence(timeout: 3) {
            app.buttons["먼저 시작하기"].tap()
        }
        let settings = app.buttons["앱 설정"]
        if settings.waitForExistence(timeout: 3) == false {
            let explore = app.buttons["성경 탐색 열기"]
            guard explore.waitForExistence(timeout: 60) else {
                fail(app, "open-explore", "본문 화면이 뜨지 않았다")
                return
            }
            dismissAdValidator(app)
            explore.tap()
            let sidebar = app.buttons["사이드바 보기"]
            if sidebar.waitForExistence(timeout: 10) {
                dismissAdValidator(app)
                sidebar.tap()
            }
        }
        guard settings.waitForExistence(timeout: 10) else {
            fail(app, "open-app-settings", "앱 설정 버튼이 없다")
            return
        }
        dismissAdValidator(app)
        settings.tap()

        // 설정 목록(「사이드바」)은 화면 밖 행을 만들지 않는다 — 「광고」 섹션이 보일 때까지 올린다.
        let list = app.collectionViews["사이드바"]
        guard list.waitForExistence(timeout: 10) else {
            fail(app, "open-settings", "설정 목록이 없다")
            return
        }
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "광고 제거")).firstMatch
        var swipes = 0
        while row.exists == false || row.isHittable == false, swipes < 6 {
            list.swipeUp()
            swipes += 1
        }
        guard row.exists else {
            fail(app, "open-remove-ads", "설정에 광고 제거가 없다")
            return
        }
        row.tap()
    }

    /// Debug 의 Google 시험 네이티브 광고가 띄우는 「AdMob native ad validator」 팝업을 닫는다.
    private func dismissAdValidator(_ app: XCUIApplication) {
        let dismiss = app.buttons["Dismiss"]
        if dismiss.exists, dismiss.isHittable {
            dismiss.tap()
        }
    }

    private func tapRestore(_ app: XCUIApplication) {
        let restore = app.buttons["구매 복원"]
        XCTAssertTrue(restore.waitForExistence(timeout: 10), "구매 복원 버튼이 없다")
        dismissAdValidator(app)
        restore.tap()
        usleep(500_000)
    }

    /// 요청이 끝나 버튼이 다시 눌릴 때까지 기다린다.
    private func waitUntilIdle(_ app: XCUIApplication) {
        _ = poll(timeout: 20) { app.buttons["구매 복원"].isEnabled && app.activityIndicators.firstMatch.exists == false }
        usleep(1_000_000)
    }

    private func labelContains(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// 라벨에 `text` 가 든 요소를 기다린다. 화면은 늘 남기고, 없으면 트리도 남기고 실패한다.
    private func expect(_ app: XCUIApplication, contains text: String, step: String, timeout: TimeInterval = 20) {
        let found = labelContains(app, text).waitForExistence(timeout: timeout)
        capture(app, step)
        if found == false {
            fail(app, step, "「\(text)」 이 보이지 않는다")
        }
    }

    private func fail(_ app: XCUIApplication, _ step: String, _ message: String) {
        captureTree(app, "\(step)-tree")
        capture(app, "\(step)-failed")
        XCTFail("\(step): \(message)")
    }
}
