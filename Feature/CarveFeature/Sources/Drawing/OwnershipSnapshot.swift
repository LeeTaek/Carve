//
//  OwnershipSnapshot.swift
//  CarveFeature
//
//  Created by Claude on 9/5/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation
import PencilKit

/// 획 ↔ 절 소유권 대응 (설계 §5).
///
/// > ⚠️ **`map` 은 "원본 획 → 절" 이지 "canvas stroke 엔트리 → 절" 이 아니다 (§7-2).**
/// > bitmap 지우개가 만든 조각들은 같은 `StrokeIdentityKey` 를 공유하므로
/// > 키 하나가 여러 canvas 엔트리에 대응할 수 있다. 조각들의 owner 값은 서로 같으므로
/// > `[StrokeIdentityKey: Int]` 자체는 안전하지만, **다음은 금지한다.**
/// >
/// > - `map.count` 를 stroke 개수로 쓰기
/// > - `map` 을 순회해 stroke 를 열거하기
/// >
/// > stroke 열거는 **항상 `drawing.strokes` 를 순회하고 `map` 은 조회에만** 쓴다.
/// > 이 타입이 조회 메서드만 노출하고 열거용 API 를 두지 않는 이유다.
///
/// 이 매핑은 **한 편집 세션 안에서 owner 를 승계하기 위한 도구**다.
/// `StrokeIdentityKey` 는 공개 API 가 보장하는 영구 ID 가 아니며, 세션이 끊기면 DB 의 절별 그룹이 진실이 된다.
///
/// - Note: PencilKit 타입에서 유도되는 키를 담으므로 Domain 이 아니라 `CarveFeature` 에 둔다.
///         P9("Feature 는 PencilKit 을 모른다")의 경계는 모듈이 아니라 **Reducer** 이며,
///         `CarveFeature` 는 이미 PencilKit 을 의존한다(설계 §4). Reducer 에서 쓰지 않기만 하면 된다.
public struct OwnershipSnapshot: Equatable, Sendable {
    /// 원본 획 → 절 번호.
    let map: [StrokeIdentityKey: Int]
    /// 이 소유권이 성립한 레이아웃의 signature.
    ///
    /// 승계(§7-3)는 레이아웃이 바뀌어도 owner 를 **재판정하지 않으므로**,
    /// 이 값이 이전 스냅샷과 달라도 `map` 의 값은 그대로 승계된다.
    /// 즉 이 필드는 "이 소유권이 어떤 좌표계 위에서 해석돼야 하는가"를 가리킬 뿐 승계 조건이 아니다.
    let layoutSignature: String

    /// - Parameters:
    ///   - map: 원본 획 → 절 번호.
    ///   - layoutSignature: 이 소유권이 성립한 레이아웃의 signature.
    init(map: [StrokeIdentityKey: Int], layoutSignature: String) {
        self.map = map
        self.layoutSignature = layoutSignature
    }

    /// 아무것도 소유하지 않은 스냅샷.
    /// - Parameter layoutSignature: 대상 레이아웃의 signature.
    /// - Returns: 빈 스냅샷.
    static func empty(layoutSignature: String) -> OwnershipSnapshot {
        OwnershipSnapshot(map: [:], layoutSignature: layoutSignature)
    }

    /// 키로 owner 를 조회한다.
    /// - Parameter key: 원본 획 키.
    /// - Returns: 소유 절 번호. 없으면 nil.
    func owner(of key: StrokeIdentityKey) -> Int? {
        map[key]
    }

    /// stroke 로 owner 를 조회한다. bitmap 조각도 원본과 같은 키를 가지므로 그대로 조회된다.
    /// - Parameter stroke: 대상 stroke.
    /// - Returns: 소유 절 번호. 없으면 nil.
    func owner(of stroke: PKStroke) -> Int? {
        map[StrokeIdentityKey(stroke: stroke)]
    }

    /// 소유자로 등장하는 절 번호를 오름차순으로 돌려준다.
    ///
    /// **절 번호 열거이지 stroke 열거가 아니다.** 설계 §8-2 가 dirty 후보 집합을 만들 때 쓰는 형태이며,
    /// Dictionary 순회 순서에 결과가 좌우되지 않도록 정렬해서 돌려준다.
    var ownedVerses: [Int] {
        Array(Set(map.values)).sorted()
    }
}
