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
        public var feedbackType: FeedbackType = .inquiry
        public var emailAddress: String = ""
        public var emailDomainType: EmailDomainType = .custom
        public var emailDomain: String = ""
        public var domainDisabled: Bool = false
        public var title: String = ""
        public var description: String = "- 문의 내용:"
        public var imageSelection: [PhotosPickerItem] = []
        public var selectionImageData: [Data] = []
        public var isOnPhotosPicker: Bool = false
        public var isOnFileImporter: Bool = false
        public var privacyAgreement: Bool = false
        public var presentPrivacyDescription: Bool = false
        @Presents public var path: Path.State?
    }
    public enum Action {
        case setFeedbackType(FeedbackType)
        case setEmail(String)
        case setDomain(String)
        case setDomainType(EmailDomainType)
        case setTitle(String)
        case setDescription(String)
        case setAttachment(AttachmentType?)
        case presentPhotoPicker(Bool)
        case preesentFileImporter(Bool)
        case setPhotosImage([PhotosPickerItem])
        case setEncodedData([Data])
        case setFileData([URL])
        case removePhoto(Int)
        case togglePrivacyAgreement
        case togglePrivacyDescription
        case sendFeedback
        case path(PresentationAction<Path.Action>)
    }
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .setFeedbackType(let type):
                state.feedbackType = type
            case .setEmail(let email):
                state.emailAddress = email
            case .setDomain(let domain):
                if state.emailDomainType == .custom {
                    state.emailDomain = domain
                }
            case .setDomainType(let domainType):
                state.emailDomainType = domainType
                if domainType != .custom {
                    state.emailDomain = domainType.rawValue
                    state.domainDisabled = true
                } else {
                    state.emailDomain = ""
                    state.domainDisabled = false
                }
            case .setTitle(let title):
                state.title = title
            case .setDescription(let description):
                state.description = description
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
                    state.selectionImageData = data
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
                guard state.selectionImageData.count > index else { return .none }
                withAnimation(.easeInOut(duration: 0.1)) {
                    state.selectionImageData.remove(at: index)
                }
                guard state.imageSelection.count > index else { return .none }
                state.imageSelection.remove(at: index)
                
            case .togglePrivacyAgreement:
                state.privacyAgreement.toggle()
            case .togglePrivacyDescription:
                state.presentPrivacyDescription.toggle()
                
            case .sendFeedback:
                if MFMailComposeViewController.canSendMail() {
                    state.path = .email(.initialState)
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
    public enum FeedbackType: String, CaseIterable {
        case inquiry = "일반 문의"
        case proposal =  "개선 및 제안"
        case etc = "기타"
    }
    
    public enum EmailDomainType: String, CaseIterable {
        case custom = "직접 입력"
        case naver = "naver.com"
        case google = "gmail.com"
        case daum = "daum.net"
        case kakao = "kakao.com"
    }

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

