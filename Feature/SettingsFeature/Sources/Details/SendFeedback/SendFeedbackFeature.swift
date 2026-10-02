//
//  SendFeedbackFeature.swift
//  FeatureSettings
//
//  Created by 이택성 on 7/24/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import CarveToolkit
import Domain
import SwiftUI
import PhotosUI
import MessageUI

import ComposableArchitecture

/// 의존성만 가지므로 `Sendable` 이다 — `MainActor.assumeIsolated` 안에서 `mailAvailability` 를 그대로 쓴다.
@Reducer
public struct SendFeedbackFeature: Sendable {
    public init() { }

    @ObservableState
    public struct State: Hashable, Sendable {
        public static let initialState = Self()
        @Presents public var path: Path.State?
        public var feedbackInfo: UserFeedback = .initialState
        public var imageSelection: [PhotosPickerItem] = []
        public var isOnPhotosPicker: Bool = false
        public var isOnFileImporter: Bool = false
        public var agreeToDefaultNotice: Bool = false
        public var agreeToGetDeviceInfo: Bool = false
        /// 이 iPad 가 메일을 보낼 수 있는가(메일 앱에 계정이 설정돼 있는가). 화면이 뜰 때 보고, 보내기 직전에 다시 본다. 모르는 동안은 nil.
        public var canSendMail: Bool?

        /// 아직 채우지 않은 필수 항목 중 첫째 — 제목 · 내용 · 필수 동의 차례로 본다. 모두 채웠으면 nil.
        /// 공백만 적은 것은 채운 것으로 보지 않는다. 내용은 기본 머리(「- 문의 내용:」) 뒤에 적은 것만 센다.
        public var missingRequirement: Requirement? {
            if feedbackInfo.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .title }
            let template = UserFeedback.initialState.body
            let body = feedbackInfo.body
            let written = body.hasPrefix(template) ? body.dropFirst(template.count) : Substring(body)
            if written.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .body }
            if !agreeToDefaultNotice || !agreeToGetDeviceInfo { return .agreements }
            return nil
        }

        /// 필수 항목을 모두 채웠는가 — 보내기 버튼은 이때만 켜진다.
        public var isFormComplete: Bool { missingRequirement == nil }
    }
    public enum Action: ViewAction {
        case path(PresentationAction<Path.Action>)
        case setFeedbackType(UserFeedback.FeedbackType)
        case presentPhotoPicker(Bool)
        case preesentFileImporter(Bool)
        case setPhotosImage([PhotosPickerItem])
        case setEncodedData([Data])
        case sendFeedback
        
        case view(View)
        
        @CasePathable
        public enum View {
            /// 화면이 떴다 — 메일을 보낼 수 있는지 본다.
            case onAppear
            case setTitle(String)
            case setBody(String)
            case setAttachment(AttachmentType?)
            case setFileData([URL])
            case toggleDefaultAgreement
            case togglePrivacyAgreement
            case removePhoto(Int)
            case isEnableSendButton
        }
    }
    
    @Dependency(\.mailComposeAvailability) private var mailAvailability

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .view(.onAppear):
                state.canSendMail = MainActor.assumeIsolated { mailAvailability.canSendMail() }
            case .setFeedbackType(let type):
                state.feedbackInfo.feedbackType = type
            case .view(.setTitle(let title)):
                state.feedbackInfo.title = title
            case .view(.setBody(let body)):
                state.feedbackInfo.body = body
            case .view(.setAttachment(let type)):
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
            case .view(.setFileData(let urls)):
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
                
            case .view(.removePhoto(let index)):
                guard state.feedbackInfo.attachment.count > index else { return .none }
                state.feedbackInfo.attachment.remove(at: index)
                guard state.imageSelection.count > index else { return .none }
                state.imageSelection.remove(at: index)
            case .view(.toggleDefaultAgreement):
                state.agreeToDefaultNotice.toggle()
            case .view(.togglePrivacyAgreement):
                state.agreeToGetDeviceInfo.toggle()
            case .sendFeedback:
                // 보내기 직전에 다시 본다 — 화면을 연 뒤 설정 앱에서 메일 계정을 추가했을 수 있다.
                let canSendMail = MainActor.assumeIsolated { mailAvailability.canSendMail() }
                state.canSendMail = canSendMail
                if canSendMail {
                    state.path = .email(.init(mailInfo: state.feedbackInfo))
                } else {
                    // 조용히 넘어가지 않는다 — 누른 사람은 보내졌는지 모른다. 왜 못 보내는지와 대안을 알린다.
                    Log.debug("이메일을 보낼 수 없음 — 메일 계정이 없다")
                    state.path = .popup(Self.mailUnavailablePopup)
                }
            case .path(.presented(.popup(.view(.confirm)))), .path(.presented(.popup(.view(.cancel)))):
                state.path = nil
            case .view(.isEnableSendButton):
                // 버튼은 필수 항목을 모두 채워야 켜진다 — 그 전에 들어온 누름은 보내지 않는다.
                guard state.isFormComplete else { return .none }
                return .run { send in
                    await send(.sendFeedback)
                }
            default: break
            }
            return .none
        }
        .ifLet(\.$path, action: \.path)
    }
}

