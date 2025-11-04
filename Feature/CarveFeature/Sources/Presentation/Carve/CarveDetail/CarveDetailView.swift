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
    @State private(set) var halfWidth: CGFloat = 0
    
    public init(store: StoreOf<CarveDetailFeature>) {
        self.store = store
    }
    
    public var body: some View {
        if #available(iOS 17.5, *) {
            applyPencilDoubleTapView()
                .overlay(alignment: .top) {
                    HeaderView(store: store.scope(state: \.headerState,
                                                  action: \.scope.headerAction))
                }
                .toolbar(.hidden, for: .navigationBar)
        } else {
            detailScroll
                .overlay(alignment: .top) {
                    HeaderView(store: store.scope(state: \.headerState,
                                                  action: \.scope.headerAction))
                }
                .toolbar(.hidden, for: .navigationBar)
        }
    }
    
    
    @available(iOS 17.5, *)
    private func applyPencilDoubleTapView() -> some View {
        detailScroll
            .onPencilDoubleTap { _ in
                let isEraser = (store.headerState.palatteSetting.pencilConfig.pencilType == .monoline)
                if isEraser {
                    send(.switchToPrevious)
                } else {
                    send(.switchToEraser)
                }
            }
    }
    
    private var detailScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                ZStack {
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
                    
                    CombinedCanvasView(sentenceStates: Array(store.sentenceWithDrawingState))
                        .id(store.sentenceWithDrawingState.map(\.verseFrame.debugDescription).joined())
                        .allowsHitTesting(false) // 일단 보기용
                }
                .coordinateSpace(name: "Scroll")
                .onAppear {
                    send(.fetchSentence)
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            return proxy.size.width / 2
        } action: { halfWidth in
            self.halfWidth = halfWidth
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
                    SentencesWithDrawingView(store: childStore, halfWidth: $halfWidth)
                        .padding(.horizontal, 10)
                }
            }
        }
        .id("\(store.sentenceSetting)-\(halfWidth)")
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
