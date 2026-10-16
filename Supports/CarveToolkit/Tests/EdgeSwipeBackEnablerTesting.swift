//
//  EdgeSwipeBackEnablerTesting.swift
//  CarveToolkitTest
//
//  Created by Claude on 10/16/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

@testable import CarveToolkit
import Testing
import UIKit

/// 막대를 숨긴 앱 스택 화면의 뒤로 쓸기 — 보이는 동안만 시작 판정을 맡고, 사라지면 원래 판정으로 돌려 둔다.
@MainActor
@Suite("가장자리 쓸기로 뒤로 가기")
struct EdgeSwipeBackEnablerTesting {
    /// 역할: `host` 안에 판정 맡는 컨트롤러를 자식으로 붙인다(SwiftUI 가 화면에 붙이는 것과 같은 꼴).
    private static func attachEnabler(to host: UIViewController) -> EdgeSwipeBackEnabler.Controller {
        let enabler = EdgeSwipeBackEnabler.Controller()
        host.addChild(enabler)
        host.view.addSubview(enabler.view)
        enabler.didMove(toParent: host)
        return enabler
    }

    @Test("올린 화면이 보이는 동안 쓸기 판정을 맡아 시작하게 하고, 사라지면 원래 판정으로 돌려 둔다")
    func takesOverWhileVisible() throws {
        let navigation = UINavigationController(rootViewController: UIViewController())
        let shelf = UIViewController()
        navigation.pushViewController(shelf, animated: false)
        navigation.loadViewIfNeeded()
        let gesture = try #require(navigation.interactivePopGestureRecognizer)
        let original = gesture.delegate
        let enabler = Self.attachEnabler(to: shelf)

        enabler.viewDidAppear(false)
        #expect(gesture.delegate === enabler)
        #expect(enabler.gestureRecognizerShouldBegin(gesture))

        enabler.viewWillDisappear(false)
        #expect(gesture.delegate === original)
    }

    @Test("스택에 화면이 하나뿐이면 쓸기를 시작하지 않는다")
    func doesNotBeginOnRoot() throws {
        let root = UIViewController()
        let navigation = UINavigationController(rootViewController: root)
        navigation.loadViewIfNeeded()
        let gesture = try #require(navigation.interactivePopGestureRecognizer)
        let enabler = Self.attachEnabler(to: root)

        enabler.viewDidAppear(false)
        #expect(!enabler.gestureRecognizerShouldBegin(gesture))
        enabler.viewWillDisappear(false)
    }

    @Test("판정을 다른 곳이 이미 바꿨으면 사라질 때 덮어쓰지 않는다")
    func leavesForeignDelegate() throws {
        let navigation = UINavigationController(rootViewController: UIViewController())
        let shelf = UIViewController()
        navigation.pushViewController(shelf, animated: false)
        navigation.loadViewIfNeeded()
        let gesture = try #require(navigation.interactivePopGestureRecognizer)
        let enabler = Self.attachEnabler(to: shelf)
        let foreign = ForeignDelegate()

        enabler.viewDidAppear(false)
        gesture.delegate = foreign
        enabler.viewWillDisappear(false)
        #expect(gesture.delegate === foreign)
    }
}

/// 다른 곳이 단 쓸기 판정.
private final class ForeignDelegate: NSObject, UIGestureRecognizerDelegate {}
