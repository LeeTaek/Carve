//
//  ChapterLayoutBuilderTesting.swift
//  DomainTest
//
//  Created by Claude on 9/5/26.
//

import Foundation
import Testing

@testable import Domain

struct ChapterLayoutBuilderTesting {
    private let builder = ChapterLayoutBuilder()
    private let chapter = BibleChapter(title: .genesis, chapter: 1)

    /// 테스트용 고정 설정. 값이 바뀌면 signature 고정값 테스트도 함께 바뀌어야 한다.
    private func makeSetting(
        lineSpace: CGFloat = 30,
        fontSize: CGFloat = 20,
        traking: CGFloat = 1,
        fontFamily: FontCase = .gothic
    ) -> SentenceSetting {
        SentenceSetting(
            lineSpace: lineSpace,
            fontSize: fontSize,
            traking: traking,
            baseLineHeight: 20,
            textHeight: .zero,
            fontFamily: fontFamily,
            lineCount: 3
        )
    }

    private func makeLayout(
        verses: [VerseLayoutInput],
        writingWidth: CGFloat = 320,
        setting: SentenceSetting? = nil,
        isLeftHanded: Bool = false,
        metrics: ChapterLayoutMetrics = .zero
    ) -> ChapterLayout {
        builder.build(
            chapter: chapter,
            writingWidth: writingWidth,
            setting: setting ?? makeSetting(),
            isLeftHanded: isLeftHanded,
            verses: verses,
            metrics: metrics
        )
    }

    // MARK: - §6-2 게이트

    @Test("절 개수만큼 region 이 생기고 §6-2 합성 게이트를 만족한다")
    func buildsOneRegionPerVerseAndPassesCompositionGate() {
        let layout = makeLayout(verses: [
            VerseLayoutInput(verse: 1, textLineCount: 3),
            VerseLayoutInput(verse: 2, textLineCount: 2),
            VerseLayoutInput(verse: 3, textLineCount: 4)
        ])

        #expect(layout.regions.count == 3)
        #expect(layout.regions.map(\.verse) == [1, 2, 3])
        #expect(layout.totalHeight > 0)
        #expect(layout.writingWidth > 0)
        #expect(layout.satisfiesCompositionGate(expectedVerseCount: 3))
        #expect(layout.region(verse: 2)?.writingRect.height == 60)
    }

    @Test("측정된 절 수가 본문 절 수와 다르면 게이트를 통과하지 않는다")
    func compositionGateFailsWhenVerseCountMismatches() {
        let layout = makeLayout(verses: [VerseLayoutInput(verse: 1, textLineCount: 3)])

        // 부분 레이아웃을 정상 상태로 취급하지 않기 위한 조건이다.
        #expect(!layout.satisfiesCompositionGate(expectedVerseCount: 2))
    }

    @Test("절이 하나도 없어도 빈 레이아웃을 만들고 게이트에서 걸러진다")
    func buildsEmptyLayoutWithoutCrashing() {
        let layout = makeLayout(verses: [])

        #expect(layout.regions.isEmpty)
        #expect(layout.totalHeight == 0)
        #expect(!layout.satisfiesCompositionGate(expectedVerseCount: 0))
    }

    // MARK: - captureRect

    @Test("captureRect 경계가 인접 절 writingRect 의 midpoint 이고 빈틈도 겹침도 없다")
    func captureRectsSplitVerseGapAtMidpointWithoutHoles() {
        let layout = makeLayout(
            verses: [
                VerseLayoutInput(verse: 1, textLineCount: 3),
                VerseLayoutInput(verse: 2, textLineCount: 2),
                VerseLayoutInput(verse: 3, textLineCount: 4)
            ],
            metrics: ChapterLayoutMetrics(topInset: 20, verseSpacing: 12, bottomInset: 16)
        )

        for index in 0..<(layout.regions.count - 1) {
            let current = layout.regions[index]
            let next = layout.regions[index + 1]
            let expectedBoundary = (current.writingRect.maxY + next.writingRect.minY) / 2

            // 경계가 정확히 같은 값이어야 gap 이 어느 절에도 속하지 않는 구멍이 생기지 않는다.
            #expect(current.captureRect.maxY == expectedBoundary)
            #expect(next.captureRect.minY == expectedBoundary)
            #expect(current.captureRect.maxY == next.captureRect.minY)
        }

        // 각 절의 writingRect 는 자신의 captureRect 안에 온전히 들어 있어야 한다.
        for region in layout.regions {
            #expect(region.captureRect.minY <= region.writingRect.minY)
            #expect(region.captureRect.maxY >= region.writingRect.maxY)
            #expect(region.captureRect.width == layout.writingWidth)
        }
    }

