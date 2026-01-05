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
    /// iPad 멀티윈도우/회전 등으로 레이아웃(특히 width)이 바뀔 때 PKCanvasView 내부 상태를 리셋하기 위한 트리거
    @State private var canvasLayoutVersion: Int = 0
    @State private var lastObservedScrollSize: CGSize = .zero
    
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
                        .onChange(of: store.verseRowState) {
                            send(.setProxy(proxy))
                        }
                    
                    CombinedCanvasView(
                        store: self.store.scope(
                            state: \.canvasState,
                            action: \.scope.canvasAction
                        )
                    )
                    .id("\(store.canvasState.chapter)-\(canvasLayoutVersion)")
                    .transaction { $0.animation = nil }
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear {
                                    let frame = proxy.frame(in: .named("Scroll"))
                                    send(.canvasFrameChanged(frame))
                                }
                                .onChange(of: proxy.frame(in: .named("Scroll"))) { _, frame in
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
        .onGeometryChange(for: CGSize.self) { proxy in
            return proxy.size
        } action: { size in
            let newHalfWidth = size.width / 2
            if self.halfWidth != newHalfWidth {
                self.halfWidth = newHalfWidth
            }

            // PKCanvasView를 재생성하도록 version을 올린다.
            if self.lastObservedScrollSize != size {
                self.lastObservedScrollSize = size
                self.canvasLayoutVersion &+= 1
            }
        }
    }
    
    private var contentView: some View {
        LazyVStack(pinnedViews: .sectionHeaders) {
            Section {
                ForEach(
                    store.scope(state: \.verseRowState,
                                action: \.scope.verseRowAction),
                    id: \.state.id
                ) { childStore in
                    VerseRowView(
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
