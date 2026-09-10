//
//  WidgetSpikeSeed.swift
//  WIDGET-0 스파이크 — Debug 전용. 앱이 App Group 에 "아무 이미지"를 써 넣는 경로만 증명한다.
//
//  IMAGE-CORE(절 본문·필기 합성)를 구현하지 않는다. 실행 인자 `-WidgetSpikeSeed` 로만 동작한다.
//

#if DEBUG
import OSLog
import SwiftUI
import UIKit
import WidgetKit

enum WidgetSpikeSeed {
    /// 흰 배경 · 검은 글자로 그린다 — 다크 모드에서 어떻게 보이는지 확인하려는 의도적인 선택이다.
    static func seedIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-WidgetSpikeSeed") else { return }
        let payload = VerseWidgetPayload(
            titleRawValue: "1-01Genesis.txt",
            bookDisplayName: "창세기",
            chapter: 1,
            verse: 1,
            translation: "NKRV",
            designatedAt: .now
        )
        do {
            try VerseWidgetStore.write(payload: payload, imageData: makeDummyImageData())
            WidgetCenter.shared.reloadAllTimelines()
            let path = VerseWidgetSharing.containerURL?.path ?? "nil"
            VerseWidgetSharing.logger.notice("WIDGET-0 seed: 기록 성공 (\(path, privacy: .public))")
        } catch {
            VerseWidgetSharing.logger.notice("WIDGET-0 seed: 실패 \(String(describing: error), privacy: .public)")
        }
    }

    /// ⚠️ WidgetKit 아카이버는 이미지 면적에 상한이 있다 (WIDGET-0 관측: systemSmall 에서
    /// 1200x400 이 `imageTooLarge ... maximumSize: (620.4, 564.0)` 로 거부됨 — 면적 349,905.6).
    /// 그래서 scale 1 로 고정해 픽셀 수를 직접 통제한다.
    private static func makeDummyImageData() -> Data {
        let size = CGSize(width: 600, height: 200)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let text = "창세기 1:1 (스파이크 더미)"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 32),
                .foregroundColor: UIColor.black
            ]
            (text as NSString).draw(at: CGPoint(x: 24, y: 80), withAttributes: attributes)
        }
        return image.pngData() ?? Data()
    }
}
#endif