    @Test("첫 절과 마지막 절의 captureRect 는 캔버스 끝까지 확장된다")
    func firstAndLastCaptureRectReachCanvasEdges() {
        let layout = makeLayout(
            verses: [
                VerseLayoutInput(verse: 1, textLineCount: 3),
                VerseLayoutInput(verse: 2, textLineCount: 2)
            ],
            metrics: ChapterLayoutMetrics(topInset: 25, verseSpacing: 10, bottomInset: 40)
        )

        // 상단 여백(25)과 하단 여백(40)도 소유권 공백이 되지 않는다.
        // 주의: 기대값은 반드시 CGFloat 로 명시한다. `#expect` 안에서 리터럴 산술식은 Int 로 추론되어
        //       AnyHashable 비교로 접히고 항상 실패한다.
        let expectedTotalHeight: CGFloat = 25 + 90 + 10 + 60 + 40
        #expect(layout.regions.first?.captureRect.minY == 0)
        #expect(layout.regions.first?.writingRect.minY == 25)
        #expect(layout.regions.last?.captureRect.maxY == layout.totalHeight)
        #expect(layout.totalHeight == expectedTotalHeight)
    }

    // MARK: - §6-3 2-pass 높이

    @Test("저장된 band 가 현재 줄 수보다 많으면 그 절이 커지고 이후 절이 전부 아래로 밀린다")
    func savedBandCountBeyondTextLinesGrowsVerseAndShiftsFollowingVerses() {
        let metrics = ChapterLayoutMetrics(topInset: 20, verseSpacing: 10)
        let base = makeLayout(
            verses: [
                VerseLayoutInput(verse: 1, textLineCount: 3),
                VerseLayoutInput(verse: 2, textLineCount: 2),
                VerseLayoutInput(verse: 3, textLineCount: 3)
            ],
            metrics: metrics
        )
        let reflowed = makeLayout(
            verses: [
                VerseLayoutInput(verse: 1, textLineCount: 3),
                VerseLayoutInput(verse: 2, textLineCount: 2, savedBandCount: 4),
                VerseLayoutInput(verse: 3, textLineCount: 3)
            ],
            metrics: metrics
        )

        let extraHeight: CGFloat = 2 * 30

        // 앞 절은 그대로.
        #expect(reflowed.regions[0] == base.regions[0])
        // 해당 절만 (N_saved - N_now) × lineSpace 만큼 커진다.
        #expect(reflowed.regions[1].writingRect.minY == base.regions[1].writingRect.minY)
        #expect(reflowed.regions[1].writingRect.height == base.regions[1].writingRect.height + extraHeight)
        // 뒤 절은 통째로 아래로 밀린다.
        #expect(reflowed.regions[2].writingRect.minY == base.regions[2].writingRect.minY + extraHeight)
        #expect(reflowed.regions[2].writingRect.height == base.regions[2].writingRect.height)
        #expect(reflowed.totalHeight == base.totalHeight + extraHeight)
        // 밑줄은 늘어나지 않는다. 늘어난 것은 마지막 밑줄 아래의 여유 공간이다.
        #expect(reflowed.regions[1].underlineAnchors == base.regions[1].underlineAnchors)
        #expect(reflowed.regions[1].underlineAnchors.count == 2)
    }

    @Test("저장된 band 가 현재 줄 수 이하이면 높이가 변하지 않는다")
    func savedBandCountWithinTextLinesKeepsHeightUnchanged() {
        let metrics = ChapterLayoutMetrics(topInset: 20, verseSpacing: 10)
        let base = makeLayout(
            verses: [
                VerseLayoutInput(verse: 1, textLineCount: 3),
                VerseLayoutInput(verse: 2, textLineCount: 3)
            ],
            metrics: metrics
        )

        for savedBandCount in [0, 1, 2, 3] {
            let layout = makeLayout(
                verses: [
                    VerseLayoutInput(verse: 1, textLineCount: 3, savedBandCount: savedBandCount),
                    VerseLayoutInput(verse: 2, textLineCount: 3, savedBandCount: savedBandCount)
                ],
                metrics: metrics
            )
            #expect(layout.regions == base.regions)
            #expect(layout.totalHeight == base.totalHeight)
        }
    }

