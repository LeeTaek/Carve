//
//  CombinedCanvasFeature.swift
//  CarveFeature
//
//  Created by 이택성 on 11/4/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import CarveToolkit
import Domain
import PencilKit
import UIKit

import ComposableArchitecture

@Reducer
public struct CombinedCanvasFeature {
    @ObservableState
    public struct State {
        /// drawing 그리기 위한 위치 -  [verse: rect]
        public var drawingRect: [Int: CGRect] = [:]
        /// drawing 가져오기 위한 title
        public var chapter: BibleChapter
        /// fetch, update 등 데이터 관리를 위한 배열
        public var drawings: [BibleDrawing] = []
        /// Canvas에 그리기 위한 drawing
        public var combinedDrawing: PKDrawing = PKDrawing()
        /// undo/redo 가능 여부
        public var canUndo: Bool = false
        public var canRedo: Bool = false
        /// undo/redo 요청 트리거용. 
        public var undoVersion: Int = 0
        public var redoVersion: Int = 0
        
        
        @Shared(.appStorage("pencilConfig")) public var pencilConfig: PencilPalatte = .initialState
        @Shared(.appStorage("allowFingerDrawing")) public var allowFingerDrawing: Bool = false
        
        public init(chapter: BibleChapter, drawingRect: [Int: CGRect]) {
            self.chapter = chapter
            self.drawingRect = drawingRect
        }
        public static let initialState = Self(chapter: .initialState, drawingRect: [:])
    }
    @Dependency(\.drawingData) var drawingContext

    public enum Action {
        /// SwiftData에서 DrawingData 가져옴
        case fetchDrawingData
        /// Drawing 할당
        case setDrawing([BibleDrawing])
        /// 페이지 단위 full Drawing 직접 할당
        case setPageDrawing(PKDrawing)
        /// save drawing data
        case saveDrawing(PKDrawing, CGRect)
        /// 캔버스 로컬 좌표계 기준으로 계산된 각 절의 rect 갱신
        case verseFrameUpdated(verse: Int, rect: CGRect)
        /// undo 상태 변경 알림
        case undoStateChanged(canUndo: Bool, canRedo: Bool)
        /// undo
        case undo
        /// redo
        case redo
    }
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .fetchDrawingData:
                return .run { [chapter = state.chapter, context = drawingContext] send in
                    // verse 단위 drawing은 항상 가져옴. (레이아웃 변경 시 재배치의 기준)
                    let fetchedVerseDrawings = await fetchDrawings(chapter: chapter, context: context)

                    // page 단위 full drawing은 "초기 표시" 용 캐시로만 사용.
                    if let pageDrawing = try? await context.fetchPageDrawing(chapter: chapter),
                       let data = pageDrawing.fullLineData,
                       let fullDrawing = try? PKDrawing(data: data) {
                        await send(.setPageDrawing(fullDrawing))
                    }
                }

            case .setDrawing(let drawings):
                state.drawings = drawings
                if !drawings.isEmpty {
                    rebuild(state: &state)
                }
            case .setPageDrawing(let drawing):
                // page drawing은 초기 표시용 캐시로만 사용.
                // verse 단위 drawings는 유지하여, 레이아웃 변경 시 verse 기준 재배치(rebuild)
                state.combinedDrawing = drawing
                
            case .saveDrawing(let drawing, let changedRect):
                state.combinedDrawing = drawing
                
                return .run { [chapter = state.chapter, verseRects = state.drawingRect, context = drawingContext] _ in
                    await saveDrawing(
                        for: chapter,
                        from: changedRect,
                        verseRects: verseRects,
                        canvasDrawing: drawing,
                        context: context
                    )
                }
                
            case .verseFrameUpdated(let verse, let rect):
                if let current = state.drawingRect[verse], current == rect {
                    // 동일한 프레임이면 그냥 무시
                    return .none
                }
                
                state.drawingRect[verse] = rect
                if !state.drawings.isEmpty {
                    rebuild(state: &state)
                }

            case .undoStateChanged(let canUndo, let canRedo):
                state.canUndo = canUndo
                state.canRedo = canRedo
                
            case .undo:
                state.undoVersion &+= 1
                
            case .redo:
                state.redoVersion &+= 1
            }
            return .none
        }
    }
}


