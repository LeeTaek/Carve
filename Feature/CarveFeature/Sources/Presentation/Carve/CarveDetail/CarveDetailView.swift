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
    /// verse 레이아웃 변경 시 underline frame 재측정을 위한 트리거
    @State private var verseLayoutVersion: Int = 0
    /// ScrollView의 스크롤 offset (content 기준, down = 양수)
    @State private var scrollOffset: CGFloat = 0
    /// ScrollView 내부 콘텐츠 높이 (LazyVStack 특성상 증가만 반영)
    @State private var contentHeight: CGFloat = 0
    /// ScrollView viewport 크기
    @State private var viewportSize: CGSize = .zero
    /// Root 좌표계 기준 Canvas frame
    @State private var canvasRootFrame: CGRect = .zero
    
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
            ZStack(alignment: .top) {
                ScrollView {
                    contentView
                        .padding(.top, store.headerState.headerHeight)
                        .offsetY { previous, current in
                            let newOffset = -current
                            if scrollOffset != newOffset {
                                scrollOffset = newOffset
                            }
                            delay {
                                send(.headerAnimation(previous, current))
                            }
                        }
                        .background(
                            GeometryReader { proxy in
                                Color.clear
                                    .preference(key: ContentHeightKey.self, value: proxy.size.height)
                            }
                        )
                        .onChange(of: store.verseRowState) {
                            send(.setProxy(proxy))
                        }
                }
                .onTapGesture {
                    send(.tapForHeaderHidden)
                }
                .onTwoFingerDoubleTap {
                    send(.twoFingerDoubleTapForUndo)
                }
                .coordinateSpace(name: "Scroll")
                
                CombinedCanvasView(
                    store: self.store.scope(
                        state: \.canvasState,
                        action: \.scope.canvasAction
                    ),
                    viewportSize: CGSize(width: halfWidth, height: viewportSize.height),
                    contentHeight: contentHeight,
                    scrollOffset: scrollOffset,
                    bottomBuffer: canvasBuffer
                )
                .id("\(store.canvasState.chapter)-\(canvasLayoutVersion)")
                .transaction { $0.animation = nil }
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear {
                                canvasRootFrame = proxy.frame(in: .named("Root"))
                            }
                            .onChange(of: proxy.frame(in: .named("Root"))) { _, frame in
                                canvasRootFrame = frame
                            }
                    }
                )
                .frame(width: halfWidth)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: store.isLeftHanded ? .topLeading : .topTrailing
                )
            }
            .coordinateSpace(name: "Root")
            .onAppear {
                send(.fetchSentence)
            }
            .onChange(of: store.canvasState.chapter) { _, _ in
                contentHeight = 0
            }
            .onChange(of: store.sentenceSetting) { _, _ in
                contentHeight = 0
            }
            .onPreferenceChange(ContentHeightKey.self) { height in
                if height > contentHeight {
                    contentHeight = height
                }
            }
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            let newHalfWidth = size.width / 2
            if halfWidth != newHalfWidth {
                halfWidth = newHalfWidth
                verseLayoutVersion &+= 1
            }
            
            let viewportChanged = (viewportSize != size)
            if viewportChanged {
                viewportSize = size
                // iPad 멀티윈도우/회전 등으로 viewport가 바뀌면 PKCanvasView를 재생성하도록 version을 올린다.
                canvasLayoutVersion &+= 1
                verseLayoutVersion &+= 1
                // LazyVStack 콘텐츠 높이 측정값도 리셋
                contentHeight = 0
            }
        }
    }
    
    private var contentView: some View {
        LazyVStack {
            ForEach(
                store.scope(state: \.verseRowState,
                            action: \.scope.verseRowAction),
                id: \.state.id
            ) { childStore in
                VerseRowView(
                    store: childStore,
                    halfWidth: $halfWidth,
                    canvasRootFrame: canvasRootFrame,
                    scrollOffset: scrollOffset,
                    layoutVersion: verseLayoutVersion + store.underlineLayoutVersion,
                    onUnderlineLayoutChange: { id, layout in
                        send(.underlineLayoutChanged(id: id, layout: layout))
                    }
                )
                .padding(.horizontal, 10)
            }
            
        }
        .id("\(store.sentenceSetting)-\(halfWidth)")
    }
    
    private var canvasBuffer: CGFloat {
        guard viewportSize.height > 0 else { return 0 }
        return max(80, viewportSize.height * 0.25)
    }
    
    /// 헤더 스크롤 애니메이션 등 과도한 이벤트 호출을 방지하기 위한 딜레이
    private func delay(
        to delay: TimeInterval = 0.1,
        _ action: @escaping () -> Void
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
    }
}

/// ScrollView 콘텐츠 높이를 상위로 전달하기 위한 PreferenceKey.
private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
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