    // MARK: - underlineAnchors / storageOrigin

    @Test("밑줄 anchor 는 writingRect 기준 상대값이고 storageOrigin 은 첫 밑줄과 일치한다")
    func underlineAnchorsAreRelativeAndStorageOriginMatchesFirstUnderline() {
        let layout = makeLayout(
            verses: [
                VerseLayoutInput(verse: 1, textLineCount: 3),
                VerseLayoutInput(verse: 2, textLineCount: 2)
            ],
            metrics: ChapterLayoutMetrics(topInset: 25, verseSpacing: 10)
        )

        let second = layout.regions[1]
        #expect(second.writingRect.minY == 125)
        // 절이 화면 아래쪽에 있어도 anchor 값은 절대좌표가 아니라 0 부터 시작하는 상대값이다.
        #expect(second.underlineAnchors == [30, 60])
        #expect(second.underlineAnchors.allSatisfy { $0 <= second.writingRect.height })
        #expect(second.storageOrigin == CGPoint(x: 0, y: 125 + 30))
        #expect(layout.regions[0].underlineAnchors == [30, 60, 90])
        #expect(layout.regions[0].storageOrigin == CGPoint(x: 0, y: 25 + 30))
    }

    @Test("실측 밑줄 anchor 가 들어오면 그대로 쓰고, 개수가 어긋나면 band 근사로 되돌아간다")
    func measuredUnderlineAnchorsArePreferredWhenCountMatches() {
        let measured = makeLayout(verses: [
            VerseLayoutInput(verse: 1, textLineCount: 3, measuredUnderlineAnchors: [24, 54, 84])
        ])
        #expect(measured.regions[0].underlineAnchors == [24, 54, 84])
        #expect(measured.regions[0].storageOrigin.y == 24)

        let mismatched = makeLayout(verses: [
            VerseLayoutInput(verse: 1, textLineCount: 3, measuredUnderlineAnchors: [24, 54])
        ])
        #expect(mismatched.regions[0].underlineAnchors == [30, 60, 90])
    }

    // MARK: - §6-5 signature

    @Test("같은 입력이면 signature 가 항상 같다")
    func signatureIsIdenticalForIdenticalInput() {
        let verses = [VerseLayoutInput(verse: 1, textLineCount: 3)]
        let first = makeLayout(verses: verses)
        let second = makeLayout(verses: verses)

        #expect(first.signature == second.signature)
        // 저장된 band 수는 signature 구성요소가 아니다. 같은 설정이면 같은 값이어야 한다.
        #expect(makeLayout(verses: [VerseLayoutInput(verse: 1, textLineCount: 3, savedBandCount: 9)]).signature == first.signature)
    }

    @Test("signature 구성요소가 하나라도 바뀌면 signature 가 달라진다")
    func signatureChangesWhenAnyComponentChanges() {
        let verses = [VerseLayoutInput(verse: 1, textLineCount: 3)]
        let signatures = [
            makeLayout(verses: verses).signature,
            makeLayout(verses: verses, setting: makeSetting(fontSize: 21)).signature,
            makeLayout(verses: verses, setting: makeSetting(traking: 2)).signature,
            makeLayout(verses: verses, setting: makeSetting(lineSpace: 31)).signature,
            makeLayout(verses: verses, setting: makeSetting(fontFamily: .myeongjo)).signature,
            makeLayout(verses: verses, writingWidth: 321).signature,
            makeLayout(verses: verses, isLeftHanded: true).signature
        ]

        #expect(Set(signatures).count == signatures.count)
    }

