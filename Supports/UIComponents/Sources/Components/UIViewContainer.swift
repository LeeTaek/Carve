//
//  UIViewContainer.swift
//  UIComponents
//
//  Created by 이택성 on 1/8/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import SwiftUI
import UIKit

import CarveToolkit

/// 광고처럼 동일 UIView 인스턴스를 재부착하거나, 토큰에 따라 UIView가 바뀔 수 있는 경우에는
/// 아래 `UIViewEmbedContainer`를 사용.
public struct UIViewEmbedContainer: UIViewRepresentable {
    private let viewProvider: @MainActor () -> UIView?

    public init(viewProvider: @escaping @MainActor () -> UIView?) {
        self.viewProvider = viewProvider
    }

    public func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = .clear
        return containerView
    }

    public func updateUIView(_ uiView: UIView, context: Context) {
        let nextView = viewProvider()
#if DEBUG
        if nextView == nil {
            if context.coordinator.didLogNil == false {
                Log.debug("[UIViewEmbedContainer] nextView is nil")
                context.coordinator.didLogNil = true
                context.coordinator.didLogProvided = false
            }
        } else {
            if context.coordinator.didLogProvided == false {
                context.coordinator.didLogProvided = true
                context.coordinator.didLogNil = false
            }
        }
#endif

        if context.coordinator.embeddedView === nextView {
            return
        }

        // 기존 embedded view 제거
        if let embeddedView = context.coordinator.embeddedView {
            embeddedView.removeFromSuperview()
            context.coordinator.embeddedView = nil
        }

        // 새 view가 없으면 종료
        guard let nextView else {
            return
        }

        nextView.removeFromSuperview()

        nextView.translatesAutoresizingMaskIntoConstraints = false
#if DEBUG
        Log.debug("[UIViewEmbedContainer] attach view to container")
#endif
        uiView.addSubview(nextView)

        NSLayoutConstraint.activate([
            nextView.leadingAnchor.constraint(equalTo: uiView.leadingAnchor),
            nextView.trailingAnchor.constraint(equalTo: uiView.trailingAnchor),
            nextView.topAnchor.constraint(equalTo: uiView.topAnchor),
            nextView.bottomAnchor.constraint(equalTo: uiView.bottomAnchor)
        ])

        context.coordinator.embeddedView = nextView
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public final class Coordinator {
        fileprivate var embeddedView: UIView?
        fileprivate var didLogNil = false
        fileprivate var didLogProvided = false

        public init() {}
    }
}
