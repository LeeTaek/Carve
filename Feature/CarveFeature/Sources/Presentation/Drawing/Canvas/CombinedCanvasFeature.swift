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
import ClientInterfaces

import ComposableArchitecture

@Reducer
public struct CombinedCanvasFeature {
    @ObservableState
    public struct State {
        /// drawing 그리기 위한 위치 -  [verse: rect]
        public var drawingRect: [Int: CGRect] = [:]
        /// underline 첫 라인의 y offset (verse 기준)
        public var verseFirstUnderlineOffsets: [Int: CGFloat] = [:]
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
    @Dependency(\.analyticsClient) var analyticsClient

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
        /// underline offset 변경 (레이아웃 변경 시)
        case verseUnderlineOffsetsUpdated(verse: Int, offsets: [CGFloat])
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
                return .run { [chapter = state.chapter, context = drawingContext, analyticsClient = analyticsClient] send in
                    analyticsClient.trackFeatureEntry(
                        .carve,
                        extra: [
                            "title_name": .string(chapter.title.rawValue),
                            "title_chapter": .int(chapter.chapter)
                        ]
                    )
                    
                    // 1) Fetch verse drawing. (레이아웃 변경 시 재배치의 기준)
                    let fetchedVerseDrawings = await fetchDrawings(chapter: chapter, context: context)

                    // 2) page 단위 full drawing은 "초기 표시" 용 캐시로만 사용.
                    do {
                        if let pageDrawing = try await context.fetchPageDrawing(chapter: chapter),
                           let data = pageDrawing.fullLineData {
                            do {
                                let fullDrawing = try PKDrawing(data: data)
                                await send(.setPageDrawing(fullDrawing))
                            } catch {
                                analyticsClient.trackErrorShown(
                                    .canvasDrawingDecodeFailed,
                                    feature: .carve,
                                    context: "CombinedCanvasFeature.fetchDrawingData.pageDrawingDecode",
                                    message: error.localizedDescription,
                                    extra: [
                                        "title_name": .string(chapter.title.rawValue),
                                        "title_chapter": .int(chapter.chapter)
                                    ]
                                )
                                Log.error("❌ pageDrawing decode failed:", error)
                            }
                        }
                    } catch {
                        // SwiftData fetch 자체가 실패한 케이스
                        analyticsClient.trackErrorShown(
                            .swiftDataOperationFailed,
                            feature: .domain,
                            context: "CombinedCanvasFeature.fetchDrawingData",
                            message: error.localizedDescription,
                            extra: [
                                "title_name": .string(chapter.title.rawValue),
                                "title_chapter": .int(chapter.chapter)
                            ]
                        )
                        Log.error("❌ fetchPageDrawing failed:", error)
                    }
                    
                    // 3) verse drawing을 state에 주입. (이후 verseFrameUpdated 시 rebuild)
                    await send(.setDrawing(fetchedVerseDrawings))
                }

            case .setDrawing(let drawings):
                state.drawings = drawings
                if !state.verseFirstUnderlineOffsets.isEmpty {
                    for index in state.drawings.indices {
                        guard state.drawings[index].baseFirstUnderlineOffset == nil,
                              let verse = state.drawings[index].verse,
                              let offset = state.verseFirstUnderlineOffsets[verse]
                        else { continue }
                        state.drawings[index].baseFirstUnderlineOffset =
                            Double(offset + DrawingLayoutMetrics.clipTopPadding)
                    }
                }
                if !state.drawingRect.isEmpty {
                    for index in state.drawings.indices {
                        guard let verse = state.drawings[index].verse,
                              let rect = state.drawingRect[verse]
                        else { continue }
                        if state.drawings[index].baseWidth == nil {
                            state.drawings[index].baseWidth = Double(rect.width)
                        }
                        if state.drawings[index].baseHeight == nil {
                            state.drawings[index].baseHeight = Double(rect.height)
                        }
                    }
                }

                // 첫 진입 시에는 rebuild를 호출하면 rebuild의 guard에 걸려 combinedDrawing을 비워
                // "처음 진입 시 그림이 안 보이는" 현상이 발생할 수 있으므로,
                // rect가 준비된 이후(verseFrameUpdated) 또는 이미 준비된 경우에만 rebuild.
                if canRebuild(state) {
                    rebuild(state: &state)
                }
            case .setPageDrawing(let drawing):
                // page drawing은 초기 표시용 캐시로만 사용.
                // verse 단위 drawings는 유지하여, 레이아웃 변경 시 verse 기준 재배치(rebuild)
                state.combinedDrawing = drawing
                
