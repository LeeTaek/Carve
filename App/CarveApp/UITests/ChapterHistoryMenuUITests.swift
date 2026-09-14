//
//  ChapterHistoryMenuUITests.swift
//  CarveAppUITests
//
//  D9-5 — 히스토리 메뉴 (설계 §20-11 · 런북 §6-9 D9-5).
//
//  절 메뉴는 앱 안의 SwiftUI 오버레이(`VerseMenuOverlay`, 시안 E1)다. 항목은 버튼으로 트리에 올라오므로
//  **식별자 `verseMenu.<항목>` 으로 조회**한다 (2026-09-14 전환).
//  그 전의 `UIEditMenuInteraction` 메뉴는 앱 밖 remote view 라 라벨로 조회되지 않았고, `menuItems` 로 보이던 것은
//  PencilKit 자체 메뉴였다 — 그래서 옛 `menuItems["이전 필사 내용 보기"]` 판정은 지금 메뉴를 보지 못한다.
//

import XCTest

final class ChapterHistoryMenuUITests: XCTestCase {

    /// 절 메뉴 항목 식별자 (`VerseMenuOverlay`).
    private enum VerseMenuID {
        static let history = "verseMenu.history"
        static let image = "verseMenu.image"
        static let widget = "verseMenu.widget"
        static let erase = "verseMenu.erase"
        static let all = [history, image, widget, erase]
    }

    /// 필사 컬럼 안(시편 119편 1절)의 누를 지점을 **창 크기에서 계산**한다.
    ///
    /// 좌표를 하드코딩했다가 기기가 가로로 남아 있어 엉뚱한 곳을 눌렀다 (2026-09-09).
    /// 오른손 설정에서 필사 컬럼은 화면 오른쪽 절반이다.
    private func inkPoint(_ app: XCUIApplication) -> CGVector {
        let frame = app.windows.firstMatch.frame
        return CGVector(dx: frame.width * 0.75, dy: frame.height * 0.27)
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func point(_ app: XCUIApplication, _ vector: CGVector) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero).withOffset(vector)
    }

    /// 필기가 있는 시편 119편에서 앱을 띄운다.
    private func launchAtInkedChapter() -> XCUIApplication {
        launchCarve(extra: startChapterArguments(bookFile: "1-19Psalms.txt", chapter: 119))
    }

    /// D9-5-1 — 필기가 있는 절을 길게 누르면 절 메뉴가 뜬다.
    ///
    /// 메뉴는 보여 줄 항목이 있을 때만 뜬다(UI-2) — 쓰기만 한 절은 「지우기」 만, 지운 뒤에는 「이전 필사 내용 보기」 만.
    /// 「이미지 저장」 은 메뉴가 열리면 늘 (비활성으로) 있으므로, 보관본 유무와 무관하게 그것으로 메뉴가 떴는지 본다.
    /// 이 기기의 시편 119편 1절에 필기가 없으면 메뉴가 뜨지 않는 것이 정상이다.
    func testLongPressOpensHistoryMenuAndSheet() throws {
        try skipUnlessPhysicalDevice()
        XCUIDevice.shared.orientation = .portrait
        let app = launchAtInkedChapter()
        waitForChapterReady(app)
        capture(app, "01-ready")

        let press = inkPoint(app)
        point(app, press).press(forDuration: 1.0)

        let appeared = poll(timeout: 6) { app.buttons[VerseMenuID.image].exists }
        capture(app, "02-menu")   // ← D9-5-1 판정

        let present = VerseMenuID.all.filter { app.buttons[$0].exists }
        let probe = XCTAttachment(string: """
        window=\(app.windows.firstMatch.frame) press=\(press) appeared=\(appeared) items=\(present)
        """)
        probe.name = "menu-items"
        probe.lifetime = .keepAlways
        add(probe)

        XCTAssertTrue(appeared, "롱프레스 후 절 메뉴가 뜨지 않았다 — 시편 119편 1절에 필기가 있는지 확인한다")

        // ⛔ **메뉴 항목을 누르지 않는다.** 「지우기」 는 실제 필사를 보관 후 비운다.
        // 2026-09-09 에는 좌표 탭이 PencilKit 메뉴를 눌러 **시편 119편 1~4절이 실제로 수정·저장**됐다.
        // D9-5-2(메뉴 → 이전 필사 시트)는 자동화 대상에서 빼고 사람이 눌러 판정한다. 여기서는 D9-5-1 까지만 본다.
    }

    /// D9-5-3 — 본문(텍스트) 쪽에서 길게 눌러도 x 클램프로 같은 절이 잡히는지. 판정은 스크린샷으로 한다.
    func testLongPressOnTextSideClampsToSameVerse() throws {
        try skipUnlessPhysicalDevice()
        let app = launchAtInkedChapter()
        waitForChapterReady(app)

        // 본문은 왼쪽 절반이다 (columnX 366.70 왼쪽).
        XCUIDevice.shared.orientation = .portrait
        let frame = app.windows.firstMatch.frame
        point(app, CGVector(dx: frame.width * 0.24, dy: frame.height * 0.27)).press(forDuration: 1.0)
        sleep(2)
        capture(app, "text-side-menu")
    }
}
