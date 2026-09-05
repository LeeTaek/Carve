//
//  LineBandReflow.swift
//  CarveFeature
//
//  Created by Claude on 9/5/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import CoreGraphics
import Domain
import Foundation
import PencilKit

// MARK: - 결과 타입 — §9-4 비파괴 원칙(P10)을 타입으로 강제한다 ★

/// 한 절의 reflow 처리 결과 (설계 §9-3).
enum VerseReflowOutcome: Equatable, Sendable {
    /// metadata 의 band 별로 현재 밑줄에 재배치했다.
    case reflowed
    /// 저장 band 를 현재 밑줄에 대응시킬 수 없어 **첫 밑줄 기준으로 통째 보존**했다 (설계 §9-3-1).
    case layoutMismatch
    /// metadata 가 없는 legacy 행이라 **좌표를 전혀 건드리지 않았다** (설계 §9-3 / §10-2).
    case legacyPassthrough
}

/// reflow 된 절 하나 — **표시용 값이다.**
///
/// > ⚠️ **이 값을 저장 경로에 넣지 마십시오 (설계 §9-4 / P10).**
/// > reflow 는 표시 시점 변환이고, 저장은 사용자가 그 절을 실제로 편집할 때만 일어난다.
/// > 설정 화면에서 폰트를 이리저리 바꿔보는 것만으로 원본이 훼손되면 안 된다.
/// >
/// > 그래서 이 타입은 **`Data` 를 노출하지 않는다.** 저장 명령(`VerseDrawingMutation`, 설계 §5)은
/// > `Data` 를 요구하므로, 이 타입만으로는 저장 경로에 그대로 흘려보낼 수 없다.
/// > 프로퍼티 이름도 `displayDrawing` 으로 두어 호출부에서 용도가 드러나게 한다.
struct ReflowedVerseDrawing: Sendable {
    /// 절 번호.
    let verse: Int
    /// **표시용** drawing. 좌표계는 `.reflowed` / `.layoutMismatch` 면 **캔버스 절대좌표**,
    /// `.legacyPassthrough` 면 **입력 그대로**(무변환)다.
    let displayDrawing: PKDrawing
    /// 이 절이 어떤 정책으로 처리됐는지.
    let outcome: VerseReflowOutcome

    /// 설계 §9-3-1 의 `layoutMismatch` 여부.
    ///
    /// **표시 상태이지 저장 상태가 아니다.** `State.layoutMismatchVerses`(설계 §4)에만 두고
    /// DB 에 기록하지 않는다.
    var isLayoutMismatch: Bool { outcome == .layoutMismatch }
}

/// 장 전체 reflow 결과.
struct ChapterReflowResult: Sendable {
    /// 절별 결과. 입력 순서를 보존한다.
    let verses: [ReflowedVerseDrawing]
    /// 전 절을 합성한 **표시용** 캔버스 drawing.
    ///
    /// - Warning: `.legacyPassthrough` 절은 좌표를 건드리지 않으므로(설계 §10-2)
    ///            합성 결과에서 위치가 보장되지 않는다. 런타임 legacy 판별과 좌표 변환은
    ///            Phase 3 의 legacy codec 이 담당하며, 그 전까지 이 합성은 metadata 가 있는
    ///            절에 대해서만 의미가 있다.
    let displayDrawing: PKDrawing
    /// 설계 §9-3-1 로 처리된 절 번호. `State.layoutMismatchVerses`(설계 §4)에 그대로 대응한다.
    /// **DB 에 기록하지 않는다.**
    let layoutMismatchVerses: Set<Int>
}

// MARK: - line band reflow (설계 §9-2)

/// 저장된 필사를 현재 레이아웃의 밑줄에 다시 앉히는 순수 로직 (설계 §9).
///
/// ```
/// 저장 stroke
///   → 저장 당시 metadata 의 baseUnderlineAnchors 로 band(줄) 판정
///   → 현재 layout 의 같은 index underline 으로 translate
///   → 폭이 줄었을 때만 uniform 축소 (scale = min(1, now / base))
/// ```
///
/// 상태도 부수효과도 없다. `StrokeOwnershipResolver` 와 마찬가지로 PencilKit 을 알지만
/// Reducer 가 아니므로 P9 를 위반하지 않는다(설계 §4).
///
/// ### 구현하지 않은 정책 행 — §9-3 "줄바꿈만 달라짐"
/// `metadata.textLineRanges` 와 **현재 줄의 문자 범위**를 겹쳐 가장 많이 겹치는 밑줄로 옮기는 규칙은
/// 이번 범위에서 **제외했다.** 현재 줄의 문자 범위는 `Text.Layout.Run.characterIndices` 실측이 있어야
/// 만들 수 있고(설계 §9-3의 S2 확정 사항), 그 측정은 Phase 2 에서 들어온다.
/// 자리는 `Input.currentTextLineRanges` 에 남겨 두었고 현재는 **읽지 않는다.**
/// 근거 없는 대체 구현을 넣지 않는다 — 잘못 맞춘 줄은 어긋난 줄보다 발견하기 어렵다.
struct LineBandReflow: Sendable {

