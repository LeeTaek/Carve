//
//  ChapterCanvasHistoryEditTesting.swift
//  CarveFeatureTest
//
//  팔레트의 Undo/Redo 와 저장 상태 표시 (리뷰 P2-6).
//
//  일반 필기는 도구 시작에 `editBegan` 이 나가 Feature 가 편집 중(= 미저장)으로 안다. Undo/Redo 는 도구 사용 없이
//  drawing 을 바꾸므로 trailing 보고(0.3초)가 나갈 때까지 Feature 는 아무것도 모르고 "이 기기에 저장됨" 을 유지했다.
//  Feature 에 편집 액션을 직접 보내는 테스트로는 이 틈이 보이지 않는다 — **컨트롤러 경계를 태운다.**
//

import Domain
import Foundation
import PencilKit
import Testing
import UIKit

import ComposableArchitecture

@testable import CarveFeature

@Suite("Undo/Redo — 보고 전에도 미저장으로 보인다")
@MainActor
struct ChapterCanvasHistoryEditTesting {

    /// 창에 붙인 컨트롤러 — 응답자 사슬에 undoManager 가 있어야 팔레트의 Undo/Redo 경로(`performHistory`)가 돈다.
    /// 이벤트는 앱과 같은 코디네이터로 Feature 에 넘긴다.
    @MainActor
    private final class Harness {
        let controller = ChapterCanvasController()
        let store: StoreOf<ChapterCanvasFeature>
        let coordinator: ChapterCanvasView.Coordinator
        private(set) var events: [ChapterCanvasController.Event] = []
        private let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 1200))
        private var undoVersion = 0
        private var redoVersion = 0

        init() {
            var state = ChapterCanvasFeature.State(chapter: CanvasTestSupport.chapter)
            // 앞서 쓴 필사가 저장까지 끝난 상태 — 표시는 "이 기기에 저장됨".
            state.editRevision = 1
            state.persistedRevision = 1
            store = Store(initialState: state) {
                ChapterCanvasFeature()
            } withDependencies: {
                $0.drawingCodec = CanvasTestSupport.codec(results: LockIsolated([]))
                $0.drawingRepository = RepositorySpy()
                $0.uuid = .incrementing
                $0.date = .constant(Date(timeIntervalSince1970: 1_000))
            }
            coordinator = ChapterCanvasView.Coordinator(store: store, onScroll: { _, _ in })
            controller.view.frame = window.bounds
            window.rootViewController = controller
            window.isHidden = false
            controller.loadViewIfNeeded()
            controller.onEvent = { [unowned self] event in
                self.events.append(event)
                self.coordinator.handle(event)
            }
            apply()
        }

        func teardown() {
            window.isHidden = true
        }

        func apply() {
            controller.apply(ChapterCanvasController.Configuration(
                renderedData: nil, renderedRevision: 1, isInputEnabled: true,
                tool: PKInkingTool(.pen), drawingPolicy: .anyInput, topInset: 0, bottomInset: 24,
                undoRequestVersion: undoVersion, redoRequestVersion: redoVersion, scrollRequest: nil, layout: nil
            ))
        }

        /// 팔레트의 Undo 버튼 — Feature 가 요청 번호를 올리고, 뷰 갱신이 그 번호로 컨트롤러를 부른다.
        func tapUndo() {
            undoVersion += 1
            apply()
        }

        func tapRedo() {
            redoVersion += 1
            apply()
        }

        var editBeganCount: Int {
            events.filter { if case .editBegan = $0 { return true } else { return false } }.count
        }
        var editEnded: [CanvasEditSnapshot] {
            events.compactMap { if case .editEnded(let snapshot) = $0 { return snapshot } else { return nil } }
        }
        var cancelledCount: Int {
            events.filter { if case .editCancelled = $0 { return true } else { return false } }.count
        }
    }

    private func stroke(y: CGFloat) -> PKStroke {
        OwnershipTestSupport.stroke(from: CGPoint(x: 10, y: y), to: CGPoint(x: 60, y: y), seed: UInt32(y), creationTime: Double(y))
    }

    /// 캔버스 내용을 `after` 로 바꾸고, 그것을 되돌리는 undo 동작을 등록한다 — PencilKit 의 획 등록도 결국 drawing 을 바꾼다.
    /// 등록 뒤 한 턴을 넘겨 자동 undo 그룹이 닫히게 한다.
    private func registerUndoableChange(_ harness: Harness, to after: PKDrawing) async throws -> UndoManager {
        let canvas = harness.controller.canvas
        let undoManager = try #require(canvas.undoManager, "창에 붙은 캔버스는 undoManager 를 가진다")
        let before = canvas.drawing
        canvas.drawing = after
        undoManager.registerUndo(withTarget: canvas) { target in
            let redone = target.drawing
            target.drawing = before
            undoManager.registerUndo(withTarget: target) { $0.drawing = redone }
        }
        try await Task.sleep(for: .milliseconds(450))
        #expect(undoManager.canUndo)
        return undoManager
    }

    @Test("Undo 로 내용이 바뀌면 trailing 보고 전에 편집 구간이 열려 '저장 대기 중' 이 된다")
    func undoShowsPendingBeforeTrailingReport() async throws {
        let harness = Harness()
        defer { harness.teardown() }
        _ = try await registerUndoableChange(harness, to: PKDrawing(strokes: [stroke(y: 40)]))
        let beganBefore = harness.editBeganCount
        let endedBefore = harness.editEnded.count
        #expect(harness.store.localSaveIndicator == .saved)

        harness.tapUndo()
        #expect(harness.controller.canvas.drawing.strokes.isEmpty)
        try await Task.sleep(for: .milliseconds(50))

        // ★ 보고(0.3초)는 아직이다. 이전 구현은 여기서 아무 이벤트도 없어 "이 기기에 저장됨" 이 남았다.
        #expect(harness.editEnded.count == endedBefore)
        #expect(harness.editBeganCount == beganBefore + 1)
        #expect(harness.store.localSaveIndicator == .pending)

        // 보고가 나가면 그 편집은 Undo 로 표시되고 편집 구간이 닫힌다.
        try await Task.sleep(for: .milliseconds(450))
        #expect(harness.editEnded.count == endedBefore + 1)
        #expect(harness.editEnded.last?.reason == .undo)
        #expect(!harness.store.isEditing)
    }

    @Test("되돌릴 것이 없으면 편집 구간을 열지 않는다 — 닫는 보고가 오지 않아 '저장 대기 중' 에 갇히지 않게")
    func undoWithNothingToUndoOpensNothing() async throws {
        let harness = Harness()
        defer { harness.teardown() }
        let undoManager = try #require(harness.controller.canvas.undoManager)
        undoManager.removeAllActions()
        #expect(!undoManager.canUndo)

        harness.tapUndo()
        try await Task.sleep(for: .milliseconds(450))

        #expect(harness.editBeganCount == 0)
        #expect(harness.editEnded.isEmpty)
        #expect(harness.cancelledCount == 0)
        #expect(!harness.store.isEditing)
        #expect(harness.store.localSaveIndicator == .saved)
    }

    @Test("Redo 도 같다")
    func redoShowsPendingBeforeTrailingReport() async throws {
        let harness = Harness()
        defer { harness.teardown() }
        _ = try await registerUndoableChange(harness, to: PKDrawing(strokes: [stroke(y: 40)]))
        harness.tapUndo()
        try await Task.sleep(for: .milliseconds(450))
        let beganBefore = harness.editBeganCount
        let endedBefore = harness.editEnded.count

        harness.tapRedo()
        #expect(harness.controller.canvas.drawing.strokes.count == 1)
        try await Task.sleep(for: .milliseconds(50))

        #expect(harness.editEnded.count == endedBefore)
        #expect(harness.editBeganCount == beganBefore + 1)
        #expect(harness.store.localSaveIndicator == .pending)

        try await Task.sleep(for: .milliseconds(450))
        #expect(harness.editEnded.last?.reason == .redo)
        #expect(!harness.store.isEditing)
    }
}
