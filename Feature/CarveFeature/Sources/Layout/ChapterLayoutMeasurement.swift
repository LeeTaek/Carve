//
//  ChapterLayoutMeasurement.swift
//  CarveFeature
//
//  Created by Claude on 9/5/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import CoreGraphics
import Domain
import Foundation

// MARK: - 절 하나의 텍스트 실측값

/// View 계층(`Text.LayoutKey`)이 절 하나에 대해 실측한 값.
struct VerseTextMeasurement: Equatable, Sendable {
    /// 실제로 접힌 텍스트 줄 수 (설계 §6-3 의 `N_now`).
    let lineCount: Int
    /// `writingRect` 상단 기준 밑줄 y. 1절의 상단 여백(`topPadding`)이 포함된 값이다.
    let underlineAnchors: [CGFloat]
}

// MARK: - 장 전체 측정 상태

/// Phase 2 — 장 전체의 레이아웃 측정을 모아 `ChapterLayout` 을 만드는 순수 상태 (설계 §6).
///
/// 비동기로 도착하는 절별 실측값을 보관하고, **전 절이 모였을 때만** `ChapterLayoutBuilder` 를 호출한다.
/// 부분 레이아웃을 정상 상태처럼 취급하지 않는다(P4). 그 판정은 `ChapterLayout.satisfiesCompositionGate` 하나로 모은다.
///
/// ## 두 종류의 입력을 구분한다
///
/// | 입력 | 용도 | 없으면 |
/// |---|---|---|
/// | 텍스트 실측 (`recordText`) · 소제목 높이 (`recordTitleHeight`) · 필사 폭 (`setWritingWidth`) | **레이아웃 계산의 입력** | 레이아웃을 만들지 않는다 (게이트 닫힘) |
/// | 행 frame 실측 (`recordFrame`) | **검증 전용** — 예측한 `writingRect` 와 실제 행 위치의 차이(`frameDeltas`) | 레이아웃에는 영향 없음 |
///
/// 행 frame 을 레이아웃 입력으로 쓰지 않는 이유: 그러면 "빌더가 실제 배치를 재현하는가"(S3) 를 확인할 수 없다.
/// 빌더는 **선언된 배치 상수**(`ChapterLayoutHosting`)와 텍스트 실측만으로 좌표를 예측하고,
/// 실측 frame 은 그 예측이 맞는지를 보는 자 역할만 한다.
///
/// - Note: 이 타입은 UIKit/PencilKit/SwiftUI 를 모른다. Reducer 상태에 그대로 들어가며 단위 테스트로 전부 검증한다.
struct ChapterLayoutMeasurement: Equatable, Sendable {
    /// 예측 `writingRect` 와 실측 행 frame 의 차이.
    struct FrameDelta: Equatable, Sendable {
        let verse: Int
        /// 실측 상단 − 예측 상단.
        let topDelta: CGFloat
        /// 실측 높이 − 예측 높이.
        let heightDelta: CGFloat

        /// 두 차이 중 큰 절댓값.
        var magnitude: CGFloat { max(abs(topDelta), abs(heightDelta)) }
    }

    /// 측정 대상 장. `begin` 전에는 nil.
    private(set) var chapter: BibleChapter?
    /// 본문 fetch 로 확정된 절 개수 (설계 §6-4 의 `expectedVerseCount`). 게이트의 기준값이다.
    private(set) var expectedVerseCount: Int?
    /// 본문 순서대로의 절 번호. `regions` 의 순서가 된다.
    private(set) var verses: [Int] = []
    /// 절별 텍스트 실측값.
    private(set) var textMeasurements: [Int: VerseTextMeasurement] = [:]
    /// 절별 소제목 높이 (소제목이 있는 절만).
    private(set) var titleHeights: [Int: CGFloat] = [:]
    /// 절별 저장 band 수 (설계 §6-3 의 `N_saved`). metadata 가 없는 legacy 행은 없다.
    private(set) var savedBandCounts: [Int: Int] = [:]
    /// 절별 캔버스 영역의 실측 frame (`ChapterLayoutHosting.coordinateSpaceName` 좌표). **검증 전용.**
    private(set) var measuredFrames: [Int: CGRect] = [:]
    /// 필사 컬럼 폭 (= 절 캔버스 폭 = `ChapterLayout.writingWidth`).
    private(set) var writingWidth: CGFloat = 0
    /// 전 절 측정으로 완성된 레이아웃. 게이트 판정은 이 값과 `expectedVerseCount` 로 한다.
    private(set) var layout: ChapterLayout?
    /// 이 장에서 레이아웃을 (재)계산한 횟수. 첫 완성 이후의 재계산은 실측값 갱신에 의한 것이다.
    private(set) var buildCount = 0
    /// `begin` 시각. 첫 완성까지의 소요 시간을 재기 위한 기준점이다.
    private(set) var measureStartedAt: ContinuousClock.Instant?
    /// `begin` 부터 **첫** 완성까지의 소요 시간. 재계산은 갱신하지 않는다.
    private(set) var firstBuildDuration: Duration?

