//
//  CarveDetailView.swift
//  FeatureCarve
//
//  Created by 이택성 on 5/30/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI

import ComposableArchitecture

public struct CarveDetailView: View {
    @Bindable private var store: StoreOf<CarveDetailReducer>
    
    public init(store: StoreOf<CarveDetailReducer>) {
        self.store = store
    }
    
    public var body: some View {
        detailScroll
            .overlay(alignment: .top) {
                HeaderView(store: store.scope(state: \.headerState,
                                              action: \.scope.headerAction))
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                store.send(.inner(.fetchSentence))
            }
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
            .padding(.top, store.headerState.headerHeight)
            .offsetY { previous, current in
                store.send(.view(.headerAnimation(previous, current)))
            }
        }
        .sheet(
            item: $store.scope(
                state: \.navigation?.sentenceSettings,
                action: \.view.navigation.sentenceSettings
            )
        ) { store in
            SentenceSettingsView(store: store)
        }
        .coordinateSpace(name: "Scroll")
    }

    
}