    @Test("signature 는 프로세스가 바뀌어도 같은 값이다 (hashValue 회귀 방지)")
    func signatureMatchesHardcodedDigestAcrossProcesses() {
        // 이 기대값은 다른 프로세스(shasum)에서 계산한 고정값이다.
        // Hashable.hashValue 로 회귀하면 시드가 매 실행 달라지므로 이 테스트가 반드시 깨진다.
        let setting = makeSetting()
        let expectedCanonical = "carve.chapterLayout/1"
            + "|font=NanumGothic"
            + "|fontSize=20.0000"
            + "|tracking=1.0000"
            + "|lineSpace=30.0000"
            + "|writingWidth=320.0000"
            + "|direction=rightHanded"
        let expectedSignature = "cl1-32f3d51249a609f16b697c22fa5f8d7b4bb9e77ea99f490b256cac4ff0e0281f"

        #expect(
            ChapterLayoutSignature.canonicalString(setting: setting, writingWidth: 320, isLeftHanded: false)
                == expectedCanonical
        )
        #expect(
            ChapterLayoutSignature.make(setting: setting, writingWidth: 320, isLeftHanded: false)
                == expectedSignature
        )
        #expect(makeLayout(verses: [VerseLayoutInput(verse: 1, textLineCount: 3)]).signature == expectedSignature)
    }

    @Test("부동소수는 고정 자릿수로 인코딩되어 표현 차이가 signature 를 흔들지 않는다")
    func signatureEncodesFloatingPointDeterministically() {
        let setting = makeSetting()

        // -0.0 과 0.0, 20 과 20.0 처럼 값이 같은 표현은 같은 signature 를 만들어야 한다.
        #expect(
            ChapterLayoutSignature.make(setting: setting, writingWidth: -0.0, isLeftHanded: false)
                == ChapterLayoutSignature.make(setting: setting, writingWidth: 0.0, isLeftHanded: false)
        )
        #expect(
            ChapterLayoutSignature.make(setting: makeSetting(fontSize: 20), writingWidth: 320, isLeftHanded: false)
                == ChapterLayoutSignature.make(setting: makeSetting(fontSize: 20.0), writingWidth: 320, isLeftHanded: false)
        )
        // 0.0001 차이는 구분되고, 그보다 작은 차이는 같은 값으로 접힌다.
        #expect(
            ChapterLayoutSignature.make(setting: setting, writingWidth: 320.0001, isLeftHanded: false)
                != ChapterLayoutSignature.make(setting: setting, writingWidth: 320, isLeftHanded: false)
        )
    }

}

// MARK: - R13 실측 높이 (D9)

/// `VerseLayoutInput.measuredHeight` — 빌더의 `줄 수 × lineSpace` 예측 대신 View 실측을 쓰는 입력 (R13).
/// 예측식은 SwiftUI 의 픽셀 스냅에 의존해 실기기에서 절당 0.5pt 씩 누적됐다.
struct ChapterLayoutBuilderHeightTesting {
    private let builder = ChapterLayoutBuilder()
    private let chapter = BibleChapter(title: .genesis, chapter: 1)

    private func makeLayout(
        verses: [VerseLayoutInput],
        metrics: ChapterLayoutMetrics = .zero
    ) -> ChapterLayout {
        builder.build(
            chapter: chapter,
            writingWidth: 320,
            setting: SentenceSetting(
                lineSpace: 30, fontSize: 20, traking: 1, baseLineHeight: 20,
                textHeight: .zero, fontFamily: .gothic, lineCount: 3
            ),
            isLeftHanded: false,
            verses: verses,
            metrics: metrics
        )
    }

    @Test("실측 높이가 있으면 줄 수 × lineSpace 예측을 이기고, 이후 절이 그 차이만큼 밀린다")
    func measuredHeightWinsOverPredictedHeight() {
        let metrics = ChapterLayoutMetrics(topInset: 2, verseSpacing: 12, bottomInset: 2)
        let predicted = makeLayout(
            verses: [
                VerseLayoutInput(verse: 1, textLineCount: 2),
                VerseLayoutInput(verse: 2, textLineCount: 2)
            ],
            metrics: metrics
        )
        // 실기기 R13 의 모양 그대로 — 실제 렌더가 예측보다 절당 0.5pt 크다.
        let measured = makeLayout(
            verses: [
                VerseLayoutInput(verse: 1, textLineCount: 2, measuredHeight: 60.5),
                VerseLayoutInput(verse: 2, textLineCount: 2, measuredHeight: 60.5)
            ],
            metrics: metrics
        )

        #expect(predicted.regions[0].writingRect.height == 60)
        #expect(measured.regions[0].writingRect.height == 60.5)
        // 어긋남은 누적된다 — 2절은 앞 절의 0.5pt 만큼 아래에서 시작한다.
        #expect(measured.regions[1].writingRect.minY == predicted.regions[1].writingRect.minY + 0.5)
        #expect(measured.regions[1].writingRect.height == 60.5)
        #expect(measured.totalHeight == predicted.totalHeight + 1)
        // 밑줄 anchor 는 실측 anchor 가 따로 담당한다 — 높이 실측이 근사 anchor 를 바꾸지 않는다.
        #expect(measured.regions[0].underlineAnchors == predicted.regions[0].underlineAnchors)
    }

