//
//  StrokeOwnershipResolver.swift
//  CarveFeature
//
//  Created by Claude on 9/5/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import CoreGraphics
import Domain
import Foundation
import PencilKit

/// 획 소유권 판정(설계 §7-1)과 승계(§7-3)를 수행하는 순수 로직.
///
/// PencilKit 을 알지만 Reducer 가 아니므로 P9 를 위반하지 않는다(설계 §4).
/// 상태를 갖지 않고 부수효과도 없어 전부 단위 테스트로 검증할 수 있다.
struct StrokeOwnershipResolver: Sendable {

    // MARK: - §7-1 소유권 판정

    /// 획의 소유권 앵커 — **첫 control point 를 캔버스 좌표로 변환한 점**.
    ///
    /// 앵커로 `CanvasEditBeginSnapshot.startPoint`(pencil-down 좌표)를 쓰지 않는 이유는 설계 §5 에 있다.
    /// 한 번의 pen-down 이 복수 획을 만들 수 있고, undo/redo 경로에서는 `startPoint` 가 nil 이다.
    /// 각 획이 자기 자신의 첫 점을 앵커로 쓰면 두 경우가 모두 덮인다.
    ///
    /// - Important: `PKStrokePath` 의 좌표는 **로컬**이고 `PKStroke.transform` 이 로컬 → 캔버스 변환이다.
    ///              변환을 적용하지 않으면 transform 이 걸린 획의 owner 가 엉뚱한 절로 간다.
    /// - Parameter stroke: 대상 획.
    /// - Returns: 캔버스 좌표의 앵커. control point 가 없으면 nil.
    func anchorPoint(of stroke: PKStroke) -> CGPoint? {
        guard let first = stroke.path.first else { return nil }
        return first.location.applying(stroke.transform)
    }

    /// 신규 획의 owner 를 판정한다 (설계 §7-1).
    ///
    /// **획을 자르지 않는다.** 여러 절을 지나는 획도 시작한 절에 통째로 귀속되며,
    /// 레이아웃이 바뀌면 시작 절과 함께 이동한다 (P1 / U1).
    /// - Parameters:
    ///   - stroke: 대상 획.
    ///   - layout: 현재 장 레이아웃.
    /// - Returns: 소유 절 번호. 앵커가 캔버스 밖이면 nil.
    func owner(of stroke: PKStroke, in layout: ChapterLayout) -> Int? {
        guard let anchor = anchorPoint(of: stroke) else { return nil }
        return layout.verse(containing: anchor)
    }

    /// 승계 없이 drawing 전체의 소유권을 새로 판정한다.
    ///
    /// 이전 소유권이 아예 없는 상태(첫 로드 등)에서만 쓴다.
    /// 편집 중에는 반드시 `reconcile(previous:previousDrawing:drawing:layout:)` 를 써야 한다 —
    /// 매 편집마다 전량 재판정하면 리플로우 후 소유권이 옆 절로 흘러간다(P2).
    /// - Parameters:
    ///   - drawing: 대상 drawing.
    ///   - layout: 현재 장 레이아웃.
    /// - Returns: 새 소유권 스냅샷.
    func resolve(drawing: PKDrawing, layout: ChapterLayout) -> OwnershipSnapshot {
        // 승계할 것이 없는 reconcile 과 같다. 두 경로가 갈라지지 않도록 위임한다.
        reconcile(
            previous: .empty(layoutSignature: layout.signature),
            previousDrawing: PKDrawing(),
            drawing: drawing,
            layout: layout
        )
    }

    // MARK: - §7-3 승계 (reconciliation)

