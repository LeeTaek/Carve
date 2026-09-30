//
//  VerseWidgetView.swift
//  CarveWidget
//
//  Created by Claude on 9/16/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import SwiftUI
import WidgetKit

/// 위젯 카드(시안 G4) — 짧은 출처 · 지정 당시 필기 · 「새기다 · 번역본」.
///
/// 필기가 없는 말씀은 본문을 대신 보여 준다. 지정된 말씀이 없으면 고르는 방법을 안내한다.
/// 누르면 그 절의 필사 화면으로 들어간다.
struct VerseWidgetView: View {
    let entry: VerseWidgetEntry
    @Environment(\.widgetFamily) private var family

    /// 크게 · 아주 크게. 필기 없는 본문을 더 큰 글자로 더 많이 보여 준다.
    private var isLarge: Bool {
        family == .systemLarge || family == .systemExtraLarge
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .widgetURL(entry.payload?.deepLinkURL)
    }

    @ViewBuilder
    private var content: some View {
        if let payload = entry.payload {
            verse(payload)
        } else {
            empty
        }
    }

    private func verse(_ payload: VerseWidgetPayload) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(payload.compactReference)
                .font(.caption2)
                .foregroundStyle(VerseWidgetPalette.secondary)

            if let handwriting = entry.handwriting {
                // 필기 그림은 획 경계로 잘라 두었으므로 남는 폭을 양옆에 나눠 가운데에 둔다.
                Image(uiImage: handwriting)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                // 필기 없이 말씀만 즐겨찾기한 경우.
                Text(payload.sentence)
                    .font(.system(size: isLarge ? 20 : 15))
                    .foregroundStyle(VerseWidgetPalette.ink)
                    .lineLimit(isLarge ? 8 : 3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            Text("새기다 · \(payload.translationDisplayName)")
                .font(.caption2)
                .foregroundStyle(VerseWidgetPalette.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(payload.reference). \(payload.sentence)")
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("표시할 말씀을 골라 주세요")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(VerseWidgetPalette.ink)
            Text("새기다 앱의 즐겨찾기에서 고를 수 있어요.")
                .font(.caption2)
                .foregroundStyle(VerseWidgetPalette.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
