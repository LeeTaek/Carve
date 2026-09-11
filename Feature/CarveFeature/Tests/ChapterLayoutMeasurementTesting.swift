//
//  ChapterLayoutMeasurementTesting.swift
//  CarveFeatureTest
//
//  Phase 2 — 장 레이아웃 측정 파이프라인과 §6-2 입력 게이트 (설계 §6 · §13 Phase 2)
//  절별 실측이 비동기로 도착하는 상황을 순수 상태(`ChapterLayoutMeasurement`)와 Reducer 두 층에서 고정한다.
//

import CoreGraphics
import Domain
import Foundation
import Testing

import ComposableArchitecture
import Dependencies

@testable import CarveFeature

// MARK: - 순수 상태

@Suite("Phase 2 — ChapterLayoutMeasurement")
struct ChapterLayoutMeasurementTesting {
    private let chapter = BibleChapter(title: .genesis, chapter: 1)
    private let setting = SentenceSetting.initialState   // lineSpace 30
    private let metrics = ChapterLayoutHosting.metrics
    /// 줄 띠 폭 = 글꼴 줄 높이 + 줄 간격(`SentenceSetting.linePitch`). 실측 높이가 없을 때의 예측 · Δ 임계값이 이 값이다.
    /// 아래 `anchors` 는 **실측으로 넣는 입력값**이라 30pt 간격 그대로 둔다.
    private var pitch: CGFloat { setting.linePitch }
    private let clock = ContinuousClock()

    /// 절 `verse` 가 `lineCount` 줄일 때 Reducer 가 넘기는 anchor (topPadding 포함, 30pt 간격).
    private func anchors(verse: Int, lineCount: Int) -> [CGFloat] {
        let padding = ChapterLayoutHosting.topPadding(forVerse: verse)
        return (1...lineCount).map { padding + CGFloat($0) * 30 }
    }

    private func begun(verses: [Int] = [1, 2, 3], savedBandCounts: [Int: Int] = [:]) -> ChapterLayoutMeasurement {
        var measurement = ChapterLayoutMeasurement()
        measurement.begin(chapter: chapter, verses: verses, savedBandCounts: savedBandCounts, now: clock.now)
        return measurement
    }

    @discardableResult
    private func rebuild(_ measurement: inout ChapterLayoutMeasurement) -> ChapterLayout? {
        measurement.rebuildIfComplete(setting: setting, isLeftHanded: false, metrics: metrics, now: clock.now)
    }

    // MARK: §6-2 게이트

    @Test("begin 직후에는 게이트가 닫혀 있고 전 절이 미측정이다")
    func gateIsClosedRightAfterBegin() {
        let measurement = begun()

        #expect(!measurement.isReady)
        #expect(measurement.layout == nil)
        #expect(measurement.expectedVerseCount == 3)
        #expect(measurement.missingVerses == [1, 2, 3])
        #expect(!measurement.isTextComplete)
    }

    @Test("전 절 텍스트 실측 + 폭이 모두 있어야 레이아웃이 만들어지고 게이트가 열린다")
    func gateOpensOnlyWhenEveryVerseAndWidthArePresent() {
        var measurement = begun()
        measurement.setWritingWidth(372)

        measurement.recordText(verse: 1, underlineAnchors: anchors(verse: 1, lineCount: 2))
        #expect(rebuild(&measurement) == nil)
        #expect(!measurement.isReady)
        #expect(measurement.missingVerses == [2, 3])

        measurement.recordText(verse: 2, underlineAnchors: anchors(verse: 2, lineCount: 1))
        #expect(rebuild(&measurement) == nil)
        #expect(!measurement.isReady)

        measurement.recordText(verse: 3, underlineAnchors: anchors(verse: 3, lineCount: 3))
        let layout = rebuild(&measurement)

        #expect(layout != nil)
        #expect(measurement.isReady)
        #expect(measurement.isTextComplete)
        #expect(measurement.buildCount == 1)
        #expect(measurement.firstBuildDuration != nil)
        #expect(layout?.regions.map(\.verse) == [1, 2, 3])
        #expect(layout?.writingWidth == 372)
        #expect(layout?.satisfiesCompositionGate(expectedVerseCount: 3) == true)
    }

    @Test("폭이 0 이면 전 절이 측정돼도 레이아웃을 만들지 않는다 (§6-2 writingWidth > 0)")
    func zeroWidthKeepsGateClosed() {
        var measurement = begun(verses: [1])
        measurement.recordText(verse: 1, underlineAnchors: anchors(verse: 1, lineCount: 1))

        #expect(rebuild(&measurement) == nil)
        #expect(!measurement.isReady)

        let didChange1 = measurement.setWritingWidth(300)
        #expect(didChange1)
        #expect(rebuild(&measurement) != nil)
        #expect(measurement.isReady)
    }

