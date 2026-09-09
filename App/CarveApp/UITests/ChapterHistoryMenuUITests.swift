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

    /// D9-5-1 · D9-5-2 — 필기가 있는 절을 길게 눌러 메뉴를 띄우고, 그 메뉴를 눌러 시트를 연다.
    func testLongPressOpensHistoryMenuAndSheet() throws {
        try skipUnlessPhysicalDevice()
        XCUIDevice.shared.orientation = .portrait
        let app = launchCarve()
        waitForChapterReady(app)
        capture(app, "01-ready")

        let press = inkPoint(app)
        point(app, press).press(forDuration: 1.0)

        // 메뉴 항목은 bounded 쿼리로만 조회한다 — 트리 전체 열거는 열거 중 트리가 바뀌어 실패한다.
        let label = "이전 필사 내용 보기"
        let target = app.menuItems[label]
        let appeared = poll(timeout: 6) { target.exists }
        capture(app, "02-menu")   // ← D9-5-1 판정

        let items = app.menuItems.allElementsBoundByIndex.map { "\($0.label)@\($0.frame)" }
        let probe = XCTAttachment(string: """
        window=\(app.windows.firstMatch.frame) press=\(press) appeared=\(appeared) items=\(items)
        """)
        probe.name = "menu-items"
        probe.lifetime = .keepAlways
        add(probe)

        // ⚠️ `exists` 는 캐시된 스냅샷에서 참이지만 `tap()` 은 라이브 해석이 필요해 실패한다
        // ("No matches found ... IN identifiers"). remote view 라 좌표로 눌러야 한다.
        //
        // 열거되는 라벨은 낡은 값("전체 선택"·"빈칸 삽입")이지만 **frame 은 현재 메뉴를 가리킨다** —
        // 실측에서 두 frame 의 합집합(x 487.5~641.5, y 326~366.5)이 화면의 알약과 일치했다.
        // 그래서 좌표를 하드코딩하지 않고 합집합의 중심을 누른다.
        XCTAssertTrue(appeared, "롱프레스 후 '\(label)' 메뉴 항목이 조회되지 않았다")
        _ = target

        // ⛔ **좌표 탭을 하지 않는다.** 2026-09-09 에 이 자리에서 사고가 났다 —
        // 열거되는 menuItems 의 frame 은 앱 메뉴가 아니라 **PencilKit 자체 메뉴**("전체 선택")의 것이었고,
        // 그 중심을 누르자 전 획이 선택된 뒤 끌려가 **시편 119편 1~4절이 실제로 수정·저장**됐다.
        // 화면에 보이는 알약과 frame 이 우연히 겹쳐 있어 구분되지 않았다.
        //
        // 앱 메뉴는 remote view 라 조회로도 좌표로도 안전하게 누를 수 없다. D9-5-2(메뉴 → 시트)는
        // **자동화 대상에서 뺀다.** 사람이 눌러 판정한다. 여기서는 D9-5-1(메뉴가 뜨는가)까지만 본다.
        _ = target

        let summary = XCTAttachment(string: """
        sheets=\(app.sheets.allElementsBoundByIndex.count) \
        texts=\(app.staticTexts.allElementsBoundByIndex.prefix(30).map(\.label))
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
        XCUIDevice.shared.orientation = .portrait
        let frame = app.windows.firstMatch.frame
        point(app, CGVector(dx: frame.width * 0.24, dy: frame.height * 0.27)).press(forDuration: 1.0)
        sleep(2)
        capture(app, "text-side-menu")
    }
}
