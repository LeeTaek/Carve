//
//  TitleView.swift
//  FeatureCarve
//
//  Created by 이택성 on 1/29/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI
import DomainRealm

import ComposableArchitecture

public struct TitleView: View {
    private let store: StoreOf<TitleReducer>
    @ObservedObject private var viewStore: ViewStore<TitleReducer.State, TitleReducer.ViewAction>
    
    public init(store: StoreOf<TitleReducer>) {
        self.store = store
        self.viewStore = ViewStore(self.store, observe: { $0 }, send: { .view($0) })
    }
    
    public var body: some View {
        title
    }
    
    var title: some View {
        let titleName = viewStore.currentBible.title.rawValue
        return HStack {
            Button(action: { viewStore.send(.titleDidTapped) }) {
                Text("\(titleName) \(viewStore.state.currentBible.chapter)장")
                    .font(.system(size: 30))
                    .padding()
            }
            Spacer()
        }
        .sheet(
            isPresented: viewStore.binding(
                get: { $0.isPresentTitleSheet },
                send: .titleDidTapped),
            content: {
                VStack {
                    sheetTitle
                    HStack {
                        bibleTitleList
                        chapterList
                    }
                    .padding()
                }
            }
        )
    }
    
    
    var sheetTitle: some View {
        HStack {
            Text("목차")
                .font(.title)
                .fontWeight(.heavy)
                .padding()
            
            Spacer()
            Button(action: { viewStore.send(.presentTitle(false)) }) {
                Image(systemName: "x.circle")
            }
            .padding()
        }
    }
    
    
    var bibleTitleList: some View {
        List {
            ForEach(BibleTitle.allCases, id: \.self) { title in
                let titleName = title.rawTitle()
                
                Button(action: { viewStore.send(.bibleTitleDidTapped(title)) }) {
                    Text("\(titleName)")
                }
            }
        }
        .listStyle(.plain)
    }
    
    
    var chapterList: some View {
        List {
            ForEach(1...viewStore.lastChapter, id: \.self) { chapter in
                Button(action: { viewStore.send(.bibleChapterDidTapped(chapter))}) {
                    Text("\(chapter)")
                }
            }
        }
        .listStyle(.plain)
    }
    
}



#Preview {
    let store = Store(initialState: TitleReducer.State.initialState) {
        TitleReducer()
    }
    return TitleView(store: store)
}