extension CombinedCanvasFeature {
    /// SwiftData에서 Drawing Fetch
    /// - Parameter title: SwiftData에서 가져올 TitleVO
    /// - Returns: SwiftData에서 가져온 데이터
    private func fetchDrawings(chapter: BibleChapter, context: DrawingDatabase) async -> [BibleDrawing] {
        do {
            let storedDrawing = try await context.fetch(chapter: chapter)
            // DrawingData가 있는 애들만 거름
            let candidates = storedDrawing.filter { $0.lineData?.containsPKStroke == true }
            
            Log.debug("candidates", candidates.map { $0.verse })
            
            // 한 절에 여러 Drawing이 있는 경우 필터링
            let filteredDrawings: [BibleDrawing] = Dictionary(grouping: candidates, by: \.verse)
                .compactMap { $0.value.mainDrawing() }
                .sorted(by: { ($0.verse ?? 0) < ($1.verse ?? 0) })
            return filteredDrawings
        } catch {
            Log.error("Fetch Drawing Error", error)
            return []
        }
    }

    /// 그린걸 verse 단위로 나누어 저장하고, 페이지단위 full drawing도 함께 업데이트
    /// 1. Canvas에서 그린 Stroke의 Rect와 drawing을 통으로 받음(CombinedCanvasView - canvasViewDraiwngDidChange)
    /// 2. stroke가 지나간 verse를 찾아서 해당 verse의 drawing을 업데이트 or 새로 생성
    /// 3. SwiftData update
    ///
    /// - Parameters:
    ///   - chapter: 저장할 drawing
    ///   - changedRect: 새로 그려진 영역의 Rect
    ///   - verseRects: rect가 어떤 절에 있는지 정보
    ///   - canvasDrawing: canvas의 전체 그림 정보
    ///   - context: SwiftData Context
    private func saveDrawing(
        for chapter: BibleChapter,
        from changedRect: CGRect,
        verseRects: [Int: CGRect],
        canvasDrawing: PKDrawing,
        context: DrawingDatabase
    ) async {
        // 어떤 verse가 변경되었는지 찾기
        let affectedVerse = verseRects.filter { $0.value.intersects(changedRect) }
        guard !affectedVerse.isEmpty else { return }
            
        // drawing이 여러 절을 지나갈 경우 지나간 해당 절의 drawing data temp
        var updateDrawingList: [DrawingUpdateRequest] = []
        
        for (verse, rect) in affectedVerse {
            Log.debug("drawing이 지나간 verse", verse)
            
            // 캔버스에서 해당 절의 영역에 있는 drawing clipping
            let clipped = canvasDrawing.clippedPrecisely(to: rect)
            guard !clipped.strokes.isEmpty else { continue }

            // 절 rect의 Origin 만큼 빼서 로컬좌표 기준으로 변환
            let local = clipped.transformed(
                using: CGAffineTransform(
                    translationX: -rect.minX,
                    y: -rect.minY
                )
            )
            
            let request = DrawingUpdateRequest(
                chapter: chapter,
                verse: verse,
                updateLineData: local.dataRepresentation()
            )
            updateDrawingList.append(request)
        }
        await context.updateDrawings(requests: updateDrawingList)
        // 페이지 단위 fullUpdate
        await context.upsertPageDrawing(
            chapter: chapter,
            fullLineData: canvasDrawing.dataRepresentation()
        )
    }
    
    
    
    /// DrawingRect와 verse별 drawing 기반으로 combinedDrawing 생성
    /// 레이아웃/좌표가 변경될때마다 호출되어 verse위치 반영한 하나의 PKDrawing 로 merge
    /// - Parameter state: 현재 상태값
    private func rebuild(state: inout State) {
        guard !state.drawings.isEmpty, !state.drawingRect.isEmpty else {
            state.combinedDrawing = PKDrawing()
            return
        }
        
        var merged = PKDrawing()
        
        for (verse, rect) in state.drawingRect.sorted(by: { $0.key < $1.key }) {
            guard let drawing = state.drawings.first(where: { $0.verse == verse }),
                  let data = drawing.lineData,
                  let pkDrawing = try? PKDrawing(data: data)
            else { continue }
            
            let transform = CGAffineTransform(
                translationX: rect.minX,
                y: rect.minY
            )
            let shifted = pkDrawing.transformed(using: transform)
            merged.append(shifted)
        }
        state.combinedDrawing = merged
    }
    
    
}
