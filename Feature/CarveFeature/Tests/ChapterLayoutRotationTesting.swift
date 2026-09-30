//
//  ChapterLayoutRotationTesting.swift
//  CarveFeatureTest
//
//  D9 H-4 — 회전(폭 변경) 왕복에서 측정 파이프라인에 낡은 값이 남지 않는지.
//  시뮬레이터에는 회전 명령이 없고(`simctl ui` 에 orientation 없음) 실기기 회전은 손으로만 볼 수 있으므로,
//  같은 자극을 **폭 A → B → A** 로 태운다. 설계 §14 의 "이월 상태 감사" 와 같은 형태다.
//

import CoreGraphics
import Domain
import Foundation
import Testing

@testable import CarveFeature

@Suite("D9 H-4 — 회전(폭 A→B→A) 왕복")
struct ChapterLayoutRotationTesting {
    private let chapter = BibleChapter(title: .genesis, chapter: 1)
    private let setting = SentenceSetting.initialState      // lineSpace 30
    private let metrics = ChapterLayoutHosting.metrics
    private let clock = ContinuousClock()
    private let verses = [1, 2, 3]

    /// 세로(좁음) — 줄이 더 많다. 가로(넓음) — 줄이 적다.
    private static let portraitWidth: CGFloat = 372
    private static let landscapeWidth: CGFloat = 556
    private static let portraitLines = [1: 3, 2: 2, 3: 4]
    private static let landscapeLines = [1: 2, 2: 1, 3: 3]

    private func anchors(verse: Int, lineCount: Int) -> [CGFloat] {
        let padding = ChapterLayoutHosting.topPadding(forVerse: verse)
        return (1...lineCount).map { padding + CGFloat($0) * 30 }
    }

    /// 한 방향의 실측을 통째로 밀어 넣는다 — 폭 · 절별 anchor · 절별 실측 높이(R13).
    private func record(_ measurement: inout ChapterLayoutMeasurement, width: CGFloat, lines: [Int: Int]) {
        measurement.setWritingWidth(width)
        for verse in verses {
            guard let lineCount = lines[verse] else { continue }
            measurement.recordText(verse: verse, underlineAnchors: anchors(verse: verse, lineCount: lineCount))
            let height = ChapterLayoutHosting.topPadding(forVerse: verse) + CGFloat(lineCount) * 30
            measurement.recordCanvasFrameInRow(verse: verse, frame: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    @discardableResult
    private func rebuild(_ measurement: inout ChapterLayoutMeasurement) -> ChapterLayout? {
        measurement.rebuildIfComplete(setting: setting, isLeftHanded: false, metrics: metrics, now: clock.now)
    }

    private func begun() -> ChapterLayoutMeasurement {
        var measurement = ChapterLayoutMeasurement()
        measurement.begin(chapter: chapter, verses: verses, savedBandCounts: [:], now: clock.now)
        return measurement
    }

    @Test("폭 A → B → A 왕복 뒤 레이아웃이 처음 A 와 완전히 같다 (낡은 실측이 남지 않는다)")
    func rotationRoundTripRebuildsIdenticalLayout() throws {
        var measurement = begun()

        record(&measurement, width: Self.portraitWidth, lines: Self.portraitLines)
        let first = try #require(rebuild(&measurement))

        record(&measurement, width: Self.landscapeWidth, lines: Self.landscapeLines)
        let rotated = try #require(rebuild(&measurement))
        // 가로에서는 실제로 달라야 한다 — 그래야 왕복이 의미 있는 자극이다.
        #expect(rotated != first)
        #expect(rotated.writingWidth == Self.landscapeWidth)
        #expect(rotated.totalHeight < first.totalHeight)

        record(&measurement, width: Self.portraitWidth, lines: Self.portraitLines)
        let restored = try #require(rebuild(&measurement))

        #expect(restored == first)
        #expect(restored.signature == first.signature)
        #expect(restored.totalHeight == first.totalHeight)
        for verse in verses {
            #expect(restored.region(verse: verse)?.writingRect == first.region(verse: verse)?.writingRect)
            #expect(restored.region(verse: verse)?.captureRect == first.region(verse: verse)?.captureRect)
        }
    }

    @Test("가로에서 잰 높이만 남고 세로 텍스트가 도착한 중간 상태는 세로 실측이 오면 해소된다")
    func staleHeightsFromOtherOrientationAreResolvedWhenNewOnesArrive() throws {
        var measurement = begun()
        record(&measurement, width: Self.portraitWidth, lines: Self.portraitLines)
        let portrait = try #require(rebuild(&measurement))

        record(&measurement, width: Self.landscapeWidth, lines: Self.landscapeLines)
        rebuild(&measurement)

        // 세로로 돌아오는 도중 — 폭과 텍스트만 먼저 오고 실측 높이는 아직 가로 값이다 (R13 의 중간 상태).
        measurement.setWritingWidth(Self.portraitWidth)
        for verse in verses {
            guard let lineCount = Self.portraitLines[verse] else { continue }
            measurement.recordText(verse: verse, underlineAnchors: anchors(verse: verse, lineCount: lineCount))
        }
        let halfway = try #require(rebuild(&measurement))
        #expect(halfway != portrait)   // 낡은 높이가 섞여 있으므로 아직 다르다

        // 세로 실측 높이가 도착하면 해소돼야 한다 — 여기서 안 풀리면 자가 복구가 안 되는 것이다.
        for verse in verses {
            guard let lineCount = Self.portraitLines[verse] else { continue }
            let height = ChapterLayoutHosting.topPadding(forVerse: verse) + CGFloat(lineCount) * 30
            measurement.recordCanvasFrameInRow(verse: verse, frame: CGRect(x: 0, y: 0, width: Self.portraitWidth, height: height))
        }
        let settled = try #require(rebuild(&measurement))
        #expect(settled == portrait)
    }
}
