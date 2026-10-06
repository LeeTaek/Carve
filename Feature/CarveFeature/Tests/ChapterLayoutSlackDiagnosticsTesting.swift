//
//  ChapterLayoutSlackDiagnosticsTesting.swift
//  CarveFeatureTest
//
//  진단 — 저장 당시 줄 수가 지금보다 많은 절(slack) (2026-09-14 실기기 시편 119편 Δ 195.63)
//  그런 절도 레이아웃은 텍스트 줄 수만큼만 짓는다(설계 §6-3 — 초과 필기는 reflow 가 절 안에 줄여 넣는다, §9-3).
//  레이아웃이 저장 필사를 따라 늘지 않아 행과 어긋나지 않는지(Δ 0), HUD 가 초과 절을 보이는지를 고정한다.
//

import CoreGraphics
import Domain
import Foundation
import Testing

import ComposableArchitecture

@testable import CarveFeature

@Suite("진단 — 저장 줄 수 초과(slack) 절")
struct ChapterLayoutSlackDiagnosticsTesting {
    private let chapter = BibleChapter(title: .genesis, chapter: 1)
    private let setting = SentenceSetting.initialState
    private let metrics = ChapterLayoutHosting.metrics
    /// 줄 띠 폭(`SentenceSetting.linePitch`).
    private var pitch: CGFloat { setting.linePitch }
    private let clock = ContinuousClock()

    /// 절 `verse` 가 `lineCount` 줄일 때 Reducer 가 넘기는 anchor (topPadding 포함, 30pt 간격).
    private func anchors(verse: Int, lineCount: Int) -> [CGFloat] {
        let padding = ChapterLayoutHosting.topPadding(forVerse: verse)
        return (1...lineCount).map { padding + CGFloat($0) * 30 }
    }

    private func rebuild(_ measurement: inout ChapterLayoutMeasurement) -> ChapterLayout? {
        measurement.rebuildIfComplete(setting: setting, isLeftHanded: false, metrics: metrics, now: clock.now)
    }

    /// 텍스트 실측과 폭까지 넣고 레이아웃을 지은 측정. 행 frame 은 아직 없다 (예측 높이).
    /// - Parameters:
    ///   - lineCounts: 절 → 텍스트 줄 수. 절 순서는 절 번호 오름차순이다.
    ///   - savedBandCounts: 절 → 저장 band 수.
    /// - Returns: 측정과 그 레이아웃.
    private func built(
        lineCounts: [Int: Int],
        savedBandCounts: [Int: Int] = [:]
    ) throws -> (measurement: ChapterLayoutMeasurement, layout: ChapterLayout) {
        var measurement = ChapterLayoutMeasurement()
        measurement.begin(chapter: chapter, verses: lineCounts.keys.sorted(), savedBandCounts: savedBandCounts, now: clock.now)
        measurement.setWritingWidth(300)
        for (verse, lineCount) in lineCounts {
            measurement.recordText(verse: verse, underlineAnchors: anchors(verse: verse, lineCount: lineCount))
        }
        let rebuilt = rebuild(&measurement)
        let layout = try #require(rebuilt)
        return (measurement, layout)
    }

    /// 뷰가 쌓는 대로 행을 기록한다 — 캔버스 영역은 행 원점에 붙고 행 사이는 `metrics` 의 여백이다.
    ///
    /// 레이아웃과 무관하게 **캔버스 영역 높이만으로** 행 위치를 정한다. 그래서 Δ 가 0 이면 레이아웃이 그려진 행을 따른 것이다.
    private func recordRows(_ measurement: inout ChapterLayoutMeasurement, canvasHeights: [Int: CGFloat]) {
        var top = metrics.topInset
        for verse in canvasHeights.keys.sorted() {
            let height = canvasHeights[verse] ?? 0
            measurement.recordCanvasFrameInRow(verse: verse, frame: CGRect(x: 0, y: 0, width: 300, height: height))
            measurement.recordRowFrame(verse: verse, frame: CGRect(x: 380, y: top, width: 600, height: height))
            top += height + metrics.verseSpacing
        }
    }

