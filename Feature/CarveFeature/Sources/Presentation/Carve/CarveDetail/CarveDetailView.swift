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
    /// CombinedCanvasView의 너비를 화면의 절반으로 맞추기 위해 계산.
    @State private(set) var halfWidth: CGFloat = 0
    
    public init(store: StoreOf<CarveDetailFeature>) {
        self.store = store
    }
    
    public var body: some View {
        /// iOS 17.5 이상에서 Apple Pencil 더블탭으로 지우개/이전 펜 타입을 전환하는 래핑 뷰 적용
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
                    send(.switchToPreviousPenType)
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
                            delay {
                                send(.headerAnimation(previous, current))
                            }
                        }
                        .onChange(of: store.sentenceWithDrawingState) {
                            send(.setProxy(proxy))
                        }
                    
                    CombinedCanvasView(
                        store: self.store.scope(
                            state: \.canvasState,
                            action: \.scope.canvasAction
                        )
                    )
                    .id(store.canvasState.title)
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear {
                                    let frame = proxy.frame(in: .global)
                                    send(.canvasFrameChanged(frame))
                                }
                                .onChange(of: proxy.frame(in: .global)) { _, frame in
                                    send(.canvasFrameChanged(frame))
                                }
                        }
                    )
                    .frame(width: halfWidth)
                    .frame(
                        maxWidth: .infinity,
                        alignment: store.isLeftHanded ? .leading : .trailing
                    )
                }
                .onAppear {
                    send(.fetchSentence)
                }
            }
            .onTapGesture {
                send(.tapForHeaderHidden)
            }
            .onTwoFingerDoubleTap {
                send(.twoFingerDoubleTapForUndo)
            }
            .coordinateSpace(name: "Scroll")
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
                    VerseRowView(store: childStore, halfWidth: $halfWidth)
                        .padding(.horizontal, 10)
                }
            }
        }
        .id("\(store.sentenceSetting)-\(halfWidth)")
    }
    
    /// 헤더 스크롤 애니메이션 등 과도한 이벤트 호출을 방지하기 위한 딜레이
    private func delay(
        to delay: TimeInterval = 0.1,
        _ action: @escaping () -> Void
    ) {
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
