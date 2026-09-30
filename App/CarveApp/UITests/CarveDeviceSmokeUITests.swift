//
//  CarveDeviceSmokeUITests.swift
//  CarveAppUITests
//
//  실기기 터치 자동화 (D9-5 · D9-7). XCUITest 러너가 iPadOS 27.0 beta 기기에 붙는 것을 확인했다 (2026-09-08).
//  ⚠️ **Pencil 입력은 범위 밖이다** — `drawingPolicy` 가 `.pencilOnly` 라 합성 터치는 무시되고,
//  손가락 필사를 켜도 압력·기울기가 없다. 자동화되는 것은 **탭·롱프레스·스와이프·스크린샷** 뿐이다.
//

import XCTest

final class CarveDeviceSmokeUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// 스플래시가 걷히고 본문이 올라올 때까지 기다린다.
    ///
    /// 첫 시도는 `otherElements.firstMatch` 를 기다렸는데 스플래시에서 즉시 만족돼 로딩 화면을 찍었다.
    /// 본문 행이 실제로 생겼는지를 조건으로 삼는다.
    @discardableResult
    private func waitForChapter(_ app: XCUIApplication, timeout: TimeInterval = 40) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if app.staticTexts.count > 3 { return true }
            usleep(500_000)
        }
        return false
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// 무계정 전용 iPad simulator에서 명시적으로 실행한다. 기존 실제 필기/계정 시험 기기에 실행하지 않는다.
    /// 2.0.0 은 실행 중에 다시 연결하지 않는다(2026-09-28 결정) — 보류 안내가 앱을 다시 열라고 말하고, 「다시 시도」 와 연결 대기 표시가 없다.
    func testHeldStoreGuidesRelaunchWithoutRetry() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("무계정 시험 simulator 전용")
        #endif
        guard ProcessInfo.processInfo.environment["CARVE_RECONNECT_SMOKE"] == "1" else {
            throw XCTSkip("CARVE_RECONNECT_SMOKE=1인 별도 무계정 iPad에서만 실행")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenFirstRunGuide", "YES", "-SingleCanvas"]
            + startChapterArguments(bookFile: "1-01Genesis.txt", chapter: 22)
        app.launch()
        if app.buttons["건너뛰기"].waitForExistence(timeout: 10) {
            app.buttons["건너뛰기"].tap()
        }
        XCTAssertTrue(app.buttons["성경 탐색 열기"].waitForExistence(timeout: 45))
        // 로그인하지 않았다 — 재실행 안내(로그인 · 소유 확인 뒤에만 뜬다)는 없어야 한다.
        XCTAssertFalse(app.otherElements["relaunchGuidance"].exists)
        app.buttons["성경 탐색 열기"].tap()
        XCTAssertTrue(app.buttons["앱 설정"].waitForExistence(timeout: 10))
        app.buttons["앱 설정"].tap()

        XCTAssertTrue(app.staticTexts["cloudSettings.connectionHeld"].waitForExistence(timeout: 10), "무계정 보류 안내가 없다")
        let detail = app.staticTexts["cloudSettings.connectionHeldDetail"]
        XCTAssertTrue(detail.exists)
        XCTAssertTrue(detail.label.contains("iCloud에 로그인한 뒤 앱을 완전히 종료하고 다시 열면"), "재실행 안내가 없다: \(detail.label)")
        XCTAssertFalse(app.buttons["cloudSettings.retryConnection"].exists, "실행 중 재연결 버튼이 남아 있다")
        XCTAssertFalse(app.buttons["다시 시도"].exists)
        attach(app, "held-store-guides-relaunch")
    }

    /// 접근성 트리를 남긴다 — D9-5(롱프레스 → 메뉴)·D9-7(탭·fling)을 쓰려면 요소 구조를 알아야 한다.
    func testCaptureChapterAndAccessibilityTree() throws {
        try skipUnlessPhysicalDevice()
        let app = XCUIApplication()
        app.launchArguments = ["-SingleCanvas", "-ChapterLayoutOverlay"]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "앱이 전면으로 오지 않았다")
        XCTAssertTrue(waitForChapter(app), "본문이 뜨지 않았다 — 스플래시에 머물렀다")

        attach(app, "chapter")

        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "accessibility-tree"
        tree.lifetime = .keepAlways
        add(tree)

        let counts = """
        staticTexts=\(app.staticTexts.count) buttons=\(app.buttons.count) \
        otherElements=\(app.otherElements.count) scrollViews=\(app.scrollViews.count) \
        switches=\(app.switches.count) cells=\(app.cells.count)
        """
        let summary = XCTAttachment(string: counts)
        summary.name = "element-counts"
        summary.lifetime = .keepAlways
        add(summary)
    }
}
