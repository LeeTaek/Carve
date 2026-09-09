//
//  ChapterCanvasMenuSuppressionTesting.swift
//  CarveFeatureTest
//
//  R25 — 롱프레스 메뉴가 PencilKit 메뉴로 교체돼 오탭이 전 획 선택으로 이어지던 결함.
//  PencilKit 이 내부 타일 뷰에 붙이는 편집 메뉴를 걷어내는 것이 수정이라, 그 제거를 고정한다.
//

import CoreGraphics
import Foundation
import PencilKit
import Testing
import UIKit

@testable import CarveFeature

// MARK: - R25 — PencilKit 편집 메뉴가 우리 메뉴를 덮지 않는다

@Suite("R25 — 롱프레스 메뉴 교체 방지")
@MainActor
struct ChapterCanvasMenuSuppressionTesting {

    private func makeController() -> ChapterCanvasController {
        let controller = ChapterCanvasController()
        controller.view.frame = CGRect(x: 0, y: 0, width: 800, height: 1200)
        controller.loadViewIfNeeded()
        controller.view.layoutIfNeeded()
        return controller
    }

    @Test("캔버스 하위 뷰에 편집·컨텍스트 메뉴가 남지 않는다")
    func subviewsCarryNoEditMenu() {
        let controller = makeController()

        // 하위 뷰가 없으면 아래 루프가 돌지 않아 이 테스트가 공허해진다. PencilKit 은 타일 뷰를 만든다.
        #expect(!controller.canvas.subviews.isEmpty)

        for subview in controller.canvas.subviews {
            for interaction in subview.interactions {
                #expect(!(interaction is UIEditMenuInteraction))
                #expect(!(interaction is UIContextMenuInteraction))
            }
        }
    }

    @Test("하위 뷰에 편집 메뉴가 다시 붙어도 레이아웃에서 걷어낸다 — 양성 대조")
    func reAddedMenuIsRemovedAgain() {
        let controller = makeController()
        guard let subview = controller.canvas.subviews.first else {
            Issue.record("캔버스에 하위 뷰가 없다 — 제거 경로를 태울 수 없다")
            return
        }

        // PencilKit 이 타일 뷰를 다시 만들며 메뉴를 붙이는 상황을 흉내낸다.
        subview.addInteraction(UIEditMenuInteraction(delegate: nil))
        #expect(subview.interactions.contains { $0 is UIEditMenuInteraction })

        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        #expect(!subview.interactions.contains { $0 is UIEditMenuInteraction })
    }

    @Test("우리 메뉴는 캔버스 자신에 그대로 남는다")
    func ownEditMenuSurvivesOnCanvas() {
        let controller = makeController()

        let ownMenus = controller.canvas.interactions.filter { $0 is UIEditMenuInteraction }
        #expect(ownMenus.count == 1)
    }

    @Test("레이아웃이 다시 돌아도 하위 뷰에 메뉴가 되살아나지 않는다")
    func reappliedAfterLayout() {
        let controller = makeController()

        // PencilKit 이 타일 뷰를 다시 만들 수 있는 지점 — 폭이 바뀌는 회전을 흉내낸다.
        controller.view.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        controller.view.layoutIfNeeded()

        for subview in controller.canvas.subviews {
            for interaction in subview.interactions {
                #expect(!(interaction is UIEditMenuInteraction))
                #expect(!(interaction is UIContextMenuInteraction))
            }
        }
        #expect(controller.canvas.interactions.filter { $0 is UIEditMenuInteraction }.count == 1)
    }
}
