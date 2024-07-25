//
//  MailComposeView.swift
//  FeatureSettings
//
//  Created by 이택성 on 7/25/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import UIKit
import SwiftUI
import MessageUI

import ComposableArchitecture

public struct MailComposeView: UIViewControllerRepresentable {
    private let store: StoreOf<MailComposeReducer>
    
    public init(store: StoreOf<MailComposeReducer>) {
        self.store = store
    }
    
    public func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let viewController = MFMailComposeViewController()
        viewController.mailComposeDelegate = context.coordinator
        viewController.setToRecipients([store.mailInfo.feedbackAddress])
        viewController.setSubject(store.mailInfo.title)
        viewController.setMessageBody(store.mailInfo.body, isHTML: false)
        guard let datas = store.mailInfo.attachment else { return viewController }
        for (index, imageData) in datas.enumerated() {
            viewController.addAttachmentData(imageData, mimeType: "image/jpeg", fileName: "attacnmentImage_\(index).jpg")
        }
        return viewController
    }
    
    public func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }
    
    public class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let store: StoreOf<MailComposeReducer>
        public init(store: StoreOf<MailComposeReducer>) {
            self.store = store
        }
        
        public func mailComposeController(_ controller: MFMailComposeViewController,
                                          didFinishWith result: MFMailComposeResult,
                                          error: (any Error)?) {
            defer {
                store.send(.dismiss)
            }
        }
    }
    
    
}
