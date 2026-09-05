//
//  ChapterLayoutHosting.swift
//  CarveFeature
//
//  Created by Claude on 9/5/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import CoreGraphics
import Domain

/// Phase 2 — N-Canvas `VStack` 의 배치 상수 (설계 §6 · §13 Phase 2).
///
/// **뷰와 `ChapterLayoutBuilder` 가 같은 값을 쓴다.** S4 하네스가 `CanvasScrollSpikeContent.metrics` 로
/// 레이아웃과 텍스트 컬럼을 같은 상수에 묶은 것과 같은 원칙이다. 이 값이 뷰의 실제 배치와 어긋나면
/// `ChapterLayout.writingRect` 가 실제 행 위치와 어긋나고, 그 차이는 디버그 오버레이의 Δ 로 드러난다.
///
/// 상수는 전부 **기존 N-Canvas 화면의 값을 그대로 명시**한 것이다 (사용자 동작 변화 없음).
///
/// | 상수 | 기존 코드 | 위치 |
/// |---|---|---|
/// | `rowSpacing` | `LazyVStack` 기본 spacing | `CarveDetailView.contentView` |
/// | `rowVerticalPadding` | `.padding(.vertical, 2)` | `SentencesWithDrawingView` 의 HStack |
/// | `titleSpacing` | 행 안쪽 `VStack` 기본 spacing | `SentencesWithDrawingView` |
/// | `firstVerseTopPadding` | `topDrawingInset` (1절만 25) | `SentencesWithDrawingView` |
enum ChapterLayoutHosting {
    /// 절 행 사이의 `VStack` spacing.
    static let rowSpacing: CGFloat = 8
    /// 각 행의 본문·캔버스 HStack 상하 padding.
    static let rowVerticalPadding: CGFloat = 2
    /// 소제목과 본문 사이 간격 (행 안쪽 `VStack` spacing).
    static let titleSpacing: CGFloat = 8
    /// 장 첫 절의 상단 여백. 캔버스 **안**에 있으므로 `VerseLayoutInput.topPadding` 으로 들어간다.
    static let firstVerseTopPadding: CGFloat = 25

    /// 레이아웃 좌표계의 원점이 되는 SwiftUI 좌표 공간 이름. `VStack` 자체에 붙인다.
    ///
    /// 헤더 padding 이나 스크롤 offset 은 이 공간 **밖**이므로 실측 frame 에 섞이지 않는다.
    static let coordinateSpaceName = "ChapterContent"

    /// 절 행 **안**의 좌표 공간 이름. 행의 루트 `VStack` 에 붙인다.
    ///
    /// 행 본문은 `touchIgnoringContextMenu` 가 만드는 중첩 `UIHostingController` 안에 있어 바깥 `ChapterContent` 공간을
    /// 볼 수 없다 — 이름이 해석되지 않으면 SwiftUI 는 **조용히 global 로 대체**한다 (Phase 3 실측: named == global).
    /// 그래서 캔버스 영역은 행 안에서 이 공간으로 재고, 행 자체의 frame 은 바깥 트리에서 `ChapterContent` 로 재어 합친다.
    static let rowCoordinateSpaceName = "VerseRow"

    /// 빌더에 넘길 배치 여백. 행 padding 과 stack spacing 을 `writingRect` 사이의 gap 으로 환산한 값이다.
    ///
    /// ```
    /// topInset      = 첫 행의 상단 padding (2)
    /// verseSpacing  = 하단 padding (2) + stack spacing (8) + 상단 padding (2) = 12
    /// bottomInset   = 마지막 행의 하단 padding (2)
    /// ```
    static var metrics: ChapterLayoutMetrics {
        ChapterLayoutMetrics(
            topInset: rowVerticalPadding,
            verseSpacing: rowVerticalPadding * 2 + rowSpacing,
            bottomInset: rowVerticalPadding
        )
    }

    /// 절의 `writingRect` 안쪽 상단 여백. 현재는 1절에만 25pt 가 있다.
    /// - Parameter verse: 절 번호.
    /// - Returns: 상단 여백.
    static func topPadding(forVerse verse: Int) -> CGFloat {
        verse == 1 ? firstVerseTopPadding : 0
    }

    /// 소제목 높이를 절 위 여백(`VerseLayoutInput.leadingInset`)으로 환산한다.
    ///
    /// 소제목은 행 안쪽 `VStack` 의 첫 child 라 본문 HStack 과의 사이에 `titleSpacing` 이 들어간다.
    /// - Parameter titleHeight: 실측된 소제목 높이. 소제목이 없으면 nil.
    /// - Returns: `leadingInset`.
    static func leadingInset(titleHeight: CGFloat?) -> CGFloat {
        guard let titleHeight, titleHeight > 0 else { return 0 }
        return titleHeight + titleSpacing
    }
}