    /// 절 하나의 reflow 입력.
    struct Input: Sendable {
        /// 절 번호.
        let verse: Int
        /// DB 에서 읽어온 drawing. 좌표계는 **첫 밑줄 원점의 절 로컬**이다
        /// (`drawingVersion == 3`, 설계 §10-1). metadata 가 nil 이면 좌표계는 미확정이다.
        let storedDrawing: PKDrawing
        /// 저장 시점 metadata. legacy 행이면 nil (설계 §10-2).
        let metadata: DrawingLayoutMetadata?
        /// **Phase 2 자리 — 현재 구현은 읽지 않는다.**
        ///
        /// 설계 §9-3 "줄바꿈만 달라짐" 행을 구현할 때 `metadata.textLineRanges` 와 겹침을
        /// 비교할 현재 줄의 문자 범위다. 측정( `Text.Layout` )이 선행되어야 하므로 비워 둔다.
        let currentTextLineRanges: [Range<Int>]?

        /// - Parameters:
        ///   - verse: 절 번호.
        ///   - storedDrawing: DB 에서 읽어온 drawing.
        ///   - metadata: 저장 시점 metadata. legacy 면 nil.
        ///   - currentTextLineRanges: Phase 2 자리. 현재는 사용하지 않는다.
        init(
            verse: Int,
            storedDrawing: PKDrawing,
            metadata: DrawingLayoutMetadata?,
            currentTextLineRanges: [Range<Int>]? = nil
        ) {
            self.verse = verse
            self.storedDrawing = storedDrawing
            self.metadata = metadata
            self.currentTextLineRanges = currentTextLineRanges
        }
    }

    /// §7-1 과 **같은** 앵커 규칙을 쓰기 위해 소유권 resolver 를 그대로 재사용한다.
    /// 규칙이 한쪽에서만 바뀌어 소유 절과 band 가 어긋나는 일을 구조적으로 막는다.
    private let ownership = StrokeOwnershipResolver()

    init() { }

    // MARK: - 절 단위

    /// 절 하나를 현재 레이아웃에 맞춰 다시 배치한다.
    /// - Parameters:
    ///   - input: 저장 drawing 과 metadata.
    ///   - region: 현재 레이아웃의 절 영역.
    /// - Returns: **표시용** 결과.
    func reflow(_ input: Input, into region: VerseCanvasRegion) -> ReflowedVerseDrawing {
        // ── metadata 없음 (legacy) → 무변환 (설계 §9-3 / §10-2) ─────────────────
        // 좌표계가 미확정이므로 "적당히 옮기는" 것이 곧 손상이다. 런타임 legacy 판별은 Phase 3 의 일이다.
        guard let metadata = input.metadata else {
            return ReflowedVerseDrawing(
                verse: input.verse,
                displayDrawing: input.storedDrawing,
                outcome: .legacyPassthrough
            )
        }

        let scale = Self.uniformScale(
            baseWidth: metadata.baseWritingWidth,
            currentWidth: region.writingRect.width
        )

        // ★ 기준점 변환은 여기 두 줄뿐이다. 다른 어디에서도 anchor 를 직접 더하거나 빼지 않는다.
        //   base    : §10-1 기준(첫 밑줄) — 저장 stroke 와 같은 좌표 공간.
        //   current : §5 기준(writingRect 상단) → 캔버스 절대좌표.
        let baseAnchors = metadata.normalizedBaseUnderlineAnchors
        let currentAnchors = UnderlineAnchorBasis.canvasAbsolute(
            writingRectRelative: region.underlineAnchors,
            writingRect: region.writingRect
        )

        guard let plan = BandPlan(
            base: baseAnchors,
            current: currentAnchors,
            writingRectTop: region.writingRect.minY
        ) else {
            // ── 매핑할 줄 없음 → 설계 §9-3-1 ────────────────────────────────
            let whole = Self.wholeVerseTransform(region: region, scale: scale)
            return ReflowedVerseDrawing(
                verse: input.verse,
                displayDrawing: transformed(input.storedDrawing) { _ in whole },
                outcome: .layoutMismatch
            )
        }

        // band 별 변환은 stroke 수와 무관하게 band 수만큼만 있으면 된다.
        let byBand = (0..<plan.base.count).map {
            plan.transform(forBand: $0, scale: scale, left: region.writingRect.minX)
        }
        return ReflowedVerseDrawing(
            verse: input.verse,
            displayDrawing: transformed(input.storedDrawing) { stroke in
                byBand[plan.band(of: bandAnchorY(of: stroke))]
            },
            outcome: .reflowed
        )
    }