    @Test("빈 실측(줄 0개)은 측정 완료로 치지 않는다 — Text.LayoutKey 기본값 방어")
    func emptyMeasurementIsIgnored() {
        var measurement = begun(verses: [1])
        measurement.setWritingWidth(300)

        let didChange2 = measurement.recordText(verse: 1, underlineAnchors: [])
        #expect(!didChange2)
        #expect(rebuild(&measurement) == nil)
        #expect(measurement.missingVerses == [1])
    }

    @Test("현재 장에 없는 절의 실측은 무시된다 (§6-4 이전 장 이벤트 폐기)")
    func measurementForUnknownVerseIsDiscarded() {
        var measurement = begun(verses: [1, 2])
        measurement.setWritingWidth(300)

        let didChange3 = measurement.recordText(verse: 7, underlineAnchors: [30])
        #expect(!didChange3)
        let didChange4 = measurement.recordTitleHeight(verse: 7, height: 20)
        #expect(!didChange4)
        let didChange5 = measurement.recordFrame(verse: 7, frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(!didChange5)
        #expect(measurement.textMeasurements.isEmpty)
        #expect(measurement.measuredFrames.isEmpty)
    }

    @Test("장이 바뀌면 이전 실측·레이아웃·계측이 전부 버려지고 폭만 남는다")
    func beginningNewChapterDiscardsPreviousMeasurements() {
        var measurement = begun(verses: [1, 2])
        measurement.setWritingWidth(300)
        measurement.recordText(verse: 1, underlineAnchors: anchors(verse: 1, lineCount: 1))
        measurement.recordText(verse: 2, underlineAnchors: anchors(verse: 2, lineCount: 1))
        measurement.recordFrame(verse: 1, frame: CGRect(x: 380, y: 2, width: 300, height: 55))
        rebuild(&measurement)
        #expect(measurement.isReady)

        let next = BibleChapter(title: .genesis, chapter: 2)
        measurement.begin(chapter: next, verses: [1, 2, 3, 4], savedBandCounts: [:], now: clock.now)

        #expect(measurement.chapter == next)
        #expect(!measurement.isReady)
        #expect(measurement.layout == nil)
        #expect(measurement.buildCount == 0)
        #expect(measurement.firstBuildDuration == nil)
        #expect(measurement.textMeasurements.isEmpty)
        #expect(measurement.measuredFrames.isEmpty)
        #expect(measurement.expectedVerseCount == 4)
        #expect(measurement.writingWidth == 300)
    }

    // MARK: 재계산

    @Test("완성 뒤 실측이 바뀌면 재계산되고, 첫 완성 소요 시간은 그대로다")
    func changedMeasurementRebuildsWithoutResettingFirstDuration() {
        var measurement = begun(verses: [1, 2])
        measurement.setWritingWidth(300)
        measurement.recordText(verse: 1, underlineAnchors: anchors(verse: 1, lineCount: 1))
        measurement.recordText(verse: 2, underlineAnchors: anchors(verse: 2, lineCount: 1))
        let first = rebuild(&measurement)
        let firstDuration = measurement.firstBuildDuration

        // 같은 값은 변경이 아니다.
        let didChange6 = measurement.recordText(verse: 2, underlineAnchors: anchors(verse: 2, lineCount: 1))
        #expect(!didChange6)

        let didChange7 = measurement.recordText(verse: 2, underlineAnchors: anchors(verse: 2, lineCount: 3))
        #expect(didChange7)
        let second = rebuild(&measurement)

        #expect(measurement.buildCount == 2)
        #expect(measurement.firstBuildDuration == firstDuration)
        #expect(second?.regions[1].writingRect.height == 3 * pitch)
        #expect(second?.totalHeight == (first?.totalHeight ?? 0) + 2 * pitch)
        // 재계산 사이에도 게이트는 닫히지 않는다 — 절 개수가 그대로이기 때문이다.
        #expect(measurement.isReady)
    }

    @Test("실측 도착 순서가 바뀌어도 같은 레이아웃이 나온다 (§14 6-2)")
    func arrivalOrderDoesNotChangeLayout() {
        var forward = begun()
        forward.setWritingWidth(300)
        var reverse = begun()
        reverse.setWritingWidth(300)

        for verse in [1, 2, 3] {
            forward.recordText(verse: verse, underlineAnchors: anchors(verse: verse, lineCount: verse))
        }
        for verse in [3, 2, 1] {
            reverse.recordText(verse: verse, underlineAnchors: anchors(verse: verse, lineCount: verse))
        }
        reverse.recordTitleHeight(verse: 2, height: 26)
        forward.recordTitleHeight(verse: 2, height: 26)

        #expect(rebuild(&forward) == rebuild(&reverse))
    }

    // MARK: 입력이 좌표에 반영되는 방식

    @Test("소제목 높이는 leadingInset 으로 들어가 그 절부터 아래로 밀린다")
    func titleHeightShiftsVerseByLeadingInset() {
        var plain = begun(verses: [1, 2])
        plain.setWritingWidth(300)
        plain.recordText(verse: 1, underlineAnchors: anchors(verse: 1, lineCount: 1))
        plain.recordText(verse: 2, underlineAnchors: anchors(verse: 2, lineCount: 1))
        let base = rebuild(&plain)

        var titled = plain
        let didChange8 = titled.recordTitleHeight(verse: 2, height: 26)
        #expect(didChange8)
        let shifted = rebuild(&titled)

        let expectedShift = ChapterLayoutHosting.leadingInset(titleHeight: 26)
        #expect(expectedShift == 26 + ChapterLayoutHosting.titleSpacing)
        #expect(shifted?.regions[0] == base?.regions[0].withCaptureMaxY(added: expectedShift / 2))
        #expect(shifted?.regions[1].writingRect.minY == (base?.regions[1].writingRect.minY ?? 0) + expectedShift)
        #expect(shifted?.totalHeight == (base?.totalHeight ?? 0) + expectedShift)

        // 0 이하 높이는 "소제목 없음" 이며 값이 같으면 변경이 아니다.
        let didChange9 = titled.recordTitleHeight(verse: 2, height: 0)
        #expect(didChange9)
        let didChange10 = titled.recordTitleHeight(verse: 2, height: -3)
        #expect(!didChange10)
        #expect(rebuild(&titled) == base)
    }

    @Test("1절의 상단 여백은 writingRect 안의 topPadding 으로 들어가고 anchor 는 이미 그만큼 내려온 값이다")
    func firstVerseTopPaddingIsInsideWritingRect() {
        var measurement = begun(verses: [1, 2])
        measurement.setWritingWidth(300)
        measurement.recordText(verse: 1, underlineAnchors: anchors(verse: 1, lineCount: 2))
        measurement.recordText(verse: 2, underlineAnchors: anchors(verse: 2, lineCount: 2))
        let layout = rebuild(&measurement)

        let padding = ChapterLayoutHosting.firstVerseTopPadding
        #expect(layout?.regions[0].writingRect.height == padding + 2 * pitch)
        #expect(layout?.regions[0].underlineAnchors == [padding + 30, padding + 60])
        #expect(layout?.regions[1].writingRect.height == 2 * pitch)
        #expect(layout?.regions[1].underlineAnchors == [30, 60])
    }

    @Test("저장 band 수는 Pass 2 여유 높이로 반영된다")
    func savedBandCountGrowsVerse() {
        var measurement = begun(verses: [1, 2], savedBandCounts: [2: 4])
        measurement.setWritingWidth(300)
        measurement.recordText(verse: 1, underlineAnchors: anchors(verse: 1, lineCount: 1))
        measurement.recordText(verse: 2, underlineAnchors: anchors(verse: 2, lineCount: 1))
        let layout = rebuild(&measurement)

        // 1줄 텍스트 + 초과 band 3개 = 4 × 줄 거리.
        #expect(layout?.regions[1].writingRect.height == 4 * pitch)
        #expect(layout?.regions[1].underlineAnchors == [30])
    }

    // MARK: 검증 — 예측 vs 실측

    @Test("실측 frame 은 레이아웃에 영향을 주지 않고 columnOrigin 과 Δ 만 만든다")
    func measuredFramesOnlyProduceDeltasAndColumnOrigin() throws {
        var measurement = begun(verses: [1, 2])
        measurement.setWritingWidth(300)
        measurement.recordText(verse: 1, underlineAnchors: anchors(verse: 1, lineCount: 1))
        measurement.recordText(verse: 2, underlineAnchors: anchors(verse: 2, lineCount: 1))
        let layout = rebuild(&measurement)
        let region1 = try #require(layout?.regions[0])
        let region2 = try #require(layout?.regions[1])

        // 실측이 없으면 Δ 도 없다.
        #expect(measurement.frameDeltas.isEmpty)
        #expect(measurement.worstFrameDelta == nil)
        #expect(measurement.columnOrigin == nil)

        // 1절은 예측과 정확히 일치, 2절은 3pt 아래·2pt 더 큼.
        let frame1 = CGRect(x: 382, y: region1.writingRect.minY, width: 300, height: region1.writingRect.height)
        let frame2 = CGRect(x: 382, y: region2.writingRect.minY + 3, width: 300, height: region2.writingRect.height + 2)
        let didChange11 = measurement.recordFrame(verse: 1, frame: frame1)
        #expect(didChange11)
        let didChange12 = measurement.recordFrame(verse: 2, frame: frame2)
        #expect(didChange12)
        let didChange13 = measurement.recordFrame(verse: 2, frame: frame2)
        #expect(!didChange13)

        #expect(measurement.layout == layout)
        #expect(measurement.buildCount == 1)
        #expect(measurement.columnOrigin == CGPoint(x: 382, y: 0))
        #expect(measurement.frameDeltas == [
            ChapterLayoutMeasurement.FrameDelta(verse: 1, topDelta: 0, heightDelta: 0),
            ChapterLayoutMeasurement.FrameDelta(verse: 2, topDelta: 3, heightDelta: 2)
        ])
        #expect(measurement.worstFrameDelta?.verse == 2)
        #expect(measurement.worstFrameDelta?.magnitude == 3)
    }

    @Test("실측 높이를 레이아웃 입력으로 쓰면 heightDelta 는 구조적으로 0 이고 topDelta 만 독립 검증으로 남는다 (R13 부작용)")
    func measuredHeightMakesHeightDeltaStructurallyZero() throws {
        var measurement = begun(verses: [1, 2])
        measurement.setWritingWidth(300)
        measurement.recordText(verse: 1, underlineAnchors: anchors(verse: 1, lineCount: 1))
        measurement.recordText(verse: 2, underlineAnchors: anchors(verse: 2, lineCount: 1))
        // 실기기 R13 의 모양 — 실제 렌더가 예측보다 절당 0.5pt 크다.
        measurement.recordCanvasFrameInRow(verse: 1, frame: CGRect(x: 0, y: 0, width: 300, height: 55.5))
        measurement.recordCanvasFrameInRow(verse: 2, frame: CGRect(x: 0, y: 0, width: 300, height: 30.5))
        let layout = try #require(rebuild(&measurement))

        // 예측이었다면 55 / 30 이었을 값이 실측으로 지어졌다.
        #expect(layout.regions[0].writingRect.height == 55.5)
        #expect(layout.regions[1].writingRect.height == 30.5)

        // 실제 배치가 레이아웃과 정확히 일치하는 경우 — Δ 가 전부 0.
        measurement.recordRowFrame(verse: 1, frame: CGRect(x: 0, y: layout.regions[0].writingRect.minY, width: 300, height: 55.5))
        measurement.recordRowFrame(verse: 2, frame: CGRect(x: 0, y: layout.regions[1].writingRect.minY, width: 300, height: 30.5))
        #expect(measurement.frameDeltas.allSatisfy { $0.heightDelta == 0 && $0.topDelta == 0 })

        // 배치 여백(metrics)이 어긋나면 heightDelta 는 여전히 0 이지만 topDelta 가 그것을 잡는다.
        measurement.recordRowFrame(verse: 2, frame: CGRect(x: 0, y: layout.regions[1].writingRect.minY + 7, width: 300, height: 30.5))
        let worst = try #require(measurement.worstFrameDelta)
        #expect(worst.verse == 2)
        #expect(worst.heightDelta == 0)
        #expect(worst.topDelta == 7)
    }

    // MARK: Δ 안전망 (§14 — D9 R13)

    @Test("Δ 가 허용치 이내면 판정이 열려 있고, 허용치를 넘어도 한 줄 이하면 차단하지 않는다")
    func verdictStaysOpenBelowOneLine() throws {
        var measurement = begun(verses: [1, 2])
        measurement.setWritingWidth(300)
        measurement.recordText(verse: 1, underlineAnchors: anchors(verse: 1, lineCount: 1))
        measurement.recordText(verse: 2, underlineAnchors: anchors(verse: 2, lineCount: 1))
        let layout = try #require(rebuild(&measurement))
        let region = try #require(layout.region(verse: 2))

        // 실측이 없으면 판정 자체가 없다.
        #expect(measurement.layoutDeltaVerdict == nil)

        // 0.5pt — 허용치(1pt) 이내.
        measurement.recordFrame(verse: 2, frame: CGRect(
            x: 380, y: region.writingRect.minY + 0.5, width: 300, height: region.writingRect.height
        ))
        let small = try #require(measurement.layoutDeltaVerdict)
        #expect(small.magnitude == 0.5)
        #expect(!small.exceedsTolerance)
        #expect(!small.blocksInput)
        #expect(small.lineSpace == pitch)

        // 12pt — 허용치는 넘지만 한 줄(30pt)보다 작다. 로그는 남기되 막지 않는다.
        measurement.recordFrame(verse: 2, frame: CGRect(
            x: 380, y: region.writingRect.minY + 12, width: 300, height: region.writingRect.height
        ))
        let medium = try #require(measurement.layoutDeltaVerdict)
        #expect(medium.exceedsTolerance)
        #expect(!medium.blocksInput)
    }

    @Test("Δ 가 한 줄(lineSpace)을 넘으면 판정이 차단으로 바뀐다")
    func verdictBlocksBeyondOneLine() throws {
        var measurement = begun(verses: [1, 2])
        measurement.setWritingWidth(300)
        measurement.recordText(verse: 1, underlineAnchors: anchors(verse: 1, lineCount: 1))
        measurement.recordText(verse: 2, underlineAnchors: anchors(verse: 2, lineCount: 1))
        let layout = try #require(rebuild(&measurement))
        let region = try #require(layout.region(verse: 2))

        // D9 시편 119편의 모양 — 하단 절이 87.5pt 아래에 있다.
        measurement.recordFrame(verse: 2, frame: CGRect(
            x: 380, y: region.writingRect.minY + 87.5, width: 300, height: region.writingRect.height
        ))
        let verdict = try #require(measurement.layoutDeltaVerdict)

        #expect(verdict.verse == 2)
        #expect(verdict.magnitude == 87.5)
        #expect(verdict.topDelta == 87.5)
        #expect(verdict.exceedsTolerance)
        #expect(verdict.blocksInput)
        // 합성 게이트는 Δ 를 보지 않는다 — 안전망이 열려도 닫혀도 §6-2 는 그대로다.
        #expect(measurement.isReady)
    }

    @Test("Pass 2 여유 높이가 있는 장에서는 Δ 로 판정할 수 없어 차단하지 않는다")
    func verdictDoesNotBlockWhenPassTwoSlackIsPresent() throws {
        // 2절의 저장 band 4개 > 현재 1줄 → writingRect 가 의도적으로 90pt 부풀려진다.
        var measurement = begun(verses: [1, 2], savedBandCounts: [2: 4])
        measurement.setWritingWidth(300)
        measurement.recordText(verse: 1, underlineAnchors: anchors(verse: 1, lineCount: 1))
        measurement.recordText(verse: 2, underlineAnchors: anchors(verse: 2, lineCount: 1))
        let layout = try #require(rebuild(&measurement))
        let region = try #require(layout.region(verse: 2))

        #expect(measurement.hasReflowSlack)
        // 행은 여유만큼 커지지 않으므로 Δ 가 의도적으로 크다.
        measurement.recordFrame(verse: 2, frame: CGRect(x: 380, y: region.writingRect.minY, width: 300, height: pitch))
        let verdict = try #require(measurement.layoutDeltaVerdict)

        #expect(verdict.magnitude == 3 * pitch)
        #expect(verdict.exceedsTolerance)
        // 의도한 여유와 예측 결함을 구별할 수 없다 — 막지 않는다.
        #expect(!verdict.blocksInput)
    }
}

