//
//  WidgetVerseRotationTesting.swift
//  DomainTest
//
//  위젯이 담은 말씀을 도는 순서 — 1시간마다, 한 바퀴 돈 뒤 다시 섞기(2026-09-16 사용자 결정).
//

@testable import Domain
import Foundation
import Testing

@Suite("위젯 말씀 순환")
struct WidgetVerseRotationTesting {
    /// 이어지는 칸 `count` 개를 본다.
    private func indices(count: Int, slots: Int, from slot: Int = 0) -> [Int] {
        (0..<slots).map { WidgetVerseRotation.index(forSlot: slot + $0, count: count) }
    }

    @Test("한 바퀴 안에서는 담은 말씀이 한 번씩 모두 나온다")
    func oneCycleShowsEveryVerse() {
        for count in 1...20 {
            for cycle in 0..<5 {
                let shown = indices(count: count, slots: count, from: cycle * count)
                #expect(Set(shown) == Set(0..<count), "\(count)개 · \(cycle)바퀴에서 빠지거나 겹친 말씀이 있다")
            }
        }
    }

    @Test("같은 말씀이 연달아 나오지 않는다 — 바퀴가 넘어가는 자리도 포함해서")
    func neverRepeatsBackToBack() {
        for count in 2...20 {
            let shown = indices(count: count, slots: count * 5)
            for (previous, next) in zip(shown, shown.dropFirst()) {
                #expect(previous != next, "\(count)개에서 같은 말씀이 연달아 나왔다")
            }
        }
    }

    @Test("바퀴마다 순서를 다시 섞는다")
    func reshufflesEachCycle() {
        let count = 8
        let orders = (0..<6).map { cycle in indices(count: count, slots: count, from: cycle * count) }
        #expect(Set(orders).count > 1, "여섯 바퀴가 모두 같은 순서였다")
    }

    @Test("같은 칸은 늘 같은 말씀이다 — 위젯이 다시 그려져도 순서가 튀지 않는다")
    func isDeterministic() {
        let first = indices(count: 7, slots: 30, from: 123_456)
        let second = indices(count: 7, slots: 30, from: 123_456)
        #expect(first == second)
    }

    @Test("한 말씀만 담으면 늘 그 말씀이다")
    func singleVerseStays() {
        #expect(indices(count: 1, slots: 10) == Array(repeating: 0, count: 10))
    }

    @Test("첫 칸은 지금이고 다음 칸부터는 정시에 한 칸씩 간다")
    func planStartsNowThenAlignsToTheHour() throws {
        // 10:20 — 다음 칸은 11:00 이다.
        let now = Date(timeIntervalSince1970: 10 * 3_600 + 20 * 60)
        let plan = WidgetVerseRotation.plan(count: 4, from: now, slots: 3)

        #expect(plan.count == 3)
        #expect(plan.first?.date == now)
        #expect(plan[1].date == Date(timeIntervalSince1970: 11 * 3_600))
        #expect(plan[2].date == Date(timeIntervalSince1970: 12 * 3_600))
        #expect(plan.map(\.index) == indices(count: 4, slots: 3, from: 10))
    }

    @Test("담은 말씀이 없으면 만들 칸도 없다")
    func emptySelectionHasNoPlan() {
        #expect(WidgetVerseRotation.plan(count: 0, from: .now).isEmpty)
    }
}