extension SendFeedbackFeature {
    /// 메일 계정이 없어 보낼 수 없을 때의 안내(설정의 알림 대화상자, 시안 F2).
    static let mailUnavailablePopup = PopupFeature.State(
        title: "메일을 보낼 수 없어요",
        body: "이 iPad에 메일 계정이 설정돼 있지 않아요.",
        hint: "설정 앱의 메일에서 계정을 추가한 뒤 다시 보내 주세요. App Store 리뷰로 의견을 남겨 주셔도 돼요.",
        confirmTitle: "확인"
    )

    /// 보내기 전에 채워야 하는 항목.
    public enum Requirement: Hashable, Sendable {
        case title
        case body
        case agreements

        /// 보내기 버튼 아래 안내 — 버튼이 왜 꺼져 있는지와 무엇을 채울지 알린다.
        public var hint: String {
            switch self {
            case .title: "보내려면 제목을 적어 주세요."
            case .body: "보내려면 내용을 적어 주세요."
            case .agreements: "보내려면 필수 항목에 모두 동의해 주세요."
            }
        }
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
    
    @Reducer
    public enum Path {
        case email(MailComposeFeature)
        /// 메일을 보낼 수 없다는 안내.
        case popup(PopupFeature)
    }
}

/// 이 기기가 메일을 보낼 수 있는가 — 메일 앱에 계정이 설정돼 있어야 한다. 시험이 바꿔 끼울 수 있게 경계로 나눈다.
/// `MFMailComposeViewController` 가 메인 액터에 묶여 있어 메인 액터에서만 부른다(리듀서는 스토어가 메인 액터에서 돌린다).
public struct MailComposeAvailabilityClient: Sendable {
    public var canSendMail: @MainActor @Sendable () -> Bool

    public init(canSendMail: @escaping @MainActor @Sendable () -> Bool) {
        self.canSendMail = canSendMail
    }
}

extension MailComposeAvailabilityClient: DependencyKey {
    public static let liveValue = Self(canSendMail: { MFMailComposeViewController.canSendMail() })
    public static let testValue = Self(canSendMail: { true })
    public static let previewValue = Self(canSendMail: { true })
}

public extension DependencyValues {
    /// 메일을 보낼 수 있는가.
    var mailComposeAvailability: MailComposeAvailabilityClient {
        get { self[MailComposeAvailabilityClient.self] }
        set { self[MailComposeAvailabilityClient.self] = newValue }
    }
}

extension SendFeedbackFeature.Path.State: Hashable {}
extension SendFeedbackFeature.Path.State: Sendable {}
