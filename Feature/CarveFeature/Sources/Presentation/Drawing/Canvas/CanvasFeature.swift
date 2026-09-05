//
//  CanvasReducer.swift
//  FeatureCarve
//
//  Created by 이택성 on 2/23/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import CarveToolkit
import Domain
import PencilKit
import UIKit

import ComposableArchitecture

//@available(*, deprecated, message: "CombinedCanvasView / CombinedCanvasFeature로 대체")
@Reducer
public struct CanvasFeature {
    @ObservableState
    public struct State: Identifiable {
        public var id: String
        public var drawing: BibleDrawing?
        public var title: BibleChapter
        public var verse: Int
        /// 마지막으로 캔버스에서 올라온 drawing 의 bounds (**이 절 캔버스의 로컬 좌표**).
        ///
        /// Phase 2 디버그 오버레이가 `dirtyBounds` 로 표시하는 값이다. 빈 drawing 이면 nil.
        /// 저장·소유권 판정에는 쓰지 않는다 — 그 계약(§8-1 `CanvasEditSnapshot.dirtyBounds`)은 Phase 3 의 것이다.
        public var lastDrawingBounds: CGRect?
        @Shared(.appStorage("pencilConfig")) public var pencilConfig: PencilPalatte = .initialState
        @Shared(.inMemory("canUndo")) public var canUndo: Bool = false
        @Shared(.inMemory("canRedo")) public var canRedo: Bool = false
        @Shared(.appStorage("allowFingerDrawing")) public var allowFingerDrawing: Bool = false
        public init(sentence: BibleVerse, drawing: BibleDrawing?) {
            self.id = "drawingData.\(sentence.sentenceScript)"
            self.drawing = drawing
            self.title = sentence.title
            self.verse = sentence.verse
        }
        public static let initialState = Self(sentence: .initialState,
                                              drawing: .init(bibleTitle: .initialState,
                                                             verse: 1))
    }
    
    @Dependency(\.undoManager) private var undoManager

    public enum Action {
        case saveDrawing(PKDrawing)
        case registUndoCanvas(PKCanvasView)
        case setDrawing(BibleDrawing)
    }

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .saveDrawing(let newDrawing):
                let bounds = newDrawing.bounds
                state.lastDrawingBounds = (bounds.isNull || bounds.isEmpty) ? nil : bounds
                if let drawing = state.drawing {
                    // 기존 기록은 획이 0개여도 그대로 반영한다.
                    // (지우개로 전부 지운 결과가 저장되지 않으면 재기동 시 획이 되살아난다.)
                    drawing.lineData = newDrawing.dataRepresentation()
                    drawing.updateDate = Date.now
                } else {
                    // 아직 기록이 없는 절인데 빈 canvas 변경이 올라온 경우(초기 렌더링 등)에는
                    // 새 기록을 만들지 않는다. 실제로 획이 그려진 뒤에만 생성한다.
                    guard !newDrawing.strokes.isEmpty else { return .none }
                    state.drawing = BibleDrawing(bibleTitle: state.title,
                                                 verse: state.verse,
                                                 lineData: newDrawing.dataRepresentation())
                }
            case .registUndoCanvas(let canvas):
                if undoManager.isPerformingUndoRedo {
                    undoManager.isPerformingUndoRedo = false
                    return .none
                }
                undoManager.registerUndoAction(for: canvas)
                state.$canUndo.withLock { $0 = undoManager.canUndo }
                state.$canRedo.withLock { $0 = undoManager.canRedo }
            case .setDrawing(let drawing):
                state.drawing = drawing
            }
            return .none
        }
    }

}
