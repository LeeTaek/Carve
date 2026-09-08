//
//  SingleCanvasRollbackTesting.swift
//  CarveFeatureTest
//
//  Phase 3 (rev.17) — 설계 §10-3 "V4 저장소를 유지한 채 flag 를 껐을 때 N-Canvas 경로가 정상 동작" (§14 16) 중
//  단일 Canvas 가 쓴 v3(첫 밑줄 원점) 행을 N-Canvas 가 읽고 쓰는 경로, 디코드 불가 행의 비파괴, 팔레트 undo 위임.
//

@testable import CarveFeature
import CoreGraphics
import Domain
import Foundation
import PencilKit
import SwiftData
import Testing
import UIKit

import ComposableArchitecture
import Dependencies

@Suite("Phase 3 — flag off 롤백 경로 (rev.17)")
struct SingleCanvasRollbackTesting {

    private static func stroke() -> PKStroke {
        OwnershipTestSupport.stroke(from: CGPoint(x: 10, y: -5), to: CGPoint(x: 60, y: -5), seed: 1, creationTime: 1_000)
    }

    private static func anchors(_ drawing: PKDrawing) -> [CGPoint] {
        drawing.strokes.compactMap { stroke in stroke.path.first.map { $0.location.applying(stroke.transform) } }
    }

    // MARK: N-Canvas 가 v3 행을 읽고 쓴다

    @Test("v3 행은 첫 밑줄만큼 내려 표시되고, legacy·v2 행은 무변환이다")
    func version3RowsAreDisplayedAtFirstUnderline() {
        let chapter = BibleChapter(title: .micah, chapter: 1)
        let sentence = BibleVerse(title: chapter, verse: 2, sentence: "백성들아 다 들을지어다")
        let row = BibleDrawing(bibleTitle: chapter, verse: 2, lineData: PKDrawing(strokes: [Self.stroke()]).dataRepresentation())
        row.drawingVersion = 3

        var state = CanvasFeature.State(sentence: sentence, drawing: row)
        state.firstUnderlineY = 37.5
        #expect(state.displayTransform == CGAffineTransform(translationX: 0, y: 37.5))

        row.drawingVersion = 1
        #expect(state.displayTransform.isIdentity)
        row.drawingVersion = 2
        #expect(state.displayTransform.isIdentity)

        let none = CanvasFeature.State(sentence: sentence, drawing: nil)
        #expect(none.displayTransform.isIdentity)
    }

    @Test("N-Canvas 가 v3 행을 편집하면 좌상단 원점(v2)으로 내리고 metadata 를 지운다 — 표시 변환도 함께 사라진다")
    func editingVersion3RowDowngradesToVersion2() throws {
        let chapter = BibleChapter(title: .micah, chapter: 2)
        let sentence = BibleVerse(title: chapter, verse: 1, sentence: "그들이 밤에 악을 꾀하며")
        let row = BibleDrawing(bibleTitle: chapter, verse: 1, lineData: PKDrawing(strokes: [Self.stroke()]).dataRepresentation())
        row.drawingVersion = 3
        row.layoutMetadataData = Data([9, 9, 9])

        var state = CanvasFeature.State(sentence: sentence, drawing: row)
        state.firstUnderlineY = 40
        // 캔버스 로컬 좌표(첫 밑줄 5pt 위 = y 35)의 편집 결과.
        let local = PKDrawing(strokes: [
            OwnershipTestSupport.stroke(from: CGPoint(x: 10, y: 35), to: CGPoint(x: 60, y: 35), seed: 2, creationTime: 2_000)
        ])
        _ = CanvasFeature().reduce(into: &state, action: .saveDrawing(local))

        #expect(row.drawingVersion == 2)
        #expect(row.layoutMetadataData == nil)
        #expect(row.lineData == local.dataRepresentation())
        #expect(state.displayTransform.isIdentity)
        #expect(Self.anchors(try PKDrawing(data: try #require(row.lineData))) == [CGPoint(x: 10, y: 35)])
    }