    // MARK: - 장 단위

    /// 장 전체를 다시 배치한다.
    /// - Parameters:
    ///   - inputs: 절별 입력. 결과는 이 순서를 보존한다.
    ///   - layout: 현재 장 레이아웃.
    /// - Returns: 절별 결과와 합성 drawing.
    func reflow(_ inputs: [Input], into layout: ChapterLayout) -> ChapterReflowResult {
        var verses: [ReflowedVerseDrawing] = []
        var mismatched: Set<Int> = []
        var composed: [PKStroke] = []
        verses.reserveCapacity(inputs.count)

        for input in inputs {
            let result: ReflowedVerseDrawing
            if let region = layout.region(verse: input.verse) {
                result = reflow(input, into: region)
            } else {
                // 레이아웃에 없는 절 — §6-2 합성 게이트를 통과했다면 발생하지 않는다.
                // 좌표를 만들 근거가 없으므로 무변환으로 보존하고 mismatch 로 알린다. 잉크를 버리지 않는다.
                result = ReflowedVerseDrawing(
                    verse: input.verse,
                    displayDrawing: input.storedDrawing,
                    outcome: .layoutMismatch
                )
            }
            verses.append(result)
            if result.isLayoutMismatch { mismatched.insert(result.verse) }
            composed.append(contentsOf: result.displayDrawing.strokes)
        }

        return ChapterReflowResult(
            verses: verses,
            displayDrawing: PKDrawing(strokes: composed),
            layoutMismatchVerses: mismatched
        )
    }

    // MARK: - §9-2 uniform scale

    /// 폭 비율로 정하는 uniform scale.
    ///
    /// `min(1, now / base)` — **폭이 늘어나도 확대하지 않는다** (설계 §9-3).
    /// 확대하면 글씨 크기가 설정과 무관하게 변해 "내 필사가 커졌다" 로 보이기 때문이다.
    /// 세로로 균등 스케일하지 않는 이유는 설계 §9-2 의 그림 그대로다 — 폰트가 커지면 줄 수가 늘어난다.
    /// - Parameters:
    ///   - baseWidth: 저장 시점 필사 폭.
    ///   - currentWidth: 현재 필사 폭.
    /// - Returns: 1 이하의 배율. 어느 한쪽이 0 이하면 판단 근거가 없으므로 1(무변환)이다.
    static func uniformScale(baseWidth: CGFloat, currentWidth: CGFloat) -> CGFloat {
        guard baseWidth > 0, currentWidth > 0 else { return 1 }
        return min(1, currentWidth / baseWidth)
    }

    // MARK: - band 판정 기준 ★

