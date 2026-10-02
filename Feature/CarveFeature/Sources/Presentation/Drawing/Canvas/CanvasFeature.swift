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

// N-Canvas(절마다 PKCanvasView) 경로. 단일 Canvas 는 ChapterCanvasView 가 대체하며, flag off 롤백용으로 유지한다 (설계 §10-3).
@Reducer
public struct CanvasFeature: Sendable {
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
        /// 이 절 캔버스 로컬 좌표의 첫 밑줄 y (`writingRect` 상단 기준). 상위(`CarveDetailFeature`)가 실측으로 채운다.
        ///
        /// 단일 Canvas 는 절 행을 **첫 밑줄 원점**(`drawingVersion == 3`)으로 저장한다. flag 를 끄고 N-Canvas 로 돌아오면(§10-3)
        /// 그 행을 좌상단 원점으로 읽어 첫 밑줄만큼 위로 어긋나므로, 표시할 때 이 값만큼 내린다.
        public var firstUnderlineY: CGFloat = 0
        @Shared(.codableAppStorage("pencilConfig")) public var pencilConfig: PencilPalatte = .initialState
        @Shared(.inMemory("canUndo")) public var canUndo: Bool = false
        @Shared(.inMemory("canRedo")) public var canRedo: Bool = false
        @Shared(.appStorage("allowFingerDrawing")) public var allowFingerDrawing: Bool = false
        public init(sentence: BibleVerse, drawing: BibleDrawing?) {
            self.id = "drawingData.\(sentence.sentenceScript)"
            self.drawing = drawing
            self.title = sentence.title
            self.verse = sentence.verse
        }
        /// @Model(`BibleDrawing`)을 담아 Sendable 이 아니므로 저장 프로퍼티 대신 계산 프로퍼티다(N-Canvas).
        public static var initialState: Self {
            Self(sentence: .initialState,
                 drawing: .init(bibleTitle: .initialState,
                                verse: 1))
        }

        /// 저장 좌표 → 캔버스 로컬 좌표 변환. v3(첫 밑줄 원점) 행만 첫 밑줄만큼 내리고 그 밖(legacy · v2)은 무변환이다.
        public var displayTransform: CGAffineTransform {
            drawing?.drawingVersion == 3
                ? CGAffineTransform(translationX: 0, y: firstUnderlineY)
                : .identity
        }
    }
    
    @Dependency(\.undoManager) private var undoManager

    public enum Action {
        case saveDrawing(PKDrawing)
        case registUndoCanvas(PKCanvasView)
        /// 이전 필사 기록에서 회차를 골랐다 — 그 행을 이 절의 캔버스에 올린다.
        case setDrawing(VerseDrawingSnapshot)
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
                    if drawing.drawingVersion == 3 {
                        // N-Canvas 는 캔버스 로컬(writingRect 좌상단) 좌표를 쓴다 — 설계 §10-1 의 v2 다.
                        // 첫 밑줄 원점의 v3 행을 여기서 편집하면 v2 로 내린다. metadata 는 이 좌표를 설명하지 않으므로 함께 지운다.
                        // 단일 Canvas 가 다음 편집 때 다시 v3 + metadata 로 올린다 (§10-2 정책 5).
                        drawing.drawingVersion = 2
                        drawing.layoutMetadataData = nil
                    }
                } else {
                    // 아직 기록이 없는 절인데 빈 canvas 변경이 올라온 경우(초기 렌더링 등)에는
                    // 새 기록을 만들지 않는다. 실제로 획이 그려진 뒤에만 생성한다.
                    guard !newDrawing.strokes.isEmpty else { return .none }
                    state.drawing = BibleDrawing(bibleTitle: state.title,
                                                 verse: state.verse,
                                                 lineData: newDrawing.dataRepresentation())
                }
            case .registUndoCanvas(let canvas):
                // `SharedUndoManager` · `PKCanvasView` 는 MainActor 타입이다. 리듀서는 스토어(MainActor)에서 돈다.
                let undoState: (canUndo: Bool, canRedo: Bool)? = MainActor.assumeIsolated {
                    if undoManager.isPerformingUndoRedo {
                        undoManager.isPerformingUndoRedo = false
                        return nil
                    }
                    undoManager.registerUndoAction(for: canvas)
                    return (undoManager.canUndo, undoManager.canRedo)
                }
                guard let undoState else { return .none }
                state.$canUndo.withLock { $0 = undoState.canUndo }
                state.$canRedo.withLock { $0 = undoState.canRedo }
            case .setDrawing(let snapshot):
                state.drawing = Self.legacyDrawing(from: snapshot, chapter: state.title)
            }
            return .none
        }
    }

    /// 이력 화면이 고른 행(DTO)을 N-Canvas 가 들고 쓰는 행 모양으로 옮긴다.
    ///
    /// 저장소의 모델은 actor 밖으로 나오지 않으므로(룰북 swiftdata.md 규칙 3 · 4) 값으로 새로 만든다. 저장소에 넣지 않는 값 운반용이다 —
    /// 이어지는 편집은 `CarveDetailFeature.makeLegacyDrawingSaveRequest` 가 행 키(`rowKey`)로 저장하므로, 행 키를 그대로 실어
    /// **고른 행**에 저장되게 한다(새 행이 아니다). 표시 변환(`displayTransform`)이 좌표 형식을 보므로 그것도 옮긴다.
    /// - Parameters:
    ///   - snapshot: 고른 회차.
    ///   - chapter: 이 절의 성경 · 장.
    /// - Returns: 고른 행과 같은 행 키 · 내용 · 좌표 형식을 가진 모델. 부작용 없음.
    static func legacyDrawing(from snapshot: VerseDrawingSnapshot, chapter: BibleChapter) -> BibleDrawing {
        let drawing = BibleDrawing(
            bibleTitle: chapter,
            verse: snapshot.verse,
            lineData: snapshot.lineData,
            updateDate: snapshot.updateDate,
            layoutMetadataData: try? snapshot.metadata?.encodedBlob(),
            rowUUID: snapshot.rowID.raw
        )
        drawing.drawingVersion = snapshot.drawingVersion
        drawing.isPresent = snapshot.isPresent
        return drawing
    }
}