private extension VerseCanvasRegion {
    /// captureRect 의 하단만 늘린 사본. 다음 절 앞의 gap 이 커질 때 이전 절이 받는 유일한 변화다.
    func withCaptureMaxY(added delta: CGFloat) -> VerseCanvasRegion {
        VerseCanvasRegion(
            verse: verse,
            writingRect: writingRect,
            captureRect: CGRect(
                x: captureRect.minX,
                y: captureRect.minY,
                width: captureRect.width,
                height: captureRect.height + delta
            ),
            underlineAnchors: underlineAnchors
        )
    }
}

// MARK: - 수집기

@Suite("Phase 2 — VerseGeometryCollector")
@MainActor
struct VerseGeometryCollectorTesting {
    @Test("같은 행의 실측값은 필드별로 겹쳐 쌓이고 flush 한 번에 전부 나간다")
    func reportsAreMergedPerRowAndFlushedTogether() {
        let collector = VerseGeometryCollector()
        var received: [[VerseGeometryCollector.RowID: VerseRowGeometry]] = []
        collector.onFlush = { received.append($0) }

        collector.reportUnderlineOffsets(id: "창세기.1.1", offsets: [30, 60])
        collector.reportRowFrame(id: "창세기.1.1", frame: CGRect(x: 10, y: 2, width: 733, height: 60))
        collector.reportCanvasFrameInRow(id: "창세기.1.1", frame: CGRect(x: 372, y: 0, width: 372, height: 60))
        collector.reportTitleHeight(id: "창세기.1.2", height: 26)
        collector.reportUnderlineOffsets(id: "창세기.1.1", offsets: [30])   // 나중 값이 이긴다
        #expect(received.isEmpty)

        collector.flush()

        #expect(received.count == 1)
        #expect(received.first?["창세기.1.1"] == VerseRowGeometry(
            underlineOffsets: [30],
            rowFrame: CGRect(x: 10, y: 2, width: 733, height: 60),
            canvasFrameInRow: CGRect(x: 372, y: 0, width: 372, height: 60)
        ))
        #expect(received.first?["창세기.1.2"] == VerseRowGeometry(titleHeight: 26))
        #expect(collector.pendingGeometry.isEmpty)

        // 비어 있으면 아무것도 보내지 않는다.
        collector.flush()
        #expect(received.count == 1)
    }

    @Test("onFlush 가 없는 동안 도착한 값은 버려지지 않고 설정 뒤에 나간다")
    func reportsBeforeOnFlushAreKept() async {
        let collector = VerseGeometryCollector()
        collector.reportUnderlineOffsets(id: "창세기.1.1", offsets: [30])
        collector.flush()
        #expect(collector.pendingGeometry.count == 1)

        var received: [VerseGeometryCollector.RowID: VerseRowGeometry] = [:]
        collector.onFlush = { received = $0 }
        // didSet 이 다음 런루프 턴에 flush 를 예약한다.
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(received["창세기.1.1"]?.underlineOffsets == [30])
        #expect(collector.pendingGeometry.isEmpty)
    }

    @Test("merge 에서 nil 은 '보고 없음' 이라 기존 값을 지우지 않는다")
    func mergeKeepsExistingFieldsWhenOtherIsNil() {
        var geometry = VerseRowGeometry(underlineOffsets: [30], titleHeight: 26, rowFrame: .zero, canvasFrameInRow: .zero)
        geometry.merge(VerseRowGeometry(canvasFrameInRow: CGRect(x: 1, y: 2, width: 3, height: 4)))

        #expect(geometry.underlineOffsets == [30])
        #expect(geometry.titleHeight == 26)
        #expect(geometry.rowFrame == .zero)
        #expect(geometry.canvasFrameInRow == CGRect(x: 1, y: 2, width: 3, height: 4))
    }
}

