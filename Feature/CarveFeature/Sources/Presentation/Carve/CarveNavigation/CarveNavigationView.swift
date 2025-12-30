//
//  CarveNavigationView.swift
//  AppManifests
//
//  Created by 이택성 on 1/22/24.
//

import CarveToolkit
import Domain
import SwiftUI
import Resources

import ComposableArchitecture

/// Carve 디테일 화면의 네비게이션 담당
@ViewAction(for: CarveNavigationFeature.self)
public struct CarveNavigationView: View {
    @Bindable public var store: StoreOf<CarveNavigationFeature>
    /// 구약 성경의 DisclosureGroup 접힘/펼침
    @State private var isShowOldTestment: Bool
    /// 신약 성경의 DisclosureGroup 접힘/펼침
    @State private var isShowNewTestment: Bool
    
    public init(store: StoreOf<CarveNavigationFeature>) {
        self.store = store
        self.isShowOldTestment = store.currentTitle.title.isOldtestment
        self.isShowNewTestment = !store.currentTitle.title.isOldtestment
    }
    
    public var body: some View {
        NavigationSplitView(columnVisibility: $store.columnVisibility) {
            sideBar
                .navigationSplitViewColumnWidth(min: 200, ideal: 300, max: 350)
        } content: {
            contentList
                .navigationSplitViewColumnWidth(min: 150, ideal: 300, max: 350)
        } detail: {
            detailView()
        }
        .navigationSplitViewStyle(.prominentDetail)
    }
    
    /// 성경 제목(구약/신약) 사이드바
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
            ToolbarItemGroup(placement: .bottomBar) {
                HStack {
//                    Button {
//                        send(.navigationToDrewLog)
//                    } label: {
//                        Image(asset: CarveFeatureAsset.chart)
//                            .resizable()
//                            .aspectRatio(contentMode: .fit)
//                            .foregroundStyle(.black)
//                            .frame(width: 35, height: 35)
//                    }
                    
//                    if #available(iOS 26.0, *) {
//                        ToolbarSpacer(.fixed)
//                    }
                    
                    
                    Button {
                        send(.moveToSetting)
                    } label: {
                        Image(asset: CarveFeatureAsset.settings)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundStyle(.black)
                            .frame(width: 25, height: 25)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
    
    /// 성경 장 목록
    private var contentList: some View {
        List(1...(store.currentTitle.title.lastChapter),
             id: \.self ,
             selection: $store.selectedChapter) { chapter in
            NavigationLink(chapter.description, value: chapter)
        }
             .navigationTitle(store.currentTitle.title.koreanTitle())
    }
    
    /// detail화면의 content와 sheet popup 등 네비게이션 관리.
    @ViewBuilder
    private func detailView() -> some View {
        if store.columnVisibility != .detailOnly {
            Color(uiColor: .secondarySystemGroupedBackground)
                .onTapGesture {
                    send(.closeNavigationBar)
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

/// 사이드바 DisclosureGroup에 화살표 회전 애니메이션을 적용하는 커스텀 스타일
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

#Preview {
    @Previewable @State var store = Store(initialState: .initialState) {
        CarveNavigationFeature()
    }
    
    CarveNavigationView(store: store)
}
