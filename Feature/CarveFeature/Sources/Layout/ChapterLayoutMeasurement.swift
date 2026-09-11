//
//  ChapterLayoutMeasurement.swift
//  CarveFeature
//
//  Created by Claude on 9/5/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import CarveToolkit
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

// MARK: - 레이아웃 Δ 안전망 (설계 §14 — D9 R13)

/// 예측 좌표와 실제 렌더가 얼마나 어긋났는지에 대한 판정.
///
/// **§6-2 합성 게이트(`ChapterLayoutMeasurement.isReady`)와 별개다.** 합성 게이트는 절 개수만 보므로
/// Δ 가 87.5pt 여도 `gate PASS` 이고, 그 상태의 필기는 장 하단에서 잘못된 절에 귀속된다 (G3 위반).
/// 그렇다고 Δ 를 합성 게이트에 넣으면 오탐 하나로 **기존 잉크가 안 보이거나 미저장분이 유실**될 수 있다 (§15).
/// 그래서 이 판정은 **새 입력만** 막는다 — 합성·표시·저장은 무엇이 어긋나든 계속 돈다.
///
/// | 조건 | 동작 |
/// |---|---|
/// | Δ > `tolerance` (1pt) | Debug 로그 |
/// | Δ > `lineSpace` (한 줄 — 귀속이 확실히 틀어지는 크기) | 그 위에 더해 **새 입력 차단** |
///
/// 이것은 **결함의 대체재가 아니라 안전망**이다. R13 수정(실측 높이)이 본체다.
public struct LayoutDeltaVerdict: Equatable, Sendable {
    /// Debug 로그 허용치. 디버그 HUD 의 `tol` 과 같은 값이다.
    public static let tolerance: CGFloat = 1

    /// 가장 크게 어긋난 절.
    public let verse: Int
    /// 그 절의 Δ (`FrameDelta.magnitude`).
    public let magnitude: CGFloat
    public let topDelta: CGFloat
    public let heightDelta: CGFloat
    /// 차단 임계값으로 쓴 한 줄 높이.
    public let lineSpace: CGFloat
    /// 허용치 초과 — Debug 에서 시끄럽게 알린다.
    public var exceedsTolerance: Bool { magnitude > Self.tolerance }
    /// 새 입력을 막아야 하는가. `blocksInput == false` 여도 `exceedsTolerance` 는 참일 수 있다.
    public let blocksInput: Bool

    public init(verse: Int, magnitude: CGFloat, topDelta: CGFloat, heightDelta: CGFloat, lineSpace: CGFloat, blocksInput: Bool) {
        self.verse = verse
        self.magnitude = magnitude
        self.topDelta = topDelta
        self.heightDelta = heightDelta
        self.lineSpace = lineSpace
        self.blocksInput = blocksInput
    }

    /// 허용치를 넘은 Δ 를 Debug 에서 시끄럽게 남긴다. 어긋난 절과 값을 함께 적는다.
    ///
    /// 실측은 절마다 계속 도착하므로 값이 바뀔 때마다 찍으면 로그가 폭주한다. **의미 있는 변화**에만 남긴다 —
    /// 차단 여부가 바뀌었을 때 · 허용치를 새로 넘겼을 때 · 최악 절이 바뀌었을 때 · Δ 가 허용치 이상 더 벌어졌을 때.
    /// - Parameters:
    ///   - previous: 직전 판정.
    ///   - current: 새 판정.
    ///   - chapter: 대상 장.
    static func logIfNoteworthy(previous: LayoutDeltaVerdict?, current: LayoutDeltaVerdict?, chapter: BibleChapter) {
        #if DEBUG
        guard let current, current.exceedsTolerance else { return }
        let isNoteworthy = previous?.blocksInput != current.blocksInput
            || previous?.exceedsTolerance != true
            || previous?.verse != current.verse
            || abs((previous?.magnitude ?? 0) - current.magnitude) > tolerance
        guard isNoteworthy else { return }
        Log.error(
            current.blocksInput
                ? "단일 Canvas — 레이아웃 Δ 가 한 줄을 넘어 새 입력을 막는다 (§14 안전망)"
                : "단일 Canvas — 레이아웃 Δ 가 허용치를 넘었다 (입력은 열어 둔다)",
            "\(chapter.title.rawValue).\(chapter.chapter)",
            "worst v\(current.verse)",
            String(format: "Δ %.2fpt (top %+.2f · height %+.2f)", current.magnitude, current.topDelta, current.heightDelta),
            String(format: "tol %.2fpt · lineSpace %.2fpt", tolerance, current.lineSpace)
        )
        #endif
    }
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
/// | 행 안 캔버스 영역의 **높이** (`recordCanvasFrameInRow`) | **레이아웃 계산의 입력** (R13) — 절의 실측 높이 | 예측식(`줄 수 × lineSpace`)으로 떨어진다. 게이트는 열린다 |
/// | 행 frame 의 **원점** (`recordRowFrame`) | **검증 전용** — `columnOrigin` 과 `frameDeltas.topDelta` | 레이아웃에는 영향 없음 |
///
/// 원래는 실측 frame 전체가 검증 전용이었다 — "빌더가 실제 배치를 재현하는가"(S3) 를 보기 위해서다.
/// 그런데 D9 실기기에서 빌더의 **높이 예측만** 실제 렌더와 어긋나(R13, 절당 0.5pt 누적) 그 전제가 깨졌다.
/// 높이는 실측을 쓰고(`VerseLayoutInput.measuredHeight`), 검증은 `topDelta` 가 이어받는다.
///
/// > ⚠️ **알려진 부작용.** 실측 높이를 레이아웃 입력으로 쓰면 `frameDeltas.heightDelta` 가 **구조적으로 0** 이 된다
/// > (Pass 2 여유 높이가 붙은 절만 예외이며, 그때는 정확히 `−extraBands × lineSpace` 다).
/// > 즉 높이 Δ 는 더 이상 독립 검증이 아니라 자기 자신을 검증한다. 남는 독립 검증은 **`topDelta`** 이고,
/// > 그것은 여전히 `metrics`(`topInset`/`verseSpacing`/`bottomInset`)와 `leadingInset` 의 적재를 검증한다.
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
    /// 절별 행 frame (콘텐츠 좌표) — `measuredFrames` 를 만들기 위한 절반.
    private(set) var rowFrames: [Int: CGRect] = [:]
    /// 절별 캔버스 영역 (행 안 좌표) — 나머지 절반이자 **실측 높이의 출처**(R13).
    private(set) var canvasFramesInRow: [Int: CGRect] = [:]
    /// 필사 컬럼 폭 (= 절 캔버스 폭 = `ChapterLayout.writingWidth`).
    private(set) var writingWidth: CGFloat = 0
    /// 마지막 계산에 쓴 줄 거리(`SentenceSetting.linePitch`). 안전망의 차단 임계값(한 줄)이자 빌더의 band 폭이다.
    /// 설정값이므로 장이 바뀌어도 유지된다 (`writingWidth` 와 같은 성격).
    private(set) var lineSpace: CGFloat = 0
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

