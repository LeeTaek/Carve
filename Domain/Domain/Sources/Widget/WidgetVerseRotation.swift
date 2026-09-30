//
//  WidgetVerseRotation.swift
//  Domain
//
//  Created by Claude on 9/16/26.
//  Copyright © 2026 leetaek. All rights reserved.
//
//  위젯 타깃이 이 파일을 **소스로 함께 컴파일**한다 (Domain 을 링크하지 않는다 — WIDGET-0 §2).
//  그래서 Foundation 밖의 것을 쓰지 않는다. import 를 더하면 위젯 빌드가 깨진다.
//

import Foundation

/// 위젯이 고른 말씀들을 도는 순서 (2026-09-16 사용자 결정 — 1시간마다 · 한 바퀴 돈 뒤 다시 섞기).
///
/// 매번 새로 뽑지 않고 **한 바퀴**를 만들어 돈다. 그래서 한 바퀴 안에서는 같은 말씀이 두 번 나오지 않고,
/// 고른 말씀은 모두 골고루 보인다. 바퀴가 끝나면 다시 섞되 직전 말씀이 연달아 나오지 않게 한 자리 물린다.
///
/// 순서는 칸 번호에서 씨앗을 얻는 **결정적 셔플**이다 — 같은 시각을 두 번 그려도 같은 말씀이 나오므로
/// 위젯이 다시 그려질 때 순서가 튀지 않는다.
public enum WidgetVerseRotation {
    /// 한 말씀이 머무는 시간 — 1시간(2026-09-16 사용자 결정).
    public static let slotDuration: TimeInterval = 60 * 60

    /// 한 번에 만들어 두는 칸 수.
    ///
    /// 하루치(24칸)를 한 번에 만들지 않는다. WidgetKit 은 타임라인의 **모든 칸을 한꺼번에** 들고 있어
    /// 칸마다 올린 필기 그림이 그대로 메모리가 된다. 6칸이면 그림도 최대 6장이라 익스텐션 한도 안에 든다.
    /// 6시간마다 한 번 새 타임라인을 물어보는 셈이라 시스템 새로고침 예산(하루 수십 회)에도 여유가 있다.
    public static let slotsPerTimeline = 6

    /// 한 칸 — 이 시각부터 `index` 번째 말씀을 보여 준다.
    public struct Slot: Equatable, Sendable {
        /// 이 칸이 시작하는 시각.
        public let date: Date
        /// 고른 말씀 목록에서 몇 번째인가(0 부터).
        public let index: Int

        public init(date: Date, index: Int) {
            self.date = date
            self.index = index
        }
    }

    /// `date` 부터 이어지는 칸들.
    ///
    /// 첫 칸만 `date` 그대로이고(지정하자마자 바뀌어 보이도록) 다음 칸부터는 정시에 맞춘다.
    /// - Parameters:
    ///   - count: 고른 말씀 수.
    ///   - date: 첫 칸이 시작하는 시각.
    ///   - slots: 만들 칸 수.
    /// - Returns: 고른 말씀이 없으면 빈 배열.
    public static func plan(count: Int, from date: Date, slots: Int = slotsPerTimeline) -> [Slot] {
        guard count >= 1, slots >= 1 else { return [] }
        let first = slotNumber(for: date)
        return (0..<slots).map { offset in
            let number = first + offset
            let start = offset == 0 ? date : Date(timeIntervalSince1970: Double(number) * slotDuration)
            return Slot(date: start, index: index(forSlot: number, count: count))
        }
    }

    /// 1970-01-01 부터 센 칸 번호.
    static func slotNumber(for date: Date) -> Int {
        Int((date.timeIntervalSince1970 / slotDuration).rounded(.down))
    }

    /// 그 칸에 보여 줄 말씀의 자리(0 부터).
    public static func index(forSlot slot: Int, count: Int) -> Int {
        guard count > 1 else { return 0 }
        let cycle = Int((Double(slot) / Double(count)).rounded(.down))
        let position = slot - cycle * count
        return order(count: count, cycle: cycle)[position]
    }

    /// 한 바퀴의 순서.
    ///
    /// 직전 바퀴의 마지막 말씀이 새 바퀴 첫 자리에 오면 둘째 자리와 맞바꾼다 — 연달아 같은 말씀이 나오지 않게.
    /// 맞바꾸는 자리가 앞 두 곳뿐이라 **마지막 자리는 셔플 그대로**여서, 직전 바퀴를 한 번만 계산하면 된다.
    static func order(count: Int, cycle: Int) -> [Int] {
        switch count {
        case ...1:
            return [0]
        case 2:
            // 둘뿐이면 번갈아 보일 수밖에 없다 — 섞을 것이 없다.
            return [0, 1]
        default:
            var order = shuffledOrder(count: count, cycle: cycle)
            if order.first == shuffledOrder(count: count, cycle: cycle - 1).last {
                order.swapAt(0, 1)
            }
            return order
        }
    }

    /// 바퀴 번호로 씨앗을 삼아 섞은 순서.
    private static func shuffledOrder(count: Int, cycle: Int) -> [Int] {
        var generator = SplitMix64(seed: UInt64(bitPattern: Int64(cycle)))
        return Array(0..<count).shuffled(using: &generator)
    }
}

/// 씨앗으로 같은 값을 되풀이해 내는 난수 생성기(SplitMix64).
///
/// 시스템 난수를 쓰면 위젯이 다시 그려질 때마다 순서가 달라져 같은 시각에 다른 말씀이 뜬다.
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