// MARK: - Reducer 배선

@Suite("Phase 2 — CarveDetailFeature 레이아웃 측정 배선")
struct CarveDetailLayoutMeasurementTesting {
    private let chapter = BibleChapter(title: .genesis, chapter: 1)

    private func sentences(count: Int, chapter: BibleChapter? = nil) -> [BibleVerse] {
        (1...count).map { BibleVerse(title: chapter ?? self.chapter, verse: $0, sentence: "본문 \($0)") }
    }

    private func rowID(_ verse: Int, chapter: BibleChapter? = nil) -> SentencesWithDrawingFeature.State.ID {
        let target = chapter ?? self.chapter
        return "\(target.title.koreanTitle()).\(target.chapter).\(verse)"
    }

    /// `reduce(into:)` 를 직접 호출한다. `setSentence` 가 `undoManager.clear()` 를 부르므로 테스트값을 주입한다.
    private func reduce(_ state: inout CarveDetailFeature.State, _ action: CarveDetailFeature.Action) {
        withDependencies {
            $0.undoManager = SharedUndoManager()
        } operation: {
            _ = CarveDetailFeature().reduce(into: &state, action: action)
        }
    }

    private func measured(_ state: inout CarveDetailFeature.State, _ batch: [SentencesWithDrawingFeature.State.ID: VerseRowGeometry]) {
        reduce(&state, .view(.verseGeometryMeasured(batch)))
    }

