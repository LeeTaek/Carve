//
//  SentencesWithDrawingView.swift
//  FeatureCarve
//
//  Created by 이택성 on 2/22/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI
import CarveToolkit

import ComposableArchitecture

@ViewAction(for: SentencesWithDrawingFeature.self)
public struct SentencesWithDrawingView: View, Equatable {
    /// 부모 재평가 시 body 생략 판정 (`.equatable()`). 클로저는 비교할 수 없으므로 제외하고,
    /// 자식 store 는 TCA 가 id 별로 캐시하는 같은 인스턴스이므로 참조 동일성으로 비교한다.
    /// 행 자신의 상태 변화는 store 관찰로 따로 갱신되므로 이 비교와 무관하다.
    public static func == (lhs: SentencesWithDrawingView, rhs: SentencesWithDrawingView) -> Bool {
        lhs.store === rhs.store
            && lhs.halfWidth == rhs.halfWidth
            && lhs.isLayoutReady == rhs.isLayoutReady
            && lhs.isCanvasActive == rhs.isCanvasActive
    }

    @Bindable public var store: StoreOf<SentencesWithDrawingFeature>
    @Binding private var halfWidth: CGFloat
    /// 설계 §6-2 입력 게이트. 장 레이아웃이 완성되기 전에는 캔버스 입력을 막는다 (Phase 2).
    private let isLayoutReady: Bool
    /// `PKCanvasView` 를 실제로 만들지 여부 (Phase 2 — 캔버스 지연 생성).
    ///
    /// 텍스트·밑줄·frame 실측은 이 값과 무관하게 항상 일어나므로 장 레이아웃은 전 절에 대해 완성된다.
    /// false 인 동안은 같은 크기의 빈 자리만 차지한다 — 행 높이는 텍스트가 정하므로 배치가 바뀌지 않는다.
    private let isCanvasActive: Bool
    
    /// 1절의 상단 여백. 캔버스 **안**의 여백이라 레이아웃에서는 `VerseLayoutInput.topPadding` 이 된다.
    private var topDrawingInset: CGFloat {
        ChapterLayoutHosting.topPadding(forVerse: store.sentence.verse)
    }
    let onUnderlineLayoutChange: (VerseRowFeature.State.ID, Text.LayoutKey.Value) -> Void
    /// 소제목 높이 실측 → 상위(`CarveDetailFeature`)로 전달. 레이아웃의 `leadingInset` 이 된다.
    let onTitleHeightChange: (VerseRowFeature.State.ID, CGFloat) -> Void
    /// 캔버스 영역의 실측 frame(**행 안** `ChapterLayoutHosting.rowCoordinateSpaceName` 좌표) → 상위로 전달. 레이아웃 검증용.
    /// 행 자체의 frame 은 상위가 바깥 트리에서 재어 더한다 (중첩 호스팅 때문 — `rowCoordinateSpaceName` 참조).
    let onCanvasFrameInRowChange: (VerseRowFeature.State.ID, CGRect) -> Void

    
    public init(
        store: StoreOf<SentencesWithDrawingFeature>,
        halfWidth: Binding<CGFloat>,
        isLayoutReady: Bool = true,
        isCanvasActive: Bool = true,
        onUnderlineLayoutChange: @escaping (VerseRowFeature.State.ID, Text.LayoutKey.Value) -> Void,
        onTitleHeightChange: @escaping (VerseRowFeature.State.ID, CGFloat) -> Void = { _, _ in },
        onCanvasFrameInRowChange: @escaping (VerseRowFeature.State.ID, CGRect) -> Void = { _, _ in }
    ) {
        self.store = store
        self._halfWidth = halfWidth
        self.isLayoutReady = isLayoutReady
        self.isCanvasActive = isCanvasActive
        self.onUnderlineLayoutChange = onUnderlineLayoutChange
        self.onTitleHeightChange = onTitleHeightChange
        self.onCanvasFrameInRowChange = onCanvasFrameInRowChange
    }
    
    public var body: some View {
        // 간격은 전부 `ChapterLayoutHosting` 상수로 명시한다 — `ChapterLayoutBuilder` 가 같은 값으로 좌표를 예측한다.
        VStack(spacing: ChapterLayoutHosting.titleSpacing) {
            if store.sentenceState.chapterTitle != nil {
                chapterTitleView
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        onTitleHeightChange(store.id, height)
                    }
            }
            HStack(alignment: .top) {
                if store.isLeftHanded {
                    // 왼손잡이
                    canvasView
                    sentenceView
                } else {
                    // 오른손잡이
                    sentenceView
                    canvasView
                }
            }
            .animation(.easeInOut(duration: 0.3), value: store.isLeftHanded)
            .padding(.vertical, ChapterLayoutHosting.rowVerticalPadding)
        }
        // 행 안 실측의 기준 공간. 아래 touchIgnoringContextMenu 의 중첩 호스팅 안쪽이라 바깥 공간은 보이지 않는다.
        .coordinateSpace(name: ChapterLayoutHosting.rowCoordinateSpaceName)
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
    
    private var sentenceView: some View {
        VerseTextView(
            store: self.store.scope(state: \.sentenceState,
                                    action: \.scope.sentenceAction),
            onLayoutChange: { layout in
                onUnderlineLayoutChange(store.id, layout)
            }
        )
        .frame(width: halfWidth * 0.95, alignment: .leading)
        .padding(.top, topDrawingInset)
    }
    
    private var canvasView: some View {
        ZStack {
            underLineView
            if isCanvasActive {
                CanvasView(
                    store: self.store.scope(state: \.canvasState,
                                            action: \.scope.canvasAction),
                    isInputEnabled: isLayoutReady
                )
            } else {
                Color.clear
            }
        }
        .frame(width: halfWidth, alignment: .topTrailing)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(ChapterLayoutHosting.rowCoordinateSpaceName))
        } action: { frame in
            onCanvasFrameInRowChange(store.id, frame)
        }
    }
    
    private var chapterTitleView: some View {
        Text(store.sentenceState.chapterTitle ?? "")
            .font(.system(size: 22))
            .fontWeight(.heavy)
    }
    
    private var underLineView: some View {
        let underlineOffsets = store.sentenceState.underlineOffsets
        
        return Canvas { context, size in
            for y in underlineOffsets {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y + topDrawingInset))
                path.addLine(to: CGPoint(x: size.width, y: y + topDrawingInset))
                context.stroke(path, with: .color(.gray), style: StrokeStyle(lineWidth: 1, dash: [5]))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 20)
    }
    
}

#Preview {
    @Previewable @State var store = Store(
        initialState: .initialState) {
            SentencesWithDrawingFeature()
        }
    @Previewable @State var halfWidth = UIScreen().bounds.width / 2
    
    SentencesWithDrawingView(
        store: store,
        halfWidth: $halfWidth,
        onUnderlineLayoutChange: { _, layout in
            let offsets =  VerseTextFeature.makeUnderlineOffsets(
                from: layout,
                sentenceSetting: store.sentenceState.sentenceSetting
            )
            store.send(.scope(.sentenceAction(.setUnderlineOffsets(offsets))))
        }
    )
}