    init() { }

    // MARK: 파생값

    /// 설계 §6-2 입력 게이트. 이 값이 false 면 합성·입력·저장을 금지한다.
    var isReady: Bool {
        guard let layout, let expectedVerseCount else { return false }
        return layout.satisfiesCompositionGate(expectedVerseCount: expectedVerseCount)
    }

    /// 아직 텍스트 실측이 도착하지 않은 절.
    var missingVerses: [Int] {
        verses.filter { textMeasurements[$0] == nil }
    }

    /// 텍스트 실측이 전 절에 대해 모였는가.
    var isTextComplete: Bool {
        !verses.isEmpty && missingVerses.isEmpty
    }

    /// 실측 frame 으로부터 얻은 필사 컬럼의 원점 (content 좌표).
    ///
    /// 설계 §5 의 `columnOrigin` — 캔버스 content 좌표 = layout 좌표 + `columnOrigin`.
    /// Phase 2 에서는 N 개 캔버스가 모두 같은 x 에 놓이므로 아무 행의 `minX` 나 같다.
    /// y 는 레이아웃 원점이 곧 content 원점이라 0 이다.
    var columnOrigin: CGPoint? {
        guard let first = verses.lazy.compactMap({ measuredFrames[$0] }).first else { return nil }
        return CGPoint(x: first.minX, y: 0)
    }

    /// 예측 `writingRect` 와 실측 frame 의 절별 차이. 레이아웃과 실측이 둘 다 있는 절만 포함한다.
    var frameDeltas: [FrameDelta] {
        guard let layout else { return [] }
        return layout.regions.compactMap { region in
            guard let frame = measuredFrames[region.verse] else { return nil }
            return FrameDelta(
                verse: region.verse,
                topDelta: frame.minY - region.writingRect.minY,
                heightDelta: frame.height - region.writingRect.height
            )
        }
    }

    /// 가장 크게 어긋난 절. 실측이 없으면 nil.
    var worstFrameDelta: FrameDelta? {
        frameDeltas.max { $0.magnitude < $1.magnitude }
    }

    // MARK: 입력

    /// 새 장의 측정을 시작한다. 이전 장의 모든 실측값을 버린다 (설계 §6-4 의 요청 취소에 해당).
    /// - Parameters:
    ///   - chapter: 대상 장.
    ///   - verses: 본문 순서대로의 절 번호.
    ///   - savedBandCounts: 절별 저장 band 수. metadata 가 있는 행만.
    ///   - now: 시작 시각.
    mutating func begin(
        chapter: BibleChapter,
        verses: [Int],
        savedBandCounts: [Int: Int],
        now: ContinuousClock.Instant
    ) {
        self.chapter = chapter
        self.expectedVerseCount = verses.count
        self.verses = verses
        self.savedBandCounts = savedBandCounts
        textMeasurements = [:]
        titleHeights = [:]
        measuredFrames = [:]
        layout = nil
        buildCount = 0
        measureStartedAt = now
        firstBuildDuration = nil
    }

    /// 필사 컬럼 폭을 갱신한다.
    /// - Parameter width: 새 폭.
    /// - Returns: 값이 실제로 바뀌었으면 true.
    @discardableResult
    mutating func setWritingWidth(_ width: CGFloat) -> Bool {
        let normalized = max(0, width)
        guard normalized != writingWidth else { return false }
        writingWidth = normalized
        return true
    }