    /// stroke 를 어느 band 로 볼지 정하는 y 좌표 — **첫 control point** 를 쓴다.
    ///
    /// ### 왜 첫 control point 인가 (설계가 명시하지 않아 여기서 정한다)
    /// 1. **§7-1 소유권 앵커와 같은 점이다.** 소유 절과 band 를 같은 점으로 정하면
    ///    "소유는 3절인데 band 는 2절의 줄" 같은 어긋남이 원천적으로 생기지 않는다.
    ///    실제로 `StrokeOwnershipResolver.anchorPoint(of:)` 를 그대로 호출한다.
    /// 2. **bitmap 지우개에 불변이다.** `renderBounds` 는 mask 가 반영된 가시 영역이라
    ///    획의 위쪽을 지우면 `minY` 가 내려간다. 그것을 기준으로 삼으면 **지우기만 했는데
    ///    남은 획이 다음 줄로 내려앉는다.** 반면 control point 값은 지우개 전후로 불변임이
    ///    S1-4 실측에서 확인됐다(설계 §19-2). 조각들이 원본 path 를 공유하므로(S1-2)
    ///    한 원본에서 갈라진 조각은 모두 같은 band 로 간다 — 흩어지지 않는다.
    /// 3. 여러 줄을 지나는 긴 획은 `renderBounds.minY` 를 쓰면 실제로 쓴 줄보다 위 줄로 끌려간다.
    ///    "시작한 줄에 속한다" 는 §7-1 의 U1 정책(시작 절 귀속)과도 결이 같다.
    ///
    /// - Parameter stroke: 대상 stroke.
    /// - Returns: 판정에 쓸 저장 좌표계 y. control point 가 없으면 `renderBounds.minY` 로 대체한다.
    private func bandAnchorY(of stroke: PKStroke) -> CGFloat {
        if let anchor = ownership.anchorPoint(of: stroke) { return anchor.y }
        return stroke.renderBounds.minY
    }

    // MARK: - §9-3-1 전체 보존 변환

    /// 절 Drawing 전체를 **첫 밑줄 기준**으로 옮기는 변환 (설계 §9-3-1).
    ///
    /// `region.storageOrigin` 이 곧 "현재 레이아웃의 첫 밑줄"이다(설계 §5). 밑줄이 하나도 없으면
    /// §5 의 `?? 0` 규칙에 따라 `writingRect` 상단이 된다.
    /// 임의로 다른 줄에 합치거나 분산시키지 않는다.
    ///
    /// - Note: uniform scale 은 그대로 적용한다. §9-2 의 축소 규칙은 band 매핑과 독립적인
    ///         "좁아진 폭 밖으로 잉크가 나가지 않게 한다" 는 규칙이고, 축소는 절 안의 상대 배치를
    ///         바꾸지 않으므로 §9-3-1 의 "보존" 과 충돌하지 않는다.
    private static func wholeVerseTransform(region: VerseCanvasRegion, scale: CGFloat) -> CGAffineTransform {
        let origin = region.storageOrigin
        return CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: origin.x, y: origin.y))
    }

    // MARK: - stroke 변환

    /// stroke 마다 다른 변환을 적용한 새 drawing 을 만든다. 입력은 값 타입이라 변경되지 않는다(P10).
    ///
    /// `PKStroke.transform` 을 직접 조작하지 않고 `PKDrawing.transformed(using:)` 을 거치는 이유는
    /// `mask` 의 좌표 공간을 이 코드가 가정하지 않기 위함이다. 공개 API 가 mask 까지 함께 처리한다.
    /// 원래 stroke 순서는 그대로 보존한다.
    /// - Parameters:
    ///   - drawing: 원본 drawing.
    ///   - transformForStroke: stroke 별 변환.
    /// - Returns: 변환된 drawing.
    private func transformed(
        _ drawing: PKDrawing,
        by transformForStroke: (PKStroke) -> CGAffineTransform
    ) -> PKDrawing {
        PKDrawing(strokes: drawing.strokes.map { stroke in
            let transform = transformForStroke(stroke)
            if transform.isIdentity { return stroke }
            // 한 획짜리 drawing 을 거쳐야 mask 까지 공개 API 규칙대로 옮겨진다.
            return PKDrawing(strokes: [stroke]).transformed(using: transform).strokes.first ?? stroke
        })
    }
}

// MARK: - band ↔ 밑줄 대응 계획

extension LineBandReflow {

    /// 저장 band index 를 현재 레이아웃의 목표 y(캔버스 절대)로 잇는 계획.
    ///
    /// **두 배열의 기준이 다르다는 점이 이 타입의 존재 이유다.**
    /// - `base`: 첫 밑줄 기준(§10-1). 저장 stroke 와 같은 공간이라 band 판정에 쓴다.
    /// - `target`: 캔버스 절대(§5 → 변환됨). 이동 목적지다.
    ///
    /// 두 배열의 길이는 항상 같고(`base.count`), index 가 곧 band 번호다.
    struct BandPlan: Equatable, Sendable {
        /// 저장 좌표계의 밑줄 y (첫 값 0, 오름차순).
        let base: [CGFloat]
        /// band index 별 목표 y (캔버스 절대). `base` 와 개수가 같다.
        let target: [CGFloat]

