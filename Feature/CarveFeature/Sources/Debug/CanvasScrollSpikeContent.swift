//
//  CanvasScrollSpikeContent.swift
//  CarveFeature
//
//  Created by Claude on 9/5/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

#if DEBUG
import CoreGraphics
import Domain
import PencilKit
import SwiftUI

// MARK: - 모드

/// 설계 §11의 A/B 호스팅 구조.
enum CanvasScrollSpikeMode: String, CaseIterable, Identifiable, Sendable {
    /// SwiftUI `ScrollView` + content-sized `PKCanvasView` overlay.
    case optionA = "A"
    /// `PKCanvasView`가 유일한 `UIScrollView`, 그 scroll content 안에 `UIHostingController`.
    case optionB = "B"

    var id: String { rawValue }

    /// HUD에 표시할 한 줄 설명.
    var summary: String {
        switch self {
        case .optionA: "SwiftUI ScrollView + Canvas overlay"
        case .optionB: "PKCanvasView 단독 scroll + HostingController"
        }
    }
}

// MARK: - 고정 입력

/// 스파이크가 쓰는 mock 장.
///
/// **SwiftData·실제 사용자 Drawing과 연결하지 않는다**(설계 §11 실험 범위).
/// 본문도 리소스에서 읽지 않고 절 번호에서 결정적으로 만든다.
enum CanvasScrollSpikeFixture: String, CaseIterable, Identifiable, Sendable {
    /// 시편 119편 — 176절. 설계 §18-3의 최대 부하 케이스.
    case psalm119
    /// 창세기 1장 — 31절. 장 전환(통과 기준 6) 비교용.
    case genesis1

    var id: String { rawValue }

    var chapter: BibleChapter {
        switch self {
        case .psalm119: BibleChapter(title: .psalms, chapter: 119)
        case .genesis1: BibleChapter(title: .genesis, chapter: 1)
        }
    }

    var verseCount: Int {
        switch self {
        case .psalm119: 176
        case .genesis1: 31
        }
    }

    var label: String {
        switch self {
        case .psalm119: "시편 119편 (176절)"
        case .genesis1: "창세기 1장 (31절)"
        }
    }
}

// MARK: - mock layout / 결정적 Drawing

/// 176절 mock layout과 동일한 초기 `PKDrawing`을 만드는 결정적 생성기.
///
/// - 레이아웃은 `Domain`의 `ChapterLayoutBuilder`(Phase 0B 산출물)를 그대로 쓴다. 새 빌더를 만들지 않는다.
/// - 난수를 쓰지 않는다. 같은 입력이면 A와 B가 **완전히 동일한** 캔버스 내용을 갖는다.
enum CanvasScrollSpikeContent {
    /// 본문 렌더링 설정. 기본값 고정(lineSpace 30).
    static let setting = SentenceSetting.initialState

    /// 절 배치 여백. 레이아웃과 텍스트 컬럼이 **같은 값**을 쓰기 때문에
    /// SwiftUI `VStack(spacing:)` + top padding만으로 `writingRect.minY`를 그대로 재현할 수 있다.
    static let metrics = ChapterLayoutMetrics(topInset: 24, verseSpacing: 16, bottomInset: 160)

    /// 필사 컬럼의 좌우 여백(캔버스 폭 밖). 왼손/오른손 전환 시 컬럼이 반대편으로 간다.
    static let columnGutter: CGFloat = 96

    /// 절별 텍스트 줄 수. 절 번호만으로 정해지므로 재실행해도 같다.
    ///
    /// - Note: S4는 **호스팅·스크롤 기하**를 보는 실험이라 실제 텍스트 실측 줄 수는 쓰지 않는다.
    ///         텍스트 실측(`Text.LayoutKey`)의 정확성은 S3의 범위다. 여기서는 레이아웃이
    ///         **단일 진실 공급원**이고 텍스트 뷰가 그 높이에 맞춰진다.
    static func lineCount(forVerse verse: Int) -> Int {
        1 + ((verse - 1) % 4)
    }

    /// 결정적 mock 본문. 리소스 로드가 없으므로 SwiftData/파일 의존이 생기지 않는다.
    static func verseText(verse: Int, lineCount: Int) -> String {
        let words = ["주의", "말씀은", "내", "발의", "등이요", "길의", "빛이니이다", "내가",
                     "주의", "의로운", "규례들을", "지키기로", "맹세하고", "굳게", "정하였나이다"]
        let take = 4 + lineCount * 3
        let body = (0..<take).map { words[($0 + verse) % words.count] }.joined(separator: " ")
        return "\(verse). \(body)"
    }

