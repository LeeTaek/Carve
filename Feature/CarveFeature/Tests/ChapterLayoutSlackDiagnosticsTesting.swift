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
