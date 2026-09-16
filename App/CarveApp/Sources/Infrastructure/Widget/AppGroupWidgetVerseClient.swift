//
//  AppGroupWidgetVerseClient.swift
//  Carve
//
//  Created by Claude on 9/16/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Domain
import Foundation
import PencilKit
import UIKit
import WidgetKit

/// 위젯에 담을 말씀들을 App Group 에 써 두고 위젯을 깨운다(시안 N6~N9).
///
/// 위젯은 Domain · SwiftData 를 링크하지 않으므로, 즐겨찾기 보관본을 **위젯이 읽을 수 있는 모양**
/// (작은 JSON + 말씀마다 필기 PNG)으로 옮겨 적는 것이 이 타입의 일이다 (WIDGET-0 §2).
struct AppGroupWidgetVerseClient: WidgetVerseClient {
    /// 위젯에 넣을 필기 그림의 최대 크기(pt).
    ///
    /// WidgetKit 은 이미지 **면적**에 상한을 두고, 넘으면 위젯이 조용히 빈 칸으로 남는다
    /// (WIDGET-0 §2 — systemSmall 에서 면적 349,905 · 최대 620.4 × 564 를 관측했다).
    /// 여러 말씀을 돌리면 한 타임라인이 그림을 여러 장 들고 있으므로 익스텐션 메모리도 함께 본다.
    /// `UIImage(data:)` 는 PNG 를 배율 1 로 되살리므로 픽셀 수가 곧 포인트 수다.
    private static let handwritingLimit = CGSize(width: 420, height: 260)

    func selection() async -> [FavoriteVerseKey] {
        VerseWidgetStore.readPayloads().compactMap(Self.key(from:))
    }

    func select(_ favorites: [FavoriteVerseSnapshot]) async throws {
        guard favorites.count <= WidgetVerseLimit.maximum else { throw WidgetVerseLimitExceeded() }
        // 이미 담긴 말씀은 페이로드를 그대로 둔다 — 담은 시각을 지키고 필기를 다시 그리지 않는다.
        let stored = Dictionary(
            VerseWidgetStore.readPayloads().compactMap { payload in
                Self.key(from: payload).map { ($0, payload) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        var payloads: [VerseWidgetPayload] = []
        var handwriting: [String: Data] = [:]
        for favorite in favorites {
            if let kept = stored[favorite.key] {
                payloads.append(kept)
                continue
            }
            let payload = Self.payload(for: favorite)
            payloads.append(payload)
            if let png = await Self.handwritingPNG(favorite.lineData) {
                handwriting[payload.handwritingFileName] = png
            }
        }
        try VerseWidgetStore.write(payloads, handwriting: handwriting)
        await Self.reloadWidgets()
    }

    func add(_ favorite: FavoriteVerseSnapshot) async throws {
        var payloads = VerseWidgetStore.readPayloads()
        guard !payloads.contains(where: { Self.key(from: $0) == favorite.key }) else { return }
        guard payloads.count < WidgetVerseLimit.maximum else { throw WidgetVerseLimitExceeded() }
        let payload = Self.payload(for: favorite)
        payloads.append(payload)
        var handwriting: [String: Data] = [:]
        if let png = await Self.handwritingPNG(favorite.lineData) {
            handwriting[payload.handwritingFileName] = png
        }
        try VerseWidgetStore.write(payloads, handwriting: handwriting)
        await Self.reloadWidgets()
    }

    func remove(_ key: FavoriteVerseKey) async throws {
        let payloads = VerseWidgetStore.readPayloads()
        let remaining = payloads.filter { Self.key(from: $0) != key }
        guard remaining.count != payloads.count else { return }
        // 빠진 말씀의 필기 그림은 write 가 지운다.
        try VerseWidgetStore.write(remaining)
        await Self.reloadWidgets()
    }

    func clear() async throws {
        try VerseWidgetStore.clear()
        await Self.reloadWidgets()
    }

    /// 보관본을 위젯이 읽는 모양으로 옮겨 적는다.
    private static func payload(for favorite: FavoriteVerseSnapshot) -> VerseWidgetPayload {
        let key = favorite.key
        return VerseWidgetPayload(
            titleRawValue: key.chapter.title.rawValue,
            bookDisplayName: key.chapter.title.koreanTitle(),
            chapter: key.chapter.chapter,
            verse: key.verse,
            translation: key.translation.rawValue,
            translationDisplayName: key.translation.displayName,
            sentence: favorite.sentence,
            designatedAt: Date()
        )
    }

    /// 위젯이 읽은 페이로드를 다시 즐겨찾기 키로 되돌린다. 모르는 권이면 nil.
    private static func key(from payload: VerseWidgetPayload) -> FavoriteVerseKey? {
        guard let title = BibleTitle(rawValue: payload.titleRawValue) else { return nil }
        return FavoriteVerseKey(
            chapter: BibleChapter(title: title, chapter: payload.chapter),
            verse: payload.verse,
            translation: Translation(rawValue: payload.translation) ?? .NKRV
        )
    }

    /// 보관된 필기를 위젯이 읽을 PNG 로 그린다. 획이 없으면 nil — 위젯은 본문을 대신 보여 준다.
    ///
    /// 종이 위 필기라 **라이트 외관**으로 그린다. 다크로 그리면 PencilKit 이 잉크 색을 바꾼다
    /// (`VerseDrawingHistoryView.thumbnail` 과 같은 이유).
    @MainActor
    private static func handwritingPNG(_ lineData: Data?) -> Data? {
        guard let lineData,
              let drawing = try? PKDrawing(data: lineData),
              !drawing.strokes.isEmpty else { return nil }
        let bounds = drawing.bounds.insetBy(dx: -4, dy: -4)
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = min(2, handwritingLimit.width / bounds.width, handwritingLimit.height / bounds.height)
        var image: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: bounds, scale: scale)
        }
        return image?.pngData()
    }

    /// 홈 화면의 위젯이 새 말씀을 읽도록 깨운다. 실제 반영 시점은 시스템이 정한다.
    @MainActor
    private static func reloadWidgets() {
        WidgetCenter.shared.reloadTimelines(ofKind: VerseWidgetSharing.widgetKind)
    }
}
