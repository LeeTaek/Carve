//
//  ChapterLayoutSignpost.swift
//  CarveFeature
//
//  Created by Claude on 9/5/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Domain
import Foundation
import OSLog

/// Phase 2 — 장 레이아웃 측정 시간을 Instruments 에서 볼 수 있게 하는 `os_signpost` (설계 §18-3 · §18-3-a 이월 항목).
///
/// D5 가 "정밀 layout 소요 시간은 `os_signpost` 부재로 Phase 2 이월" 로 남긴 지표가 이것이다.
/// Instruments 의 **os_signpost** 계측기에서 `ChapterLayout` 카테고리를 고르면
/// 장 진입(`setSentence`)부터 전 절 측정 완료까지의 구간이 `measure` 인터벌로 보인다.
///
/// 상태 객체가 필요한 `OSSignposter` 대신 ID 만으로 짝을 맞추는 `os_signpost(_:log:name:signpostID:)` 를 쓴다.
/// ID 는 Reducer 상태에 `UInt64` 로 보관되므로 상태가 Equatable/Sendable 을 잃지 않는다.
enum ChapterLayoutSignpost {
    /// Instruments 필터용 카테고리. 툴킷의 `OSLog.subsystem`(번들 ID)과 같은 subsystem 을 쓴다.
    static let log = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "kr.co.carve", category: "ChapterLayout")

    /// 측정 구간을 연다.
    /// - Parameters:
    ///   - chapter: 대상 장.
    ///   - verseCount: 절 개수.
    /// - Returns: 구간 ID. `end` 에 그대로 넘긴다.
    static func beginMeasure(chapter: BibleChapter, verseCount: Int) -> UInt64 {
        let id = OSSignpostID(log: log)
        os_signpost(
            .begin, log: log, name: "measure", signpostID: id,
            "%{public}@ %d verses", "\(chapter.title.rawValue).\(chapter.chapter)", verseCount
        )
        return id.rawValue
    }

    /// 측정 구간을 닫는다. 전 절 실측이 모여 첫 레이아웃이 완성된 시점이다.
    /// - Parameters:
    ///   - rawID: `beginMeasure` 가 돌려준 ID.
    ///   - layout: 완성된 레이아웃.
    ///   - duration: `begin` 부터의 소요 시간.
    static func endMeasure(rawID: UInt64, layout: ChapterLayout, duration: Duration) {
        let millis = Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
        os_signpost(
            .end, log: log, name: "measure", signpostID: OSSignpostID(rawID),
            "%d regions height %.1f %.1f ms", layout.regions.count, Double(layout.totalHeight), millis
        )
    }

    /// 완성 이후의 재계산 1회를 점(event)으로 남긴다.
    /// - Parameters:
    ///   - layout: 재계산된 레이아웃.
    ///   - buildCount: 누적 계산 횟수.
    static func rebuildEvent(layout: ChapterLayout, buildCount: Int) {
        os_signpost(
            .event, log: log, name: "rebuild",
            "#%d regions %d height %.1f", buildCount, layout.regions.count, Double(layout.totalHeight)
        )
    }
}