    @Test("setSentence 가 측정을 시작하고, 전 절의 밑줄 실측이 모여야 게이트가 열린다")
    func gateOpensAfterEveryVerseReportsUnderlines() {
        var state = CarveDetailFeature.State.initialState
        reduce(&state, .view(.layoutHostingChanged(writingWidth: 372)))
        reduce(&state, .setSentence(sentences(count: 3), []))

        #expect(state.chapterLayout.chapter == chapter)
        #expect(state.chapterLayout.expectedVerseCount == 3)
        #expect(state.layoutSignpostID != nil)
        #expect(!state.isLayoutReady)

        measured(&state, [
            rowID(1): VerseRowGeometry(underlineOffsets: [30, 60]),
            rowID(2): VerseRowGeometry(underlineOffsets: [30])
        ])
        #expect(!state.isLayoutReady)
        #expect(state.chapterLayout.missingVerses == [3])

        measured(&state, [rowID(3): VerseRowGeometry(underlineOffsets: [30, 60, 90])])

        #expect(state.isLayoutReady)
        #expect(state.chapterLayout.buildCount == 1)
        #expect(state.layoutSignpostID == nil)
        // 행의 밑줄 offset 도 기존대로 갱신된다.
        #expect(state.sentenceWithDrawingState[id: rowID(3)]?.sentenceState.underlineOffsets == [30, 60, 90])
        // 1절 anchor 에는 상단 여백 25 가 더해진다 (밑줄이 캔버스 안에서 그만큼 내려 그려지므로).
        let padding = ChapterLayoutHosting.firstVerseTopPadding
        #expect(state.chapterLayout.layout?.regions[0].underlineAnchors == [padding + 30, padding + 60])
        #expect(state.chapterLayout.layout?.regions[1].underlineAnchors == [30])
    }

