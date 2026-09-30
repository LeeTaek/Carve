//
//  VerseRowGeometry.swift
//  CarveFeature
//
//  Created by Claude on 9/5/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import CoreGraphics
import Foundation

/// 절 행 하나가 View 계층에서 실측해 올리는 값들 (Phase 2 — 설계 §6).
///
/// 세 값은 서로 다른 시점에 따로 도착하므로 전부 optional 이며, `merge` 로 겹쳐 쌓는다.
public struct VerseRowGeometry: Equatable, Sendable {
    /// 텍스트 줄별 밑줄 offset (`VerseTextFeature.makeUnderlineOffsets` 결과). 텍스트 뷰 기준 상대값.
    public var underlineOffsets: [CGFloat]?
    /// 절 위 소제목의 높이. 소제목이 없는 절은 보고하지 않는다.
    public var titleHeight: CGFloat?
    /// 행 전체의 frame — `ChapterLayoutHosting.coordinateSpaceName` 좌표 (바깥 트리에서 실측).
    public var rowFrame: CGRect?
    /// 캔버스 영역의 frame — **행 안** `ChapterLayoutHosting.rowCoordinateSpaceName` 좌표 (행 안에서 실측).
    ///
    /// 두 값을 더한 것이 콘텐츠 좌표의 캔버스 영역이다. 둘로 나눈 이유는 `ChapterLayoutHosting.rowCoordinateSpaceName` 참조.
    public var canvasFrameInRow: CGRect?

    public init(
        underlineOffsets: [CGFloat]? = nil,
        titleHeight: CGFloat? = nil,
        rowFrame: CGRect? = nil,
        canvasFrameInRow: CGRect? = nil
    ) {
        self.underlineOffsets = underlineOffsets
        self.titleHeight = titleHeight
        self.rowFrame = rowFrame
        self.canvasFrameInRow = canvasFrameInRow
    }

    /// 나중에 도착한 값으로 덮어쓴다. nil 은 "보고 없음" 이지 "지움" 이 아니다.
    public mutating func merge(_ other: VerseRowGeometry) {
        if let offsets = other.underlineOffsets { underlineOffsets = offsets }
        if let height = other.titleHeight { titleHeight = height }
        if let frame = other.rowFrame { rowFrame = frame }
        if let frame = other.canvasFrameInRow { canvasFrameInRow = frame }
    }
}

/// 행들의 실측 콜백을 모아 **런루프 한 번에 한 액션**으로 흘려보내는 수집기.
///
/// ## 왜 행마다 액션을 보내면 안 되는가 ★ (Phase 2 실측)
///
/// 절 행은 `touchIgnoringContextMenu` 때문에 각각 중첩 `UIHostingController` 안에 있고, 바깥 `VStack` 은
/// 매 레이아웃 패스마다 176개 행의 `sizeThatFits` 를 다시 계산한다. 그 상태에서 행마다 실측 액션을 보내면
/// **액션 하나가 부모 상태를 바꿔 전체 패스를 다시 돌린다** — 시편 119편은 밑줄·frame·소제목 이벤트가
/// 500건을 넘어, 패스당 약 0.85 s × 500 ≈ 7분 동안 메인 스레드가 한 레이아웃 트랜잭션에 갇혔다
/// (설계 §20-8 실측). 이벤트를 한 틱에 모아 한 번만 반영하면 패스 수가 이벤트 수와 무관해진다.
///
/// 수집기는 SwiftUI 상태가 아니라 뷰가 들고 있는 참조 객체다. 콜백은 SwiftUI 커밋 중에 호출되므로
/// 그 자리에서 상태를 건드리지 않고 다음 런루프 턴으로 미룬다.
@MainActor
final class VerseGeometryCollector {
    typealias RowID = SentencesWithDrawingFeature.State.ID

    /// 모인 값을 한 번에 넘겨받는 지점. 뷰가 여기서 액션을 보낸다.
    /// 아직 설정되지 않은 동안 도착한 값은 버리지 않고 보관했다가, 설정되는 즉시 흘려보낸다.
    var onFlush: (([RowID: VerseRowGeometry]) -> Void)? {
        didSet {
            if onFlush != nil, !pending.isEmpty { scheduleFlush() }
        }
    }

    private var pending: [RowID: VerseRowGeometry] = [:]
    private var isFlushScheduled = false

    init() { }

    /// 아직 흘려보내지 않은 값. 테스트·디버그용.
    var pendingGeometry: [RowID: VerseRowGeometry] { pending }

    func reportUnderlineOffsets(id: RowID, offsets: [CGFloat]) {
        report(id: id, VerseRowGeometry(underlineOffsets: offsets))
    }

    func reportTitleHeight(id: RowID, height: CGFloat) {
        report(id: id, VerseRowGeometry(titleHeight: height))
    }

    func reportRowFrame(id: RowID, frame: CGRect) {
        report(id: id, VerseRowGeometry(rowFrame: frame))
    }

    func reportCanvasFrameInRow(id: RowID, frame: CGRect) {
        report(id: id, VerseRowGeometry(canvasFrameInRow: frame))
    }

    /// 모인 값을 즉시 흘려보낸다. 예약된 flush 는 취소되지 않지만 빈 상태에서는 아무것도 하지 않는다.
    /// `onFlush` 가 없으면 값을 보관한 채 기다린다.
    func flush() {
        isFlushScheduled = false
        guard let onFlush, !pending.isEmpty else { return }
        let batch = pending
        pending = [:]
        onFlush(batch)
    }

    private func report(id: RowID, _ geometry: VerseRowGeometry) {
        pending[id, default: VerseRowGeometry()].merge(geometry)
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard !isFlushScheduled else { return }
        isFlushScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.flush()
        }
    }
}
