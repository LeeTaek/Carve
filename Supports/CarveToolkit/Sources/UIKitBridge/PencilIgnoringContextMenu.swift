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
        let hosting = UIHostingController(rootView: content())
        let view = hosting.view!

        let longPress = UILongPressGestureRecognizer(target: context.coordinator,
                                                     action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.5
        longPress.delegate = context.coordinator
        view.addGestureRecognizer(longPress)
        
        return view
    }
    
    func updateUIView(_ uiView: UIViewType, context: Context) {
        if let hostingController = uiView.subviews
            .compactMap({ $0.next as? UIHostingController<Content> })
            .first {
            hostingController.rootView = content()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(ignoringType: ignoringType, menu: menu)
    }
    
    class Coordinator: NSObject, UIGestureRecognizerDelegate, UIContextMenuInteractionDelegate {
        let ignoringType: UITouch.TouchType
        let menu: () -> UIMenu
        var isIgnoreMenu: Bool = false

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