    @Test("실측 높이가 없는 절만 기존 예측식으로 떨어진다 (additive 이고 fallback 이 남는다)")
    func missingMeasuredHeightFallsBackToPrediction() {
        let metrics = ChapterLayoutMetrics(topInset: 2, verseSpacing: 12, bottomInset: 2)
        let mixed = makeLayout(
            verses: [
                VerseLayoutInput(verse: 1, textLineCount: 2, measuredHeight: 61),
                VerseLayoutInput(verse: 2, textLineCount: 2),
                VerseLayoutInput(verse: 3, textLineCount: 3, measuredHeight: nil)
            ],
            metrics: metrics
        )

        #expect(mixed.regions[0].writingRect.height == 61)
        #expect(mixed.regions[1].writingRect.height == 60)    // 2 × 30 예측
        #expect(mixed.regions[2].writingRect.height == 90)    // 3 × 30 예측
        // 실측이 하나도 없으면 이 수정 전과 완전히 같은 레이아웃이다.
        let allPredicted = makeLayout(
            verses: [
                VerseLayoutInput(verse: 1, textLineCount: 2),
                VerseLayoutInput(verse: 2, textLineCount: 2),
                VerseLayoutInput(verse: 3, textLineCount: 3)
            ],
            metrics: metrics
        )
        #expect(allPredicted.regions[0].writingRect.height == 60)
        #expect(allPredicted.totalHeight == mixed.totalHeight - 1)
        // 음수 실측은 0 으로 정규화된다.
        #expect(VerseLayoutInput(verse: 1, textLineCount: 2, measuredHeight: -3).measuredHeight == 0)
    }

    @Test("실측 높이로 지어도 captureRect 가 [0, totalHeight] 를 빈틈·겹침 없이 분할한다 (소유권의 근거)")
    func captureRectsStillPartitionCanvasWithMeasuredHeights() {
        // 절마다 다른 소수 실측 — 반올림 잔차가 경계에 구멍을 내지 않는지 본다.
        let layout = makeLayout(
            verses: [
                VerseLayoutInput(verse: 1, textLineCount: 2, measuredHeight: 60.5, leadingInset: 0, topPadding: 25),
                VerseLayoutInput(verse: 2, textLineCount: 1, measuredHeight: 30.5, leadingInset: 34, topPadding: 0),
                VerseLayoutInput(verse: 3, textLineCount: 3, measuredHeight: 91.25, leadingInset: 0, topPadding: 0),
                VerseLayoutInput(verse: 4, textLineCount: 2, savedBandCount: 4, measuredHeight: 60.5)
            ],
            metrics: ChapterLayoutMetrics(topInset: 2, verseSpacing: 12, bottomInset: 2)
        )

        #expect(layout.regions.first?.captureRect.minY == 0)
        #expect(layout.regions.last?.captureRect.maxY == layout.totalHeight)
        for index in 0..<(layout.regions.count - 1) {
            // 같은 값이어야 빈틈도 겹침도 없다.
            #expect(layout.regions[index].captureRect.maxY == layout.regions[index + 1].captureRect.minY)
        }
        // 분할의 합이 정확히 전체 높이다.
        #expect(layout.regions.map(\.captureRect.height).reduce(0, +) == layout.totalHeight)
        // 각 절의 writingRect 는 자기 captureRect 안에 온전히 들어 있다.
        for region in layout.regions {
            #expect(region.captureRect.minY <= region.writingRect.minY)
            #expect(region.captureRect.maxY >= region.writingRect.maxY)
        }
    }

