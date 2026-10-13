//
//  PencilIgnoringContextMenu.swift
//  CarveFeature
//
//  Created by 이택성 on 7/31/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import SwiftUI

 struct TouchIgnoringContextMenu<Content: View>: UIViewRepresentable {
    public typealias UIViewType = UIView

    let ignoringType: UITouch.TouchType
    let content: () -> Content
    let menu: () -> UIMenu
    
    func makeUIView(context: Context) -> UIViewType {
        // 따로 만든 호스트는 바깥 환경을 물려받지 않는다 — 화면 언어(환경 locale)를 넣고, 갱신 때 다시 넣으려고 붙잡아 둔다.
        let hosting = UIHostingController(rootView: Self.hosted(content(), locale: context.environment.locale))
        context.coordinator.hosting = hosting
        context.coordinator.hostedLocale = context.environment.locale
        let view = hosting.view!
        // 호스팅 뷰의 기본 배경(systemBackground)이 행마다 흰 띠로 비치지 않게 한다 — 바탕은 감싸는 쪽(종이)이 칠한다.
        view.backgroundColor = .clear

        let longPress = UILongPressGestureRecognizer(target: context.coordinator,
                                                     action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.5
        longPress.delegate = context.coordinator
        view.addGestureRecognizer(longPress)
        
        return view
    }
    
    /// 화면 언어가 바뀐 때만 호스트의 `rootView` 를 다시 넣는다.
    ///
    /// 예전에는 `uiView.subviews` 의 `next` 로 호스트를 찾았지만 한 번도 찾지 못했다(subview 의 다음 응답자는 호스트 뷰이고,
    /// 붙잡지 않은 호스트는 사라진다 — 2026-10-13 계측 124/124). 행 안 값(왼손 모드 등)은 행 뷰가 스토어를 직접 관찰해 바뀌어 왔다.
    /// 환경 locale 은 그렇게 오지 않으므로 붙잡아 둔 호스트에 넣는다. 갱신마다 넣지 않는다 — 행이 다시 그려지면 실측이 흔들릴 수 있다.
    func updateUIView(_ uiView: UIViewType, context: Context) {
        let locale = context.environment.locale
        guard let hosting = context.coordinator.hosting, context.coordinator.hostedLocale != locale else { return }
        context.coordinator.hostedLocale = locale
        hosting.rootView = Self.hosted(content(), locale: locale)
    }

    private static func hosted(_ content: Content, locale: Locale) -> AnyView {
        AnyView(content.environment(\.locale, locale))
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(ignoringType: ignoringType, menu: menu)
    }
    
    class Coordinator: NSObject, UIGestureRecognizerDelegate, UIContextMenuInteractionDelegate {
        let ignoringType: UITouch.TouchType
        let menu: () -> UIMenu
        var isIgnoreMenu: Bool = false
        /// 행 내용을 담은 호스트. 붙잡아 두어야 갱신 때 `rootView` 를 바꿀 수 있다.
        var hosting: UIHostingController<AnyView>?
        /// 호스트에 마지막으로 넣은 화면 언어.
        var hostedLocale: Locale?

        init(ignoringType: UITouch.TouchType, menu: @escaping () -> UIMenu) {
            self.ignoringType = ignoringType
            self.menu = menu
        }
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            self.isIgnoreMenu = (touch.type == ignoringType)
            return touch.type != ignoringType
        }
        
        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard let view = gesture.view, gesture.state == .began, !isIgnoreMenu else { return }
            let interaction = UIContextMenuInteraction(delegate: self)
            view.addInteraction(interaction)
            interaction.updateVisibleMenu { _ in self.menu() }
        }
        
        func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
            if self.isIgnoreMenu { return nil }
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in self.menu() }
        }
    }
}


struct TouchIgnoringContextMenuModifier: ViewModifier {
    let ignoringType: UITouch.TouchType
    let menu: () -> UIMenu

    func body(content: Content) -> some View {
        TouchIgnoringContextMenu(ignoringType: ignoringType, content: { content }, menu: menu)
    }
}
