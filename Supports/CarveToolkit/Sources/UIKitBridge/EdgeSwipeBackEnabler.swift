//
//  EdgeSwipeBackEnabler.swift
//  CarveToolkit
//
//  Created by Claude on 10/16/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import SwiftUI
import UIKit

/// 시스템 내비게이션 막대를 숨긴 앱 스택 화면에서도 왼쪽 가장자리 쓸기로 뒤로 가게 한다.
///
/// UIKit 은 막대를 숨긴 화면에서 뒤로 쓸기(`interactivePopGestureRecognizer`)를 시작하지 않는다(2.2 책장 시안 — 막대 없이 떠 있는 버튼).
/// 이 화면이 보이는 동안만 쓸기의 시작 판정(delegate)을 맡아 「스택에 화면이 둘 이상이면 시작」 으로 두고,
/// 사라질 때(쓸기가 시작될 때 포함) 원래 판정으로 돌려 둔다 — 다른 화면의 쓸기는 바뀌지 않는다.
struct EdgeSwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        /// 맡기 전의 판정 — 사라질 때 돌려 둔다.
        private weak var originalDelegate: (any UIGestureRecognizerDelegate)?
        /// 판정을 맡은 쓸기.
        private weak var takenGesture: UIGestureRecognizer?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard let gesture = navigationController?.interactivePopGestureRecognizer, gesture.delegate !== self else { return }
            originalDelegate = gesture.delegate
            takenGesture = gesture
            gesture.delegate = self
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            guard let gesture = takenGesture, gesture.delegate === self else { return }
            gesture.delegate = originalDelegate
            takenGesture = nil
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            (navigationController?.viewControllers.count ?? 0) > 1
        }
    }
}

extension View {
    /// 시스템 내비게이션 막대를 숨긴 앱 스택 화면에서도 왼쪽 가장자리 쓸기로 뒤로 가게 한다(`EdgeSwipeBackEnabler`).
    public func edgeSwipeBackEnabled() -> some View {
        background(EdgeSwipeBackEnabler().frame(width: 0, height: 0).accessibilityHidden(true))
    }
}
