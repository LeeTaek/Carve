//
//  CarveNavigationView.swift
//  AppManifests
//
//  Created by 이택성 on 1/22/24.
//

import Core
import Domain
import SwiftUI
import Resources

import ComposableArchitecture

public struct CarveNavigationView: View {
    @Bindable private var store: StoreOf<CarveNavigationReducer>
    @State private var isShowOldTestment: Bool
    @State private var isShowNewTestment: Bool
    
    public init(store: StoreOf<CarveNavigationReducer>) {
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
            detailView()
        }
        .navigationSplitViewStyle(.automatic)
    }
    
    private var sideBar: some View {
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
        .navigationTitle("성경")
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                HStack {
                    Spacer()
//                    Button {
//                        store.send(.view(.navigationToDrewLog))
//                    } label: {
//                        Image(systemName: "book.pages")
//                            .foregroundStyle(.black)
//                    }
//                    .frame(width: 30, height: 30)
//                    .padding(15)
                    Button {
                        store.send(.view(.moveToSetting))
                    } label: {
                        Image(systemName: "gear")
                            .foregroundStyle(.black)
                    }
                    .frame(width: 30, height: 30)
                    .padding(.trailing, 15)
                }
            }
        }
        .toolbar(removing: .sidebarToggle)
    }
    
    private var contentList: some View {
        List(1...(store.currentTitle.title.lastChapter),
             id: \.self ,
             selection: $store.selectedChapter) { chapter in
            NavigationLink(chapter.description, value: chapter)
        }
             .navigationTitle(store.currentTitle.title.koreanTitle())
    }
    
    @ViewBuilder
    private func detailView() -> some View {
        if store.columnVisibility != .detailOnly {
            Color(uiColor: .secondarySystemGroupedBackground)
                .toolbar(.hidden)
                .onTapGesture {
                    store.send(.view(.closeNavigationBar))
                }
        } else {
            CarveDetailView(store: store.scope(state: \.carveDetailState,
                                               action: \.scope.carveDetailAction))
            .sheet(
                item: $store.scope(
                    state: \.detailNavigation?.sentenceSettings,
                    action: \.view.detailNavigation.sentenceSettings
                )
            ) { store in
                SentenceSettingsView(store: store)
            }
            .fullScreenCover(
                item: $store.scope(
                    state: \.detailNavigation?.drewLog,
                    action: \.view.detailNavigation.drewLog)
            ) { store in
                DrewLogView(store: store)
                    .toolbar(.visible, for: .navigationBar)
            }
        }
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
