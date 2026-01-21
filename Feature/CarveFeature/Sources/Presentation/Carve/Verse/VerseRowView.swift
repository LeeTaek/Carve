//
//  VerseRowView.swift
//  FeatureCarve
//
//  Created by 이택성 on 2/22/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI
import CarveToolkit

import ComposableArchitecture

enum VerseLayoutMetrics {
    static let underlineHorizontalInset: CGFloat = 20
    /// VerseRowView의 HStack에 적용되는 세로 padding. (아래/위 여백)
    /// - Note: 이 여백 영역에 그려진 스트로크도 인접 verse에 포함되어 저장될 수 있도록
    ///         underline frame 측정 rect를 동일 값만큼 확장할 때도 사용한다.
    static let rowVerticalPadding: CGFloat = 2
}

/// 한 절(verse)에 대한 Row UI를 그리는 뷰.
@ViewAction(for: VerseRowFeature.self)
public struct VerseRowView: View {
    @Bindable public var store: StoreOf<VerseRowFeature>
    /// sentence와 canvas 영역 배치를 위한 너비
    @Binding private var halfWidth: CGFloat
    /// Root 좌표계 기준 Canvas frame
    private let canvasRootFrame: CGRect
    /// ScrollView의 스크롤 offset (content 기준, down = 양수)
    private let scrollOffset: CGFloat
    /// 레이아웃 변경 시 underline frame 재측정용 버전
    private let layoutVersion: Int
    /// Text.LayoutKey(텍스트 레이아웃 변경 이벤트)를 상위(CarveDetailFeature)로 전달하기 위한 클로저.
    /// - Note: 원래는 VerseTextFeature.Action.setUnderlineOffsets로 직접 액션을 보냈으나,
    ///         ForEachReducer에서 missing element warning이 발생하는 문제를 피하기 위해
    ///         레이아웃 이벤트만 상위로 올리고, 실제 underlineOffsets 계산 및 상태 갱신은
    ///         CarveDetailFeature에서 처리.
    let onUnderlineLayoutChange: (VerseRowFeature.State.ID, Text.LayoutKey.Value) -> Void

    
    public init(
        store: StoreOf<VerseRowFeature>,
        halfWidth: Binding<CGFloat>,
        canvasRootFrame: CGRect,
        scrollOffset: CGFloat,
        layoutVersion: Int,
        onUnderlineLayoutChange: @escaping (VerseRowFeature.State.ID, Text.LayoutKey.Value) -> Void
    ) {
        self.store = store
        self._halfWidth = halfWidth
        self.canvasRootFrame = canvasRootFrame
        self.scrollOffset = scrollOffset
        self.layoutVersion = layoutVersion
        self.onUnderlineLayoutChange = onUnderlineLayoutChange
    }
    
    public var body: some View {
        VStack {
            if store.verseTextState.chapterTitle != nil {
                chapterTitleView
            }
            HStack(alignment: .top) {
                if store.isLeftHanded {
                    // 왼손잡이
                    underLineView
                    sentenceView
                } else {
                    // 오른손잡이
                    sentenceView
                    underLineView
                }
            }
            .animation(.easeInOut(duration: 0.3), value: store.isLeftHanded)
            .padding(.vertical, VerseLayoutMetrics.rowVerticalPadding)
        }
        .touchIgnoringContextMenu(ignoringType: .pencil) {
            UIMenu(children: [
                UIAction(title: "이전 필사 내용 보기") {_ in send(.presentDrewHistory(true)) }
            ])
        }
        .sheet(isPresented: $store.isPresentDrewHistory.sending(\.view.presentDrewHistory)) {
            VerseDrawingHistoryView(
                store: self.store.scope(state: \.drewHistoryState,
                                        action: \.scope.drewHistoryAction)
            )
        }
    }
    
    /// 현재 절 내용표시 텍스트 뷰
    private var sentenceView: some View {
        VerseTextView(
            store: self.store.scope(state: \.verseTextState,action: \.scope.verseTextAction),
            onLayoutChange: { layout in
                onUnderlineLayoutChange(store.id, layout)
            }
        )
        .frame(width: halfWidth * 0.95, alignment: .leading)
    }
    
    /// 각 장의 제목
    private var chapterTitleView: some View {
        Text(store.verseTextState.chapterTitle ?? "")
            .font(.system(size: 22))
            .fontWeight(.heavy)
    }
    
    /// Canvas 밑에 깔 밑줄 view
    /// glbalRect를 측정해 상위로 전달
    private var underLineView: some View {
        let underlineOffsets = store.verseTextState.underlineOffsets
        let sendFrame: (CGRect) -> Void = { rect in
            let verticalPadding = VerseLayoutMetrics.rowVerticalPadding
            let adjusted = CGRect(
                x: rect.minX - canvasRootFrame.minX,
                y: rect.minY - canvasRootFrame.minY + scrollOffset - verticalPadding,
                width: rect.width,
                height: rect.height + verticalPadding * 2
            )
            send(.updateVerseFrame(adjusted))
        }
        
        return Canvas { context, size in
            for y in underlineOffsets {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(.gray), style: StrokeStyle(lineWidth: 1, dash: [5]))
            }
        }
        .padding(.horizontal, VerseLayoutMetrics.underlineHorizontalInset)
        .frame(width: halfWidth, alignment: .topTrailing)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        DispatchQueue.main.async {
                            sendFrame(proxy.frame(in: .named("Root")))
                        }
                    }
                    .onChange(of: proxy.size) { _, _ in
                        DispatchQueue.main.async {
                            sendFrame(proxy.frame(in: .named("Root")))
                        }
                    }
                    .onChange(of: canvasRootFrame) { _, _ in
                        DispatchQueue.main.async {
                            sendFrame(proxy.frame(in: .named("Root")))
                        }
                    }
                    .onChange(of: layoutVersion) { _, _ in
                        DispatchQueue.main.async {
                            sendFrame(proxy.frame(in: .named("Root")))
                        }
                    }
            }
        )
    }
    
}

#Preview {
    @Previewable @State var store = Store(
        initialState: .initialState) {
            VerseRowFeature()
        }
    @Previewable @State var halfWidth = UIScreen().bounds.width / 2
    @Previewable @State var layoutVersion: Int = 0
    
    VerseRowView(
        store: store,
        halfWidth: $halfWidth,
        canvasRootFrame: .zero,
        scrollOffset: 0,
        layoutVersion: layoutVersion
    ) { _, layout in
        let offsets =  VerseTextFeature.makeUnderlineOffsets(
            from: layout,
            sentenceSetting: store.verseTextState.sentenceSetting
        )
        store.send(.scope(.verseTextAction(.setUnderlineOffsets(offsets))))
    }
}