    @Test("legacy 행의 편집은 좌표 형식 표식을 건드리지 않는다")
    func editingLegacyRowKeepsVersion() {
        let chapter = BibleChapter(title: .micah, chapter: 3)
        let sentence = BibleVerse(title: chapter, verse: 1, sentence: "내가 또 이르노니")
        let row = BibleDrawing(bibleTitle: chapter, verse: 1, lineData: PKDrawing().dataRepresentation())
        row.drawingVersion = 1

        var state = CanvasFeature.State(sentence: sentence, drawing: row)
        _ = CanvasFeature().reduce(into: &state, action: .saveDrawing(PKDrawing(strokes: [Self.stroke()])))
        #expect(row.drawingVersion == 1)
    }

    @Test("v3 → v2 로 내린 행을 저장하면 좌표 형식 표식과 metadata 가 DB 에도 반영된다")
    func downgradeIsPersisted() async throws {
        // 저장 경로(DrawingDatabase.testValue)는 프로세스에서 한 번 만들어진 actor 를 쓴다. 검증용 context 는 반드시 **그 actor 의
        // 컨테이너**로 만든다 — `@Dependency(\.modelContainer)` 는 테스트마다 새 인메모리 컨테이너라 실행 순서에 따라 다른 DB 를 본다.
        @Dependency(\.drawingData) var drawingContext
        let actor = drawingContext.actor
        let verifier = SwiftDatabaseActor(modelContainer: actor.modelContainer)
        let chapter = BibleChapter(title: .zephaniah, chapter: 2)
        let verse = 3
        let feature = CarveDetailFeature()

        // given: 단일 Canvas 가 남긴 v3 행.
        let row = BibleDrawing(bibleTitle: chapter, verse: verse, lineData: PKDrawing(strokes: [Self.stroke()]).dataRepresentation())
        row.drawingVersion = 3
        row.layoutMetadataData = try CanvasTestSupport.metadata().encodedBlob()
        try await feature.persistDrawing(row)
        let stored = try await Self.fetch(chapter: chapter, verse: verse, from: verifier)
        #expect(stored.first?.drawingVersion == 3)
        #expect(stored.first?.layoutMetadataData != nil)

        // when: N-Canvas 가 편집해 v2 로 내린다.
        var state = CanvasFeature.State(sentence: BibleVerse(title: chapter, verse: verse, sentence: "가사는 버림을 당하며"), drawing: row)
        _ = CanvasFeature().reduce(into: &state, action: .saveDrawing(PKDrawing(strokes: [Self.stroke()])))
        try await feature.persistDrawing(row)

        // then: 다른 context 에서 읽어도 v2 이고 metadata 가 없다. 이전 구현은 lineData 만 갱신해 v3 표식이 남았다.
        let reloaded = try await Self.fetch(chapter: chapter, verse: verse, from: verifier)
        #expect(reloaded.count == 1)
        #expect(reloaded.first?.drawingVersion == 2)
        #expect(reloaded.first?.layoutMetadataData == nil)

        for stored in try await Self.fetch(chapter: chapter, verse: verse, from: actor) {
            try await actor.delete(stored)
        }
    }