    /// Pass 2 여유 높이(설계 §6-3)가 실제로 붙은 절이 하나라도 있는가.
    ///
    /// 그 여유는 저장된 필사가 현재 텍스트보다 많은 줄을 요구할 때 `writingRect` 를 **의도적으로** 부풀린 값이라
    /// 행은 그만큼 커지지 않는다. 즉 Δ 가 의도적으로 커지며, 그 상태의 Δ 로는 "의도한 여유" 와 "예측 결함" 을
    /// 구별할 수 없다. 안전망은 구별할 수 없을 때 **막지 않는다** — 무해한 조건으로 필기를 막는 쪽이 더 나쁜 회귀다.
    var hasReflowSlack: Bool {
        verses.contains { verse in
            guard let saved = savedBandCounts[verse] else { return false }
            return saved > (textMeasurements[verse]?.lineCount ?? 0)
        }
    }

    /// 안전망 판정 (`LayoutDeltaVerdict`). 실측 frame 이 없으면 nil — 판정할 근거가 없다는 뜻이다.
    var layoutDeltaVerdict: LayoutDeltaVerdict? {
        guard let worst = worstFrameDelta else { return nil }
        return LayoutDeltaVerdict(
            verse: worst.verse,
            magnitude: worst.magnitude,
            topDelta: worst.topDelta,
            heightDelta: worst.heightDelta,
            lineSpace: lineSpace,
            blocksInput: lineSpace > 0 && worst.magnitude > lineSpace && !hasReflowSlack
        )
    }

    // MARK: 입력

    /// 새 장의 측정을 시작한다. 이전 장의 모든 실측값을 버린다 (설계 §6-4 의 요청 취소에 해당).
    ///
    /// **같은 장을 다시 시작할 때는 기하 실측값을 유지한다.** `rowFrames`·`canvasFramesInRow`·`titleHeights` 는
    /// SwiftUI 의 `onGeometryChange` 로만 들어오는데, 그것은 **값이 바뀔 때만** 부른다. 같은 장을 같은 폭·설정으로
    /// 다시 불러오면(설정 토글에 따른 재로드 등) 기하가 그대로여서 콜백이 다시 오지 않고, 여기서 지운 값은
    /// **아무도 복구할 수 없다.** 그 상태에서는 세 가지가 함께 무너진다 (R24, 2026-09-08 실기기 실측):
    ///
    /// 1. `measuredFrames` 가 비어 `CarveDetailView.updateActiveCanvases()` 가 항상 즉시 반환한다
    ///    → N-Canvas 에서 **새 행에 캔버스가 붙지 않아 필기가 보이지 않는다.**
    /// 2. `canvasFramesInRow` 가 비어 레이아웃이 **실측 높이 대신 예측식으로 후퇴**한다 — R13 이 없앤 그 상태다
    ///    (시편 122편 `H` 3016.00 → 2977.00).
    /// 3. `frameDeltas` 가 비어 **Δ 안전망이 눈을 감는다** (`deltaMax=unmeasured`).
    ///
    /// 폭·설정이 실제로 바뀌면 컬럼이 다시 지어져 콜백이 오고 이 값들은 덮인다. 즉 유지해도 낡은 값이 남지 않는다.
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
        // 장 자체가 바뀌면 이전 장의 기하는 의미가 없다. 같은 장이면 기하는 여전히 참이다.
        let isSameChapter = self.chapter == chapter && self.verses == verses
        self.chapter = chapter
        self.expectedVerseCount = verses.count
        self.verses = verses
        self.savedBandCounts = savedBandCounts
        textMeasurements = [:]
        if !isSameChapter {
            titleHeights = [:]
            measuredFrames = [:]
            rowFrames = [:]
            canvasFramesInRow = [:]
        }
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

