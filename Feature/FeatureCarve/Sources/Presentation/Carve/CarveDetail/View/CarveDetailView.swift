//
//  CarveDetailView.swift
//  FeatureCarve
//
//  Created by 이택성 on 5/30/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Core
import SwiftUI

import ComposableArchitecture

@ViewAction(for: CarveDetailReducer.self)
public struct CarveDetailView: View {
    @Bindable public var store: StoreOf<CarveDetailReducer>
    
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
                        scrollToTop(proxy: proxy)
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
                                action: \.scope.sentenceWithDrawingAction)
                ) { childStore in
                    SentencesWithDrawingView(store: childStore)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10)
                }
            }
        }
    }
    
    private func scrollToTop(proxy: ScrollViewProxy) {
        guard let id = store.scope(state: \.sentenceWithDrawingState,
                                   action: \.scope.sentenceWithDrawingAction).first?.id else { return }
        send(.setProxy(proxy, id))
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
            CarveDetailReducer()
        }   
    )
    CarveDetailView(store: store)
}
