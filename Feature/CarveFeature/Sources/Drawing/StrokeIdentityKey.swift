//
//  StrokeIdentityKey.swift
//  CarveFeature
//
//  Created by Claude on 9/5/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation
import PencilKit

/// 같은 논리적 stroke 인지 판단하는 키 — **owner 승계용** (설계 §7-2).
///
/// bitmap 지우개가 바꾸는 `mask` / `maskedPathRanges` 를 **제외**한 구성요소만 담는다.
/// S1-4 실측에서 지우개 전후로 `randomSeed` / `path.creationDate` / `path.count` 가
/// 전부 불변임이 확인됐으므로(설계 §19-2) 승계 1번 규칙의 근거가 된다.
///
/// > ⚠️ **이 키는 canvas stroke 엔트리와 1:1이 아니다 (S1-2).**
/// > bitmap 지우개가 만든 조각들은 **같은 키를 공유**한다. 이 키의 의미는
/// > `"원본 획 → 절"` 이지 `"canvas 엔트리 → 절"` 이 아니다.
/// > 따라서 이 키를 담은 사전의 `count` 를 stroke 개수로 쓰거나,
/// > 사전을 순회해 stroke 를 열거해서는 안 된다. `OwnershipSnapshot` 주석 참조.
///
/// > 저장 내용이 바뀌었는지(dirty)는 이 키가 아니라 `StrokeContentSignature` 로 판정한다.
/// > 하나의 키로 둘 다 하면 "승계는 됐지만 지우기가 저장되지 않는" D7 이 재발한다.
struct StrokeIdentityKey: Hashable, Sendable {
    /// `PKStroke.randomSeed` (iOS 16+).
    let randomSeed: UInt32
    /// `PKStrokePath.creationDate` 의 epoch 초.
    let creationTime: TimeInterval
    /// `PKStrokePath.count` — control point 개수.
    let pointCount: Int

    /// 구성요소를 직접 지정해 만든다. 주로 테스트용.
    /// - Parameters:
    ///   - randomSeed: `PKStroke.randomSeed`.
    ///   - creationTime: `PKStrokePath.creationDate` 의 epoch 초.
    ///   - pointCount: control point 개수.
    init(randomSeed: UInt32, creationTime: TimeInterval, pointCount: Int) {
        self.randomSeed = randomSeed
        self.creationTime = creationTime
        self.pointCount = pointCount
    }

    /// stroke 에서 키를 유도한다.
    /// - Parameter stroke: 대상 stroke.
    init(stroke: PKStroke) {
        self.init(
            randomSeed: stroke.randomSeed,
            creationTime: stroke.path.creationDate.timeIntervalSince1970,
            pointCount: stroke.path.count
        )
    }
}