    /// 이전 소유권을 새 drawing 에 승계한다 (설계 §7-3).
    ///
    /// 규칙 우선순위
    /// 1. `StrokeIdentityKey` 완전 일치 → 기존 owner 승계.
    ///    S1-2/S1-4 실측상 **bitmap 지우개 경로는 전부 여기서 해결된다.**
    ///    조각들은 원본과 같은 키를 가지므로 자동으로 같은 owner 를 받는다.
    /// 2. *(설계의 2번 규칙 — 유사도 판정은 생략)* `randomSeed` **또는** `creationTime` 이 이전 세대의 어떤 획과 일치하면
    ///    "같은 논리적 획의 변형" 으로 보고 **3번으로 넘긴다.** 유사도 임계값 대신 3번의 겹침이 그 역할을 한다.
    /// 3. 2번의 전제가 있는 획에 한해, 이전 세대 획과 공간적으로 가장 많이 겹치는 owner 승계.
    ///    `.vector` 지우개 전환이나 예외 상황용이다.
    /// 4. 그 밖(= **새 획**) → 첫 control point 의 `captureRect` 로 신규 귀속 (§7-1, U1).
    ///
    /// ### 3번을 2번의 전제 위에서만 적용하는 이유 (rev.19)
    /// 이전 구현은 identity 가 맞지 않는 모든 획에 3번을 4번보다 먼저 적용했다. 그런데 `.bitmap` 지우개는 1번이 전부 처리하므로
    /// 3번이 실제로 발동하는 것은 **새 획**뿐이었고, 새 획이 이웃 절 잉크의 `renderBounds` 와 겹치면(절 경계 근처의 긴 획 · 큰 글씨)
    /// 시작 절이 아니라 **이웃 절**에 귀속돼 reflow 때 그 절과 함께 움직였다 — U1("시작한 절에 속한다")의 위반이다.
    /// 새 획은 seed 도 creationTime 도 새것이라 2번의 전제가 없고, 곧바로 4번으로 간다.
    ///
    /// ### 2번의 유사도 판정을 생략한 근거
    /// - S1-4 실측(§19-2)에서 지우개 전후로 `randomSeed` / `creationDate` / `path.count` 는 물론
    ///   control point 10개의 값까지 전부 불변이었다. 즉 `.bitmap` 경로는 1번이 100% 처리한다.
    /// - 1번이 실패하는 경우는 키 구성요소 중 하나 이상이 실제로 달라진 경우인데,
    ///   그때 무엇을 "유사하다" 고 볼지에 대한 **실측 근거가 아직 없다.**
    ///   근거 없는 임계값(bounds 거리 몇 pt, path 유사도 몇 %)을 지어내면
    ///   조용히 오소유(mis-ownership)를 만드는 마법 상수가 된다.
    /// - 그 구간은 임계값 없이도 3번(겹침 면적 최대)이 덮는다. 3번은 파라미터가 없고 결정적이다.
    ///
    /// `.vector` 지우개를 도입하거나 1번이 실패하는 실제 사례를 측정하게 되면 그때 근거와 함께 넣는다.
    ///
    /// - Note: `previous.layoutSignature` 와 `layout.signature` 가 달라도(리플로우) **재판정하지 않는다.**
    ///         레이아웃 변경은 표시 변환일 뿐이라는 P10 과, 소유권은 승계한다는 P2 가 그 이유다.
    ///         결과 스냅샷의 signature 만 현재 레이아웃 것으로 갱신된다.
    /// - Parameters:
    ///   - previous: 편집 전 소유권.
    ///   - previousDrawing: 편집 전 drawing. 3번 규칙의 기하 비교 대상이다.
    ///   - drawing: 편집 후 drawing.
    ///   - layout: 현재 장 레이아웃.
    /// - Returns: 승계가 반영된 새 소유권 스냅샷.
    func reconcile(
        previous: OwnershipSnapshot,
        previousDrawing: PKDrawing,
        drawing: PKDrawing,
        layout: ChapterLayout
    ) -> OwnershipSnapshot {
        let previousGeometry = ownerGeometry(of: previousDrawing, ownership: previous)
        let previousIdentities = PartialIdentityIndex(previousDrawing)
        let groups = groupByIdentity(drawing)

        var resolved: [StrokeIdentityKey: Int] = [:]
        resolved.reserveCapacity(groups.count)
        for group in groups {
            if let inherited = previous.owner(of: group.key) {
                resolved[group.key] = inherited                                  // 규칙 1
            } else if previousIdentities.partiallyMatches(group.key),           // 규칙 2 의 전제
                      let overlapped = overlapOwner(of: group.strokes, in: previousGeometry) {
                resolved[group.key] = overlapped                                 // 규칙 3
            } else if let fresh = freshOwner(of: group.strokes, in: layout) {
                resolved[group.key] = fresh                                      // 규칙 4 (U1)
            }
            // 어느 규칙에도 걸리지 않으면(앵커가 캔버스 밖 등) map 에 넣지 않는다.
            // "조회 실패 = 소유자 없음" 이며, 0 같은 대체값을 만들지 않는다.
        }
        return OwnershipSnapshot(map: resolved, layoutSignature: layout.signature)
    }

    // MARK: - 내부 구현

    /// 이전 세대 획들의 `randomSeed` · `creationTime` 집합 — 규칙 2 의 전제("같은 논리적 획의 변형인가") 판정용.
    ///
    /// 여기서도 열거는 `drawing.strokes` 다 (§7-2). 새 획은 seed 도 creationTime 도 새것이라 어느 쪽에도 없다.
    private struct PartialIdentityIndex {
        private let seeds: Set<UInt32>
        private let creationTimes: Set<TimeInterval>

