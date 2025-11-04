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
        public var title: TitleVO = .initialState
        /// fetch, update 등 데이터 관리를 위한 배열
        public var drawings: [BibleDrawing] = []
        /// Canvas에 그리기 위한 drawing
        public var combinedDrawing: PKDrawing = PKDrawing()
        
        @Shared(.appStorage("pencilConfig")) public var pencilConfig: PencilPalatte = .initialState
        @Shared(.appStorage("allowFingerDrawing")) public var allowFingerDrawing: Bool = false
        @Shared(.inMemory("canUndo")) public var canUndo: Bool = false
        @Shared(.inMemory("canRedo")) public var canRedo: Bool = false
        
        public init(drawingRect: [Int: CGRect]) {
            self.drawingRect = drawingRect
        }
        public static let initialState = Self(drawingRect: [:])
    }
    @Dependency(\.drawingData) var drawingContext
    @Dependency(\.undoManager) var undoManager

    public enum Action: ViewAction {
        case view(View)
        /// SwiftData에서 DrawingData 가져옴
        case fetchDrawingData
        /// Drawing 할당
        case setDrawing([BibleDrawing])
        /// DrawingData를 canvase에 그림
        case drawToCanvas

        public enum View {
        }
    }
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .fetchDrawingData:
                return .run { [title = state.title] send in
                    let fetchedData = await fetchDrawings(title: title)
                    Log.debug("fetchedData", fetchedData)
                    await send(.setDrawing(fetchedData))
                }
            
            case .setDrawing(let drawings):
                state.drawings = drawings
                return .send(.drawToCanvas)
                
            case .drawToCanvas:
                state.combinedDrawing = mergeDrawings(state.drawings, verseFrame: state.drawingRect)
                
            case .view(_:): break
            }
            return .none
        }
    }
    

}


extension CombinedCanvasFeature {
    /// SwiftData에서 Drawing Fetch
    /// - Parameter title: SwiftData에서 가져올 TitleVO
    /// - Returns: SwiftData에서 가져온 데이터
    private func fetchDrawings(title: TitleVO) async -> [BibleDrawing] {
        do {
            let storedDrawing = try await drawingContext.fetch(title: title)
            // DrawingData가 있는 애들만 거름
            let candidates = storedDrawing.filter { $0.lineData?.containsPKStroke == true }
            // 한 절에 여러 Drawing이 있는 경우 필터링
            let filteredDrawings: [BibleDrawing] = Dictionary(grouping: candidates, by: \.verse)
                .compactMap { (_, drawings) in
                    // isPresent가 있으면 그 데이터로 가져옴
                    if let active = drawings.first(where: { $0.isPresent == true }) {
                        return active
                    }
                    // isPresent 설정이 안되어 있으면 가장 최근 업데이트 된 데이터를 가져옴
                    return drawings.max {
                        ($0.updateDate ?? .distantPast) > ($1.updateDate ?? .distantPast)
                    }
                }
                .sorted(by: { ($0.verse ?? 0) < ($1.verse ?? 0) })
            return filteredDrawings
        } catch {
            Log.error("Fetch Drawing Error", error)
            return []
        }
    }
    
    
    /// 여러개의 BibleDrawing의 drawingData를 하나로 통합
    /// - Parameters:
    ///   - drawings: 필사 데이터
    ///   - verseFrame: 각 절의 drawing 위치
    /// - Returns: 통합된 하나의 drawing
    private func mergeDrawings(_ drawings: [BibleDrawing], verseFrame: [Int: CGRect]) -> PKDrawing {
        var mergedDrawing = PKDrawing()

        for (verse, frame) in verseFrame {
            Log.debug(verse)
            guard let drawing = drawings.first(where: { $0.verse == verse }),
                  let data = drawing.lineData,
                  let pkDrawing = try? PKDrawing(data: data)
            else { continue }
            
            Log.debug("frame", frame)
            guard frame.width > 0, frame.height > 0 else { continue }
            
            let transform = CGAffineTransform(
                translationX: frame.minX,
                y: frame.minY
            )
            let shifted = pkDrawing.transformed(using: transform)
            mergedDrawing.append(shifted)
        }
        return mergedDrawing
    }
}
