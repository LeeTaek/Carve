//
//  CarveWidgetBundle.swift
//  CarveWidget
//
//  Created by Claude on 9/16/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import SwiftUI
import WidgetKit

@main
struct CarveWidgetBundle: WidgetBundle {
    var body: some Widget {
        VerseWidget()
    }
}

/// 즐겨찾기에서 고른 말씀 하나를 홈 화면에 띄우는 위젯(시안 G4 · N7).
///
/// 앱이 App Group 에 놓아 둔 지정 당시 사본만 읽는다. 표시할 말씀을 바꾸는 것은 앱이 하고,
/// 위젯은 앱이 `WidgetCenter.reloadAllTimelines()` 로 깨울 때 다시 읽는다.
struct VerseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: VerseWidgetSharing.widgetKind, provider: VerseWidgetProvider()) { entry in
            VerseWidgetView(entry: entry)
                // 위젯은 앱의 라이트 고정을 상속하지 않는다 — 종이 배경을 명시 색으로 칠한다 (WIDGET-0 §4, 문서 8-1).
                .environment(\.colorScheme, .light)
                .containerBackground(VerseWidgetPalette.paper, for: .widget)
        }
        .configurationDisplayName("말씀")
        .description("즐겨찾기에서 고른 말씀을 홈 화면에 띄워요.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// 위젯 한 칸의 내용. 앱이 지정한 말씀이 없으면 `content` 가 nil 이다.
struct VerseWidgetEntry: TimelineEntry {
    let date: Date
    let payload: VerseWidgetPayload?
    let handwriting: UIImage?
}

struct VerseWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> VerseWidgetEntry {
        VerseWidgetEntry(date: .now, payload: nil, handwriting: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (VerseWidgetEntry) -> Void) {
        completion(loadEntry())
    }

    /// 표시할 말씀은 앱이 바꿀 때만 달라진다 — 시간으로 갱신하지 않고 앱이 깨우기를 기다린다.
    func getTimeline(in context: Context, completion: @escaping (Timeline<VerseWidgetEntry>) -> Void) {
        completion(Timeline(entries: [loadEntry()], policy: .never))
    }

    private func loadEntry() -> VerseWidgetEntry {
        guard let content = VerseWidgetStore.read() else {
            return VerseWidgetEntry(date: .now, payload: nil, handwriting: nil)
        }
        return VerseWidgetEntry(
            date: .now,
            payload: content.payload,
            handwriting: content.handwriting.flatMap(UIImage.init(data:))
        )
    }
}

/// 위젯 색. 위젯은 Resources 를 링크하지 않아 종이 색을 여기에 적어 둔다(디자인 3-1 종이 · 잉크 · 보조).
enum VerseWidgetPalette {
    static let paper = Color(red: 0.980, green: 0.976, blue: 0.965)
    static let ink = Color(red: 0.188, green: 0.231, blue: 0.212)
    static let secondary = Color(red: 0.373, green: 0.408, blue: 0.384)
}
