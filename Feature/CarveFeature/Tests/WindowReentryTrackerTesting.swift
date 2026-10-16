//
//  WindowReentryTrackerTesting.swift
//  CarveFeatureTest
//
//  2.2 도구 막대 결함 — 필사 화면이 창을 떠났다가 돌아오면 도크 안을 새로 만든다(docs/notebook-design.md §9-2).
//  「떠났다가 다시 들어옴」 판정은 순수 상태라 UI 없이, 창 소속을 받는 UIKit 관찰 뷰는 화면 밖 `UIWindow` 로 고정한다.
//  관찰을 SwiftUI onAppear · onDisappear 로 하던 첫 수정은 iPadOS 18.6 에서 끝없이 돌았다 — 그래서 창 소속(`didMoveToWindow`)으로 본다.
//

import Testing
import UIKit

@testable import CarveFeature

@Suite("창 재진입 판정 — 떠났다가 돌아올 때만 알린다")
struct WindowReentryTrackerTesting {
    @Test("처음 창에 붙을 때는 알리지 않는다")
    func firstEntryIsNotReentry() {
        var tracker = WindowReentryTracker()

        let reentered = tracker.windowChanged(isInWindow: true)

        #expect(reentered == false)
    }

    @Test("창을 떠났다가 다시 들어오면 알린다")
    func leavingThenEnteringIsReentry() {
        var tracker = WindowReentryTracker()
        _ = tracker.windowChanged(isInWindow: true)

        // 책장이 올라와 필사 화면이 창에서 빠졌다가 돌아온다.
        let left = tracker.windowChanged(isInWindow: false)
        let reentered = tracker.windowChanged(isInWindow: true)

        #expect(left == false)
        #expect(reentered)
        #expect(tracker.hasLeftWindow == false)
    }

    @Test("거듭 떠나고 거듭 붙어도 돌아온 한 번만 센다")
    func repeatedChangesCountOnce() {
        var tracker = WindowReentryTracker()
        _ = tracker.windowChanged(isInWindow: false)
        _ = tracker.windowChanged(isInWindow: false)

        let first = tracker.windowChanged(isInWindow: true)
        let again = tracker.windowChanged(isInWindow: true)

        #expect(first)
        #expect(again == false)
    }

    @Test("왕복마다 한 번씩 알린다")
    func everyRoundTripIsReentry() {
        var tracker = WindowReentryTracker()
        _ = tracker.windowChanged(isInWindow: true)
        var reentries = 0

        for _ in 0..<3 {
            _ = tracker.windowChanged(isInWindow: false)
            if tracker.windowChanged(isInWindow: true) { reentries += 1 }
        }

        #expect(reentries == 3)
    }

    @Test("관찰 뷰 — 창에서 빠졌다가 다시 붙으면 다음 차례에 한 번 알린다")
    @MainActor
    func observerViewNotifiesOnceAfterWindowRoundTrip() async {
        // 화면 밖 창에 놓는다. 처음 붙을 때는 알리지 않는다.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        let container = UIView(frame: window.bounds)
        let observer = WindowReentryObserver.ObserverView()
        var notified = 0
        observer.onReenter = { notified += 1 }
        container.addSubview(observer)
        window.addSubview(container)
        await drainMainQueue()
        #expect(notified == 0)

        // 앱 스택에 화면이 올라간 것처럼 창에서 뺐다가 다시 붙인다.
        container.removeFromSuperview()
        await drainMainQueue()
        #expect(notified == 0)
        window.addSubview(container)
        await drainMainQueue()

        #expect(notified == 1)
    }

    /// 관찰 뷰가 `DispatchQueue.main.async` 로 미룬 알림까지 돌게 한다.
    @MainActor
    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }
}
