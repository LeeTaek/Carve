//
//  CarveDetailView.swift
//  FeatureCarve
//
//  Created by 이택성 on 5/30/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import CarveToolkit
import SwiftUI

import ComposableArchitecture

@ViewAction(for: CarveDetailFeature.self)
public struct CarveDetailView: View {
    @Bindable public var store: StoreOf<CarveDetailFeature>
    
    public init(store: StoreOf<CarveDetailFeature>) {
        self.store = store
    }
    
    public var body: some View {
        detailScroll
            .overlay(alignment: .top) {
                HeaderView(store: store.scope(state: \.headerState,
                                              action: \.scope.headerAction))
            }
            .toolbar(.hidden, for: .navigationBar)
    }
    
    private var detailScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                contentView
                    .padding(.top, store.headerState.headerHeight)
                    .offsetY { previous, current in
                        debounce {
                            send(.headerAnimation(previous, current))
                        }
                    }
                    .onChange(of: store.sentenceWithDrawingState) {
                        send(.setProxy(proxy))
                    }
            }
            .coordinateSpace(name: "Scroll")
            .onAppear {
                send(.fetchSentence)
            }
        }
    }
    
    private var contentView: some View {
        LazyVStack(pinnedViews: .sectionHeaders) {
            Section {
                ForEach(
                    store.scope(state: \.sentenceWithDrawingState,
                                action: \.scope.sentenceWithDrawingAction),
                    id: \.state.id
                ) { childStore in
                    SentencesWithDrawingView(store: childStore)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10)
                }
            }
        }
    }

    private func debounce(delay: TimeInterval = 0.1,
                          _ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
    }
}


#Preview {
    @Previewable @State var store = Store(
        initialState: .initialState,
        reducer: {
            CarveDetailFeature()
        }   
    )
    CarveDetailView(store: store)
}
