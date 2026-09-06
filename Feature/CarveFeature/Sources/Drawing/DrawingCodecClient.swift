//
//  DrawingCodecClient.swift
//  CarveFeature
//
//  Created by Claude on 9/6/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import CoreGraphics
import Domain
import Foundation

import Dependencies
import IssueReporting

/// `DrawingCodec` 을 Reducer 에 주입하기 위한 의존성 (설계 §4 — "PencilKit을 아는 유일한 Dependency").
///
/// Reducer 는 `Data` 와 DTO 만 주고받는다. 테스트는 두 클로저를 통째로 바꿔 코덱 없이 상태 전이를 고정한다.
struct DrawingCodecClient: Sendable {
    /// 절별 대표 행을 캔버스 하나로 합성한다 (§6-4).
    var compose: @Sendable (
        _ snapshots: [VerseDrawingSnapshot],
        _ layout: ChapterLayout,
        _ columnOrigin: CGPoint
    ) -> ComposedChapterDrawing
    /// 편집 전후로 소유권을 승계하고 저장 명령을 만든다 (§8-2).
    var mutations: @Sendable (
        _ beforeData: Data,
        _ beforeOwnership: OwnershipSnapshot,
        _ afterData: Data,
        _ context: DrawingEditContext
    ) -> DrawingEditResult
}

extension DrawingCodecClient: DependencyKey {
    static let liveValue: DrawingCodecClient = {
        let codec = DrawingCodec()
        return DrawingCodecClient(
            compose: { codec.compose(snapshots: $0, layout: $1, columnOrigin: $2) },
            mutations: { codec.mutations(beforeData: $0, beforeOwnership: $1, afterData: $2, context: $3) }
        )
    }()

    static let testValue = DrawingCodecClient(
        compose: unimplemented("DrawingCodecClient.compose", placeholder: ComposedChapterDrawing(
            data: Data(), ownership: .empty(layoutSignature: ""), activeRowIDs: [:],
            layoutMismatchVerses: [], legacyVerses: [], undecodableVerses: []
        )),
        mutations: unimplemented("DrawingCodecClient.mutations", placeholder: DrawingEditResult(
            ownership: .empty(layoutSignature: ""), mutations: [], issuedRowIDs: [:]
        ))
    )
}

extension DependencyValues {
    var drawingCodec: DrawingCodecClient {
        get { self[DrawingCodecClient.self] }
        set { self[DrawingCodecClient.self] = newValue }
    }
}
