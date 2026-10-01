//
//  ChapterCanvasController+DisplayRebuild.swift
//  CarveFeature
//
//  Created by Claude on 9/28/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import CarveToolkit
import Foundation
import PencilKit

// MARK: - 표시용 획 재구성 (D9 H)

extension ChapterCanvasController {

    /// 표시용으로 **획을 새로 만든** drawing. 잉크·좌표·마스크·seed·생성 시각을 그대로 옮기므로 내용은 입력과 동등하다.
    ///
    /// 회전 뒤 재합성에서 데이터는 캔버스까지 정상 도착하는데 화면만 이전 렌더에 머무는 결함이 있었다 (D9 H).
    /// 실기기 실험에서 `setNeedsDisplay` 와 **같은 drawing 재대입은 효과가 없었고**, 빈 drawing 을 거친 복원과
    /// **같은 공개 속성으로 만든 새 획**만 정상화됐다. 기존 획에서 파생된 표현을 재사용하는 경로를 끊는 것이 요점이다.
    /// 프레임워크 내부 캐시 키를 확인한 것은 아니므로 OS 버전 조건이나 캐시 결함 탐지 분기는 두지 않는다.
    ///
    /// **보존 범위 (iOS 26 SDK 감사).** `PKStroke` 에서 값을 지정할 수 있는 공개 속성은
    /// `ink` · `path` · `transform` · `mask` · `randomSeed` 다섯뿐이고 전부 그대로 넘긴다.
    /// `renderBounds` · `maskedPathRanges` · `requiredContentVersion` 은 그 다섯에서 파생되는 읽기 전용 값이라 옮길 것이 없다.
    /// `path` 는 통째로 넘겨 `creationDate` 와 control point(그 안의 `secondaryScale` · `threshold` 포함)를 유지한다.
    /// `StrokeIdentityKey` 는 seed + 생성 시각 + point 수만 쓰므로 **소유권 승계가 그대로 유지된다** (§7-2).
    /// `PKStroke` 의 내부 식별자는 소유권 키로 쓰지 않는다.
    ///
    /// 빈 drawing 은 그대로 돌려준다 — 빈 장·디코드 실패의 기존 처리를 바꾸지 않는다.
    /// - Parameter drawing: 디코드한 표시 대상.
    /// - Returns: 같은 내용의 새 획으로 이루어진 drawing.
    static func freshDrawingForDisplay(_ drawing: PKDrawing) -> PKDrawing {
        let strokes = drawing.strokes
        guard !strokes.isEmpty else { return drawing }
        return PKDrawing(strokes: strokes.map { stroke in
            PKStroke(
                ink: stroke.ink,
                path: stroke.path,
                transform: stroke.transform,
                mask: stroke.mask,
                randomSeed: stroke.randomSeed
            )
        })
    }

    #if DEBUG
    /// 실기기에서 **수정 전 동작**을 다시 보기 위한 Debug 전용 opt-out (`-CanvasReuseStrokesOnApply`).
    ///
    /// 정식 경로는 위 재구성이다. 이 인자는 결함을 재현하는 쪽이며, 회전 왕복 A/B 와 긴 장 성능 비교를
    /// 같은 빌드에서 하기 위해서만 남긴다. 실행당 한 번 읽는다 — `apply` 마다 인자를 훑지 않는다.
    static let reusesStrokesOnApply = ProcessInfo.processInfo.arguments.contains(LaunchArgument.canvasReuseStrokesOnApply)
    #else
    static let reusesStrokesOnApply = false
    #endif
}