    @Test("한 배치에 전 절이 들어오면 레이아웃은 한 번만 계산된다")
    func singleBatchBuildsLayoutOnce() {
        var state = CarveDetailFeature.State.initialState
        reduce(&state, .view(.layoutHostingChanged(writingWidth: 372)))
        reduce(&state, .setSentence(sentences(count: 3), []))

        measured(&state, [
            rowID(1): VerseRowGeometry(
                underlineOffsets: [30],
                rowFrame: CGRect(x: 10, y: 2, width: 733, height: 55),
                canvasFrameInRow: CGRect(x: 372, y: 0, width: 372, height: 55)
            ),
            rowID(2): VerseRowGeometry(underlineOffsets: [30, 60], titleHeight: 26),
            rowID(3): VerseRowGeometry(underlineOffsets: [30])
        ])

        #expect(state.isLayoutReady)
        #expect(state.chapterLayout.buildCount == 1)
        #expect(state.chapterLayout.titleHeights[2] == 26)
        // 행 frame(콘텐츠) + 행 안 캔버스 영역 = 콘텐츠 좌표의 캔버스 영역.
        #expect(state.chapterLayout.measuredFrames[1] == CGRect(x: 382, y: 2, width: 372, height: 55))
    }

    @Test("이전 장 행의 실측 이벤트는 id 조회에 실패해 버려진다 (§14 6-3)")
    func staleChapterEventsAreDiscarded() {
        var state = CarveDetailFeature.State.initialState
        reduce(&state, .view(.layoutHostingChanged(writingWidth: 372)))
        reduce(&state, .setSentence(sentences(count: 2), []))
        measured(&state, [
            rowID(1): VerseRowGeometry(underlineOffsets: [30]),
            rowID(2): VerseRowGeometry(underlineOffsets: [30])
        ])
        #expect(state.isLayoutReady)

        // 장 전환 — 새 장은 3절이고 아직 아무것도 측정되지 않았다.
        let next = BibleChapter(title: .genesis, chapter: 2)
        reduce(&state, .setSentence(sentences(count: 3, chapter: next), []))
        #expect(!state.isLayoutReady)
        #expect(state.chapterLayout.chapter == next)

        // 이전 장 행의 늦은 이벤트.
        measured(&state, [
            rowID(1): VerseRowGeometry(
                underlineOffsets: [30, 60],
                titleHeight: 20,
                rowFrame: CGRect(x: 0, y: 0, width: 1, height: 1),
                canvasFrameInRow: CGRect(x: 0, y: 0, width: 1, height: 1)
            )
        ])

        #expect(state.chapterLayout.textMeasurements.isEmpty)
        #expect(state.chapterLayout.measuredFrames.isEmpty)
        #expect(!state.isLayoutReady)

        // 새 장의 행은 정상 반영된다.
        var batch: [SentencesWithDrawingFeature.State.ID: VerseRowGeometry] = [:]
        for verse in 1...3 {
            batch[rowID(verse, chapter: next)] = VerseRowGeometry(underlineOffsets: [30])
        }
        measured(&state, batch)
        #expect(state.isLayoutReady)
        #expect(state.chapterLayout.layout?.regions.count == 3)
    }

