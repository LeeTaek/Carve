//
//  SendFeedbackReducer.swift
//  FeatureSettings
//
//  Created by 이택성 on 7/24/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Core
import Domain
import SwiftUI
import PhotosUI
import MessageUI

import ComposableArchitecture

@Reducer
public struct SendFeedbackReducer {
    public init() { }
    
    @ObservableState
    public struct State: Hashable {
        public static let initialState = Self()
        @Presents public var path: Path.State?
        public var feedbackInfo: FeedbackVO = .initialState
        public var imageSelection: [PhotosPickerItem] = []
        public var isOnPhotosPicker: Bool = false
        public var isOnFileImporter: Bool = false
    }
    public enum Action {
        case path(PresentationAction<Path.Action>)
        case setFeedbackType(FeedbackVO.FeedbackType)
        case setTitle(String)
        case setBody(String)
        case setAttachment(AttachmentType?)
        case presentPhotoPicker(Bool)
        case preesentFileImporter(Bool)
        case setPhotosImage([PhotosPickerItem])
        case setEncodedData([Data])
        case setFileData([URL])
        case removePhoto(Int)
        case togglePrivacyAgreement
        case sendFeedback
    }
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .setFeedbackType(let type):
                state.feedbackInfo.feedbackType = type
            case .setTitle(let title):
                state.feedbackInfo.title = title
            case .setBody(let body):
                state.feedbackInfo.body = body
            case .setAttachment(let type):
                switch type {
                case .photo:
                    state.isOnPhotosPicker = true
                case .file:
                    state.isOnFileImporter = true
                case .none:
                    break
                }
            case .presentPhotoPicker(let isPresent):
                state.isOnPhotosPicker = isPresent
            case .preesentFileImporter(let isPresent):
                state.isOnFileImporter = isPresent
            case .setPhotosImage(let selection):
                state.imageSelection = selection
                return .run { send in
                    var items: [Data] = []
                    for item in selection {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            items.append(data)
                        }
                    }
                    await send(.setEncodedData(items))
                }
            case .setEncodedData(let data):
                withAnimation(.easeInOut(duration: 0.8)) {
                    state.feedbackInfo.attachment = data
                }
            case .setFileData(let urls):
                return .run { send in
                    var imageDatas: [Data] = []
                    for url in Array(urls.prefix(5)) {
                        guard url.startAccessingSecurityScopedResource(),
                              let imageData = try? Data(contentsOf: url)
                        else { continue }
                        imageDatas.append(imageData)
                    }
                    await send(.setEncodedData(imageDatas))
                }
                
            case .removePhoto(let index):
                guard state.feedbackInfo.attachment.count > index else { return .none }
                withAnimation(.easeInOut(duration: 0.1)) {
                    state.feedbackInfo.attachment.remove(at: index)
                }
                guard state.imageSelection.count > index else { return .none }
                state.imageSelection.remove(at: index)
                
            case .togglePrivacyAgreement:
                state.feedbackInfo.agreeToGetDeviceInfo.toggle()
            case .sendFeedback:
                if MFMailComposeViewController.canSendMail() {
                    state.path = .email(.init(mailInfo: state.feedbackInfo))
                } else {
                    Log.debug("이메일을 보낼 수 없음")
                }
            default: break
            }
            return .none
        }
        .ifLet(\.$path, action: \.path)
    }
}

extension SendFeedbackReducer {
    public enum AttachmentType: String, CaseIterable {
        case photo = "사진 보관함"
        case file = "파일 선택"
        var image: String {
            switch self {
            case .photo: return "photo"
            case .file: return "folder"
            }
        }
    }
    
    @Reducer(state: .hashable)
    public enum Path {
        case email(MailComposeReducer)
    }
}

