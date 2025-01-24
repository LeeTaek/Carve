//
//  SendFeedbackView.swift
//  FeatureSettings
//
//  Created by 이택성 on 7/24/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Core
import Domain
import SwiftUI
import PhotosUI

import ComposableArchitecture

public struct SendFeedbackView: View {
    @Bindable private var store: StoreOf<SendFeedbackReducer>
    @State private var shakeTrigger: Bool = false

    public init(store: StoreOf<SendFeedbackReducer>) {
        self.store = store
    }
    
    public var body: some View {
        List {
            Text("메일 앱을 통해 개발자에게 버그 수정, 기능 개성 요청 등등 의견을 보냅니다.\n회신이 필요한 경우 사용하신 메일 주소로 회신합니다.\n메일 앱 설정이 되어있지 않은 경우 앱스토어 의견에 남겨주세요.\n감사합니다😊")
                .font(.system(size: 18, weight: .medium))
                .lineSpacing(8)
                .foregroundStyle(.black.opacity(0.7))
                .listRowInsets(.init())
                .padding()
            
            Section(
                header: HStack {
                        Text("*")
                            .font(.system(size: 20))
                            .foregroundStyle(.red)
                        Text("문의 분류")
                    }
            ) {
                feedbackTypeView
            }
            .listRowInsets(.init())
            .listRowBackground(Color.clear)
                        
            Section(
                
                header: HStack {
                    Text("*")
                        .font(.system(size: 20))
                        .foregroundStyle(.red)
                    Text("문의 제목")
                }
            ) {
                titleView
            }
            .listRowInsets(.init())
            .listRowBackground(Color.clear)
            
            Section(
                header: HStack {
                    Text("*")
                        .font(.system(size: 20))
                        .foregroundStyle(.red)
                    Text("문의 내용")
                },
                footer: HStack {
                    Spacer()
                    Text("\(store.feedbackInfo.body.count)/3000")
                }
            ) {
                inquryDetailsView
            }
            .listRowInsets(.init())
            .listRowBackground(Color.clear)
            
            Section(
                header: Text("첨부 사진"),
                footer:
                    HStack {
                        Text("첨부 사진은 5개까지 등록 가능합니다.")
                        Spacer()
                        Text("\(store.feedbackInfo.attachment.count)/5")
                    }
            ) {
                attachmentView
                if !store.feedbackInfo.attachment.isEmpty {
                    selectedImageList
                }
            }
            .listRowInsets(.init())
            
            noticeView
                .listRowInsets(.init())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            
            if !store.popupMessage.isEmpty {
                errorMessage
                    .listRowInsets(.init())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .shakeAnimation(trigger: $shakeTrigger)
                    .onAppear {
                        triggerShankeAnimation()
                    }
            }
            
            sendFeedbackButton
                .listRowInsets(.init())
                .listRowSeparator(.hidden)
        }
        .navigationTitle("의견 보내기")
    }
    
