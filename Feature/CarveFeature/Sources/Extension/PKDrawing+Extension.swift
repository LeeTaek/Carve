//
//  PKDrawing+Extension.swift
//  CarveFeature
//
//  Created by 이택성 on 11/4/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Foundation
import PencilKit

extension PKDrawing {
    func clipped(to rect: CGRect) -> PKDrawing {
        let filteredStrokes = self.strokes.filter { stroke in
            stroke.renderBounds.intersects(rect)
        }
        return PKDrawing(strokes: filteredStrokes)
    }
    
    /// verseRect 내부에 포함되는 stroke 부분만 남기는 정밀 clip
    func clippedPrecisely(to rect: CGRect) -> PKDrawing {
        let clippedStrokes = strokes.compactMap { $0.clippedPrecisely(to: rect) }
        return PKDrawing(strokes: clippedStrokes)
    }
}

public extension PKStroke {
    func clippedPrecisely(to rect: CGRect) -> PKStroke? {
        //  이 stroke가 rect와 전혀 겹치지 않으면 skip
        guard renderBounds.intersects(rect) else { return nil }

        // path 내부의 control point 중 rect 안에 들어가는 점만 추출
        let filteredPoints = path.map { $0 }.filter { rect.contains($0.location) }

        // 남은 점이 없으면 skip
        guard !filteredPoints.isEmpty else { return nil }

        // 새로운 PKStrokePath 구성
        let newPath = PKStrokePath(controlPoints: filteredPoints, creationDate: path.creationDate)

        // 기존 속성 그대로 복제
        return PKStroke(
            ink: ink,
            path: newPath,
            transform: transform,
            mask: mask
        )
    }
}
