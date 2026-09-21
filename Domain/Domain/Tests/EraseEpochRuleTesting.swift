//
//  EraseEpochRuleTesting.swift
//  DomainTest
//
//  삭제 기준점 판정 — 시계가 아니라 "그 삭제를 알았는가" 로 가른다 (정책 §12-6 C11).
//

import Foundation
import Testing

@testable import Domain

/// 이 규칙이 막는 것은 **삭제 뒤 재등장**과 **조용한 유실** 두 가지다.
/// 판정은 순수 함수이므로 도착 순서 순열까지 여기서 확인하고, 저장소 시험은 그다음이다.
@Suite("삭제 기준점 판정")
struct EraseEpochRuleTesting {

    private func knowledge(received: [String] = [], referenced: [String] = []) -> EraseEpochKnowledge {
        EraseEpochKnowledge(received: Set(received), referencedOnly: Set(referenced))
    }

    @Test("기준점이 없으면 모든 레코드가 유효하다")
    func emptyKnowledgeKeepsEverything() {
        let device = knowledge()

        #expect(EraseEpochRule.judge(recordKnown: [], device: device) == .valid)
        #expect(EraseEpochRule.judge(recordKnown: ["E1"], device: device) == .valid)
    }

    /// S1 — 삭제를 받은 기기에서, 그 삭제를 모른 채 작성한 레코드는 무효다.
    @Test("기기가 아는 삭제를 모른 채 작성한 레코드는 무효다")
    func recordWithoutKnownEpochIsInvalid() {
        var device = knowledge()
        device.receive("E1")

        #expect(EraseEpochRule.judge(recordKnown: [], device: device) == .removable)
        #expect(EraseEpochRule.judge(recordKnown: ["E1"], device: device) == .valid)
    }

    /// S2 — 서로 모르고 삭제(E1 · E2)한 뒤 각자 작성한 레코드는 두 기준점을 모두 아는 기기에서 양쪽 모두 무효다.
    /// 정책상 의도된 결과이며, 작성한 기기의 복구 사본으로 되살린다.
    @Test("동시 삭제 — 각자 작성한 레코드는 양쪽 모두 무효다")
    func concurrentErasesInvalidateBothSides() {
        var device = knowledge()
        device.receive("E1")
        device.receive("E2")

        #expect(EraseEpochRule.judge(recordKnown: ["E1"], device: device) == .removable)
        #expect(EraseEpochRule.judge(recordKnown: ["E2"], device: device) == .removable)
        #expect(EraseEpochRule.judge(recordKnown: ["E1", "E2"], device: device) == .valid)
    }

    /// S8 — 기준점 레코드보다 그것을 참조한 레코드가 먼저 올 수 있다.
    /// 참조만으로도 숨기지만, 그 이유로 서버 · 로컬 원본을 지우지는 않는다(정리 조건).
    @Test("참조로만 아는 기준점은 숨김까지다 — 원본을 지우지 않는다")
    func referencedOnlyEpochHidesButDoesNotDestroy() {
        var device = knowledge()
        device.note(referenced: ["E1"])

        #expect(EraseEpochRule.judge(recordKnown: [], device: device) == .hidden)
        #expect(!EraseEpochRule.mayDestroy(recordKnown: [], device: device))
    }

    @Test("기준점 레코드를 받은 뒤에는 정리할 수 있다")
    func receivingEpochRecordAllowsCleanup() {
        var device = knowledge()
        device.note(referenced: ["E1"])
        device.receive("E1")

        #expect(EraseEpochRule.mayDestroy(recordKnown: [], device: device))
        #expect(device.referencedOnly.isEmpty)
    }

