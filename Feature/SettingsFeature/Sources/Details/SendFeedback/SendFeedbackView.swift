//
//  SendFeedbackView.swift
//  FeatureSettings
//
//  Created by 이택성 on 7/24/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import CarveToolkit
import Domain
import SwiftUI
import PhotosUI

import ComposableArchitecture
import UIComponents

/// 설정 → 의견 보내기. 다른 설정 화면과 같은 틀(제목 한 줄 · 설정 묶음 · 구분선 · Carve 색 · 글꼴 · 버튼)로 둔다.
@ViewAction(for: SendFeedbackFeature.self)
public struct SendFeedbackView: View {
    @Bindable public var store: StoreOf<SendFeedbackFeature>

    private static let titleLimit = 20
    private static let bodyLimit = 3000
    private static let attachmentLimit = 5

    public init(store: StoreOf<SendFeedbackFeature>) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CarveSpacing.large) {
                header

                if store.canSendMail == false {
                    mailUnavailableNotice
                }

                CarveSettingsSection("문의 분류") {
                    feedbackTypeRow
                }

                CarveSettingsSection("제목") {
                    titleField
                }

                CarveSettingsSection("내용") {
                    bodyField
                }

                CarveSettingsSection("첨부 사진 · 선택") {
                    attachmentSection
                }

                CarveDivider()

                CarveSettingsSection("보내기 전에 확인해 주세요") {
                    agreements
                }

                sendFeedbackButton
            }
            .padding(CarveSpacing.large)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(CarveColor.surface)
        .scrollDismissesKeyboard(.interactively)
        .onAppear { send(.onAppear) }
        .sheet(item: $store.scope(state: \.path?.email, action: \.path.email)) { store in
            MailComposeView(store: store)
        }
        // 메일을 보낼 수 없다는 안내 — iCloud 전체 삭제 확인과 같은 설정 대화상자(시안 F2)로 띄운다.
        .settingsPopup($store.scope(state: \.path?.popup, action: \.path.popup))
    }

    /// 이 iPad 에 메일 계정이 없다 — 다 적은 뒤에야 알지 않도록 먼저 말한다. 보내기를 누르면 같은 안내를 대화상자로 띄운다.
    private var mailUnavailableNotice: some View {
        HStack(alignment: .top, spacing: CarveSpacing.xSmall) {
            Image(systemName: "envelope.badge")
                .foregroundStyle(CarveColor.accent)
                .accessibilityHidden(true)
            Text("이 iPad에 메일 계정이 설정돼 있지 않아 지금은 보낼 수 없어요. 설정 앱의 메일에서 계정을 추가하거나 App Store 리뷰로 남겨 주세요.")
                .font(CarveTypography.body)
                .foregroundStyle(CarveColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(CarveSpacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CarveColor.selected, in: fieldShape)
        .accessibilityElement(children: .combine)
    }

    // MARK: - 머리말

    private var header: some View {
        VStack(alignment: .leading, spacing: CarveSpacing.xxSmall) {
            Text("의견 보내기")
                .font(CarveTypography.sectionTitle)
                .foregroundStyle(CarveColor.secondary)
            Text("메일 앱으로 개발자에게 버그 제보나 기능 개선 의견을 보낼 수 있어요. 회신이 필요하면 보내신 메일 주소로 답장해요.")
                .font(CarveTypography.body)
                .foregroundStyle(CarveColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - 입력

    /// 분류 — 제목 · 내용 칸과 같은 모양의 선택 칸. 고른 값은 강조색으로 적는다.
    private var feedbackTypeRow: some View {
        Menu {
            Picker(
                "문의 분류",
                selection: $store.feedbackInfo.feedbackType.sending(\.setFeedbackType)
            ) {
                ForEach(UserFeedback.FeedbackType.allCases, id: \.self) { type in
                    Text(type.rawValue)
                }
            }
        } label: {
            HStack(spacing: CarveSpacing.small) {
                Text(store.feedbackInfo.feedbackType.rawValue)
                    .font(CarveTypography.body)
                    .foregroundStyle(CarveColor.ink)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(CarveTypography.caption)
                    .foregroundStyle(CarveColor.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, CarveSpacing.small)
            .frame(maxWidth: .infinity, minHeight: CarveSize.minimumHitTarget)
            .background(CarveColor.fill, in: fieldShape)
            .contentShape(fieldShape)
        }
        .accessibilityLabel("문의 분류")
        .accessibilityValue(store.feedbackInfo.feedbackType.rawValue)
    }

    private var titleField: some View {
        VStack(alignment: .trailing, spacing: CarveSpacing.xxSmall) {
            TextField("제목을 적어 주세요", text: $store.feedbackInfo.title.sending(\.view.setTitle))
                .font(CarveTypography.body)
                .foregroundStyle(CarveColor.ink)
                .onChange(of: store.feedbackInfo.title) { _, newValue in
                    if newValue.count > Self.titleLimit {
                        send(.setTitle(String(newValue.prefix(Self.titleLimit))))
                    }
                }
                .padding(.horizontal, CarveSpacing.small)
                .frame(minHeight: CarveSize.minimumHitTarget)
                .background(CarveColor.fill, in: fieldShape)
            counter(store.feedbackInfo.title.count, limit: Self.titleLimit)
        }
    }

    private var bodyField: some View {
        VStack(alignment: .trailing, spacing: CarveSpacing.xxSmall) {
            TextEditor(text: $store.feedbackInfo.body.sending(\.view.setBody))
                .font(CarveTypography.body)
                .foregroundStyle(CarveColor.ink)
                .scrollContentBackground(.hidden)
                .onChange(of: store.feedbackInfo.body) { _, newValue in
                    if newValue.count > Self.bodyLimit {
                        send(.setBody(String(newValue.prefix(Self.bodyLimit))))
                    }
                }
                .padding(CarveSpacing.xSmall)
                .frame(height: 200)
                .background(CarveColor.fill, in: fieldShape)
                .accessibilityLabel("문의 내용")
            counter(store.feedbackInfo.body.count, limit: Self.bodyLimit)
        }
    }

    // MARK: - 첨부

    private var attachmentSection: some View {
        VStack(alignment: .leading, spacing: CarveSpacing.small) {
            HStack(spacing: CarveSpacing.small) {
                attachmentMenu
                Spacer(minLength: 0)
                counter(store.feedbackInfo.attachment.count, limit: Self.attachmentLimit)
            }
            if !store.feedbackInfo.attachment.isEmpty {
                selectedImageList
            }
            Text("사진은 \(Self.attachmentLimit)장까지 붙일 수 있어요.")
                .font(CarveTypography.caption)
                .foregroundStyle(CarveColor.secondary)
        }
    }

    private var attachmentMenu: some View {
        Menu {
            ForEach(SendFeedbackFeature.AttachmentType.allCases, id: \.self) { type in
                Button {
                    send(.setAttachment(type))
                } label: {
                    Label(type.rawValue, systemImage: type.image)
                }
            }
        } label: {
            Label("사진 첨부", systemImage: "paperclip")
                .font(CarveTypography.body)
                .foregroundStyle(CarveColor.ink)
                .padding(.horizontal, CarveSpacing.medium)
                .frame(minHeight: CarveSize.minimumHitTarget)
                .background(CarveColor.fill, in: fieldShape)
                .contentShape(fieldShape)
        }
        .photosPicker(
            isPresented: $store.isOnPhotosPicker.sending(\.presentPhotoPicker),
            selection: $store.imageSelection.sending(\.setPhotosImage),
            maxSelectionCount: Self.attachmentLimit,
            matching: .images,
            photoLibrary: .shared()
        )
        .fileImporter(
            isPresented: $store.isOnFileImporter.sending(\.preesentFileImporter),
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let fileUrls):
                send(.setFileData(fileUrls))
            case .failure(let error):
                Log.debug("fileImporter error:", error.localizedDescription)
            }
        }
    }

    private var selectedImageList: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: CarveSpacing.small) {
                ForEach(Array(store.feedbackInfo.attachment.enumerated()), id: \.offset) { index, imageData in
                    if let image = UIImage(data: imageData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 96, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: CarveRadius.inner, style: .continuous))
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    send(.removePhoto(index))
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title3)
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(CarveColor.surface, CarveColor.ink.opacity(0.75))
                                        .frame(width: CarveSize.minimumHitTarget, height: CarveSize.minimumHitTarget)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(index + 1)번째 사진 빼기")
                            }
                    }
                }
            }
        }
    }

    // MARK: - 동의 · 보내기

    /// 필수 동의 둘 — 체크박스로 고른다. 줄 어디를 눌러도 바뀐다.
    private var agreements: some View {
        VStack(alignment: .leading, spacing: CarveSpacing.xxSmall) {
            AgreementCheckbox(
                title: "작성한 의견을 개발자에게 보내요",
                detail: "필수",
                isChecked: store.agreeToDefaultNotice
            ) {
                send(.toggleDefaultAgreement)
            }
            AgreementCheckbox(
                title: "기종과 OS 정보를 함께 보내요",
                detail: "필수 · 의견을 확인한 뒤 바로 지워요.",
                isChecked: store.agreeToGetDeviceInfo
            ) {
                send(.togglePrivacyAgreement)
            }
        }
    }

    /// 보내기 — 이 화면의 주 동작이라 강조색으로 채운다. 필수 항목(제목 · 내용 · 동의 둘)을 모두 채울 때까지 흐리게 막고,
    /// 아래에 무엇이 남았는지 적는다. 메일 계정이 없으면 누를 때 안내를 띄운다.
    private var sendFeedbackButton: some View {
        VStack(alignment: .leading, spacing: CarveSpacing.xSmall) {
            Button("의견 보내기") {
                send(.isEnableSendButton)
            }
            .buttonStyle(SubmitButtonStyle())
            .disabled(!store.isFormComplete)
            .accessibilityHint(store.missingRequirement?.hint ?? "")
            .accessibilityIdentifier("sendFeedback.send")

            if let missing = store.missingRequirement {
                Text(missing.hint)
                    .font(CarveTypography.caption)
                    .foregroundStyle(CarveColor.secondary)
                    // 버튼의 접근성 힌트로 이미 읽는다.
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: - 조각

    private var fieldShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: CarveRadius.control, style: .continuous)
    }

    private func counter(_ count: Int, limit: Int) -> some View {
        Text("\(count)/\(limit)")
            .font(CarveTypography.caption)
            .foregroundStyle(CarveColor.secondary)
            .monospacedDigit()
    }
}