    @Test("실측 높이와 함께 있어도 leadingInset · topPadding · Pass 2 extraBands 가 규정대로 적재된다")
    func measuredHeightComposesWithInsetsAndPassTwo() {
        let metrics = ChapterLayoutMetrics(topInset: 2, verseSpacing: 12, bottomInset: 2)
        let layout = makeLayout(
            verses: [
                // 실측 높이는 topPadding 을 이미 포함한 값이다 — 빌더가 다시 더하지 않는다.
                VerseLayoutInput(verse: 1, textLineCount: 2, measuredHeight: 85.5, topPadding: 25),
                // Pass 2 는 실측 높이 **위에** band 개수만큼 더한다 (band 모델은 lineSpace 그대로).
                VerseLayoutInput(verse: 2, textLineCount: 2, savedBandCount: 4, measuredHeight: 60.5, leadingInset: 34)
            ],
            metrics: metrics
        )

        // 1절: 실측 그대로. topPadding 이 두 번 더해지면 110.5 가 됐을 것이다.
        #expect(layout.regions[0].writingRect.minY == 2)
        #expect(layout.regions[0].writingRect.height == 85.5)
        // 근사가 아닌 규정대로의 anchor — topPadding 아래에서 시작한다.
        #expect(layout.regions[0].underlineAnchors == [55, 85])

        // 2절: leadingInset 은 writingRect **밖**의 gap 이라 cursor 만 민다.
        #expect(layout.regions[1].writingRect.minY == 2 + 85.5 + 12 + 34)
        // 실측 60.5 + 초과 band 2개 × 30.
        #expect(layout.regions[1].writingRect.height == 60.5 + 60)
        #expect(layout.regions[1].underlineAnchors == [30, 60])
        #expect(layout.totalHeight == 2 + 85.5 + 12 + 34 + 120.5 + 2)
    }
}

// MARK: - Phase 2 — leadingInset / topPadding (실측 파이프라인 입력)

/// `VerseLayoutInput.leadingInset` / `topPadding` — Phase 2 의 실측 파이프라인이 추가한 두 여백 입력.
struct ChapterLayoutBuilderInsetTesting {
    private let builder = ChapterLayoutBuilder()
    private let chapter = BibleChapter(title: .genesis, chapter: 1)

    private func makeLayout(
        verses: [VerseLayoutInput],
        metrics: ChapterLayoutMetrics = .zero
    ) -> ChapterLayout {
        builder.build(
            chapter: chapter,
            writingWidth: 320,
            setting: SentenceSetting(
                lineSpace: 30, fontSize: 20, traking: 1, baseLineHeight: 20,
                textHeight: .zero, fontFamily: .gothic, lineCount: 3
            ),
            isLeftHanded: false,
            verses: verses,
            metrics: metrics
        )
    }

    @Test("leadingInset 은 writingRect 밖의 gap 이고 captureRect 가 midpoint 로 나눠 갖는다")
    func leadingInsetIsPlacedOutsideWritingRectAndSplitByCaptureRects() {
        let metrics = ChapterLayoutMetrics(topInset: 2, verseSpacing: 12, bottomInset: 2)
        let layout = makeLayout(
            verses: [
                VerseLayoutInput(verse: 1, textLineCount: 2),
                VerseLayoutInput(verse: 2, textLineCount: 1, leadingInset: 30),   // 소제목 30pt
                VerseLayoutInput(verse: 3, textLineCount: 1)
            ],
            metrics: metrics
        )

        // 1절: y 2, h 60 → maxY 62. 2절: 62 + 12 + 30(소제목) = 104, h 30 → maxY 134. 3절: 134 + 12 = 146.
        #expect(layout.regions[0].writingRect == CGRect(x: 0, y: 2, width: 320, height: 60))
        #expect(layout.regions[1].writingRect == CGRect(x: 0, y: 104, width: 320, height: 30))
        #expect(layout.regions[2].writingRect == CGRect(x: 0, y: 146, width: 320, height: 30))
        // 소제목은 writingRect 에 포함되지 않고 밑줄도 늘지 않는다.
        #expect(layout.regions[1].underlineAnchors == [30])
        // captureRect 경계는 소제목까지 포함한 gap 의 midpoint 다: (62 + 104) / 2.
        let expectedBoundary: CGFloat = 83
        #expect(layout.regions[0].captureRect.maxY == expectedBoundary)
        #expect(layout.regions[1].captureRect.minY == expectedBoundary)
        let expectedTotalHeight: CGFloat = 146 + 30 + 2
        #expect(layout.totalHeight == expectedTotalHeight)
    }