    @Test("소제목 높이와 실측 높이는 재계산을 일으키고, 행 frame 은 원점만 주므로 재계산하지 않는다 (R13)")
    func titleHeightAndMeasuredHeightRebuildButRowFrameDoesNot() {
        var state = CarveDetailFeature.State.initialState
        reduce(&state, .view(.layoutHostingChanged(writingWidth: 372)))
        reduce(&state, .setSentence(sentences(count: 2), []))
        measured(&state, [
            rowID(1): VerseRowGeometry(underlineOffsets: [30]),
            rowID(2): VerseRowGeometry(underlineOffsets: [30])
        ])
        let before = state.chapterLayout.layout

        measured(&state, [rowID(2): VerseRowGeometry(titleHeight: 26)])
        #expect(state.chapterLayout.titleHeights[2] == 26)
        #expect(state.chapterLayout.buildCount == 2)
        #expect(state.chapterLayout.layout != before)

        // 행 frame 만 오면 합칠 수도 없고, 레이아웃 입력도 아니다.
        let afterTitle = state.chapterLayout.layout
        measured(&state, [rowID(1): VerseRowGeometry(rowFrame: CGRect(x: 10, y: 2, width: 733, height: 55))])
        #expect(state.chapterLayout.measuredFrames[1] == nil)
        #expect(state.chapterLayout.buildCount == 2)
        #expect(state.chapterLayout.layout == afterTitle)

        // 행 안 캔버스 영역이 오면 원점이 합쳐지고, **높이는 레이아웃 입력이라 재계산된다** (R13).
        measured(&state, [rowID(1): VerseRowGeometry(canvasFrameInRow: CGRect(x: 372, y: 0, width: 372, height: 57))])
        #expect(state.chapterLayout.measuredFrames[1] == CGRect(x: 382, y: 2, width: 372, height: 57))
        #expect(state.chapterLayout.buildCount == 3)
        // 예측은 topPadding 25 + 1줄 30 = 55 였다. 실측 57 이 이긴다.
        #expect(state.chapterLayout.layout?.regions[0].writingRect.height == 57)
        #expect(state.chapterLayout.columnOrigin == CGPoint(x: 382, y: 0))

        // 같은 값이 다시 오면 재계산하지 않는다.
        measured(&state, [rowID(1): VerseRowGeometry(canvasFrameInRow: CGRect(x: 372, y: 0, width: 372, height: 57))])
        #expect(state.chapterLayout.buildCount == 3)
    }