    /// 행 frame(콘텐츠 좌표)을 기록하고, 행 안 캔버스 영역이 이미 있으면 둘을 합쳐 `measuredFrames` 를 갱신한다.
    ///
    /// 행 frame 은 **원점만** 쓰인다 (`columnOrigin` · `topDelta`). 레이아웃 입력이 아니므로 재계산을 일으키지 않는다.
    /// - Returns: `measuredFrames` 가 실제로 바뀌었으면 true.
    @discardableResult
    mutating func recordRowFrame(verse: Int, frame: CGRect) -> Bool {
        guard verses.contains(verse) else { return false }
        rowFrames[verse] = frame
        return combineFrames(verse: verse)
    }

    /// 행 안 캔버스 영역(행 좌표)을 기록하고, 행 frame 이 이미 있으면 둘을 합쳐 `measuredFrames` 를 갱신한다.
    ///
    /// **이 frame 의 높이는 레이아웃 입력이다** (`VerseLayoutInput.measuredHeight`, R13). 행 frame 과 달리
    /// 여기서는 높이만 쓰므로, 행 frame 이 아직 오지 않아 `measuredFrames` 를 합칠 수 없어도 재계산 대상이다.
    /// - Returns: 레이아웃 입력(높이) 또는 `measuredFrames` 가 실제로 바뀌었으면 true.
    @discardableResult
    mutating func recordCanvasFrameInRow(verse: Int, frame: CGRect) -> Bool {
        guard verses.contains(verse) else { return false }
        let previousHeight = canvasFramesInRow[verse]?.height
        canvasFramesInRow[verse] = frame
        let framesChanged = combineFrames(verse: verse)
        return framesChanged || previousHeight != frame.height
    }

    private mutating func combineFrames(verse: Int) -> Bool {
        guard let row = rowFrames[verse], let inner = canvasFramesInRow[verse] else { return false }
        return recordFrame(verse: verse, frame: CGRect(
            x: row.minX + inner.minX, y: row.minY + inner.minY, width: inner.width, height: inner.height
        ))
    }

    // MARK: 레이아웃 계산

    /// 입력이 전부 모였으면 레이아웃을 (재)계산한다.
    ///
    /// 조건: 전 절 텍스트 실측 + `writingWidth > 0`. 하나라도 빠지면 `layout` 을 건드리지 않고 nil 을 돌려준다.
    /// **실측 높이는 조건이 아니다** — 아직 오지 않은 절은 예측식으로 떨어지므로 게이트가 늦게 열리지 않는다 (R13).
    /// 이미 완성된 뒤 실측값이 갱신되면 다시 계산한다 — 그 사이 게이트는 닫히지 않는다
    /// (절 개수는 그대로이므로). 즉 장 진입은 보통 **예측 → 실측**으로 두 번 이상 지어진다.
    /// Phase 3 은 그 두 번째 레이아웃을 `isEditing` / `pendingLayout` (설계 §4 · §8-1) 이 흡수한다 —
    /// 편집 중 도착한 레이아웃은 pencil-up 뒤에 적용된다.
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
        // 줄 띠 폭은 뷰가 실제로 그리는 줄 거리다(글꼴 줄 높이 + 줄 간격). 빌더 · Δ 가드가 같은 값을 쓴다.
        lineSpace = setting.linePitch

        let inputs = verses.map { verse -> VerseLayoutInput in
            let text = textMeasurements[verse]
            return VerseLayoutInput(
                verse: verse,
                textLineCount: text?.lineCount ?? 0,
                savedBandCount: savedBandCounts[verse],
                measuredUnderlineAnchors: text?.underlineAnchors,
                // R13 — 행 높이는 예측하지 않고 실측을 쓴다. 아직 도착하지 않은 절만 빌더의 예측식으로 떨어진다.
                measuredHeight: canvasFramesInRow[verse]?.height,
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
            metrics: metrics,
            linePitch: lineSpace
        )
        layout = built
        buildCount += 1
        if firstBuildDuration == nil, let measureStartedAt {
            firstBuildDuration = measureStartedAt.duration(to: now)
        }
        return built
    }
}