            case .saveDrawing(let drawing, let changedRect):
                state.combinedDrawing = drawing
                
                return .run { [
                    chapter = state.chapter,
                    verseRects = state.drawingRect,
                    verseOffsets = state.verseFirstUnderlineOffsets,
                    context = drawingContext,
                    analyticsClient = analyticsClient
                ] _ in
                    let updatedVerseCount = await saveDrawing(
                        for: chapter,
                        from: changedRect,
                        verseRects: verseRects,
                        verseFirstUnderlineOffsets: verseOffsets,
                        canvasDrawing: drawing,
                        context: context
                    )
                    analyticsClient.trackFeatureComplete(
                        .carve,
                        success: true,
                        extra: [
                            "title_name": .string(chapter.title.rawValue),
                            "title_chapter": .int(chapter.chapter),
                            "updated_verse_count": .int(updatedVerseCount)
                        ]
                    )
                }
                
            case .verseFrameUpdated(let verse, let rect):
                let current = state.drawingRect[verse]
                let rectChanged = !rectApproximatelyEqual(current, rect, tolerance: 0.5)
                if rectChanged {
                    state.drawingRect[verse] = rect
                }

                var didUpdate = rectChanged
                if let index = state.drawings.firstIndex(where: { $0.verse == verse }) {
                    if state.drawings[index].baseWidth == nil {
                        state.drawings[index].baseWidth = Double(rect.width)
                        didUpdate = true
                    }
                    if state.drawings[index].baseHeight == nil {
                        state.drawings[index].baseHeight = Double(rect.height)
                        didUpdate = true
                    }
                }

                if didUpdate {
                    if canRebuild(state) {
                        rebuild(state: &state)
                    } else if let currentRect = state.drawingRect[verse] {
                        replaceDrawing(
                            state: &state,
                            verse: verse,
                            rect: currentRect,
                            previousRect: current
                        )
                    }
                }

            case .verseUnderlineOffsetsUpdated(let verse, let offsets):
                let newFirst = offsets.first
                if state.verseFirstUnderlineOffsets[verse] == newFirst {
                    return .none
                }

                if let newFirst {
                    state.verseFirstUnderlineOffsets[verse] = newFirst
                } else {
                    state.verseFirstUnderlineOffsets.removeValue(forKey: verse)
                }

                if let index = state.drawings.firstIndex(where: { $0.verse == verse }),
                   state.drawings[index].baseFirstUnderlineOffset == nil,
                   let newFirst {
                    state.drawings[index].baseFirstUnderlineOffset =
                        Double(newFirst + DrawingLayoutMetrics.clipTopPadding)
                }

