//
//  ChapterScrollGestureUITests.swift
//  CarveAppUITests
//
//  D9-7 — §11 잔여 기준 2(관성 fling) · 5(탭/헤더 애니메이션) (런북 §6-9 D9-7).
//
//  ⛔ **안전 규칙 (2026-09-09 사고 이후).**
//  1. 자동화는 **시편 122편(테스트 장)** 에서만 돈다. 실제 필사가 있는 장은 건드리지 않는다.
//  2. **잉크 컬럼 안을 탭하지 않는다.** PencilKit 의 편집 메뉴가 뜨고, 그 항목을 잘못 누르면
//     전 획이 선택돼 끌려가 저장된다 — 실제로 시편 119편 1~4절이 그렇게 수정됐다.
//  3. 스와이프와 헤더 버튼 탭만 쓴다. 둘 다 저장을 건드리지 않는다.
//

import XCTest

final class ChapterScrollGestureUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// 헤더의 다음 장 버튼으로 목표 장까지 이동한다. HUD 의 장 라벨로 도착을 확인한다.
    private func move(_ app: XCUIApplication, toChapter chapter: String, maxSteps: Int = 8) -> Bool {
        for _ in 0..<maxSteps {
            if hudValue(app, prefix: chapter) != nil { return true }
            app.buttons["Next"].tap()
            _ = poll(timeout: 20) { self.hudValue(app, prefix: "gate PASS") != nil }
            usleep(800_000)
        }
        return hudValue(app, prefix: chapter) != nil
    }

    /// D9-7-1 — 관성 fling 을 위·아래로 반복하고 끝에서 bounce 시킨 뒤, 잉크와 본문이 어긋나지 않는지 본다.
    func testInertialFlingKeepsInkAlignedWithText() throws {
        try skipUnlessPhysicalDevice()
        XCUIDevice.shared.orientation = .portrait
        let app = launchCarve()
        waitForChapterReady(app)

        XCTAssertTrue(move(app, toChapter: "시편 122장"), "테스트 장(시편 122편)에 도달하지 못했다")
        waitForChapterReady(app)
        capture(app, "d97-01-before-fling")

        // 본문 왼쪽 절반에서 스와이프한다 — 잉크 컬럼을 건드리지 않기 위함이다.
        let frame = app.windows.firstMatch.frame
        let top = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.width * 0.25, dy: frame.height * 0.30))
        let bottom = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.width * 0.25, dy: frame.height * 0.80))

        for _ in 0..<4 { bottom.press(forDuration: 0.01, thenDragTo: top) }   // 아래로 빠르게
        usleep(1_500_000)
        capture(app, "d97-02-flung-down")

        for _ in 0..<6 { top.press(forDuration: 0.01, thenDragTo: bottom) }   // 위로 — 끝에서 bounce
        usleep(1_500_000)
        capture(app, "d97-03-flung-up-bounce")

        let hud = XCTAttachment(string: """
        gate=\(hudValue(app, prefix: "gate") ?? "—") \
        compose=\(hudValue(app, prefix: "compose") ?? "—") \
        delta=\(hudValue(app, prefix: "Δ max") ?? "—") \
        guardState=\(hudValue(app, prefix: "guard") ?? "—") \
        H=\(hudValue(app, prefix: "H ") ?? "—") \
        frames=\(hudValue(app, prefix: "frames") ?? "—")
        """)
        hud.name = "d97-hud-after-fling"
        hud.lifetime = .keepAlways
        add(hud)
    }

    /// D9-7-3 — 헤더 토글 탭과 헤더 애니메이션 중 스크롤.
    func testHeaderTapAndScrollDuringAnimation() throws {
        try skipUnlessPhysicalDevice()
        XCUIDevice.shared.orientation = .portrait
        let app = launchCarve()
        waitForChapterReady(app)
        XCTAssertTrue(move(app, toChapter: "시편 122장"), "테스트 장에 도달하지 못했다")
        waitForChapterReady(app)

        let frame = app.windows.firstMatch.frame
        let top = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.width * 0.25, dy: frame.height * 0.30))
        let bottom = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.width * 0.25, dy: frame.height * 0.80))

        // 헤더가 접히도록 아래로 스크롤한 뒤, 애니메이션이 도는 동안 곧바로 반대로 스크롤한다.
        bottom.press(forDuration: 0.01, thenDragTo: top)
        capture(app, "d97-04-header-collapsing")
        top.press(forDuration: 0.01, thenDragTo: bottom)
        usleep(1_200_000)
        capture(app, "d97-05-header-restored")

        XCTAssertTrue(app.buttons["Next"].exists, "헤더 버튼이 사라졌다")
    }
}
