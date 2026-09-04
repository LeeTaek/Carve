//
//  DrawingErasePersistenceTesting.swift
//  CarveFeatureTest
//
//  "지우개로 획을 전부 지운 뒤 재기동하면 지웠던 획이 되살아난다" 회귀 방지 테스트.
//
//  원인은 두 곳이 겹쳐 있었다.
//  1) 저장 가드가 `lineData?.containsPKStroke == true` 를 요구해, 마지막 획을 지운 순간 저장 자체를 건너뜀
//  2) `canvasViewDrawingDidChange` 의 leading-edge throttle 이 제스처의 마지막 변경을 버림
//

@testable import CarveFeature
import CarveToolkit
import Domain
import Foundation
import PencilKit
import SwiftData
import Testing
import UIKit

import ComposableArchitecture
import Dependencies

@Suite("지우개로 전부 지운 결과의 영속화")
struct DrawingErasePersistenceTesting {

    private enum Failure: Error {
        /// 저장된 lineData 가 없어 stroke 수를 셀 수 없음
        case missingLineData
        /// 해당 절의 대표 drawing 을 찾지 못함
        case missingDrawing
    }

    // MARK: - 전제 확인

    @Test("획을 전부 지운 drawing 은 containsPKStroke == false 다 (예전 저장 가드가 막던 조건)")
    func fullyErasedDrawingHasNoStroke() {
        #expect(PKDrawing().dataRepresentation().containsPKStroke == false)
        #expect(PKDrawing(strokes: [Self.makeStroke()]).dataRepresentation().containsPKStroke == true)
    }

    // MARK: - 저장 경로

    @Test("획이 하나도 없는 drawing 도 저장 경로를 통과해 영속화된다")
    func emptyDrawingIsPersisted() async throws {
        @Dependency(\.createSwiftDataActor) var actor
        @Dependency(\.modelContainer) var container

        // 앱 재기동 상황을 흉내내기 위해 별도 context 로 확인한다.
        // 같은 context 로 읽으면 저장(save) 여부와 무관하게 메모리상의 변경이 그대로 보이기 때문이다.
        let verifier = SwiftDatabaseActor(modelContainer: container)

        let chapter = BibleChapter(title: .habakkuk, chapter: 2)
        let verse = 4
        let feature = CarveDetailFeature()

        // given: 획이 있는 상태로 한 번 저장한다.
        let drawing = BibleDrawing(
            bibleTitle: chapter,
            verse: verse,
            lineData: PKDrawing(strokes: [Self.makeStroke()]).dataRepresentation()
        )
        try await feature.persistDrawing(drawing)
        let afterDraw = try await Self.fetch(chapter: chapter, verse: verse, from: verifier)
        let afterDrawStrokes = try Self.strokeCount(of: afterDraw)
        #expect(afterDrawStrokes == 1)

        // when: 지우개로 전부 지운 상태(= stroke 0개인 유효한 PKDrawing)를 저장한다.
        drawing.lineData = PKDrawing().dataRepresentation()
        drawing.updateDate = Date()
        try await feature.persistDrawing(drawing)

        // then: 다른 context 에서 다시 읽어도 획이 되살아나지 않는다.
        let reloaded = try await Self.fetch(chapter: chapter, verse: verse, from: verifier)
        let reloadedStrokes = try Self.strokeCount(of: reloaded)
        #expect(reloaded.count == 1)
        #expect(reloadedStrokes == 0)

        // teardown
        for row in try await Self.fetch(chapter: chapter, verse: verse, from: actor) {
            try await actor.delete(row)
        }
    }

    @Test("drawing 이 없으면(nil) 저장을 시도하지 않는다")
    func nilDrawingIsNotPersisted() async throws {
        @Dependency(\.drawingData) var drawingContext

        let chapter = BibleChapter(title: .obadiah, chapter: 1)
        try await CarveDetailFeature().persistDrawing(nil)

        let stored = try await drawingContext.fetch(chapter: chapter)
        #expect(stored.isEmpty)
    }

    // MARK: - 대표 drawing 선택