    /// 다른 기준점을 받았다는 이유로, 참조로만 아는 기준점 때문에 무효가 된 레코드를 지우면 안 된다.
    @Test("무효로 만든 기준점을 받았을 때만 정리한다")
    func cleanupNeedsTheInvalidatingEpochItself() {
        var device = knowledge()
        device.receive("E1")
        device.note(referenced: ["E2"])

        // E1 은 아는 레코드다 — 무효로 만든 것은 참조로만 아는 E2 뿐이다.
        #expect(EraseEpochRule.judge(recordKnown: ["E1"], device: device) == .hidden)
        // E1 · E2 를 모두 모르는 레코드는 받은 기준점(E1)이 무효 사유에 들어 있어 정리할 수 있다.
        #expect(EraseEpochRule.judge(recordKnown: [], device: device) == .removable)
    }

    @Test("도착 순서를 바꿔도 K(기기)와 최종 판정이 같다")
    func arrivalOrderDoesNotChangeTheConclusion() {
        enum Arrival {
            case receive(String, Set<String>)
            case reference(Set<String>)
        }
        let arrivals: [Arrival] = [
            .receive("E1", []),
            .reference(["E1"]),
            .receive("E2", ["E1"]),
            .reference(["E3"])
        ]

        var conclusions: Set<EraseEpochJudgement> = []
        var knowledges: [EraseEpochKnowledge] = []
        for order in permutations(of: arrivals) {
            var device = knowledge()
            for arrival in order {
                switch arrival {
                case let .receive(id, known): device.receive(id, knownAtCreation: known)
                case let .reference(ids): device.note(referenced: ids)
                }
            }
            knowledges.append(device)
            conclusions.insert(EraseEpochRule.judge(recordKnown: ["E1"], device: device))
        }

        #expect(knowledges.count == 24)
        #expect(Set(knowledges.map(\.received)) == [["E1", "E2"]])
        #expect(Set(knowledges.map(\.referencedOnly)) == [["E3"]])
        // E1 만 아는 레코드는 E2(받음)·E3(참조) 를 모르므로 어느 순서에서도 정리 대상이다.
        #expect(conclusions == [.removable])
    }

    /// 단조성 — `K(기기)` 는 늘기만 하므로 한 번 무효인 레코드는 다시 유효해지지 않는다.
    @Test("한 번 무효가 된 레코드는 다시 유효해지지 않는다")
    func invalidityIsMonotonic() {
        var device = knowledge()
        device.receive("E1")
        #expect(!EraseEpochRule.isValid(recordKnown: [], device: device))

        device.receive("E2")
        device.note(referenced: ["E3"])
        #expect(!EraseEpochRule.isValid(recordKnown: [], device: device))
        #expect(device.all.isSuperset(of: ["E1", "E2", "E3"]))
    }

    /// S3b — 초안의 K 를 그대로 잇기 때문에, 편집 중 삭제를 받은 초안의 확정은 무효로 걸린다.
    /// 확정 시점의 `K(기기)` 로 바꿔 적으면 이 레코드가 유효로 통과해 삭제를 조용히 되돌린다.
    @Test("초안의 K 를 이은 확정은 새 데이터로 통과하지 않는다")
    func committedDraftInheritsDraftKnowledge() {
        let draftKnown: Set<String> = []          // 초안을 시작할 때는 아무 기준점도 몰랐다
        var device = knowledge()
        device.receive("E1")                      // 편집 도중 삭제를 받았다

        #expect(EraseEpochRule.judge(recordKnown: draftKnown, device: device) == .removable)
        // 되살리기는 사용자가 그 시점에 한 새 결정이므로 현재 K 로 만든다 — 유효하다.
        #expect(EraseEpochRule.judge(recordKnown: device.all, device: device) == .valid)
    }

    private func permutations<Element>(of elements: [Element]) -> [[Element]] {
        guard elements.count > 1 else { return [elements] }
        var result: [[Element]] = []
        for index in elements.indices {
            var rest = elements
            let picked = rest.remove(at: index)
            for tail in permutations(of: rest) {
                result.append([picked] + tail)
            }
        }
        return result
    }
}