    @Test("slack 은 저장 band 가 텍스트 줄 수보다 많은 절만 세고, 레이아웃은 저장 필사가 없을 때와 같다")
    func reflowSlacksCountOnlyVersesBeyondTheirLines() throws {
        // 1절 저장 3 > 1줄(+2) · 2절 저장 1 = 1줄(없음) · 3절 저장 없음 · 4절 저장 3 > 2줄(+1)
        let lineCounts = [1: 1, 2: 1, 3: 2, 4: 2]
        let plain = try built(lineCounts: lineCounts)
        let slack = try built(lineCounts: lineCounts, savedBandCounts: [1: 3, 2: 1, 4: 3])

        #expect(slack.measurement.reflowSlacks == [
            ChapterLayoutMeasurement.ReflowSlack(verse: 1, extraBands: 2),
            ChapterLayoutMeasurement.ReflowSlack(verse: 4, extraBands: 1)
        ])
        #expect(slack.measurement.hasReflowSlack)
        // 절 간격이 일정해야 한다 — 저장 필사가 절 높이를 바꾸지 않는다 (2026-09-15 전에는 3줄만큼 늘었다).
        #expect(slack.layout == plain.layout)
        #expect(plain.measurement.reflowSlacks.isEmpty)
        #expect(!plain.measurement.hasReflowSlack)
    }

    @Test("텍스트 실측이 아직 없는 절은 slack 으로 세지 않는다")
    func reflowSlacksSkipVersesWithoutTextMeasurement() {
        var measurement = ChapterLayoutMeasurement()
        measurement.begin(chapter: chapter, verses: [1, 2], savedBandCounts: [1: 3, 2: 3], now: clock.now)
        measurement.recordText(verse: 1, underlineAnchors: anchors(verse: 1, lineCount: 1))

        #expect(measurement.reflowSlacks == [ChapterLayoutMeasurement.ReflowSlack(verse: 1, extraBands: 2)])
    }

    @Test("slack 이 있어도 텍스트대로 쌓인 행과 레이아웃이 맞아 Δ 가 0 이고 안전망이 열린다 — 실기기 시편 119편의 계단이 없다")
    func slackKeepsRowsAndLayoutAligned() throws {
        // 1절 저장 band 3 > 1줄. 2026-09-15 전에는 레이아웃만 2줄 늘어 2·3절 상단이 2줄씩 어긋났다.
        var measurement = try built(lineCounts: [1: 1, 2: 1, 3: 1], savedBandCounts: [1: 3]).measurement
        recordRows(&measurement, canvasHeights: [1: pitch, 2: pitch, 3: pitch])
        let rebuilt = rebuild(&measurement)
        let layout = try #require(rebuilt)

        #expect(abs(layout.regions[0].writingRect.height - pitch) < 0.001)
        #expect(measurement.frameDeltas.count == 3)
        #expect(measurement.frameDeltas.allSatisfy { $0.magnitude < 0.001 })
        let verdict = try #require(measurement.layoutDeltaVerdict)
        #expect(!verdict.blocksInput)
    }

    #if DEBUG
    @MainActor
    @Test("HUD 콘솔 스냅샷에 slack 절별 초과 band 수가 남고 deltaMax 는 0 이다")
    func consoleSnapshotReportsSlackBands() throws {
        var measurement = try built(lineCounts: [1: 1, 2: 1, 3: 1], savedBandCounts: [1: 3]).measurement
        recordRows(&measurement, canvasHeights: [1: pitch, 2: pitch, 3: pitch])
        _ = rebuild(&measurement)
        let snapshot = ChapterLayoutDebugHUD(measurement: measurement, lastEdit: nil).consoleSnapshot

        #expect(snapshot.contains("slack=true slackBands=[v1:+2]"))
        #expect(snapshot.contains("deltaMax=0.00"))
        #expect(!snapshot.contains("slackAdjusted"))
    }
    #endif
}

// MARK: - 저장 band 수의 출처 (2.1 N-Canvas 제거 뒤)

/// slack 진단의 저장 band 수(`N_saved`)는 2.0.x 까지 N-Canvas 가 읽은 행(@Model)에서 왔다. 2.1 은 그 조회를 지웠으므로
/// **단일 Canvas 가 읽은 장의 행**(`ChapterCanvasFeature.State.loadedDrawings`)의 metadata 에서 센다.
/// 출처를 잃으면 HUD 의 slack 이 오류 없이 늘 비게 된다 — 그것을 막는 자리다.
@Suite("진단 — slack 의 저장 band 수는 단일 Canvas 가 읽은 행에서 온다")
@MainActor
struct ChapterLayoutSlackSourceTesting {
    private let chapter = BibleChapter(title: .genesis, chapter: 1)

    nonisolated private static func metadata(bands: Int) -> DrawingLayoutMetadata {
        DrawingLayoutMetadata(
            baseWritingWidth: 372, baseWritingHeight: CGFloat(bands) * 30,
            baseUnderlineAnchors: (0..<bands).map { CGFloat($0) * 30 }, layoutSignature: "cl1-test"
        )
    }

