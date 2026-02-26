//
//  CombinedCanvasFeatureTests.swift
//  CarveFeatureTests
//

@testable import CarveFeature
@testable import Domain
import PencilKit
import Testing
import UIKit

import ComposableArchitecture

struct CombinedCanvasFeatureTests {
    @Test
    func verseFrameUpdated_doesNotDuplicateStrokeAboveVerseRect() throws {
        var state = CombinedCanvasFeature.State(
            chapter: .initialState,
            drawingRect: [:]
        )
        let reducer = CombinedCanvasFeature()

        let verseOneDrawing = BibleDrawing(
            bibleTitle: .initialState,
            verse: 1,
            lineData: try makeDrawingData(
                from: CGPoint(x: 30, y: -6),
                to: CGPoint(x: 60, y: -4)
            )
        )
        let verseTwoDrawing = BibleDrawing(
            bibleTitle: .initialState,
            verse: 2,
            lineData: nil
        )

        _ = reducer.reduce(into: &state, action: .setDrawing([verseOneDrawing, verseTwoDrawing]))
        _ = reducer.reduce(
            into: &state,
            action: .verseUnderlineOffsetsUpdated(verse: 1, offsets: [12])
        )

        _ = reducer.reduce(
            into: &state,
            action: .verseFrameUpdated(
                verse: 1,
                rect: CGRect(x: 10, y: 100, width: 120, height: 24)
            )
        )
        #expect(state.combinedDrawing.strokes.count == 1)

        _ = reducer.reduce(
            into: &state,
            action: .verseFrameUpdated(
                verse: 1,
                rect: CGRect(x: 10, y: 101, width: 120, height: 24)
            )
        )

        #expect(state.combinedDrawing.strokes.count == 1)
    }

}

private func makeDrawingData(from start: CGPoint, to end: CGPoint) throws -> Data {
    let path = PKStrokePath(
        controlPoints: [
            .init(
                location: start,
                timeOffset: 0,
                size: .init(width: 1, height: 1),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: 0
            ),
            .init(
                location: end,
                timeOffset: 1,
                size: .init(width: 1, height: 1),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: 0
            )
        ],
        creationDate: Date()
    )
    let stroke = PKStroke(ink: PKInk(.pen, color: .black), path: path)
    return PKDrawing(strokes: [stroke]).dataRepresentation()
}
