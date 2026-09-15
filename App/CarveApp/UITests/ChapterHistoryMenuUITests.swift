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

    /// 누를 지점의 기준이 되는 화면 요소 (접근성 라벨).
    ///
    /// 좌표는 창 크기가 아니라 **보이는 요소에서** 만든다. 헤더 광고 높이 · 창 위치 · 방향이 바뀌어도 1절을 누르기 위함이다.
    /// - 2026-09-09: 좌표를 하드코딩했다가 기기가 가로로 남아 있어 엉뚱한 곳을 눌렀다.
    /// - 2026-09-15: 창 크기 비율로 바꿨더니, 창 모드(창 y=177)에서 앱 좌표 원점이 화면 원점이라 헤더 위 여백을 눌렀다.
    private enum Anchor {
        /// 1절 번호 (`VerseTextView` 의 접근성 라벨). 1절 첫 줄 높이에 있다.
        /// 단일 Canvas 에서는 본문 컬럼이 캔버스 안이라 `ChapterPKCanvasView.accessibilityElements` 가 노출해야 트리에 올라온다.
        static let firstVerseNumber = "1절"
        /// 필사 반쪽의 열 라벨 (`ChapterColumnHeader`). 왼손 설정에서도 필사 반쪽 안에 있다.
        static let writingColumn = "나의 필사 · 절을 길게 눌러 더 보기"
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func firstVerseNumber(_ app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(identifier: Anchor.firstVerseNumber).firstMatch
    }

    private func writingColumn(_ app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(identifier: Anchor.writingColumn).firstMatch
    }

    /// 누를 기준 요소가 트리에 있는지 확인한다. 없으면 좌표를 만들 수 없으므로 여기서 멈춘다.
    private func requireAnchors(_ app: XCUIApplication) {
        XCTAssertTrue(firstVerseNumber(app).waitForExistence(timeout: 5), "1절 번호(「\(Anchor.firstVerseNumber)」)를 찾지 못했다")
        XCTAssertTrue(writingColumn(app).exists, "필사 열 라벨(「\(Anchor.writingColumn)」)을 찾지 못했다")
    }

    /// 1절 높이에서 필사 반쪽을 누를 지점. 두 frame 은 모두 화면 좌표라, 그 차이만큼 옮기면 창 위치와 무관하다.
    private func inkPoint(_ app: XCUIApplication) -> XCUICoordinate {
        let verse = firstVerseNumber(app)
        return verse.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .withOffset(CGVector(dx: writingColumn(app).frame.midX - verse.frame.midX, dy: 0))
    }

    /// 1절 높이에서 본문 첫 줄을 누를 지점 — 절 번호 바로 오른쪽 글자다.
    private func textPoint(_ app: XCUIApplication) -> XCUICoordinate {
        firstVerseNumber(app).coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
            .withOffset(CGVector(dx: 60, dy: 0))
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
        requireAnchors(app)
        capture(app, "01-ready")

        let press = inkPoint(app)
        press.press(forDuration: 1.0)

        let appeared = poll(timeout: 6) { app.buttons[VerseMenuID.image].exists }
        capture(app, "02-menu")   // ← D9-5-1 판정

        let present = VerseMenuID.all.filter { app.buttons[$0].exists }
        let probe = XCTAttachment(string: """
        window=\(app.windows.firstMatch.frame) verse=\(firstVerseNumber(app).frame) \
        press=\(press.screenPoint) appeared=\(appeared) items=\(present)
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
        XCUIDevice.shared.orientation = .portrait
        let app = launchAtInkedChapter()
        waitForChapterReady(app)
        requireAnchors(app)

        textPoint(app).press(forDuration: 1.0)
        sleep(2)
        capture(app, "text-side-menu")
    }
}