    nonisolated private static func row(
        verse: Int, key: String, isPresent: Bool, updatedAt: TimeInterval, version: Int?, bands: Int?
    ) -> VerseDrawingSnapshot {
        VerseDrawingSnapshot(
            verse: verse, rowID: BibleDrawingRowID(raw: key), isPresent: isPresent,
            updateDate: Date(timeIntervalSince1970: updatedAt), lineData: Data([1]),
            drawingVersion: version, metadata: bands.map(metadata(bands:))
        )
    }

    /// 1절 legacy(metadata 없음) · 2절 v3 4줄 · 3절 대표가 metadata 없는 v2(보관된 v3 5줄은 대표가 아니다).
    nonisolated private static func chapterRows() -> [VerseDrawingSnapshot] {
        [
            row(verse: 1, key: "legacy-1", isPresent: true, updatedAt: 10, version: 1, bands: nil),
            row(verse: 2, key: "v3-2", isPresent: true, updatedAt: 20, version: 3, bands: 4),
            row(verse: 3, key: "archived-v3-3", isPresent: false, updatedAt: 5, version: 3, bands: 5),
            row(verse: 3, key: "current-v2-3", isPresent: true, updatedAt: 30, version: 2, bands: nil)
        ]
    }

    @Test("저장 band 수는 절마다 대표 행의 metadata 에서만 센다 — metadata 없는 대표 · 보관 행은 세지 않는다")
    func savedBandCountsComeFromRepresentativeMetadata() {
        #expect(CarveDetailFeature.savedBandCounts(from: Self.chapterRows()) == [2: 4])
        #expect(CarveDetailFeature.savedBandCounts(from: []).isEmpty)
    }

    @Test("다른 장에서 읽은 band 수는 지금 측정에 넣지 않는다 — 늦게 온 이전 장 결과")
    func updateSavedBandCountsIgnoresOtherChapter() {
        var measurement = ChapterLayoutMeasurement()
        measurement.begin(chapter: chapter, verses: [1, 2], savedBandCounts: [:], now: ContinuousClock().now)

        measurement.updateSavedBandCounts([1: 3], chapter: BibleChapter(title: .genesis, chapter: 2))
        #expect(measurement.savedBandCounts.isEmpty)

        measurement.updateSavedBandCounts([1: 3], chapter: chapter)
        #expect(measurement.savedBandCounts == [1: 3])
    }

    /// 실제 `Store` 로 장을 연다 — 본문 → 캔버스 조회 → `drawingsLoaded` 의 배선이 끊기면 band 수가 조용히 비고 slack 도 사라진다.
    @Test("장을 열면 캔버스가 읽은 행의 band 수가 측정에 들어가 HUD slack 이 보인다")
    func hudSlackComesFromCanvasLoadedRows() async throws {
        let spy = RepositorySpy()
        spy.snapshots = { _ in Self.chapterRows() }
        let store = Store(initialState: CarveDetailFeature.State(headerState: .initialState)) {
            CarveDetailFeature()
        } withDependencies: {
            $0.drawingRepository = spy
            $0.drawingCodec = CanvasTestSupport.codec(results: LockIsolated([]))
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }

        // when: 본문 3절(모두 1줄)을 받고 실측이 모인다.
        store.send(.view(.layoutHostingChanged(writingWidth: 372)))
        store.send(.setSentence((1...3).map { BibleVerse(title: chapter, verse: $0, sentence: "본문 \($0)") }))
        var batch: [SentencesWithDrawingFeature.State.ID: VerseRowGeometry] = [:]
        for verse in 1...3 {
            batch["\(chapter.title.koreanTitle()).\(chapter.chapter).\(verse)"] = VerseRowGeometry(underlineOffsets: [30])
        }
        store.send(.view(.verseGeometryMeasured(batch)))

        // then: 캔버스가 행을 읽자 2절의 저장 4줄이 들어오고, 텍스트 1줄보다 3줄 많은 slack 이 된다.
        let deadline = ContinuousClock.now + .seconds(2)
        while store.chapterLayout.savedBandCounts.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(spy.loadedChapters.value.contains(chapter))
        #expect(store.chapterLayout.savedBandCounts == [2: 4])
        #expect(store.chapterLayout.reflowSlacks == [ChapterLayoutMeasurement.ReflowSlack(verse: 2, extraBands: 3)])
        #if DEBUG
        #expect(ChapterLayoutDebugHUD(measurement: store.chapterLayout, lastEdit: nil).consoleSnapshot.contains("slackBands=[v2:+3]"))
        #endif
    }
}
