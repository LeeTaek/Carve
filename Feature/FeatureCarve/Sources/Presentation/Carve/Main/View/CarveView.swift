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
    @State private var isShowOldTestment: Bool
    @State private var isShowNewTestment: Bool
    
    public init(store: StoreOf<CarveReducer>) {
        self.store = store
        self.isShowOldTestment = store.currentTitle.title.isOldtestment
        self.isShowNewTestment = !store.currentTitle.title.isOldtestment
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
                DisclosureGroup(
                    isExpanded: $isShowOldTestment,
                    content: {
                        ForEach(BibleTitle.allCases[0..<39]) { title in
                            NavigationLink(title.koreanTitle(), value: title)
                        }
                    }, label: {
                        Text("구약")
                    })
                .disclosureGroupStyle(SidebarDisclosureGroupStyle())
                
                DisclosureGroup(
                    isExpanded: $isShowNewTestment,
                    content: {
                        ForEach(BibleTitle.allCases[39..<66]) { title in
                            NavigationLink(title.koreanTitle(), value: title)
                        }
                    }, label: {
                        Text("신약")
                    })
                .disclosureGroupStyle(SidebarDisclosureGroupStyle())
            }
            .listStyle(.sidebar)
            
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
            Text(store.currentTitle.title.koreanTitle())
            List(1...(store.currentTitle.title.lastChapter),
                 id: \.self ,
                 selection: $store.selectedChapter) { chapter in
                NavigationLink(chapter.description, value: chapter)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}


struct SidebarDisclosureGroupStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
                .bold()
            Spacer()
            Image(systemName: "chevron.right")
                .rotationEffect(configuration.isExpanded ? Angle(degrees: 90) : Angle(degrees: 0))
                .foregroundStyle(.black)
                .animation(.easeInOut(duration: 0/2), value: configuration.isExpanded)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation {
                configuration.isExpanded.toggle()
            }
        }
        if configuration.isExpanded {
            configuration.content
        }
    }
}