    private static func fetch(chapter: BibleChapter, verse: Int, from actor: SwiftDatabaseActor) async throws -> [BibleDrawing] {
        let titleName = chapter.title.rawValue
        let chapterNumber = chapter.chapter
        let predicate = #Predicate<BibleDrawing> {
            $0.titleName == titleName && $0.titleChapter == chapterNumber && $0.verse == verse
        }
        return try await actor.fetch(FetchDescriptor(predicate: predicate))
    }

    // MARK: 디코드 불가 행

    @Test("디코드할 수 없는 행은 활성 행에서 빠지고, 그 절의 다음 편집은 replace 가 아니라 create 다 — 원본을 덮어쓰지 않는다")
    func undecodableRowIsNotOverwritten() throws {
        let codec = DrawingCodec()
        let layout = OwnershipTestSupport.uniformLayout(verseCount: 4, lineSpace: 30)
        let broken = VerseDrawingSnapshot(
            verse: 2, rowID: BibleDrawingRowID(raw: "broken"), isPresent: true, updateDate: nil,
            lineData: Data([0xDE, 0xAD, 0xBE, 0xEF]), drawingVersion: 3, metadata: CanvasTestSupport.metadata()
        )
        let composed = codec.compose(snapshots: [broken], layout: layout, columnOrigin: .zero)
        #expect(composed.undecodableVerses == [2])
        #expect(composed.activeRowIDs[2] == nil)
        #expect(try PKDrawing(data: composed.data).strokes.isEmpty)

        // layout (10, 35) → verse 2 에 새 획.
        let added = OwnershipTestSupport.stroke(from: CGPoint(x: 10, y: 35), to: CGPoint(x: 20, y: 35), seed: 3, creationTime: 3_000)
        let result = codec.mutations(
            beforeData: composed.data, beforeOwnership: composed.ownership,
            afterData: PKDrawing(strokes: [added]).dataRepresentation(),
            context: DrawingEditContext(layout: layout, columnOrigin: .zero, activeRowIDs: composed.activeRowIDs)
        )
        guard case .create(let verse, let rowID, _, _) = try #require(result.mutations.first) else {
            Issue.record("create 가 아니다"); return
        }
        #expect(verse == 2)
        #expect(rowID.raw != "broken")
    }

    @Test("비워진 행(lineData nil)은 디코드 불가가 아니다 — 활성 행으로 남는다")
    func clearedRowStaysActive() {
        let codec = DrawingCodec()
        let layout = OwnershipTestSupport.uniformLayout(verseCount: 4, lineSpace: 30)
        let cleared = VerseDrawingSnapshot(
            verse: 1, rowID: BibleDrawingRowID(raw: "cleared"), isPresent: true, updateDate: nil,
            lineData: nil, drawingVersion: 3, metadata: CanvasTestSupport.metadata()
        )
        let composed = codec.compose(snapshots: [cleared], layout: layout, columnOrigin: .zero)
        #expect(composed.undecodableVerses.isEmpty)
        #expect(composed.activeRowIDs[1]?.raw == "cleared")
    }

    // MARK: 팔레트 undo 위임

    @Test("undo 가 캔버스에 위임되면 팔레트는 SharedUndoManager 값으로 공유 canUndo/canRedo 를 덮지 않는다")
    func delegatedUndoLeavesSharedFlagsAlone() {
        withDependencies {
            $0.undoManager = SharedUndoManager()   // 비어 있다 — 이전 구현은 이 값(false)으로 덮었다.
        } operation: {
            var state = PencilPalatteFeature.State()
            state.delegatesUndoToCanvas = true
            state.$canUndo.withLock { $0 = true }
            state.$canRedo.withLock { $0 = true }

            _ = PencilPalatteFeature().reduce(into: &state, action: .view(.undo))
            _ = PencilPalatteFeature().reduce(into: &state, action: .setCanUndo)   // 위임 안 된 경로가 보내던 후속 액션
            #expect(state.canUndo)
            #expect(state.canRedo)

            state.delegatesUndoToCanvas = false
            _ = PencilPalatteFeature().reduce(into: &state, action: .setCanUndo)
            #expect(!state.canUndo)
        }
    }

    // MARK: R23 — 장을 여는 것만으로 강등되지 않는다

    /// 실제 `PKCanvasView` 와 delegate 를 붙여 R23 의 경로를 그대로 태운다.
    ///
    /// PencilKit 은 사용자 입력뿐 아니라 **프로그램 대입에도** `canvasViewDrawingDidChange` 를 부른다.
    /// 억제가 없던 구현에서는 장을 열 때 `CanvasView.updateUIView` 의 대입이 곧바로 `.saveDrawing` 으로 이어져
    /// 그 장의 v3 행이 전부 v2 로 강등되고 `layoutMetadataData` 가 지워졌다 (2026-09-08 실기기 실측, 시편 122편 9개 절).
    /// 설계 §10-3 은 **편집할 때만** 강등이다.
    @MainActor
    @Test("프로그램 대입은 편집이 아니다 — v3 행이 강등되지 않고 metadata 도 남는다 (R23)")
    func programmaticApplyDoesNotDowngrade() throws {
        let chapter = BibleChapter(title: .micah, chapter: 4)
        let sentence = BibleVerse(title: chapter, verse: 1, sentence: "끝날에 이르러는")
        let row = BibleDrawing(bibleTitle: chapter, verse: 1, lineData: PKDrawing(strokes: [Self.stroke()]).dataRepresentation())
        row.drawingVersion = 3
        row.layoutMetadataData = try CanvasTestSupport.metadata().encodedBlob()
        let originalLineData = row.lineData

        // `.registUndoCanvas` 가 실제 의존성을 건드리지 않게 주입한다 — 이걸 빼면 변이 시 강등이 아니라
        // "undoManager 에 test 구현이 없다" 로 실패해, 정작 지키려는 계약을 고정하지 못한다.
        let store = withDependencies {
            $0.undoManager = SharedUndoManager()
        } operation: {
            Store(initialState: CanvasFeature.State(sentence: sentence, drawing: row)) { CanvasFeature() }
        }
        let coordinator = CanvasView.Coordinator(store: store)
        let canvas = PKCanvasView()
        canvas.delegate = coordinator

        // when: 표시용 drawing 을 프로그램으로 넣는다 (장 진입에서 일어나는 일).
        coordinator.applyProgrammatically(PKDrawing(strokes: [Self.stroke()]), to: canvas)

        // then: 좌표 형식 표식·metadata·저장 내용이 그대로다.
        #expect(row.drawingVersion == 3)
        #expect(row.layoutMetadataData != nil)
        #expect(row.lineData == originalLineData)
    }

    /// 위 억제가 **너무 넓지 않은지** 를 함께 고정한다. 억제가 delegate 전체를 막아버리면
    /// 실제 필기가 저장되지 않는데, 그 회귀는 위 테스트만으로는 드러나지 않는다.
    @MainActor
    @Test("사용자 편집 콜백은 그대로 저장으로 이어진다 — 억제가 delegate 전체를 막지 않는다 (R23)")
    func userEditStillSaves() async throws {
        let chapter = BibleChapter(title: .micah, chapter: 5)
        let sentence = BibleVerse(title: chapter, verse: 2, sentence: "베들레헴 에브라다야")
        let row = BibleDrawing(bibleTitle: chapter, verse: 2, lineData: PKDrawing(strokes: [Self.stroke()]).dataRepresentation())
        row.drawingVersion = 3
        row.layoutMetadataData = try CanvasTestSupport.metadata().encodedBlob()

        // `.registUndoCanvas` 가 실제 의존성을 건드리지 않게 주입한다 — 이걸 빼면 변이 시 강등이 아니라
        // "undoManager 에 test 구현이 없다" 로 실패해, 정작 지키려는 계약을 고정하지 못한다.
        let store = withDependencies {
            $0.undoManager = SharedUndoManager()
        } operation: {
            Store(initialState: CanvasFeature.State(sentence: sentence, drawing: row)) { CanvasFeature() }
        }
        let coordinator = CanvasView.Coordinator(store: store)
        let canvas = PKCanvasView()
        canvas.delegate = coordinator
        canvas.drawing = PKDrawing(strokes: [
            OwnershipTestSupport.stroke(from: CGPoint(x: 1, y: 2), to: CGPoint(x: 3, y: 4), seed: 7, creationTime: 7_000)
        ])

        // when: 사용자 입력에 해당하는 콜백을 직접 부른다.
        coordinator.canvasViewDrawingDidChange(canvas)

        // then: leading throttle 에 걸리면 trailing debounce(0.3s)로 저장된다. 고정 sleep 대신 값이 바뀔 때까지 폴링한다.
        var downgraded = false
        for _ in 0..<40 where !downgraded {
            if row.drawingVersion == 2 { downgraded = true; break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(downgraded)
        #expect(row.layoutMetadataData == nil)
        #expect(row.lineData == canvas.drawing.dataRepresentation())
    }
}
