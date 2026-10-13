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

/// 즐겨찾기에서 고른 말씀들을 홈 화면에 돌려 띄우는 위젯(시안 G4 · N7).
///
/// 앱이 App Group 에 놓아 둔 지정 당시 사본만 읽는다. 담을 말씀을 고르는 것은 앱이 하고,
/// 위젯은 앱이 `WidgetCenter.reloadTimelines(ofKind:)` 로 깨울 때 다시 읽는다.
/// 여러 말씀을 담았으면 `WidgetVerseRotation` 이 정한 순서로 1시간에 하나씩 보여 준다.
/// 화면 언어도 앱이 App Group 에 적어 둔 값(`VerseWidgetSharing.appLanguageKey`)을 따른다 — 앱 안에서 고른 언어.
struct VerseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: VerseWidgetSharing.widgetKind, provider: VerseWidgetProvider()) { entry in
            VerseWidgetView(entry: entry)
                // 위젯은 앱의 라이트 고정을 상속하지 않는다 — 종이 배경을 명시 색으로 칠한다 (WIDGET-0 §4, 문서 8-1).
                .environment(\.colorScheme, .light)
                // 앱 화면 언어 — 키 기반 `Text(…, bundle: .main)`(빈 상태 안내 · 「새기다 · 번역본」)이 이 언어로 나온다.
                // 담은 참조 · 권 이름 · 번역본 이름은 담을 때의 언어로 남고, 갤러리 이름 · 설명은 시스템이 그린다.
                .environment(\.locale, entry.locale)
                .containerBackground(VerseWidgetPalette.paper, for: .widget)
        }
        .configurationDisplayName(Text("말씀", bundle: .main, comment: "위젯 갤러리의 위젯 이름"))
        .description(Text(
            "즐겨찾기에서 고른 말씀을 홈 화면에 띄워요. 여러 개를 고르면 한 시간에 하나씩 돌아가며 보여 줘요.",
            bundle: .main,
            comment: "위젯 갤러리의 위젯 설명"
        ))
        // 작게(systemSmall)는 말씀 한 줄도 좁아 뺀다(2026-09-16 사용자 확인).
        // 중간은 필기가 작아 읽기 어려워 크게 · 아주 크게를 더한다(2026-09-29 사용자 요청).
        .supportedFamilies([.systemMedium, .systemLarge, .systemExtraLarge])
    }
}

/// 위젯 한 칸의 내용. 앱이 지정한 말씀이 없으면 `content` 가 nil 이다.
struct VerseWidgetEntry: TimelineEntry {
    let date: Date
    let payload: VerseWidgetPayload?
    let handwriting: UIImage?
    /// 이 칸을 그리는 표시 locale — 앱이 App Group 에 적어 둔 화면 언어다. 적힌 값이 없으면 위젯 자기 언어.
    let locale: Locale
}

struct VerseWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> VerseWidgetEntry {
        VerseWidgetEntry(date: .now, payload: nil, handwriting: nil, locale: Self.displayLocale())
    }

    func getSnapshot(in context: Context, completion: @escaping (VerseWidgetEntry) -> Void) {
        let payloads = VerseWidgetStore.readPayloads()
        completion(entry(payloads.first, at: .now, locale: Self.displayLocale()))
    }

    /// 담긴 말씀을 1시간에 하나씩 돌린다.
    ///
    /// 한 번에 `WidgetVerseRotation.slotsPerTimeline` 칸만 만들고 `.atEnd` 로 다음 타임라인을 받는다 —
    /// 칸마다 필기 그림을 들고 있어 하루치를 한 번에 만들면 익스텐션 메모리에 부담이 된다.
    /// 담긴 말씀이 하나뿐이면 돌릴 것이 없으므로 `.never` 로 두고 앱이 깨울 때만 다시 읽는다.
    func getTimeline(in context: Context, completion: @escaping (Timeline<VerseWidgetEntry>) -> Void) {
        let payloads = VerseWidgetStore.readPayloads()
        // 언어는 앱이 바꾸며 위젯을 깨우므로(`WidgetAppLanguage`) 타임라인마다 한 번 읽는다.
        let locale = Self.displayLocale()
        guard payloads.count > 1 else {
            completion(Timeline(entries: [entry(payloads.first, at: .now, locale: locale)], policy: .never))
            return
        }
        // 같은 말씀이 여러 칸에 나와도 그림은 한 번만 읽는다.
        var handwritings: [Int: UIImage?] = [:]
        let entries = WidgetVerseRotation.plan(count: payloads.count, from: .now).map { slot -> VerseWidgetEntry in
            let payload = payloads[slot.index]
            let handwriting = handwritings[slot.index] ?? {
                let image = VerseWidgetStore.handwriting(for: payload).flatMap(UIImage.init(data:))
                handwritings[slot.index] = image
                return image
            }()
            return VerseWidgetEntry(date: slot.date, payload: payload, handwriting: handwriting, locale: locale)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func entry(_ payload: VerseWidgetPayload?, at date: Date, locale: Locale) -> VerseWidgetEntry {
        guard let payload else {
            return VerseWidgetEntry(date: date, payload: nil, handwriting: nil, locale: locale)
        }
        return VerseWidgetEntry(
            date: date,
            payload: payload,
            handwriting: VerseWidgetStore.handwriting(for: payload).flatMap(UIImage.init(data:)),
            locale: locale
        )
    }

    /// 역할: 앱이 App Group 에 적어 둔 화면 언어로 이 위젯의 표시 locale 을 만든다.
    /// 입력 · 출력: 없음 → 적힌 언어로 바꾼 locale(지역 · 시간제는 위젯 자기 locale 것). 적힌 값이 없으면 위젯 자기 언어(`autoupdatingCurrent`).
    /// 부작용: App Group UserDefaults 를 읽는다.
    private static func displayLocale() -> Locale {
        VerseWidgetSharing.displayLocale(in: UserDefaults(suiteName: VerseWidgetSharing.appGroupID), base: .autoupdatingCurrent)
    }
}

/// 위젯 색. 위젯은 Resources 를 링크하지 않아 종이 색을 여기에 적어 둔다(디자인 3-1 종이 · 잉크 · 보조).
enum VerseWidgetPalette {
    static let paper = Color(red: 0.980, green: 0.976, blue: 0.965)
    static let ink = Color(red: 0.188, green: 0.231, blue: 0.212)
    static let secondary = Color(red: 0.373, green: 0.408, blue: 0.384)
}
