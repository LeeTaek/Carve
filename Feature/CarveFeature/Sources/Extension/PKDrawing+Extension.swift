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
    /// verseRect 내부에 포함되는 stroke 부분만 남기는 정밀 clip
    func clippedPrecisely(to rect: CGRect) -> PKDrawing {
        let clippedStrokes = strokes.compactMap { $0.clippedPrecisely(to: rect) }
        return PKDrawing(strokes: clippedStrokes)
    }
    
    /// 절대좌표계를 로컬좌표계로 정규화
    func normalizedForVerseRect(_ rect: CGRect, tolerance: CGFloat = 20) -> PKDrawing {
        guard let first = strokes.first else { return self }

        let bounds = first.renderBounds

        // 절대좌표로 저장된 경우: verseRect.minX/minY 근처에서 시작함
        let isAbsolute =
            abs(bounds.minX - rect.minX) < tolerance &&
            abs(bounds.minY - rect.minY) < tolerance

        if isAbsolute {
            // 절대 → 로컬 변환
            let toLocal = CGAffineTransform(
                translationX: -rect.minX,
                y: -rect.minY
            )
            return self.transformed(using: toLocal)
        } else {
            // 이미 로컬좌표
            return self
        }
    }

}

public extension PKStroke {
    /// 캔버스 좌표계 기준 Rect 안에 포함되는 Stroke만 만 남기는 Clip 
    func clippedPrecisely(to rect: CGRect) -> PKStroke? {
        //  이 stroke가 rect와 전혀 겹치지 않으면 skip
        guard renderBounds.intersects(rect) else { return nil }

        // rect(캔버스/global 좌표)를 stroke 로컬 좌표계로 변환
        // transform: local -> global 이므로, inverse 는 global -> local
        let inverseTransform = transform.inverted()
        let localRect = rect.applying(inverseTransform)
        
        // 로컬 좌표계 기준으로 rect 안에 들어오는 control point 만 추출
        let filteredPoints: [PKStrokePoint] = path.map { $0 }.filter { point in
            localRect.contains(point.location)
        }

        // 남은 점이 없으면 skip
        guard !filteredPoints.isEmpty else { return nil }

        // 새로운 PKStrokePath 구성 (좌표계는 여전히 로컬)
        let newPath = PKStrokePath(
            controlPoints: filteredPoints,
            creationDate: path.creationDate
        )

        // 기존 속성을 유지한 채 path 만 교체
        return PKStroke(
            ink: ink,
            path: newPath,
            transform: transform,
            mask: mask
        )
    }
}
