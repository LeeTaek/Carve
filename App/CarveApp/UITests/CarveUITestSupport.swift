//
//  CarveUITestSupport.swift
//  CarveAppUITests
//
//  실기기 UI 테스트 공용 도구 (2026-09-08 신설).
//
//  ⚠️ **자동화할 수 있는 것과 없는 것을 구분한다.**
//  - 가능: 탭 · 롱프레스 · 스와이프 · 스크린샷 · HUD 판독 (헤더 버튼과 HUD 가 접근성 트리에 노출된다)
//  - 불가: **Apple Pencil 입력.** `drawingPolicy` 가 `.pencilOnly` 라 합성 터치는 무시되고,
//    손가락 필사를 켜도 압력·기울기가 없다. D9-1·D9-2·D9-3 의 필기·지우개는 여전히 사람 손이다.
//

import XCTest

extension XCTestCase {

    /// 이 UI 테스트들은 **실기기 전용**이다.
    ///
    /// 시뮬레이터에서는 앱이 종료 신호로 죽어(`signal term`) 무관한 실패를 만든다. 무엇보다
    /// 검증 대상이 실기기 표시·터치라 시뮬레이터 실행은 의미가 없다. 표준 검증 명령
    /// (`xcodebuild test -scheme Carve-Workspace`, 시뮬레이터)이 이것 때문에 빨개지면 안 되므로 건너뛴다.
    func skipUnlessPhysicalDevice() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("실기기 전용 — 시뮬레이터에서는 건너뛴다")
        #endif
    }

    /// HUD 가 노출하는 값을 읽는다. `-ChapterLayoutOverlay` 가 켜져 있어야 한다.
    ///
    /// HUD 는 `StaticText` 로 트리에 올라오므로 라벨 접두사로 찾는다.
    func hudValue(_ app: XCUIApplication, prefix: String) -> String? {
        let predicate = NSPredicate(format: "label BEGINSWITH %@", prefix)
        let match = app.staticTexts.matching(predicate).firstMatch
        guard match.exists else { return nil }
        return match.label
    }

    /// 본문 레이아웃이 완성될 때까지 기다린다 (`gate PASS`).
    @discardableResult
    func waitForGate(_ app: XCUIApplication, timeout: TimeInterval = 45) -> Bool {
        poll(timeout: timeout) { self.hudValue(app, prefix: "gate PASS") != nil }
    }

    /// 합성이 현재 레이아웃을 따라잡을 때까지 기다린다.
    ///
    /// ⚠️ **이 대기가 없으면 오판한다.** `gate PASS` 직후에는 `compose STALE` 이라 잉크가 아직 안 그려져 있고,
    /// 그 시점에 캡처하면 "필기가 사라졌다" 로 읽힌다 (2026-09-08 실측에서 실제로 겪음).
    @discardableResult
    func waitForComposeSync(_ app: XCUIApplication, timeout: TimeInterval = 30) -> Bool {
        poll(timeout: timeout) { self.hudValue(app, prefix: "compose SYNC") != nil }
    }

    /// 장이 완전히 준비될 때까지 — 게이트 + 합성 + 안정화 여유.
    func waitForChapterReady(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(waitForGate(app), "gate 가 열리지 않았다", file: file, line: line)
        XCTAssertTrue(waitForComposeSync(app), "compose 가 SYNC 로 가지 않았다", file: file, line: line)
        // 마지막 렌더가 화면에 반영될 여유.
        usleep(1_500_000)
    }

    func poll(timeout: TimeInterval, interval: TimeInterval = 0.25, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            usleep(useconds_t(interval * 1_000_000))
        }
        return condition()
    }

    /// 판정용 캡처. 이름은 결과 판독 때 파일명이 된다.
    func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// 접근성 트리 덤프 — 조작 대상을 찾을 때 쓴다.
    func captureTree(_ app: XCUIApplication, _ name: String) {
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name
        tree.lifetime = .keepAlways
        add(tree)
    }

    /// 오버레이를 켠 채 앱을 띄운다.
    func launchCarve(singleCanvas: Bool = true, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = (singleCanvas ? ["-SingleCanvas"] : []) + ["-ChapterLayoutOverlay"] + extra
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "앱이 전면으로 오지 않았다")
        return app
    }
}
