//
//  ChapterLayoutSlackDiagnosticsTesting.swift
//  CarveFeatureTest
//
//  진단 — Pass 2 여유(설계 §6-3)를 뺀 Δ (2026-09-14 실기기 시편 119편)
//  저장 당시 줄 수가 지금보다 많은 절이 있으면 `frameDeltas` 는 설계상 계단을 보인다. 여유를 뺀 Δ 가 그 계단만 지우고
//  다른 어긋남은 남기는지, 안전망 입력은 그대로인지를 고정한다.
//

import CoreGraphics
import Domain
import Foundation
import Testing

@testable import CarveFeature

@Suite("진단 — Pass 2 여유를 뺀 Δ")
struct ChapterLayoutSlackDiagnosticsTesting {
    private let chapter = BibleChapter(title: .genesis, chapter: 1)
    private let setting = SentenceSetting.initialState
    private let metrics = ChapterLayoutHosting.metrics
    /// 줄 띠 폭(`SentenceSetting.linePitch`). 여유 band 한 개의 높이다.
    private var pitch: CGFloat { setting.linePitch }
    private let clock = ContinuousClock()

    /// 절 `verse` 가 `lineCount` 줄일 때 Reducer 가 넘기는 anchor (topPadding 포함, 30pt 간격).
    private func anchors(verse: Int, lineCount: Int) -> [CGFloat] {
        let padding = ChapterLayoutHosting.topPadding(forVerse: verse)
        return (1...lineCount).map { padding + CGFloat($0) * 30 }
    }

    /// 텍스트 실측과 폭까지 넣고 레이아웃을 지은 측정.
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
        let rebuilt = measurement.rebuildIfComplete(setting: setting, isLeftHanded: false, metrics: metrics, now: clock.now)
        let layout = try #require(rebuilt)
        return (measurement, layout)
    }

    /// 1절에만 저장 band 가 `savedBands` 개 있는 3절 장. 텍스트는 전부 1줄이다.
    ///
    /// 행은 **여유 없는 레이아웃의 자리**에 놓는다 — 행은 여유만큼 커지지 않는다(실기기 시편 119편과 같은 모양).
    /// - Parameters:
    ///   - savedBands: 1절의 저장 band 수.
    ///   - rowShift: 절별로 행을 더 내릴 거리. 여유와 무관한 어긋남을 흉내 낸다.
    /// - Returns: 여유가 반영된 레이아웃에 행 실측이 들어간 측정.
    private func slackChapter(savedBands: Int, rowShift: [Int: CGFloat] = [:]) throws -> ChapterLayoutMeasurement {
        let lineCounts = [1: 1, 2: 1, 3: 1]
        let rows = try built(lineCounts: lineCounts).layout
        var measurement = try built(lineCounts: lineCounts, savedBandCounts: [1: savedBands]).measurement
        for region in rows.regions {
            measurement.recordFrame(verse: region.verse, frame: CGRect(
                x: 380,
                y: region.writingRect.minY + (rowShift[region.verse] ?? 0),
                width: 300,
                height: region.writingRect.height
            ))
        }
        return measurement
    }

    @Test("여유 band 는 저장 band 가 텍스트 줄 수보다 많은 절만 센다 — 합계가 레이아웃이 늘어난 양과 같다")
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
        #expect(abs(slack.layout.totalHeight - plain.layout.totalHeight - 3 * pitch) < 0.001)
        #expect(plain.measurement.reflowSlacks.isEmpty)
        #expect(!plain.measurement.hasReflowSlack)
    }

    @Test("여유를 뺀 Δ 는 여유만큼의 계단을 지워 0 이 된다 — 안전망은 여전히 원래 Δ 를 본다")
    func slackAdjustedDeltasRemoveTheSlackStep() throws {
        // 1절 저장 band 3 > 1줄 → 1절 +2 band. 원래 Δ 는 1절 높이 −2줄, 2·3절 상단 −2줄의 계단이다.
        let measurement = try slackChapter(savedBands: 3)
        let raw = measurement.frameDeltas

        try #require(raw.map(\.verse) == [1, 2, 3])
        #expect(abs(raw[0].heightDelta + 2 * pitch) < 0.001)
        #expect(abs(raw[1].topDelta + 2 * pitch) < 0.001)
        #expect(abs(raw[2].topDelta + 2 * pitch) < 0.001)
        #expect(measurement.slackAdjustedFrameDeltas.map(\.verse) == [1, 2, 3])
        #expect(measurement.slackAdjustedFrameDeltas.allSatisfy { $0.magnitude < 0.001 })

        // 안전망 입력은 그대로다 — 여유를 뺀 값으로 막거나 풀지 않는다.
        let verdict = try #require(measurement.layoutDeltaVerdict)
        #expect(abs(verdict.magnitude - 2 * pitch) < 0.001)
        #expect(!verdict.blocksInput)
    }

    @Test("여유를 뺀 Δ 에도 여유와 무관한 어긋남은 그대로 남는다")
    func slackAdjustedDeltasKeepMisalignmentOutsideTheSlack() throws {
        // 3절 행만 5pt 더 내려가 있다 — 측정 경로 결함의 모양.
        let measurement = try slackChapter(savedBands: 3, rowShift: [3: 5])
        let worst = try #require(measurement.worstSlackAdjustedFrameDelta)

        #expect(worst.verse == 3)
        #expect(abs(worst.topDelta - 5) < 0.001)
        #expect(worst.magnitude > LayoutDeltaVerdict.tolerance)
    }

    #if DEBUG
    @MainActor
    @Test("HUD 콘솔 스냅샷에 여유 절별 band 수와 여유를 뺀 Δ 가 남는다")
    func consoleSnapshotReportsSlackBandsAndSlackAdjustedDelta() throws {
        let measurement = try slackChapter(savedBands: 3)
        let snapshot = ChapterLayoutDebugHUD(measurement: measurement, lastEdit: nil).consoleSnapshot

        #expect(snapshot.contains("slack=true slackBands=[v1:+2]"))
        #expect(snapshot.contains("slackAdjustedDeltaMax=0.00"))
    }
    #endif
}