        /// 계획을 세운다. 세울 수 없으면 nil — 호출부는 그때 설계 §9-3-1 을 수행한다.
        ///
        /// nil 이 되는 경우는 셋뿐이다.
        /// 1. 저장 band 가 하나도 없다 (`base.isEmpty`) — 판정 기준이 없다.
        /// 2. 현재 밑줄이 하나도 없다 (`current.isEmpty`) — 옮겨 앉을 줄이 없다.
        /// 3. 줄 수가 줄었는데 마지막 간격을 잴 수 없다 — 초과 band 를 한 줄에 겹쳐 쌓게 되므로
        ///    "임의로 다른 줄에 합치지 않는다"(§9-3-1)를 지키려면 여기서 포기해야 한다.
        /// - Parameters:
        ///   - base: 첫 밑줄 기준 저장 밑줄 y.
        ///   - current: 캔버스 절대 현재 밑줄 y.
        ///   - writingRectTop: 현재 `writingRect` 상단 y. 밑줄이 하나뿐일 때 간격 근거로 쓴다.
        init?(base: [CGFloat], current: [CGFloat], writingRectTop: CGFloat) {
            guard !base.isEmpty, let lastCurrent = current.last else { return nil }

            if current.count >= base.count {
                // 줄 수 증가(또는 동일) — 같은 index 밑줄로 그대로 간다.
                // 남는 밑줄(index >= base.count)에는 아무 band 도 배정되지 않아 **빈 줄**이 된다 (설계 §9-3).
                self.base = base
                self.target = Array(current.prefix(base.count))
                return
            }

            // 줄 수 감소 — 초과 band 는 **마지막 간격을 연장**해 배치한다 (설계 §9-3).
            // 간격은 현재 레이아웃의 마지막 밑줄 간격이다. 밑줄이 하나뿐이면 잴 간격이 없으므로
            // `writingRect` 상단 ~ 첫 밑줄 거리를 한 줄 높이로 본다.
            let lastGap: CGFloat = current.count >= 2
                ? current[current.count - 1] - current[current.count - 2]
                : lastCurrent - writingRectTop
            guard lastGap > 0 else { return nil }

            let lastIndex = current.count - 1
            self.base = base
            self.target = current + (current.count..<base.count).map { index in
                lastCurrent + CGFloat(index - lastIndex) * lastGap
            }
        }

        /// 저장 좌표계 y 가 속한 band index.
        ///
        /// band `i` 는 "밑줄 `i` 바로 위 구간" 이다. 즉 `base[i-1] < y <= base[i]` 다.
        /// - 첫 밑줄보다 위(`y <= base[0]`)는 전부 band 0 이다. 글씨는 밑줄 위에 쓰이므로
        ///   첫 줄 필기는 저장 좌표계에서 음수 y 를 갖는 것이 정상이다.
        /// - 마지막 밑줄보다 아래는 마지막 band 로 **클램프**한다. 그 아래에는 원래 줄이 없었으므로
        ///   합칠 다른 줄을 만들어내는 것이 아니라 **원래 속해 있던 줄** 로 되돌리는 것이다.
        /// - Parameter storedY: 저장 좌표계 y.
        /// - Returns: `0 ..< base.count` 범위의 band index.
        func band(of storedY: CGFloat) -> Int {
            guard storedY.isFinite else { return 0 }
            for (index, anchor) in base.enumerated() where storedY <= anchor { return index }
            return base.count - 1
        }

        /// band 하나를 목표 밑줄로 옮기는 변환.
        ///
        /// ```
        /// x' = x × scale + left
        /// y' = (y − base[band]) × scale + target[band]
        /// ```
        /// 밑줄로부터의 상대 offset 에도 scale 을 곱한다 — uniform 이라야 종횡비가 유지된다(설계 §9-2).
        /// - Parameters:
        ///   - band: band index.
        ///   - scale: uniform scale.
        ///   - left: 현재 `writingRect.minX`.
        /// - Returns: 저장 좌표 → 캔버스 좌표 변환.
        func transform(forBand band: Int, scale: CGFloat, left: CGFloat) -> CGAffineTransform {
            let index = min(max(band, 0), base.count - 1)
            return CGAffineTransform(translationX: 0, y: -base[index])
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(CGAffineTransform(translationX: left, y: target[index]))
        }
    }
}
