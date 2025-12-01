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
        public var title: TitleVO
        /// fetch, update 등 데이터 관리를 위한 배열
        public var drawings: [BibleDrawing] = []
        /// Canvas에 그리기 위한 drawing
        public var combinedDrawing: PKDrawing = PKDrawing()
        /// global 좌표계 기준 CombinedCanvasView의 frame (절 frame → 캔버스 로컬 좌표 변환용)
        public var canvasGlobalFrame: CGRect = .zero

        
        @Shared(.appStorage("pencilConfig")) public var pencilConfig: PencilPalatte = .initialState
        @Shared(.appStorage("allowFingerDrawing")) public var allowFingerDrawing: Bool = false
        @Shared(.inMemory("canUndo")) public var canUndo: Bool = false
        @Shared(.inMemory("canRedo")) public var canRedo: Bool = false
        
        public init(title: TitleVO, drawingRect: [Int: CGRect]) {
            self.title = title
            self.drawingRect = drawingRect
        }
        public static let initialState = Self(title: .initialState, drawingRect: [:])
    }
    @Dependency(\.drawingData) var drawingContext
    @Dependency(\.undoManager) var undoManager

    public enum Action {
        /// SwiftData에서 DrawingData 가져옴
        case fetchDrawingData
        /// Drawing 할당
        case setDrawing([BibleDrawing])
        /// save drawing data
        case saveDrawing(PKDrawing, CGRect)
        /// 캔버스 로컬 좌표계 기준으로 계산된 각 절의 rect 갱신
        case verseFrameUpdated(verse: Int, rect: CGRect)
        /// global 좌표계 기준 CombinedCanvasView의 frame 변경 알림
        case canvasFrameChanged(CGRect)
    }
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .fetchDrawingData:
                state.combinedDrawing = .init()
                return .run { [title = state.title, context = drawingContext] send in
                    let fetchedData = await fetchDrawings(title: title, context: context)
                    await send(.setDrawing(fetchedData))
                }
                
            case .setDrawing(let drawings):
                state.drawings = drawings
                rebuild(state: &state)
                
            case .saveDrawing(let drawing, let changedRect):
                return .run { [title = state.title, verseRects = state.drawingRect, context = drawingContext] _ in
                    await saveDrawing(
                        for: title,
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
                rebuild(state: &state)

            case .canvasFrameChanged(let frame):
                state.canvasGlobalFrame = frame
                return .none
            }
            return .none
        }
    }
}


extension CombinedCanvasFeature {
    /// SwiftData에서 Drawing Fetch
    /// - Parameter title: SwiftData에서 가져올 TitleVO
    /// - Returns: SwiftData에서 가져온 데이터
    private func fetchDrawings(title: TitleVO, context: DrawingDatabase) async -> [BibleDrawing] {
        do {
            let storedDrawing = try await context.fetch(title: title)
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

    /// 그린걸 verse로 저장하는 drawing
    /// 1. Canvas에서 그린 Stroke의 Rect와 drawing을 통으로  받음(CombinedCanvasView - canvasViewDraiwngDidChange)
    /// 2. stroke가 지나간 verse를 찾아서 해당 verse의 drawing을 업데이트 or 새로 생성
    /// 3. SwiftData update
    ///
    /// - Parameters:
    ///   - title: 저장할 drawing
    ///   - changedRect: 새로 그려진 영역의 Rect
    ///   - verseRects: rect가 어떤 절에 있는지 정보
    ///   - canvasDrawing: canvas의 전체 그림 정보
    ///   - context: SwiftData Context
    private func saveDrawing(
        for title: TitleVO,
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
                title: title,
                verse: verse,
                updateLineData: local.dataRepresentation()
            )
            updateDrawingList.append(request)
        }
        await context.updateDraiwngs(requests: updateDrawingList)
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
            
            let bounds = pkDrawing.bounds
            let targetX: CGFloat = 0
            let targetY: CGFloat = rect.minY
            
            let transform = CGAffineTransform(
                translationX: targetX - bounds.minX,
                y: targetY - bounds.minY
            )
            let shifted = pkDrawing.transformed(using: transform)
            merged.append(shifted)
        }
        state.combinedDrawing = merged
    }
    
    
}