                if canRebuild(state) {
                    rebuild(state: &state)
                } else if let rect = state.drawingRect[verse] {
                    replaceDrawing(
                        state: &state,
                        verse: verse,
                        rect: rect,
                        previousRect: rect
                    )
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
    private enum DrawingLayoutMetrics {
        static let clipTopPadding: CGFloat = 8
    }

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
    /// - Return: 업데이트 된 verse count (analytics용)
    @discardableResult
    private func saveDrawing(
        for chapter: BibleChapter,
        from changedRect: CGRect,
        verseRects: [Int: CGRect],
        verseFirstUnderlineOffsets: [Int: CGFloat],
        canvasDrawing: PKDrawing,
        context: DrawingDatabase
    ) async -> Int {
        // 어떤 verse가 변경되었는지 찾기
        let captureRects = captureRects(from: verseRects)
        let affectedVerse = captureRects.filter { $0.value.intersects(changedRect) }
        guard !affectedVerse.isEmpty else { return 0 }
            
        // drawing이 여러 절을 지나갈 경우 지나간 해당 절의 drawing data temp
        var updateDrawingList: [DrawingUpdateRequest] = []
        
        for (verse, captureRect) in affectedVerse {
            guard let rect = verseRects[verse] else { continue }
            Log.debug("drawing이 지나간 verse", verse)
            
            // 캔버스에서 해당 절의 영역에 있는 drawing clipping
            let topPadding: CGFloat = DrawingLayoutMetrics.clipTopPadding
            let horizontalInset = VerseLayoutMetrics.underlineHorizontalInset
            let contentRect = captureRect.insetBy(dx: horizontalInset, dy: 0)
            guard contentRect.width > 0 else { continue }
            let paddedRect = CGRect(
                x: contentRect.minX,
                y: captureRect.minY - topPadding,
                width: contentRect.width,
                height: captureRect.height + topPadding
            )
            let clipped = canvasDrawing.clippedPrecisely(to: paddedRect)
            guard !clipped.strokes.isEmpty else { continue }

            // 절 rect의 Origin 만큼 빼서 로컬좌표 기준으로 변환
            let originY = rect.minY - topPadding
            let local = clipped.transformed(
                using: CGAffineTransform(
                    translationX: -rect.minX,
                    y: -originY
                )
            )
            
            let baseFirstUnderlineOffset = verseFirstUnderlineOffsets[verse].map {
                Double($0 + topPadding)
            }
            let request = DrawingUpdateRequest(
                chapter: chapter,
                verse: verse,
                updateLineData: local.dataRepresentation(),
                baseWidth: Double(rect.width),
                baseHeight: Double(rect.height),
                baseFirstUnderlineOffset: baseFirstUnderlineOffset
            )
            updateDrawingList.append(request)
        }
        await context.updateDrawings(requests: updateDrawingList)
        // 페이지 단위 fullUpdate
        await context.upsertPageDrawing(
            chapter: chapter,
            fullLineData: canvasDrawing.dataRepresentation()
        )
        return updateDrawingList.count
    }
    
    
    
    /// DrawingRect와 verse별 drawing 기반으로 combinedDrawing 생성
    /// 레이아웃/좌표가 변경될때마다 호출되어 verse위치 반영한 하나의 PKDrawing 로 merge
    private func rebuild(state: inout State) {
        // verse drawing 자체가 없으면 비움.
        guard !state.drawings.isEmpty else {
            state.combinedDrawing = PKDrawing()
            return
        }
        // rect가 아직 준비되지 않았으면(초기 진입/첫 렌더링)
        // page-cache(combinedDrawing)를 유지.
        guard !state.drawingRect.isEmpty else {
            return
        }

        let signpostID = PerformanceLog.begin("CombinedCanvas.Rebuild")
        defer { PerformanceLog.end("CombinedCanvas.Rebuild", signpostID) }

        var merged = PKDrawing()

        for (verse, rect) in state.drawingRect.sorted(by: { $0.key < $1.key }) {
            guard let verseDrawing = state.drawings.first(where: { $0.verse == verse }),
                  let data = verseDrawing.lineData,
                  let local = try? PKDrawing(data: data)
            else { continue }

            let placed = placedDrawing(
                local: local,
                verseDrawing: verseDrawing,
                rect: rect,
                targetFirstUnderlineOffset: state.verseFirstUnderlineOffsets[verse]
            )
            merged.append(placed)
        }

        // rect 준비/매칭 이슈로 merged가 비는 경우 pageDrawing(캐시)을 빈 그림으로 덮어쓰지 않도록.
        guard !merged.strokes.isEmpty else { return }
        state.combinedDrawing = merged
    }
    
    
    /// rebuild를 수행해도 되는지 판단: 실제 drawing이 있는 verse들의 rect가 준비되어 있어야 함.
    private func canRebuild(_ state: State) -> Bool {
        let verses = Set(state.drawings.compactMap { $0.verse })
        guard !verses.isEmpty else { return false }
        return verses.allSatisfy { verse in
            guard let rect = state.drawingRect[verse] else { return false }
            return !rect.isNull && !rect.isEmpty
        }
    }

    /// verse별 underline rect(실제 텍스트/밑줄 영역)를 기반으로, "캡처(저장)"에 사용할 확장 rect를 만든다.
    ///
    /// 왜 필요한가?
    /// - 사용자가 획을 그릴 때, 스트로크의 `changedRect`가 정확히 특정 verse rect 내부에만 머물지 않고
    ///   절 사이의 간격(패딩/줄 간격)이나 경계 근처를 스치면서 넘어갈 수 있다.
    /// - 이때 단순히 underline rect로만 `intersects` 판정하면, 경계 영역에 그린 스트로크가
    ///   어떤 verse에도 속하지 않아 저장이 누락될 수 있다.
    ///
    /// 동작 방식
    /// - 각 verse rect를 Y축 기준으로 정렬한 뒤,
    /// - 인접한 두 rect의 경계(midpoint)를 기준으로 위/아래 영역을 나눠
    ///   verse별 "캡처 영역"이 서로 빈틈 없이 이어지도록 만든다.
    /// - 결과적으로 절과 절 사이의 공간에서도 스트로크가 어느 한 verse의 캡처 영역에 포함되어
    ///   저장 대상(affectedVerse)으로 안정적으로 잡히도록 돕는다.
    ///
    /// - Parameter verseRects: 캔버스 로컬 좌표 기준의 verse별 underline rect.
    /// - Returns: verse별 캡처 rect. 인접 verse 사이를 midpoint로 분할하여 gap이 생기지 않는다.
    private func captureRects(from verseRects: [Int: CGRect]) -> [Int: CGRect] {
        let sorted = verseRects.sorted { $0.value.minY < $1.value.minY }
        guard !sorted.isEmpty else { return [:] }

        var result: [Int: CGRect] = [:]
        for index in sorted.indices {
            let (verse, rect) = sorted[index]
            let top: CGFloat
            if index == sorted.startIndex {
                top = rect.minY
            } else {
                let prevRect = sorted[sorted.index(before: index)].value
                top = (prevRect.maxY + rect.minY) / 2
            }

            let bottom: CGFloat
            if index == sorted.index(before: sorted.endIndex) {
                bottom = rect.maxY
            } else {
                let nextRect = sorted[sorted.index(after: index)].value
                bottom = (rect.maxY + nextRect.minY) / 2
            }

            let height = bottom - top
            guard height > 0 else { continue }
            result[verse] = CGRect(x: rect.minX, y: top, width: rect.width, height: height)
        }
        return result
    }

    /// CGRect의 동등성 비교.
    /// - Parameters:
    ///   - lhs: 기존 rect(옵셔널). nil이면 비교 불가로 false 반환.
    ///   - rhs: 새로 측정된 rect.
    ///   - tolerance: 허용 오차(pt). 기본은 호출부에서 0.5pt 사용.
    /// - Returns: 네 변(minX/minY/width/height)이 tolerance 이내로 같으면 true.
    private func rectApproximatelyEqual(
        _ lhs: CGRect?,
        _ rhs: CGRect,
        tolerance: CGFloat
    ) -> Bool {
        guard let lhs else { return false }
        return abs(lhs.minX - rhs.minX) <= tolerance &&
            abs(lhs.minY - rhs.minY) <= tolerance &&
            abs(lhs.width - rhs.width) <= tolerance &&
            abs(lhs.height - rhs.height) <= tolerance
    }
    
    /// 특정 verse의 드로잉만 부분 업데이트로 교체.
    /// - Parameters:
    ///   - state: reducer state(inout). `combinedDrawing`이 갱신된다.
    ///   - verse: 교체할 verse 번호.
    ///   - rect: 현재 레이아웃에서의 verse rect.
    ///   - previousRect: 이전 rect. 있는 경우 `union`하여 제거 범위를 넓혀 잔여 스트로크를 방지한다.
    private func replaceDrawing(
        state: inout State,
        verse: Int,
        rect: CGRect,
        previousRect: CGRect?
    ) {
        guard let verseDrawing = state.drawings.first(where: { $0.verse == verse }),
              let data = verseDrawing.lineData,
              let local = try? PKDrawing(data: data)
        else { return }

        let placed = placedDrawing(
            local: local,
            verseDrawing: verseDrawing,
            rect: rect,
            targetFirstUnderlineOffset: state.verseFirstUnderlineOffsets[verse]
        )

        let removalRect = previousRect.map { $0.union(rect) } ?? rect
        let expandedRemovalRect = CGRect(
            x: removalRect.minX,
            y: removalRect.minY - DrawingLayoutMetrics.clipTopPadding,
            width: removalRect.width,
            height: removalRect.height + DrawingLayoutMetrics.clipTopPadding
        )
        state.combinedDrawing = removingStrokes(
            from: state.combinedDrawing,
            intersecting: expandedRemovalRect
        )
        state.combinedDrawing.append(placed)
    }
    
    /// verse 단위로 저장된 "로컬 좌표" 드로잉을, 현재 레이아웃의 verse rect에 맞게 배치(스케일/오프셋).
    /// - Parameters:
    ///   - local: verse 로컬 좌표계로 저장된 PKDrawing.
    ///   - verseDrawing: 저장 메타데이터(baseWidth/baseHeight/baseFirstUnderlineOffset 등) 포함.
    ///   - rect: 현재 레이아웃에서의 verse rect(캔버스 로컬 좌표).
    ///   - targetFirstUnderlineOffset: 현재 verse의 첫 underline y offset(verse 기준).
    /// - Returns: `rect` 위치에 맞게 변환된 PKDrawing.
    private func placedDrawing(
        local: PKDrawing,
        verseDrawing: BibleDrawing,
        rect: CGRect,
        targetFirstUnderlineOffset: CGFloat?
    ) -> PKDrawing {
        // 로컬 drawing의 bounds origin을 (0,0)으로 정규화
        // 저장 시 -rect.minX/-rect.minY를 했더라도, 실제 stroke bounds가 0부터 시작하지 않을 수 있음
        let normalized = local

        let horizontalInset = VerseLayoutMetrics.underlineHorizontalInset
        let targetContentWidth = rect.width - horizontalInset * 2

        let scaleX: CGFloat
        if let bw = verseDrawing.baseWidth, bw > 0, targetContentWidth > 0 {
            let baseContentWidth = max(1, CGFloat(bw) - horizontalInset * 2)
            // baseWidth가 있으면 underline 폭 기준으로 확대/축소 모두 허용
            scaleX = targetContentWidth / baseContentWidth
        } else {
            // fallback(bounds 기반)에서는 확대 금지(축소만 허용)
            // 한 글자/짧은 필사가 과하게 늘어나는 문제 방지
            let width = normalized.bounds.width
            if width > 0, targetContentWidth > 0 {
                scaleX = min(1, targetContentWidth / width)
            } else {
                scaleX = 1
            }
        }

        let topPadding = DrawingLayoutMetrics.clipTopPadding
        let baseAnchor = verseDrawing.baseFirstUnderlineOffset.map { CGFloat($0) }
        let targetAnchor = targetFirstUnderlineOffset.map { $0 + topPadding }
        let hasBaseline = baseAnchor != nil && targetAnchor != nil
        let anchorFrom = baseAnchor ?? 0
        let anchorTo = hasBaseline ? (targetAnchor ?? 0) : 0

        let scaleY: CGFloat
        if hasBaseline {
            let contentDepth = normalized.bounds.maxY - anchorFrom
            if contentDepth > 0 {
                let maxAllowedY = rect.height + topPadding
                let requiredScale = (maxAllowedY - anchorTo) / contentDepth
                scaleY = min(1, max(0, requiredScale))
            } else {
                scaleY = 1
            }
        } else if let bh = verseDrawing.baseHeight, bh > 0 {
            // baseHeight 기준으로 축소만 허용
            let ratio = rect.height / CGFloat(bh)
            scaleY = min(1, ratio)
        } else {
            // fallback(bounds 기반)에서는 Y 스케일을 적용하지 않음.
            scaleY = 1
        }

        let scaled = normalized.transformed(
            using: CGAffineTransform(translationX: -horizontalInset, y: -anchorFrom)
                .scaledBy(x: scaleX, y: scaleY)
                .translatedBy(x: horizontalInset, y: anchorTo)
        )
        return scaled.transformed(
            using: CGAffineTransform(translationX: rect.minX, y: rect.minY)
        )
    }

    /// `drawing`에서 주어진 `rect`와 교차하는 스트로크를 제거한 새 `PKDrawing`을 만든다.
    /// - Parameters:
    ///   - drawing: 현재 합쳐진 combined drawing.
    ///   - rect: 제거 대상으로 간주할 영역.
    /// - Returns: 교차 스트로크가 제거된 새 PKDrawing.
    private func removingStrokes(from drawing: PKDrawing, intersecting rect: CGRect) -> PKDrawing {
        let kept = drawing.strokes.filter { !$0.renderBounds.intersects(rect) }
        return PKDrawing(strokes: kept)
    }
}