    @Test("첫 절의 leadingInset 은 topInset 뒤에 더해지고 captureRect 는 여전히 캔버스 상단부터다")
    func leadingInsetOnFirstVerseFollowsTopInset() {
        let layout = makeLayout(
            verses: [VerseLayoutInput(verse: 1, textLineCount: 1, leadingInset: 40)],
            metrics: ChapterLayoutMetrics(topInset: 10)
        )

        let expectedMinY: CGFloat = 50
        #expect(layout.regions[0].writingRect.minY == expectedMinY)
        #expect(layout.regions[0].captureRect.minY == 0)
    }

    @Test("topPadding 은 writingRect 안에 포함되고 근사 anchor 를 그만큼 내린다")
    func topPaddingIsInsideWritingRectAndShiftsApproximatedAnchors() {
        let layout = makeLayout(
            verses: [
                VerseLayoutInput(verse: 1, textLineCount: 3, topPadding: 25),
                VerseLayoutInput(verse: 2, textLineCount: 2)
            ],
            metrics: ChapterLayoutMetrics(topInset: 2, verseSpacing: 12)
        )

        let first = layout.regions[0]
        #expect(first.writingRect == CGRect(x: 0, y: 2, width: 320, height: 25 + 90))
        #expect(first.underlineAnchors == [55, 85, 115])
        #expect(first.storageOrigin == CGPoint(x: 0, y: 2 + 55))
        // 다음 절은 padding 만큼 아래에서 시작하고, 자기 anchor 는 영향을 받지 않는다.
        let expectedSecondMinY: CGFloat = 2 + 115 + 12
        #expect(layout.regions[1].writingRect.minY == expectedSecondMinY)
        #expect(layout.regions[1].underlineAnchors == [30, 60])
    }

    @Test("topPadding 이 있는 절의 실측 anchor 는 padding 을 이미 포함한 값으로 받아 그대로 쓴다")
    func measuredAnchorsWithTopPaddingAreUsedVerbatim() {
        let layout = makeLayout(verses: [
            VerseLayoutInput(verse: 1, textLineCount: 2, measuredUnderlineAnchors: [49.5, 79.5], topPadding: 25)
        ])

        #expect(layout.regions[0].underlineAnchors == [49.5, 79.5])
        let expectedHeight: CGFloat = 25 + 60
        #expect(layout.regions[0].writingRect.height == expectedHeight)
    }

    @Test("topPadding 이 있어도 Pass 2 여유 높이는 band 개수로만 더해진다")
    func topPaddingDoesNotInterfereWithPassTwo() {
        let layout = makeLayout(verses: [
            VerseLayoutInput(verse: 1, textLineCount: 2, savedBandCount: 4, topPadding: 25)
        ])

        let expectedHeight: CGFloat = 25 + 60 + 60
        #expect(layout.regions[0].writingRect.height == expectedHeight)
        #expect(layout.regions[0].underlineAnchors == [55, 85])
    }

    @Test("leadingInset 과 topPadding 은 signature 구성요소가 아니다")
    func insetsAreNotSignatureComponents() {
        let base = makeLayout(verses: [VerseLayoutInput(verse: 1, textLineCount: 1)])
        let withInsets = makeLayout(verses: [
            VerseLayoutInput(verse: 1, textLineCount: 1, leadingInset: 30, topPadding: 25)
        ])

        #expect(base.signature == withInsets.signature)
    }

    @Test("음수 여백은 0 으로 정규화된다")
    func negativeInsetsAreClampedToZero() {
        let input = VerseLayoutInput(verse: 1, textLineCount: 1, leadingInset: -5, topPadding: -7)

        #expect(input.leadingInset == 0)
        #expect(input.topPadding == 0)
    }
}
