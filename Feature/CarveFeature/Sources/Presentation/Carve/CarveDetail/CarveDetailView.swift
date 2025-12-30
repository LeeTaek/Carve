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
    @State private var isInking: Bool = false
    
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
//                    // ✅ Canvas를 contentView에 overlay로 올려서 높이/레이아웃을 완전히 동일하게 맞춘다.
//                    // 이렇게 하면 Pencil hover/다운 시점에 Canvas만 별도로 "커지는" 레이아웃 흔들림을 줄일 수 있다.
//                    .overlay {
//                        CombinedCanvasView(
//                            store: self.store.scope(
//                                state: \.canvasState,
//                                action: \.scope.canvasAction
//                            ),
//                            onInkingChanged: { isInking in
//                                self.isInking = isInking
//                            }
//                        )
//                        .border(.red)
//                        .id(store.canvasState.chapter)
//                        .frame(width: halfWidth)
//                        .frame(
//                            maxWidth: .infinity,
//                            maxHeight: .infinity,
//                            alignment: store.isLeftHanded ? .leading : .trailing
//                        )
//                        .background(
//                            GeometryReader { proxy in
//                                Color.clear
//                                    .allowsHitTesting(false)
//                                    .onAppear {
//                                        let frame = proxy.frame(in: .named("CanvasSpace"))
//                                        send(.canvasFrameChanged(frame))
//                                    }
//                                    .onChange(of: proxy.frame(in: .named("CanvasSpace"))) { _, frame in
//                                        // 최종 레이아웃 기준 프레임을 항상 반영 (split/fullscreen 전환 시 좌표계 어긋남 방지)
//                                        send(.canvasFrameChanged(frame))
//                                    }
//                            }
//                        )
//                    }
                    .coordinateSpace(name: "CanvasSpace")
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
            // Drawing 중에는 레이아웃 폭 변경을 반영하지 않아 좌표계 흔들림을 방지
            guard !isInking else { return }

            let scale = UIScreen.main.scale
            let newValue = floor(halfWidth * scale) / scale

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                self.halfWidth = newValue
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
                    SentencesWithDrawingView(
                        store: childStore,
                        halfWidth: $halfWidth,
                        onUnderlineLayoutChange: { id, layout in
                            send(.underlineLayoutChanged(id: id, layout: layout))
                        }
                    )
                    .padding(.horizontal, 10)
                }
            }
        }
        .id(store.sentenceSetting)
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