/// 필수 동의 한 줄 — 체크박스와 제목 · 설명. VoiceOver 는 한 요소로 읽고 선택 여부를 값으로 말한다.
private struct AgreementCheckbox: View {
    let title: String
    let detail: String
    let isChecked: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .top, spacing: CarveSpacing.small) {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(isChecked ? CarveColor.accent : CarveColor.secondary)
                    .frame(width: CarveSize.iconGlyph, height: CarveSize.iconGlyph)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(CarveTypography.body)
                        .foregroundStyle(CarveColor.ink)
                    Text(detail)
                        .font(CarveTypography.caption)
                        .foregroundStyle(CarveColor.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, CarveSpacing.xxSmall)
            .frame(minHeight: CarveSize.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isChecked ? "선택됨" : "선택 안 됨")
        .accessibilityAddTraits(isChecked ? .isSelected : [])
    }
}

/// 이 화면의 주 동작 버튼 — 강조색으로 채운다. 설정 대화상자의 위험 확인 버튼(위험색 바탕 · 바탕색 글자)과 같은 짜임이다.
/// 꺼진 상태는 `.disabled(_:)` 로 주고, Carve 글자 버튼(`CarveButtonStyle`)과 같이 불투명도 0.4 로 흐리게 그린다.
private struct SubmitButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(CarveTypography.body.weight(.semibold))
            .foregroundStyle(CarveColor.canvas)
            .frame(maxWidth: .infinity, minHeight: CarveSize.minimumHitTarget + 4)
            .background(CarveColor.accent, in: RoundedRectangle(cornerRadius: CarveRadius.control, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: CarveRadius.control, style: .continuous))
            .opacity(opacity(isPressed: configuration.isPressed))
    }

    private func opacity(isPressed: Bool) -> Double {
        if !isEnabled { return 0.4 }
        return isPressed ? 0.6 : 1
    }
}

#Preview {
    @Previewable @State var store = Store(initialState: .initialState) {
        SendFeedbackFeature()
    }
    SendFeedbackView(store: store)
}
