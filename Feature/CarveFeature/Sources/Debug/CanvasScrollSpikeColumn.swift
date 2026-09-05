//
//  CanvasScrollSpikeColumn.swift
//  CarveFeature
//
//  Created by Claude on 9/5/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

#if DEBUG
import Domain
import SwiftUI
import UIKit

// MARK: - 텍스트 컬럼

/// 장 전체 텍스트 컬럼. **A와 B가 같은 뷰를 쓴다.**
///
/// A에서는 SwiftUI `ScrollView`의 content로, B에서는 `UIHostingController`에 담겨
/// `PKCanvasView`의 scroll content **안에** 놓인다. 두 경우 모두 좌표 원점은 layout의 `(0, 0)`이다.
///
/// 행 높이와 간격을 `ChapterLayout`이 계산한 값 그대로 쓰기 때문에
/// 각 행의 원점은 정확히 `region.writingRect.origin`이 된다. 텍스트가 실제로 몇 줄로 접히는지는
/// 여기서 판정하지 않는다(그건 S3의 범위다). S4는 **호스팅·스크롤 기하**만 본다.
struct SpikeVerseColumn: View {
    let layout: ChapterLayout
    let probeVerses: Set<Int>
    let metrics: CanvasScrollSpikeMetrics

    private var spacing: CGFloat { CanvasScrollSpikeContent.metrics.verseSpacing }
    private var topInset: CGFloat { CanvasScrollSpikeContent.metrics.topInset }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(layout.regions, id: \.verse) { region in
                row(region)
                    .frame(width: layout.writingWidth, height: region.writingRect.height, alignment: .topLeading)
            }
        }
        .padding(.top, topInset)
        .frame(width: layout.writingWidth, height: layout.totalHeight, alignment: .topLeading)
    }

    @ViewBuilder
    private func row(_ region: VerseCanvasRegion) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(region.underlineAnchors.enumerated()), id: \.offset) { _, anchor in
                Rectangle()
                    .fill(Color.primary.opacity(0.22))
                    .frame(width: layout.writingWidth, height: 1)
                    .position(x: layout.writingWidth / 2, y: anchor)
            }
            Text(CanvasScrollSpikeContent.verseText(verse: region.verse,
                                                    lineCount: region.underlineAnchors.count))
                .font(.system(size: CanvasScrollSpikeContent.setting.fontSize - 4))
                .foregroundStyle(Color.primary.opacity(0.45))
                .lineLimit(region.underlineAnchors.count)
                .frame(width: layout.writingWidth - 12, alignment: .topLeading)
                .padding(.leading, 6)
            if probeVerses.contains(region.verse), let first = region.underlineAnchors.first {
                SpikeProbeMarker(verse: region.verse, metrics: metrics)
                    .frame(width: 26, height: 26)
                    .position(x: CanvasScrollSpikeContent.probePoint(region: region).x, y: first)
            }
        }
        .clipped()
    }
}

// MARK: - 기준 마커

/// 텍스트 컬럼 안, 정확히 `probePoint`에 놓이는 마커.
///
/// 이 뷰의 **중심**이 측정 기준점이다. `UIView`로 만드는 이유는 측정에
/// SwiftUI의 좌표 보고가 아니라 UIKit의 `convert(_:to:)`를 쓰기 위해서다.
struct SpikeProbeMarker: UIViewRepresentable {
    let verse: Int
    let metrics: CanvasScrollSpikeMetrics

    func makeUIView(context: Context) -> SpikeMarkerView {
        let view = SpikeMarkerView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        metrics.registerMarker(verse: verse, view: view)
        return view
    }

    func updateUIView(_ uiView: SpikeMarkerView, context: Context) {
        metrics.registerMarker(verse: verse, view: uiView)
    }
}

/// 초록 십자 마커. 캔버스의 빨간 십자(잉크)와 겹쳐 보이면 육안으로도 정합을 알 수 있다.
final class SpikeMarkerView: UIView {
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setStrokeColor(UIColor.systemGreen.cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: rect.midX, y: rect.minY))
        context.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        context.move(to: CGPoint(x: rect.minX, y: rect.midY))
        context.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        context.strokePath()
    }
}
#endif