    @Test("전부 지운 최신 기록이 있으면 더 오래된 기록이 대표로 되살아나지 않는다")
    func erasedLatestDrawingIsChosenOverOlderStrokedDrawing() throws {
        let chapter = BibleChapter(title: .nahum, chapter: 1)
        let sentence = BibleVerse(title: chapter, verse: 3, sentence: "여호와는 노하기를 더디하시며")

        let old = BibleDrawing(
            bibleTitle: chapter,
            verse: 3,
            lineData: PKDrawing(strokes: [Self.makeStroke()]).dataRepresentation(),
            updateDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let erased = BibleDrawing(
            bibleTitle: chapter,
            verse: 3,
            lineData: PKDrawing().dataRepresentation(),
            updateDate: Date(timeIntervalSince1970: 1_700_000_100)
        )

        let selected: BibleDrawing? = withDependencies {
            $0.undoManager = SharedUndoManager()
        } operation: {
            var state = CarveDetailFeature.State.initialState
            _ = CarveDetailFeature().reduce(
                into: &state,
                action: .setSentence([sentence], [old, erased])
            )
            return state.sentenceWithDrawingState.first?.canvasState.drawing
        }

        #expect(selected === erased)
        #expect(try Self.strokeCount(of: selected) == 0)
    }

    // MARK: - 빈 canvas 로 인한 불필요한 기록 생성

    @Test("기록이 없는 절에 빈 canvas 변경이 올라와도 새 기록을 만들지 않는다")
    func emptyCanvasDoesNotCreateNewRecord() {
        var state = CanvasFeature.State(sentence: .initialState, drawing: nil)

        _ = CanvasFeature().reduce(into: &state, action: .saveDrawing(PKDrawing()))
        #expect(state.drawing == nil)

        _ = CanvasFeature().reduce(
            into: &state,
            action: .saveDrawing(PKDrawing(strokes: [Self.makeStroke()]))
        )
        #expect(state.drawing != nil)

        // 한 번 기록이 생긴 뒤에는 전부 지운 상태(획 0개)도 그대로 반영된다.
        _ = CanvasFeature().reduce(into: &state, action: .saveDrawing(PKDrawing()))
        let strokes = try? Self.strokeCount(of: state.drawing)
        #expect(strokes == 0)
    }

    // MARK: - throttle 로 인한 마지막 변경 유실

    @MainActor
    @Test("throttle 에 걸린 마지막 변경(= 전부 지움)도 trailing 저장으로 반드시 반영된다")
    func trailingSaveFlushesThrottledChange() async throws {
        try await withDependencies {
            $0.undoManager = SharedUndoManager()
        } operation: {
            let store = Store(
                initialState: CanvasFeature.State(
                    sentence: .initialState,
                    drawing: BibleDrawing(bibleTitle: BibleVerse.initialState.title, verse: 1)
                )
            ) {
                CanvasFeature()
            }
            let coordinator = CanvasView(store: store).makeCoordinator()
            let canvas = PKCanvasView()

            // 0) coordinator 생성 직후의 throttle 구간을 지나 보낸다.
            try await Task.sleep(for: .milliseconds(400))

            // 1) 획을 하나 그린다 → leading edge 라 즉시 저장된다.
            canvas.drawing = PKDrawing(strokes: [Self.makeStroke()])
            coordinator.canvasViewDrawingDidChange(canvas)
            let afterDraw = try Self.strokeCount(of: store.drawing)
            #expect(afterDraw == 1)

            // 2) 방금 저장한 직후(= throttle 구간 안)에 지우개로 전부 지운다 → 즉시 반영되지 않는다.
            canvas.drawing = PKDrawing()
            coordinator.canvasViewDrawingDidChange(canvas)
            let afterThrottledErase = try Self.strokeCount(of: store.drawing)
            #expect(afterThrottledErase == 1, "leading-edge throttle 이라 이 시점에는 아직 반영되지 않아야 한다")

            // 3) trailing 저장이 최종 상태를 반영한다.
            try await Task.sleep(for: .milliseconds(600))
            let afterTrailingSave = try Self.strokeCount(of: store.drawing)
            #expect(afterTrailingSave == 0)
        }
    }

    // MARK: - 헬퍼

    private static func makeStroke() -> PKStroke {
        let points = (0..<8).map { index in
            PKStrokePoint(
                location: CGPoint(x: Double(index) * 10, y: 0),
                timeOffset: Double(index) * 0.02,
                size: CGSize(width: 4, height: 4),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        let path = PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 1_700_000_000))
        return PKStroke(ink: PKInk(.pencil, color: .black), path: path)
    }

    private static func strokeCount(of drawing: BibleDrawing?) throws -> Int {
        guard let data = drawing?.lineData else { throw Failure.missingLineData }
        return try PKDrawing(data: data).strokes.count
    }

    private static func strokeCount(of drawings: [BibleDrawing]) throws -> Int {
        guard let main = drawings.mainDrawing() else { throw Failure.missingDrawing }
        return try strokeCount(of: main)
    }

    /// 주어진 actor(= ModelContext)에서 해당 절의 필사 기록을 읽는다.
    private static func fetch(
        chapter: BibleChapter,
        verse: Int,
        from actor: SwiftDatabaseActor
    ) async throws -> [BibleDrawing] {
        let titleName = chapter.title.rawValue
        let titleChapter = chapter.chapter
        let predicate = #Predicate<BibleDrawing> {
            $0.titleName == titleName
            && $0.titleChapter == titleChapter
            && $0.verse == verse
        }
        return try await actor.fetch(FetchDescriptor(predicate: predicate))
    }
}
