//
//  ChapterLayoutReloadTesting.swift
//  CarveFeatureTest
//
//  R24 — 같은 장을 다시 불러올 때 기하 실측이 살아남는가 (설계 §6 · 런북 §8-7).
//  `onGeometryChange` 는 값이 바뀔 때만 부르므로, `begin` 이 지운 기하는 같은 장·같은 폭에서 복구되지 않는다.
//

import CoreGraphics
import Domain
import Foundation
import Testing

@testable import CarveFeature

@Suite("R24 — 같은 장 재로드와 기하 실측")
struct ChapterLayoutReloadTesting {
    private let chapter = BibleChapter(title: .genesis, chapter: 1)
    private let setting = SentenceSetting.initialState
    private let metrics = ChapterLayoutHosting.metrics
    private let clock = ContinuousClock()

    private func anchors(verse: Int, lineCount: Int) -> [CGFloat] {
        let padding = ChapterLayoutHosting.topPadding(forVerse: verse)
        return (1...lineCount).map { padding + CGFloat($0) * 30 }
    }

    private func begun(verses: [Int] = [1, 2, 3]) -> ChapterLayoutMeasurement {
        var measurement = ChapterLayoutMeasurement()
        measurement.begin(chapter: chapter, verses: verses, savedBandCounts: [:], now: clock.now)
        return measurement
    }

    @discardableResult
    private func rebuild(_ measurement: inout ChapterLayoutMeasurement) -> ChapterLayout? {
        measurement.rebuildIfComplete(setting: setting, isLeftHanded: false, metrics: metrics, now: clock.now)
    }

    /// `onGeometryChange` 로만 들어오는 값들을 채운다.
    private func withGeometry(_ measurement: inout ChapterLayoutMeasurement) {
        for verse in [1, 2, 3] {
            measurement.recordText(verse: verse, underlineAnchors: anchors(verse: verse, lineCount: 2))
            measurement.recordTitleHeight(verse: verse, height: 10)
            measurement.recordRowFrame(verse: verse, frame: CGRect(x: 5, y: CGFloat(verse) * 100, width: 700, height: 90))
            measurement.recordCanvasFrameInRow(verse: verse, frame: CGRect(x: 361, y: 3, width: 372, height: 84))
        }
    }

    /// 실기기에서는 셋이 함께 무너졌다 (2026-09-08, 시편 122편):
    /// 캔버스 미활성으로 **필기가 사라지고**, 레이아웃이 **예측식으로 후퇴**하며(`H` 3016 → 2977),
    /// `frameDeltas` 가 비어 **Δ 안전망이 눈을 감는다**.
    @Test("같은 장으로 다시 begin 하면 기하 실측(행 frame · 행 안 캔버스 · 소제목 높이)이 유지된다")
    func beginOnSameChapterKeepsGeometry() {
        var measurement = begun()
        withGeometry(&measurement)
        let framesBefore = measurement.measuredFrames
        let originBefore = measurement.columnOrigin
        #expect(!framesBefore.isEmpty)
        #expect(originBefore != nil)

        // 설정 토글 등으로 같은 장을 다시 불러온다.
        measurement.begin(chapter: chapter, verses: [1, 2, 3], savedBandCounts: [:], now: clock.now)

        #expect(measurement.measuredFrames == framesBefore)
        #expect(measurement.columnOrigin == originBefore)
        #expect(measurement.titleHeights.count == 3)
        // 텍스트 실측은 재보고되므로 비우는 쪽이 맞다 — 게이트는 다시 닫힌다.
        #expect(measurement.textMeasurements.isEmpty)
        #expect(!measurement.isReady)
    }

    @Test("다른 장으로 begin 하면 기하 실측을 버린다 — 이전 장의 좌표가 남지 않는다")
    func beginOnDifferentChapterClearsGeometry() {
        var measurement = begun()
        withGeometry(&measurement)
        #expect(!measurement.measuredFrames.isEmpty)

        measurement.begin(
            chapter: BibleChapter(title: .genesis, chapter: 2),
            verses: [1, 2, 3], savedBandCounts: [:], now: clock.now
        )

        #expect(measurement.measuredFrames.isEmpty)
        #expect(measurement.columnOrigin == nil)
        #expect(measurement.titleHeights.isEmpty)
    }

    @Test("같은 장이라도 절 목록이 달라지면 기하 실측을 버린다")
    func beginWithDifferentVersesClearsGeometry() {
        var measurement = begun()
        withGeometry(&measurement)
        #expect(!measurement.measuredFrames.isEmpty)

        measurement.begin(chapter: chapter, verses: [1, 2], savedBandCounts: [:], now: clock.now)

        #expect(measurement.measuredFrames.isEmpty)
        #expect(measurement.columnOrigin == nil)
    }

    @Test("유지된 행 안 캔버스 높이로 레이아웃이 실측 높이를 그대로 쓴다 — 예측식으로 후퇴하지 않는다")
    func rebuiltLayoutAfterSameChapterBeginUsesMeasuredHeight() {
        var measurement = begun()
        withGeometry(&measurement)
        measurement.setWritingWidth(372)
        let heightBefore = rebuild(&measurement)?.totalHeight

        measurement.begin(chapter: chapter, verses: [1, 2, 3], savedBandCounts: [:], now: clock.now)
        for verse in [1, 2, 3] {
            measurement.recordText(verse: verse, underlineAnchors: anchors(verse: verse, lineCount: 2))
        }
        let heightAfter = rebuild(&measurement)?.totalHeight

        #expect(heightBefore != nil)
        #expect(heightAfter == heightBefore)
    }
}
