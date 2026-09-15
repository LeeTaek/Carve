//
//  VerseImageCard.swift
//  CarveFeature
//
//  Created by Claude on 9/15/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Domain
import PencilKit
import SwiftUI

import Dependencies
import IssueReporting
import UIComponents

/// 사진으로 저장하는 절 이미지(시안 G1).
///
/// 본문을 위, 필기를 아래에 둔다 — 공유했을 때 좁은 화면에서도 읽는 순서가 그대로다. 출처(권 · 장 · 절과 번역본)를 아래에 적고
/// 도구 팔레트 · 선택 표시 · 광고는 넣지 않는다(로드맵 §3-2). 필사 영역처럼 늘 종이(라이트) 외관이다(문서 8-1).
/// 필기가 없는 절은 「나의 필사」 칸을 빼고 본문만 담는다(2026-09-15 결정).
///
/// 필기 칸은 캔버스의 그 절 필사 영역을 그대로 옮긴다 — 같은 폭 · 같은 밑줄 위에 화면에 보이던 자리 그대로 필기를 놓는다.
struct VerseImageCard: View {
    let content: VerseImageContent
    /// 필기 칸의 그림. 필기가 없으면 nil.
    let handwriting: HandwritingImage?

    /// 필기를 필사 영역 좌표로 그린 그림과 그 자리.
    struct HandwritingImage {
        /// 필기 그림(라이트 외관).
        let image: UIImage
        /// 그림의 자리 — 필사 영역 좌상단 원점.
        let inkRect: CGRect
        /// 칸 전체 — 필사 영역에 필기 범위를 더한 것. 절 경계를 넘는 획도 자르지 않는다.
        let areaRect: CGRect
    }

    /// 카드 안쪽 여백.
    static let padding = EdgeInsets(top: 44, leading: 40, bottom: 32, trailing: 40)
    /// 이미지 배율. 필사 폭(약 340~560pt)에서 폭 1,300~2,000px 가 된다.
    static let renderScale: CGFloat = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(content.sentence)
                .tracking(content.setting.traking)
                .font(CarveTypography.scripture(content.setting.fontFamily.font(size: content.setting.fontSize)))
                .foregroundStyle(CarveColor.Paper.text)
                .lineSpacing(max(0, content.setting.lineSpace))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let handwriting {
                divider
                    .padding(.top, 28)
                Text("나의 필사")
                    .font(.system(size: 12))
                    .foregroundStyle(CarveColor.Paper.secondary)
                    .padding(.top, 20)
                handwritingArea(handwriting)
                    .padding(.top, 12)
            }

            divider
                .padding(.top, 28)
            HStack(alignment: .firstTextBaseline) {
                Text(content.reference)
                    .font(.system(size: 14))
                    .foregroundStyle(CarveColor.Paper.text)
                Spacer(minLength: CarveSpacing.medium)
                Text("새기다")
                    .font(.system(size: 13))
                    .foregroundStyle(CarveColor.Paper.secondary)
            }
            .padding(.top, 16)
        }
        .padding(Self.padding)
        .frame(width: Self.cardWidth(for: content))
        .background(CarveColor.Paper.background)
    }

    private var divider: some View {
        Rectangle()
            .fill(CarveColor.Paper.text.opacity(0.1))
            .frame(height: 1)
    }

    /// 필기 칸 — 필사 영역의 밑줄과 필기. 경계를 넘는 획으로 칸이 본문 폭보다 넓어지면 비율을 지켜 줄인다.
    private func handwritingArea(_ handwriting: HandwritingImage) -> some View {
        let area = handwriting.areaRect
        let writingWidth = content.handwriting.writingSize.width
        let scale = min(1, writingWidth / max(area.width, 1))
        return ZStack(alignment: .topLeading) {
            ForEach(Array(content.handwriting.underlineAnchors.enumerated()), id: \.offset) { _, anchor in
                Rectangle()
                    .fill(CarveColor.Paper.guide)
                    .frame(width: writingWidth, height: 1)
                    .offset(x: -area.minX, y: anchor - area.minY)
            }
            Image(uiImage: handwriting.image)
                .resizable()
                .frame(width: handwriting.inkRect.width, height: handwriting.inkRect.height)
                .offset(x: handwriting.inkRect.minX - area.minX, y: handwriting.inkRect.minY - area.minY)
        }
        .frame(width: area.width, height: area.height, alignment: .topLeading)
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: area.width * scale, height: area.height * scale, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

extension VerseImageCard {
    /// 카드 폭 — 필사 폭에 좌우 여백을 더한 것.
    static func cardWidth(for content: VerseImageContent) -> CGFloat {
        content.handwriting.writingSize.width + padding.leading + padding.trailing
    }

    /// 절 이미지를 PNG 로 그린다. 그리지 못하면 nil.
    /// - Parameters:
    ///   - content: 이미지 내용.
    ///   - scale: 배율.
    static func renderPNG(_ content: VerseImageContent, scale: CGFloat = renderScale) -> Data? {
        let card = VerseImageCard(content: content, handwriting: handwritingImage(content.handwriting, scale: scale))
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: card)
        renderer.scale = scale
        renderer.isOpaque = true
        return renderer.uiImage?.pngData()
    }

    /// 필기를 라이트 외관으로 그린다 — 다크 외관이면 PencilKit 이 잉크 색을 바꾼다(`VerseDrawingHistoryView.thumbnail`).
    static func handwritingImage(_ handwriting: VerseImageHandwriting, scale: CGFloat) -> HandwritingImage? {
        guard let data = handwriting.inkData,
              let drawing = try? PKDrawing(data: data),
              !drawing.strokes.isEmpty else { return nil }
        let inkRect = drawing.bounds.insetBy(dx: -2, dy: -2)
        guard !inkRect.isNull, inkRect.width > 0, inkRect.height > 0 else { return nil }
        var image: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: inkRect, scale: scale)
        }
        guard let image else { return nil }
        let writingArea = CGRect(origin: .zero, size: handwriting.writingSize)
        return HandwritingImage(image: image, inkRect: inkRect, areaRect: writingArea.union(inkRect))
    }
}

// MARK: - 의존성

/// 절 이미지를 그리는 곳. 리듀서 테스트는 실제로 그리지 않도록 바꿔 끼운다.
struct VerseImageRenderer: Sendable {
    /// PNG 데이터. 그리지 못하면 nil.
    var render: @MainActor @Sendable (VerseImageContent) -> Data?
}

extension VerseImageRenderer: DependencyKey {
    static let liveValue = VerseImageRenderer { content in
        VerseImageCard.renderPNG(content)
    }

    static let testValue = VerseImageRenderer { _ in
        reportIssue("VerseImageRenderer.render 를 주입하지 않았다")
        return nil
    }
}

extension DependencyValues {
    var verseImageRenderer: VerseImageRenderer {
        get { self[VerseImageRenderer.self] }
        set { self[VerseImageRenderer.self] = newValue }
    }
}
