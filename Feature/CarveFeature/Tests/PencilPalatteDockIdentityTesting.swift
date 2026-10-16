//
//  PencilPalatteDockIdentityTesting.swift
//  CarveFeatureTest
//
//  2.2 도구 막대 결함 — 펼침 · 접힘 전환 중에 앱 스택에 책장이 올라가고 그 위에서 이름 시트가 떴다 닫힌 뒤 돌아오면,
//  팔레트 유리의 bounds 원점이 망가진 채 남아 도구가 사라졌다(docs/notebook-design.md §9-2).
//  도크는 떠났다가 돌아올 때 안을 새로 만든다 — 그 판정은 순수 상태라 UI 없이 고정한다.
//

import Testing

@testable import CarveFeature

@Suite("도구 막대 identity — 떠났다 돌아오면 새로 만든다")
struct PencilPalatteDockIdentityTesting {
    @Test("처음 나타날 때는 새로 만들지 않는다")
    func firstAppearanceKeepsIdentity() {
        var identity = PencilPalatteDockIdentity()

        let rebuilt = identity.appeared()

        #expect(rebuilt == false)
        #expect(identity.generation == 0)
    }

    @Test("화면을 떠났다가 돌아오면 identity 가 하나 는다")
    func returningAfterDisappearanceRenewsIdentity() {
        var identity = PencilPalatteDockIdentity()
        identity.appeared()

        // 책장이 올라와 필사 화면이 창에서 빠졌다가 돌아온다.
        identity.disappeared()
        let rebuilt = identity.appeared()

        #expect(rebuilt)
        #expect(identity.generation == 1)
        #expect(identity.isAway == false)
    }

    @Test("나타남이 거듭 와도 돌아온 한 번만 센다")
    func repeatedAppearanceRenewsOnce() {
        var identity = PencilPalatteDockIdentity()
        identity.disappeared()
        identity.disappeared()

        identity.appeared()
        let again = identity.appeared()

        #expect(again == false)
        #expect(identity.generation == 1)
    }

    @Test("떠났다 돌아올 때마다 새 값이 된다")
    func everyReturnGetsNewIdentity() {
        var identity = PencilPalatteDockIdentity()
        var generations: Set<Int> = [identity.generation]

        for _ in 0..<3 {
            identity.disappeared()
            identity.appeared()
            generations.insert(identity.generation)
        }

        #expect(generations.count == 4)
    }
}
