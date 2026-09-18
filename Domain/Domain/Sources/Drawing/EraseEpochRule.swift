//
//  EraseEpochRule.swift
//  Domain
//
//  Created by Claude on 9/18/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

/// 기기가 아는 삭제 기준점 집합 `K(기기)` (정책 §12-6 C11).
///
/// - `received` — 기준점 레코드 **자체를 받은** ID.
/// - `referencedOnly` — 다른 레코드의 `K` 에서 이름만 본 ID. 로컬 저장과 서버 전송은 별개라
///   기준점 레코드보다 그것을 참조한 레코드가 먼저 도착할 수 있다.
///
/// 두 집합 모두 **추가만 한다.** 참조로만 아는 기준점도 숨김 판정에는 쓰지만, 원본을 없애는 일
/// (서버 정리 · 로컬 보존 기록 삭제)에는 `received` 만 쓴다 — 잘못된 참조 하나로 계정 데이터가
/// 지워지는 것을 막는 안전장치다.
public struct EraseEpochKnowledge: Equatable, Sendable {
    public private(set) var received: Set<String>
    public private(set) var referencedOnly: Set<String>

    public init(received: Set<String> = [], referencedOnly: Set<String> = []) {
        self.received = received
        self.referencedOnly = referencedOnly.subtracting(received)
    }

    /// 판정에 쓰는 전체 집합.
    public var all: Set<String> { received.union(referencedOnly) }

    /// 기준점 레코드를 받았다. 그 기준점이 만들어질 때 알던 집합(`knownAtCreation`)도 함께 알게 되지만,
    /// 그 ID 들의 레코드를 받은 것은 아니므로 참조로만 아는 것으로 둔다.
    public mutating func receive(_ epochID: String, knownAtCreation: Set<String> = []) {
        received.insert(epochID)
        referencedOnly.remove(epochID)
        referencedOnly.formUnion(knownAtCreation.subtracting(received))
    }

    /// 레코드의 `K` 에서 참조만 봤다. 이미 받은 기준점은 그대로 둔다(강등하지 않는다).
    public mutating func note(referenced ids: Set<String>) {
        referencedOnly.formUnion(ids.subtracting(received))
    }

    /// 영속 집합을 합친다. 둘 다 추가만 하므로 합치는 순서와 무관하다.
    public func merging(_ other: EraseEpochKnowledge) -> EraseEpochKnowledge {
        EraseEpochKnowledge(
            received: received.union(other.received),
            referencedOnly: referencedOnly.union(other.referencedOnly)
        )
    }
}

/// 레코드 한 건에 대한 판정 결과.
public enum EraseEpochJudgement: Equatable, Sendable {
    /// `K(기기) ⊆ K(x)` — 유효하다.
    case valid
    /// 무효지만 **참조로만 아는 기준점** 때문이다. 숨기기만 하고 원본은 없애지 않는다.
    case hidden
    /// 무효이고, 무효로 만든 기준점 중 레코드 자체를 받은 것이 있다(정리 조건 충족).
    case removable
}

/// 삭제 기준점 판정 (정책 §12-6 C11). 저장소 · CloudKit 과 무관한 순수 규칙이다.
///
/// 시계가 아니라 **"그 삭제를 알았는가"** 로 가른다. `K(기기)` 는 늘기만 하고 `K(x)` 는 바뀌지 않으므로,
/// 기준점과 레코드가 어떤 순서로 도착해도 최종 판정은 같다.
public enum EraseEpochRule {
    /// 이 레코드를 무효로 만든 기준점들 = `K(기기) − K(x)`.
    public static func invalidatingEpochs(recordKnown: Set<String>, device: EraseEpochKnowledge) -> Set<String> {
        device.all.subtracting(recordKnown)
    }

    public static func judge(recordKnown: Set<String>, device: EraseEpochKnowledge) -> EraseEpochJudgement {
        let invalidating = invalidatingEpochs(recordKnown: recordKnown, device: device)
        if invalidating.isEmpty { return .valid }
        return invalidating.isDisjoint(with: device.received) ? .hidden : .removable
    }

    public static func isValid(recordKnown: Set<String>, device: EraseEpochKnowledge) -> Bool {
        judge(recordKnown: recordKnown, device: device) == .valid
    }

    /// 원본을 없애도 되는가 — 무효이고, 무효로 만든 기준점 중 **레코드 자체를 받은** 것이 있을 때만.
    /// 다른 기준점을 받았다는 이유로 정리하지 않는다.
    public static func mayDestroy(recordKnown: Set<String>, device: EraseEpochKnowledge) -> Bool {
        judge(recordKnown: recordKnown, device: device) == .removable
    }
}
