//
//  CarveWidgetBundle.swift
//  WIDGET-0 스파이크 — 경로 증명용. 디자인 마감이 아니다(DESIGN-0 전).
//
//  화면에 일부러 진단값을 찍는다: colorScheme · widgetFamily · App Group 도달 여부.
//  "지정 당시 이미지"를 흰 배경 전제로 렌더하면 다크에서 어떻게 보이는지를 눈으로 확인하려는 것이다.
//

import SwiftUI
import WidgetKit

struct VerseEntry: TimelineEntry {
    let date: Date
    let payload: VerseWidgetPayload?
    let image: UIImage?
    /// App Group 컨테이너 자체에 닿았는지. 이미지 유무와 구분해서 본다.
    let containerReachable: Bool
}

struct VerseProvider: TimelineProvider {
    func placeholder(in context: Context) -> VerseEntry {
        VerseEntry(date: .now, payload: nil, image: nil, containerReachable: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (VerseEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VerseEntry>) -> Void) {
        completion(Timeline(entries: [loadEntry()], policy: .never))
    }

    private func loadEntry() -> VerseEntry {
        let reachable = VerseWidgetSharing.containerURL != nil
        guard let stored = VerseWidgetStore.read() else {
            return VerseEntry(date: .now, payload: nil, image: nil, containerReachable: reachable)
        }
        return VerseEntry(
            date: .now,
            payload: stored.payload,
            image: UIImage(data: stored.imageData),
            containerReachable: reachable
        )
    }
}

struct VerseWidgetView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetFamily) private var family
    let entry: VerseEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let image = entry.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Text(entry.containerReachable ? "지정된 절 없음" : "App Group 접근 실패")
            }
            Text("WIDGET-0 / \(colorScheme == .dark ? "dark" : "light") / \(String(describing: family))")
                .font(.system(size: 9))
            if let payload = entry.payload {
                Text("\(payload.bookDisplayName) \(payload.chapter):\(payload.verse)")
                    .font(.system(size: 9))
            }
        }
        .widgetURL(entry.payload?.deepLinkURL)
        // WIDGET-0 실험 — 시맨틱 색(.background) 은 위젯 호스트가 다크로 해석한다. 명시 색으로 바꿔 본다.
        .containerBackground(Color.white, for: .widget)
    }
}

struct CarveVerseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CarveVerseWidgetSpike", provider: VerseProvider()) { entry in
            // WIDGET-0 실험 — Info.plist 의 UIUserInterfaceStyle 이 무효였으므로 뷰에서 강제해 본다.
            VerseWidgetView(entry: entry)
                .environment(\.colorScheme, .light)
        }
        .configurationDisplayName("새기다 필사")
        .description("WIDGET-0 가능성 확인용")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

@main
struct CarveWidgetBundle: WidgetBundle {
    var body: some Widget {
        CarveVerseWidget()
    }
}
