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
    private let store: StoreOf<MailComposeFeature>
    
    public init(store: StoreOf<MailComposeFeature>) {
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
        AppVersion: \(UIDevice.appVersion())
        
        -----------------------------------------------------
        """
        return store.mailInfo.body + deviceInfo
    }
    
    /// 메일 작성 화면의 delegate — 메인 액터에서만 쓴다. MessageUI 의 delegate 프로토콜은 격리 표기가 없지만 메인 스레드에서 불리므로
    /// `@preconcurrency` 로 잇는다(어긋나면 실행 중 격리 검사가 잡는다).
    @MainActor
    public class Coordinator: NSObject, @preconcurrency MFMailComposeViewControllerDelegate {
        let store: StoreOf<MailComposeFeature>
        public init(store: StoreOf<MailComposeFeature>) {
            self.store = store
        }
        
        public func mailComposeController(_ controller: MFMailComposeViewController,
                                          didFinishWith result: MFMailComposeResult,
                                          error: (any Error)?) {
            store.send(.dismiss)
        }
    }
    
}
