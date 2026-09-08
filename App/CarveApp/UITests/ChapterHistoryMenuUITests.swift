//
//  ChapterHistoryMenuUITests.swift
//  CarveAppUITests
//
//  D9-5 — 히스토리 메뉴 (설계 §20-11 · 런북 §6-9 D9-5).
//
//  ⚠️ **`UIEditMenuInteraction` 은 앱 밖 remote view 로 렌더된다.** 앱·springboard 어느 트리에서도
//  라벨로 조회되지 않는 것을 확인했다(2026-09-08). 따라서 **존재는 스크린샷으로 판정**하고
//  **조작은 좌표로** 한다. 트리를 통째로 열거하는 방식은 열거 중 트리가 바뀌어 실패한다.
//

import XCTest

final class ChapterHistoryMenuUITests: XCTestCase {

    /// 필사 컬럼 안(시편 119편 1절)의 누를 지점. ScrollView frame {{0,32},{744,1081}} 기준.
    private let pressPoint = CGVector(dx: 558, dy: 302)

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func point(_ app: XCUIApplication, _ vector: CGVector) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero).withOffset(vector)
    }

    /// D9-5-1 · D9-5-2 — 필기가 있는 절을 길게 눌러 메뉴를 띄우고, 그 메뉴를 눌러 시트를 연다.
    func testLongPressOpensHistoryMenuAndSheet() throws {
        try skipUnlessPhysicalDevice()
        let app = launchCarve()
        waitForChapterReady(app)
        capture(app, "01-ready")

        point(app, pressPoint).press(forDuration: 1.0)
        sleep(2)
        capture(app, "02-menu")   // ← D9-5-1 판정: '이전 필사 내용 보기' 가 보여야 한다

        // 실측 기하: 메뉴의 오른쪽 끝이 누른 지점에 붙고 세로 중심은 같다.
        point(app, CGVector(dx: pressPoint.dx - 55, dy: pressPoint.dy - 5)).tap()
        sleep(3)
        capture(app, "03-sheet")  // ← D9-5-2 판정: 시트가 뜨고 1절이 잡혀야 한다

        let summary = XCTAttachment(string: """
        sheets=\(app.sheets.allElementsBoundByIndex.count) \
        navBars=\(app.navigationBars.allElementsBoundByIndex.map(\.identifier)) \
        texts=\(app.staticTexts.allElementsBoundByIndex.prefix(24).map(\.label))
        """)
        summary.name = "sheet-summary"
        summary.lifetime = .keepAlways
        add(summary)
    }

    /// D9-5-3 — 본문(텍스트) 쪽에서 길게 눌러도 x 클램프로 같은 절이 잡히는지.
    func testLongPressOnTextSideClampsToSameVerse() throws {
        try skipUnlessPhysicalDevice()
        let app = launchCarve()
        waitForChapterReady(app)

        // 본문은 왼쪽 절반이다 (columnX 366.70 왼쪽).
        point(app, CGVector(dx: 180, dy: 302)).press(forDuration: 1.0)
        sleep(2)
        capture(app, "text-side-menu")
    }
}