        init(_ drawing: PKDrawing) {
            var seeds: Set<UInt32> = []
            var creationTimes: Set<TimeInterval> = []
            for stroke in drawing.strokes {
                seeds.insert(stroke.randomSeed)
                creationTimes.insert(stroke.path.creationDate.timeIntervalSince1970)
            }
            self.seeds = seeds
            self.creationTimes = creationTimes
        }

        func partiallyMatches(_ key: StrokeIdentityKey) -> Bool {
            seeds.contains(key.randomSeed) || creationTimes.contains(key.creationTime)
        }
    }

    /// 같은 `StrokeIdentityKey` 를 공유하는 stroke 묶음.
    private struct IdentityGroup {
        let key: StrokeIdentityKey
        var strokes: [PKStroke]
    }

    /// `drawing.strokes` 를 순회해 identity 별로 묶는다.
    ///
    /// **열거는 언제나 `drawing.strokes` 다** (§7-2). bitmap 조각이 같은 키를 공유하므로
    /// 키 하나가 복수 stroke 를 갖는 것이 정상이며, 결과 배열의 순서는 첫 등장 순서로 고정된다.
    private func groupByIdentity(_ drawing: PKDrawing) -> [IdentityGroup] {
        var groups: [IdentityGroup] = []
        var indexByKey: [StrokeIdentityKey: Int] = [:]
        for stroke in drawing.strokes {
            let key = StrokeIdentityKey(stroke: stroke)
            if let index = indexByKey[key] {
                groups[index].strokes.append(stroke)
            } else {
                indexByKey[key] = groups.count
                groups.append(IdentityGroup(key: key, strokes: [stroke]))
            }
        }
        return groups
    }

    /// 이전 세대 stroke 의 캔버스 기하를 owner 별로 모은다.
    ///
    /// 여기서도 열거는 `drawing.strokes` 이고 `ownership.map` 은 조회에만 쓴다 (§7-2).
    /// `renderBounds` 는 transform 과 mask 가 반영된 **가시 영역**의 캔버스 좌표 사각형이므로
    /// 별도 변환 없이 그대로 비교할 수 있다.
    private func ownerGeometry(of drawing: PKDrawing, ownership: OwnershipSnapshot) -> [Int: [CGRect]] {
        var geometry: [Int: [CGRect]] = [:]
        for stroke in drawing.strokes {
            guard let owner = ownership.owner(of: stroke) else { continue }
            geometry[owner, default: []].append(stroke.renderBounds)
        }
        return geometry
    }

    /// 규칙 3 — 이전 세대 획과 가장 많이 겹치는 owner.
    ///
    /// 선택 기준은 **겹침 면적 최대**이고, 동점이면 **절 번호가 작은 쪽**이다.
    /// 후보를 절 번호 오름차순으로 훑으면서 면적이 **더 클 때만** 교체하므로
    /// Dictionary 순회 순서에 결과가 좌우되지 않는다 (설계 §7-3의 결정적 순서, §20-1의 재발 방지).
    ///
    /// - Note: 한 절 안에서 이전 획들이 서로 겹쳐 있으면 그 부분이 중복 합산된다.
    ///         fallback 휴리스틱이라 그대로 두며, 승자 판정을 뒤집을 만한 영향은 실사용 형태에서 나오지 않는다.
    private func overlapOwner(of strokes: [PKStroke], in geometry: [Int: [CGRect]]) -> Int? {
        guard !geometry.isEmpty, !strokes.isEmpty else { return nil }
        let candidateRects = strokes.map(\.renderBounds)
        var best: (verse: Int, area: CGFloat)?
        for verse in geometry.keys.sorted() {
            guard let rects = geometry[verse] else { continue }
            let area = overlapArea(candidateRects, rects)
            guard area > 0 else { continue }
            if let current = best {
                if area > current.area { best = (verse, area) }
            } else {
                best = (verse, area)
            }
        }
        return best?.verse
    }

    /// 규칙 4 — 첫 control point 로 신규 귀속.
    ///
    /// 한 identity 에 조각이 여럿이어도 조각들은 원본 path 를 그대로 공유하므로(S1-2)
    /// 앵커가 서로 같다. 그래도 앵커를 얻지 못하는 조각이 섞일 수 있으므로 먼저 성공하는 것을 쓴다.
    private func freshOwner(of strokes: [PKStroke], in layout: ChapterLayout) -> Int? {
        for stroke in strokes {
            if let verse = owner(of: stroke, in: layout) { return verse }
        }
        return nil
    }

    private func overlapArea(_ lhs: [CGRect], _ rhs: [CGRect]) -> CGFloat {
        var total: CGFloat = 0
        for left in lhs {
            for right in rhs {
                let intersection = left.intersection(right)
                guard !intersection.isNull, !intersection.isEmpty else { continue }
                total += intersection.width * intersection.height
            }
        }
        return total
    }
}