    /// 절의 텍스트 실측값을 기록한다.
    ///
    /// 빈 측정(줄 0개)은 기록하지 않는다 — `Text.LayoutKey` 의 기본값이 빈 배열이라 초기 렌더에서 한 번 들어올 수 있는데,
    /// 그것을 "측정 완료" 로 치면 게이트가 잘못 열린다.
    /// - Parameters:
    ///   - verse: 절 번호. 현재 장의 절이 아니면 무시한다.
    ///   - underlineAnchors: `writingRect` 상단 기준 밑줄 y.
    /// - Returns: 값이 실제로 바뀌었으면 true.
    @discardableResult
    mutating func recordText(verse: Int, underlineAnchors: [CGFloat]) -> Bool {
        guard verses.contains(verse), !underlineAnchors.isEmpty else { return false }
        let measurement = VerseTextMeasurement(lineCount: underlineAnchors.count, underlineAnchors: underlineAnchors)
        guard textMeasurements[verse] != measurement else { return false }
        textMeasurements[verse] = measurement
        return true
    }

    /// 절 위 소제목의 높이를 기록한다.
    /// - Parameters:
    ///   - verse: 절 번호.
    ///   - height: 실측 높이. 0 이하면 소제목 없음으로 본다.
    /// - Returns: 값이 실제로 바뀌었으면 true.
    @discardableResult
    mutating func recordTitleHeight(verse: Int, height: CGFloat) -> Bool {
        guard verses.contains(verse) else { return false }
        let normalized: CGFloat? = height > 0 ? height : nil
        guard titleHeights[verse] != normalized else { return false }
        titleHeights[verse] = normalized
        return true
    }

    /// 절 캔버스 영역의 실측 frame 을 기록한다. **레이아웃에는 영향이 없다** (검증 전용).
    /// - Parameters:
    ///   - verse: 절 번호.
    ///   - frame: content 좌표의 frame.
    /// - Returns: 값이 실제로 바뀌었으면 true.
    @discardableResult
    mutating func recordFrame(verse: Int, frame: CGRect) -> Bool {
        guard verses.contains(verse), measuredFrames[verse] != frame else { return false }
        measuredFrames[verse] = frame
        return true
    }

    // MARK: 레이아웃 계산

    /// 입력이 전부 모였으면 레이아웃을 (재)계산한다.
    ///
    /// 조건: 전 절 텍스트 실측 + `writingWidth > 0`. 하나라도 빠지면 `layout` 을 건드리지 않고 nil 을 돌려준다.
    /// 이미 완성된 뒤 실측값이 갱신되면 다시 계산한다 — 그 사이 게이트는 닫히지 않는다
    /// (절 개수는 그대로이므로). 잠깐 이전 값이 섞인 레이아웃이 보일 수 있으나 Phase 2 에는 합성이 없어 무해하다.
    /// Phase 3 은 이 지점에 `isEditing` / `pendingLayout` (설계 §4) 을 끼워야 한다.
    /// - Parameters:
    ///   - setting: 본문 설정.
    ///   - isLeftHanded: 왼손 모드.
    ///   - metrics: 배치 여백 (`ChapterLayoutHosting.metrics`).
    ///   - now: 현재 시각. 첫 완성의 소요 시간 계산용.
    /// - Returns: 새로 계산된 레이아웃. 조건 미달이면 nil.
    @discardableResult
    mutating func rebuildIfComplete(
        setting: SentenceSetting,
        isLeftHanded: Bool,
        metrics: ChapterLayoutMetrics,
        now: ContinuousClock.Instant
    ) -> ChapterLayout? {
        guard let chapter, isTextComplete, writingWidth > 0 else { return nil }

        let inputs = verses.map { verse -> VerseLayoutInput in
            let text = textMeasurements[verse]
            return VerseLayoutInput(
                verse: verse,
                textLineCount: text?.lineCount ?? 0,
                savedBandCount: savedBandCounts[verse],
                measuredUnderlineAnchors: text?.underlineAnchors,
                leadingInset: ChapterLayoutHosting.leadingInset(titleHeight: titleHeights[verse]),
                topPadding: ChapterLayoutHosting.topPadding(forVerse: verse)
            )
        }
        let built = ChapterLayoutBuilder().build(
            chapter: chapter,
            writingWidth: writingWidth,
            setting: setting,
            isLeftHanded: isLeftHanded,
            verses: inputs,
            metrics: metrics
        )
        layout = built
        buildCount += 1
        if firstBuildDuration == nil, let measureStartedAt {
            firstBuildDuration = measureStartedAt.duration(to: now)
        }
        return built
    }
}