    /// 176절 mock 레이아웃.
    /// - Parameters:
    ///   - fixture: 대상 장.
    ///   - writingWidth: 필사 컬럼 폭(= 캔버스 content 폭).
    ///   - isLeftHanded: 왼손 레이아웃 여부(통과 기준 4).
    /// - Returns: `ChapterLayoutBuilder`가 계산한 레이아웃.
    static func makeLayout(
        fixture: CanvasScrollSpikeFixture,
        writingWidth: CGFloat,
        isLeftHanded: Bool
    ) -> ChapterLayout {
        let verses = (1...fixture.verseCount).map { verse in
            VerseLayoutInput(verse: verse, textLineCount: lineCount(forVerse: verse))
        }
        return ChapterLayoutBuilder().build(
            chapter: fixture.chapter,
            writingWidth: writingWidth,
            setting: setting,
            isLeftHanded: isLeftHanded,
            verses: verses,
            metrics: metrics
        )
    }

    /// 델타를 측정할 기준 절. 위·중간·아래 3곳을 골라 **평행이동뿐 아니라 스케일 드리프트도** 잡는다.
    static func probeVerses(fixture: CanvasScrollSpikeFixture) -> [Int] {
        let count = fixture.verseCount
        return Array(Set([1, max(1, count / 2), count])).sorted()
    }

    /// 기준 마커의 캔버스 content 좌표(= layout 좌표).
    ///
    /// 절의 `storageOrigin`(첫 밑줄 시작점)에서 x만 안쪽으로 밀어 화면 가장자리 클리핑을 피한다.
    static func probePoint(region: VerseCanvasRegion) -> CGPoint {
        CGPoint(x: region.storageOrigin.x + 44, y: region.storageOrigin.y)
    }

    // MARK: 결정적 PKDrawing

    /// 레이아웃과 1:1로 대응하는 초기 `PKDrawing`.
    ///
    /// 각 절의 첫 밑줄 위에 절 번호로 모양이 정해지는 파형 획을 하나 긋고,
    /// 기준 절에는 정확히 `probePoint`를 중심으로 하는 십자 마커를 추가한다.
    /// 십자 마커의 교차점이 텍스트 쪽 마커와 겹쳐 보이는지가 육안 확인 경로이고,
    /// 수치 판정은 HUD가 따로 계산한다.
    static func makeDrawing(layout: ChapterLayout, probeVerses: [Int]) -> PKDrawing {
        var strokes: [PKStroke] = []
        strokes.reserveCapacity(layout.regions.count + probeVerses.count * 2)
        let probeSet = Set(probeVerses)

        for region in layout.regions {
            strokes.append(waveStroke(region: region, width: layout.writingWidth))
            guard probeSet.contains(region.verse) else { continue }
            let center = probePoint(region: region)
            strokes.append(segment(from: CGPoint(x: center.x - 22, y: center.y),
                                   to: CGPoint(x: center.x + 22, y: center.y),
                                   color: .systemRed, size: 3))
            strokes.append(segment(from: CGPoint(x: center.x, y: center.y - 22),
                                   to: CGPoint(x: center.x, y: center.y + 22),
                                   color: .systemRed, size: 3))
        }
        return PKDrawing(strokes: strokes)
    }

    /// 절 하나의 필기 흉내 획. 진폭·주기가 절 번호로 정해져 절끼리 구분된다.
    private static func waveStroke(region: VerseCanvasRegion, width: CGFloat) -> PKStroke {
        let baseY = region.storageOrigin.y - 6
        let humps = 3 + (region.verse % 5)
        let amplitude = 5 + CGFloat(region.verse % 4) * 2.5
        let startX: CGFloat = 44
        let endX = max(startX + 40, width - 44)
        let sampleCount = 48
        let points = (0...sampleCount).map { step -> PKStrokePoint in
            let ratio = CGFloat(step) / CGFloat(sampleCount)
            let x = startX + (endX - startX) * ratio
            let y = baseY - amplitude * sin(ratio * CGFloat(humps) * 2 * .pi)
            return point(at: CGPoint(x: x, y: y), timeOffset: TimeInterval(step) * 0.004, size: 2.6)
        }
        return PKStroke(
            ink: PKInk(.pen, color: .label),
            path: PKStrokePath(controlPoints: points, creationDate: fixedDate)
        )
    }

    /// 직선 한 획.
    private static func segment(
        from start: CGPoint,
        to end: CGPoint,
        color: UIColor,
        size: CGFloat
    ) -> PKStroke {
        let points = (0...8).map { step -> PKStrokePoint in
            let ratio = CGFloat(step) / 8
            let location = CGPoint(x: start.x + (end.x - start.x) * ratio,
                                   y: start.y + (end.y - start.y) * ratio)
            return point(at: location, timeOffset: TimeInterval(step) * 0.004, size: size)
        }
        return PKStroke(
            ink: PKInk(.pen, color: color),
            path: PKStrokePath(controlPoints: points, creationDate: fixedDate)
        )
    }

    private static func point(at location: CGPoint, timeOffset: TimeInterval, size: CGFloat) -> PKStrokePoint {
        PKStrokePoint(
            location: location,
            timeOffset: timeOffset,
            size: CGSize(width: size, height: size),
            opacity: 1,
            force: 1,
            azimuth: 0,
            altitude: .pi / 2
        )
    }

    /// 고정 생성 시각. 실행마다 달라지는 값이 들어가면 A/B 캔버스가 동일하지 않게 된다.
    private static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
}
#endif
