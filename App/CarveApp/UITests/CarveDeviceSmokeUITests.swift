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
