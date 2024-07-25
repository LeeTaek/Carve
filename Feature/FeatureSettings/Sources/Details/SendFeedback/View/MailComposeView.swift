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
        let title = "[\(store.mailInfo.feedbackType.rawValue)] \(store.mailInfo.title)"
        viewController.setSubject(title)
        viewController.setMessageBody(body(), isHTML: false)
        for (index, imageData) in store.mailInfo.attachment.enumerated() {
            viewController.addAttachmentData(imageData, mimeType: "image/jpeg", fileName: "attacnmentImage_\(index).jpg")
        }
        return viewController
    }
    
    public func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }
    
    private func body() -> String {
        let deviceInfo = """
        
        
        -----------------------------------------------------
        
        Device Model: \(UIDevice.modelName)
        Device OS: \(UIDevice.current.systemVersion)
        AppVersion: \(currentAppVersion())
        
        -----------------------------------------------------
        """
        return store.mailInfo.body + deviceInfo
    }
    
    
    private func currentAppVersion() -> String {
      if let info: [String: Any] = Bundle.main.infoDictionary,
          let currentVersion: String
            = info["CFBundleShortVersionString"] as? String {
            return currentVersion
      }
      return "nil"
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