    @Test("실측 높이가 없어도 게이트가 열리고, 도착해 재계산돼도 게이트는 닫히지 않는다 (R13)")
    func gateOpensBeforeMeasuredHeightsAndStaysOpenAfterRebuild() {
        var state = CarveDetailFeature.State.initialState
        reduce(&state, .view(.layoutHostingChanged(writingWidth: 372)))
        reduce(&state, .setSentence(sentences(count: 2), []))

        // 밑줄 실측만으로 게이트가 열린다 — 실측 높이는 레이아웃 완성의 조건이 아니다.
        measured(&state, [
            rowID(1): VerseRowGeometry(underlineOffsets: [30, 60]),
            rowID(2): VerseRowGeometry(underlineOffsets: [30])
        ])
        #expect(state.isLayoutReady)
        #expect(state.chapterLayout.buildCount == 1)
        let padding = ChapterLayoutHosting.firstVerseTopPadding
        #expect(state.chapterLayout.layout?.regions[0].writingRect.height == padding + 2 * SentenceSetting.initialState.linePitch)   // 예측
        #expect(state.chapterLayout.canvasFramesInRow.isEmpty)

        // 실측 높이가 뒤늦게 도착 — 예측 → 실측으로 한 번 더 지어지고, 그 사이 게이트는 닫히지 않는다.
        measured(&state, [
            rowID(1): VerseRowGeometry(canvasFrameInRow: CGRect(x: 372, y: 0, width: 372, height: 86)),
            rowID(2): VerseRowGeometry(canvasFrameInRow: CGRect(x: 372, y: 0, width: 372, height: 30.5))
        ])
        #expect(state.isLayoutReady)
        #expect(state.chapterLayout.buildCount == 2)
        #expect(state.chapterLayout.layout?.regions[0].writingRect.height == 86)
        #expect(state.chapterLayout.layout?.regions[1].writingRect.height == 30.5)
    }

    @Test("이전 장 행의 실측 높이는 새 장 레이아웃에 적용되지 않는다 (§14 6-3 계열)")
    func staleChapterMeasuredHeightIsNotApplied() {
        var state = CarveDetailFeature.State.initialState
        reduce(&state, .view(.layoutHostingChanged(writingWidth: 372)))
        reduce(&state, .setSentence(sentences(count: 2), []))
        measured(&state, [
            rowID(1): VerseRowGeometry(underlineOffsets: [30], canvasFrameInRow: CGRect(x: 372, y: 0, width: 372, height: 99)),
            rowID(2): VerseRowGeometry(underlineOffsets: [30], canvasFrameInRow: CGRect(x: 372, y: 0, width: 372, height: 99))
        ])
        #expect(state.chapterLayout.layout?.regions[0].writingRect.height == 99)

        let next = BibleChapter(title: .genesis, chapter: 2)
        reduce(&state, .setSentence(sentences(count: 2, chapter: next), []))
        measured(&state, [
            rowID(1, chapter: next): VerseRowGeometry(underlineOffsets: [30]),
            rowID(2, chapter: next): VerseRowGeometry(underlineOffsets: [30])
        ])
        let padding = ChapterLayoutHosting.firstVerseTopPadding
        #expect(state.chapterLayout.layout?.regions[0].writingRect.height == padding + SentenceSetting.initialState.linePitch)
        let buildCount = state.chapterLayout.buildCount

        // 이전 장 행 id 로 늦게 도착한 실측 높이 — id 조회에 실패해 버려진다.
        measured(&state, [rowID(1): VerseRowGeometry(canvasFrameInRow: CGRect(x: 372, y: 0, width: 372, height: 99))])

        #expect(state.chapterLayout.canvasFramesInRow.isEmpty)
        #expect(state.chapterLayout.buildCount == buildCount)
        #expect(state.chapterLayout.layout?.regions[0].writingRect.height == padding + SentenceSetting.initialState.linePitch)
    }

    @Test("폭이 나중에 도착해도 이미 모인 실측으로 곧바로 레이아웃이 완성된다 (§6-4 도착 순서 무관)")
    func widthArrivingLastCompletesLayout() {
        var state = CarveDetailFeature.State.initialState
        reduce(&state, .setSentence(sentences(count: 2), []))
        measured(&state, [
            rowID(1): VerseRowGeometry(underlineOffsets: [30]),
            rowID(2): VerseRowGeometry(underlineOffsets: [30])
        ])
        #expect(!state.isLayoutReady)

        reduce(&state, .view(.layoutHostingChanged(writingWidth: 372)))

        #expect(state.isLayoutReady)
        #expect(state.chapterLayout.layout?.writingWidth == 372)
    }

    @Test("metadata 가 없는 legacy 행은 band 수를 주지 않고, metadata 가 있으면 band 수를 준다")
    func savedBandCountComesOnlyFromMetadata() throws {
        let legacy = BibleDrawing(bibleTitle: chapter, verse: 1)
        #expect(CarveDetailFeature.savedBandCount(of: legacy) == nil)
        #expect(CarveDetailFeature.savedBandCount(of: nil) == nil)

        let metadata = DrawingLayoutMetadata(
            baseWritingWidth: 372,
            baseWritingHeight: 120,
            baseUnderlineAnchors: [0, 30, 60, 90],
            layoutSignature: "cl1-test"
        )
        let versioned = BibleDrawing(
            bibleTitle: chapter,
            verse: 2,
            layoutMetadataData: try JSONEncoder().encode(metadata)
        )
        #expect(CarveDetailFeature.savedBandCount(of: versioned) == 4)
    }
}
