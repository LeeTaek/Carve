//
//  SendFeedbackView.swift
//  FeatureSettings
//
//  Created by 이택성 on 7/24/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Core
import SwiftUI
import PhotosUI

import ComposableArchitecture

public struct SendFeedbackView: View {
    @Bindable private var store: StoreOf<SendFeedbackReducer>

    public init(store: StoreOf<SendFeedbackReducer>) {
        self.store = store
    }
    
    public var body: some View {
        List {
            Section("문의 분류") {
                feedbackTypeView
            }
            .listRowInsets(.init())
            .listRowBackground(Color.clear)
            
            Section("답변 받을 이메일 주소") {
                emailView
            }
            .listRowInsets(.init())
            .listRowBackground(Color.clear)
            
            Section("문의 제목") {
                titleView
            }
            .listRowInsets(.init())
            .listRowBackground(Color.clear)
            
            Section(
                header: Text("문의 내용"),
                footer: HStack {
                    Spacer()
                    Text("\(store.description.count)/3000")
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
                        Text("\(store.selectionImageData.count)/5")
                    }
            ) {
                attachmentView
                if !store.selectionImageData.isEmpty {
                    selectedImageList
                }
            }
            .listRowInsets(.init())
            
            privacyNoticeView
                .listRowInsets(.init())
                .listRowBackground(Color.clear)
            
            sendFeedbackButton
                .listRowInsets(.init())
        }
        .navigationTitle("의견 보내기")
    }
    
    private var feedbackTypeView: some View {
        Menu {
            Picker(store.feedbackType.rawValue, selection: $store.feedbackType.sending(\.setFeedbackType)) {
                ForEach(SendFeedbackReducer.FeedbackType.allCases, id: \.self) { type in
                    Text(type.rawValue)
                        .padding()
                }
            }
        } label: {
            HStack {
                Text(store.feedbackType.rawValue)
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
    
    private var emailView: some View {
        HStack {
            TextField("이메일 주소", text: $store.emailAddress.sending(\.setEmail))
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            
            Text("@")
                .frame(width: 20)
                .background(Color(uiColor: .systemGroupedBackground))
            
            TextField("\(store.emailDomainType.rawValue)", text: $store.emailDomain.sending(\.setDomain))
                .padding()
                .disabled(store.domainDisabled)
                .frame(maxWidth: .infinity)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    HStack {
                        Spacer()
                        Menu {
                            Picker(store.emailDomainType.rawValue, selection: $store.emailDomainType.sending(\.setDomainType)) {
                                ForEach(SendFeedbackReducer.EmailDomainType.allCases, id: \.self) { type in
                                    Text(type.rawValue)
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                                .foregroundStyle(.black)
                                .padding()
                        }
                    }
                }
        }
    }
    
    private var titleView: some View {
        HStack {
            TextField("제목을 입력하세요 (20자 이내)", text: $store.title.sending(\.setTitle))
                .onChange(of: store.title) { _, newValue in
                    if store.title.count > 20 {
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
                        Text("\(store.title.count)/20")
                            .foregroundStyle(.gray)
                            .padding()
                    }
                }
        }
    }
    
    private var inquryDetailsView: some View {
        TextEditor(text: $store.description.sending(\.setDescription))
            .onChange(of: store.description) { _, newValue in
                if store.description.count > 3000 {
                    store.send(.setDescription(String(newValue.prefix(3000))))
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
            ForEach(Array(store.selectionImageData.enumerated()), id: \.offset) { index, imageData in
                if store.selectionImageData.count > index,
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
    
    private var privacyNoticeView: some View {
        HStack {
            HStack {
                Image(systemName: store.privacyAgreement ? "v.circle.fill" : "v.circle")
                    .resizable()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(store.privacyAgreement ? Color.green.opacity(0.6) : Color.gray)
                Text("(필수) 개인정보 수집 이용에 대한 안내")
                    .foregroundStyle(Color.gray)
            }
            .onTapGesture {
                store.send(.togglePrivacyAgreement)
            }
            
            Spacer()
            Text("전문 보기")
                .underline()
                .onTapGesture {
                    store.send(.togglePrivacyDescription)
                }
        }
        .frame(height: 100, alignment: .center)
    }
    
    private var sendFeedbackButton: some View {
        Button {
            store.send(.sendFeedback)
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
    
    private func icon(type: SendFeedbackReducer.AttachmentType) -> String {
        switch type {
        case .photo: return "photo"
        case .file: return "folder"
        }
    }
    
}
 
