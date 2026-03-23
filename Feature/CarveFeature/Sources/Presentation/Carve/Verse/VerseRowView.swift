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
    /// 마지막으로 전달한 underline frame (중복 업데이트 방지용)
    @State private var lastSentFrame: CGRect?

    
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
        let lineGapPadding = underlineVerticalPadding
        let underlineMinimumHeight = max(1, (underlineOffsets.max() ?? 0) + 1)
        let strokeBuffer: CGFloat = 2
        let combinedLayoutVersion = layoutVersion + store.layoutVersion
        let sendFrame: (CGRect) -> Void = { rect in
            let adjusted = CGRect(
                x: rect.minX - canvasRootFrame.minX,
                y: rect.minY - canvasRootFrame.minY + scrollOffset - strokeBuffer,
                width: rect.width,
                height: rect.height + strokeBuffer * 2
            )
            let isValidFrame = adjusted.minX.isFinite
                && adjusted.minY.isFinite
                && adjusted.width.isFinite
                && adjusted.height.isFinite
            guard isValidFrame else { return }
            if !rectApproximatelyEqual(lastSentFrame, adjusted, tolerance: 0.5) {
                lastSentFrame = adjusted
                PerformanceLog.event("VerseRow.FrameUpdated")
                send(.updateVerseFrame(adjusted))
            } else {
                PerformanceLog.event("VerseRow.FrameSkipped")
            }
        }
        return Canvas { context, size in
            for y in underlineOffsets {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(.gray), style: StrokeStyle(lineWidth: 1, dash: [5]))
            }
        }
        .frame(minHeight: underlineMinimumHeight, alignment: .top)
        .padding(.vertical, lineGapPadding)
        .padding(.horizontal, VerseLayoutMetrics.underlineHorizontalInset)
        .frame(width: halfWidth, alignment: .topTrailing)
        .background(
            GeometryReader { proxy in
                let combinedKey = UnderlineLayoutKey(
                    size: proxy.size,
                    canvasFrame: canvasRootFrame,
                    layoutVersion: combinedLayoutVersion
                )
                let rootFrame = proxy.frame(in: .named("Root"))
                Color.clear
                    .onAppear {
                        sendFrame(rootFrame)
                    }
                    .onChange(of: combinedKey) { _, _ in
                        sendFrame(proxy.frame(in: .named("Root")))
                    }
            }
        )
    }

    private var underlineVerticalPadding: CGFloat {
        let setting = store.verseTextState.sentenceSetting
        let font = setting.fontFamily.font(size: setting.fontSize)
        let lineGap = max(0, setting.lineSpace - font.lineHeight)
        return lineGap / 2
    }
    
}

private func rectApproximatelyEqual(_ lhs: CGRect?, _ rhs: CGRect, tolerance: CGFloat) -> Bool {
    guard let lhs else { return false }
    return abs(lhs.minX - rhs.minX) <= tolerance &&
        abs(lhs.minY - rhs.minY) <= tolerance &&
        abs(lhs.width - rhs.width) <= tolerance &&
        abs(lhs.height - rhs.height) <= tolerance
}

private struct UnderlineLayoutKey: Equatable {
    let size: CGSize
    let canvasFrame: CGRect
    let layoutVersion: Int
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