    private var feedbackTypeView: some View {
        Menu {
            Picker(store.feedbackInfo.feedbackType.rawValue, selection: $store.feedbackInfo.feedbackType.sending(\.setFeedbackType)) {
                ForEach(UserFeedback.FeedbackType.allCases, id: \.self) { type in
                    Text(type.rawValue)
                        .padding()
                }
            }
        } label: {
            HStack {
                Text(store.feedbackInfo.feedbackType.rawValue)
                    .foregroundStyle(.black)
                Spacer()
                Image(systemName: "chevron.down")
                    .foregroundStyle(.black)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
    
    private var titleView: some View {
        HStack {
            TextField("제목을 입력하세요 (20자 이내)", text: $store.feedbackInfo.title.sending(\.setTitle))
                .onChange(of: store.feedbackInfo.title) { _, newValue in
                    if store.feedbackInfo.title.count > 20 {
                        store.send(.setTitle(String(newValue.prefix(20))))
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    HStack {
                        Spacer()
                        Text("\(store.feedbackInfo.title.count)/20")
                            .foregroundStyle(.gray)
                            .padding()
                    }
                }
        }
    }
    
    private var inquryDetailsView: some View {
        TextEditor(text: $store.feedbackInfo.body.sending(\.setBody))
            .onChange(of: store.feedbackInfo.body) { _, newValue in
                if store.feedbackInfo.body.count > 3000 {
                    store.send(.setBody(String(newValue.prefix(3000))))
                }
             }
            .frame(height: 200)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    
    private var attachmentView: some View {
        Menu {
            ForEach(SendFeedbackReducer.AttachmentType.allCases, id: \.self) { type in
                Button {
                    store.send(.setAttachment(type))
                } label: {
                    Text(type.rawValue)
                        .padding()
                    Image(systemName: type.image)
                }
            }

        } label: {
            HStack {
                Text("+ 사진 첨부")
                    .foregroundStyle(.black)
                Spacer()
                Image(systemName: "paperclip")
                    .foregroundStyle(.black)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .photosPicker(
            isPresented:  $store.isOnPhotosPicker.sending(\.presentPhotoPicker),
            selection: $store.imageSelection.sending(\.setPhotosImage),
            maxSelectionCount: 5,
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
                store.send(.setFileData(fileUrls))
            case .failure(let error):
                Log.debug("fileImporter error:", error.localizedDescription)
            }
        }
    }
    
    private var selectedImageList: some View {
        LazyHStack {
            ForEach(Array(store.feedbackInfo.attachment.enumerated()), id: \.offset) { index, imageData in
                if store.feedbackInfo.attachment.count > index,
                   let image = UIImage(data: imageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding()
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: "x.circle.fill")
                                .resizable()
                                .frame(width: 25, height: 25)
                                .foregroundStyle(.white)
                                .background(Color.black.opacity(0.7))
                                .clipShape(.circle)
                                .onTapGesture {
                                    store.send(.removePhoto(index))
                                }
                        }
                }
            }
        }
        .padding()
    }
    
    private var noticeView: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("*")
                    .font(.system(size: 20))
                    .foregroundStyle(.red)
                Image(systemName: store.agreeToDefaultNotice ? "v.circle.fill" : "v.circle")
                    .resizable()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(store.agreeToDefaultNotice ? Color.green.opacity(0.6) : Color.gray)
                Text("(필수)작성하신 의견을 앱 개발자에게 보냅니다.")
                    .foregroundStyle(Color.gray)
            }
            .onTapGesture {
                store.send(.toggleDefaultAgreement)
            }
            
            HStack {
                Text("*")
                    .font(.system(size: 20))
                    .foregroundStyle(.red)
                Image(systemName: store.agreeToGetDeviceInfo ? "v.circle.fill" : "v.circle")
                    .resizable()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(store.agreeToGetDeviceInfo ? Color.green.opacity(0.6) : Color.gray)
                Text("(필수)기종 정보와 OS에 대한 정보도 함께 전달합니다. 해당 정보는 피드백 확인 후 바로 파기됩니다.")
                    .foregroundStyle(Color.gray)
            }
            .onTapGesture {
                store.send(.togglePrivacyAgreement)
            }
        }
        .frame(height: 100)
        .padding(.vertical)
    }
    
    private var sendFeedbackButton: some View {
        Button {
            store.send(.isEnableSendButton)
            triggerShankeAnimation()
        } label: {
            Text("의견 보내기")
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
        }
        .sheet(item: $store.scope(state: \.path?.email,
                                  action: \.path.email)) { store in
            MailComposeView(store: store)
        }
    }
    
    private var errorMessage: some View {
        Text(store.popupMessage)
            .fontWeight(.medium)
            .foregroundStyle(.red)
    }
    
    private func triggerShankeAnimation() {
        withAnimation(
            Animation.linear(duration: 0.25)
                .repeatCount(2, autoreverses: false)
        ) {
            shakeTrigger.toggle()
            
        }
    }
    
    private func icon(type: SendFeedbackReducer.AttachmentType) -> String {
        switch type {
        case .photo: return "photo"
        case .file: return "folder"
        }
    }
    
}
 
