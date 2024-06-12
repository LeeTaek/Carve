//
//  CarveView.swift
//  AppManifests
//
//  Created by 이택성 on 1/22/24.
//

import Core
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
            CarveDetailView(store: store.scope(state: \.carveDetailState,
                                               action: \.scope.carveDetailAction))
            .toolbar(.hidden)
        }
        .navigationSplitViewStyle(.automatic)
    }
    
    private var sideBar: some View {
        VStack(alignment: .trailing) {
            List(selection: $store.selectedTitle) {
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
            Text(store.selectedTitle?.koreanTitle() ?? BibleTitle.genesis.koreanTitle())
            List(1...(store.selectedTitle?.lastChapter ?? 1),
                 id: \.self ,
                 selection: $store.selectedChapter) { chapter in
                NavigationLink(chapter.description, value: chapter)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
