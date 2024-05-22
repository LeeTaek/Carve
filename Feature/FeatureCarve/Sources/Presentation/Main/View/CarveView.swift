//
//  CarveView.swift
//  AppManifests
//
//  Created by 이택성 on 1/22/24.
//

import Core
import CommonUI
import Domain
import SwiftUI

import ComposableArchitecture

public struct CarveView: View {
    @Bindable private var store: StoreOf<CarveReducer>
    
    public init(store: StoreOf<CarveReducer>) {
        self.store = store
    }
    
    public var body: some View {
        NavigationSplitView(columnVisibility: $store.columnVisibility) {
            sideBar
        } content: {
            contentList
        } detail: {
            detailScroll
                .overlay(alignment: .top) {
                    header
                    
                }
                .toolbar(.hidden, for: .navigationBar)
                .onAppear {
                    store.send(.inner(.fetchSentence))
                }
        }
        .navigationSplitViewStyle(.automatic)
    }
    
    private var sideBar: some View {
        VStack(alignment: .trailing) {
            List(selection: $store.viewProperty.selectedTitle) {
                Section(header: Text("구약")) {
                    ForEach(BibleTitle.allCases[0..<39]) { title in
                        NavigationLink(title.koreanTitle(), value: title)
                    }
                }
                Section(header: Text("신약")) {
                    ForEach(BibleTitle.allCases[39..<66]) { title in
                        NavigationLink(title.koreanTitle(), value: title)
                    }
                }
            }
            .listStyle(.inset)
            
            Button {
                store.send(.view(.moveToSetting))
            } label: {
                Image(systemName: "gear")
                    .foregroundStyle(.black)
            }
            .frame(width: 30, height: 30)
            .padding(.trailing, 15)
        }
        .navigationTitle("성경")
    }
    
    private var contentList: some View {
        VStack {
            Text(store.viewProperty.selectedTitle?.koreanTitle() ?? store.currentTitle.title.koreanTitle())
            List(1...(store.viewProperty.selectedTitle?.lastChapter ?? store.currentTitle.title.lastChapter),
                 id: \.self ,
                 selection: $store.viewProperty.selectedChapter) { chapter in
                NavigationLink(chapter.description, value: chapter)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
    
    public var header: some View {
        let titleName = store.currentTitle.title.koreanTitle()
        return HStack {
            Button(action: { store.send(.view(.titleDidTapped)) }) {
                Text("\(titleName) \(store.state.currentTitle.chapter)장")
                    .font(.system(size: 30))
                    .padding()
            }
            Spacer()
        }
        .background {
            Color.white
                .ignoresSafeArea()
        }
        .padding(.top, safeArea().top)
        .padding(.bottom, 20)
        .anchorPreference(key: HeaderBoundsKey.self, value: .bounds) { $0 }
        .overlayPreferenceValue(HeaderBoundsKey.self) { value in
            GeometryReader { proxy in
                if let anchor = value {
                    Color.clear
                        .onAppear {
                            store.send(.view(.setHeaderHeight(proxy[anchor].height)))
                        }
                }
            }
        }
        .offset(y: -store.viewProperty.headerOffset < store.viewProperty.headerOffset
                ? store.viewProperty.headerOffset
                : (store.viewProperty.headerOffset < 0 ? store.viewProperty.headerOffset : 0))
        .ignoresSafeArea(.all, edges: .top)
    }
    
    private var detailScroll: some View {
        ScrollView {
            LazyVStack(pinnedViews: .sectionHeaders) {
                Section {
                    ForEach(
                        store.scope(state: \.sentenceWithDrawingState,
                                    action: \.scope.sentenceWithDrawingAction)
                    ) { childStore in
                        SentencesWithDrawingView(store: childStore)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 10)
                    }
                } header: {
                    // TODO: - ChapterTitleView
                }
            }
            .padding(.top, store.viewProperty.headerHeight)
            .offsetY { previous, current in
                store.send(.view(.headerAnimation(previous, current)))
            }
        }
        .coordinateSpace(name: "Scroll")
    }
}
