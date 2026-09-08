//
//  SingleCanvasDisplayWiringTesting.swift
//  CarveFeatureTest
//
//  D9 — 합성물이 SwiftUI 를 지나 캔버스까지 가는가 (`updateUIViewController` 배선).
//

import CoreGraphics
import Domain
import Foundation
import PencilKit
import SwiftUI
import Testing
import UIKit

import ComposableArchitecture

@testable import CarveFeature

/// 본문을 코드로 넣는 스텁 (실기기 리소스 대신).
private struct StubBibleTextClient: BibleTextClient {
    let verseCount: Int
    func fetch(chapter: BibleChapter) throws -> [BibleVerse] {
        (1...verseCount).map { verse in
            BibleVerse(title: chapter, sentence: "\(chapter.chapter):\(verse) 이 절은 회전 시 줄 수가 바뀌도록 충분히 길게 만든 본문입니다.")
        }
    }
}

@Suite("D9 — 단일 Canvas 표시 배선")
@MainActor
struct SingleCanvasDisplayWiringTesting {

    /// legacy(v1) 잉크 한 획. 합성이 `columnOrigin` 을 더해 캔버스 좌표로 옮긴다.
    nonisolated private static func legacyRow() -> VerseDrawingSnapshot {
        let stroke = OwnershipTestSupport.stroke(
            from: CGPoint(x: 10, y: 5), to: CGPoint(x: 60, y: 5), seed: 21, creationTime: 1_000
        )
        return VerseDrawingSnapshot(
            verse: 2, rowID: BibleDrawingRowID(raw: "legacy-2"), isPresent: true,
            updateDate: Date(timeIntervalSince1970: 1),
            lineData: PKDrawing(strokes: [stroke]).dataRepresentation(),
            drawingVersion: 1, metadata: nil
        )
    }

    private func makeStore(spy: RepositorySpy) -> StoreOf<CarveDetailFeature> {
        Store(initialState: CarveDetailFeature.State(headerState: .initialState)) {
            CarveDetailFeature()
        } withDependencies: {
            $0.drawingRepository = spy
            $0.drawingCodec = .liveValue
            $0.bibleTextClient = StubBibleTextClient(verseCount: 5)
            $0.undoManager = SharedUndoManager()
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }
    }

    private func findController(_ root: UIViewController?) -> ChapterCanvasController? {
        guard let root else { return nil }
        if let match = root as? ChapterCanvasController { return match }
        for child in root.children {
            if let match = findController(child) { return match }
        }
        return nil
    }

    /// 실기기 회전에 가깝게 — 애니메이션 트랜잭션 안에서 크기를 바꾼다.
    private func rotate(_ window: UIWindow, to size: CGSize) {
        UIView.animate(withDuration: 0.3) {
            window.frame = CGRect(origin: .zero, size: size)
            window.layoutIfNeeded()
        }
    }

    /// SwiftUI 갱신·effect 가 도는 시간을 준다.
    private func pump(_ window: UIWindow, turns: Int = 40) async {
        for _ in 0..<turns {
            window.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    /// 캔버스가 지금 들고 있는 잉크의 x 범위.
    private func canvasInkMinX(_ controller: ChapterCanvasController) -> CGFloat? {
        let bounds = controller.canvas.drawing.bounds
        return (bounds.isNull || bounds.isEmpty) ? nil : bounds.minX
    }

    @Test("실기기 회전 시퀀스 — 재합성된 잉크가 캔버스까지 간다 (합성 출력 == 캔버스 내용)")
    func rotationDeliversRecompositionToCanvas() async throws {
        let suite = "SingleCanvasWiring.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: SingleCanvasFlag.appStorageKey)

        try await withDependencies {
            $0.defaultAppStorage = defaults
        } operation: {
            let spy = RepositorySpy()
            spy.snapshots = { _ in [Self.legacyRow()] }
            let store = makeStore(spy: spy)
            try #require(store.usesSingleCanvas)
            let hosting = UIHostingController(rootView: CarveDetailView(store: store))
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1_200, height: 800))
            window.rootViewController = hosting
            window.isHidden = false
            await pump(window)

            let controller = try #require(findController(hosting), "컨트롤러를 찾지 못했다")

            // ① 가로 진입.
            await pump(window, turns: 60)
            let firstComposed = try #require(store.chapterCanvas.legacyInkBounds)
            #expect(controller.appliedRevision == store.chapterCanvas.renderedRevision)
            #expect(abs(try #require(canvasInkMinX(controller)) - firstComposed.minX) < 0.5)

            // ② 세로로 회전 — 합성 좌표가 Δ columnOrigin 만큼 움직인다.
            rotate(window, to: CGSize(width: 800, height: 1_200))
            await pump(window, turns: 60)
            let portraitComposed = try #require(store.chapterCanvas.legacyInkBounds)
            #expect(portraitComposed.minX != firstComposed.minX)   // 자극이 실제로 걸렸다
            #expect(controller.appliedRevision == store.chapterCanvas.renderedRevision)
            #expect(abs(try #require(canvasInkMinX(controller)) - portraitComposed.minX) < 0.5)

            // ③ 다시 가로 — 실기기에서 화면이 ② 에 머문 지점.
            rotate(window, to: CGSize(width: 1_200, height: 800))
            await pump(window, turns: 60)
            let restoredComposed = try #require(store.chapterCanvas.legacyInkBounds)
            #expect(abs(restoredComposed.minX - firstComposed.minX) < 0.5)
            #expect(controller.appliedRevision == store.chapterCanvas.renderedRevision)
            #expect(abs(try #require(canvasInkMinX(controller)) - restoredComposed.minX) < 0.5)

            window.isHidden = true
        }
    }
}
