//
//  TwoFingerTapDoubleTapView.swift
//  CarveToolkit
//
//  Created by 이택성 on 12/3/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import UIKit
import SwiftUI

struct TwoFingerTapDoubleTapView: UIViewRepresentable {
    let action: () -> Void

    func makeUIView(context: Context) -> HelperView {
        let view = HelperView()
        view.action = action
        return view
    }

    func updateUIView(_ uiView: HelperView, context: Context) {
        uiView.action = action
    }

    final class HelperView: UIView {
        var action: (() -> Void)?
        private var didAttachGesture = false

        // 두 손가락 더블탭용 제스처 하나만 재사용
        private lazy var gesture: UITapGestureRecognizer = {
            let g = UITapGestureRecognizer(
                target: self,
                action: #selector(handleDoubleTap(_:))
            )
            g.numberOfTapsRequired = 2
            g.numberOfTouchesRequired = 2
            g.cancelsTouchesInView = false
            return g
        }()

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            // 이 뷰는 터치를 아예 안 받게 해서 ScrollView 스크롤을 막지 않음
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            attachGestureToScrollViewIfNeeded()
        }

        /// hit-test에 참여하지 않도록 해서, ScrollView 스크롤을 막지 않음
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            return nil
        }

        private func attachGestureToScrollViewIfNeeded() {
            // 이미 붙었으면 더 안 함
            guard !didAttachGesture else { return }

            // window 기준으로 전체 뷰 트리 탐색
            guard let root = window else {
                // 아직 window가 없으면 다음 runloop에서 재시도
                DispatchQueue.main.async { [weak self] in
                    self?.attachGestureToScrollViewIfNeeded()
                }
                return
            }

            guard let scrollView = findScrollView(in: root) else {
                DispatchQueue.main.async { [weak self] in
                    self?.attachGestureToScrollViewIfNeeded()
                }
                return
            }

            scrollView.addGestureRecognizer(gesture)
            didAttachGesture = true
        }

        private func findScrollView(in view: UIView) -> UIScrollView? {
            if let scroll = view as? UIScrollView {
                return scroll
            }
            for subview in view.subviews {
                if let found = findScrollView(in: subview) {
                    return found
                }
            }
            return nil
        }

        @objc private func handleDoubleTap(_ sender: UITapGestureRecognizer) {
            guard sender.state == .ended else { return }
            action?()
        }
    }
}
