//
//  DrawingErasePersistenceTesting.swift
//  CarveFeatureTest
//
//  "지우개로 획을 전부 지운 뒤 재기동하면 지웠던 획이 되살아난다" 회귀 방지 테스트.
//
//  원인은 두 곳이 겹쳐 있었다.
//  1) 저장 가드가 `lineData?.containsPKStroke == true` 를 요구해, 마지막 획을 지운 순간 저장 자체를 건너뜀
//  2) `canvasViewDrawingDidChange` 의 leading-edge throttle 이 제스처의 마지막 변경을 버림
//
//  2.1 에서 N-Canvas(절마다 캔버스 · `persistDrawing`)를 지우며 그 경로의 시험도 함께 지웠다. 단일 Canvas 의 같은 계약
//  (빈 결과도 저장 명령이다 — P7)은 `ChapterCanvasFeatureTesting` · `DrawingCodecTesting` 이 본다. 여기에는 전제만 남는다.
//

@testable import CarveFeature
import CarveToolkit
import Foundation
import PencilKit
import Testing
import UIKit

@Suite("지우개로 전부 지운 결과의 영속화")
struct DrawingErasePersistenceTesting {

    // MARK: - 전제 확인

    @Test("획을 전부 지운 drawing 은 containsPKStroke == false 다 (예전 저장 가드가 막던 조건)")
    func fullyErasedDrawingHasNoStroke() {
        #expect(PKDrawing().dataRepresentation().containsPKStroke == false)
        #expect(PKDrawing(strokes: [Self.makeStroke()]).dataRepresentation().containsPKStroke == true)
    }

    // MARK: - 헬퍼

    private static func makeStroke() -> PKStroke {
        let points = (0..<8).map { index in
            PKStrokePoint(
                location: CGPoint(x: Double(index) * 10, y: 0),
                timeOffset: Double(index) * 0.02,
                size: CGSize(width: 4, height: 4),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        let path = PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 1_700_000_000))
        return PKStroke(ink: PKInk(.pencil, color: .black), path: path)
    }
}
